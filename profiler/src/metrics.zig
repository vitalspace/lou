const std = @import("std");

pub const TimeMetrics = struct {
    wall_time_ns: u64 = 0,
    user_cpu_ns: u64 = 0,
    kernel_cpu_ns: u64 = 0,
    max_rss_bytes: u64 = 0,
    minor_page_faults: u64 = 0,
    major_page_faults: u64 = 0,
    vol_context_switches: u64 = 0,
    invol_context_switches: u64 = 0,
    exit_code: u32 = 0,
    timed_out: bool = false,
};

pub const PerfMetrics = struct {
    cycles: u64 = 0,
    instructions: u64 = 0,
    cache_misses: u64 = 0,
    branch_misses: u64 = 0,
    cache_refs: u64 = 0,
    branches: u64 = 0,
    stalled_frontend: u64 = 0,
    stalled_backend: u64 = 0,
    ipc: f64 = 0,
};

pub const PerfFunction = struct {
    overhead_pct: f64,
    symbol: []const u8,
    source: []const u8,
};

pub const RunStats = struct {
    median_wall_ns: u64,
    min_wall_ns: u64,
    max_wall_ns: u64,
    median_rss: u64,
    min_rss: u64,
    max_rss: u64,
    median_cpu_ns: u64,
    median_user_cpu_ns: u64,
    median_kernel_cpu_ns: u64,
    median_minor_faults: u64,
    median_major_faults: u64,
    median_vol_ctx_switches: u64,
    median_invol_ctx_switches: u64,
    min_cpu_ns: u64,
    max_cpu_ns: u64,
    stddev_wall_ns: u64,
    run_count: usize,
};

pub fn computeStats(samples: []const TimeMetrics) RunStats {
    // Fixed-capacity scratch buffers: keep 256 slots so larger run counts do
    // not overflow, and clamp defensively to the buffer size.
    var wall_vals: [256]u64 = undefined;
    var rss_vals: [256]u64 = undefined;
    var cpu_vals: [256]u64 = undefined;
    var user_vals: [256]u64 = undefined;
    var kernel_vals: [256]u64 = undefined;
    var minor_vals: [256]u64 = undefined;
    var major_vals: [256]u64 = undefined;
    var vol_vals: [256]u64 = undefined;
    var invol_vals: [256]u64 = undefined;
    var n: usize = 0;
    for (samples) |s| {
        if (n >= wall_vals.len) break;
        wall_vals[n] = s.wall_time_ns;
        rss_vals[n] = s.max_rss_bytes;
        cpu_vals[n] = s.user_cpu_ns + s.kernel_cpu_ns;
        user_vals[n] = s.user_cpu_ns;
        kernel_vals[n] = s.kernel_cpu_ns;
        minor_vals[n] = s.minor_page_faults;
        major_vals[n] = s.major_page_faults;
        vol_vals[n] = s.vol_context_switches;
        invol_vals[n] = s.invol_context_switches;
        n += 1;
    }
    if (n == 0) return RunStats{
        .median_wall_ns = 0, .min_wall_ns = 0, .max_wall_ns = 0,
        .median_rss = 0, .min_rss = 0, .max_rss = 0,
        .median_cpu_ns = 0, .median_user_cpu_ns = 0, .median_kernel_cpu_ns = 0,
        .median_minor_faults = 0, .median_major_faults = 0,
        .median_vol_ctx_switches = 0, .median_invol_ctx_switches = 0,
        .min_cpu_ns = 0, .max_cpu_ns = 0, .stddev_wall_ns = 0, .run_count = 0,
    };
    const wall_sorted = sortAsc(wall_vals[0..n]);
    const rss_sorted = sortAsc(rss_vals[0..n]);
    const cpu_sorted = sortAsc(cpu_vals[0..n]);
    const user_sorted = sortAsc(user_vals[0..n]);
    const kernel_sorted = sortAsc(kernel_vals[0..n]);
    const minor_sorted = sortAsc(minor_vals[0..n]);
    const major_sorted = sortAsc(major_vals[0..n]);
    const vol_sorted = sortAsc(vol_vals[0..n]);
    const invol_sorted = sortAsc(invol_vals[0..n]);

    const mid = wall_sorted.len / 2;
    return RunStats{
        .median_wall_ns = wall_sorted[mid],
        .min_wall_ns = wall_sorted[0],
        .max_wall_ns = wall_sorted[wall_sorted.len - 1],
        .median_rss = rss_sorted[mid],
        .min_rss = rss_sorted[0],
        .max_rss = rss_sorted[rss_sorted.len - 1],
        .median_cpu_ns = cpu_sorted[mid],
        .median_user_cpu_ns = user_sorted[mid],
        .median_kernel_cpu_ns = kernel_sorted[mid],
        .median_minor_faults = minor_sorted[mid],
        .median_major_faults = major_sorted[mid],
        .median_vol_ctx_switches = vol_sorted[mid],
        .median_invol_ctx_switches = invol_sorted[mid],
        .min_cpu_ns = cpu_sorted[0],
        .max_cpu_ns = cpu_sorted[cpu_sorted.len - 1],
        .stddev_wall_ns = computeStddev(wall_sorted),
        .run_count = n,
    };
}

fn sortAsc(buf: []u64) []u64 {
    std.mem.sort(u64, buf, {}, std.sort.asc(u64));
    return buf;
}

fn computeStddev(values: []const u64) u64 {
    if (values.len < 2) return 0;
    var sum: u64 = 0;
    for (values) |v| sum += v;
    const mean = sum / values.len;
    var variance_sum: u128 = 0;
    for (values) |v| {
        const diff = if (v > mean) v - mean else mean - v;
        variance_sum += @as(u128, diff) * @as(u128, diff);
    }
    const variance = variance_sum / values.len;
    return @intCast(@as(u64, @intCast(std.math.sqrt(variance))));
}

pub const ProgramMetrics = struct {
    time: TimeMetrics = .{},
    samples: []TimeMetrics = &.{},
    perf: PerfMetrics = .{},
    perf_functions: []PerfFunction = &.{},
};

pub const ProgramResult = struct {
    name: []const u8,
    metrics: ProgramMetrics,
};

pub const Comparison = struct {
    results: []ProgramResult,
    file_path: []const u8,
    mode: []const u8,

    pub fn ratio(a: anytype, b: anytype) f64 {
        if (b == 0) return 0;
        return @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b));
    }

    pub fn ratioFloat(a: f64, b: f64) f64 {
        if (b == 0) return 0;
        return a / b;
    }
};
