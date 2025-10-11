const std = @import("std");
pub const errors = error{ NotFound, Unknown };

pub fn downloadZig(allocator: std.mem.Allocator, version: []const u8, file: []const u8, downloadFolder: std.fs.Dir) anyerror![]const u8 {
    var client = std.http.Client{
        .allocator = allocator,
    };

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
    const versionDir = try downloadFolder.makeOpenPath(
        version,
        .{ .access_sub_paths = true, .iterate = true },
    );

    var zig_version = try versionDir.createFile(file, .{});
    defer zig_version.close();

    const buff = allocator.alloc(u8, 1024 * 1024 * 10) catch |e| {
        std.log.err("No memory for download/file buffer: {s}", .{@errorName(e)});
        return e;
    };
    var writer = zig_version.writerStreaming(buff);

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = downloadUrl },
        .response_writer = &writer.interface,
    });

    std.log.info("Download got status {d}", .{@intFromEnum(response.status)});
    const path = try versionDir.realpathAlloc(allocator, file);

    if (@intFromEnum(response.status) == 200) {
        const fileStat = try zig_version.stat();
        std.log.info("Got file: {s} with size {d}bytes", .{ path, fileStat.size });

        return path;
    } else if (@intFromEnum(response.status) == 404) {
        try std.fs.deleteFileAbsolute(path);
        return errors.NotFound;
    }

    return errors.Unknown;
}

pub fn getZig(allocator: std.mem.Allocator, version: []const u8, file: []const u8, downloadFolder: std.fs.Dir) anyerror![]const u8 {
    const versionDir = try downloadFolder.makeOpenPath(
        version,
        .{ .access_sub_paths = true, .iterate = true },
    );

    versionDir.access(file, .{}) catch {
        return downloadZig(allocator, version, file, downloadFolder);
    };

    const path = try versionDir.realpathAlloc(allocator, file);
    return path;
}
