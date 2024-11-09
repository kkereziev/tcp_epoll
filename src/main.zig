const std = @import("std");
const epoll = @import("./epoll.zig");
const EventLoop = @import("./event_loop.zig");

const TcpConnectionAcceptor = struct {
    alloc: std.mem.Allocator,
    event_loop: *EventLoop,
    epoll_fd: i32,
    server: *std.net.Server,

    fn accept_tcp_connection(user_data: ?*anyopaque) anyerror!void {
        const self: *TcpConnectionAcceptor = @ptrCast(@alignCast(user_data));
        const connection = try self.server.accept();

        const tcp_echoer = try self.alloc.create(TcpEchoer);
        errdefer self.alloc.destroy(tcp_echoer);

        tcp_echoer.* = .{
            .connection = connection,
            .epoll_fd = self.epoll_fd,
        };

        const conn_data = try self.alloc.create(epoll.EventHandler);
        errdefer self.alloc.destroy(conn_data);

        conn_data.* = .{
            .data = tcp_echoer,
            .callback = TcpEchoer.echo,
        };

        try self.event_loop.register(connection.stream.handle, conn_data);
    }
};

const TcpEchoer = struct {
    connection: std.net.Server.Connection,
    handle: EventLoop.Handle,

    fn echo(user_data: ?*anyopaque) !void {
        const self: *TcpEchoer = @ptrCast(@alignCast(user_data));

        std.debug.print("Waiting\n", .{});

        var buf: [1024]u8 = undefined;
        const read_bytes = try self.connection.stream.read(&buf);

        if (read_bytes == 0) {
            try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, self.connection.stream.handle, null);

            return;
        }

        try self.connection.stream.writeAll(buf[0..read_bytes]);
    }
};

fn echo(conn: std.net.Server.Connection) !void {
    while (true) {
        var buf: [1024]u8 = undefined;
        const read_bytes = try conn.stream.read(&buf);
        try conn.stream.writeAll(buf[0..read_bytes]);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const ok = gpa.deinit();
        std.debug.assert(ok == std.heap.Check.ok);
    }

    const alloc = gpa.allocator();

    const server_addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8000);

    var tcp_server = try server_addr.listen(.{});
    defer tcp_server.deinit();

    const epoll_fd = try std.posix.epoll_create1(0);

    const event_loop = EventLoop{
        .epoll_fd = epoll_fd,
    };
    var acceptor = TcpConnectionAcceptor{
        .alloc = alloc,
        .epoll_fd = epoll_fd,
        .event_loop = &event_loop,
        .server = &tcp_server,
    };

    const listener_data = &epoll.EventHandler{
        .data = &acceptor,
        .callback = TcpConnectionAcceptor.accept_tcp_connection,
    };

    var listen_event = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN,
        .data = .{ .ptr = @intFromPtr(listener_data) },
    };

    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, tcp_server.stream.handle, &listen_event);

    var events: [100]std.os.linux.epoll_event = undefined;

    while (true) {
        const num_fd = std.posix.epoll_wait(epoll_fd, &events, -1);

        for (events[0..num_fd]) |event| {
            const data: *const epoll.EventHandler = @ptrFromInt(event.data.ptr);

            data.callback(data.data) catch |e| {
                std.log.err("Found error during event handling: {any}\n", .{e});
            };
        }
    }
}
