const Callback = *const fn (?*anyopaque) anyerror!void;

pub const EventHandler = struct {
    data: ?*anyopaque,
    callback: Callback,
};
