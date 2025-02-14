const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag.isDarwin()) {
        @cInclude("sys/sysctl.h");
    } else if (builtin.os.tag == .linux) {
        @cInclude("sys/sysinfo.h");
    }
});

const lib = @import("lib.zig");

const Swap = struct {
    used: usize,
    total: usize,
};

fn swapDarwin() !Swap {
    const swapusage = try lib.getsysctl(c.xsw_usage, "vm.swapusage");

    return .{
        .used = swapusage.xsu_used / 1024,
        .total = swapusage.xsu_total / 1024,
    };
}

fn swapLinux() !Swap {
    var sysinfo: c.sysinfo = undefined;
    const ret = c.sysinfo(&sysinfo);
    if (ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }

    const mem_unit = sysinfo.mem_unit;
    const total = sysinfo.totalswap * mem_unit;
    const free = sysinfo.freeswap * mem_unit;

    return .{
        .used = (total - free) / 1024,
        .total = total / 1024,
    };
}

fn swap() !Swap {
    if (builtin.os.tag.isDarwin()) {
        return try swapDarwin();
    } else if (builtin.os.tag == .linux) {
        return try swapLinux();
    } else {
        @compileError("unsupported OS");
    }
}

pub fn run(stdout: std.io.AnyWriter) !void {
    const swp = try swap();

    const used: f64 = @floatFromInt(swp.used);
    const total: f64 = @floatFromInt(swp.total);
    const usage = 100 * used / total;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "brightgreen", .fg = "black" } });

    var unit: []const u8 = undefined;
    if (total >= 1048576) {
        try stdout.print("s{d:.1}", .{total / 1048576});
        unit = "G";
    } else if (total >= 1024) {
        try stdout.print("s{d:.0}", .{total / 1024});
        unit = "M";
    } else {
        try stdout.print("s{d:.0}", .{total});
        unit = "K";
    }
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "brightgreen", .fg = "black" } });
    try stdout.print("{s}", .{unit});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "brightgreen", .fg = "black" } });
    try stdout.print("{d:.0}", .{usage});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "brightgreen", .fg = "black" } });
    _ = try stdout.write("%");
    try lib.color(stdout, .end);
}
