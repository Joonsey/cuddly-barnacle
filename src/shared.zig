const udptp = @import("udptp");

const entity = @import("entity.zig");
const Levels = @import("level.zig").Levels;

const to_fixed = @import("util.zig").to_fixed;

pub const MAX_PLAYERS = 12;
pub const MIN_PLAYERS = 2;
pub const MAX_LAPS: usize = 1;
pub const SERVER_PORT = 8080;
pub const MATCHMAKING_PORT = 8469;
pub const LOCALHOST_IP = .{ 127, 0, 0, 1 };
pub const PUBLIC_IP = .{ 84, 215, 22, 166 };

pub const SCOPE = to_fixed("zigkartracing", 32);

pub const PlayerId = u32;

const builtin = @import("builtin");

pub const MatchmakingEndpoint: udptp.network.EndPoint = .{
    .address = .{ .ipv4 = .{ .value = if (builtin.mode == .Debug) LOCALHOST_IP else PUBLIC_IP } },
    .port = MATCHMAKING_PORT,
};

pub const AckPacket = extern struct {
    id: PlayerId,
};

pub const UpdatePacket = extern struct {
    transform: entity.Transform,
    race_context: entity.RaceContext,
    kinetic: entity.Kinetic,
    prefab: entity.Prefab,
    drift: entity.Drift,
    boost: entity.Boost,
};

pub const SyncPacket = extern struct {
    id: PlayerId,
    update: UpdatePacket,
};

pub const PacketType = enum(u32) {
    // matchmaking packets
    host,
    join,
    review_response,
    review_request,
    close,
    req_host_list,
    ret_host_list,
    keepalive,

    // Game packets
    ack,
    update,
    lobby_update,
    sync,
    lobby_sync,
    server_state_changed,
    finished,
};

pub const Packet = udptp.Packet(.{ .T = PacketType, .magic_bytes = 0x13800818 });

pub const CloseReason = enum(u8) {
    HOST_QUIT,
    TIMEOUT,
};

pub const JoinPayload = extern struct {
    scope: [32]u8,
    key: [32]u8,
};

pub const JoinRequestPayload = extern struct {
    ip: [4]u8,
    port: u16,
};

pub const ReviewResponsePayload = extern struct {
    result: enum(u8) {
        Accepted,
        Rejected,
        Pending,
    },
    q: JoinPayload,
    join_request: JoinRequestPayload,
};

pub const HostPayload = extern struct {
    q: JoinPayload,
    policy: JoinPolicy = .AutoAccept,
};
pub const ClosePayload = extern struct {
    q: JoinPayload,
    reason: CloseReason,
};
pub const RequestRooms = extern struct {
    scope: [32]u8,
};

pub const JoinPolicy = enum(u8) {
    AutoAccept,
    ManualReview,
    Reject,
};

pub const Room = extern struct {
    name: [32]u8,
    ip: [4]u8,
    port: u16,
    users: u16,
    capacity: u16,
    policy: JoinPolicy,
};

pub const LobbySync = extern struct {
    id: PlayerId,
    update: LobbyUpdate,
};

pub const LobbyUpdate = extern struct {
    ready: bool,
    vote: usize = 0,
    name: [16]u8,
};

pub const State = enum(u8) {
    Lobby,
    Starting,
    Playing,
    Finishing,
};

pub const Finish = extern struct {
    id: PlayerId,
    time: i64,
};

pub const ServerState = extern struct {
    state: State,
    ctx: extern struct {
        time: i64,

        const Self = @This();
        pub fn reset(self: *Self) void {
            self.time = 0;
        }
    },
};
