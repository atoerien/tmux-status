const builtin = @import("builtin");
const std = @import("std");

pub const Context = struct {
    allocator: std.mem.Allocator,
    stdout: std.io.AnyWriter,
    cache_dir: []const u8,

    pub fn getModuleCachePath(self: *const Context, module: []const u8) ![]u8 {
        const paths = [_][]const u8{ self.cache_dir, module };
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
pub fn printSize(stdout: std.io.AnyWriter, val: f64, comptime divisor: comptime_int) ![]const u8 {
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
        size /= divisor;
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
    const num = if (@typeInfo(@TypeOf(err)) == .@"enum")
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

    var stdout = std.ArrayListUnmanaged(u8){};
    defer stdout.deinit(allocator);
    var stderr = std.ArrayListUnmanaged(u8){};
    defer stderr.deinit(allocator);

    try child.spawn();
    try child.collectOutput(allocator, &stdout, &stderr, max_output_bytes);
    const term = try child.wait();

    if (term != .Exited or term.Exited != 0) {
        return error.ChildProcessError;
    }

    return stdout.toOwnedSlice(allocator);
}

pub fn getTmuxSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const argv = [_][]const u8{ "tmux", "display-message", "-pF", "#{socket_path}" };

    return runProcess(allocator, &argv, 1024);
}

pub fn getCacheDir(allocator: std.mem.Allocator) ![]u8 {
    const socket_path = try getTmuxSocketPath(allocator);
    defer allocator.free(socket_path);
    const dir = std.fs.path.dirname(socket_path) orelse unreachable;
    return try std.fmt.allocPrint(allocator, "{s}/cache", .{dir});
}

pub fn ensureCacheDir(cache_dir: []const u8) !void {
    std.fs.makeDirAbsolute(cache_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // ignore
        else => |e| return e,
    };
}

pub fn clearCacheDir(cache_dir: []const u8) !void {
    var dir = std.fs.openDirAbsolute(cache_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return, // nothing to do
        else => |e| return e,
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        try dir.deleteTree(entry.name);
    }
}

pub fn getNow() !isize {
    const time = try std.posix.clock_gettime(std.posix.CLOCK.REALTIME);
    return time.sec;
}

pub fn getNowNanos() !i128 {
    const time = try std.posix.clock_gettime(std.posix.CLOCK.REALTIME);
    return @as(i128, time.sec) * std.time.ns_per_s + time.nsec;
}

pub fn getsysctl(comptime T: type, name: [*:0]const u8) !T {
    var ret: T = undefined;
    var len: usize = @sizeOf(T);
    try std.posix.sysctlbynameZ(name, &ret, &len, null, 0);
    return ret;
}

pub fn allocCString(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const ret = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(ret, s);
    return ret;
}

// removed from std, copied from https://github.com/ziglang/zig/blob/master/src/link.zig

pub fn getKernError(err: std.c.kern_return_t) KernE {
    return @as(KernE, @enumFromInt(@as(u32, @truncate(@as(usize, @intCast(err))))));
}

pub fn unexpectedKernError(err: KernE) std.posix.UnexpectedError {
    if (std.posix.unexpected_error_tracing) {
        std.debug.print("unexpected error: {d}\n", .{@intFromEnum(err)});
        std.debug.dumpCurrentStackTrace(null);
    }
    return error.Unexpected;
}

/// Kernel return values
pub const KernE = enum(u32) {
    SUCCESS = 0,
    /// Specified address is not currently valid
    INVALID_ADDRESS = 1,
    /// Specified memory is valid, but does not permit the
    /// required forms of access.
    PROTECTION_FAILURE = 2,
    /// The address range specified is already in use, or
    /// no address range of the size specified could be
    /// found.
    NO_SPACE = 3,
    /// The function requested was not applicable to this
    /// type of argument, or an argument is invalid
    INVALID_ARGUMENT = 4,
    /// The function could not be performed.  A catch-all.
    FAILURE = 5,
    /// A system resource could not be allocated to fulfill
    /// this request.  This failure may not be permanent.
    RESOURCE_SHORTAGE = 6,
    /// The task in question does not hold receive rights
    /// for the port argument.
    NOT_RECEIVER = 7,
    /// Bogus access restriction.
    NO_ACCESS = 8,
    /// During a page fault, the target address refers to a
    /// memory object that has been destroyed.  This
    /// failure is permanent.
    MEMORY_FAILURE = 9,
    /// During a page fault, the memory object indicated
    /// that the data could not be returned.  This failure
    /// may be temporary; future attempts to access this
    /// same data may succeed, as defined by the memory
    /// object.
    MEMORY_ERROR = 10,
    /// The receive right is already a member of the portset.
    ALREADY_IN_SET = 11,
    /// The receive right is not a member of a port set.
    NOT_IN_SET = 12,
    /// The name already denotes a right in the task.
    NAME_EXISTS = 13,
    /// The operation was aborted.  Ipc code will
    /// catch this and reflect it as a message error.
    ABORTED = 14,
    /// The name doesn't denote a right in the task.
    INVALID_NAME = 15,
    /// Target task isn't an active task.
    INVALID_TASK = 16,
    /// The name denotes a right, but not an appropriate right.
    INVALID_RIGHT = 17,
    /// A blatant range error.
    INVALID_VALUE = 18,
    /// Operation would overflow limit on user-references.
    UREFS_OVERFLOW = 19,
    /// The supplied (port) capability is improper.
    INVALID_CAPABILITY = 20,
    /// The task already has send or receive rights
    /// for the port under another name.
    RIGHT_EXISTS = 21,
    /// Target host isn't actually a host.
    INVALID_HOST = 22,
    /// An attempt was made to supply "precious" data
    /// for memory that is already present in a
    /// memory object.
    MEMORY_PRESENT = 23,
    /// A page was requested of a memory manager via
    /// memory_object_data_request for an object using
    /// a MEMORY_OBJECT_COPY_CALL strategy, with the
    /// VM_PROT_WANTS_COPY flag being used to specify
    /// that the page desired is for a copy of the
    /// object, and the memory manager has detected
    /// the page was pushed into a copy of the object
    /// while the kernel was walking the shadow chain
    /// from the copy to the object. This error code
    /// is delivered via memory_object_data_error
    /// and is handled by the kernel (it forces the
    /// kernel to restart the fault). It will not be
    /// seen by users.
    MEMORY_DATA_MOVED = 24,
    /// A strategic copy was attempted of an object
    /// upon which a quicker copy is now possible.
    /// The caller should retry the copy using
    /// vm_object_copy_quickly. This error code
    /// is seen only by the kernel.
    MEMORY_RESTART_COPY = 25,
    /// An argument applied to assert processor set privilege
    /// was not a processor set control port.
    INVALID_PROCESSOR_SET = 26,
    /// The specified scheduling attributes exceed the thread's
    /// limits.
    POLICY_LIMIT = 27,
    /// The specified scheduling policy is not currently
    /// enabled for the processor set.
    INVALID_POLICY = 28,
    /// The external memory manager failed to initialize the
    /// memory object.
    INVALID_OBJECT = 29,
    /// A thread is attempting to wait for an event for which
    /// there is already a waiting thread.
    ALREADY_WAITING = 30,
    /// An attempt was made to destroy the default processor
    /// set.
    DEFAULT_SET = 31,
    /// An attempt was made to fetch an exception port that is
    /// protected, or to abort a thread while processing a
    /// protected exception.
    EXCEPTION_PROTECTED = 32,
    /// A ledger was required but not supplied.
    INVALID_LEDGER = 33,
    /// The port was not a memory cache control port.
    INVALID_MEMORY_CONTROL = 34,
    /// An argument supplied to assert security privilege
    /// was not a host security port.
    INVALID_SECURITY = 35,
    /// thread_depress_abort was called on a thread which
    /// was not currently depressed.
    NOT_DEPRESSED = 36,
    /// Object has been terminated and is no longer available
    TERMINATED = 37,
    /// Lock set has been destroyed and is no longer available.
    LOCK_SET_DESTROYED = 38,
    /// The thread holding the lock terminated before releasing
    /// the lock
    LOCK_UNSTABLE = 39,
    /// The lock is already owned by another thread
    LOCK_OWNED = 40,
    /// The lock is already owned by the calling thread
    LOCK_OWNED_SELF = 41,
    /// Semaphore has been destroyed and is no longer available.
    SEMAPHORE_DESTROYED = 42,
    /// Return from RPC indicating the target server was
    /// terminated before it successfully replied
    RPC_SERVER_TERMINATED = 43,
    /// Terminate an orphaned activation.
    RPC_TERMINATE_ORPHAN = 44,
    /// Allow an orphaned activation to continue executing.
    RPC_CONTINUE_ORPHAN = 45,
    /// Empty thread activation (No thread linked to it)
    NOT_SUPPORTED = 46,
    /// Remote node down or inaccessible.
    NODE_DOWN = 47,
    /// A signalled thread was not actually waiting.
    NOT_WAITING = 48,
    /// Some thread-oriented operation (semaphore_wait) timed out
    OPERATION_TIMED_OUT = 49,
    /// During a page fault, indicates that the page was rejected
    /// as a result of a signature check.
    CODESIGN_ERROR = 50,
    /// The requested property cannot be changed at this time.
    POLICY_STATIC = 51,
    /// The provided buffer is of insufficient size for the requested data.
    INSUFFICIENT_BUFFER_SIZE = 52,
    /// Denied by security policy
    DENIED = 53,
    /// The KC on which the function is operating is missing
    MISSING_KC = 54,
    /// The KC on which the function is operating is invalid
    INVALID_KC = 55,
    /// A search or query operation did not return a result
    NOT_FOUND = 56,
    _,
};
