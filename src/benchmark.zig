const std = @import("std");
const builtin = @import("builtin");
const Chameleon = @import("chameleon").Chameleon;
pub const getCpuName = @import("cpu_name.zig").getCpuName;
pub const fmtIntu32 = @import("fmt_u32.zig").fmtIntu32;

const CallbackFn = *const fn () anyerror!void;

fn noop() !void {}

pub const Config = struct {
    show_cpu_name: bool = true,
    show_zig_version: bool = true,
    show_summary: bool = true,
    show_summary_comparison: bool = true,
    show_output: bool = true,
    enable_warmup: bool = true,
    iterations: u16 = 10,
    budget: u64 = 2e9, // 2 seconds
    hooks: LifecycleHooks = .{},
    export_json: ?[]const u8 = null,
};

const LifecycleHooks = struct {
    beforeAll: CallbackFn = noop,
    afterAll: CallbackFn = noop,
    beforeEach: CallbackFn = noop,
    afterEach: CallbackFn = noop,
};

const Test = struct {
    name: []const u8,
    function: CallbackFn,
};

const Result = struct {
    name: []const u8,
    iterations: u32 = 0,
    total: u128 = 0,
    avg: u64 = 0,
    min: u64 = std.math.maxInt(u64),
    max: u64 = 0,
};

fn sortResult(_: @TypeOf(.{}), a: Result, b: Result) bool {
    return a.avg < b.avg;
}

