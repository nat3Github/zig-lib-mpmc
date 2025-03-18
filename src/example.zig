const std = @import("std");
pub const c = @import("cmpmc").c;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const alloc = gpa.allocator();
    const mem = try alloc.alloc(u8, 1024 * 1024);
    defer alloc.free(mem);
    const fifo: *c.lfring = @ptrCast(mem.ptr);
    const order = 4;
    c.sqc_init(fifo, order);
    const T = struct {
        name: []const u8 = "gustav",
        age: usize = 50,
    };
    const gustav = try alloc.create(T);
    defer alloc.destroy(gustav);
    gustav.* = T{};
    _ = c.sqc_enqueue(fifo, order, to_anyopaque(gustav));
    std.log.warn("hello wk", .{});
}

fn to_anyopaque(ptr: anytype) *anyopaque {
    return @ptrCast(ptr);
}
