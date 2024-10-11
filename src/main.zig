const std = @import("std");

fn echo(conn: std.net.Server.Connection) !void {
    while (true) {
        var buf: [1024]u8 = undefined;
        const read_bytes = try conn.stream.read(&buf);
        try conn.stream.writeAll(buf[0..read_bytes]);
    }
}

pub fn main() !void {
    const server_addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8000);
    var tcp_server = try server_addr.listen(.{});
    defer tcp_server.deinit();

    // while (true) {
    //     std.debug.print("waiting for conn\n", .{});
    //     const conn = try tcp_server.accept();
    //
    //     echo(conn) catch {
    //         std.debug.print("closed conn\n", .{});
    //     };
    //
    //     std.debug.print("bye bye\n", .{});
    // }

    const epoll_fd = try std.posix.epoll_create1(0);
    var listen_event = std.os.linux.epoll_event{
        .events = std.os.linux.EPOLL.IN,
        .data = .{ .fd = tcp_server.stream.handle },
    };

    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, tcp_server.stream.handle, &listen_event);

    var events: [100]std.os.linux.epoll_event = undefined;

    while (true) {
        const num_fd = std.posix.epoll_wait(epoll_fd, &events, -1);

        for (events[0..num_fd]) |event| {
            std.debug.assert(event.data.fd == tcp_server.stream.handle);

            const conn = try tcp_server.accept();
            echo(conn) catch {};
        }
    }
}
