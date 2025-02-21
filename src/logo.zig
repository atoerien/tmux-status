const builtin = @import("builtin");
const std = @import("std");

const lib = @import("lib.zig");

fn logoDarwin() []const u8 {
    return "#[default]#[fg=black,bg=white]  #[default] ";
}

fn logoLinux() []const u8 {
    return "#[default]#[fg=blue,bold,bg=white] λ #[default] ";
}

fn logo() []const u8 {
    if (builtin.os.tag.isDarwin()) {
        return logoDarwin();
    } else if (builtin.os.tag == .linux) {
        return logoLinux();
    } else {
        @compileError("unsupported OS");
    }
}

pub fn run(ctx: *const lib.Context) !void {
    const s = logo();

    _ = try ctx.stdout.write(s);
}
