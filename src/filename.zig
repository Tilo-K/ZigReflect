const std = @import("std");

const supportedExt = [_][]const u8{
    ".tar.xz.minisig",
    ".zip.minisig",
    ".tar.xz",
    ".zip",
};

fn trimSupportedExt(filename: []const u8) ?[]const u8 {
    for (supportedExt) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) {
            return filename[0 .. filename.len - ext.len];
        }
    }

    return null;
}

fn isTargetPart(part: []const u8) bool {
    if (part.len == 0) return false;

    for (part) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') {
            return false;
        }
    }

    return true;
}

fn isHexLower(bytes: []const u8) bool {
    if (bytes.len == 0) return false;

    for (bytes) |c| {
        if (!std.ascii.isDigit(c) and !(c >= 'a' and c <= 'f')) {
            return false;
        }
    }

    return true;
}

// Validate that the file name starts with zig-
// Validate that the file name ends with a supported extension (.tar.xz, .zip, .tar.xz.minisig, .zip.minisig)
pub fn isValidFilename(filename: []const u8) bool {
    if (!std.mem.startsWith(u8, filename, "zig-")) {
        return false;
    }

    if (trimSupportedExt(filename) == null) {
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

    const without_ext = trimSupportedExt(filename) orelse return null;

    var splitIter = std.mem.splitScalar(u8, without_ext, '-');
    var split = std.ArrayList([]const u8).initCapacity(allocator, 5) catch return null;
    while (splitIter.next()) |part| {
        split.append(allocator, part) catch return null;
    }
    defer split.deinit(allocator);

    if (split.items.len < 2 or !std.mem.eql(u8, split.items[0], "zig")) {
        return null;
    }

    var version_index = split.items.len - 1;
    if (split.items.len >= 2 and std.mem.startsWith(u8, split.items[version_index], "dev.")) {
        version_index -= 1;
    }

    if (version_index == 1) {
        // zig-VERSION
    } else if (version_index == 2 and std.mem.eql(u8, split.items[1], "bootstrap")) {
        // zig-bootstrap-VERSION
    } else if (version_index == 3 and isTargetPart(split.items[1]) and isTargetPart(split.items[2])) {
        // zig-ARCH-OS-VERSION or legacy zig-OS-ARCH-VERSION
    } else {
        return null;
    }

    const version = if (version_index + 1 < split.items.len)
        std.mem.join(allocator, "-", split.items[version_index..]) catch return null
    else
        allocator.dupe(u8, split.items[version_index]) catch return null;

    if (!isValidVersion(version)) {
        allocator.free(version);
        return null;
    }

    return version;
}

pub fn isValidVersion(version: []const u8) bool {
    var semver_and_build = std.mem.splitScalar(u8, version, '+');
    const semver = semver_and_build.next() orelse return false;
    const build = semver_and_build.next();
    if (semver_and_build.next() != null) return false;

    var release_and_pre = std.mem.splitScalar(u8, semver, '-');
    const release = release_and_pre.next() orelse return false;
    const prerelease = release_and_pre.next();
    if (release_and_pre.next() != null) return false;

    if (std.mem.count(u8, release, ".") != 2) {
        return false;
    }

    var iter = std.mem.splitScalar(u8, release, '.');
    while (iter.next()) |s| {
        if (s.len == 0) return false;
        _ = std.fmt.parseInt(usize, s, 10) catch {
            return false;
        };
    }

    if (prerelease) |pre| {
        if (build == null) return false;
        if (!std.mem.startsWith(u8, pre, "dev.")) return false;
        const dev_num = pre["dev.".len..];
        if (dev_num.len == 0) return false;
        _ = std.fmt.parseInt(usize, dev_num, 10) catch return false;
    } else if (build != null) {
        return false;
    }

    if (build) |b| {
        if (!isHexLower(b)) return false;
    }

    return true;
}

test "extractVersion returns stable release version from supported filenames" {
    const allocator = std.testing.allocator;

    const tar_version = extractVersion(allocator, "zig-x86_64-linux-0.16.0.tar.xz").?;
    defer allocator.free(tar_version);
    try std.testing.expectEqualStrings("0.16.0", tar_version);

    const zip_version = extractVersion(allocator, "zig-x86_64-windows-0.15.1.zip").?;
    defer allocator.free(zip_version);
    try std.testing.expectEqualStrings("0.15.1", zip_version);
}

test "extractVersion returns version from source and bootstrap tarballs" {
    const allocator = std.testing.allocator;

    const source_version = extractVersion(allocator, "zig-0.14.1.tar.xz").?;
    defer allocator.free(source_version);
    try std.testing.expectEqualStrings("0.14.1", source_version);

    const bootstrap_version = extractVersion(allocator, "zig-bootstrap-0.14.1.tar.xz").?;
    defer allocator.free(bootstrap_version);
    try std.testing.expectEqualStrings("0.14.1", bootstrap_version);
}

test "extractVersion returns version from minisig filenames" {
    const allocator = std.testing.allocator;

    const tar_sig_version = extractVersion(allocator, "zig-aarch64-macos-0.14.0.tar.xz.minisig").?;
    defer allocator.free(tar_sig_version);
    try std.testing.expectEqualStrings("0.14.0", tar_sig_version);

    const zip_sig_version = extractVersion(allocator, "zig-x86_64-windows-0.13.0.zip.minisig").?;
    defer allocator.free(zip_sig_version);
    try std.testing.expectEqualStrings("0.13.0", zip_sig_version);
}

test "extractVersion returns full pre-release version from dev build filenames" {
    const allocator = std.testing.allocator;

    const version = extractVersion(allocator, "zig-x86_64-linux-0.16.0-dev.123+abcdef.tar.xz").?;
    defer allocator.free(version);
    try std.testing.expectEqualStrings("0.16.0-dev.123+abcdef", version);
}

test "extractVersion supports source and bootstrap pre-release filenames" {
    const allocator = std.testing.allocator;

    const source_version = extractVersion(allocator, "zig-0.15.0-dev.671+c907866d5.tar.xz").?;
    defer allocator.free(source_version);
    try std.testing.expectEqualStrings("0.15.0-dev.671+c907866d5", source_version);

    const bootstrap_version = extractVersion(allocator, "zig-bootstrap-0.15.0-dev.671+c907866d5.tar.xz").?;
    defer allocator.free(bootstrap_version);
    try std.testing.expectEqualStrings("0.15.0-dev.671+c907866d5", bootstrap_version);
}

test "extractVersion rejects invalid filenames" {
    const allocator = std.testing.allocator;

    try std.testing.expect(extractVersion(allocator, "not-zig-x86_64-linux-0.16.0.tar.xz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-0.16.tar.xz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-0.16.0.tar.gz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-version.tar.xz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-0.16.0") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-0.16.0-dev.1+ABCDEF.tar.xz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-0.16.0-dev+abcdef.tar.xz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-0.16.0-dev.1.tar.xz") == null);
    try std.testing.expect(extractVersion(allocator, "zig-x86_64-linux-extra-0.16.0.tar.xz") == null);
}
