const std = @import("std");
const metrics = @import("metrics.zig");
const Comparison = metrics.Comparison;
const ProgramResult = metrics.ProgramResult;
const PerfFunction = metrics.PerfFunction;

const Color = enum { reset, red, yellow, green, cyan, bold };

fn colorStr(writer: anytype, clr: Color, use: bool) !void {
    if (!use) return;
    try writer.writeAll(switch (clr) {
        .reset => "\x1b[0m",
        .red => "\x1b[31m",
        .yellow => "\x1b[33m",
        .green => "\x1b[32m",
        .cyan => "\x1b[36m",
        .bold => "\x1b[1m",
    });
}

fn fmtDur(writer: anytype, ns: u64) !void {
    if (ns >= 1_000_000_000) {
        try writer.print("{d:>7.2}s", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000});
    } else if (ns >= 1_000_000) {
        try writer.print("{d:>7.2}ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
    } else if (ns >= 1_000) {
        try writer.print("{d:>7.2}µs", .{@as(f64, @floatFromInt(ns)) / 1_000});
    } else {
        try writer.print("{d:>7}ns ", .{ns});
    }
}

fn fmtBytes(writer: anytype, bytes: u64) !void {
    if (bytes >= 1_000_000_000) {
        try writer.print("{d:>7.2}GB", .{@as(f64, @floatFromInt(bytes)) / 1_000_000_000});
    } else if (bytes >= 1_000_000) {
        try writer.print("{d:>7.2}MB", .{@as(f64, @floatFromInt(bytes)) / 1_000_000});
    } else if (bytes >= 1_000) {
        try writer.print("{d:>7.2}KB", .{@as(f64, @floatFromInt(bytes)) / 1_000});
    } else {
        try writer.print("{d:>7}B  ", .{bytes});
    }
}

fn fmtCount(writer: anytype, count: u64) !void {
    if (count >= 1_000_000_000) {
        try writer.print("{d:>7.2} B", .{@as(f64, @floatFromInt(count)) / 1_000_000_000});
    } else if (count >= 1_000_000) {
        try writer.print("{d:>7.2} M", .{@as(f64, @floatFromInt(count)) / 1_000_000});
    } else if (count >= 1_000) {
        try writer.print("{d:>7.2} K", .{@as(f64, @floatFromInt(count)) / 1_000});
    } else {
        try writer.print("{d:>7}  ", .{count});
    }
}

fn fmtRatio(writer: anytype, ratio: f64) !void {
    const r = if (ratio >= 100.0) @as(f64, @floatFromInt(@as(u64, @intFromFloat(ratio)))) else blk: {
        const rounded = @round(ratio * 10.0) / 10.0;
        break :blk rounded;
    };
    try writer.print("{d:>8.1}x", .{r});
}

fn ratioColor(ratio: f64) Color {
    return if (ratio > 5.0) .red else if (ratio > 2.0) .yellow else .green;
}

fn barColor(is_fastest: bool, is_slowest: bool) Color {
    if (is_fastest) return .green;
    if (is_slowest) return .red;
    return .yellow;
}

fn drawBar(writer: anytype, name: []const u8, value: u64, max_value: u64, max_width: usize, clr: Color, use_color: bool) !void {
    try writer.print("  {s:>8} ", .{name});
    const bar_len = if (max_value == 0) 0 else (value * max_width) / max_value;
    const clamped = @min(bar_len, max_width);
    try colorStr(writer, clr, use_color);
    var i: usize = 0;
    while (i < clamped) : (i += 1) {
        try writer.writeAll("█");
    }
    try colorStr(writer, .reset, use_color);
    try writer.writeAll(" ");
}

