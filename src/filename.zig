const std = @import("std");

const supportedExt = [_][]const u8{
    ".tar.xz.minisig",
    ".zip.minisig",
    ".tar.xz",
    ".zip",
};

// Validate that the file name starts with zig-
// Validate that the file name ends with a supported extension (.tar.xz, .zip, .tar.xz.minisig, .zip.minisig)
pub fn isValidFilename(filename: []const u8) bool {
    if (!std.mem.startsWith(u8, filename, "zig-")) {
        return false;
    }

    var found = false;
    for (supportedExt) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            found = true;
            break;
        }
    }
    if (!found) {
        return false;
    }

    return true;
}

// Find the last occurrence of "-" in the file name; if that byte is followed by the string "dev", find the previous occurence of "-" instead
// The substring after that "-" byte, and excluding the trailing file extension, is the Zig version
pub fn extractVersion(allocator: std.mem.Allocator, filename: []const u8) ?[]const u8 {
    if (!isValidFilename(filename)) {
        return null;
    }

    var splitIter = std.mem.splitAny(u8, filename, "-");
    var split = std.ArrayList([]const u8).initCapacity(allocator, 4) catch return null;
    while (splitIter.next()) |part| {
        split.append(allocator, part) catch return null;
    }
    defer split.deinit(allocator);

    var version = split.getLast();
    if (std.mem.startsWith(u8, version, "dev")) {
        version = split.items[split.items.len - 2];
    }

    var allocated_version: ?[]const u8 = null;

    for (supportedExt) |ext| {
        const new_len = std.mem.replacementSize(u8, version, ext, "");
        if (new_len == version.len) continue;

        if (allocated_version) |prev| allocator.free(prev);

        const new_version = allocator.alloc(u8, new_len) catch return null;
        _ = std.mem.replace(u8, version, ext, "", new_version);

        version = new_version;
        allocated_version = new_version;
    }

    if (!isValidVersion(version)) {
        if (allocated_version) |v| allocator.free(v);
        return null;
    }

    return version;
}

pub fn isValidVersion(version: []const u8) bool {
    std.log.info("{s}", .{version});
    if (std.mem.count(u8, version, ".") != 2) {
        return false;
    }

    var iter = std.mem.splitAny(u8, version, ".");

    while (iter.next()) |s| {
        _ = std.fmt.parseInt(usize, s, 10) catch {
            return false;
        };
    }

    return true;
}
