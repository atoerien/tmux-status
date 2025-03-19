const std = @import("std");

const lib = @import("lib.zig");

const modules = struct {
    pub const cpu_count = @import("cpu_count.zig");
    pub const cpu_freq = @import("cpu_freq.zig");
    pub const disk = @import("disk.zig");
    pub const disk_io = @import("disk_io.zig");
    pub const hostname = @import("hostname.zig");
    pub const load_average = @import("load_average.zig");
    pub const logo = @import("logo.zig");
    pub const memory = @import("memory.zig");
    pub const network = @import("network.zig");
    pub const processes = @import("processes.zig");
    pub const swap = @import("swap.zig");
    pub const uptime = @import("uptime.zig");
    pub const whoami = @import("whoami.zig");
};

fn runModule(mod: []const u8, ctx: *const lib.Context) !void {
    inline for (@typeInfo(modules).@"struct".decls) |decl| {
        if (std.mem.eql(u8, mod, decl.name)) {
            const module = @field(modules, decl.name);
            try module.run(ctx);
            return;
        }
    }
    return error.InvalidModule;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cache_dir = try lib.getCacheDir(allocator);
    defer allocator.free(cache_dir);

    const ctx = lib.Context{
        .allocator = allocator,
        .stdout = stdout.any(),
        .cache_dir = cache_dir,
    };

    for (args[1..]) |arg| {
        try runModule(arg, &ctx);
    }
    try bw.flush();
}
