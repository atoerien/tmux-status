const std = @import("std");

const lib = @import("lib.zig");

fn hostname(allocator: std.mem.Allocator) ![]const u8 {
    var buf = try allocator.alloc(u8, std.posix.HOST_NAME_MAX);
    errdefer allocator.free(buf);

    return try std.posix.gethostname(@ptrCast(&buf));
}

pub fn run(allocator: std.mem.Allocator, stdout: std.io.AnyWriter) !void {
    const s = try hostname(allocator);
    defer allocator.free(s);
    try lib.color(stdout, .bold);
    try stdout.print("{s}", .{s});
    try lib.color(stdout, .end);
}
