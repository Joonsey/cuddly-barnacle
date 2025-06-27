const std = @import("std");
const rl = @import("raylib");

const renderer = @import("renderer.zig");
const entity = @import("entity.zig");
const level = @import("level.zig");

const prefab = @import("prefabs.zig");
const Tracks = @import("tracks.zig").Tracks;
const Particles = @import("particles.zig").Particles;
const server = @import("server.zig");
const client = @import("clients.zig");
const util = @import("util.zig");
const shared = @import("shared.zig");
const settings = @import("settings.zig");

var WINDOW_WIDTH: i32 = 1540;
var WINDOW_HEIGHT: i32 = 860;
const RENDER_WIDTH = shared.RENDER_WIDTH;
const RENDER_HEIGHT = shared.RENDER_HEIGHT;

const Inventory = struct {
    item: ?prefab.Item,
    random: std.Random,

    player_id: entity.EntityId,

    allocator: std.mem.Allocator,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, seed: u64) Self {
        var rand = std.Random.DefaultPrng.init(seed);
        return .{
            .item = null,
            .allocator = allocator,
            .random = rand.random(),
            .player_id = 0,
        };
    }

    pub fn generate_item(self: *Self, eligible_items: []prefab.Item) void {
        if (self.item) |_| return;
        std.debug.assert(eligible_items.len > 0);
        // this randomly crashes, no idea why
        // const chosen = self.random.intRangeAtMost(usize, 0, eligible_items.len - 1);
        self.item = eligible_items[0];
    }

    pub fn draw(self: Self) void {
        if (self.item) |item| {
            prefab.get_item(item).drawEx(.init(0, 0), 0, 2, .white);
        }
    }

    pub fn set_player(self: *Self, new_player_id: entity.EntityId) void {
        self.player_id = new_player_id;
    }

    pub fn on_event(s: *anyopaque, ecs: *entity.ECS, event: entity.Event) void {
        const self: *Self = @alignCast(@ptrCast(s));
        switch (event) {
            .Collision => |col| {
                const a = ecs.get(col.a);
                const b = ecs.get(col.b);
                if (a.archetype == .ItemBox and col.b == self.player_id or b.archetype == .ItemBox and col.a == self.player_id) {
                    var eligible_items: std.ArrayListUnmanaged(prefab.Item) = .{};
                    // eligible_items.append(self.allocator, prefab.Item.boost) catch unreachable;
                    eligible_items.append(self.allocator, prefab.Item.missile) catch unreachable;
                    self.generate_item(eligible_items.items);
                    eligible_items.deinit(self.allocator);
                }
            },
            else => {},
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        return;
    }
};

const State = union(enum) {
    Playing: enum {
        offline,
        online,
    },
    Browsing,
    Lobby,
    Settings: struct {
        is_writing: bool = false,
        name_len: usize = 0,
    },
};

