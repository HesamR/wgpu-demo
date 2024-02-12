const std = @import("std");
const log = std.log.scoped(.nuklear_backend);

const sdl = @import("sdl");
const nk = @import("nuklear");
const wgpu = @import("wgpu");
const tracy = @import("tracy");

const CStyleAllocator = @import("CStyleAllocator.zig");

pub fn toNKAllocator(self: *const CStyleAllocator) nk.Allocator {
    const wrapper = struct {
        pub fn alloc(user_data: nk.Handle, old: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
            _ = old;

            var allocator: *CStyleAllocator = @ptrCast(@alignCast(user_data.ptr));
            const mem = allocator.alloc(size) catch return null;
            return @ptrCast(mem);
        }

        pub fn free(user_data: nk.Handle, ptr: ?*anyopaque) callconv(.C) void {
            if (ptr) |p| {
                var allocator: *CStyleAllocator = @ptrCast(@alignCast(user_data.ptr));
                allocator.free(p);
            }
        }
    };

    return nk.Allocator{
        .alloc = wrapper.alloc,
        .free = wrapper.free,
        .userdata = .{
            .ptr = @constCast(@ptrCast(self)),
        },
    };
}

const Vertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    col: u32,
};

const Uniforms = struct {
    mvp: [16]f32,
    gamma: f32,

    _padding: [3]u32 = .{0} ** 3,
};

const Self = @This();

ctx: nk.Context,

font_atlas: nk.FontAtlas,
null_texture: nk.DrawNullTexture,

nk_allocator: nk.Allocator,

cmd_buffer: nk.Buffer,
vertex_buffer_data: nk.Buffer,
index_buffer_data: nk.Buffer,

font_texture: *wgpu.Texture,
font_texture_view: *wgpu.TextureView,
font_texture_bind_group: *wgpu.BindGroup,

sampler: *wgpu.Sampler,
texture_bind_group_layout: *wgpu.BindGroupLayout,
common_bind_group: *wgpu.BindGroup,

pipeline: *wgpu.RenderPipeline,

uniform_buffer: *wgpu.Buffer,
vertex_buffer: *wgpu.Buffer,
index_buffer: *wgpu.Buffer,

