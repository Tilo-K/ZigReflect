const std = @import("std");

pub fn downloadZig(allocator: std.mem.Allocator) ![]const u8 {
    var client = std.http.Client{
        .allocator = allocator,
    };

    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = "https://raw.githubusercontent.com/Tilo-K/csvu/refs/heads/master/README.md" },
        .response_writer = &body.writer,
    });

    std.log.info("Download got status {d}", .{@intFromEnum(response.status)});
    const data = try body.toOwnedSlice();
    return data;
}
