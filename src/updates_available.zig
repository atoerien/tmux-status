const builtin = @import("builtin");
const std = @import("std");

const lib = @import("lib.zig");

const Child = std.process.Child;

const UpdatesAvailable = struct {
    time: i128,
    count: i64,
    security_count: i64,

    fn load(path: []const u8) !UpdatesAvailable {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        var buf: [100]u8 = undefined;
        const len = try file.read(&buf);

        var it = std.mem.splitScalar(u8, buf[0..len], ' ');
        const t = try std.fmt.parseInt(i128, it.next() orelse return error.Invalid, 10);
        const count = try std.fmt.parseInt(i64, it.next() orelse return error.Invalid, 10);
        const security_count = try std.fmt.parseInt(i64, it.next() orelse return error.Invalid, 10);

        return .{
            .time = t,
            .count = count,
            .security_count = security_count,
        };
    }

    fn save(self: *const UpdatesAvailable, path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        const writer = file.writer();

        try std.fmt.format(writer, "{} {} {}", .{ self.time, self.count, self.security_count });
    }
};

fn updatesAvailable(allocator: std.mem.Allocator) !UpdatesAvailable {
    const time = try lib.getNowNanos();

    if (try lib.which(allocator, "/usr/lib/update-notifier/apt-check")) |apt_check| {
        defer allocator.free(apt_check);

        const output = try lib.runProcessCaptureStderr(
            allocator,
            &[_][]const u8{apt_check},
            1024,
        );
        defer allocator.free(output);

        // output format: updates;security_updates
        var it = std.mem.splitScalar(u8, output, ';');
        const count = std.fmt.parseInt(i64, it.next() orelse "-1", 10) catch -1;
        const security = std.fmt.parseInt(i64, it.next() orelse "-1", 10) catch -1;

        return .{
            .time = time,
            .count = count,
            .security_count = security,
        };
    }
    if (try lib.which(allocator, "apt-get")) |apt_get| {
        defer allocator.free(apt_get);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ apt_get, "-s", "-o", "Debug::NoLocking=true", "upgrade" },
            1024 * 1024,
        );
        defer allocator.free(output);

        const count: i64 = @intCast(std.mem.count(u8, output, "\nInst"));

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }
    if (try lib.which(allocator, "pkcon")) |pkcon| {
        defer allocator.free(pkcon);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ pkcon, "get-updates", "-p" },
            1024 * 1024,
        );
        defer allocator.free(output);

        var count: i32 = -1;
        var security: i32 = -1;
        var it = std.mem.splitScalar(u8, output, '\n');
        var results_found = false;
        while (it.next()) |line| {
            if (line.len == 0)
                continue;
            if (std.mem.startsWith(u8, line, "Results:")) {
                results_found = true;
                count = 0;
                security = 0;
                continue;
            }
            if (!results_found)
                continue;

            count += 1;
            if (std.mem.startsWith(u8, line, "Security"))
                security += 1;
        }
        return .{
            .time = time,
            .count = count,
            .security_count = security,
        };
    }
    if (try lib.which(allocator, "zypper")) |zypper| {
        defer allocator.free(zypper);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ zypper, "--no-refresh", "lu", "--best-effort" },
            1024 * 1024,
        );
        defer allocator.free(output);

        const count: i64 = @intCast(std.mem.count(u8, output, "v |"));

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }
    if (try lib.which(allocator, "yum")) |yum| {
        defer allocator.free(yum);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ yum, "list", "updates", "-q" },
            1024 * 1024,
        );
        defer allocator.free(output);

        const lines = std.mem.count(u8, output, "\n");
        // subtract "Updated Packages" header
        const count: i64 = if (lines > 0) @intCast(lines - 1) else -1;

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }
    if (try lib.which(allocator, "pacman")) |pacman| {
        defer allocator.free(pacman);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ pacman, "-Sup" },
            1024 * 1024,
        );
        defer allocator.free(output);

        // ignore lines that start with "::" or space
        var count: i32 = 0;
        var it = std.mem.splitScalar(u8, output, '\n');
        while (it.next()) |line| {
            if (line.len == 0)
                continue;
            if (std.mem.startsWith(u8, line, "::") or std.mem.startsWith(u8, line, " "))
                continue;
            count += 1;
        }

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }
    if (try lib.which(allocator, "brew")) |brew| {
        defer allocator.free(brew);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ brew, "outdated" },
            50 * 1024,
        );
        defer allocator.free(output);

        const count: i64 = @intCast(std.mem.count(u8, output, "\n"));

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }
    if (try lib.which(allocator, "apk")) |apk| {
        defer allocator.free(apk);

        // Wolfi updates are cheap (~1s); so update cache every time
        try lib.runProcess(allocator, &[_][]const u8{ apk, "update" });

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ apk, "upgrade", "--simulate" },
            1024 * 1024,
        );
        defer allocator.free(output);

        const count: i64 = @intCast(std.mem.count(u8, output, " Upgrading "));

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }
    if (try lib.which(allocator, "dnf")) |dnf| {
        defer allocator.free(dnf);

        const output = try lib.runProcessCaptureStdout(
            allocator,
            &[_][]const u8{ dnf, "list", "--upgrades", "-q", "-y" },
            1024 * 1024,
        );
        defer allocator.free(output);

        const lines = std.mem.count(u8, output, "\n");
        // subtract "Available Upgrades" header
        const count: i64 = if (lines > 0) @intCast(lines - 1) else -1;

        return .{
            .time = time,
            .count = count,
            .security_count = -1,
        };
    }

    return .{
        .time = time,
        .count = 0,
        .security_count = -1,
    };
}