pub fn formatBarChart(writer: anytype, comp: Comparison, use_color: bool) !void {
    if (comp.results.len < 2) return;

    const max_width: usize = 40;

    // Wall time bars
    try colorStr(writer, .bold, use_color);
    try writer.print("  Wall Time\n", .{});
    try colorStr(writer, .reset, use_color);

    var max_wall: u64 = 0;
    for (comp.results) |r| {
        if (r.metrics.time.wall_time_ns > max_wall) max_wall = r.metrics.time.wall_time_ns;
    }
    const fastest_idx = fastest(comp.results);
    const slowest_idx = slowest(comp.results);

    for (comp.results, 0..) |r, i| {
        const clr = barColor(i == fastest_idx, i == slowest_idx);
        try drawBar(writer, r.name, r.metrics.time.wall_time_ns, max_wall, max_width, clr, use_color);
        try fmtDur(writer, r.metrics.time.wall_time_ns);
        try writer.print("\n", .{});
    }
    try writer.print("\n", .{});

    // Memory bars
    try colorStr(writer, .bold, use_color);
    try writer.print("  Memory (RSS)\n", .{});
    try colorStr(writer, .reset, use_color);

    var max_rss: u64 = 0;
    for (comp.results) |r| {
        if (r.metrics.time.max_rss_bytes > max_rss) max_rss = r.metrics.time.max_rss_bytes;
    }
    const best_rss_idx = bestRss(comp.results);
    const worst_rss_idx = worstRss(comp.results);

    for (comp.results, 0..) |r, i| {
        const clr = barColor(i == best_rss_idx, i == worst_rss_idx);
        try drawBar(writer, r.name, r.metrics.time.max_rss_bytes, max_rss, max_width, clr, use_color);
        try fmtBytes(writer, r.metrics.time.max_rss_bytes);
        try writer.print("\n", .{});
    }
    try writer.print("\n", .{});

    // CPU bars
    try colorStr(writer, .bold, use_color);
    try writer.print("  CPU (user + kernel)\n", .{});
    try colorStr(writer, .reset, use_color);

    var max_cpu: u64 = 0;
    for (comp.results) |r| {
        const cpu = r.metrics.time.user_cpu_ns + r.metrics.time.kernel_cpu_ns;
        if (cpu > max_cpu) max_cpu = cpu;
    }

    var best_cpu_idx: usize = 0;
    var worst_cpu_idx: usize = 0;
    var best_cpu: u64 = comp.results[0].metrics.time.user_cpu_ns + comp.results[0].metrics.time.kernel_cpu_ns;
    var worst_cpu: u64 = best_cpu;
    for (comp.results, 0..) |r, i| {
        const cpu = r.metrics.time.user_cpu_ns + r.metrics.time.kernel_cpu_ns;
        if (cpu < best_cpu) { best_cpu = cpu; best_cpu_idx = i; }
        if (cpu > worst_cpu) { worst_cpu = cpu; worst_cpu_idx = i; }
    }

    for (comp.results, 0..) |r, i| {
        const cpu = r.metrics.time.user_cpu_ns + r.metrics.time.kernel_cpu_ns;
        const clr = barColor(i == best_cpu_idx, i == worst_cpu_idx);
        try drawBar(writer, r.name, cpu, max_cpu, max_width, clr, use_color);
        try fmtDur(writer, cpu);
        try writer.print("\n", .{});
    }
    try writer.print("\n", .{});
}

