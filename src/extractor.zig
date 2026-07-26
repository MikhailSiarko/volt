const Context = @import("core").Context;

const method_name = "fromContext";

pub fn isExtractor(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct" and @typeInfo(T) != .@"union") return false;
    if (@hasDecl(T, method_name)) {
        const info = @typeInfo(@TypeOf(@field(T, method_name)));
        return info == .@"fn" and
            info.@"fn".param_types.len == 1 and
            info.@"fn".param_types[0] == Context and
            info.@"fn".return_type.? == T;
    }

    return false;
}

test "extractor returns true for a struct with a fromContext method and returns Extractor type" {
    const std = @import("std");

    const TestExtractor = struct {
        pub fn fromContext(ctx: Context) @This() {
            _ = ctx;
            return .{};
        }
    };

    try std.testing.expect(isExtractor(TestExtractor));
}

test "extractor returns false for a struct without a fromContext method" {
    const std = @import("std");

    const NonExtractor = struct {
        pub fn someOtherMethod() void {}
    };

    try std.testing.expect(!isExtractor(NonExtractor));
}

test "extractor returns false if fromContext return type that is not an extractor itself" {
    const std = @import("std");

    const NonExtractor = struct {
        pub fn fromContext(ctx: Context) !u8 {
            _ = ctx;
            return 5;
        }
    };

    try std.testing.expect(!isExtractor(NonExtractor));
}
