const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorError = std.mem.Allocator.Error;

fn hasEncodedCharacters(component: []const u8) bool {
    if (std.mem.findScalar(u8, component, '%')) |idx| {
        if (idx + 2 > component.len - 1) {
            return false;
        }

        const hex1 = component[idx + 1];
        const hex2 = component[idx + 2];
        return std.ascii.isHex(hex1) and std.ascii.isHex(hex2);
    }

    return false;
}

pub fn decode(arena: Allocator, component: []const u8) AllocatorError![]const u8 {
    if (!hasEncodedCharacters(component)) return component;
    const decoded = try arena.alloc(u8, component.len);
    @memcpy(decoded, component);
    return std.Uri.percentDecodeInPlace(decoded);
}

pub const StringToEnumError = error{InvalidEnumValue};
pub const ParseError = StringToEnumError || std.fmt.ParseIntError || std.fmt.ParseFloatError;

pub fn parse(comptime T: type, val: []const u8) ParseError!T {
    const i = @typeInfo(T);
    return switch (i) {
        .float => try std.fmt.parseFloat(T, val),
        .int => try std.fmt.parseInt(T, val, 10),
        .@"enum" => std.meta.stringToEnum(T, val) orelse return StringToEnumError.InvalidEnumValue,
        .@"struct" => return error.Unimplemented, // TODO: support nested structs in form data
        else => val,
    };
}

test "hasEncodedCharacters detects markers" {
    try std.testing.expect(!hasEncodedCharacters("abc"));
    try std.testing.expect(hasEncodedCharacters("a%20b"));
}

test "decodeUrl fails on malformed percent escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqualStrings("bad%2", try decode(arena.allocator(), "bad%2"));
}

test "decodeUrl returns source slice on non-hex percent escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "bad%G0";
    const decoded = try decode(arena.allocator(), source);

    try std.testing.expectEqual(@intFromPtr(source.ptr), @intFromPtr(decoded.ptr));
    try std.testing.expectEqualStrings("bad%G0", decoded);
}

test "decodeUrl returns allocation-sized slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const source = "a%20b";
    const decoded = try decode(arena.allocator(), source);

    try std.testing.expect(@intFromPtr(decoded.ptr) != @intFromPtr(source.ptr));
    try std.testing.expectEqualStrings("a b", decoded);
}

test "decodeUrl returns borrowed slice when decoding is not needed" {
    const source = "plain";
    const decoded = try decode(std.testing.allocator, source);
    try std.testing.expectEqual(@intFromPtr(source.ptr), @intFromPtr(decoded.ptr));
    try std.testing.expectEqual(source.len, decoded.len);
}