pub fn formatReport(comp: Comparison, writer: anytype, use_color: bool) !void {
    try colorStr(writer, .cyan, use_color);
    try writer.print("\n═══ PROFILER ═══════════════════════════════════\n", .{});
    try colorStr(writer, .reset, use_color);
    try writer.print("  File:  {s}\n", .{comp.file_path});
    try writer.print("  Mode:     {s}\n", .{comp.mode});
    if (comp.results.len > 0) {
        const fastest_idx = fastest(comp.results);
        const fastest_name = comp.results[fastest_idx].name;
        const fastest_wall = comp.results[fastest_idx].metrics.time.wall_time_ns;
        const slowest_idx = slowest(comp.results);
        const slowest_wall = comp.results[slowest_idx].metrics.time.wall_time_ns;
        const factor = @as(f64, @floatFromInt(slowest_wall)) / @as(f64, @floatFromInt(fastest_wall));
        try writer.print("  Winner:  {s} ({d:.1}x faster)\n", .{ fastest_name, factor });
        try writer.print("\n", .{});
        try writer.writeAll("    ");
        try colorStr(writer, .green, use_color);
        try writer.print(" * ", .{});
        try colorStr(writer, .reset, use_color);
        try writer.print(" = fastest    ", .{});
        try colorStr(writer, .yellow, use_color);
        try writer.print(" * ", .{});
        try colorStr(writer, .reset, use_color);
        try writer.print(" = middle     ", .{});
        try colorStr(writer, .red, use_color);
        try writer.print(" * ", .{});
        try colorStr(writer, .reset, use_color);
        try writer.print(" = slowest\n", .{});
    }
    try writer.print("\n", .{});

    for (comp.results) |r| {
        try colorStr(writer, .bold, use_color);
        try writer.print("  {s} {s:-<30}\n", .{ r.name, " " });
        try colorStr(writer, .reset, use_color);
        try writer.writeAll("    Total time (wall):  ");
        try fmtDur(writer, r.metrics.time.wall_time_ns);
        try writer.print("\n", .{});
        try writer.writeAll("    CPU (user + kernel): ");
        try fmtDur(writer, r.metrics.time.user_cpu_ns + r.metrics.time.kernel_cpu_ns);
        try writer.print("\n", .{});
        try writer.writeAll("    Memory (RSS max):   ");
        try fmtBytes(writer, r.metrics.time.max_rss_bytes);
        try writer.print("\n", .{});

        if (r.metrics.samples.len > 1) {
            const st = metrics.computeStats(r.metrics.samples);
            try writer.print("    Runs:                {d}\n", .{st.run_count});
            try writer.writeAll("    Wall (min/med/max):  ");
            try fmtDur(writer, st.min_wall_ns);
            try writer.writeAll(" / ");
            try fmtDur(writer, st.median_wall_ns);
            try writer.writeAll(" / ");
            try fmtDur(writer, st.max_wall_ns);
            try writer.print("\n", .{});
            try writer.writeAll("    CPU user/kernel (med): ");
            try fmtDur(writer, st.median_user_cpu_ns);
            try writer.writeAll(" / ");
            try fmtDur(writer, st.median_kernel_cpu_ns);
            try writer.print("\n", .{});
            try writer.writeAll("    Std deviation:");
            try fmtDur(writer, st.stddev_wall_ns);
            try writer.print("\n", .{});
            try writer.writeAll("    RSS (min/med/max):   ");
            try fmtBytes(writer, st.min_rss);
            try writer.writeAll(" / ");
            try fmtBytes(writer, st.median_rss);
            try writer.writeAll(" / ");
            try fmtBytes(writer, st.max_rss);
            try writer.print("\n", .{});
        } else {
            try writer.writeAll("    Page faults:         ");
            try fmtCount(writer, r.metrics.time.minor_page_faults + r.metrics.time.major_page_faults);
            try writer.print("\n", .{});
            try writer.print("    Context switches:  {d}\n", .{r.metrics.time.vol_context_switches + r.metrics.time.invol_context_switches});
        }
        try writer.print("\n", .{});
    }

    if (comp.results.len >= 2) {
        const ref = comp.results[0];
        try colorStr(writer, .bold, use_color);
        try writer.print("  Comparison (vs {s}) ------\n", .{ref.name});
        try colorStr(writer, .reset, use_color);
        for (comp.results[1..]) |r| {
            const wall_r = Comparison.ratio(r.metrics.time.wall_time_ns, ref.metrics.time.wall_time_ns);
            const cpu_r = Comparison.ratio(r.metrics.time.user_cpu_ns + r.metrics.time.kernel_cpu_ns, ref.metrics.time.user_cpu_ns + ref.metrics.time.kernel_cpu_ns);
            const mem_r = Comparison.ratio(r.metrics.time.max_rss_bytes, ref.metrics.time.max_rss_bytes);
            try writer.print("  {s}:\n", .{r.name});
            try colorStr(writer, ratioColor(wall_r), use_color);
            try writer.writeAll("    Wall time:  ");
            try fmtRatio(writer, wall_r);
            try colorStr(writer, .reset, use_color);
            try writer.print("\n", .{});
            try colorStr(writer, ratioColor(cpu_r), use_color);
            try writer.writeAll("    CPU total:  ");
            try fmtRatio(writer, cpu_r);
            try colorStr(writer, .reset, use_color);
            try writer.print("\n", .{});
            try colorStr(writer, ratioColor(mem_r), use_color);
            try writer.writeAll("    Memory:    ");
            try fmtRatio(writer, mem_r);
            try colorStr(writer, .reset, use_color);
            try writer.print("\n", .{});
        }
        try writer.print("\n", .{});
    }

    // Visual bar chart comparison
    try colorStr(writer, .cyan, use_color);
    try writer.print("── Visual Comparison ──\n", .{});
    try colorStr(writer, .reset, use_color);
    try formatBarChart(writer, comp, use_color);

    const has_perf = blk: {
        for (comp.results) |r| {
            if (r.metrics.perf.instructions > 0) break :blk true;
        }
        break :blk false;
    };
    if (has_perf) {
        try colorStr(writer, .cyan, use_color);
        try writer.print("── Hardware counters (perf) ──\n", .{});
        try colorStr(writer, .reset, use_color);
        for (comp.results) |r| {
            const p = &r.metrics.perf;
            try writer.print("  {s}:\n", .{r.name});
            try writer.writeAll("    Instructions: "); try fmtCount(writer, p.instructions); try writer.print("\n", .{});
            try writer.writeAll("    Cycles:       "); try fmtCount(writer, p.cycles); try writer.print("\n", .{});
            try writer.print("    IPC:          {d:.2}\n", .{p.ipc});
            try writer.writeAll("    Cache misses: "); try fmtCount(writer, p.cache_misses); try writer.print("\n", .{});
            try writer.writeAll("    Branch misses:"); try fmtCount(writer, p.branch_misses); try writer.print("\n", .{});
        }
        try writer.print("\n", .{});

        // Perf bar charts
        try colorStr(writer, .bold, use_color);
        try writer.print("  IPC Comparison\n", .{});
        try colorStr(writer, .reset, use_color);
        var max_ipc: f64 = 0;
        for (comp.results) |r| {
            if (r.metrics.perf.ipc > max_ipc) max_ipc = r.metrics.perf.ipc;
        }
        var best_ipc_idx: usize = 0;
        var worst_ipc_idx: usize = 0;
        for (comp.results, 0..) |r, i| {
            if (r.metrics.perf.ipc > comp.results[best_ipc_idx].metrics.perf.ipc) best_ipc_idx = i;
            if (r.metrics.perf.ipc < comp.results[worst_ipc_idx].metrics.perf.ipc) worst_ipc_idx = i;
        }
        for (comp.results, 0..) |r, i| {
            const bar_len: usize = if (max_ipc == 0) 0 else @intFromFloat(r.metrics.perf.ipc / max_ipc * 40);
            try writer.print("  {s:>8} ", .{r.name});
            const clr = barColor(i == best_ipc_idx, i == worst_ipc_idx);
            try colorStr(writer, clr, use_color);
            var j: usize = 0;
            while (j < bar_len) : (j += 1) {
                try writer.writeAll("█");
            }
            try colorStr(writer, .reset, use_color);
            try writer.print(" {d:.2}\n", .{r.metrics.perf.ipc});
        }
        try writer.print("\n", .{});
    }

    try colorStr(writer, .cyan, use_color);
    try writer.print("── Insights ──\n", .{});
    try colorStr(writer, .reset, use_color);
    try formatInsights(comp, writer, use_color);
    try writer.print("\n", .{});
}

