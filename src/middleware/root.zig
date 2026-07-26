const std = @import("std");
const core = @import("core");
const Context = core.Context;
const Response = core.Response;

pub const logger = @import("logger.zig").logger;
pub const cors = @import("cors.zig").cors;
pub const Cors = @import("cors.zig").Cors;
pub const CorsConfig = @import("cors.zig").CorsConfig;
pub const recovery = @import("recovery.zig").recovery;
pub const requestId = @import("request_id.zig").requestId;

/// Execution continuation interface for middleware pipeline.
/// Call `next.exec(ctx)` to yield control to the next middleware or final route handler.
pub const Next = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        exec: *const fn (ptr: *const anyopaque, ctx: *Context) anyerror!Response,
    };

    pub fn exec(self: *Next, ctx: *Context) anyerror!Response {
        return self.vtable.exec(self.ptr, ctx);
    }
};

/// Type-erased middleware wrapper supporting function pointers and struct instances.
pub const Middleware = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        exec: *const fn (ptr: *const anyopaque, ctx: *Context, next: *Next) anyerror!Response,
    };

    pub fn execute(self: Middleware, ctx: *Context, next: *Next) anyerror!Response {
        return self.vtable.exec(self.ptr, ctx, next);
    }

    pub fn fromFn(comptime func: anytype) Middleware {
        return makeMiddleware(func);
    }

    pub fn fromStruct(comptime T: type, instance_ptr: *const T) Middleware {
        return makeMiddleware(instance_ptr);
    }
};

/// Converts any valid middleware representation (stateless function or stateful struct pointer)
/// into a uniform `Middleware` wrapper.
pub fn makeMiddleware(mw: anytype) Middleware {
    const T = @TypeOf(mw);
    if (T == Middleware) return mw;

    const info = @typeInfo(T);
    const FnType: ?type = if (info == .@"fn")
        T
    else if (info == .pointer and @typeInfo(info.pointer.child) == .@"fn")
        info.pointer.child
    else
        null;

    if (FnType) |Fn| {
        const field_types = @typeInfo(std.meta.ArgsTuple(Fn)).@"struct".field_types;
        if (field_types.len != 2) {
            @compileError("Middleware function must accept 2 parameters: (ctx: *Context, next: *Next)");
        }
        const P0 = field_types[0];
        const impl = struct {
            fn exec(ptr: *const anyopaque, ctx: *Context, next: *Next) anyerror!Response {
                const func: *const Fn = @ptrCast(@alignCast(ptr));
                if (P0 == *Context) {
                    return func(ctx, next);
                } else if (P0 == Context) {
                    return func(ctx.*, next);
                } else {
                    @compileError("First parameter of middleware function must be *Context or Context");
                }
            }
        };

        const fn_ptr: *const Fn = if (info == .pointer) mw else &mw;
        return .{
            .ptr = @ptrCast(fn_ptr),
            .vtable = &.{ .exec = impl.exec },
        };
    } else if (info == .pointer and @typeInfo(info.pointer.child) == .@"struct") {
        const Child = info.pointer.child;
        if (!@hasDecl(Child, "exec")) {
            @compileError("Middleware struct " ++ @typeName(Child) ++ " must declare an 'exec' method");
        }
        const impl = struct {
            fn exec(ptr: *const anyopaque, ctx: *Context, next: *Next) anyerror!Response {
                const self_ptr: *const Child = @ptrCast(@alignCast(ptr));
                return self_ptr.exec(ctx, next);
            }
        };
        return .{
            .ptr = @ptrCast(mw),
            .vtable = &.{ .exec = impl.exec },
        };
    }

    @compileError("Invalid middleware type: " ++ @typeName(T) ++ ". Expected function 'fn(*Context, *Next) !Response' or struct pointer with 'exec' method.");
}

test {
    const refAllDecl = std.testing.refAllDecls;
    _ = refAllDecl(@import("logger.zig"));
    _ = refAllDecl(@import("cors.zig"));
    _ = refAllDecl(@import("recovery.zig"));
    _ = refAllDecl(@import("request_id.zig"));
}
