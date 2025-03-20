const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag.isDarwin()) {
        @cInclude("libproc.h");
    }
});

const lib = @import("lib.zig");

fn processesDarwin(allocator: std.mem.Allocator) !usize {
    const ret = c.proc_listallpids(null, 0);
    if (ret < 0) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }
    const bufsize: usize = @intCast(ret);
    const buf = try allocator.alloc(c.pid_t, bufsize);

    const count = c.proc_listallpids(@ptrCast(buf), @intCast(bufsize * @sizeOf(c.pid_t)));
    if (count < 0) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }

    return @intCast(count);
}

fn processesLinux() !usize {
    var stat = try std.fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer stat.close();

    var count: usize = 0;
    var it = stat.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            // check if the first char in filename is 0-9
            if (entry.name.len >= 1) {
                const char = entry.name[0];
                if (char >= '0' and char <= '9') {
                    count += 1;
                }
            }
        }
    }
    return count;
}

fn processes(allocator: std.mem.Allocator) !usize {
    if (builtin.os.tag.isDarwin()) {
        return try processesDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try processesLinux();
    } else {
        return error.Unsupported;
    }
}

pub fn run(ctx: *const lib.Context) !void {
    const p = try processes(ctx.allocator);

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "yellow", .fg = "white" } });
    try stdout.print("{}", .{p});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "yellow", .fg = "white" } });
    _ = try stdout.write("&");
    try lib.color(stdout, .end);
}
