const std = @import("std");

/// Returns the name of the host device cpu.
pub fn getCpuName(allocator: std.mem.Allocator) ![]const u8 {
    return switch (@import("builtin").os.tag) {
        .linux => {
            const file = try std.fs.cwd().openFile("/proc/cpuinfo", .{});
            defer file.close();
            var buffer = try allocator.alloc(u8, 128);
            _ = try file.read(buffer);
            const start = if (std.mem.indexOf(u8, buffer, "model name")) |pos| pos + 13 else unreachable;
            const end = if (std.mem.indexOfScalar(u8, buffer[start..], '\n')) |pos| start + pos else unreachable;
            return buffer[start..end];
        },
        .windows => {
            const stdout = try spawn(allocator, &.{ "wmic", "cpu", "get", "name" });
            return stdout[41 .. stdout.len - 7];
        },
        .macos => try spawn(allocator, &.{ "sysctl", "-n", "machdep.cpu.brand_string" }),
        else => "err_unknown_platform",
    };
}

fn spawn(allocator: std.mem.Allocator, args: []const []const u8) ![]const u8 {
    const stdout = (try std.process.Child.run(.{ .allocator = allocator, .argv = args })).stdout;
    return stdout[0 .. stdout.len - 1];
}
