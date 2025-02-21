const std = @import("std");

const lib = @import("lib.zig");

const cpu_count = @import("cpu_count.zig");
const cpu_freq = @import("cpu_freq.zig");
const disk = @import("disk.zig");
const disk_io = @import("disk_io.zig");
const hostname = @import("hostname.zig");
const load_average = @import("load_average.zig");
const logo = @import("logo.zig");
const memory = @import("memory.zig");
const network = @import("network.zig");
const processes = @import("processes.zig");
const swap = @import("swap.zig");
const uptime = @import("uptime.zig");
const whoami = @import("whoami.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cacheDir = try lib.getCacheDir(allocator);
    defer allocator.free(cacheDir);

    const ctx = lib.Context{
        .allocator = allocator,
        .stdout = stdout.any(),
        .cacheDir = cacheDir,
    };

    if (args.len < 2) {
        //
    } else if (std.mem.eql(u8, args[1], "left")) {
        try logo.run(&ctx);
        try whoami.run(&ctx);
        try hostname.run(&ctx);
    } else if (std.mem.eql(u8, args[1], "right")) {
        try load_average.run(&ctx);
        try processes.run(&ctx);
        try cpu_count.run(&ctx);
        // try cpu_freq.run(&ctx);
        try memory.run(&ctx);
        try swap.run(&ctx);
        try disk.run(&ctx);
        try disk_io.run(&ctx);
        try network.run(&ctx);
        try uptime.run(&ctx);
    }
    try bw.flush();
}
