const std = @import("std");

const lib = @import("lib.zig");

const modules = struct {
    pub const cpu_count = @import("cpu_count.zig");
    pub const cpu_freq = @import("cpu_freq.zig");
    pub const disk = @import("disk.zig");
    pub const disk_io = @import("disk_io.zig");
    pub const disk_io_total = @import("disk_io_total.zig");
    pub const hostname = @import("hostname.zig");
    pub const load_average = @import("load_average.zig");
    pub const logo = @import("logo.zig");
    pub const memory = @import("memory.zig");
    pub const network = @import("network.zig");
    pub const network_total = @import("network_total.zig");
    pub const processes = @import("processes.zig");
    pub const swap = @import("swap.zig");
    pub const uptime = @import("uptime.zig");
    pub const whoami = @import("whoami.zig");
};

fn runModule(mod: []const u8, args: [][]const u8, ctx: *const lib.Context) !void {
    inline for (@typeInfo(modules).@"struct".decls) |decl| {
        if (std.mem.eql(u8, mod, decl.name)) {
            const module = @field(modules, decl.name);
            const run = module.run;
            const run_argcount = @typeInfo(@TypeOf(run)).@"fn".params.len - 1;
            if (args.len < run_argcount) {
                return error.NotEnoughArgs;
            } else if (args.len > run_argcount) {
                return error.TooManyArgs;
            }
            var run_args: std.meta.ArgsTuple(@TypeOf(run)) = undefined;
            run_args[0] = ctx;
            inline for (0..run_argcount) |i| {
                run_args[i + 1] = args[i];
            }
            return @call(.auto, run, run_args);
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

    if (args.len == 2 and std.mem.eql(u8, args[1], "reset")) {
        try lib.clearCacheDir(cache_dir);
        return;
    }

    try lib.ensureCacheDir(cache_dir);

    const ctx = lib.Context{
        .allocator = allocator,
        .stdout = stdout.any(),
        .cache_dir = cache_dir,
    };

    var mod_args = std.ArrayList([]const u8).init(allocator);
    for (args[1..]) |arg| {
        mod_args.clearRetainingCapacity();
        var it = std.mem.splitScalar(u8, arg, ':');
        const mod = it.next().?;
        while (it.next()) |a| {
            try mod_args.append(a);
        }
        try runModule(mod, mod_args.items, &ctx);
    }
    try bw.flush();
}
