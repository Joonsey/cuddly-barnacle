const udptp = @import("udptp");

const entity = @import("entity.zig");

pub const MAX_PLAYERS = 12;
pub const SERVER_PORT = 8080;

pub const PlayerId = u32;

const GameServerPacketTypes = enum(u16) {
    ack,
    update,
    sync,
};

pub const AckPacket = extern struct {
    id: PlayerId,
};

pub const UpdatePacket = extern struct {
    transform: entity.Transform,
    race_context: entity.RaceContext,
    kinetic: entity.Kinetic,
    prefab: entity.Prefab,
};

pub const SyncPacket = extern struct {
    id: PlayerId,
    update: UpdatePacket,
};

pub const GameServerPacket = udptp.Packet(.{ .T = GameServerPacketTypes, .magic_bytes = 0x89028902 });
