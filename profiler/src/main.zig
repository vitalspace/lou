const std = @import("std");
const Io = std.Io;
const metrics = @import("metrics.zig");
const parsers = @import("parsers.zig");
const report = @import("report.zig");

const Comparison = metrics.Comparison;
const ProgramMetrics = metrics.ProgramMetrics;
const ProgramResult = metrics.ProgramResult;
const TimeMetrics = metrics.TimeMetrics;

const RuntimeConfig = struct {
    name: []const u8,
    cmd: []const []const u8,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const env_map = init.environ_map;

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var args_it = init.minimal.args.iterate();
    _ = args_it.next();
    var args = try parseArgs(&args_it, arena);
    if (args.command == .help) {
        try printUsage(io);
        return;
    }

    const runtimes = if (args.runtimes.items.len > 0) args.runtimes.items else blk: {
        try args.runtimes.append(arena, RuntimeConfig{ .name = "Lou", .cmd = &.{ "lou", "run" } });
        try args.runtimes.append(arena, RuntimeConfig{ .name = "Node", .cmd = &.{"node"} });
        break :blk args.runtimes.items;
    };

    if (Io.Dir.cwd().access(io, args.file_path, .{})) |_| {
        // file exists
    } else |_| {
        printErr(io, "Error: file not found: {s}\n", .{args.file_path});
        std.process.exit(1);
    }

    const runs: u32 = args.runs orelse if (std.mem.eql(u8, args.mode, "quick")) 1 else 50;

    const results = try arena.alloc(ProgramResult, runtimes.len);
    for (runtimes, 0..) |rt, i| {
        const bin = try resolveBin(arena, io, env_map, rt.cmd[0]);
        var cmd = try std.ArrayList([]const u8).initCapacity(arena, rt.cmd.len + 1);
        try cmd.append(arena, bin);
        for (rt.cmd[1..]) |part| try cmd.append(arena, part);
        try cmd.append(arena, args.file_path);

        if (args.verbose) {
            printErr(io, "Running {s}...\n", .{rt.name});
        }

        var prog_metrics = try benchOne(arena, io, cmd.items, runs);

        if (args.perf) {
            if (args.verbose) {
                printErr(io, "Running perf stat for {s}...\n", .{rt.name});
            }
            prog_metrics.perf = runPerfStat(gpa, io, cmd.items) catch blk: {
                printErr(io, "Warning: perf stat failed for {s} (is perf installed?)\n", .{rt.name});
                break :blk metrics.PerfMetrics{};
            };
        }

        results[i] = ProgramResult{
            .name = rt.name,
            .metrics = prog_metrics,
        };
    }

    const comp = Comparison{
        .results = results,
        .file_path = args.file_path,
        .mode = args.mode,
    };

    var buf: [8192]u8 = undefined;
    var file_writer = std.Io.File.Writer.init(.stdout(), io, &buf);
    const out = &file_writer.interface;
    try report.formatReport(comp, out, !args.no_color);
    try file_writer.flush();

    if (args.save) |save_path| {
        const json = try report.formatJSON(comp, arena);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = save_path, .data = json });
    }
}

fn printErr(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    var fw = std.Io.File.Writer.init(.stderr(), io, &buf);
    fw.interface.print(fmt, args) catch {};
    fw.flush() catch {};
}

const Args = struct {
    command: enum { bench, help },
    file_path: []const u8 = "",
    mode: []const u8 = "quick",
    runs: ?u32 = null,
    runtimes: std.ArrayList(RuntimeConfig),
    no_color: bool = false,
    save: ?[]const u8 = null,
    verbose: bool = false,
    perf: bool = false,
};

