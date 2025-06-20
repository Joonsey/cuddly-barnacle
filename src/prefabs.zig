const std = @import("std");
const entity = @import("entity.zig");
const renderer = @import("renderer.zig");

pub const Prefab = enum {
    cube,
    tank,
};

var map: std.AutoHashMapUnmanaged(Prefab, entity.Entity) = .{};

pub fn init(allocator: std.mem.Allocator) !void {
    try map.put(allocator, .cube, .{ .prefab = .cube, .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 40, .height = 40 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/cube.png") } });
    try map.put(allocator, .tank, .{ .prefab = .cube, .archetype = .Car, .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/tank.png") }, .shadow = .{ .radius = 9 } });
}

pub fn deinit(allocator: std.mem.Allocator) void {
    map.deinit(allocator);
}

pub fn get(fab: Prefab) entity.Entity {
    return map.get(fab) orelse @panic("no entity for prefab!");
}
