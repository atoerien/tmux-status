const builtin = @import("builtin");
const std = @import("std");

pub const Context = struct {
    allocator: std.mem.Allocator,
    stdout: std.io.AnyWriter,
    cacheDir: []const u8,

    pub fn getModuleCachePath(self: *const Context, module: []const u8) ![]u8 {
        const paths = [_][]const u8{ self.cacheDir, module };
        return std.fs.path.join(self.allocator, &paths);
    }
};

pub const Color = union(enum) {
    esc,
    none,
    end,
    bold,
    invert,
    color: struct { fg: []const u8, bg: []const u8 },
    color_attr: struct { fg: []const u8, attr: []const u8, bg: []const u8 },
};

pub fn color(out: std.io.AnyWriter, col: Color) !void {
    switch (col) {
        .esc => { // esc
            _ = try out.write("");
        },
        .none => { // -, none
            _ = try out.write("#[default]");
        },
        .end => { // --
            _ = try out.write("#[default] ");
        },
        .bold => { // bold
            _ = try out.write("#[default]#[fg=bold]");
        },
        .invert => { // invert
            _ = try out.write("#[default]#[reverse]");
        },
        .color => |val| { // {back} {fore}
            _ = try out.print("#[default]#[fg={s},bg={s}]", .{ val.fg, val.bg });
        },
        .color_attr => |val| { // {attr} {back} {fore}
            _ = try out.print("#[default]#[fg={s},{s},bg={s}]", .{ val.fg, val.attr, val.bg });
        },
    }
}

/// formats and prints val to stdout
/// returns unit ("k", "M", "G", etc)
pub fn printSize(stdout: std.io.AnyWriter, val: f64) ![]const u8 {
    var size = val;

    if (@abs(size) < 1) {
        try stdout.print("{d:1.2}", .{size});
        return "";
    }

    const units = [_][]const u8{ "", "k", "M", "G", "T", "P", "E", "Z" };
    for (units) |unit| {
        if (@abs(size) < 999.5) {
            if (@abs(size) < 99.95) {
                if (@abs(size) < 9.995) {
                    try stdout.print("{d:1.2}", .{size});
                    return unit;
                }
                try stdout.print("{d:2.1}", .{size});
                return unit;
            }
            try stdout.print("{d:3.0}", .{size});
            return unit;
        }
        size /= 1024;
    }

    try stdout.print("{d:3.1}", .{size});
    return "Y";
}

const errno_map = errno_map: {
    var max_value = 0;
    for (std.enums.values(std.c.E)) |v|
        max_value = @max(max_value, @intFromEnum(v));

    var map: [max_value + 1]anyerror = undefined;
    @memset(&map, error.Unexpected);
    for (std.enums.values(std.c.E)) |v|
        map[@intFromEnum(v)] = @field(anyerror, "E" ++ @tagName(v));

    break :errno_map map;
};

pub fn errnoToZigErr(err: anytype) anyerror {
    const num = if (@typeInfo(@TypeOf(err)) == .Enum)
        @intFromEnum(err)
    else
        err;

    if (num > 0 and num < errno_map.len)
        return errno_map[@intCast(num)];

    return error.Unexpected;
}

pub fn runProcess(allocator: std.mem.Allocator, argv: []const []const u8, max_output_bytes: usize) ![]u8 {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout = std.ArrayList(u8).init(allocator);
    defer stdout.deinit();
    var stderr = std.ArrayList(u8).init(allocator);
    defer stderr.deinit();

    try child.spawn();
    try child.collectOutput(&stdout, &stderr, max_output_bytes);
    const term = try child.wait();

    if (term != .Exited or term.Exited != 0) {
        return error.ChildProcessError;
    }

    return stdout.toOwnedSlice();
}

pub fn getTmuxSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const argv = [_][]const u8{ "tmux", "display-message", "-pF", "#{socket_path}" };

    return runProcess(allocator, &argv, 1024);
}

pub fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
    const socketPath = try getTmuxSocketPath(allocator);
    defer allocator.free(socketPath);
    const dir = std.fs.path.dirname(socketPath) orelse unreachable;
    const cacheDir = try std.fmt.allocPrint(allocator, "{s}/cache", .{dir});
    // ensure dir exists
    std.fs.makeDirAbsolute(cacheDir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // ignore
        else => |e| return e,
    };
    return cacheDir;
}

pub fn getNow() !isize {
    var ret: std.posix.timespec = undefined;
    try std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ret);
    return ret.tv_sec;
}

pub fn getNowNanos() !i128 {
    var ret: std.posix.timespec = undefined;
    try std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ret);
    return @as(i128, ret.tv_sec) * std.time.ns_per_s + ret.tv_nsec;
}

pub fn getsysctl(comptime T: type, name: [*:0]const u8) !T {
    var ret: T = undefined;
    var len: usize = @sizeOf(T);
    try std.posix.sysctlbynameZ(name, &ret, &len, null, 0);
    return ret;
}
