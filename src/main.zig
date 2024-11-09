const std = @import("std");
const epoll = @import("./epoll.zig");
const EventLoop = @import("./event_loop.zig");

const TcpConnectionAcceptor = struct {
    alloc: std.mem.Allocator,
    event_loop: *EventLoop,
    server: *std.net.Server,

    fn accept_tcp_connection(user_data: ?*anyopaque) anyerror!void {
        const self: *TcpConnectionAcceptor = @ptrCast(@alignCast(user_data));
        const connection = try self.server.accept();

        const tcp_echoer = try self.alloc.create(TcpEchoer);
        errdefer self.alloc.destroy(tcp_echoer);

        tcp_echoer.* = .{
            .connection = connection,
            .handle = undefined,
        };

        const conn_data = try self.alloc.create(epoll.EventHandler);
        errdefer self.alloc.destroy(conn_data);

        conn_data.* = .{
            .data = tcp_echoer,
            .callback = TcpEchoer.echo,
        };

        const event_loop_handle = try self.event_loop.register(connection.stream.handle, conn_data);

        tcp_echoer.handle = event_loop_handle;
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
            self.handle.deinit();

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

    var event_loop = try EventLoop.init();
    defer event_loop.deinit();

    var acceptor = TcpConnectionAcceptor{
        .alloc = alloc,
        .event_loop = &event_loop,
        .server = &tcp_server,
    };

    var listener_data = epoll.EventHandler{
        .data = &acceptor,
        .callback = TcpConnectionAcceptor.accept_tcp_connection,
    };

    const handle = try event_loop.register(tcp_server.stream.handle, &listener_data);
    defer handle.deinit();

    try event_loop.run();
}
