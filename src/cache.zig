const std = @import("std");

pub const AccessCache = struct {
    notFoundMutex: std.Thread.Mutex,
    notFoundMap: std.StringHashMap(i64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AccessCache {
        const map = std.StringHashMap(i64).init(allocator);
        return AccessCache{
            .notFoundMap = map,
            .notFoundMutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AccessCache) !void {
        self.notFoundMap.deinit();
    }

    pub fn addUnavailableFile(self: *AccessCache, file: []const u8) !void {
        std.debug.print("Adding not found file {s}\n", .{file});
        const owned_file = try self.allocator.alloc(u8, file.len);
        @memcpy(owned_file, file);

        self.notFoundMutex.lock();
        defer self.notFoundMutex.unlock();
        const time = std.time.timestamp();
        try self.notFoundMap.put(owned_file, time);
    }

    pub fn isKnownUnavailable(self: *AccessCache, file: []const u8) bool {
        if (self.notFoundMap.get(file)) |timestamp| {
            const now = std.time.timestamp();
            const delta = now - timestamp;
            if (delta < 60) {
                std.debug.print("Found cached not found file\n", .{});
                return true;
            }

            self.notFoundMutex.lock();
            defer self.notFoundMutex.unlock();
            _ = self.notFoundMap.remove(file);
        }

        return false;
    }
};
