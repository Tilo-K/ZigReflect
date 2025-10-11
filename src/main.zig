const std = @import("std");
const zap = @import("zap");
const download = @import("download.zig");
const filename = @import("filename.zig");

fn on_request(r: zap.Request) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();

    if (r.path) |the_path| {
        std.debug.print("PATH: {s}\n", .{the_path});
        if (std.mem.startsWith(u8, the_path, "/admin")) {
            const data = try download.downloadZig(alloc);
            try r.sendBody(data);
            return;
        }

        const file = std.mem.trim(u8, the_path, "/ ");
        const version = filename.extractFilename(alloc, file);
        if (version) |ver| {
            r.sendBody(try std.fmt.allocPrint(alloc, "<h1>{s}</h1>", .{ver})) catch return;
        } else {
            try r.sendBody(":( :( :(");
        }
        return;
    }

    if (r.query) |the_query| {
        std.debug.print("QUERY: {s}\n", .{the_query});
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