const Gamestate = struct {
    ecs: *entity.ECS,
    level: level.Level,
    camera: renderer.Camera,
    tracks: *Tracks,
    particles: *Particles,
    inventory: *Inventory,
    client: *client.GameClient,

    state: State,
    start_time: i64 = 0,

    selector: usize = 0,
    ready: bool = false,
    frame_count: u32 = 0,

    show_leaderboard: bool = false,

    name: [16]u8 = undefined,
    selected_prefab: prefab.Prefab = .car_base,

    server: ?server.GameServer = null,
    room: ?client.Room = null,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, lvl: level.Level) !Self {
        const tracks = try allocator.create(Tracks);
        tracks.* = try .init(allocator);

        const particles = try allocator.create(Particles);
        particles.* = .init(allocator);

        const inventory = try allocator.create(Inventory);
        inventory.* = .init(allocator, 2728989);

        const cli = try allocator.create(client.GameClient);
        cli.* = .init(allocator);

        const ecs = try allocator.create(entity.ECS);
        ecs.* = .init(allocator);

        ecs.register_observer(.{ .callback = &Particles.on_event, .context = particles });
        ecs.register_observer(.{ .callback = &Inventory.on_event, .context = inventory });
        ecs.register_observer(.{ .callback = &client.GameClient.on_event, .context = cli });

        return .{
            .ecs = ecs,
            .level = lvl,
            .camera = .init(RENDER_WIDTH, RENDER_HEIGHT),
            .tracks = tracks,
            .particles = particles,
            .inventory = inventory,
            .client = cli,

            .state = .{ .Settings = .{} },

            .allocator = allocator,
        };
    }

    fn draw_background(self: Self) void {
        _ = self;
        const size = 16;
        for (0..RENDER_WIDTH / size + 2) |u_x| {
            for (0..RENDER_HEIGHT / size + 1) |u_y| {
                const x: i32 = @intCast(u_x);
                const y: i32 = @intCast(u_y);
                const offset: i32 = @intFromFloat(@mod(rl.getTime() * size, size));
                const dark_gray = rl.Color.init(23, 23, 25, 255);
                const very_dark_gray = rl.Color.init(5, 3, 3, 255);

                rl.drawRectangle(x * size - offset, y * size - offset, size, size, if (@mod(x + y, 2) == 0) very_dark_gray else dark_gray);
            }
        }
    }

    pub fn spawn_player(self: *Self, spawn_index: usize) void {
        var tank = prefab.get(self.selected_prefab);
        tank.transform.?.position = self.level.finish.get_spawn(1 + spawn_index);
        tank.transform.?.rotation = self.level.finish.get_direction();
        tank.kinetic = .{ .velocity = .{ .x = 0, .y = 0 }, .traction = .Track };
        tank.controller = .{};
        tank.drift = .{};
        tank.boost = .{};
        tank.race_context = .{};
        tank.name_tag = .{ .name = self.name };
        const player_id = self.ecs.spawn(tank);
        self.client.player_map.put(self.allocator, self.client.ctx.own_player_id, player_id) catch unreachable;
        self.inventory.set_player(player_id);
    }

    fn determine_missile_target(self: *Self) shared.PlayerId {
        var iter = self.client.player_map.iterator();
        const self_player = self.ecs.get(self.inventory.player_id);
        // checking for player directly in front of the player
        const target = blk: {
            while (iter.next()) |player| {
                if (player.key_ptr.* == self.client.ctx.own_player_id) continue;

                const other_player_entity_id: entity.EntityId = @intCast(player.value_ptr.*);
                const other_player_entity = self.ecs.get(other_player_entity_id);
                if (other_player_entity.race_context) |other_rc| {
                    if (self_player.race_context) |own_rc| {
                        if (own_rc.checkpoint == other_rc.checkpoint) {
                            if (other_player_entity.transform) |other_transform| {
                                if (self_player.transform) |own_transform| {
                                    const to_other = other_transform.position.subtract(own_transform.position).normalize();
                                    const self_forward: rl.Vector2 = .init(std.math.cos(own_transform.rotation), std.math.sin(own_transform.rotation));

                                    const dot = self_forward.dotProduct(to_other);
                                    if (dot > 0) break :blk player.key_ptr.*;
                                }
                            }
                        }
                    }
                }
            }

            break :blk null;
        };

        if (target) |t| return t;

        for (1..self.level.checkpoints.len) |i| {
            iter.index = 0;
            while (iter.next()) |player| {
                if (player.key_ptr.* == self.client.ctx.own_player_id) continue;

                const other_player_entity_id: entity.EntityId = @intCast(player.value_ptr.*);
                const other_player_entity = self.ecs.get(other_player_entity_id);
                if (other_player_entity.race_context) |other_rc| {
                    if (self_player.race_context) |own_rc| {
                        if ((own_rc.checkpoint + i) % self.level.checkpoints.len == other_rc.checkpoint) {
                            return player.key_ptr.*;
                        }
                    }
                }
            }
        }

        return self.client.ctx.own_player_id;
    }

    pub fn use_item(self: *Self) void {
        if (self.inventory.item) |item| switch (item) {
            .boost => {
                if (self.ecs.get_mut(self.inventory.player_id).boost) |*boost| {
                    const turbo = entity.DriftStage.Turbo;
                    boost.boost_time = entity.DriftStage.get_boost_time(turbo);
                }
            },
            .missile => {
                const player = self.ecs.get(self.inventory.player_id);
                var pre = prefab.get(.missile);
                pre.race_context = player.race_context;
                pre.transform = player.transform;
                pre.kinetic = player.kinetic;
                pre.transform.?.height = 10;
                pre.kinetic.?.weight = 0;
                const target_player_id = self.determine_missile_target();
                pre.target = .{ .id = @intCast(target_player_id) };
                self.client.send_spawn_missile(pre);
                if (self.client.player_map.get(target_player_id)) |entity_id| pre.target.?.id = entity_id;
                _ = self.ecs.spawn(pre);
            },
        };

        self.inventory.item = null;
    }

    pub fn deinit(self: *Self) void {
        self.ecs.deinit();
        self.allocator.destroy(self.ecs);

        self.tracks.deinit();
        self.allocator.destroy(self.tracks);

        self.particles.deinit();
        self.allocator.destroy(self.particles);

        self.inventory.deinit();
        self.allocator.destroy(self.inventory);

        self.client.deinit();
        self.allocator.destroy(self.client);
        if (self.server) |*s| s.deinit();
    }

    pub fn reset(self: *Self) void {
        self.ecs.deinit();
        self.ecs.* = .init(self.allocator);

        // lifetime shold be maintained in ecs. via a .reset()
        self.ecs.register_observer(.{ .callback = &Particles.on_event, .context = self.particles });
        self.ecs.register_observer(.{ .callback = &Inventory.on_event, .context = self.inventory });
        self.ecs.register_observer(.{ .callback = &client.GameClient.on_event, .context = self.client });

        self.tracks.deinit();
        self.tracks.* = Tracks.init(self.allocator) catch unreachable;

        self.particles.deinit();
        self.particles.* = Particles.init(self.allocator);

        self.client.player_map.clearRetainingCapacity();
        self.client.ctx.players_who_have_completed.clearRetainingCapacity();
        self.client.is_finished = false;

        self.camera.rotation = 0;
        self.inventory.item = null;
    }

    fn change_state(self: *Self, new_state: State) void {
        if (std.meta.activeTag(self.state) == std.meta.activeTag(new_state)) return;

        switch (new_state) {
            .Lobby => {
                self.selector = 0;
                self.ready = false;
            },
            .Playing => |playing| {
                self.selector = 0;
                self.ready = false;
                self.reset();
                self.level.load_ecs(self.ecs);
                rl.playMusicStream(self.level.sound_track);
                switch (playing) {
                    .offline => {
                        self.spawn_player(0);
                    },
                    .online => {
                        for (0..self.client.ctx.ready_check.len) |i| {
                            const player = self.client.ctx.ready_check[i];
                            if (player.id == self.client.ctx.own_player_id) {
                                self.spawn_player(i);
                            }
                        }
                    },
                }
            },
            .Browsing => {
                self.selector = 0;
                self.ready = false;
                self.room = null;
                if (self.server) |*s| {
                    s.stop();
                    s.deinit();
                    self.server = null;
                }
            },
            .Settings => {
                self.selector = 0;
                self.ready = false;
            },
        }

        self.state = new_state;
    }

    fn has_started(self: Self) bool {
        return switch (self.state) {
            .Playing => self.start_time < std.time.milliTimestamp(),
            else => false,
        };
    }

    pub fn update(self: *Self, deltatime: f32) void {
        self.frame_count += 1;
        switch (self.state) {
            .Playing => |playing| {
                if (rl.isKeyPressed(.j)) self.use_item();

                // TODO
                // THIS MAY GET REALLOCATED ELSEWHERE!! UNSAFE TO USE
                const mut_player = self.ecs.get_mut(self.inventory.player_id);
                mut_player.controller = if (self.has_started()) .{} else null;

                const player = self.ecs.get(self.inventory.player_id);

                switch (playing) {
                    .online => {
                        self.client.send_player_update(player);
                        self.client.sync(self.ecs);

                        switch (self.client.ctx.server_state.state) {
                            .Lobby => self.change_state(.Lobby),
                            .Finishing => if (std.time.milliTimestamp() > self.client.ctx.server_state.ctx.time) self.change_state(.Lobby),
                            else => {},
                        }
                    },
                    .offline => {},
                }
                self.ecs.update(deltatime, self.level);
                self.level.update_intermediate_texture(self.camera);
                self.tracks.update(self.ecs);
                self.particles.update(deltatime, self.ecs.*);

                self.show_leaderboard = rl.isKeyDown(.tab);

                const transform = player.transform.?;
                self.camera.target(transform.position);
                const delta = transform.rotation + std.math.pi * 0.5 - self.camera.rotation;
                self.camera.rotation += delta / 120;
            },
            .Browsing => {
                if (self.frame_count % 140 == 0) self.client.update_rooms();
                self.client.ctx.lock.lockShared();
                const rooms = self.client.get_rooms();
                if (rl.isKeyPressed(.t) and rooms.len > 0) {
                    self.client.join_room(rooms[self.selector]);
                    self.change_state(.Lobby);
                }

                if (rl.isKeyPressed(.w)) self.selector = self.selector + 1 % rooms.len;
                if (rl.isKeyPressed(.s)) self.selector = self.selector - 1 % rooms.len;

                if (rl.isKeyPressed(.q)) {
                    self.server = .init(self.allocator);
                    if (self.server) |*s| {
                        s.start();
                        self.client.join(shared.LOCALHOST_IP, shared.SERVER_PORT);
                        self.change_state(.Lobby);
                    }
                }

                if (rl.isKeyPressed(.h)) {
                    self.change_state(.{ .Playing = .offline });
                    self.start_time = std.time.milliTimestamp();
                }
                self.client.ctx.lock.unlockShared();
            },
            .Lobby => {
                if (rl.isKeyPressed(.r)) self.ready = !self.ready;
                self.client.send_lobby_update(.{ .ready = self.ready, .name = self.name, .vote = self.selector });

                const levels = level.get_all();
                if (!self.ready) {
                    if (rl.isKeyPressed(.w)) self.selector = (self.selector + levels.len - 1) % levels.len;
                    if (rl.isKeyPressed(.s)) self.selector = (self.selector + 1) % levels.len;
                }

                const server_state = self.client.ctx.server_state;
                switch (server_state.state) {
                    .Starting => {
                        var votes: [level.NUM_LEVELS]usize = std.mem.zeroes([level.NUM_LEVELS]usize);
                        for (self.client.ctx.ready_check[0..self.client.ctx.num_players]) |rc| {
                            votes[rc.update.vote] += 1;
                        }

                        var highest: usize = 0;
                        var highest_level: usize = 0;
                        for (votes, 0..) |vote, current_level| {
                            if (vote > highest) {
                                highest = vote;
                                highest_level = current_level;
                            }
                        }

                        self.level = level.get(highest_level);
                    },
                    .Playing => {
                        self.change_state(.{ .Playing = .online });
                        self.start_time = server_state.ctx.time + std.time.ms_per_s * shared.TIME_TO_START_RACING_S;
                    },
                    else => {},
                }

                self.show_leaderboard = rl.isKeyDown(.tab);
            },
            .Settings => |*state| {
                var user_settings_copy = settings.get();
                defer settings.update(user_settings_copy);
                if (state.is_writing) {
                    const key = rl.getCharPressed();
                    if (key >= 32 and key <= 127 and state.name_len < user_settings_copy.player_name.len) {
                        user_settings_copy.player_name[state.name_len] = @intCast(key);
                        state.name_len += 1;
                    }

                    if (rl.isKeyPressed(.enter)) state.is_writing = false;
                    if (rl.isKeyPressed(.backspace)) {
                        user_settings_copy.player_name[state.name_len] = 0;
                        if (state.name_len > 0) state.name_len -= 1;
                    }
                } else {
                    const amount_of_user_settings = 2;
                    if (rl.isKeyPressed(.w)) self.selector = (self.selector + amount_of_user_settings - 1) % amount_of_user_settings;
                    if (rl.isKeyPressed(.s)) self.selector = (self.selector + 1) % amount_of_user_settings;

                    if (self.selector == 0) {
                        const change: f32 = if (rl.isKeyDown(.left_shift)) 0.01 else 0.05;
                        if (rl.isKeyPressed(.a)) user_settings_copy.volume = @max(user_settings_copy.volume - change, 0);
                        if (rl.isKeyPressed(.d)) user_settings_copy.volume = @min(user_settings_copy.volume + change, 1);
                    } else if (self.selector == 1) {
                        if (rl.isKeyPressed(.e)) {
                            state.is_writing = true;
                            state.name_len = 0;
                            @memset(&user_settings_copy.player_name, 0);
                        }
                        if (rl.isKeyPressed(.d)) user_settings_copy.volume = @min(user_settings_copy.volume + (1 / 20), 1);
                    }

                    if (rl.isKeyPressed(.q)) {
                        user_settings_copy.save(self.allocator) catch |err| std.log.err("couldnt save settings! {}", .{err});
                        rl.setMasterVolume(settings.get().volume);
                        self.change_state(.Browsing);
                    }
                }
            },
        }
    }

    fn draw_leaderboard(self: Self, start_x: i32) void {
        for (self.client.ctx.players_who_have_completed.items, 1..) |finish, i| {
            const finish_time_f: f32 = @floatFromInt(finish.time - self.start_time);
            const font_size = 10;
            const maybe_entity_id = self.client.player_map.get(finish.id);
            const name = blk: {
                if (finish.id == self.client.ctx.own_player_id) break :blk self.name;
                if (maybe_entity_id) |entity_id| if (self.ecs.get(entity_id).name_tag) |tag| break :blk tag.name;
                break :blk util.to_fixed("????", 16);
            };
            const text = rl.textFormat("%16.16s %.1f", .{ &name, finish_time_f / 1000 });

            const i_i: i32 = @intCast(i);
            const texture = prefab.get_ui(prefab.UI.get_placement(i));
            const delta_time = std.time.milliTimestamp() - finish.time;
            if (delta_time >= shared.LEADERBOARD_ENTER_TIME_MS) {
                texture.draw(start_x, texture.height * i_i, .white);
                rl.drawText(text, start_x + 16, texture.height * i_i + 1, font_size, .white);
            } else {
                const delta_time_f: f32 = @floatFromInt(delta_time);
                const lerped_x_f: f32 = std.math.lerp(@as(f32, @floatFromInt(RENDER_WIDTH)), @as(f32, @floatFromInt(start_x)), delta_time_f / shared.LEADERBOARD_ENTER_TIME_MS);
                const lerped_x: i32 = @intFromFloat(lerped_x_f);
                texture.draw(lerped_x, texture.height * i_i, .white);
                rl.drawText(text, lerped_x + 16, texture.height * i_i + 1, font_size, .white);
            }
        }
    }

    fn determine_level(self: Self) level.Level {
        return self.level;
    }

    pub fn draw(self: Self) void {
        switch (self.state) {
            .Playing => |playing| {
                self.level.draw(self.camera);
                self.tracks.draw(self.camera);
                self.particles.draw(self.camera);
                self.ecs.draw(self.camera);

                if (self.has_started()) {
                    self.inventory.draw();
                    rl.updateMusicStream(self.level.sound_track);
                } else {
                    const delta = self.start_time - std.time.milliTimestamp();
                    const delta_seconds: f32 = @as(f32, @floatFromInt(delta)) / 1000;
                    rl.drawText(rl.textFormat("%.1f", .{delta_seconds}), 102, 102, 30, .black);
                    rl.drawText(rl.textFormat("%.1f", .{delta_seconds}), 100, 100, 30, .white);
                }

                if (self.client.is_finished or self.show_leaderboard) {
                    self.draw_leaderboard(RENDER_WIDTH / 2 - 64);
                } else {
                    const player = self.ecs.get(self.inventory.player_id);
                    const lap = player.race_context.?.lap + 1;

                    const text = rl.textFormat("%d/%d", .{ lap, shared.MAX_LAPS });
                    const text_width = rl.measureText(text, 30);
                    rl.drawText(text, RENDER_WIDTH - text_width + 2, 2, 30, .black);
                    rl.drawText(text, RENDER_WIDTH - text_width, 0, 30, .white);
                }

                if (playing == .online) {
                    if (self.client.ctx.server_state.state == .Finishing) {
                        const time_to_end = self.client.ctx.server_state.ctx.time - std.time.milliTimestamp();
                        const time_to_end_f: f32 = @floatFromInt(time_to_end);

                        const font_size = 10;
                        const text = rl.textFormat("%.2f until we are going back", .{time_to_end_f / 1000});
                        const text_width = rl.measureText(text, font_size);

                        rl.drawText(text, RENDER_WIDTH - text_width + 1, 1 + RENDER_HEIGHT - font_size, font_size, .black);
                        rl.drawText(text, RENDER_WIDTH - text_width, RENDER_HEIGHT - font_size, font_size, .white);
                    }
                }
            },
            .Browsing => {
                self.draw_background();
                self.client.ctx.lock.lockShared();
                const rooms = self.client.get_rooms();
                for (0..rooms.len) |i| {
                    const room = rooms[i];
                    rl.drawText(rl.textFormat("%6.6s %d/%d", .{ &room.name, room.users, room.capacity }), 100, 32 + 20 * @as(i32, @intCast(i)), 10, if (self.selector == i) .yellow else .white);
                }
                self.client.ctx.lock.unlockShared();
            },
            .Lobby => {
                self.draw_background();
                self.client.ctx.lock.lockShared();
                const ready_status = self.client.ctx.ready_check[0..self.client.ctx.num_players];
                for (0..shared.MAX_PLAYERS) |i| {
                    if (i < ready_status.len) {
                        const status = ready_status[i];
                        const ready = if (status.id == self.client.ctx.own_player_id) self.ready else status.update.ready;
                        const texture = if (ready) prefab.get_ui(.ready) else prefab.get_ui(.notready);
                        const pos_x: i32 = 20;
                        const pos_y: i32 = 1 + 20 * @as(i32, @intCast(i));
                        if (ready) level.get(status.update.vote).icon.draw(pos_x, pos_y, .white);
                        texture.draw(pos_x, pos_y, .white);

                        var name = status.update.name;
                        rl.drawText(rl.textFormat("%.16s", .{&name}), 20 + 16, 1 + 3 + 20 * @as(i32, @intCast(i)), 10, .white);
                    } else {
                        const texture = prefab.get_ui(.unoccupied);
                        texture.draw(20, 1 + 20 * @as(i32, @intCast(i)), .white);
                    }
                }

                const server_state = self.client.ctx.server_state;
                if (server_state.state == .Starting) {
                    const time_left = server_state.ctx.time - std.time.milliTimestamp();
                    const time_left_f: f32 = @floatFromInt(time_left);
                    rl.drawText(rl.textFormat("starting in %.1fs", .{time_left_f / 1000}), RENDER_WIDTH / 2 + 20, RENDER_HEIGHT - 10, 10, .white);
                }

                const levels = level.get_all();
                for (levels, 0..) |lvl, i| {
                    const pos_x: i32 = RENDER_WIDTH / 2 + 50;
                    const pos_y: i32 = @intCast(16 * i);
                    lvl.icon.draw(pos_x, pos_y, .white);
                    if (i == self.selector) prefab.get_ui(.selected).draw(pos_x, pos_y, .white);
                }

                self.client.ctx.lock.unlockShared();

                if (self.show_leaderboard) self.draw_leaderboard(RENDER_WIDTH / 2 - 64);

                prefab.get(self.selected_prefab).renderable.?.Stacked.draw_raw(.init(RENDER_WIDTH - 30, RENDER_HEIGHT - 30), @floatCast(rl.getTime()));
            },
            .Settings => |state| {
                self.draw_background();

                const current_settings = settings.get();
                const font_size = 10;
                rl.drawText(rl.textFormat("volume: %.2f", .{current_settings.volume}), 0, 0 * font_size, font_size, if (self.selector == 0) .yellow else .white);
                rl.drawText(rl.textFormat(if (state.is_writing) "name: %s_" else "name: %s", .{&current_settings.player_name}), 0, 1 * font_size, font_size, if (self.selector == 1) .yellow else .white);

                {
                    const text = rl.textFormat("'q' to save and go back to main menu", .{});
                    const text_size = rl.measureText(text, font_size);
                    rl.drawText(text, shared.RENDER_WIDTH - text_size, shared.RENDER_HEIGHT - font_size, font_size, .ray_white);
                }
                if (self.selector == 0) {
                    const text = rl.textFormat("'a' and 'd' to adjust volume", .{});
                    const text_size = rl.measureText(text, font_size);
                    rl.drawText(text, shared.RENDER_WIDTH - text_size, shared.RENDER_HEIGHT - font_size * 2, font_size, .ray_white);
                }
                if (self.selector == 1) {
                    const text = rl.textFormat("'e' change name 'enter' to confirm", .{});
                    const text_size = rl.measureText(text, font_size);
                    rl.drawText(text, shared.RENDER_WIDTH - text_size, shared.RENDER_HEIGHT - font_size * 2, font_size, .ray_white);
                }
            },
        }
    }
};

