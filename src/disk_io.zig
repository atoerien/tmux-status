const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    if (builtin.os.tag.isDarwin()) {
        // prevent CFSTR() from trying to use a nonexistent compiler builtin
        @cUndef("__CONSTANT_CFSTRINGS__");
        @cInclude("CoreFoundation/CoreFoundation.h");
        @cInclude("IOKit/IOBSD.h");
        @cInclude("IOKit/IOKitLib.h");
        @cInclude("IOKit/storage/IOBlockStorageDriver.h");
        @cInclude("IOKit/storage/IOMedia.h");
    }
});

const lib = @import("lib.zig");

const DiskIo = struct {
    time: i128,
    read: u64,
    write: u64,

    fn load(path: []const u8) !DiskIo {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        var buf: [100]u8 = undefined;
        const len = try file.read(&buf);

        var it = std.mem.splitScalar(u8, buf[0..len], ' ');
        const t = try std.fmt.parseInt(i128, it.next() orelse return error.Invalid, 10);
        const rd = try std.fmt.parseUnsigned(u64, it.next() orelse return error.Invalid, 10);
        const wr = try std.fmt.parseUnsigned(u64, it.next() orelse return error.Invalid, 10);

        return .{
            .time = t,
            .read = rd,
            .write = wr,
        };
    }

    fn save(self: *const DiskIo, path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        const writer = file.writer();

        try std.fmt.format(writer, "{} {} {}", .{ self.time, self.read, self.write });
    }
};

fn diskIoDarwin(allocator: std.mem.Allocator, disk: []const u8) !DiskIo {
    const disk_cstr = try lib.allocCString(allocator, disk);
    defer allocator.free(disk_cstr);

    var ret: std.c.kern_return_t = undefined;

    var main_port: std.c.mach_port_t = undefined;
    ret = c.IOMainPort(c.MACH_PORT_NULL, &main_port);
    switch (lib.getKernError(ret)) {
        .SUCCESS => {},
        else => |err| return lib.unexpectedKernError(err),
    }

    var drive_iter: c.io_iterator_t = undefined;
    ret = c.IOServiceGetMatchingServices(main_port, c.IOBSDNameMatching(main_port, c.kNilOptions, disk_cstr), &drive_iter);
    switch (lib.getKernError(ret)) {
        .SUCCESS => {},
        else => |err| return lib.unexpectedKernError(err),
    }
    defer _ = c.IOObjectRelease(drive_iter);

    const drive = c.IOIteratorNext(drive_iter);
    if (drive == 0) {
        return error.NotFound;
    }
    defer _ = c.IOObjectRelease(drive);
    if (c.IOObjectConformsTo(drive, "IOMedia") == 0) {
        return error.Invalid;
    }

    var driver: c.io_registry_entry_t = undefined;
    ret = c.IORegistryEntryGetParentEntry(drive, c.kIOServicePlane, &driver);
    switch (lib.getKernError(ret)) {
        .SUCCESS => {},
        else => |err| return lib.unexpectedKernError(err),
    }
    defer _ = c.IOObjectRelease(driver);
    if (c.IOObjectConformsTo(driver, "IOBlockStorageDriver") == 0) {
        return error.Invalid;
    }

    const time = try lib.getNowNanos();

    var properties: c.CFMutableDictionaryRef = undefined;
    ret = c.IORegistryEntryCreateCFProperties(driver, &properties, c.kCFAllocatorDefault, c.kNilOptions);
    switch (lib.getKernError(ret)) {
        .SUCCESS => {},
        else => |err| return lib.unexpectedKernError(err),
    }
    defer c.CFRelease(properties);

    const o_stats: c.CFDictionaryRef = @ptrCast(c.CFDictionaryGetValue(properties, c.CFSTR(c.kIOBlockStorageDriverStatisticsKey)));
    const stats = o_stats orelse return error.Unexpected;

    var o_number: c.CFNumberRef = undefined;

    var read: i64 = 0;
    o_number = @ptrCast(c.CFDictionaryGetValue(stats, c.CFSTR(c.kIOBlockStorageDriverStatisticsBytesReadKey)));
    if (o_number) |number| {
        _ = c.CFNumberGetValue(number, c.kCFNumberSInt64Type, &read);
    }

    var write: i64 = 0;
    o_number = @ptrCast(c.CFDictionaryGetValue(stats, c.CFSTR(c.kIOBlockStorageDriverStatisticsBytesWrittenKey)));
    if (o_number) |number| {
        _ = c.CFNumberGetValue(number, c.kCFNumberSInt64Type, &write);
    }

    return .{
        .time = time,
        .read = @intCast(read),
        .write = @intCast(write),
    };
}

fn diskIoLinux(disk: []const u8) !DiskIo {
    var path_buf: [std.posix.PATH_MAX]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/sys/block/{s}/stat", .{disk});
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const time = try lib.getNowNanos();

    var buf: [1024]u8 = undefined;
    const len = try file.readAll(&buf);

    var read: usize = undefined;
    var write: usize = undefined;

    var it = std.mem.tokenizeScalar(u8, buf[0..len], ' ');
    for (0..7) |i| {
        const field = it.next() orelse return error.Unexpected;
        switch (i) {
            2 => read = try std.fmt.parseUnsigned(usize, field, 10),
            6 => write = try std.fmt.parseUnsigned(usize, field, 10),
            else => {},
        }
    }

    return .{
        .time = time,
        .read = 512 * read,
        .write = 512 * write,
    };
}

fn diskIo(allocator: std.mem.Allocator, disk: []const u8) !DiskIo {
    if (builtin.os.tag.isDarwin()) {
        return try diskIoDarwin(allocator, disk);
    } else if (builtin.os.tag == .linux) {
        return try diskIoLinux(disk);
    } else {
        return error.Unsupported;
    }
}

pub fn run(ctx: *const lib.Context, disk: []const u8) !void {
    const io = try diskIo(ctx.allocator, disk);

    const cache_path = try ctx.getModuleCachePath("disk_io");
    defer ctx.allocator.free(cache_path);

    const r_cache = DiskIo.load(cache_path);

    try io.save(cache_path);

    const cache = r_cache catch return;

    if (io.time <= cache.time) {
        // time went backwards, or didn't change (prevent div by 0)
        return;
    }

    const t1: f64 = @floatFromInt(cache.time);
    const t2: f64 = @floatFromInt(io.time);

    const rd1: f64 = @floatFromInt(cache.read);
    const rd2: f64 = @floatFromInt(io.read);
    const read = (rd2 - rd1) / (t2 - t1) * std.time.ns_per_s;

    const wr1: f64 = @floatFromInt(cache.write);
    const wr2: f64 = @floatFromInt(io.write);
    const write = (wr2 - wr1) / (t2 - t1) * std.time.ns_per_s;

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "brightmagenta", .fg = "brightwhite" } });
    _ = try stdout.write("◂");
    const rd_unit = try lib.printSize(stdout, read, 1024);
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "brightmagenta", .fg = "brightwhite" } });
    try stdout.print("{s}B/s", .{rd_unit});
    try lib.color(stdout, .end);

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "brightmagenta", .fg = "brightwhite" } });
    _ = try stdout.write("▸");
    const wr_unit = try lib.printSize(stdout, write, 1024);
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "brightmagenta", .fg = "brightwhite" } });
    try stdout.print("{s}B/s", .{wr_unit});
    try lib.color(stdout, .end);
}
