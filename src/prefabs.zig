const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const renderer = @import("renderer.zig");

pub const Prefab = enum(u8) {
    cube,
    tank,
    itembox,
    car_base,
};

const Map = std.AutoHashMapUnmanaged(Prefab, entity.Entity);
var map: Map = .{};
var arr: std.ArrayListUnmanaged(entity.Entity) = .{};

fn reg(comptime pre: Prefab, allocator: std.mem.Allocator, e: entity.Entity) !void {
    var e_cop = e;
    e_cop.prefab = pre;
    try map.put(allocator, pre, e_cop);
}

pub fn init(allocator: std.mem.Allocator) !void {
    // init prefabs
    try reg(.cube, allocator, .{ .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 40, .height = 40 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/cube.png") } });
    try reg(.tank, allocator, .{ .archetype = .Car, .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/tank.png") }, .shadow = .{ .radius = 9 } });
    try reg(.itembox, allocator, .{ .archetype = .ItemBox, .collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/itembox.png") }, .shadow = .{ .radius = 8 } });
    try reg(.car_base, allocator, .{ .archetype = .Car, .collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/car_base.png") }, .shadow = .{ .radius = 8 } });

    // init icons
    try items.put(allocator, .boost, try rl.loadTexture("assets/ui/icons/boost.png"));

    // UI elements
    try ui.put(allocator, .notready, try rl.loadTexture("assets/ui/lobby/notready.png"));
    try ui.put(allocator, .ready, try rl.loadTexture("assets/ui/lobby/ready.png"));
    try ui.put(allocator, .unoccupied, try rl.loadTexture("assets/ui/lobby/unoccupied.png"));
}

pub fn deinit(allocator: std.mem.Allocator) void {
    map.deinit(allocator);
    arr.deinit(allocator);
    items.deinit(allocator);
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

pub const Item = enum(u8) {
    boost,
};

pub const UI = enum(u8) {
    ready,
    notready,
    unoccupied,
};

pub fn get_item(item: Item) rl.Texture {
    return items.get(item) orelse unreachable;
}

pub fn get_ui(_ui: UI) rl.Texture {
    return ui.get(_ui) orelse unreachable;
}

var items: std.AutoHashMapUnmanaged(Item, rl.Texture) = .{};
var ui: std.AutoHashMapUnmanaged(UI, rl.Texture) = .{};