fn fastest(results: []const ProgramResult) usize {
    var idx: usize = 0;
    var best = results[0].metrics.time.wall_time_ns;
    for (results, 0..) |r, i| {
        if (r.metrics.time.wall_time_ns < best) {
            best = r.metrics.time.wall_time_ns;
            idx = i;
        }
    }
    return idx;
}

fn slowest(results: []const ProgramResult) usize {
    var idx: usize = 0;
    var worst = results[0].metrics.time.wall_time_ns;
    for (results, 0..) |r, i| {
        if (r.metrics.time.wall_time_ns > worst) {
            worst = r.metrics.time.wall_time_ns;
            idx = i;
        }
    }
    return idx;
}

fn formatInsights(comp: Comparison, writer: anytype, use_color: bool) !void {
    if (comp.results.len < 2) return;
    const f = fastest(comp.results);
    const s = slowest(comp.results);
    const wall_r = @as(f64, @floatFromInt(comp.results[s].metrics.time.wall_time_ns)) / @as(f64, @floatFromInt(comp.results[f].metrics.time.wall_time_ns));

    const label = if (wall_r > 5.0) "🔴" else if (wall_r > 2.0) "🟡" else "🟢";
    if (wall_r > 2.0) {
        try colorStr(writer, .red, use_color);
        try writer.print("  {s} {s} is {d:.1}x slower than {s} in wall time\n", .{ label, comp.results[s].name, wall_r, comp.results[f].name });
        try colorStr(writer, .reset, use_color);
    } else {
        try colorStr(writer, .green, use_color);
        try writer.print("  {s} {s} is within {d:.1}x of {s} — good!\n", .{ label, comp.results[f].name, wall_r, comp.results[s].name });
        try colorStr(writer, .reset, use_color);
    }

    const best_rss = bestRss(comp.results);
    const worst_rss = worstRss(comp.results);
    if (best_rss != worst_rss) {
        const rss_r = @as(f64, @floatFromInt(comp.results[worst_rss].metrics.time.max_rss_bytes)) / @as(f64, @floatFromInt(comp.results[best_rss].metrics.time.max_rss_bytes));
        try colorStr(writer, .green, use_color);
        try writer.print("  {s} uses {d:.2}x less memory than {s}\n", .{ comp.results[best_rss].name, rss_r, comp.results[worst_rss].name });
        try colorStr(writer, .reset, use_color);
    }
}

