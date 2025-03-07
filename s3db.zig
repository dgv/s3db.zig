const std = @import("std");
pub usingnamespace @import("sqlite");
const builtin = @import("builtin");
const gz = std.compress.gzip;

pub fn init(options: @This().InitOptions) @This().Db.InitError!@This().Db {
    // moved from build https://github.com/ziglang/zig/blob/0.14.0/lib/compiler/build_runner.zig#L22
    const s3db_ext_module = switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            .arm => "https://github.com/jrhy/s3db/releases/download/v0.1.65/s3db-v0.1.65-linux-arm-glibc.sqlite-ext.so.gz",
            .aarch64 => "https://github.com/jrhy/s3db/releases/download/v0.1.65/s3db-v0.1.65-linux-arm64-glibc.sqlite-ext.so.gz",
            .x86_64 => "https://github.com/jrhy/s3db/releases/download/v0.1.65/s3db-v0.1.65-linux-amd64-glibc.sqlite-ext.so.gz",
            else => @panic("arch not currently supported"),
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => "https://pub.dgv.dev.br/s3db-v0.1.65-macos-amd64.dylib.gz",
            else => @panic("arch not currently supported"),
        },
        else => @panic("platform not currently supported"),
    };
    _ = std.fs.cwd().statFile(std.fs.path.basename(s3db_ext_module)) catch |e| if (e != error.FileNotFound) @panic("not able to stat s3db lib") else {
        fetch(std.heap.page_allocator, s3db_ext_module) catch |err| {
            std.debug.print("fetch err: {?}", .{err});
            return error.SQLiteError;
        };
    };
    const db = try @This().Db.init(options);
    {
        const result = @This().c.sqlite3_enable_load_extension(db.db, 1);
        std.debug.assert(result == @This().c.SQLITE_OK);
    }

    {
        var pzErrMsg: [*c]u8 = undefined;
        const result = @This().c.sqlite3_load_extension(db.db, "s3db", null, &pzErrMsg);
        if (result != @This().c.SQLITE_OK) {
            const err = @This().c.sqlite3_errstr(result);
            std.debug.panic("unable to load extension, err: {s}, err message: {s}\n", .{ err, std.mem.sliceTo(pzErrMsg, 0) });
            return error.LoadErr;
        }
    }
    return db;
}

fn fetch(alloc: std.mem.Allocator, url: []const u8) !void {
    const filename = std.fs.path.basename(url);
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();
    var buf: [10240]u8 = undefined;
    const uri = try std.Uri.parse(url);
    var req = try client.open(.GET, uri, .{ .server_header_buffer = &buf });
    defer req.deinit();
    try req.send();
    try req.wait();
    const body = try req.reader().readAllAlloc(alloc, req.response.content_length.?);
    defer alloc.free(body);
    const f = try std.fs.cwd().createFile(
        try std.mem.concat(alloc, u8, &.{ "s3db", std.fs.path.extension(filename[0 .. filename.len - std.fs.path.extension(filename).len]) }),
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

test "s3db poc" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.panic("leaks detected", .{});
    };

    var allocator = gpa.allocator();

    var db = try init(.{
        .mode = @This().Db.Mode{ .Memory = {} },
        .open_flags = .{ .write = true },
    });
    defer db.deinit();

    try db.exec("CREATE VIRTUAL TABLE user USING s3db (columns='id integer primary key, age integer, name text')", .{}, .{});

    const user_name: []const u8 = "Vincent";

    // Insert some data
    try db.exec("INSERT INTO user(id, age, name) VALUES($id{usize}, $age{u32}, $name{[]const u8})", .{}, .{ @as(usize, 10), @as(u32, 34), user_name });
    try db.exec("INSERT INTO user(id, age, name) VALUES($id{usize}, $age{u32}, $name{[]const u8})", .{}, .{ @as(usize, 20), @as(u32, 84), @as([]const u8, "José") });

    // Read one row into a struct
    const User = struct {
        id: usize,
        age: u32,
        name: []const u8,
    };

    const user_opt = try db.oneAlloc(User, allocator, "SELECT id, age, name FROM user WHERE name = $name{[]const u8}", .{}, .{
        .name = user_name,
    });
    try std.testing.expect(user_opt != null);
    if (user_opt) |user| {
        std.debug.print("select user: id={d} age={d} name={s}\n", .{ user.id, user.age, user.name });

        defer allocator.free(user.name);

        try std.testing.expectEqual(@as(usize, 10), user.id);
        try std.testing.expectEqual(@as(u32, 34), user.age);
        try std.testing.expectEqualStrings(user_name, user.name);
    }

    // Read single integers; reuse the same prepared statement
    var stmt = try db.prepare("SELECT id FROM user WHERE age = $age{u32}");
    defer stmt.deinit();

    const id1 = try stmt.one(usize, .{}, .{@as(u32, 34)});
    try std.testing.expectEqual(@as(usize, 10), id1.?);

    stmt.reset();

    const id2 = try stmt.one(usize, .{}, .{@as(u32, 84)});
    try std.testing.expectEqual(@as(usize, 20), id2.?);
}
