const std = @import("std");
const zap = @import("zap");
const download = @import("download.zig");
const filename = @import("filename.zig");
const cache = @import("cache.zig");
const admin = @import("admin.zig");

var app_io: std.Io = undefined;
var dataDir: ?std.Io.Dir = null;
var accessCache: ?cache.AccessCache = null;
var authData: []const u8 = "YWRtaW46YWRtaW4=";

fn on_request(r: zap.Request) !void {
    var gpa = std.heap.DebugAllocator(.{ .retain_metadata = true, .stack_trace_frames = 10 }){};
    defer {
        if (gpa.deinit() == .leak) {
            std.log.err("request leaked memory", .{});
        }
    }

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const alloc = arena.allocator();

    if (r.path) |the_path| {
        if (std.mem.eql(u8, the_path, "/") | std.mem.eql(u8, the_path, "")) {
            r.setStatusNumeric(200);
            try r.sendBody("ZigReflect");
            return;
        }
        if (std.mem.startsWith(u8, the_path, "/admin")) {
            return admin.handleAdmin(app_io, alloc, r, the_path, authData, dataDir.?);
        }

        const file = std.mem.trim(u8, the_path, "/ ");
        if (accessCache.?.isKnownUnavailable(app_io, file)) {
            r.setStatusNumeric(404);
            try r.sendBody("Not found");
            return;
        }

        const version = filename.extractVersion(alloc, file);
        if (version) |ver| {
            defer alloc.free(ver);
            const path = download.getZig(app_io, alloc, ver, file, dataDir.?) catch |e| {
                switch (e) {
                    download.errors.NotFound => {
                        try accessCache.?.addUnavailableFile(app_io, file);
                        r.setStatusNumeric(404);
                        try r.sendBody("Not found");
                        return;
                    },
                    download.errors.UpstreamUnavailable => {
                        r.setStatusNumeric(504);
                        try r.sendBody("ziglang.org is unavailable");
                        return;
                    },
                    else => {
                        r.setStatusNumeric(500);
                        std.log.err("An unexpected error happend {s}", .{@errorName(e)});

                        try r.sendBody("Something went wrong");
                        return;
                    },
                }
            };
            defer alloc.free(path);
            var f = try std.Io.Dir.openFileAbsolute(app_io, path, .{});
            defer f.close(app_io);
            const stat = try f.stat(app_io);
            const size = try std.fmt.allocPrint(alloc, "{d}", .{stat.size});
            defer alloc.free(size);

            r.setStatusNumeric(200);
            try r.setHeader("Content-Length", size);
            try r.sendFile(path);
            return;
        } else {
            r.setStatusNumeric(404);
            try r.sendBody("Not found");
        }
        return;
    }

    r.sendBody("<html><body><h1>Hello from ZAP!!!</h1></body></html>") catch return;
}

pub fn main(init: std.process.Init) !void {
    app_io = init.io;
    const alloc = init.gpa;
    const envMap = init.environ_map;

    var port: usize = 3000;
    if (envMap.get("PORT")) |prt| {
        const new_port = std.fmt.parseInt(usize, prt, 10) catch |e| {
            std.log.err("Invalid PORT env var {s}", .{@errorName(e)});
            return;
        };

        if (new_port != 0) {
            port = new_port;
        }
    }

    if (envMap.get("DATA_DIR")) |ddir| {
        dataDir = try std.Io.Dir.cwd().createDirPathOpen(
            app_io,
            ddir,
            .{
                .open_options = .{ .iterate = true },
            },
        );
    } else {
        dataDir = try std.Io.Dir.cwd().createDirPathOpen(
            app_io,
            "./data",
            .{
                .open_options = .{ .iterate = true },
            },
        );
    }

    var dbFile: []const u8 = "./db.sqlite3";
    if (envMap.get("DB_FILE")) |db_file| {
        dbFile = db_file;
    }

    if (envMap.get("AUTH")) |auth| {
        authData = auth;
    }

    accessCache = cache.AccessCache.init(alloc);
    defer accessCache.?.deinit() catch null;

    var listener = zap.HttpListener.init(.{
        .port = port,
        .on_request = on_request,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:{d}\n", .{port});

    const cpus = try std.Thread.getCpuCount();
    // start worker threads
    zap.start(.{
        .threads = @intCast(cpus),
        .workers = @intCast(cpus),
    });
}
