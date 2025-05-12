const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag.isDarwin()) {
        @cInclude("ifaddrs.h");
        @cInclude("net/if.h");
    }
});

const lib = @import("lib.zig");

const Network = struct {
    time: i128,
    up: u64,
    down: u64,

    fn load(path: []const u8) !Network {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        var buf: [100]u8 = undefined;
        const len = try file.read(&buf);

        var it = std.mem.splitScalar(u8, buf[0..len], ' ');
        const t = try std.fmt.parseInt(i128, it.next() orelse return error.Invalid, 10);
        const u = try std.fmt.parseUnsigned(u64, it.next() orelse return error.Invalid, 10);
        const d = try std.fmt.parseUnsigned(u64, it.next() orelse return error.Invalid, 10);

        return .{
            .time = t,
            .up = u,
            .down = d,
        };
    }

    fn save(self: *const Network, path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        const writer = file.writer();

        try std.fmt.format(writer, "{} {} {}", .{ self.time, self.up, self.down });
    }
};

fn networkTotalDarwin() !Network {
    var ifa_list: ?*c.ifaddrs = null;

    const if_ret = c.getifaddrs(&ifa_list);
    if (if_ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }
    defer c.freeifaddrs(ifa_list);

    const time = try lib.getNowNanos();

    var ret = Network{
        .time = time,
        .up = 0,
        .down = 0,
    };

    var o_ifa: ?*c.ifaddrs = ifa_list;
    while (o_ifa) |ifa| : (o_ifa = ifa.ifa_next) {
        if (ifa.ifa_flags & c.IFF_LOOPBACK != 0)
            continue;
        if (ifa.ifa_addr.*.sa_family != c.AF_LINK)
            continue;

        const ifd: *c.if_data = @alignCast(@ptrCast(ifa.ifa_data));

        ret.up += ifd.ifi_obytes;
        ret.down += ifd.ifi_ibytes;
    }

    return ret;
}

fn networkTotalLinux(allocator: std.mem.Allocator) !Network {
    const file = try std.fs.openFileAbsolute("/proc/net/dev", .{});
    defer file.close();

    const time = try lib.getNowNanos();

    var reader = file.reader();

    // skip header (2 lines)
    try reader.skipUntilDelimiterOrEof('\n');
    try reader.skipUntilDelimiterOrEof('\n');

    var ret = Network{
        .time = time,
        .up = 0,
        .down = 0,
    };

    var line = std.ArrayList(u8).init(allocator);
    const line_writer = line.writer();
    defer line.deinit();
    outer: while (true) : (line.clearRetainingCapacity()) {
        reader.streamUntilDelimiter(line_writer, '\n', null) catch |err| switch (err) {
            error.EndOfStream => {
                if (line.items.len == 0)
                    break;
            },
            else => |e| return e,
        };

        var it = std.mem.tokenizeAny(u8, line.items, " :");
        for (0..11) |i| {
            const field = it.next() orelse return error.Unexpected;
            switch (i) {
                0 => {
                    if (std.mem.eql(u8, field, "lo"))
                        continue :outer;
                },
                1 => {
                    ret.down += try std.fmt.parseUnsigned(usize, field, 10);
                },
                9 => {
                    ret.up += try std.fmt.parseUnsigned(usize, field, 10);
                },
                else => {},
            }
        }
    }

    return ret;
}

fn networkTotal(allocator: std.mem.Allocator) !Network {
    if (builtin.os.tag.isDarwin()) {
        return try networkTotalDarwin();
    } else if (builtin.os.tag == .linux) {
        return try networkTotalLinux(allocator);
    } else {
        return error.Unsupported;
    }
}

pub fn run(ctx: *const lib.Context) !void {
    const net = try networkTotal(ctx.allocator);

    const cache_path = try ctx.getModuleCachePath("network_total");
    defer ctx.allocator.free(cache_path);

    const r_cache = Network.load(cache_path);

    try net.save(cache_path);

    const cache = r_cache catch return;

    if (net.time <= cache.time) {
        // time went backwards, or didn't change (prevent div by 0)
        return;
    }

    const t1: f64 = @floatFromInt(cache.time);
    const t2: f64 = @floatFromInt(net.time);

    const up1: f64 = @floatFromInt(cache.up);
    const up2: f64 = @floatFromInt(net.up);
    const up = 8 * (up2 - up1) / (t2 - t1) * std.time.ns_per_s;

    const down1: f64 = @floatFromInt(cache.down);
    const down2: f64 = @floatFromInt(net.down);
    const down = 8 * (down2 - down1) / (t2 - t1) * std.time.ns_per_s;

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "magenta", .fg = "white" } });
    _ = try stdout.write("▴");
    const rd_unit = try lib.printSize(stdout, up, 1000);
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "magenta", .fg = "white" } });
    try stdout.print("{s}b", .{rd_unit});
    try lib.color(stdout, .end);

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "magenta", .fg = "white" } });
    _ = try stdout.write("▾");
    const wr_unit = try lib.printSize(stdout, down, 1000);
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "magenta", .fg = "white" } });
    try stdout.print("{s}b", .{wr_unit});
    try lib.color(stdout, .end);
}
