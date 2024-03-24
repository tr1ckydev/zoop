const std = @import("std");
fn formatIntu32(float: f32, comptime fmt: []const u8, options: std.fmt.FormatOptions, w: anytype) !void {
    _ = fmt;
    var buf: [24]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var buf_writer = fbs.writer();
    inline for (.{
        .{ 'P', 1_000_000_000_000_000 },
        .{ 'T', 1_000_000_000_000 },
        .{ 'G', 1_000_000_000 },
        .{ 'M', 1_000_000 },
        .{ 'k', 1_000 },
        .{ null, 1 },
    }) |pair| {
        const suffix: ?u8, const val = pair;
        if (suffix) |s| {
            if (float >= val) {
                try buf_writer.print("{d:.3}{c}", .{ float / val, s });
                break;
            }
        } else {
            try buf_writer.print("{d}", .{float});
            break;
        }
    }
    return std.fmt.formatBuf(fbs.getWritten(), options, w);
}

/// Format an integer into short form like 26.312k, 2.906M.
pub fn fmtIntu32(int: u32) std.fmt.Formatter(formatIntu32) {
    return .{ .data = @floatFromInt(int) };
}
