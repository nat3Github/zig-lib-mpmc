const std = @import("std");
pub const c = @import("cimport.zig").c;
const expect = std.testing.expect;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

fn C_SCQ(order: usize) type {
    if (order > 32) @compileError("This will eat up all your memory > 2^32 entries...");
    return struct {
        const This = @This();
        __fifo_mem: []u8,
        fifo: *c.lfring,
        pub fn init(alloc: Allocator) !This {
            const mem_size = c.sqc_size(order);
            const mem = try alloc.alloc(u8, mem_size);
            const fifo: *c.lfring = @ptrCast(mem.ptr);
            c.sqc_init(fifo, order);
            return This{
                .fifo = fifo,
                .__fifo_mem = mem,
            };
        }
        pub fn deinit(self: *This, alloc: Allocator) void {
            alloc.free(self.__fifo_mem);
        }
        pub fn push(self: *This, val: usize) void {
            assert(val < std.math.powi(usize, 2, order) catch unreachable);
            _ = c.sqc_enqueue(self.fifo, order, val);
        }
        pub fn pop(self: *This) ?usize {
            const ret = c.sqc_dequeue(self.fifo, order);
            if (ret == c.SQC_EMPTY_DEQUEUE) return null else return ret;
        }
    };
}
pub const MpmcSqcConfig = struct {
    // size = 2 to the power of order;
    order: usize,
    T: type,
    // slot count
    slot_count: usize,
};
pub fn MpmcSqc(cfg: MpmcSqcConfig) type {
    if (!(cfg.slot_count <= std.math.powi(usize, 2, cfg.order) catch unreachable)) {
        "specified slot count to big for the given order";
    }
    return struct {
        const This = @This();
        const T = cfg.T;
        const order = cfg.order;
        const OccupyError = error.SlotWasNotPopped;
        q: C_SCQ(cfg.order),
        heap: []?*T,
        pub fn init(alloc: Allocator) !This {
            const heap_storage = try alloc.alloc(?*T, cfg.slot_count);
            for (heap_storage) |*x| x.* = null;
            return This{
                .q = try .init(alloc),
                .heap = heap_storage,
            };
        }
        pub fn deinit(self: *This, alloc: Allocator) void {
            self.q.deinit(alloc);
            alloc.free(self.heap);
        }
        // everyone who pushes should use a different slot
        // after pushing the slot holds the ptr value till somebody pops it
        // if the slot already holds a ptr value it returns error.SlotWasNotPopped
        // you could use another slot thats free.
        pub fn push(self: *This, slot: usize, ptr: *T) !void {
            assert(slot < self.heap.len);
            const slotptr = &self.heap[slot];
            const current_slot = @atomicLoad(?*T, slotptr, .acquire);
            if (current_slot != null) return OccupyError;
            @atomicStore(?*T, slotptr, ptr, .release);
            self.q.push(slot);
        }
        pub fn pop(self: *This) ?*T {
            if (self.q.pop()) |slot| {
                const slotptr = &self.heap[slot];
                const res = @atomicLoad(?*T, slotptr, .acquire);
                const ptr = res.?;
                @atomicStore(?*T, slotptr, null, .release);
                return ptr;
            } else return null;
        }
    };
}