pub fn main() !void {
    rl.setTraceLogLevel(.err);
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "ZKR");
    defer rl.closeWindow();
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    var DBA = std.heap.DebugAllocator(.{}){};
    defer switch (DBA.deinit()) {
        .leak => {
            std.log.err("memory leaks detected!", .{});
        },
        .ok => {},
    };
    const allocator = DBA.allocator();
    try prefab.init(allocator);
    defer prefab.deinit(allocator);

    try settings.init(allocator);
    defer settings.deinit(allocator);

    try level.init(allocator);
    defer level.deinit(allocator);

    var state: Gamestate = try .init(allocator, level.get(1));
    defer state.deinit();

    const user_settings = settings.get();
    state.client.ctx.own_player_id = user_settings.player_id; // network id, not entity id
    state.name = user_settings.player_name;
    rl.setMasterVolume(user_settings.volume);

    state.client.start();
    state.client.update_rooms();

    const scene = try rl.loadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT);

    rl.setTargetFPS(144);
    while (!rl.windowShouldClose()) {
        const deltatime = rl.getFrameTime();
        state.update(deltatime);

        scene.begin();
        rl.clearBackground(.black);
        state.draw();

        scene.end();

        // drawing scene at desired resolution
        rl.beginDrawing();
        rl.drawTexturePro(scene.texture, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(RENDER_WIDTH),
            .height = @floatFromInt(-RENDER_HEIGHT),
        }, .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(WINDOW_WIDTH),
            .height = @floatFromInt(WINDOW_HEIGHT),
        }, rl.Vector2.zero(), 0, .white);
        rl.drawFPS(0, 0);
        rl.endDrawing();
    }
}
