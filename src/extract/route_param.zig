const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const AllocatorError = std.mem.Allocator.Error;
const Request = std.http.Server.Request;

const Context = @import("core").Context;
const url = @import("url.zig");

fn extract(
    comptime name: []const u8,
    arena: Allocator,
    route_pattern: ?[]const u8,
    req: *Request,
) AllocatorError!?[]const u8 {
    const decoded_target = try url.decode(arena, req.head.target);
    return resolveValue(name, route_pattern, decoded_target);
}

fn resolveValue(
    name: []const u8,
    route_pattern: ?[]const u8,
    req_target: []const u8,
) ?[]const u8 {
    const pattern = route_pattern orelse return null;
    const req_path = stripQuery(req_target);
    const pattern_path = stripQuery(pattern);
    const req_trimmed = if (req_path.len > 0 and req_path[0] == '/') req_path[1..] else req_path;
    const pattern_trimmed = if (pattern_path.len > 0 and pattern_path[0] == '/')
        pattern_path[1..]
    else
        pattern_path;

    var req_it = std.mem.splitScalar(u8, req_trimmed, '/');
    var pattern_it = std.mem.splitScalar(u8, pattern_trimmed, '/');
    return while (pattern_it.next()) |pat_seg| {
        const req_seg = req_it.next() orelse break null;
        if (pat_seg.len > 0 and pat_seg[0] == ':') {
            if (std.mem.eql(u8, pat_seg[1..], name)) {
                break req_seg;
            }
        } else if (!std.mem.eql(u8, pat_seg, req_seg)) {
            break null;
        }
    } else null;
}

fn stripQuery(target: []const u8) []const u8 {
    if (std.mem.findScalar(u8, target, '?')) |idx| {
        return target[0..idx];
    }

    return target;
}

/// Creates a 'RouteParam' extractor type
///
/// Fields:
/// - `value`: An optional slice of bytes that contains the value of the route parameter if it is present in the request,
/// or `null` if the parameter is absent.
///
/// The extractor can be used either:
/// - as a router handler parameter (automatic injection), or
/// - manually inside a handler body with `RouteParam(name).init(ctx)`.
///
/// ```zig
/// fn handleRequest(ctx: Context, id: RouteParam("id")) !Response {
///    if (id.value) |id_value| {
///       // Use id_value...
///    }
/// }
/// ```
pub fn RouteParam(comptime name: []const u8) type {
    assert(name.len > 0);
    return struct {
        const Self = @This();

        name: []const u8 = name,
        result: AllocatorError!?[]const u8,

        pub fn fromContext(ctx: Context) Self {
            return .{ .result = extract(name, ctx.req_arena, ctx.route_pattern, ctx.raw_req) };
        }
    };
}

test "init returns value when key matches" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /users/42 HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = "/users/:id",
    };

    const param = RouteParam("id").fromContext(test_ctx);
    const result = param.result catch {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("42", result.?);
}

test "extract returns null when key is absent" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /users/alice HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = "/accounts/:name",
    };

    const param = RouteParam("id").fromContext(test_ctx);
    const result = param.result catch {
        try testing.expect(false);
        return;
    };

    try testing.expect(result == null);
}

test "extract resolves multiple params from one pattern" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /teams/abc/users/42 HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = "/teams/:team_id/users/:user_id",
    };
    const team_id = RouteParam("team_id").fromContext(test_ctx);
    const user_id = RouteParam("user_id").fromContext(test_ctx);

    const team_id_result = team_id.result catch {
        try testing.expect(false);
        return;
    };
    const user_id_result = user_id.result catch {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("abc", team_id_result.?);
    try testing.expectEqualStrings("42", user_id_result.?);
}

test "extract returns decoded segment" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /blocks/hello%20world HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = "/blocks/:name",
    };
    const name_param = RouteParam("name").fromContext(test_ctx);
    const result = name_param.result catch {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("hello world", result.?);
}

test "extract returns original segment on malformed percent escape" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /blocks/hello%2 HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = "/blocks/:name",
    };
    const name_param = RouteParam("name").fromContext(test_ctx);
    const result = name_param.result catch {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("hello%2", result.?);
}

test "extract returns null when route pattern is missing" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /users/42 HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = null,
    };
    const id_param = RouteParam("id").fromContext(test_ctx);
    const result = id_param.result catch {
        try testing.expect(false);
        return;
    };
    try testing.expectEqual(null, result);
}

test "extract strips query from target and route pattern" {
    const Server = std.http.Server;
    const Reader = std.Io.Reader;
    const Writer = std.Io.Writer;
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const req_bytes = "GET /users/42?verbose=true HTTP/1.1\r\n\r\n";
    var stream_buf_reader = Reader.fixed(req_bytes);
    var write_buffer: [4096]u8 = undefined;
    var stream_buf_writer = Writer.fixed(&write_buffer);
    var http_server = Server.init(&stream_buf_reader, &stream_buf_writer);
    var http_req = try http_server.receiveHead();

    const testing_arena = arena.allocator();
    const test_ctx: Context = .{
        .io = undefined,
        .req_arena = testing_arena,
        .raw_req = &http_req,
        .route_pattern = "/users/:id?unused=true",
    };
    const id_param = RouteParam("id").fromContext(test_ctx);
    const result = id_param.result catch {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("42", result.?);
}