fn parseArgs(it: *std.process.Args.Iterator, arena: std.mem.Allocator) !Args {
    var result = Args{ .command = .help, .runtimes = std.ArrayList(RuntimeConfig).initCapacity(arena, 4) catch unreachable };
    var args = std.ArrayList([]const u8).initCapacity(arena, 16) catch unreachable;
    while (it.next()) |arg| try args.append(arena, arg);
    if (args.items.len == 0) return result;

    const cmd = args.items[0];
    const cmd_is_flag = std.mem.startsWith(u8, cmd, "--");
    if (std.mem.eql(u8, cmd, "bench")) {
        result.command = .bench;
    } else if (!cmd_is_flag) {
        result.file_path = cmd;
        result.command = .bench;
    } else {
        result.command = .bench;
    }

    var i: usize = if (cmd_is_flag) 0 else 1;
    while (i < args.items.len) : (i += 1) {
        const arg = args.items[i];
        if (std.mem.eql(u8, arg, "--runs")) {
            i += 1;
            result.runs = if (i < args.items.len)
                std.fmt.parseInt(u32, args.items[i], 10) catch null
            else
                null;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            i += 1;
            result.mode = if (i < args.items.len) args.items[i] else "quick";
        } else if (std.mem.eql(u8, arg, "--run")) {
            i += 1;
            if (i < args.items.len) {
                const spec = args.items[i];
                if (std.mem.indexOfScalar(u8, spec, ':')) |colon| {
                    const name = spec[0..colon];
                    const cmd_str = spec[colon + 1 ..];
                    var parts = std.ArrayList([]const u8).initCapacity(arena, 4) catch unreachable;
                    var rest = cmd_str;
                    while (std.mem.indexOfScalar(u8, rest, ' ')) |space| {
                        try parts.append(arena, rest[0..space]);
                        rest = rest[space + 1 ..];
                    }
                    try parts.append(arena, rest);
                    try result.runtimes.append(arena, RuntimeConfig{ .name = name, .cmd = try parts.toOwnedSlice(arena) });
                } else {
                    try result.runtimes.append(arena, RuntimeConfig{ .name = spec, .cmd = &.{spec} });
                }
            }
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            result.no_color = true;
        } else if (std.mem.eql(u8, arg, "--save")) {
            i += 1;
            if (i < args.items.len) result.save = args.items[i];
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            result.verbose = true;
        } else if (std.mem.eql(u8, arg, "--perf")) {
            result.perf = true;
        } else if (result.file_path.len == 0 and !std.mem.startsWith(u8, arg, "--") and !std.mem.eql(u8, arg, "bench")) {
            result.file_path = arg;
        }
    }

    if (result.file_path.len == 0 and result.command != .help) {
        result.command = .help;
    }
    return result;
}

fn printUsage(io: std.Io) !void {
    var buf: [4096]u8 = undefined;
    var fw = std.Io.File.Writer.init(.stdout(), io, &buf);
    const w = &fw.interface;
    try w.writeAll(
        \\Profiler — Benchmark any runtime
        \\Usage:
        \\  profiler <file.js> [opts]
        \\  profiler bench <file.js> [opts]
        \\
        \\Options:
        \\  --run <name>:<cmd>    Add runtime (repeatable). E.g.:
        \\                          --run Lou:"lou run"
        \\                          --run Node:node
        \\                          --run Bun:bun
        \\                        Default: Lou (lou run) + Node (node)
        \\  --mode quick|deep     Profiling depth (default: quick)
        \\  --runs <n>            Override the number of measured runs
        \\  --no-color            Disable ANSI colors
        \\  --save <file.json>    Save results as JSON
        \\  --perf                Run perf stat for hardware counters
        \\  -v, --verbose         Verbose output
        \\
    );
    try fw.flush();
}

fn findBin(io: std.Io, env_map: *std.process.Environ.Map, name: []const u8) bool {
    if (name.len > 0 and name[0] == '/') {
        Io.Dir.accessAbsolute(io, name, .{}) catch return false;
        return true;
    }
    const path_env = env_map.get("PATH") orelse return false;
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        var buf: [4096]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, name }) catch continue;
        Io.Dir.accessAbsolute(io, full, .{}) catch continue;
        return true;
    }
    return false;
}

