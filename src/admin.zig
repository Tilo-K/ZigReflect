const std = @import("std");
const zap = @import("zap");
const datetime = @import("datetime");
const Mustache = zap.Mustache;

pub fn handleAdmin(io: std.Io, allocator: std.mem.Allocator, r: zap.Request, path: []const u8, authData: []const u8, dataDir: std.Io.Dir) !void {
    if (r.getHeader("authorization")) |auth_header| {
        if (!std.mem.endsWith(u8, auth_header, authData)) {
            try r.setHeader("WWW-Authenticate", "Basic realm=\"Restricted Area\", charset=\"UTF-8\"");
            r.setStatusNumeric(401);
            try r.sendBody("Unauthorized");
            return;
        }

        if (std.mem.eql(u8, path, "/admin/cached")) {
            return renderCached(io, allocator, r, dataDir);
        }
        r.setStatusNumeric(200);
        try r.sendBody(auth_header);

        return;
    } else {
        try r.setHeader("WWW-Authenticate", "Basic realm=\"Restricted Area\", charset=\"UTF-8\"");
        r.setStatusNumeric(401);
        try r.sendBody("Unauthorized");
        return;
    }
    try r.sendBody("Nope");
    return;
}

pub fn formatAsFileSize(size: f128, allocator: std.mem.Allocator) ![]const u8 {
    if (size < 1024) {
        return std.fmt.allocPrint(allocator, "{d:.0} bytes", .{size});
    } else if (size < 1024 * 1024) {
        return std.fmt.allocPrint(allocator, "{d:.2} KiB", .{size / 1024});
    } else if (size < 1024 * 1024 * 1024) {
        return std.fmt.allocPrint(allocator, "{d:.2} MiB", .{size / (1024 * 1024)});
    } else {
        return std.fmt.allocPrint(allocator, "{d:.2} GiB", .{size / (1024 * 1024 * 1024)});
    }
}

const FileItem = struct {
    value: []const u8,
    size: []const u8,
    atime: []const u8,
};

fn getCachedFiles(io: std.Io, allocator: std.mem.Allocator, dataDir: std.Io.Dir) !std.ArrayList(FileItem) {
    var cachedFiles = try std.ArrayList(FileItem).initCapacity(allocator, 10);

    var walker = try dataDir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) continue;

        const path = try allocator.dupe(u8, entry.path);
        errdefer allocator.free(path);
        const stat = stat: {
            var f = try dataDir.openFile(io, path, .{});
            defer f.close(io);
            break :stat try f.stat(io);
        };

        const dt = datetime.datetime.Datetime.fromModifiedTime(@intCast((stat.atime orelse stat.mtime).nanoseconds));
        const t = try dt.formatISO8601(allocator, false);
        errdefer allocator.free(t);

        const size = try formatAsFileSize(@floatFromInt(stat.size), allocator);
        errdefer allocator.free(size);

        try cachedFiles.append(allocator, .{
            .value = path,
            .size = size,
            .atime = t,
        });
    }

    return cachedFiles;
}

fn renderCached(io: std.Io, allocator: std.mem.Allocator, r: zap.Request, dataDir: std.Io.Dir) !void {
    var template = try Mustache.fromData(@embedFile("./templates/cached.mustache"));
    defer template.deinit();
    var size: u64 = 0;

    var walker = try dataDir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) continue;

        const stat = stat: {
            var f = try dataDir.openFile(io, entry.path, .{});
            defer f.close(io);
            break :stat try f.stat(io);
        };

        size += stat.size;
    }

    var cachedFiles = try getCachedFiles(io, allocator, dataDir);

    defer {
        for (cachedFiles.items) |p| {
            allocator.free(p.value);
            allocator.free(p.atime);
            allocator.free(p.size);
        }
        cachedFiles.deinit(allocator);
    }

    const formatted_size = try formatAsFileSize(@floatFromInt(size), allocator);
    defer allocator.free(formatted_size);

    const ret = template.build(.{
        .files = cachedFiles.items,
        .count = @as(isize, @intCast(cachedFiles.items.len)),
        .size = formatted_size,
    });
    defer ret.deinit();

    if (r.setContentType(.HTML)) {
        if (ret.str()) |s| {
            r.sendBody(s) catch return;
        } else {
            r.sendBody("<html><body><h1>mustacheBuild() failed!</h1></body></html>") catch return;
        }
    } else |err| {
        std.debug.print("Error while setting content type: {}\n", .{err});
    }
}
