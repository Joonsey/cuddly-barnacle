const std = @import("std");
const udptp = @import("udptp");
const rl = @import("raylib");

const shared = @import("shared.zig");
const entity = @import("entity.zig");
const prefab = @import("prefabs.zig");

const GameClientContext = struct {
    num_players: usize = 0,
    updates: [shared.MAX_PLAYERS]shared.SyncPacket,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .updates = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

const GameClientType = udptp.Client(GameClientContext);

fn game_client_handle_packet_cb(self: *GameClientType, data: []const u8, sender: udptp.network.EndPoint) udptp.PacketError!void {
    const ctx = self.ctx;
    const packet: shared.GameServerPacket = try .deserialize(data, ctx.allocator);
    defer packet.free(ctx.allocator);
    _ = sender;

    switch (packet.header.packet_type) {
        .sync => {
            const size = @sizeOf(shared.SyncPacket);
            const count: usize = packet.payload.len / size;
            ctx.num_players = count;

            for (0..count) |i| {
                ctx.updates[i] = try udptp.deserialize_payload(packet.payload[i * size .. size * (1 + i)], shared.SyncPacket);
            }
        },
        else => {},
    }
}

pub const GameClient = struct {
    client: GameClientType,
    ctx: *GameClientContext,

    player_map: std.AutoHashMapUnmanaged(shared.PlayerId, entity.EntityId),

    client_thread: std.Thread,
    should_quit: bool = false,

    own_player_id: shared.PlayerId = 0,

    allocator: std.mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        const ctx = allocator.create(GameClientContext) catch unreachable;
        ctx.* = GameClientContext.init(allocator);
        var client = GameClientType.init(allocator, ctx) catch unreachable;
        client.handle_packet_cb = game_client_handle_packet_cb;
        return .{
            .client = client,
            .allocator = allocator,
            .ctx = ctx,

            .player_map = .{},

            .client_thread = undefined,
        };
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
        self.allocator.destroy(self.ctx);
        self.client.deinit();
        self.player_map.deinit(self.allocator);
    }

    pub fn sync(self: *Self, ecs: *entity.ECS) void {
        const updates = self.ctx.updates[0..self.ctx.num_players];
        for (updates) |update| {
            if (update.id == self.own_player_id) continue;

            // bandaid fix
            if (update.id == 0) continue;

            if (self.player_map.get(update.id)) |entity_id| {
                const entity_to_sync = ecs.get_mut(entity_id);
                entity_to_sync.transform = update.update.transform;
                entity_to_sync.kinetic = update.update.kinetic;
                entity_to_sync.race_context = update.update.race_context;
            } else {
                var pre = prefab.get(update.update.prefab);
                pre.transform = update.update.transform;
                pre.kinetic = update.update.kinetic;
                pre.race_context = update.update.race_context;
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
        };
        const packet = shared.GameServerPacket.init(.update, udptp.serialize_payload(&buffer, update) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        defer self.allocator.free(data);

        self.client.send(data);
    }

    pub fn connect_and_listen(self: *Self, addr: []const u8, port: u16) void {
        var buffer: [1024]u8 = undefined;
        const packet = shared.GameServerPacket.init(.ack, udptp.serialize_payload(&buffer, shared.AckPacket{ .id = self.own_player_id }) catch unreachable) catch unreachable;
        const data = packet.serialize(self.allocator) catch unreachable;
        defer self.allocator.free(data);

        std.log.debug("connecting to server at: {s}:{d}", .{ addr, port });
        self.client.connect(addr, port, data) catch unreachable;

        // TODO ???
        self.client.socket.setReadTimeout(1000) catch unreachable;
        self.client_thread = std.Thread.spawn(.{}, Self.listen, .{self}) catch unreachable;
    }
};
