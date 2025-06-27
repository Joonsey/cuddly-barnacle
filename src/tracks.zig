const std = @import("std");
const rl = @import("raylib");

const entity = @import("entity.zig");
const renderer = @import("renderer.zig");

const track_halflife = 12 * std.time.ms_per_s;

pub const Tracks = struct {
    const Query = struct {
        entity: entity.EntityId,
        index: usize,
    };

    const Track = struct {
        position: rl.Vector2,
        rotation: f32 = 0,
        start_time: i64,
    };

    const _Tracks = struct {
        arr: std.ArrayListUnmanaged(Track) = .{},
        start_time: i64,
    };

    tracks: std.AutoHashMapUnmanaged(Query, _Tracks) = .{},
    indexes: std.AutoHashMapUnmanaged(entity.EntityId, usize) = .{},

    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.tracks.valueIterator();
        while (iter.next()) |track| track.arr.clearAndFree(self.allocator);
        self.tracks.clearAndFree(self.allocator);
        self.indexes.clearAndFree(self.allocator);
    }

    pub fn update(self: *Self, ecs: *entity.ECS) void {
        for (ecs.entities.items, 0..) |e, i| {
            if (e.drift) |drift| {
                if (e.boost) |boost| {
                    if (e.transform) |transform| {
                        if (transform.height == 0 and (drift.is_drifting or boost.boost_time > 0)) {
                            const index: usize = self.indexes.get(@intCast(i)) orelse blk: {
                                self.indexes.put(self.allocator, @intCast(i), 0) catch unreachable;
                                break :blk 0;
                            };
                            const query: Query = .{ .index = index, .entity = @intCast(i) };
                            var tracks: _Tracks = self.tracks.get(query) orelse .{ .start_time = std.time.milliTimestamp() };
                            tracks.arr.append(self.allocator, .{ .position = transform.position, .rotation = transform.rotation, .start_time = std.time.milliTimestamp() }) catch unreachable;
                            self.tracks.put(self.allocator, query, tracks) catch unreachable;
                        } else {
                            if (self.indexes.getPtr(@intCast(i))) |index| {
                                const query: Query = .{ .index = index.*, .entity = @intCast(i) };
                                if (self.tracks.get(query)) |_| index.* += 1;
                            }
                        }
                    }
                }
            }
        }

        var iter = self.tracks.valueIterator();
        while (iter.next()) |tracks| {
            if (tracks.start_time + (track_halflife * 2) < std.time.milliTimestamp()) {
                tracks.arr.clearAndFree(self.allocator);
            }
        }
    }

    pub fn draw(self: Self, camera: renderer.Camera) void {
        var iter = self.tracks.valueIterator();
        var left: std.ArrayListUnmanaged(rl.Vector2) = .{};
        var right: std.ArrayListUnmanaged(rl.Vector2) = .{};

        const car_radius = 5;
        while (iter.next()) |tracks| {
            if (tracks.arr.items.len == 0) continue;
            for (tracks.arr.items) |track| {
                const forward = rl.Vector2{ .x = @cos(track.rotation), .y = @sin(track.rotation) };
                const perp = rl.Vector2{ .x = -forward.y, .y = forward.x };

                left.append(self.allocator, camera.get_relative_position(track.position.add(perp.scale(car_radius)))) catch unreachable;
                right.append(self.allocator, camera.get_relative_position(track.position.subtract(perp.scale(car_radius)))) catch unreachable;
            }
            const now = std.time.milliTimestamp();
            var color: rl.Color = .black;
            const t_time_halflife = tracks.start_time + (track_halflife * 2);
            const delta_time: f32 = @floatFromInt(t_time_halflife - now);
            color = color.alpha(delta_time / @as(f32, @floatFromInt(track_halflife)));
            rl.drawLineStrip(left.items, color);
            rl.drawLineStrip(right.items, color);
            left.clearAndFree(self.allocator);
            right.clearAndFree(self.allocator);
        }
    }
};
