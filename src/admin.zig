const std = @import("std");
const zap = @import("zap");
const datetime = @import("datetime");
const Mustache = zap.Mustache;

pub fn handleAdmin(allocator: std.mem.Allocator, r: zap.Request, path: []const u8, authData: []const u8, dataDir: std.fs.Dir) !void {
    if (r.getHeader("authorization")) |auth_header| {
        if (!std.mem.endsWith(u8, auth_header, authData)) {
            try r.setHeader("WWW-Authenticate", "Basic realm=\"Restricted Area\", charset=\"UTF-8\"");
            r.setStatusNumeric(401);
            try r.sendBody("Unauthorized");
            return;
        }

        if (std.mem.eql(u8, path, "/admin/cached")) {
            return renderCached(allocator, r, dataDir);
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

fn renderCached(allocator: std.mem.Allocator, r: zap.Request, dataDir: std.fs.Dir) !void {
    var template = try Mustache.fromData(@embedFile("./templates/cached.mustache"));
    defer template.deinit();

    var cachedFiles = try std.ArrayList(FileItem).initCapacity(allocator, 10);
    defer {
        for (cachedFiles.items) |p| {
            allocator.free(p.value);
            allocator.free(p.atime);
            allocator.free(p.size);
        }
        cachedFiles.deinit(allocator);
    }

    var walker = try dataDir.walk(allocator);
    while (try walker.next()) |entry| {
        if (entry.kind == .directory) continue;

        const path = try allocator.alloc(u8, entry.path.len);
        @memcpy(path, entry.path);

        const f = try dataDir.openFile(path, .{});
        const stat = try f.stat();

        const dt = datetime.datetime.Datetime.fromModifiedTime(stat.atime);
        const t = try dt.formatISO8601(allocator, false);

        try cachedFiles.append(allocator, .{
            .value = path,
            .size = try formatAsFileSize(@floatFromInt(stat.size), allocator),
            .atime = t,
        });
    }

    const ret = template.build(.{
        .files = cachedFiles.items,
    });

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