pub fn init(
    allocator: *const CStyleAllocator,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    rt_format: wgpu.TextureFormat,
    depth_format: ?wgpu.TextureFormat,
) !Self {
    var ret: Self = undefined;

    ret.nk_allocator = toNKAllocator(allocator);

    ret.font_atlas = nk.FontAtlas.init(&ret.nk_allocator);
    errdefer ret.font_atlas.clear();

    ret.font_atlas.begin();

    const font = ret.font_atlas.addDefault(13, null);
    const baked = ret.font_atlas.bake(.rgba32);

    ret.font_texture = device.createTexture(.{
        .label = "Nuklear Font",
        .format = .rgba8_unorm,
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .size = .{
            .width = baked.width,
            .height = baked.height,
        },
    });
    errdefer ret.font_texture.release();

    queue.writeTexture(
        .{
            .texture = ret.font_texture,
            .mip_level = 0,
            .origin = .{},
        },
        @ptrCast(baked.image.ptr),
        baked.image.len,
        .{
            .bytes_per_row = baked.width * 4,
            .rows_per_image = baked.height,
            .offset = 0,
        },
        .{
            .width = baked.width,
            .height = baked.height,
        },
    );

    ret.font_texture_view = ret.font_texture.createView(.{});
    errdefer ret.font_texture_view.release();

    ret.texture_bind_group_layout = device.createBindGroupLayout(.{
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{.{
            .binding = 0,
            .visibility = .{ .fragment = true },
            .texture = .{
                .sample_type = .float,
                .view_dimension = .dim_2d,
            },
        }},
    });
    errdefer ret.texture_bind_group_layout.release();

    ret.font_texture_bind_group = device.createBindGroup(.{
        .layout = ret.texture_bind_group_layout,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{.{
            .binding = 0,
            .texture_view = ret.font_texture_view,
        }},
    });
    errdefer ret.font_texture_bind_group.release();

    ret.font_atlas.end(
        .{ .ptr = @ptrCast(ret.font_texture_bind_group) },
        &ret.null_texture,
    );

    ret.ctx = try nk.Context.init(&ret.nk_allocator, &font.handle);

    ret.sampler = device.createSampler(.{ .label = "Nuklear Default Sampler" });
    ret.uniform_buffer = device.createBuffer(.{
        .label = "Nuklear Uniform Buffer",
        .usage = .{
            .copy_dst = true,
            .uniform = true,
        },
        .size = @sizeOf(Uniforms),
    });

    const common_bind_group_layout = device.createBindGroupLayout(.{
        .entry_count = 2,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = .{ .vertex = true, .fragment = true },
                .buffer = .{ .binding_type = .uniform },
            },
            .{
                .binding = 1,
                .visibility = .{ .fragment = true },
                .sampler = .{ .binding_type = .filtering },
            },
        },
    });
    defer common_bind_group_layout.release();

    ret.common_bind_group = device.createBindGroup(.{
        .layout = common_bind_group_layout,
        .entry_count = 2,
        .entries = &[_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = ret.uniform_buffer,
                .size = @sizeOf(Uniforms),
            },
            .{
                .binding = 1,
                .sampler = ret.sampler,
            },
        },
    });

    const pipeline_layout = device.createPipelineLayout(.{
        .bind_group_layout_count = 2,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{
            common_bind_group_layout,
            ret.texture_bind_group_layout,
        },
    });
    defer pipeline_layout.release();

    const shader_module = device.createShaderModule(.{
        .label = "Nuklear Main Shader",
        .next_in_chain = @ptrCast(&wgpu.ShaderModuleWGSLDescriptor{
            .code = @embedFile("shaders/nuklear.wgsl"),
        }),
    });
    defer shader_module.release();

    ret.pipeline = device.createRenderPipeline(.{
        .label = "Nuklear Main RenderPipeline",
        .layout = pipeline_layout,
        .primitive = .{
            .topology = .triangle_list,
            .cull_mode = .none,
            .front_face = .cw,
        },
        .vertex = .{
            .module = shader_module,
            .entry_point = "vs_main",
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{.{
                .array_stride = @sizeOf(Vertex),
                .step_mode = .vertex,
                .attribute_count = 3,
                .attributes = &[_]wgpu.VertexAttribute{
                    .{
                        .format = .float32x2,
                        .offset = @offsetOf(Vertex, "pos"),
                        .shader_location = 0,
                    },
                    .{
                        .format = .float32x2,
                        .offset = @offsetOf(Vertex, "uv"),
                        .shader_location = 1,
                    },
                    .{
                        .format = .unorm8x4,
                        .offset = @offsetOf(Vertex, "col"),
                        .shader_location = 2,
                    },
                },
            }},
        },
        .fragment = &.{
            .module = shader_module,
            .entry_point = "fs_main",
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{.{
                .format = rt_format,
                .blend = &.{
                    .color = .{
                        .src_factor = .src_alpha,
                        .dst_factor = .one_minus_src_alpha,
                        .operation = .add,
                    },
                    .alpha = .{
                        .src_factor = .src_alpha,
                        .dst_factor = .one,
                        .operation = .add,
                    },
                },
            }},
        },
        .depth_stencil = if (depth_format) |f| &.{
            .format = f,
            .depth_compare = .always,
        } else null,
    });

    ret.vertex_buffer = device.createBuffer(.{
        .label = "Nuklear Vertex Buffer",
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = 512 * 1024,
    });

    ret.index_buffer = device.createBuffer(.{
        .label = "Nuklear Index Buffer",
        .usage = .{ .copy_dst = true, .index = true },
        .size = 128 * 1024,
    });

    ret.cmd_buffer = nk.Buffer.init(&ret.nk_allocator, 4096);
    ret.vertex_buffer_data = nk.Buffer.init(&ret.nk_allocator, 4096);
    ret.index_buffer_data = nk.Buffer.init(&ret.nk_allocator, 4096);

    return ret;
}

pub fn deinit(self: *Self) void {
    self.index_buffer.release();
    self.vertex_buffer.release();

    self.pipeline.release();
    self.common_bind_group.release();
    self.uniform_buffer.release();
    self.sampler.release();

    self.cmd_buffer.free();
    self.vertex_buffer_data.free();
    self.index_buffer_data.free();
    self.ctx.free();

    self.font_texture_bind_group.release();
    self.texture_bind_group_layout.release();
    self.font_texture_view.release();
    self.font_texture.release();

    self.font_atlas.clear();
}

pub fn beginInput(self: *Self) void {
    self.ctx.inputBegin();
}

pub fn endInput(self: *Self) void {
    self.ctx.inputEnd();
}

