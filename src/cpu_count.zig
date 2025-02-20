const std = @import("std");

const c = @cImport({
    @cInclude("unistd.h");
});

const lib = @import("lib.zig");

fn cpuCount() !usize {
    const cpus = c.sysconf(c._SC_NPROCESSORS_ONLN);
    if (cpus == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }

    return @intCast(cpus);
}

pub fn run(ctx: *const lib.Context) !void {
    const cpus = try cpuCount();

    try ctx.stdout.print("{}x", .{cpus});
}
