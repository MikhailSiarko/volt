const std = @import("std");

pub const QueryEntry = struct {
    key: []const u8,
    value: ?[]const u8,
};

const Self = @This();

parts: std.mem.SplitIterator(u8, .scalar),

pub fn next(self: *Self) ?QueryEntry {
    return while (self.parts.next()) |part| {
        var key_value = std.mem.splitScalar(u8, part, '=');
        const key = key_value.next() orelse continue;
        const raw_value = key_value.next() orelse break .{ .key = key, .value = null };
        const value = if (raw_value.len == 0) null else raw_value;
        break .{ .key = key, .value = value };
    } else null;
}

pub fn init(target: []const u8) ?Self {
    var start_idx = std.mem.findScalar(u8, target, '?') orelse return null;
    if (start_idx == target.len - 1) {
        return null;
    }

    start_idx += 1;
    return .{ .parts = std.mem.splitScalar(u8, target[start_idx..], '&') };
}

test "init yields key value pairs" {
    var it = init("/users?name=zig&role=admin") orelse unreachable;

    const first = it.next() orelse unreachable;
    try std.testing.expectEqualStrings("name", first.key);
    try std.testing.expectEqualStrings("zig", first.value.?);

    const second = it.next() orelse unreachable;
    try std.testing.expectEqualStrings("role", second.key);
    try std.testing.expectEqualStrings("admin", second.value.?);
    try std.testing.expectEqual(null, it.next());
}

test "init returns null for missing query string" {
    try std.testing.expectEqual(null, init("/users"));
}

test "init returns null for trailing question mark" {
    try std.testing.expectEqual(null, init("/users?"));
}
