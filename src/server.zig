const std = @import("std");
const udptp = @import("udptp");
const rl = @import("raylib");

const shared = @import("shared.zig");
const to_fixed = @import("util.zig").to_fixed;

const Player = struct {
    id: u32,
    index: usize,
};

const GameServerContext = struct {
    num_players: usize,
    players: std.AutoHashMapUnmanaged(udptp.network.EndPoint, Player),
    updates: [shared.MAX_PLAYERS]shared.SyncPacket,
    ready_check: [shared.MAX_PLAYERS]shared.LobbySync,
    finished: [shared.MAX_PLAYERS]shared.Finish,
    state: shared.ServerState,
    update_count: u32 = 0,
    finished_count: u32 = 0,

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .num_players = 0,
            .players = .{},
            .updates = std.mem.zeroes([shared.MAX_PLAYERS]shared.SyncPacket),
            .ready_check = std.mem.zeroes([shared.MAX_PLAYERS]shared.LobbySync),
            .finished = std.mem.zeroes([shared.MAX_PLAYERS]shared.Finish),
            .state = .{ .state = .Lobby, .ctx = .{ .time = 0 } },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.players.clearAndFree(self.allocator);
    }
};

const GameServerType = udptp.Server(GameServerContext);

pub fn cleanup_dead_clients(self: *GameServer) void {
    const server = self.server;
    var iter = server.clients.iterator();
    const now = std.time.microTimestamp();
    while (iter.next()) |entry| {
        const client = entry.key_ptr;
        const timestamp = entry.value_ptr;
        const delta = now - timestamp.*;

        if (delta > std.time.us_per_s * 5) {
            if (self.ctx.players.fetchRemove(client.*)) |key_value| {
                const player = key_value.value;
                var _iter = self.ctx.players.valueIterator();
                while (_iter.next()) |value| {
                    if (value.index > player.index) {
                        value.index -= 1;
                    }
                }

                for (player.index..shared.MAX_PLAYERS - 1) |i| {
                    self.ctx.ready_check[i] = self.ctx.ready_check[i + 1];
                    self.ctx.updates[i] = self.ctx.updates[i + 1];
                }

                self.ctx.num_players -= 1;

                std.log.debug("id: {d} idx: {d} timed out", .{ key_value.value.id, key_value.value.index });
            }
        }
    }
}

pub fn handle_packet_cb(self: *GameServerType, data: []const u8, sender: udptp.network.EndPoint) udptp.PacketError!void {
    const ctx = self.ctx;
    const packet: shared.Packet = try .deserialize(data, ctx.allocator);
    defer packet.free(ctx.allocator);

    switch (packet.header.packet_type) {
        .sync => {},
        .ack => {
            const payload = try udptp.deserialize_payload(packet.payload, shared.AckPacket);
            std.log.debug("{d} has asked to connect", .{payload.id});
            if (ctx.players.size >= 12) {
                std.log.warn("{d} got rejected, because server is full", .{payload.id});
            } else {
                var iter = ctx.players.iterator();
                var exists = false;
                while (iter.next()) |player| {
                    if (player.value_ptr.id == payload.id) {
                        std.log.warn("{d} got rejected, because duplicate id", .{payload.id});
                        exists = true;
                    }
                }
                if (!exists) {
                    ctx.players.put(ctx.allocator, sender, .{ .id = payload.id, .index = ctx.num_players }) catch unreachable;
                    ctx.num_players += 1;
                }
            }
        },
        .update => {
            if (ctx.players.get(sender)) |player| {
                const payload = try udptp.deserialize_payload(packet.payload, shared.UpdatePacket);
                ctx.updates[player.index] = .{ .id = player.id, .update = payload };
            }
        },
        .review_request => {
            const payload = try udptp.deserialize_payload(packet.payload, shared.ReviewResponsePayload);
            const response_packet = shared.Packet.init(.ack, "zigkartracing") catch unreachable;
            const response_data = response_packet.serialize(ctx.allocator) catch unreachable;
            defer self.allocator.free(response_data);
            self.send_to(.{ .address = .{ .ipv4 = .{ .value = payload.join_request.ip } }, .port = payload.join_request.port }, response_data);
        },
        .lobby_update => {
            if (ctx.players.get(sender)) |player| {
                const payload = try udptp.deserialize_payload(packet.payload, shared.LobbyUpdate);
                ctx.ready_check[player.index] = .{ .id = player.id, .update = payload };
            }
        },
        .finished => {
            if (self.ctx.state.state == .Playing or self.ctx.state.state == .Finishing) {
                var iter = ctx.players.iterator();
                while (iter.next()) |player| {
                    self.send_to(player.key_ptr.*, data);
                }

                self.ctx.finished[self.ctx.finished_count] = try udptp.deserialize_payload(packet.payload, shared.Finish);
                self.ctx.finished_count += 1;
            }
        },
        .spawn_missile => {
            if (self.ctx.state.state == .Playing or self.ctx.state.state == .Finishing) {
                var iter = ctx.players.iterator();
                while (iter.next()) |player| {
                    self.send_to(player.key_ptr.*, data);
                }
            }
        },
        .req_server_state_sync => {
            var buffer: [1024]u8 = undefined;
            const return_packet = shared.Packet.init(.server_state_changed, udptp.serialize_payload(&buffer, self.ctx.state) catch unreachable) catch unreachable;

            const return_data = return_packet.serialize(self.allocator) catch unreachable;
            self.send_to(sender, return_data);
            defer self.allocator.free(return_data);
        },
        else => {},
    }

    return;
}

