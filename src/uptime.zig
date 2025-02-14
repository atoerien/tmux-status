const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag == .linux) {
        @cInclude("sys/sysinfo.h");
    }
});

const lib = @import("lib.zig");

fn uptimeDarwin() !isize {
    const now = try lib.getnow();

    const boottime = try lib.getsysctl(std.posix.timespec, "kern.boottime");

    return now - boottime.tv_sec;
}

fn uptimeLinux() !isize {
    var sysinfo: c.sysinfo = undefined;
    const ret = c.sysinfo(&sysinfo);
    if (ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }
    return sysinfo.uptime;
}

fn uptime() !isize {
    if (builtin.os.tag.isDarwin()) {
        return try uptimeDarwin();
    } else if (builtin.os.tag == .linux) {
        return try uptimeLinux();
    } else {
        @compileError("unsupported OS");
    }
}

pub fn run(stdout: std.io.AnyWriter) !void {
    const u = try uptime();

    try lib.color(stdout, .{ .color = .{ .bg = "white", .fg = "blue" } });
    if (u > 86400) {
        const d = @divTrunc(u, 86400);
        const h = @divTrunc(@rem(u, 86400), 3600);
        try stdout.print("{}d{}h", .{ d, h });
    } else if (u > 3600) {
        const h = @divTrunc(u, 3600);
        const m = @divTrunc(@rem(u, 3600), 60);
        try stdout.print("{}h{}m", .{ h, m });
    } else if (u > 60) {
        const m = @divTrunc(u, 60);
        try stdout.print("{}m", .{m});
    } else {
        try stdout.print("{}s", .{u});
    }
    try lib.color(stdout, .end);
}
