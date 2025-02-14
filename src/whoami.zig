const std = @import("std");

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("pwd.h");
});

const lib = @import("lib.zig");

fn whoami(allocator: std.mem.Allocator) ![]const u8 {
    const sysconf_ret = c.sysconf(c._SC_GETPW_R_SIZE_MAX);
    if (sysconf_ret == -1) {
        const errno = std.c._errno().*;
        return lib.errnoToZigErr(errno);
    }

    const bufsize: usize = @intCast(sysconf_ret);

    const buf = try allocator.alloc(u8, bufsize);
    defer allocator.free(buf);

    var pwd: c.passwd = undefined;
    var result: ?*c.passwd = undefined;
    const ret = c.getpwuid_r(c.getuid(), &pwd, @ptrCast(buf), bufsize, &result);
    if (ret != 0) {
        return lib.errnoToZigErr(ret);
    }
    if (result == null) {
        return error.ENOENT;
    }
    const s_len = std.mem.len(pwd.pw_name);
    const s = try allocator.dupe(u8, pwd.pw_name[0..s_len]);
    return s;
}

pub fn run(allocator: std.mem.Allocator, stdout: std.io.AnyWriter) !void {
    const s = try whoami(allocator);
    defer allocator.free(s);
    try lib.color(stdout, .bold);
    try stdout.print("{s}@", .{s});
    try lib.color(stdout, .none);
}
