const std = @import("std");
const log = std.log.scoped(.main);

pub const std_options = struct {
    pub const log_level = .debug;
    // pub const logFn = tracy.logFn;
};

const sdl = @import("sdl");
const wgpu = @import("wgpu");
const tracy = @import("tracy");
const nk = @import("nuklear");

const CStyleAllocator = @import("CStyleAllocator.zig");
const GraphicContext = @import("GraphicContext.zig");
const NuklearBackend = @import("NuklearBackend.zig");
const DebugRenderer = @import("DebugRenderer.zig");
const DebugCamera = @import("DebugCamera.zig");
const MainPass = @import("MainPass.zig");
const Mesh = @import("Mesh.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var tracing_allocator = tracy.TracingAllocator.init(gpa.allocator());
    const allocator = tracing_allocator.allocator();

    const c_style_allocator = CStyleAllocator.init(allocator);

    var context = try GraphicContext.init(960, 540);
    defer context.deinit();

    var nk_backend = try NuklearBackend.init(
        &c_style_allocator,
        context.device,
        context.queue,
        context.surface_config.format,
        null,
    );
    defer nk_backend.deinit();

    var debug_renderer = DebugRenderer.init(allocator, context);
    defer debug_renderer.deinit();

    var debug_camera = DebugCamera.init(2, 0.03);

    var main_pass = try MainPass.init(allocator, context);
    defer main_pass.deinit();

    var event: sdl.Event = undefined;

    main: while (true) {
        tracy.frameMark();

        nk_backend.beginInput();
        while (sdl.pollEvent(&event)) {
            nk_backend.processInput(event);
            debug_camera.processInput(event);

            switch (event.type) {
                .quit => break :main,
                else => {},
            }
        }
        nk_backend.endInput();

        try debug_camera.update(1.0 / 60.0);

        var width_i: c_int = 0;
        var height_i: c_int = 0;
        try context.window.getSize(&width_i, &height_i);

        const view_proj = debug_camera.getMat(
            @floatFromInt(width_i),
            @floatFromInt(height_i),
        );

        try main_pass.update(context.queue, &nk_backend.ctx, view_proj, &debug_renderer);

        const frame = context.surface.getGetCurrentTexture();
        defer if (frame.texture) |tex| tex.release();

        switch (frame.status) {
            .success => {},
            .timeout, .outdated, .lost => continue,
            .device_lost, .out_of_memory => return error.WGPUSurfaceGetCurrentTextureFailed,
        }

        const view = frame.texture.?.createView(.{});
        defer view.release();

        const encoder = context.device.createCommandEncoder(.{});
        defer encoder.release();

        const render_pass = encoder.beginRenderPass(.{
            .color_attachment_count = 1,
            .color_attachments = &[_]wgpu.RenderPassColorAttachment{.{
                .view = view,
                .load_op = .clear,
                .store_op = .store,
            }},
            .depth_stencil_attachment = &.{
                .view = context.depth_buffer_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1,
            },
        });

        main_pass.render(render_pass);

        render_pass.end();

        const debug_render_pass = encoder.beginRenderPass(.{
            .color_attachment_count = 1,
            .color_attachments = &[_]wgpu.RenderPassColorAttachment{.{
                .view = view,
                .load_op = .load,
                .store_op = .store,
            }},
            .depth_stencil_attachment = &.{
                .view = context.depth_buffer_view,
                .depth_load_op = .load,
                .depth_store_op = .store,
                .depth_clear_value = 1,
            },
        });

        debug_renderer.render(context.queue, debug_render_pass, view_proj);

        debug_render_pass.end();

        const nk_render_pass = encoder.beginRenderPass(.{
            .color_attachment_count = 1,
            .color_attachments = &[_]wgpu.RenderPassColorAttachment{.{
                .view = view,
                .load_op = .load,
                .store_op = .store,
            }},
        });

        try nk_backend.render(
            context.queue,
            nk_render_pass,
            @floatFromInt(width_i),
            @floatFromInt(height_i),
        );

        nk_render_pass.end();

        const command_buffer = encoder.finish(.{});
        defer command_buffer.release();

        context.queue.submit(&.{command_buffer});
        context.surface.preset();

        nk_backend.ctx.clear();
    }
}
