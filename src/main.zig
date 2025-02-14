const std = @import("std");

const lib = @import("lib.zig");

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
    } else if (std.mem.eql(u8, args[1], "right")) {
        try uptime.run(stdout.any());
    }
    try bw.flush();
}
