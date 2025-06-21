const std = @import("std");
const entity = @import("entity.zig");
const renderer = @import("renderer.zig");

pub const Prefab = enum {
    cube,
    tank,
    itembox,
};

const Map = std.AutoHashMapUnmanaged(Prefab, entity.Entity);
var map: Map = .{};
var arr: std.ArrayListUnmanaged(entity.Entity) = .{};


fn reg(comptime pre: Prefab, allocator: std.mem.Allocator, e: entity.Entity) !void{
    var e_cop = e;
    e_cop.prefab = pre;
    try map.put(allocator, pre, e_cop);
}

pub fn init(allocator: std.mem.Allocator) !void {
    try reg(.cube, allocator, .{ .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 40, .height = 40 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/cube.png") } });
    try reg(.tank, allocator, .{ .archetype = .Car, .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/tank.png") }, .shadow = .{ .radius = 9 } });
    try reg(.itembox, allocator, .{ .archetype = .ItemBox, .collision = .{ .x = 0, .y = 0, .width = 30, .height = 30 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/itembox.png")}, .shadow = .{ .radius = 15 } });
}

pub fn deinit(allocator: std.mem.Allocator) void {
    map.deinit(allocator);
    arr.deinit(allocator);
}

pub fn get(fab: Prefab) entity.Entity {
    return map.get(fab) orelse @panic("no entity for prefab!");
}

pub const Iterator = struct {
    items: []entity.Entity,
    current: usize = 0,

    const Self = @This();
    pub fn next(self: *Self) entity.Entity {
        self.inc(1);
        return self.items[self.current];
    }

    pub fn previous(self: *Self) entity.Entity {
        self.inc(-1);
        return self.items[self.current];
    }

    fn inc(self: *Self, delta: i32) void {
        self.current = @intCast(@mod((@as(i32, @intCast(self.current)) + delta), @as(i32, @intCast(self.items.len))));
    }
};

pub fn iter(allocator: std.mem.Allocator) Iterator {
    var it = map.valueIterator();
    arr.clearAndFree(allocator);

    while (it.next()) |item| arr.append(allocator, item.*) catch unreachable;

    return .{
        .items = arr.items,
    };
}
