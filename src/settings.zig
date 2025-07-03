const std = @import("std");
const util = @import("util.zig");
const builtin = @import("builtin");

const game_name = "zigkartracing";
const settings_path = game_name ++ "/settings.cfg";

pub const Settings = struct {
    sound_volume: f32,
    music_volume: f32,
    player_name: [16]u8,
    preferred_car: usize,
    player_id: u32,

    pub fn default() Settings {
        return .{
            .sound_volume = 0.25,
            .music_volume = 0.05,
            .player_name = util.to_fixed("zkr player", 16),
            .player_id = std.crypto.random.int(u32),
            .preferred_car = 0,
        };
    }

    pub fn reset_user_settings(s: Settings) Settings {
        return .{
            .sound_volume = 0.25,
            .music_volume = 0.05,
            .player_name = s.player_name,
            .player_id = s.player_id,
            .preferred_car = 0,
        };
    }

    pub fn load_from_file(allocator: std.mem.Allocator, path: []const u8) Settings {
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            std.log.debug("Could not open config file: {}", .{err});
            return Settings.default();
        };
        defer file.close();

        const file_size = (file.stat() catch return Settings.default()).size;
        const buffer = allocator.alloc(u8, file_size) catch return Settings.default();
        defer allocator.free(buffer);

        _ = file.readAll(buffer) catch return Settings.default();

        const parser = std.json.parseFromSlice(Settings, allocator, buffer, .{ .ignore_unknown_fields = true }) catch return Settings.default();
        defer parser.deinit();

        return parser.value;
    }

    fn validate(s: Settings) !void {
        if (s.music_volume > 1) return error.VolumeTooHigh;
        if (s.sound_volume > 1) return error.VolumeTooHigh;
        if (s.player_id == 0) return error.InvalidPlayerId;
        if (s.preferred_car < 1) return error.InvalidCar; // Remember to update
    }

    pub fn save(s: Settings, allocator: std.mem.Allocator) !void {
        try s.validate();

        const path = try std.fs.getAppDataDir(allocator, settings_path);
        defer allocator.free(path);

        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
        std.fs.makeDirAbsolute(dir_path) catch undefined;

        const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();

        var setting_copy = s;
        setting_copy.player_id = if (builtin.mode == .Debug) player_id else setting_copy.player_id;
        try std.json.stringify(setting_copy, .{}, file.writer());
    }
};

var settings: Settings = undefined;
var player_id: u32 = 0;

pub fn init(allocator: std.mem.Allocator) !void {
    const maybe_path = std.fs.getAppDataDir(allocator, settings_path) catch null;
    settings = if (maybe_path) |path| Settings.load_from_file(allocator, path) else Settings.default();

    if (builtin.mode == .Debug) {
        player_id = settings.player_id;
        settings.player_id = if (builtin.mode == .Debug) std.crypto.random.int(u32) else settings.player_id;
    }

    if (maybe_path) |path| allocator.free(path);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    _ = allocator;
}

pub fn save(allocator: std.mem.Allocator) !void {
    return try settings.save(allocator);
}

pub fn get() Settings {
    return settings;
}

pub fn update(s: Settings) void {
    settings = s;
}
