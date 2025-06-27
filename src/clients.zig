const std = @import("std");
const udptp = @import("udptp");
const rl = @import("raylib");

const shared = @import("shared.zig");
const entity = @import("entity.zig");
const prefab = @import("prefabs.zig");

pub const Room = shared.Room;

const GameClientContext = struct {
    num_players: usize = 0,
    updates: [shared.MAX_PLAYERS]shared.SyncPacket,
    ready_check: [shared.MAX_PLAYERS]shared.LobbySync,

    server_state: shared.ServerState,

    own_player_id: shared.PlayerId = 0,

    rooms: std.ArrayListUnmanaged(shared.Room),
    players_who_have_completed: std.ArrayListUnmanaged(shared.Finish) = .{},

    lock: std.Thread.RwLock,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .updates = undefined,
            .ready_check = undefined,
            .server_state = .{ .state = .Lobby, .ctx = .{ .time = 0 } },
            .rooms = .{},
            .lock = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.rooms.deinit(self.allocator);
    }
};

const GameClientType = udptp.Client(GameClientContext);

fn handle_packet(self: *GameClientType, data: []const u8, sender: udptp.network.EndPoint) udptp.PacketError!void {
    const ctx = self.ctx;
    const packet: shared.Packet = try .deserialize(data, ctx.allocator);
    defer packet.free(ctx.allocator);
    _ = sender;

    switch (packet.header.packet_type) {
        .sync => {
            const size = @sizeOf(shared.SyncPacket);
            const count: usize = packet.payload.len / size;
            ctx.num_players = count;

            ctx.lock.lockShared();
            for (0..count) |i| {
                ctx.updates[i] = try udptp.deserialize_payload(packet.payload[i * size .. size * (1 + i)], shared.SyncPacket);
            }
            ctx.lock.unlockShared();
        },
        .lobby_sync => {
            const size = @sizeOf(shared.LobbySync);
            const count: usize = packet.payload.len / size;
            ctx.num_players = count;

            ctx.lock.lockShared();
            for (0..count) |i| {
                ctx.ready_check[i] = try udptp.deserialize_payload(packet.payload[i * size .. size * (1 + i)], shared.LobbySync);
            }
            ctx.lock.unlockShared();
        },
        .ret_host_list => {
            const payload_individual_size = @sizeOf(shared.Room);
            const c = packet.header.payload_size / payload_individual_size;

            // potential memory desync here
            ctx.lock.lockShared();
            self.ctx.rooms.clearRetainingCapacity();
            for (0..c) |i| {
                const room = try udptp.deserialize_payload(packet.payload[i * payload_individual_size .. (i + 1) * payload_individual_size], shared.Room);
                try self.ctx.rooms.append(self.allocator, room);
            }
            ctx.lock.unlockShared();
        },
        .ack => {
            var buffer: [512]u8 = undefined;
            const response_packet = try shared.Packet.init(.ack, try udptp.serialize_payload(&buffer, shared.AckPacket{ .id = ctx.own_player_id }));
            const response_data = try response_packet.serialize(self.allocator);
            defer self.allocator.free(response_data);

            self.send(response_data);
        },
        .server_state_changed => {
            self.ctx.server_state = try udptp.deserialize_payload(packet.payload, shared.ServerState);
        },
        .finished => {
            const finish = try udptp.deserialize_payload(packet.payload, shared.Finish);
            if (finish.id != ctx.own_player_id) try self.ctx.players_who_have_completed.append(self.allocator, finish);
        },
        else => {},
    }
}

