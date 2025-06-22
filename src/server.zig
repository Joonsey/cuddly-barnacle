const std = @import("std");
const udptp = @import("udptp");
const rl = @import("raylib");

const shared = @import("shared.zig");

const Player = struct {
    id: u32,
    index: usize,
};

const GameServerContext = struct {
    num_players: usize,
    players: std.AutoHashMapUnmanaged(udptp.network.EndPoint, Player),
    updates: [shared.MAX_PLAYERS]shared.SyncPacket,
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .num_players = 0,
            .players = .{},
            .updates = std.mem.zeroes([shared.MAX_PLAYERS]shared.SyncPacket),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.players.clearAndFree(self.allocator);
    }
};

const GameServerType = udptp.Server(GameServerContext);

pub fn handle_packet_cb(self: *GameServerType, data: []const u8, sender: udptp.network.EndPoint) udptp.PacketError!void {
    const ctx = self.ctx;
    const packet: shared.GameServerPacket = try .deserialize(data, ctx.allocator);
    defer packet.free(ctx.allocator);

    switch (packet.header.packet_type) {
        .sync => {},
        .ack => {
            const payload = try udptp.deserialize_payload(packet.payload, shared.AckPacket);
            std.log.debug("{d} has asked to connect", .{payload.id});
            if (ctx.players.size >= 12) {
                std.log.warn("{d} got rejected, because server is full", .{payload.id});
            } else {
                ctx.players.put(ctx.allocator, sender, .{ .id = payload.id, .index = ctx.num_players }) catch unreachable;
                ctx.num_players += 1;
            }
        },
        .update => {
            if (ctx.players.get(sender)) |player| {
                const payload = try udptp.deserialize_payload(packet.payload, shared.UpdatePacket);
                ctx.updates[player.index] = .{ .id = player.id, .update = payload };
            }
        },
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
        const packet = shared.GameServerPacket.init(.sync, udptp.serialize_payload(&buffer, self.ctx.updates[0..self.ctx.num_players]) catch unreachable) catch unreachable;

        const data = packet.serialize(self.allocator) catch unreachable;
        self.broadcast(data);
        defer self.allocator.free(data);
    }

    fn listen(self: *Self) void {
        while (!self.should_quit) {
            if (self.ctx.num_players > 0) self.sync_players();
            self.server.listen() catch |err| switch (err) {
                error.WouldBlock => continue,
                else => {
                    std.log.err("server.listen failed with error {}", .{err});
                    self.should_quit = true;
                },
            };
        }
    }

    pub fn stop(self: *Self) void {
        self.should_quit = true;
        std.log.debug("closing server ...", .{});

        self.server_thread.join();
        std.log.debug("server closed", .{});
    }

    pub fn start(self: *Self) void {
        self.server.set_read_timeout(1000);

        self.server_thread = std.Thread.spawn(.{}, Self.listen, .{self}) catch unreachable;
    }
};
