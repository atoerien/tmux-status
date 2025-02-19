const builtin = @import("builtin");
const std = @import("std");

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

pub fn getnow() !isize {
    var ret: std.posix.timespec = undefined;
    try std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ret);
    return ret.tv_sec;
}

pub fn getsysctl(comptime T: type, name: [*:0]const u8) !T {
    var ret: T = undefined;
    var len: usize = @sizeOf(T);
    try std.posix.sysctlbynameZ(name, &ret, &len, null, 0);
    return ret;
}
