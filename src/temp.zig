const builtin = @import("builtin");
const std = @import("std");

const lib = @import("lib.zig");

fn tempLinux(path: []const u8) !f64 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    var buf: [10]u8 = undefined;
    const len = try file.read(&buf);
    const v = std.mem.trimRight(u8, buf[0..len], "\n");

    const t = try std.fmt.parseInt(isize, v, 10);
    if (@abs(t) > 1000) {
        return @as(f64, @floatFromInt(t)) / 1000;
    } else {
        return @floatFromInt(t);
    }
}

fn temp(what: []const u8) !f64 {
    if (builtin.os.tag == .linux) {
        return try tempLinux(what);
    } else {
        return error.Unsupported;
    }
}

pub fn run(ctx: *const lib.Context, what: []const u8) !void {
    const t = try temp(what);

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "black", .fg = "brightyellow" } });
    try stdout.print("{d:.0}", .{t});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "black", .fg = "brightyellow" } });
    _ = try stdout.write("C");
    try lib.color(stdout, .end);
}
