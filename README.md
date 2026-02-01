# tmux-status

A rudimentary Zig port of [Byobu](https://github.com/dustinkirkland/byobu)'s `byobu-status` program for tmux, because bash is slow and I want to be able to use it without needing Byobu itself.

Several modules are missing, I've only bothered to add those that I actually use.

## Usage

`tmux-status {module1} {module2} {module3}:{arg1}:{arg2} ...`

Some modules (`disk`, `network`, etc.) require argument(s).

To reset cached data (stored alongside the tmux socket, usually in `/tmp/tmux-$UID/status-cache`):

`tmux-status reset`

Example usage in `tmux.conf`:

```tmux
run 'tmux-status reset'
set -g status-interval 1
set -g status-right " #(tmux-status updates_available reboot_required load_average processes memory swap disk:/ disk_io_total network_total uptime)"
set -g status-right-length 256
```
