const udptp = @import("udptp");

const entity = @import("entity.zig");
const Levels = @import("level.zig").Levels;

const to_fixed = @import("util.zig").to_fixed;

pub const RENDER_WIDTH: i32 = 360;
pub const RENDER_HEIGHT: i32 = 240;

pub const MAX_PLAYERS = 12;
pub const MIN_PLAYERS = 2;
pub const MAX_LAPS: usize = if (builtin.mode == .Debug) 1 else 3;
pub const SERVER_PORT = 8080;
pub const MATCHMAKING_PORT = 8469;
pub const LOCALHOST_IP = .{ 127, 0, 0, 1 };
pub const PUBLIC_IP = .{ 84, 215, 22, 166 };

pub const TIME_TO_FINISH_S = 20;
/// after everyone has readied up
pub const TIME_TO_START_ALL_READY_S = 5;
/// after everyone has loaded in
pub const TIME_TO_START_RACING_S = 5;

/// fading in form the right side of the screen
pub const LEADERBOARD_ENTER_TIME_MS = 350;

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
    name_tag: entity.NameTag,
};

pub const SyncPacket = extern struct {
    id: PlayerId,
    update: UpdatePacket,
};

pub const PacketType = enum(u32) {
    // matchmaking packets
    host,
    join,
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
    spawn_missile,
    req_server_state_sync,
};

pub const Packet = udptp.Packet(.{ .T = PacketType, .magic_bytes = 0x13800818 });

pub const Server = extern struct {
    host_name: [16]u8,
    num_players: usize,
    player_id: PlayerId,
};

pub const JoinRequestPayload = extern struct {
    ip: [4]u8,
    port: u16,
};

pub const ServerSync = extern struct {
    host_addr: JoinRequestPayload,
    server: Server,
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

pub const MissileSpawn = extern struct {
    transform: entity.Transform,
    prefab: entity.Prefab,
    race_context: entity.RaceContext,
    kinetic: entity.Kinetic,
    target: PlayerId,
};

pub const MissileSpawnSync = extern struct {
    id: PlayerId,
    item: MissileSpawn,
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