fn test_basic_scq() !void {
    const alloc = std.testing.allocator;
    const thread_count = 8;
    const batch_size = 2;
    const AtomicU64 = std.atomic.Value(u64);
    const MPSC = C_SCQ(16);
    var xthread_counter = AtomicU64.init(0);
    const ResetEvent = std.Thread.ResetEvent;
    var reset_start: ResetEvent = undefined;
    reset_start.reset();
    var xmpsc = try MPSC.init(alloc);
    defer xmpsc.deinit(alloc);
    const thread_count_u64 = @as(u64, @intCast(thread_count));
    const Enque = struct {
        const This = @This();
        th_counter: *AtomicU64,
        thread_idx: usize,
        res_start: *ResetEvent,
        mpsc: *MPSC,
        pub fn f_enque(Self: This) !void {
            const self = &Self;
            _ = self.th_counter.fetchAdd(1, .seq_cst);
            self.res_start.wait();
            for (0..batch_size) |i| {
                const data = 10 * self.thread_idx + i;
                self.mpsc.push(data);
                std.log.warn("t{}-push enq/{}", .{ self.thread_idx, data });
            }
            _ = self.th_counter.fetchSub(1, .seq_cst);
        }
    };
    const Dequeue = struct {
        const This = @This();
        thread_idx: usize,
        th_counter: *AtomicU64,
        res_start: *ResetEvent,
        mpsc: *MPSC,
        pub fn f_deque(Self: This) !void {
            const self = &Self;
            _ = self.th_counter.fetchAdd(1, .seq_cst);
            self.res_start.wait();
            var t = std.time.Timer.start() catch unreachable;
            var finish = false;
            var finish_ns: u64 = 1e6;
            while (true) {
                const data = self.mpsc.pop();
                if (data) |d| std.log.warn("t{}-pop << deq\\{}", .{ self.thread_idx, d });
                if (self.th_counter.load(.monotonic) <= thread_count_u64) {
                    finish = true;
                    t.reset();
                }
                if (finish) finish_ns = std.math.sub(u64, finish_ns, t.lap()) catch 0;
                if (finish_ns == 0) break;
            }
            _ = self.th_counter.fetchSub(1, .seq_cst);
        }
    };
    for (0..thread_count) |i| {
        const t1 = Enque{
            .th_counter = &xthread_counter,
            .thread_idx = i,
            .res_start = &reset_start,
            .mpsc = &xmpsc,
        };
        var h = try std.Thread.spawn(.{ .allocator = alloc }, Enque.f_enque, .{t1});
        h.detach();
        const t2 = Dequeue{
            .th_counter = &xthread_counter,
            .thread_idx = i,
            .res_start = &reset_start,
            .mpsc = &xmpsc,
        };
        var h2 = try std.Thread.spawn(.{ .allocator = alloc }, Dequeue.f_deque, .{t2});
        h2.detach();
    }
    while (xthread_counter.load(.monotonic) != 2 * thread_count_u64) {}
    reset_start.set();
    while (xthread_counter.load(.monotonic) != 0) {}
}
test "test scq" {
    // try test_basic_scq();
    // try test_indirect_scq();
    try test_indirect_scq_init();
}

const TestStruct = struct {
    name: []const u8,
    age: usize,
};

fn test_indirect_scq_init() !void {
    const alloc = std.testing.allocator;
    const thread_count = 4;
    const thread_slots = 4;
    const T = TestStruct;
    const MPSC = MpmcSqc(.{
        .order = 8,
        .slot_count = thread_count * thread_slots,
        .T = T,
    });
    var xmpsc = try MPSC.init(alloc);
    const t = try alloc.create(T);
    defer alloc.destroy(t);
    t.*.age = 56;
    t.*.name = "peter schmutzig";
    xmpsc.push(0, t) catch unreachable;
    var is_error: anyerror = undefined;
    xmpsc.push(0, t) catch |s| {
        is_error = s;
    };
    try expect(is_error == MPSC.OccupyError);
    const res = xmpsc.pop();
    try expect(std.meta.eql(res.?.*, T{ .age = 56, .name = "peter schmutzig" }));
    xmpsc.push(0, t) catch unreachable;
    defer xmpsc.deinit(alloc);
}

fn test_the_c_stuff() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const alloc = gpa.allocator();
    _ = c;
    const mem = try alloc.alloc(usize, 1024 * 1024);
    defer alloc.free(mem);
    const fifo: *c.lfring = @ptrCast(mem.ptr);
    const order = 3;
    // const size = std.math.powi(usize, 2, order) catch unreachable;
    const size = 17;
    c.sqc_init(fifo, order);
    const k = 0;
    for (0..2) |i| {
        const ret = c.sqc_dequeue(fifo, order);
        std.log.warn("it: {} k: {} ", .{ i, ret });
    }
    for (0..size) |i| {
        const r = c.sqc_enqueue(fifo, order, k + i);
        std.log.warn("it: {} r: {} ", .{ i, r });
    }
    for (0..size) |i| {
        const ret = c.sqc_dequeue(fifo, order);
        std.log.warn("it: {} k: {} ", .{ i, ret });
    }
    std.log.warn("hello wk", .{});
}
test "test the shit" {
    // try test_the_c_stuff();
}

fn to_anyopaque(ptr: anytype) ?*anyopaque {
    return @ptrCast(ptr);
}
fn from_anyopaque_unwrap(T: type, ptr: ?*anyopaque) *T {
    return @alignCast(@ptrCast(ptr.?));
}