fn bestRss(results: []const ProgramResult) usize {
    var idx: usize = 0;
    var best = results[0].metrics.time.max_rss_bytes;
    for (results, 0..) |r, i| {
        if (r.metrics.time.max_rss_bytes < best) {
            best = r.metrics.time.max_rss_bytes;
            idx = i;
        }
    }
    return idx;
}

fn worstRss(results: []const ProgramResult) usize {
    var idx: usize = 0;
    var worst = results[0].metrics.time.max_rss_bytes;
    for (results, 0..) |r, i| {
        if (r.metrics.time.max_rss_bytes > worst) {
            worst = r.metrics.time.max_rss_bytes;
            idx = i;
        }
    }
    return idx;
}

pub fn formatJSON(comp: Comparison, gpa: std.mem.Allocator) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(gpa, 4096);

    try buf.print(gpa, "{{\"file\":", .{});
    try writeJsonString(&buf, gpa, comp.file_path);
    try buf.print(gpa, ",\"mode\":", .{});
    try writeJsonString(&buf, gpa, comp.mode);

    // Winner
    if (comp.results.len > 0) {
        const fi = fastest(comp.results);
        const si = slowest(comp.results);
        const factor = @as(f64, @floatFromInt(comp.results[si].metrics.time.wall_time_ns)) /
            @as(f64, @floatFromInt(comp.results[fi].metrics.time.wall_time_ns));
        try buf.print(gpa, ",\"winner\":", .{});
        try writeJsonString(&buf, gpa, comp.results[fi].name);
        try buf.print(gpa, ",\"speedup_factor\":{d:.2}", .{factor});
    }

    try buf.print(gpa, ",\"results\":[", .{});
    for (comp.results, 0..) |r, i| {
        if (i > 0) try buf.print(gpa, ",", .{});
        try buf.print(gpa, "{{\"name\":", .{});
        try writeJsonString(&buf, gpa, r.name);
        try buf.print(gpa, ",\"wall_time_ns\":{d}", .{r.metrics.time.wall_time_ns});
        try buf.print(gpa, ",\"cpu_ns\":{d}", .{r.metrics.time.user_cpu_ns + r.metrics.time.kernel_cpu_ns});
        try buf.print(gpa, ",\"rss_bytes\":{d}", .{r.metrics.time.max_rss_bytes});
        try buf.print(gpa, ",\"user_cpu_ns\":{d}", .{r.metrics.time.user_cpu_ns});
        try buf.print(gpa, ",\"kernel_cpu_ns\":{d}", .{r.metrics.time.kernel_cpu_ns});
        try buf.print(gpa, ",\"minor_page_faults\":{d}", .{r.metrics.time.minor_page_faults});
        try buf.print(gpa, ",\"major_page_faults\":{d}", .{r.metrics.time.major_page_faults});
        try buf.print(gpa, ",\"page_faults\":{d}", .{r.metrics.time.minor_page_faults + r.metrics.time.major_page_faults});
        try buf.print(gpa, ",\"vol_ctx_switches\":{d}", .{r.metrics.time.vol_context_switches});
        try buf.print(gpa, ",\"invol_ctx_switches\":{d}", .{r.metrics.time.invol_context_switches});
        try buf.print(gpa, ",\"context_switches\":{d}", .{r.metrics.time.vol_context_switches + r.metrics.time.invol_context_switches});
        try buf.print(gpa, ",\"exit_code\":{d}", .{r.metrics.time.exit_code});

        // Every raw run sample, so charts can show real distributions.
        try buf.print(gpa, ",\"samples\":[", .{});
        for (r.metrics.samples, 0..) |s, si| {
            if (si > 0) try buf.print(gpa, ",", .{});
            try buf.print(gpa, "{{\"wall_ns\":{d},\"user_cpu_ns\":{d},\"kernel_cpu_ns\":{d},\"rss_bytes\":{d},\"page_faults\":{d},\"ctx_switches\":{d},\"exit_code\":{d}}}", .{
                s.wall_time_ns,
                s.user_cpu_ns,
                s.kernel_cpu_ns,
                s.max_rss_bytes,
                s.minor_page_faults + s.major_page_faults,
                s.vol_context_switches + s.invol_context_switches,
                s.exit_code,
            });
        }
        try buf.print(gpa, "]", .{});

        // Perf data
        const p = &r.metrics.perf;
        if (p.instructions > 0 or p.cycles > 0) {
            try buf.print(gpa, ",\"perf\":{{", .{});
            try buf.print(gpa, "\"instructions\":{d}", .{p.instructions});
            try buf.print(gpa, ",\"cycles\":{d}", .{p.cycles});
            try buf.print(gpa, ",\"ipc\":{d:.2}", .{p.ipc});
            try buf.print(gpa, ",\"cache_misses\":{d}", .{p.cache_misses});
            try buf.print(gpa, ",\"cache_refs\":{d}", .{p.cache_refs});
            try buf.print(gpa, ",\"branch_misses\":{d}", .{p.branch_misses});
            try buf.print(gpa, ",\"branches\":{d}", .{p.branches});
            try buf.print(gpa, ",\"stalled_frontend\":{d}", .{p.stalled_frontend});
            try buf.print(gpa, ",\"stalled_backend\":{d}", .{p.stalled_backend});
            try buf.print(gpa, "}}", .{});
        }

        // Stats for multi-run
        if (r.metrics.samples.len > 1) {
            const st = metrics.computeStats(r.metrics.samples);
            try buf.print(gpa, ",\"stats\":{{", .{});
            try buf.print(gpa, "\"runs\":{d}", .{st.run_count});
            try buf.print(gpa, ",\"median_wall_ns\":{d}", .{st.median_wall_ns});
            try buf.print(gpa, ",\"min_wall_ns\":{d}", .{st.min_wall_ns});
            try buf.print(gpa, ",\"max_wall_ns\":{d}", .{st.max_wall_ns});
            try buf.print(gpa, ",\"stddev_wall_ns\":{d}", .{st.stddev_wall_ns});
            try buf.print(gpa, ",\"median_rss\":{d}", .{st.median_rss});
            try buf.print(gpa, ",\"min_rss\":{d}", .{st.min_rss});
            try buf.print(gpa, ",\"max_rss\":{d}", .{st.max_rss});
            try buf.print(gpa, ",\"median_cpu_ns\":{d}", .{st.median_cpu_ns});
            try buf.print(gpa, ",\"min_cpu_ns\":{d}", .{st.min_cpu_ns});
            try buf.print(gpa, ",\"max_cpu_ns\":{d}", .{st.max_cpu_ns});
            try buf.print(gpa, ",\"median_user_cpu_ns\":{d}", .{st.median_user_cpu_ns});
            try buf.print(gpa, ",\"median_kernel_cpu_ns\":{d}", .{st.median_kernel_cpu_ns});
            try buf.print(gpa, "}}", .{});
        }

        try buf.print(gpa, "}}", .{});
    }
    try buf.print(gpa, "]}}", .{});
    return try buf.toOwnedSlice(gpa);
}

fn writeJsonString(buf: anytype, gpa: std.mem.Allocator, s: []const u8) !void {
    try buf.print(gpa, "\"", .{});
    for (s) |c| {
        switch (c) {
            '"' => try buf.print(gpa, "\\\"", .{}),
            '\\' => try buf.print(gpa, "\\\\", .{}),
            '\n' => try buf.print(gpa, "\\n", .{}),
            '\r' => try buf.print(gpa, "\\r", .{}),
            '\t' => try buf.print(gpa, "\\t", .{}),
            else => try buf.print(gpa, "{c}", .{c}),
        }
    }
    try buf.print(gpa, "\"", .{});
}
