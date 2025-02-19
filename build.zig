const std = @import("std");
const builtin = @import("builtin");
const gz = std.compress.gzip;

pub fn build(b: *std.Build) void {
//    const use_bundled = b.option(bool, "use_bundled", "Use the bundled SQLite") orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("s3db", .{
        .root_source_file = b.path("s3db.zig"),
        .imports = &.{
            .{
                .name = "sqlite",
                .module = sqlite.module("sqlite"),
            },
        },
    });

    const s3db_ext_module = switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .arm => "https://github.com/jrhy/s3db/releases/download/v0.1.64/s3db-v0.1.64-linux-arm-glibc.sqlite-ext.so.gz",
            .aarch64 => "https://github.com/jrhy/s3db/releases/download/v0.1.64/s3db-v0.1.64-linux-arm64-glibc.sqlite-ext.so.gz",
            .x86_64 => "https://github.com/jrhy/s3db/releases/download/v0.1.64/s3db-v0.1.64-linux-amd64-glibc.sqlite-ext.so.gz",
            else => @compileError("arch not currently supported"),
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "https://pub.dgv.dev.br/s3db-v0.1.64-macos-amd64.dylib.gz",
            else => @compileError("arch not currently supported"),
        },
        else => @compileError("platform not currently supported"),
    };
    fetch(b.allocator, s3db_ext_module) catch |err| {
        std.debug.print("fetch err: {?}", .{err});
        return;
    };
    const lib = b.addStaticLibrary(.{
        .name = "s3db",
        .root_source_file = b.path("s3db.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("sqlite", sqlite.module("sqlite"));
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("s3db.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("sqlite", sqlite.module("sqlite"));
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn is_alpine() bool {
    var file = std.fs.cwd().openFile("/etc/os-release", .{}) catch return false;
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (in_stream.readUntilDelimiterOrEof(&buf, '\n') catch "") |line| {
        return std.mem.containsAtLeast(u8, line, 1, "alpine");
    }
    return false;
}

// pub const std_options: std.Options = .{
//     .http_disable_tls = false,
// };

pub const std_options = struct {
    pub const http_disable_tls = false;
};

fn fetch(alloc: std.mem.Allocator, url: []const u8) !void {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();
    var buf: [10240]u8 = undefined;
    const uri = try std.Uri.parse(url);
    std.debug.print("==>{?}", .{std.options.http_disable_tls});

    var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
    defer req.deinit();
    try req.send();
    try req.wait();
    const body = try req.reader().readAllAlloc(alloc, req.response.content_length.?);
    defer alloc.free(body);
    const filename = std.fs.path.basename(url);
    const f = try std.fs.cwd().createFile(
        try std.mem.concat(std.heap.page_allocator, u8, &.{ "s3db", std.fs.path.extension(filename[0 .. filename.len - std.fs.path.extension(filename).len]) }),
        .{ .read = true },
    );
    defer f.close();
    var in_stream = std.io.fixedBufferStream(body);
    var xz_stream = std.ArrayList(u8).init(alloc);
    defer xz_stream.deinit();
    try gz.decompress(in_stream.reader(), xz_stream.writer());
    try f.writeAll(xz_stream.items);
    try f.seekTo(0);
}
