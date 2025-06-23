const std = @import("std");
const rl = @import("raylib");

const entity = @import("entity.zig");
const renderer = @import("renderer.zig");

pub const Tracks = struct {
    const Query = struct {
        entity: entity.EntityId,
        index: usize,
    };

    const Track = struct {
        position: rl.Vector2,
        rotation: f32 = 0,
    };

    tracks: std.AutoHashMapUnmanaged(Query, std.ArrayListUnmanaged(Track)) = .{},
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
        while (iter.next()) |track| track.clearAndFree(self.allocator);
        self.tracks.clearAndFree(self.allocator);
        self.indexes.clearAndFree(self.allocator);
    }

    pub fn update(self: *Self, ecs: *entity.ECS) void {
        for (ecs.entities.items, 0..) |e, i| {
            if (e.drift) |drift| {
                if (e.transform) |transform| {
                    if (drift.is_drifting) {
                        const index: usize = self.indexes.get(@intCast(i)) orelse blk: {
                            self.indexes.put(self.allocator, @intCast(i), 0) catch unreachable;
                            break :blk 0;
                        };
                        const query: Query = .{ .index = index, .entity = @intCast(i) };
                        var tracks: std.ArrayListUnmanaged(Track) = self.tracks.get(query) orelse .{};
                        tracks.append(self.allocator, .{ .position = transform.position, .rotation = transform.rotation }) catch unreachable;
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

    pub fn draw(self: Self, camera: renderer.Camera) void {
        var iter = self.tracks.valueIterator();
        var left: std.ArrayListUnmanaged(rl.Vector2) = .{};
        var right: std.ArrayListUnmanaged(rl.Vector2) = .{};

        const car_radius = 7;
        while (iter.next()) |tracks| {
            for (tracks.items) |track| {
                const forward = rl.Vector2{ .x = @cos(track.rotation), .y = @sin(track.rotation) };
                const perp = rl.Vector2{ .x = -forward.y, .y = forward.x };

                left.append(self.allocator, camera.get_relative_position(track.position.add(perp.scale(car_radius)))) catch unreachable;
                right.append(self.allocator, camera.get_relative_position(track.position.subtract(perp.scale(car_radius)))) catch unreachable;
            }
            rl.drawLineStrip(left.items, .black);
            rl.drawLineStrip(right.items, .black);
            left.clearAndFree(self.allocator);
            right.clearAndFree(self.allocator);
        }
    }
};
