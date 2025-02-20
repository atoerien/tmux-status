const std = @import("std");

const lib = @import("lib.zig");

const cpu_count = @import("cpu_count.zig");
const cpu_freq = @import("cpu_freq.zig");
const disk = @import("disk.zig");
const hostname = @import("hostname.zig");
const load_average = @import("load_average.zig");
const memory = @import("memory.zig");
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

    if (args.len < 2) {
        //
    } else if (std.mem.eql(u8, args[1], "left")) {
        try whoami.run(allocator, stdout.any());
        try hostname.run(allocator, stdout.any());
    } else if (std.mem.eql(u8, args[1], "right")) {
        try load_average.run(stdout.any());
        try processes.run(allocator, stdout.any());
        try cpu_count.run(stdout.any());
        // try cpu_freq.run(allocator, stdout.any());
        try memory.run(stdout.any());
        try swap.run(stdout.any());
        try disk.run(stdout.any());
        try uptime.run(stdout.any());
    }
    try bw.flush();
}
