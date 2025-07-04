const std = @import("std");
const rl = @import("raylib");

pub fn get_mouse_pos(render_width: f32, screen_width: f32, render_height: f32, screen_height: f32) rl.Vector2 {
    const mouse_position = rl.getMousePosition();
    return mouse_position.multiply(.{ .x = render_width / screen_width, .y = render_height / screen_height });
}

pub fn to_fixed(str: []const u8, comptime arr_len: usize) [arr_len]u8 {
    std.debug.assert(str.len <= arr_len);
    var buf: [arr_len]u8 = std.mem.zeroes([arr_len]u8);
    @memcpy(buf[0..str.len], str);
    return buf;
}
