/// Creates a `Json` extractor type.
///
/// The resulting extractor struct contains:
/// - `result`: `JsonError!T`
///
/// `result` is successful when request validation and JSON parsing succeed.
/// Validation requires:
/// - a method that supports request bodies,
/// - `Content-Type: application/json`,
/// - a non-zero `Content-Length`,
/// - and a valid JSON body that matches `T`.
///
/// The extractor can be used either:
/// - as a router handler parameter (automatic injection), or
/// - manually inside a handler body with `Json(T).init(ctx)`.
///
/// ```zig
/// const Person = struct {
///     name: []const u8,
///     age: u7,
/// };
///
/// fn handleRequest(ctx: Context, person: Json(Person)) !Response {
///     const payload = person.result catch |e| {
///         // Handle JSON or validation error.
///         return Response.text(ctx.req_arena, .bad_request, @errorName(e), null);
///     };
///
///     _ = payload;
///     return Response.ok(ctx.req_arena, null, null);
/// }
/// ```
pub const Json = @import("json.zig").Json;

/// Creates a `Query` extractor type for a single query parameter.
///
/// The resulting extractor struct contains:
/// - `result`: `QueryError!?[]const u8`
///
/// `result` semantics:
/// - `error`: malformed percent-encoding or allocator failure while decoding
/// - `null`: query string missing, parameter missing, or parameter present with an empty value
/// - `[]const u8`: decoded parameter value
///
/// Parameter-name matching is case-insensitive and compares against the decoded key.
/// The extractor can be used either:
/// - as a router handler parameter (automatic injection), or
/// - manually inside a handler body with `Query(name).init(ctx)`.
///
/// ```zig
/// fn handleRequest(ctx: Context, filter: Query("filter")) !Response {
///     const maybe_filter = filter.result catch |e| {
///         return Response.text(ctx.req_arena, .bad_request, @errorName(e), null);
///     };
///
///     _ = maybe_filter;
///     return Response.ok(ctx.req_arena, null, null);
/// }
/// ```
pub const Query = @import("query.zig").Query;

/// Creates a `TypedQuery` extractor type.
///
/// `T` must be a struct where every field is optional.
/// Field names are matched case-insensitively against query keys.
///
/// The resulting extractor struct contains:
/// - `result`: `QueryError!?*T`
///
/// `result` semantics:
/// - `error`: malformed percent-encoding or allocator failure
/// - `null`: request target has no query string
/// - `*T`: allocated struct with each field set from matching query keys (unmatched fields are `null`)
///
/// The extractor can be used either:
/// - as a router handler parameter (automatic injection), or
/// - manually inside a handler body with `TypedQuery(T).init(ctx)`.
///
/// ```zig
/// const Filter = struct {
///     name: ?[]const u8,
///     age: ?u8,
/// };
///
/// fn handleRequest(ctx: Context, filter: TypedQuery(Filter)) !Response {
///     const maybe_filter = filter.result catch |e| {
///         return Response.text(ctx.req_arena, .bad_request, @errorName(e), null);
///     };
///
///     _ = maybe_filter;
///     return Response.ok(ctx.req_arena, null, null);
/// }
/// ```
pub const TypedQuery = @import("typed_query.zig").TypedQuery;

/// Creates a `WebSocket` extractor.
///
/// The extractor struct contains:
/// - `result`: `WebSocketError!Socket`
///
/// On success, the HTTP request is upgraded and a connected socket is available.
///
/// The extractor can be used either:
/// - as a router handler parameter (automatic injection), or
/// - manually inside a handler body with `WebSocket{ .result = WebSocket.init(ctx) }`.
///
/// In handlers, call `onConnected` to run your connection routine, then return `Response.empty`.
///
/// ```zig
/// fn handleRequest(ctx: Context, ws: WebSocket) !Response {
///     try ws.onConnected(handleWebSocket, .{ ctx });
///     return Response.empty;
/// }
/// ```
pub const WebSocket = @import("WebSocket.zig");

/// Creates a Header extractor type for a specific HTTP header name.
///
/// Fields:
/// - `value` An optional slice of bytes that contains the value of the header if it is present in the request,
/// or `null` if the header is absent
///
/// Header name comparison is case-insensitive.
///
/// Example usage in a router handler:
/// ```zig
/// fn handleRequest(ctx: Context, auth: Header("Authorization")) !Response {
///     const token = auth.value orelse return Response.unauthorized();
///     // Use token...
/// }
///
/// fn handleRequest(ctx: Context) !Response {
///     const auth = try Header("Authorization").init(ctx);
///     const token = auth.value orelse return Response.unauthorized();
///     // Use token...
/// }
/// ```
pub const Header = @import("header.zig").Header;

/// Creates a 'RouteParam' extractor type
///
/// Fields:
/// - `value`: An optional slice of bytes that contains the value of the route parameter if it is present in the request, or `null` if the parameter is absent.
///
/// The extractor can be used only as a router handler parameter (automatic injection), or
///
/// ```zig
/// fn handleRequest(ctx: Context, id: RouteParam("id")) !Response {
///    if (id.value) |id_value| {
///       // Use id_value...
///    }
/// }
/// ```
pub const RouteParam = @import("route_param.zig").RouteParam;

/// Creates a `Form` extractor type
///
/// The resulting extractor struct contains:
/// - `result`: `FormError!*T`
///
/// `result` semantics:
/// - `error`: parsing error (e.g., malformed multipart body, invalid percent-encoding, unsupported content type, allocator failure, etc.)
/// - `T`: decoded form value of type `T`, where `T` is a struct with fields corresponding to form keys
///
/// Parameter-name matching is case-insensitive and compares against the decoded key.
/// Value decoding is single-pass (`+` -> space, `%XX` escapes decoded once).
///
/// The extractor can be used either:
/// - as a router handler parameter (automatic injection), or
/// - manually inside a handler body with `Form(T).init(ctx)`.
///
/// ```zig
/// fn handleRequest(ctx: Context, form: Form(Person)) !Response {
///     const form_data = form.result catch |e| {
///         return Response.text(ctx.req_arena, .bad_request, @errorName(e), null);
///     };
///
///     _ = form_data;
///     return Response.ok(ctx.req_arena, null, null);
/// }
/// ```
pub const Form = @import("form.zig").Form;

test {
    const refAllDecls = @import("std").testing.refAllDecls;
    _ = refAllDecls(@import("json.zig"));
    _ = refAllDecls(@import("query.zig"));
    _ = refAllDecls(@import("typed_query.zig"));
    _ = refAllDecls(@import("header.zig"));
    _ = refAllDecls(@import("route_param.zig"));
    _ = refAllDecls(@import("form.zig"));
    _ = refAllDecls(@import("WebSocket.zig"));
    _ = refAllDecls(@import("QueryIterator.zig"));
    _ = refAllDecls(@import("url.zig"));
}
