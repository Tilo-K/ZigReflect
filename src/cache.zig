const std = @import("std");

pub const AccessCache = struct {
    notFoundMutex: std.Io.Mutex,
    notFoundMap: std.StringHashMap(i64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AccessCache {
        const map = std.StringHashMap(i64).init(allocator);
        return AccessCache{
            .notFoundMap = map,
            .notFoundMutex = .init,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AccessCache) !void {
        var it = self.notFoundMap.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.notFoundMap.deinit();
    }

    pub fn addUnavailableFile(self: *AccessCache, io: std.Io, file: []const u8) !void {
        try self.notFoundMutex.lock(io);
        defer self.notFoundMutex.unlock(io);

        const time = std.Io.Timestamp.now(io, .real).toSeconds();
        if (self.notFoundMap.getPtr(file)) |timestamp| {
            timestamp.* = time;
            return;
        }

        std.debug.print("Adding not found file {s}\n", .{file});
        const owned_file = try self.allocator.dupe(u8, file);
        errdefer self.allocator.free(owned_file);
        try self.notFoundMap.put(owned_file, time);
    }

    pub fn isKnownUnavailable(self: *AccessCache, io: std.Io, file: []const u8) bool {
        self.notFoundMutex.lockUncancelable(io);
        defer self.notFoundMutex.unlock(io);

        if (self.notFoundMap.get(file)) |timestamp| {
            const now = std.Io.Timestamp.now(io, .real).toSeconds();
            const delta = now - timestamp;
            if (delta < 60) {
                std.debug.print("Found cached not found file\n", .{});
                return true;
            }

            if (self.notFoundMap.fetchRemove(file)) |kv| {
                self.allocator.free(kv.key);
            }
        }

        return false;
    }
};

test "AccessCache owns and frees unavailable file keys" {
    var cache = AccessCache.init(std.testing.allocator);
    defer cache.deinit() catch unreachable;

    try cache.addUnavailableFile(std.testing.io, "zig-x86_64-linux-99.99.99.tar.xz");
    try cache.addUnavailableFile(std.testing.io, "zig-x86_64-linux-99.99.99.tar.xz");

    try std.testing.expect(cache.isKnownUnavailable(std.testing.io, "zig-x86_64-linux-99.99.99.tar.xz"));
    try std.testing.expectEqual(@as(u32, 1), cache.notFoundMap.count());
}

test "AccessCache removes and frees expired entries" {
    var cache = AccessCache.init(std.testing.allocator);
    defer cache.deinit() catch unreachable;

    const owned_file = try std.testing.allocator.dupe(u8, "zig-x86_64-linux-0.0.0.tar.xz");
    errdefer std.testing.allocator.free(owned_file);
    try cache.notFoundMap.put(owned_file, 0);

    try std.testing.expect(!cache.isKnownUnavailable(std.testing.io, "zig-x86_64-linux-0.0.0.tar.xz"));
    try std.testing.expectEqual(@as(u32, 0), cache.notFoundMap.count());
}