pub const GameClient = struct {
    client: GameClientType,
    ctx: *GameClientContext,

    player_map: std.AutoHashMapUnmanaged(shared.PlayerId, entity.EntityId),

    is_finished: bool = false,

    client_thread: std.Thread,
    should_quit: bool = false,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        const ctx = allocator.create(GameClientContext) catch unreachable;
        ctx.* = GameClientContext.init(allocator);
        var client = GameClientType.init(allocator, ctx) catch unreachable;
        client.handle_packet_cb = handle_packet;
        return .{
            .client = client,
            .allocator = allocator,
            .ctx = ctx,

            .player_map = .{},

            .client_thread = undefined,
        };
    }

    pub fn on_event(s: *anyopaque, ecs: *entity.ECS, event: entity.Event) void {
        const self: *Self = @alignCast(@ptrCast(s));
        _ = ecs;
        switch (event) {
            .Finish => |finish_event| {
                if (self.player_map.get(self.ctx.own_player_id)) |self_player| {
                    if (self_player == finish_event.entity) {
                        const finish: shared.Finish = .{ .id = self.ctx.own_player_id, .time = std.time.milliTimestamp() };
                        self.ctx.players_who_have_completed.append(self.allocator, finish) catch unreachable;
                        self.is_finished = true;

                        var buffer: [512]u8 = undefined;
                        const packet = shared.Packet.init(.finished, udptp.serialize_payload(&buffer, finish) catch unreachable) catch unreachable;
                        const data = packet.serialize(self.allocator) catch unreachable;
                        defer self.allocator.free(data);

                        self.client.send(data);
                    }
                }
            },
            else => {},
        }
    }

    fn listen(self: *Self) void {
        while (!self.should_quit) {
            self.client.listen() catch |err| switch (err) {
                error.WouldBlock => continue,
                else => {
                    std.log.err("client.listen failed with error {}", .{err});
                    // TODO send disconnect packet??
                    self.should_quit = true;
                },
            };
        }
    }

    pub fn disconnect(self: *Self) void {
        self.should_quit = true;
        std.log.debug("disconnecting from server...", .{});
        self.client_thread.join();
        std.log.debug("disconnected", .{});
    }

    pub fn deinit(self: *Self) void {
        if (!self.should_quit) self.disconnect();
        self.ctx.deinit();
        self.allocator.destroy(self.ctx);
        self.client.deinit();
        self.player_map.deinit(self.allocator);
    }

    pub fn send_lobby_update(self: *Self, status: shared.LobbyUpdate) void {
        var buffer: [1024]u8 = undefined;
        const packet = shared.Packet.init(.lobby_update, udptp.serialize_payload(&buffer, status) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;

        self.client.send(data);
        defer self.allocator.free(data);
    }

    pub fn update_rooms(self: *Self) void {
        var buffer: [512]u8 = undefined;
        const packet = shared.Packet.init(.req_host_list, udptp.serialize_payload(&buffer, shared.RequestRooms{ .scope = shared.SCOPE }) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        self.send_mm(data);
        self.allocator.free(data);
    }

    fn send_mm(self: *Self, data: []const u8) void {
        self.client.sendto(shared.MatchmakingEndpoint, data);
    }

    pub fn join_room(self: *Self, room: shared.Room) void {
        var buffer: [512]u8 = undefined;
        const mm_packet = shared.Packet.init(.join, udptp.serialize_payload(&buffer, shared.JoinPayload{ .scope = shared.SCOPE, .key = room.name }) catch unreachable) catch unreachable;
        const mm_data = mm_packet.serialize(self.allocator) catch unreachable;
        defer self.allocator.free(mm_data);

        self.send_mm(mm_data);
        self.join(room.ip, room.port);
    }

    pub fn join(self: *Self, ip: [4]u8, port: u16) void {
        var buffer: [512]u8 = undefined;
        const packet = shared.Packet.init(.ack, udptp.serialize_payload(&buffer, shared.AckPacket{ .id = self.ctx.own_player_id }) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        defer self.allocator.free(data);

        self.client.target = .{ .address = .{ .ipv4 = .{ .value = ip } }, .port = port };
        self.client.send(data);
    }

    pub fn get_rooms(self: Self) []shared.Room {
        return self.ctx.rooms.items;
    }

    pub fn sync(self: *Self, ecs: *entity.ECS) void {
        const updates = self.ctx.updates[0..self.ctx.num_players];
        for (updates) |update| {
            if (update.id == self.ctx.own_player_id) continue;

            // bandaid fix
            if (update.id == 0) continue;
            if (update.update.prefab != .car_base) continue;

            if (self.player_map.get(update.id)) |entity_id| {
                const entity_to_sync = ecs.get_mut(entity_id);
                entity_to_sync.transform = update.update.transform;
                entity_to_sync.kinetic = update.update.kinetic;
                entity_to_sync.race_context = update.update.race_context;
                entity_to_sync.drift = update.update.drift;
                entity_to_sync.boost = update.update.boost;
                entity_to_sync.name_tag = update.update.name_tag;
            } else {
                var pre = prefab.get(update.update.prefab);
                pre.transform = update.update.transform;
                pre.kinetic = update.update.kinetic;
                pre.race_context = update.update.race_context;
                pre.drift = update.update.drift;
                pre.boost = update.update.boost;
                pre.name_tag = update.update.name_tag;
                const entity_id = ecs.spawn(pre);
                self.player_map.put(self.allocator, update.id, entity_id) catch unreachable;
            }
        }
    }

    pub fn send_player_update(self: *Self, player: entity.Entity) void {
        var buffer: [1024]u8 = undefined;
        const update: shared.UpdatePacket = .{
            .kinetic = player.kinetic.?,
            .race_context = player.race_context.?,
            .transform = player.transform.?,
            .prefab = player.prefab.?,
            .boost = player.boost.?,
            .drift = player.drift.?,
            .name_tag = player.name_tag.?,
        };
        const packet = shared.Packet.init(.update, udptp.serialize_payload(&buffer, update) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        defer self.allocator.free(data);

        self.client.send(data);
    }

    pub fn start(self: *Self) void {
        self.client.socket.setReadTimeout(1000) catch unreachable;
        self.client_thread = std.Thread.spawn(.{}, Self.listen, .{self}) catch unreachable;
    }
};
