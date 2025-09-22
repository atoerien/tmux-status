const builtin = @import("builtin");
const std = @import("std");

const lib = @import("lib.zig");

fn isLivePatchedLinux() !bool {
    const file = try std.fs.openFileAbsolute("/proc/modules", .{});
    defer file.close();

    var reader = file.reader();

    var buf: [17]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    while (true) : (stream.reset()) {
        reader.streamUntilDelimiter(stream.writer(), '\n', buf.len) catch |err| switch (err) {
            error.EndOfStream => {
                if (try stream.getPos() == 0)
                    break;
            },
            error.StreamTooLong => {
                try reader.skipUntilDelimiterOrEof('\n');
            },
            else => |e| return e,
        };
        if (std.mem.eql(u8, stream.getWritten(), "kpatch_livepatch_")) {
            return true;
        }
    }
    return false;
}

pub fn run(ctx: *const lib.Context) !void {
    const stdout = ctx.stdout;

    if (builtin.os.tag == .linux) {
        var livepatched = false;
        if (std.fs.accessAbsolute("/var/run/unattended-upgrades.pid", .{})) {
            try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "brightred", .fg = "brightwhite" } });
            _ = try stdout.write("⚠");
            try lib.color(stdout, .end);
        } else |_| {}
        if (try isLivePatchedLinux()) {
            try lib.color(stdout, .{ .color = .{ .bg = "black", .fg = "brightgreen" } });
            _ = try stdout.write("🗹 ");
            try lib.color(stdout, .none);
            livepatched = true;
        }
        if (std.fs.accessAbsolute("/var/run/reboot-required", .{})) {
            if (livepatched) {
                try lib.color(stdout, .{ .color = .{ .bg = "black", .fg = "brightgreen" } });
            } else {
                try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "black", .fg = "brightred" } });
            }
            _ = try stdout.write("⟳");
            try lib.color(stdout, .end);
        } else |_| {}
        if (std.fs.accessAbsolute("/var/run/powernap/powersave", .{})) {
            try lib.color(stdout, .{ .color = .{ .bg = "black", .fg = "brightwhite" } });
            _ = try stdout.write(".zZ");
            try lib.color(stdout, .end);
        } else |_| {}
    } else {
        return error.Unsupported;
    }
}
