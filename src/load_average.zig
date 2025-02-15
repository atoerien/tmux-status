const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
});

const lib = @import("lib.zig");

fn load() !f64 {
    var loadavg: f64 = undefined;
    const ret = c.getloadavg(&loadavg, 1);
    if (ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }
    return loadavg;
}

pub fn run(stdout: std.io.AnyWriter) !void {
    const l = try load();

    try lib.color(stdout, .{ .color = .{ .bg = "brightyellow", .fg = "black" } });
    try stdout.print("{d:.2}", .{l});
    try lib.color(stdout, .end);
}
