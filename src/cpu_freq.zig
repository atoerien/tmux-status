const builtin = @import("builtin");
const std = @import("std");

const lib = @import("lib.zig");

fn cpuFreqDarwin() !f64 {
    const hz: f64 = @floatFromInt(try lib.getsysctl(c_int, "hw.cpufrequency"));
    return hz / 1000000000;
}

fn cpuFreqLinux(allocator: std.mem.Allocator) !f64 {
    const cpufreq = std.fs.openFileAbsolute("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", .{});
    if (cpufreq) |file| {
        defer file.close();
        var buf: [10]u8 = undefined;
        const len = try file.read(&buf);
        const v = std.mem.trimRight(u8, buf[0..len], "\n");
        const hz = try std.fmt.parseUnsigned(usize, v, 10);
        return @as(f64, @floatFromInt(hz)) / 1000000;
    } else |_| {
        var cpuinfo = try std.fs.openFileAbsolute("/proc/cpuinfo", .{});
        defer cpuinfo.close();

        var reader = cpuinfo.reader();
        var line = std.ArrayList(u8).init(allocator);
        const lineWriter = line.writer();
        defer line.deinit();
        while (true) {
            reader.streamUntilDelimiter(lineWriter, '\n', null) catch |err| switch (err) {
                error.EndOfStream => {
                    if (line.items.len == 0)
                        break;
                },
                else => |e| return e,
            };
            const l = line.items;
            if (std.mem.startsWith(u8, l, "cpu MHz") or std.mem.startsWith(u8, l, "clock")) {
                if (std.mem.indexOfScalar(u8, l, ':')) |i| {
                    const v = std.mem.trimLeft(u8, l[i + 1 ..], " ");
                    const hz = try std.fmt.parseFloat(f64, v);
                    return hz / 1000;
                }
            }
            line.clearRetainingCapacity();
        }
    }
    return error.Unavailable;
}

fn cpuFreq(allocator: std.mem.Allocator) !f64 {
    if (builtin.os.tag.isDarwin()) {
        return try cpuFreqDarwin();
    } else if (builtin.os.tag == .linux) {
        return try cpuFreqLinux(allocator);
    } else {
        @compileError("unsupported OS");
    }
}

pub fn run(allocator: std.mem.Allocator, stdout: std.io.AnyWriter) !void {
    const freq = try cpuFreq(allocator);

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "cyan", .fg = "brightwhite" } });
    try stdout.print("{d:.2}", .{freq});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "cyan", .fg = "brightwhite" } });
    _ = try stdout.write("GHz");
    try lib.color(stdout, .end);
}
