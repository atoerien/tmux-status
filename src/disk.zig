const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    @cInclude("sys/statvfs.h");
});

const lib = @import("lib.zig");

const Disk = struct {
    used: usize,
    total: usize,
};

fn disk() !Disk {
    const mountpoint = "/";
    var statvfs: c.struct_statvfs = undefined;
    const mountpoint_c = try std.posix.toPosixPath(mountpoint);
    const ret = c.statvfs(&mountpoint_c, &statvfs);
    if (ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }

    const blocksize = if (statvfs.f_frsize != 0) statvfs.f_frsize else statvfs.f_bsize;
    const total = blocksize * statvfs.f_blocks;
    const avail = blocksize * statvfs.f_bavail;

    return .{
        .used = total - avail,
        .total = total,
    };
}

pub fn run(ctx: *const lib.Context) !void {
    const df = try disk();

    const used: f64 = @floatFromInt(df.used);
    const total: f64 = @floatFromInt(df.total);
    const usage = 100 * used / total;

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "magenta", .fg = "brightwhite" } });
    const unit = try lib.printSize(stdout, total);
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "magenta", .fg = "brightwhite" } });
    try stdout.print("{s}", .{unit});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "magenta", .fg = "brightwhite" } });
    try stdout.print("{d:.0}", .{usage});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "magenta", .fg = "brightwhite" } });
    _ = try stdout.write("%");
    try lib.color(stdout, .end);
}