fn resolveBin(arena: std.mem.Allocator, io: std.Io, env_map: *std.process.Environ.Map, name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return name;

    if (findBin(io, env_map, name)) return name;

    const cwd = Io.Dir.cwd();
    const probes: []const []const u8 = &.{ "./zig-out/bin/", "../zig-out/bin/" };
    for (probes) |prefix| {
        const spawn_path = try std.fmt.allocPrint(arena, "{s}{s}", .{ prefix, name });
        cwd.access(io, spawn_path, .{}) catch continue;
        return spawn_path;
    }

    return name;
}

fn benchOne(arena: std.mem.Allocator, io: std.Io, argv: []const []const u8, runs: u32) !ProgramMetrics {
    var result = ProgramMetrics{};
    if (runs <= 1) {
        result.time = try runAndGetRusage(arena, io, argv);
        return result;
    }
    const samples = try arena.alloc(TimeMetrics, runs);
    for (samples) |*s| {
        s.* = try runAndGetRusage(arena, io, argv);
    }
    result.samples = samples;
    const stats = metrics.computeStats(samples);
    result.time = TimeMetrics{
        .wall_time_ns = stats.median_wall_ns,
        .user_cpu_ns = stats.median_user_cpu_ns,
        .kernel_cpu_ns = stats.median_kernel_cpu_ns,
        .max_rss_bytes = stats.max_rss,
        .minor_page_faults = stats.median_minor_faults,
        .major_page_faults = stats.median_major_faults,
        .vol_context_switches = stats.median_vol_ctx_switches,
        .invol_context_switches = stats.median_invol_ctx_switches,
    };
    return result;
}

fn runAndGetRusage(_: std.mem.Allocator, io: std.Io, argv: []const []const u8) !TimeMetrics {
    const start = Io.Timestamp.now(io, .awake);

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
        .request_resource_usage_statistics = true,
    });
    defer {
        if (child.id != null) child.kill(io);
    }

    const term = child.wait(io) catch {
        return TimeMetrics{ .timed_out = true };
    };

    const elapsed = start.untilNow(io, .awake);
    var t = TimeMetrics{ .wall_time_ns = @intCast(elapsed.nanoseconds) };

    switch (term) {
        .exited => |code| t.exit_code = code,
        .signal => |sig| {
            t.exit_code = 128 + @intFromEnum(sig);
        },
        else => {},
    }

    if (child.resource_usage_statistics.rusage) |ru| {
        t.user_cpu_ns = timevalToNs(ru.utime);
        t.kernel_cpu_ns = timevalToNs(ru.stime);
        if (child.resource_usage_statistics.getMaxRss()) |rss| {
            t.max_rss_bytes = rss;
        }
        t.minor_page_faults = @intCast(@max(ru.minflt, 0));
        t.major_page_faults = @intCast(@max(ru.majflt, 0));
        t.vol_context_switches = @intCast(@max(ru.nvcsw, 0));
        t.invol_context_switches = @intCast(@max(ru.nivcsw, 0));
    }

    return t;
}

fn timevalToNs(tv: anytype) u64 {
    const sec = @as(u64, @intCast(@max(tv.sec, 0)));
    const usec = @as(u64, @intCast(@max(tv.usec, 0)));
    return sec * 1_000_000_000 + usec * 1_000;
}

fn runPerfStat(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8) !metrics.PerfMetrics {
    var perf_argv = try std.ArrayList([]const u8).initCapacity(gpa, argv.len + 3);
    defer perf_argv.deinit(gpa);
    try perf_argv.append(gpa, "perf");
    try perf_argv.append(gpa, "stat");
    try perf_argv.append(gpa, "-d");
    for (argv) |part| try perf_argv.append(gpa, part);

    var child = try std.process.spawn(io, .{
        .argv = perf_argv.items,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
    });
    defer {
        if (child.id != null) child.kill(io);
    }

    var read_buf: [4096]u8 = undefined;
    var stderr_reader = Io.File.reader(child.stderr.?, io, &read_buf);
    const stderr_data = try stderr_reader.interface.allocRemaining(gpa, Io.Limit.limited(1024 * 1024));
    defer gpa.free(stderr_data);

    _ = child.wait(io) catch {};

    return parsers.parsePerfStatOutput(stderr_data);
}