pub const Benchmark = struct {
    allocator: std.mem.Allocator,
    config: Config,
    tests: std.ArrayList(Test),
    results: std.ArrayList(Result),
    noop: u64 = 0,
    stdout: std.fs.File.Writer = std.io.getStdOut().writer(),
    cpu: []const u8 = undefined,
    /// Create a new Benchmark instance with provided `config` options.
    ///
    /// Deinitialize with `deinit`.
    pub fn init(allocator: std.mem.Allocator, config: Config) Benchmark {
        return .{
            .allocator = allocator,
            .config = config,
            .tests = std.ArrayList(Test).init(allocator),
            .results = std.ArrayList(Result).init(allocator),
        };
    }
    /// Release all allocated memory.
    pub fn deinit(self: *Benchmark) void {
        self.tests.deinit();
        self.results.deinit();
    }
    /// Add a function to the test suite.
    pub fn add(self: *Benchmark, name: []const u8, function: CallbackFn) !void {
        try self.tests.append(.{ .name = name, .function = function });
    }
    fn measure(self: *Benchmark, t: Test) !Result {
        var result = Result{ .name = t.name };
        while (result.total < self.config.budget or result.iterations < self.config.iterations) {
            var timer = try std.time.Timer.start();
            try t.function();
            var taken = timer.lap();
            result.total += taken;
            result.iterations += 1;
            taken = taken -| self.noop;
            if (taken < result.min) result.min = taken;
            if (taken > result.max) result.max = taken;
        }
        result.avg = @intCast((result.total / result.iterations) -| self.noop);
        return result;
    }
    fn warmup(self: *Benchmark) !void {
        if (!self.config.enable_warmup) return;
        if (self.config.show_output) try self.stdout.print("Warming up...\r", .{});
        const noop_time = try self.measure(.{ .name = "warmup", .function = noop });
        self.noop = @intCast(noop_time.total / noop_time.iterations);
    }
    fn printHeader(self: *Benchmark) !void {
        if (!self.config.show_output) return;
        comptime var cham = Chameleon.init(.Auto);
        if (self.config.show_cpu_name) {
            try self.stdout.print(cham.gray().fmt("{s} {s}\n"), .{ cham.bold().fmt("cpu:"), self.cpu });
        }
        if (self.config.show_zig_version) {
            try self.stdout.print(cham.gray().fmt("{s} {s}\n"), .{ cham.bold().fmt("zig:"), builtin.zig_version_string });
        }
        try self.stdout.print(cham.bold().fmt("\nBenchmark\t\tTime (avg)\tIterations\t({s} … {s})\n" ++ "─" ** 80 ++ "\n"), .{
            cham.cyan().fmt("min"),
            cham.magenta().fmt("max"),
        });
    }
    fn printResult(self: *Benchmark, result: Result) !void {
        if (!self.config.show_output) return;
        comptime var cham = Chameleon.init(.Auto);
        try self.stdout.print("{s: <23}\t" ++ cham.yellow().fmt("{: <15}\t") ++ "{: <15}\t(" ++ cham.cyan().fmt("{}") ++ " … " ++ cham.magenta().fmt("{}") ++ ")\n", .{
            result.name,
            std.fmt.fmtDuration(result.avg),
            fmtIntu32(result.iterations),
            std.fmt.fmtDuration(result.min),
            std.fmt.fmtDuration(result.max),
        });
    }
    fn printSummary(self: *Benchmark) !void {
        if (!self.config.show_output or !self.config.show_summary) return;
        comptime var cham = Chameleon.init(.Auto);
        try self.stdout.print(cham.bold().fmt("\nSummary\n") ++ "─" ** 80 ++ cham.green().fmt("\n{s}") ++ " ran fastest\n", .{self.results.items[0].name});
        if (!self.config.show_summary_comparison) return;
        for (self.results.items[1..]) |item| {
            const timesFaster = @as(f64, @floatFromInt(item.avg)) / @as(f64, @floatFromInt(self.results.items[0].avg));
            try self.stdout.print(" └─ " ++ cham.bold().greenBright().fmt("{d:.2}") ++ " times faster than " ++ cham.blue().fmt("{s}\n"), .{ timesFaster, item.name });
        }
    }
    fn exportJSON(self: *Benchmark) !void {
        if (self.config.export_json == null) return;
        const file = try std.fs.cwd().createFile(self.config.export_json.?, .{});
        defer file.close();
        const writer = file.writer();
        _ = try writer.write("{\n");
        if (self.config.show_cpu_name) _ = try writer.print("    \"cpu\": \"{s}\",\n", .{self.cpu});
        if (self.config.show_zig_version) _ = try writer.print("    \"zig\": \"{s}\",\n", .{builtin.zig_version_string});
        _ = try writer.write("    \"results\": [\n");
        for (self.results.items, 0..) |item, i| {
            _ = try writer.print(
                \\        {{
                \\            "name": "{s}",
                \\            "iterations": {},
                \\            "totalTime": {},
                \\            "avgTime": {},
                \\            "min": {},
                \\            "max": {}
                \\        }}
            , .{ item.name, item.iterations, item.total, item.avg, item.min, item.max });
            _ = try writer.write(if (i == self.results.items.len - 1) "\n" else ",\n");
        }
        _ = try writer.write("    ]\n}");
    }
    /// Start the benchmark.
    pub fn run(self: *Benchmark) !void {
        if (self.tests.items.len == 0) return error.NoTestsAdded;
        try self.warmup();
        if (self.config.show_cpu_name) self.cpu = try getCpuName(self.allocator);
        try self.printHeader();
        try self.config.hooks.beforeAll();
        for (self.tests.items) |item| {
            try self.config.hooks.beforeEach();
            if (self.config.show_output) {
                comptime var cham = Chameleon.init(.Auto);
                try self.stdout.print(cham.gray().fmt("Measuring {s}...\r"), .{item.name});
            }
            const measured = try self.measure(item);
            try self.results.append(measured);
            if (self.config.show_output) try self.stdout.print(" " ** 80 ++ "\r", .{});
            try self.printResult(measured);
            try self.config.hooks.afterEach();
        }
        try self.config.hooks.afterAll();
        std.mem.sort(Result, self.results.items, .{}, sortResult);
        try self.printSummary();
        try self.exportJSON();
    }
};
