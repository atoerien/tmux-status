const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag.isDarwin()) {
        @cInclude("mach/mach.h");
        @cInclude("mach/vm_statistics.h");
        @cInclude("unistd.h");
    } else if (builtin.os.tag == .linux) {
        @cInclude("sys/sysinfo.h");
    }
});

const lib = @import("lib.zig");

const Memory = struct {
    used: usize,
    total: usize,
};

fn memoryDarwin() !Memory {
    const total = try lib.getsysctl(usize, "hw.memsize_usable");

    const host = c.mach_host_self();
    var stats: c.vm_statistics64 = undefined;
    var count: c.mach_msg_type_number_t = @sizeOf(c.vm_statistics64) / @sizeOf(c.integer_t);
    const ret = c.host_statistics64(host, c.HOST_VM_INFO64, @ptrCast(&stats), &count);
    switch (std.c.getKernError(ret)) {
        .SUCCESS => {},
        else => |err| return std.c.unexpectedKernError(err),
    }

    const page_size = @as(usize, @intCast(c.getpagesize()));

    const pages = stats.free_count + stats.inactive_count + stats.purgeable_count;
    const avail = page_size * pages;

    return .{
        .used = total - avail,
        .total = total,
    };
}

fn memoryLinux() !Memory {
    var sysinfo: c.struct_sysinfo = undefined;
    const ret = c.sysinfo(&sysinfo);
    if (ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }

    const mem_unit = sysinfo.mem_unit;
    const total = sysinfo.totalram * mem_unit;
    const avail = (sysinfo.freeram + sysinfo.sharedram + sysinfo.bufferram) * mem_unit;

    return .{
        .used = total - avail,
        .total = total,
    };
}

fn memory() !Memory {
    if (builtin.os.tag.isDarwin()) {
        return try memoryDarwin();
    } else if (builtin.os.tag == .linux) {
        return try memoryLinux();
    } else {
        @compileError("unsupported OS");
    }
}

pub fn run(ctx: *const lib.Context) !void {
    const mem = try memory();

    const used: f64 = @floatFromInt(mem.used);
    const total: f64 = @floatFromInt(mem.total);
    const usage = 100 * used / total;

    const fg = if (usage > 90) "brightyellow" else "brightwhite";

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "green", .fg = "brightwhite" } });
    const unit = try lib.printSize(stdout, total);
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "green", .fg = "brightwhite" } });
    try stdout.print("{s}", .{unit});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "green", .fg = fg } });
    try stdout.print("{d:.0}", .{usage});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "green", .fg = fg } });
    _ = try stdout.write("%");
    try lib.color(stdout, .end);
}
