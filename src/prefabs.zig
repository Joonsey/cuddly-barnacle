const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");
const renderer = @import("renderer.zig");
const assets = @import("assets.zig");

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
    particle,
    smoke_emitter,
    oil,
};

const Map = std.AutoHashMapUnmanaged(Prefab, entity.Entity);
var map: Map = .{};
var arr: std.ArrayListUnmanaged(entity.Entity) = .{};

fn reg(comptime pre: Prefab, allocator: std.mem.Allocator, e: entity.Entity) !void {
    var e_cop = e;
    e_cop.prefab = pre;
    try map.put(allocator, pre, e_cop);
}

pub fn get_texture(comptime asset: assets.Asset) !rl.Texture {
    const image = try rl.loadImageFromMemory(".png", assets.get(asset));
    defer image.unload();
    return try image.toTexture();
}

pub fn init(allocator: std.mem.Allocator) !void {
    // init prefabs
    try reg(.cube, allocator, .{
        .archetype = .Wall,
        .collision = .{ .x = 0, .y = 0, .width = 40, .height = 40 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.cube) } },
    });
    try reg(.particle, allocator, .{
        .archetype = .Particle,
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.particle) } },
    });
    try reg(.brick, allocator, .{
        .archetype = .Wall,
        .collision = .{ .x = 0, .y = 0, .width = 14, .height = 14 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.brick) } },
    });
    try reg(.fence, allocator, .{
        .archetype = .Wall,
        .collision = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.fence4) } },
    });
    try reg(.fence_end, allocator, .{
        .archetype = .Wall,
        .collision = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.fence3) } },
    });
    try reg(.fence_corner, allocator, .{
        .archetype = .Wall,
        .collision = .{ .x = 0, .y = 0, .width = 8, .height = 8 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.fence0) } },
    });

    try reg(.missile, allocator, .{
        .archetype = .Missile,
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.missile) } },
        .shadow = .{ .radius = 8 },
        .hazard = .{},
    });

    try reg(.tank, allocator, .{
        .archetype = .Car,
        .collision = .{ .x = 0, .y = 0, .width = 18, .height = 18 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.tank) } },
        .shadow = .{ .radius = 9 },
    });
    try reg(.car_base, allocator, .{
        .archetype = .Car,
        .collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.car_base) } },
        .shadow = .{ .radius = 8 },
    });

    try reg(.itembox, allocator, .{
        .archetype = .ItemBox,
        .collision = .{ .x = 0, .y = 0, .width = 16, .height = 16 },
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.itembox) } },
        .shadow = .{ .radius = 8 },
    });

    try reg(.smoke_emitter, allocator, .{
        .archetype = .ParticleEmitter,
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .particle_emitter = .{ .kind = .{ .Stacked = .{} }, .direction = .init(0, 0) },
    });

    try reg(.oil, allocator, .{
        .archetype = .Hazard,
        .transform = .{ .position = .{ .x = 0, .y = 0 } },
        .renderable = .{ .Stacked = .{ .texture = try get_texture(.oil) } },
        .hazard = .{},
    });

    // init icons
    try items.put(allocator, .boost, try get_texture(.ui_boost));
    try items.put(allocator, .missile, try get_texture(.ui_missile));
    try items.put(allocator, .oil, try get_texture(.ui_oil));

    // UI elements
    try ui.put(allocator, .notready, try get_texture(.lobby_notready));
    try ui.put(allocator, .ready, try get_texture(.lobby_ready));
    try ui.put(allocator, .unoccupied, try get_texture(.lobby_unoccupied));
    try ui.put(allocator, .selected, try get_texture(.lobby_selected));

    try ui.put(allocator, .placement_base, try get_texture(.placement_base));
    try ui.put(allocator, .first, try get_texture(.placement_1));
    try ui.put(allocator, .second, try get_texture(.placement_2));
    try ui.put(allocator, .third, try get_texture(.placement_3));
    try ui.put(allocator, .fourth, try get_texture(.placement_4));
    try ui.put(allocator, .fifth, try get_texture(.placement_5));
    try ui.put(allocator, .sixth, try get_texture(.placement_6));
    try ui.put(allocator, .seventh, try get_texture(.placement_7));
    try ui.put(allocator, .eight, try get_texture(.placement_8));
    try ui.put(allocator, .ninth, try get_texture(.placement_9));
    try ui.put(allocator, .tenth, try get_texture(.placement_10));
    try ui.put(allocator, .eleventh, try get_texture(.placement_11));
    try ui.put(allocator, .twelveth, try get_texture(.placement_12));
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
    oil,
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
