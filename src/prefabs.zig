const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const renderer = @import("renderer.zig");

pub const Prefab = enum(u8) {
    cube,
    brick,
    tank,
    itembox,
    car_base,
    fence,
    fence_end,
    fence_corner,
    missile,
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
    try reg(.brick, allocator, .{ .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 14, .height = 14 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/brick.png") } });
    try reg(.fence, allocator, .{ .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/fence-4.png") } });
    try reg(.fence_end, allocator, .{ .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/fence-3.png") } });
    try reg(.fence_corner, allocator, .{ .archetype = .Wall, .collision = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/fence-0.png") } });

    try reg(.missile, allocator, .{ .archetype = .Missile, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/missile.png") }, .shadow = .{ .radius = 8 }, .timer = .{ .timer = 0.5 } });

    try reg(.tank, allocator, .{ .archetype = .Car, .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/tank.png") }, .shadow = .{ .radius = 9 } });
    try reg(.car_base, allocator, .{ .archetype = .Car, .collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/car_base.png") }, .shadow = .{ .radius = 8 } });

    try reg(.itembox, allocator, .{ .archetype = .ItemBox, .collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 }, .transform = .{ .position = .{ .x = 0, .y = 0 } }, .renderable = .{ .Stacked = try .init("assets/itembox.png") }, .shadow = .{ .radius = 8 } });

    // init icons
    try items.put(allocator, .boost, try rl.loadTexture("assets/ui/icons/boost.png"));
    try items.put(allocator, .missile, try rl.loadTexture("assets/ui/icons/missile.png"));

    // UI elements
    try ui.put(allocator, .notready, try rl.loadTexture("assets/ui/lobby/notready.png"));
    try ui.put(allocator, .ready, try rl.loadTexture("assets/ui/lobby/ready.png"));
    try ui.put(allocator, .unoccupied, try rl.loadTexture("assets/ui/lobby/unoccupied.png"));
    try ui.put(allocator, .selected, try rl.loadTexture("assets/ui/lobby/selected.png"));

    try ui.put(allocator, .placement_base, try rl.loadTexture("assets/ui/lobby/placement/base.png"));
    try ui.put(allocator, .first, try rl.loadTexture("assets/ui/lobby/placement/1st.png"));
    try ui.put(allocator, .second, try rl.loadTexture("assets/ui/lobby/placement/2nd.png"));
    try ui.put(allocator, .third, try rl.loadTexture("assets/ui/lobby/placement/3rd.png"));
    try ui.put(allocator, .fourth, try rl.loadTexture("assets/ui/lobby/placement/4th.png"));
    try ui.put(allocator, .fifth, try rl.loadTexture("assets/ui/lobby/placement/5th.png"));
    try ui.put(allocator, .sixth, try rl.loadTexture("assets/ui/lobby/placement/6th.png"));
    try ui.put(allocator, .seventh, try rl.loadTexture("assets/ui/lobby/placement/7th.png"));
    try ui.put(allocator, .eight, try rl.loadTexture("assets/ui/lobby/placement/8th.png"));
    try ui.put(allocator, .ninth, try rl.loadTexture("assets/ui/lobby/placement/9th.png"));
    try ui.put(allocator, .tenth, try rl.loadTexture("assets/ui/lobby/placement/10th.png"));
    try ui.put(allocator, .eleventh, try rl.loadTexture("assets/ui/lobby/placement/11th.png"));
    try ui.put(allocator, .twelveth, try rl.loadTexture("assets/ui/lobby/placement/12th.png"));
}

pub fn deinit(allocator: std.mem.Allocator) void {
    map.deinit(allocator);
    arr.deinit(allocator);
    items.deinit(allocator);
    ui.deinit(allocator);
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
    missile,
};

pub const UI = enum(u8) {
    ready,
    notready,
    unoccupied,
    selected,
    placement_base,
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
    eight,
    ninth,
    tenth,
    eleventh,
    twelveth,

    pub fn get_placement(placement: usize) UI {
        return switch (placement) {
            1 => .first,
            2 => .second,
            3 => .third,
            4 => .fourth,
            5 => .fifth,
            6 => .sixth,
            7 => .seventh,
            8 => .eight,
            9 => .ninth,
            10 => .tenth,
            11 => .eleventh,
            12 => .twelveth,
            else => .placement_base,
        };
    }
};

pub fn get_item(item: Item) rl.Texture {
    return items.get(item) orelse unreachable;
}

pub fn get_ui(_ui: UI) rl.Texture {
    return ui.get(_ui) orelse unreachable;
}

var items: std.AutoHashMapUnmanaged(Item, rl.Texture) = .{};
var ui: std.AutoHashMapUnmanaged(UI, rl.Texture) = .{};
