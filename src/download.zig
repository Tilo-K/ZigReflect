const std = @import("std");
pub const errors = error{ NotFound, UpstreamUnavailable };

pub fn downloadZig(io: std.Io, allocator: std.mem.Allocator, version: []const u8, file: []const u8, downloadFolder: std.Io.Dir) anyerror![]const u8 {
    var client = std.http.Client{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var downloadUrl: []u8 = "";

    if (std.mem.containsAtLeast(u8, file, 1, "-dev")) {
        downloadUrl = try std.fmt.allocPrint(
            allocator,
            "https://ziglang.org/builds/{s}",
            .{file},
        );
    } else {
        downloadUrl = try std.fmt.allocPrint(
            allocator,
            "https://ziglang.org/download/{s}/{s}",
            .{ version, file },
        );
    }

    defer allocator.free(downloadUrl);

    std.log.info("Trying to download: {s}", .{downloadUrl});
    var versionDir = try downloadFolder.createDirPathOpen(
        io,
        version,
        .{ .open_options = .{ .iterate = true } },
    );
    defer versionDir.close(io);

    const timestamp = std.Io.Timestamp.now(io, .real).nanoseconds;
    const tmp_file = try std.fmt.allocPrint(allocator, "{s}.{d}.tmp", .{ file, timestamp });
    defer allocator.free(tmp_file);

    var zig_version = try versionDir.createFile(io, tmp_file, .{});
    var file_open = true;
    defer if (file_open) zig_version.close(io);

    const tmp_path = try versionDir.realPathFileAlloc(io, tmp_file, allocator);
    defer allocator.free(tmp_path);
    errdefer {
        if (file_open) {
            zig_version.close(io);
            file_open = false;
        }
        std.Io.Dir.deleteFileAbsolute(io, tmp_path) catch {};
    }

    const buff = allocator.alloc(u8, 1024 * 1024 * 10) catch |e| {
        std.log.err("No memory for download/file buffer: {s}", .{@errorName(e)});
        return e;
    };
    defer allocator.free(buff);
    var writer = zig_version.writerStreaming(io, buff);

    const response = client.fetch(.{
        .method = .GET,
        .location = .{ .url = downloadUrl },
        .response_writer = &writer.interface,
    }) catch |e| {
        std.log.err("Upstream fetch failed: {s}", .{@errorName(e)});
        return errors.UpstreamUnavailable;
    };

    try writer.interface.defaultFlush();
    try zig_version.sync(io);

    std.log.info("Download got status {d}", .{@intFromEnum(response.status)});

    if (@intFromEnum(response.status) == 200) {
        const fileStat = try zig_version.stat(io);
        zig_version.close(io);
        file_open = false;
        try std.Io.Dir.rename(versionDir, tmp_file, versionDir, file, io);
        const path = try versionDir.realPathFileAlloc(io, file, allocator);
        std.log.info("Got file: {s} with size {d}bytes", .{ path, fileStat.size });

        return path;
    } else if (@intFromEnum(response.status) == 404) {
        return errors.NotFound;
    }

    return errors.UpstreamUnavailable;
}

pub fn getZig(io: std.Io, allocator: std.mem.Allocator, version: []const u8, file: []const u8, downloadFolder: std.Io.Dir) anyerror![]const u8 {
    var versionDir = try downloadFolder.createDirPathOpen(
        io,
        version,
        .{ .open_options = .{ .iterate = true } },
    );
    defer versionDir.close(io);

    versionDir.access(io, file, .{}) catch {
        return downloadZig(io, allocator, version, file, downloadFolder);
    };

    const path = try versionDir.realPathFileAlloc(io, file, allocator);
    return path;
}
