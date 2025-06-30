const std = @import("std");
const rl = @import("raylib");

const entity = @import("entity.zig");
const assets = @import("assets.zig");
const Camera = @import("renderer.zig").Camera;

const Sounds = enum(usize) {
    hit1,
    hit2,
    hit3,
    pickup1,
    pickup2,
    pickup3,

    pub fn hits() [3]Sounds {
        return [_]Sounds{ .hit1, .hit2, .hit3 };
    }

    pub fn pickups() [3]Sounds {
        return [_]Sounds{ .pickup1, .pickup2, .pickup3 };
    }
};

var cache: std.ArrayListUnmanaged(rl.Sound) = .{};

fn load_sound(comptime path: []const u8) !rl.Sound {
    return rl.loadSoundFromWave(try rl.loadWaveFromMemory(".wav", assets.decompress_file(path)));
}

fn init_cache(allocator: std.mem.Allocator) !void {
    // hits
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Hit.wav.zst"));
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Hit1.wav.zst"));
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Hit4.wav.zst"));
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Hit4.wav.zst"));

    // pickups
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Pickup6.wav.zst"));
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Pickup18.wav.zst"));
    try cache.append(allocator, try load_sound("compressed_assets/sfx/Pickup21.wav.zst"));
}

fn deinit_cache(allocator: std.mem.Allocator) void {
    cache.deinit(allocator);
}

pub const Sfx = struct {
    allocator: std.mem.Allocator,
    camera: *Camera,

    counter: u32 = 0,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, camera: *Camera) Self {
        init_cache(allocator) catch unreachable;
        return .{ .allocator = allocator, .camera = camera };
    }

    pub fn on_event(s: *anyopaque, ecs: *entity.ECS, event: entity.Event) void {
        const self: *Self = @alignCast(@ptrCast(s));
        switch (event) {
            .Collision => |col| {
                const a = ecs.get(col.a);
                const b = ecs.get(col.b);

                const a_in_bounds = if (a.transform) |t| !self.camera.is_out_of_bounds(t.position) else false;
                const b_in_bounds = if (b.transform) |t| !self.camera.is_out_of_bounds(t.position) else false;

                const any_in_bounds = a_in_bounds or b_in_bounds;
                if ((a.archetype == .Missile and b.archetype == .Car) or (b.archetype == .Missile and a.archetype == .Car)) {
                    const sounds = Sounds.hits();
                    if (any_in_bounds) self.play_sound(sounds[self.counter % (sounds.len - 1)]);
                } else if ((a.archetype == .ItemBox and b.archetype == .Car) or (b.archetype == .ItemBox and a.archetype == .Car)) {
                    const sounds = Sounds.pickups();
                    if (any_in_bounds) self.play_sound(sounds[self.counter % (sounds.len - 1)]);
                }
            },
            else => {},
        }
    }

    pub fn play_sound(self: *Self, sound: Sounds) void {
        self.counter += 1;

        const raylib_sound = cache.items[@intFromEnum(sound)];
        rl.playSound(raylib_sound);
    }

    pub fn deinit(self: *Self) void {
        deinit_cache(self.allocator);
    }
};