pub const GameServer = struct {
    server: GameServerType,
    ctx: *GameServerContext,

    server_thread: std.Thread,
    should_quit: bool = false,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        const ctx = allocator.create(GameServerContext) catch unreachable;
        ctx.* = GameServerContext.init(allocator);
        var server = GameServerType.init(shared.SERVER_PORT, allocator, ctx) catch unreachable;
        server.handle_packet_cb = handle_packet_cb;
        return .{
            .server = server,
            .allocator = allocator,
            .ctx = ctx,
            .server_thread = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        if (!self.should_quit) self.stop();
        self.ctx.deinit();
        self.allocator.destroy(self.ctx);
        self.server.deinit();
    }

    fn broadcast(self: *Self, data: []const u8) void {
        var iter = self.ctx.players.iterator();
        while (iter.next()) |player| {
            self.server.send_to(player.key_ptr.*, data);
        }
    }

    fn sync_players(self: *Self) void {
        // first sync packets may be - out of sync, as they havent been 'updated' yet.
        // although I don't really think this is an issue?
        //
        // sync players may want to send time-sensetive information (such as prefab) at times where we are prone for disconnect
        // only sharing update Sync packets during game, at which point new .ack packets are dissallowed, maybe?
        var buffer: [1024]u8 = undefined;
        const packet = shared.Packet.init(.sync, udptp.serialize_payload(&buffer, self.ctx.updates[0..self.ctx.num_players]) catch unreachable) catch unreachable;

        const data = packet.serialize(self.allocator) catch unreachable;
        self.broadcast(data);
        defer self.allocator.free(data);
    }

    fn matchmaking_keepalive(self: *Self) void {
        const packet = shared.Packet.init(.keepalive, "peep") catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        self.send_mm(data);
        self.allocator.free(data);
    }

    fn update_state(self: *Self) void {
        const previous_state = self.ctx.state.state;
        const timestamp = std.time.milliTimestamp();

        var number_of_ready_players: usize = 0;
        for (self.ctx.ready_check[0..self.ctx.num_players]) |ready| {
            if (ready.update.ready) number_of_ready_players += 1;
        }

        switch (self.ctx.state.state) {
            .Lobby => {
                if (self.ctx.num_players == number_of_ready_players and self.ctx.num_players >= shared.MIN_PLAYERS) {
                    self.ctx.state.state = .Starting;
                    self.ctx.state.ctx.time = timestamp + std.time.ms_per_s * shared.TIME_TO_START_ALL_READY_S;
                }
            },
            .Playing => {
                if (self.ctx.finished_count >= 1) {
                    self.ctx.state.state = .Finishing;
                    self.ctx.state.ctx.time = timestamp + std.time.ms_per_s * shared.TIME_TO_FINISH_S;

                    self.ctx.finished_count = 0;
                }
            },
            .Starting => {
                if (self.ctx.num_players != number_of_ready_players or self.ctx.num_players < shared.MIN_PLAYERS) {
                    self.ctx.state.state = .Lobby;
                } else if (timestamp >= self.ctx.state.ctx.time) {
                    self.ctx.state.state = .Playing;
                }
            },
            .Finishing => {
                if (timestamp >= self.ctx.state.ctx.time) {
                    self.ctx.state.state = .Lobby;
                    self.ctx.finished_count = 0;
                    for (0..self.ctx.ready_check.len) |i| {
                        self.ctx.ready_check[i].update.ready = false;
                    }
                }
            },
        }

        if (previous_state == self.ctx.state.state) return;
        switch (self.ctx.state.state) {
            .Lobby => self.alert_host("GAME2"),
            .Finishing => self.ctx.state.ctx.time = std.time.milliTimestamp() + std.time.ms_per_s * shared.TIME_TO_FINISH_S,
            .Playing, .Starting => {},
        }

        var buffer: [1024]u8 = undefined;

        const packet = shared.Packet.init(.server_state_changed, udptp.serialize_payload(&buffer, self.ctx.state) catch unreachable) catch unreachable;

        const data = packet.serialize(self.allocator) catch unreachable;
        self.broadcast(data);
        defer self.allocator.free(data);

        std.log.debug("SERVER state changed to: {any}", .{self.ctx.state.state});
    }

    fn sync_lobby(self: *Self) void {
        var buffer: [1024]u8 = undefined;
        const packet = shared.Packet.init(.lobby_sync, udptp.serialize_payload(&buffer, self.ctx.ready_check[0..self.ctx.num_players]) catch unreachable) catch unreachable;

        const data = packet.serialize(self.allocator) catch unreachable;
        self.broadcast(data);
        defer self.allocator.free(data);
    }

    fn listen(self: *Self) void {
        while (!self.should_quit) {
            self.ctx.update_count += 1;
            switch (self.ctx.state.state) {
                .Lobby, .Starting => {
                    if (self.ctx.update_count % 500 == 0) {
                        self.matchmaking_keepalive();
                        self.sync_lobby();
                    }
                    cleanup_dead_clients(self);
                },
                .Playing, .Finishing => if (self.ctx.num_players > 0) {
                    self.sync_players();
                },
            }
            self.update_state();
            self.server.listen() catch |err| switch (err) {
                error.WouldBlock => continue,
                else => {
                    std.log.err("server.listen failed with error {}", .{err});
                    self.should_quit = true;
                },
            };
        }
    }

    fn send_mm(self: *Self, data: []const u8) void {
        self.server.send_to(shared.MatchmakingEndpoint, data);
    }

    fn alert_host(self: *Self, name: []const u8) void {
        var buffer: [1024]u8 = undefined;
        const packet = shared.Packet.init(.host, udptp.serialize_payload(&buffer, shared.HostPayload{
            .q = .{ .scope = shared.SCOPE, .key = to_fixed(name, 32) },
            .policy = .AutoAccept,
        }) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        self.send_mm(data);
        self.allocator.free(data);
    }

    pub fn stop(self: *Self) void {
        self.should_quit = true;
        std.log.debug("closing server ...", .{});

        self.server_thread.join();
        std.log.debug("server closed", .{});
    }

    pub fn start(self: *Self) void {
        self.alert_host("GAME1");
        self.server.set_read_timeout(1000);

        self.server_thread = std.Thread.spawn(.{}, Self.listen, .{self}) catch unreachable;
    }
};
