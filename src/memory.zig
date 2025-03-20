const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag.isDarwin()) {
        @cInclude("mach/mach.h");
        @cInclude("mach/vm_statistics.h");
        @cInclude("unistd.h");
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
    switch (lib.getKernError(ret)) {
        .SUCCESS => {},
        else => |err| return lib.unexpectedKernError(err),
    }

    const page_size = @as(usize, @intCast(c.getpagesize()));

    const pages = stats.free_count + stats.inactive_count + stats.purgeable_count;
    const avail = page_size * pages;

    return .{
        .used = total - avail,
        .total = total,
    };
}

fn memoryLinux(allocator: std.mem.Allocator) !Memory {
    var meminfo = try std.fs.openFileAbsolute("/proc/meminfo", .{});
    defer meminfo.close();

    var o_total: ?usize = null;
    var o_free: ?usize = null;
    var o_avail: ?usize = null;
    var o_buffers: ?usize = null;
    var o_cached: ?usize = null;

    var reader = meminfo.reader();
    var line = std.ArrayList(u8).init(allocator);
    const line_writer = line.writer();
    defer line.deinit();
    while (true) : (line.clearRetainingCapacity()) {
        reader.streamUntilDelimiter(line_writer, '\n', null) catch |err| switch (err) {
            error.EndOfStream => {
                if (line.items.len == 0)
                    break;
            },
            else => |e| return e,
        };
        const l = line.items;
        if (std.mem.indexOfScalar(u8, l, ':')) |i| {
            const key = l[0..i];
            var v = std.mem.trimLeft(u8, l[i + 1 ..], " ");
            if (std.mem.endsWith(u8, v, " kB")) {
                v = v[0 .. v.len - 3];
            }
            const val = try std.fmt.parseUnsigned(usize, v, 10);

            if (std.mem.eql(u8, key, "MemTotal")) {
                o_total = val;
            } else if (std.mem.eql(u8, key, "MemFree")) {
                o_free = val;
            } else if (std.mem.eql(u8, key, "MemAvailable")) {
                o_avail = val;
                // should already have total
                if (o_total != null)
                    break;
            } else if (std.mem.eql(u8, key, "Buffers")) {
                o_buffers = val;
            } else if (std.mem.eql(u8, key, "Cached")) {
                o_cached = val;
                // should already have total, free and buffers
                if (o_total != null and o_free != null and o_buffers != null)
                    break;
            }
        }
    }

    if (o_total == null)
        return error.Unexpected;

    const total = o_total.?;

    var used: usize = undefined;
    if (o_avail) |avail| {
        used = total - avail;
    } else if (o_free != null and o_buffers != null and o_cached != null) {
        used = total - o_free.? - o_buffers.? - o_cached.?;
    } else {
        return error.Unexpected;
    }

    return .{
        .used = used * 1024,
        .total = total * 1024,
    };
}

fn memory(allocator: std.mem.Allocator) !Memory {
    if (builtin.os.tag.isDarwin()) {
        return try memoryDarwin();
    } else if (builtin.os.tag == .linux) {
        return try memoryLinux(allocator);
    } else {
        return error.Unsupported;
    }
}

pub fn run(ctx: *const lib.Context) !void {
    const mem = try memory(ctx.allocator);

    const used: f64 = @floatFromInt(mem.used);
    const total: f64 = @floatFromInt(mem.total);
    const usage = 100 * used / total;

    const fg = if (usage > 90) "brightyellow" else "brightwhite";

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "green", .fg = "brightwhite" } });
    const unit = try lib.printSize(stdout, total, 1024);
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
