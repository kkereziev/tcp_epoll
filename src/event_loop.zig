const std = @import("std");
const epoll = @import("./epoll.zig");

const EventLoop = @This();

epoll_fd: i32,

pub fn init() !EventLoop {
    const fd = try std.posix.epoll_create1(0);

    return .{
        .epoll_fd = fd,
    };
}

pub fn register(self: *EventLoop, fd: i32, handler: *const epoll.EventHandler) !Handle {
    var listen_event = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN,
        .data = .{ .ptr = @intFromPtr(handler) },
    };

    try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &listen_event);

    return Handle{
        .epoll_fd = self.epoll_fd,
        .fd = fd,
    };
}

pub fn run(self: *EventLoop) !void {
    var events: [100]std.os.linux.epoll_event = undefined;

    while (true) {
        const num_fd = std.posix.epoll_wait(self.epoll_fd, &events, -1);

        for (events[0..num_fd]) |event| {
            const data: *const epoll.EventHandler = @ptrFromInt(event.data.ptr);

            data.callback(data.data) catch |e| {
                std.log.err("Found error during event handling: {any}\n", .{e});
            };
        }
    }
}

pub const Handle = struct {
    fd: i32,
    epoll_fd: i32,

    pub fn deinit(self: *const Handle) void {
        std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, self.fd, null) catch |e| {
            std.debug.panic("Failed to unregister with epoll: {any}\n", .{e});
        };
    }
};
