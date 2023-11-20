const std = @import("std");
const Benchmark = @import("zoop").Benchmark;

pub fn main() !void {
    var bench = Benchmark.init(std.heap.page_allocator, .{
        .export_json = "benchmark.json",
    });
    defer bench.deinit();
    try bench.add("kinda slow function", testfn1);
    try bench.add("fast function", testfn2);
    try bench.add("slowest function", testfn3);
    try bench.run();
}

fn testfn1() !void {
    std.time.sleep(5e4);
}

fn testfn2() !void {
    std.time.sleep(0);
}

fn testfn3() !void {
    std.time.sleep(2e5);
}
