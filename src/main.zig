const std = @import("std");
const zap = @import("zap");
const download = @import("download.zig");
const filename = @import("filename.zig");

var dataDir: ?std.fs.Dir = null;

fn on_request(r: zap.Request) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();

    if (r.path) |the_path| {
        if (std.mem.eql(u8, the_path, "/") | std.mem.eql(u8, the_path, "")) {
            r.setStatusNumeric(200);
            try r.sendBody("ZigReflect");
            return;
        }
        if (std.mem.startsWith(u8, the_path, "/admin")) {
            try r.sendBody("Nope");
            return;
        }

        const file = std.mem.trim(u8, the_path, "/ ");
        const version = filename.extractFilename(alloc, file);
        if (version) |ver| {
            const path = download.getZig(alloc, ver, file, dataDir.?) catch |e| {
                switch (e) {
                    download.errors.NotFound => {
                        r.setStatusNumeric(404);
                        try r.sendBody("Not found");
                        return;
                    },
                    else => {
                        r.setStatusNumeric(500);
                        try r.sendBody("Something went wrong");
                        return;
                    },
                }
            };
            defer alloc.free(path);

            try r.sendFile(path);
            return;
        } else {
            try r.sendBody(":( :( :(");
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
