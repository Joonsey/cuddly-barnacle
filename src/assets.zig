const std = @import("std");
const zstd = std.compress.zstd;

const allocator = std.heap.page_allocator;

pub const Asset = enum(usize) {
    cube,
    particle,
    brick,
    fence4,
    fence3,
    fence0,
    missile,
    tank,
    itembox,
    car_base,
    oil,

    ui_boost,
    ui_missile,

    lobby_notready,
    lobby_ready,
    lobby_unoccupied,
    lobby_selected,

    placement_base,
    placement_1,
    placement_2,
    placement_3,
    placement_4,
    placement_5,
    placement_6,
    placement_7,
    placement_8,
    placement_9,
    placement_10,
    placement_11,
    placement_12,
};

pub fn decompress_file(comptime path: []const u8) []u8 {
    const window_buffer = allocator.alloc(u8, 1 << 23) catch unreachable;
    defer allocator.free(window_buffer);

    const data = @embedFile(path);
    var in_stream = std.io.fixedBufferStream(data);
    var zstd_stream = zstd.decompressor(in_stream.reader(), .{ .window_buffer = window_buffer });
    const result = zstd_stream.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    return result catch unreachable;
}

var arr: std.ArrayListUnmanaged([]u8) = .{};
pub fn init() !void {
    try arr.append(allocator, decompress_file("compressed_assets/cube.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/particle.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/brick.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/fence-4.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/fence-3.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/fence-0.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/missile.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/tank.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/itembox.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/car_base.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/oil.png.zst"));

    try arr.append(allocator, decompress_file("compressed_assets/ui/icons/boost.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/icons/missile.png.zst"));

    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/notready.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/ready.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/unoccupied.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/selected.png.zst"));

    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/base.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/1st.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/2nd.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/3rd.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/4th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/5th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/6th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/7th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/8th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/9th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/10th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/11th.png.zst"));
    try arr.append(allocator, decompress_file("compressed_assets/ui/lobby/placement/12th.png.zst"));
}

pub fn deinit() void {
    for (arr.items) |item| {
        allocator.free(item);
    }

    arr.deinit(allocator);
}

pub fn get(idx: Asset) []u8 {
    return arr.items[@intFromEnum(idx)];
}