pub fn processInput(self: *Self, event: sdl.Event) void {
    switch (event.type) {
        .key_up, .key_down => {
            const down = event.key.state == .pressed;
            const lctrl = event.key.keysym.mod.lctrl;

            switch (event.key.keysym.keycode) {
                .lshift, .rshift => self.ctx.inputKey(.shift, down),
                .delete => self.ctx.inputKey(.del, down),
                .enter, .kp_enter => self.ctx.inputKey(.enter, down),
                .tab => self.ctx.inputKey(.tab, down),
                .backspace => self.ctx.inputKey(.backspace, down),

                .home => {
                    self.ctx.inputKey(.text_start, down);
                    self.ctx.inputKey(.scroll_start, down);
                },

                .end => {
                    self.ctx.inputKey(.text_end, down);
                    self.ctx.inputKey(.scroll_end, down);
                },

                .pagedown => self.ctx.inputKey(.scroll_down, down),
                .pageup => self.ctx.inputKey(.scroll_up, down),

                .z => if (lctrl) self.ctx.inputKey(.text_undo, down),
                .r => if (lctrl) self.ctx.inputKey(.text_redo, down),
                .c => if (lctrl) self.ctx.inputKey(.copy, down),
                .v => if (lctrl) self.ctx.inputKey(.paste, down),
                .x => if (lctrl) self.ctx.inputKey(.cut, down),
                .b => if (lctrl) self.ctx.inputKey(.text_line_start, down),
                .e => if (lctrl) self.ctx.inputKey(.text_line_end, down),
                .up => self.ctx.inputKey(.up, down),
                .down => self.ctx.inputKey(.down, down),

                .left => if (lctrl)
                    self.ctx.inputKey(.text_word_left, down)
                else
                    self.ctx.inputKey(.left, down),

                .right => if (lctrl)
                    self.ctx.inputKey(.text_word_right, down)
                else
                    self.ctx.inputKey(.right, down),

                else => {},
            }
        },

        .mouse_button_up,
        .mouse_button_down,
        => {
            const down = event.button.state == .pressed;

            const x: c_int = @intFromFloat(event.button.x);
            const y: c_int = @intFromFloat(event.button.y);

            switch (event.button.button) {
                .left => {
                    if (event.button.clicks > 1)
                        self.ctx.inputButton(.double, x, y, down);
                    self.ctx.inputButton(.left, x, y, down);
                },

                .middle => self.ctx.inputButton(.middle, x, y, down),
                .right => self.ctx.inputButton(.right, x, y, down),

                else => {},
            }
        },

        .mouse_motion => {
            const x: c_int = @intFromFloat(event.motion.x);
            const y: c_int = @intFromFloat(event.motion.y);

            self.ctx.inputMotion(x, y);
        },

        .text_input => {
            self.ctx.inputGlyph(event.text.text[0..nk.utf_size].ptr);
        },

        .mouse_wheel => {
            self.ctx.inputScroll(.{
                .x = event.wheel.x,
                .y = event.wheel.y,
            });
        },

        else => {},
    }
}

pub fn render(
    self: *Self,
    queue: *wgpu.Queue,
    render_pass: *wgpu.RenderPassEncoder,
    width: f32,
    height: f32,
) !void {
    const res = self.ctx.convert(
        &self.cmd_buffer,
        &self.vertex_buffer_data,
        &self.index_buffer_data,
        .{
            .global_alpha = 1,
            .circle_segment_count = 22,
            .curve_segment_count = 22,
            .arc_segment_count = 22,
            .line_AA = .on,
            .shape_AA = .on,
            .tex_null = self.null_texture,
            .vertex_size = @sizeOf(Vertex),
            .vertex_alignment = @alignOf(Vertex),
            .vertex_layout = &[_]nk.DrawVertexLayoutElement{
                .{
                    .attribute = .position,
                    .format = .float,
                    .offset = @offsetOf(Vertex, "pos"),
                },
                .{
                    .attribute = .texcoord,
                    .format = .float,
                    .offset = @offsetOf(Vertex, "uv"),
                },
                .{
                    .attribute = .color,
                    .format = .rgba32,
                    .offset = @offsetOf(Vertex, "col"),
                },
                nk.draw_vertex_layout_end,
            },
        },
    );
    defer self.vertex_buffer_data.clear();
    defer self.index_buffer_data.clear();
    defer self.cmd_buffer.clear();

    if (@as(u32, @bitCast(res)) != 0) {
        return error.NuklearConvertError;
    }

    if (self.vertex_buffer_data.allocated == 0 or
        self.index_buffer_data.allocated == 0) return;

    queue.writeBuffer(
        self.index_buffer,
        0,
        self.index_buffer_data.memory.ptr.?,
        self.index_buffer_data.memory.size,
    );

    queue.writeBuffer(
        self.vertex_buffer,
        0,
        self.vertex_buffer_data.memory.ptr.?,
        self.vertex_buffer_data.memory.size,
    );

    queue.writeBuffer(
        self.uniform_buffer,
        0,
        @ptrCast(&Uniforms{
            .mvp = .{
                2.0 / width, 0.0,           0.0,  0.0,
                0.0,         -2.0 / height, 0.0,  0.0,
                0.0,         0.0,           -1.0, 0.0,
                -1.0,        1.0,           0.0,  1.0,
            },
            .gamma = 2.2,
        }),
        @sizeOf(Uniforms),
    );

    render_pass.setViewport(0, 0, width, height, 0, 1);
    render_pass.setPipeline(self.pipeline);
    render_pass.setBindGroup(0, self.common_bind_group, &.{});
    render_pass.setIndexBuffer(
        self.index_buffer,
        .uint16,
        0,
        self.index_buffer_data.allocated,
    );
    render_pass.setVertexBuffer(
        0,
        self.vertex_buffer,
        0,
        self.vertex_buffer_data.allocated,
    );

    var offset: u32 = 0;
    var iter = self.ctx.drawCommandIterator(&self.cmd_buffer);
    while (iter.next()) |cmd| {
        if (cmd.elem_count == 0) continue;

        render_pass.setBindGroup(1, @ptrCast(cmd.texture.ptr.?), &.{});
        render_pass.drawIndexed(@intCast(cmd.elem_count), 1, offset, 0, 0);

        offset += @intCast(cmd.elem_count);
    }
}
