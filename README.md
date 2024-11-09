# s3db.zig
[![zig version](https://img.shields.io/badge/0.13.0-orange?style=flat&logo=zig&label=Zig&color=%23eba742)](https://ziglang.org/download/)
[![reference Zig](https://img.shields.io/badge/deps%20-1-orange?color=%23eba742)](https://github.com/dgv/s3db.zig/blob/main/build.zig.zon)
[![build](https://github.com/dgv/s3db.zig/actions/workflows/build.yml/badge.svg)](https://github.com/dgv/s3db.zig/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Zig wrapper lib/sample for SQLite/Go extension that stores tables in an S3-compatible object store

## usage
```zig
var db = try s3db.init(.{
    .mode = s3db.Db.Mode{ .Memory = {} },
    .open_flags = .{ .write = true },
});
defer db.deinit();

try db.exec("CREATE VIRTUAL TABLE user USING s3db (columns='id integer primary key, age integer, name text')", .{}, .{});
...

```
