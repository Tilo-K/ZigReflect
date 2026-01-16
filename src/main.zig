const std = @import("std");
const zap = @import("zap");
const download = @import("download.zig");
const filename = @import("filename.zig");
const cache = @import("cache.zig");
const admin = @import("admin.zig");

var dataDir: ?std.fs.Dir = null;
var accessCache: ?cache.AccessCache = null;
var authData: []const u8 = "YWRtaW46YWRtaW4=";

fn on_request(r: zap.Request) !void {
    var gpa = std.heap.DebugAllocator(.{ .retain_metadata = true, .stack_trace_frames = 10 }){};
    defer _ = gpa.deinit();

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
            return admin.handleAdmin(alloc, r, the_path, authData, dataDir.?);
        }

        const file = std.mem.trim(u8, the_path, "/ ");
        if (accessCache.?.isKnownUnavailable(file)) {
            r.setStatusNumeric(404);
            try r.sendBody("Not found");
            return;
        }

        const version = filename.extractVersion(alloc, file);
        if (version) |ver| {
            defer alloc.free(ver);
            const path = download.getZig(alloc, ver, file, dataDir.?) catch |e| {
                switch (e) {
                    download.errors.NotFound => {
                        try accessCache.?.addUnavailableFile(file);
                        r.setStatusNumeric(404);
                        try r.sendBody("Not found");
                        return;
                    },
                    download.errors.Timeout => {
                        r.setStatusNumeric(504);
                        try r.sendBody("ziglang.org did not respond in time");
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
            const f = try std.fs.openFileAbsolute(path, .{});
            const stat = try f.stat();
            const size = try std.fmt.allocPrint(alloc, "{d}", .{stat.size});
            defer alloc.free(size);
            f.close();

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

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();

    var envMap = std.process.getEnvMap(alloc) catch |e| {
        std.log.err("Error loading env vars {s}", .{@errorName(e)});
        std.process.exit(100);
    };
    defer envMap.deinit();

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
        dataDir = try std.fs.cwd().makeOpenPath(
            ddir,
            .{
                .access_sub_paths = true,
                .iterate = true,
            },
        );
    } else {
        dataDir = try std.fs.cwd().makeOpenPath(
            "./data",
            .{
                .access_sub_paths = true,
                .iterate = true,
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