fn updateCache(allocator: std.mem.Allocator, cache_path: []const u8) !void {
    const updates = updatesAvailable(allocator) catch UpdatesAvailable{
        .time = try lib.getNowNanos(),
        .count = -1,
        .security_count = -1,
    };
    try updates.save(cache_path);
}

fn forkUpdateCache(allocator: std.mem.Allocator, cache_path: []const u8) !void {
    const lock_path = try std.fmt.allocPrint(allocator, "{s}.lock", .{cache_path});
    defer allocator.free(lock_path);
    const lock_fd = try std.posix.open(lock_path, .{ .CREAT = true, .CLOEXEC = true }, 0o600);
    defer std.posix.close(lock_fd);
    std.posix.flock(lock_fd, std.posix.LOCK.EX | std.posix.LOCK.NB) catch |err| switch (err) {
        error.WouldBlock => {
            // another process is updating the cache, skip
            return;
        },
        else => |e| return e,
    };

    switch (try std.posix.fork()) {
        0 => {
            // child
            // XXX: danger alert
            // we should probably exec() ourselves instead, but since we're
            // entirely singlethreaded and shouldn't be holding any locks at
            // this point it's probably ok
            // since we don't want to return back to the caller, and also avoid
            // any problems that cleanup code might cause, we _exit()

            defer comptime unreachable;

            defer std.c._exit(0);
            errdefer |err| {
                std.log.err("{s}", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                std.c._exit(1);
            }

            // make sure to close the lock fd before _exit()
            defer std.posix.close(lock_fd);

            // close stdin and stdout (redirect to /dev/null), otherwise
            // tmux waits for the child to exit before displaying anything
            try lib.redirectToNull(std.posix.STDIN_FILENO);
            try lib.redirectToNull(std.posix.STDOUT_FILENO);

            try updateCache(allocator, cache_path);
        },
        else => {
            // parent
            return;
        },
    }
}

pub fn run(ctx: *const lib.Context) !void {
    const cache_path = try ctx.getModuleCachePath("updates_available");
    defer ctx.allocator.free(cache_path);

    const cache = UpdatesAvailable.load(cache_path) catch {
        try forkUpdateCache(ctx.allocator, cache_path);
        return;
    };

    const time = try lib.getNowNanos();
    const dt = time - cache.time;

    if (cache.count == -1) {
        // last update errored, try more often
        if (dt > 10 * std.time.ns_per_s) {
            try forkUpdateCache(ctx.allocator, cache_path);
        }
        return;
    }

    if (dt > 60 * std.time.ns_per_s) {
        try forkUpdateCache(ctx.allocator, cache_path);
    }

    if (cache.count == 0)
        return;

    const stdout = ctx.stdout;

    try lib.color(stdout, .{ .color_attr = .{ .attr = "bold", .bg = "red", .fg = "brightwhite" } });
    try stdout.print("{}", .{cache.count});
    try lib.color(stdout, .none);

    try lib.color(stdout, .{ .color = .{ .bg = "red", .fg = "brightwhite" } });
    if (cache.security_count > 0) {
        _ = try stdout.write("‼");
    } else {
        _ = try stdout.write("!");
    }
    try lib.color(stdout, .end);
}
