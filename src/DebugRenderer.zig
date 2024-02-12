const std = @import("std");
const math = std.math;
const log = std.log.scoped(.debug_renderer);

const wgpu = @import("wgpu");
const tracy = @import("tracy");

const lg = @import("linalg.zig");
const Mat4 = lg.Mat4;
const Vec3 = lg.Vec3;
const vec3 = lg.vec3;

const GraphicContext = @import("GraphicContext.zig");

pub const Color = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const black = rgb(0, 0, 0);
    pub const white = rgb(255, 255, 255);
    pub const red = rgb(255, 0, 0);
    pub const green = rgb(0, 255, 0);
    pub const blue = rgb(0, 0, 255);
    pub const yellow = rgb(255, 255, 0);

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return rgba(r, g, b, 255);
    }
};

const Vertex = extern struct {
    pos: [3]f32,
    col: Color,
};

const Uniform = struct {
    mvp: Mat4,
};

const Self = @This();

vertices: std.ArrayList(Vertex),

vertex_buffer: *wgpu.Buffer,
uniform_buffer: *wgpu.Buffer,

bind_group: *wgpu.BindGroup,
pipeline: *wgpu.RenderPipeline,

pub fn init(allocator: std.mem.Allocator, context: GraphicContext) Self {
    const vertex_buffer = context.device.createBuffer(.{
        .label = "Debug Renderer Vertex Buffer",
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = 1024 * 1024,
    });

    const uniform_buffer = context.device.createBuffer(.{
        .label = "Debug Renderer Uniform Buffer",
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(Uniform),
    });

    const bind_group_layout = context.device.createBindGroupLayout(.{
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{.{
            .binding = 0,
            .visibility = .{ .vertex = true },
            .buffer = .{ .binding_type = .uniform },
        }},
    });
    defer bind_group_layout.release();

    const pipeline_layout = context.device.createPipelineLayout(.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{bind_group_layout},
    });
    defer pipeline_layout.release();

    const shader_module = context.device.createShaderModule(.{
        .next_in_chain = @ptrCast(&wgpu.ShaderModuleWGSLDescriptor{
            .code = @embedFile("shaders/debug.wgsl"),
        }),
    });
    defer shader_module.release();

    const pipeline = context.device.createRenderPipeline(.{
        .label = "Debug Renderer Main Pipeline",
        .layout = pipeline_layout,
        .primitive = .{
            .topology = .line_list,
        },
        .vertex = .{
            .module = shader_module,
            .entry_point = "vs_main",
            .buffer_count = 1,
            .buffers = &[_]wgpu.VertexBufferLayout{.{
                .array_stride = @sizeOf(Vertex),
                .step_mode = .vertex,
                .attribute_count = 2,
                .attributes = &[_]wgpu.VertexAttribute{
                    .{
                        .format = .float32x3,
                        .offset = @offsetOf(Vertex, "pos"),
                        .shader_location = 0,
                    },
                    .{
                        .format = .unorm8x4,
                        .offset = @offsetOf(Vertex, "col"),
                        .shader_location = 1,
                    },
                },
            }},
        },
        .fragment = &.{
            .module = shader_module,
            .entry_point = "fs_main",
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{
                .{ .format = context.surface_config.format },
            },
        },
        .depth_stencil = &.{
            .format = context.depth_buffer_format,
            .depth_write_enabled = .true,
            .depth_compare = .less_equal,
        },
    });

    const bind_group = context.device.createBindGroup(.{
        .layout = bind_group_layout,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{.{
            .binding = 0,
            .buffer = uniform_buffer,
            .size = @sizeOf(Uniform),
        }},
    });

    return .{
        .vertices = std.ArrayList(Vertex).init(allocator),

        .vertex_buffer = vertex_buffer,
        .uniform_buffer = uniform_buffer,

        .bind_group = bind_group,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: Self) void {
    self.pipeline.release();
    self.bind_group.release();
    self.uniform_buffer.release();
    self.vertex_buffer.release();
    self.vertices.deinit();
}

pub fn render(self: *Self, queue: *wgpu.Queue, render_pass: *wgpu.RenderPassEncoder, mvp: Mat4) void {
    if (self.vertices.items.len == 0) return;

    queue.writeBuffer(
        self.vertex_buffer,
        0,
        @ptrCast(self.vertices.items.ptr),
        self.vertices.items.len * @sizeOf(Vertex),
    );

    queue.writeBuffer(
        self.uniform_buffer,
        0,
        @ptrCast(&Uniform{ .mvp = mvp }),
        @sizeOf(Uniform),
    );

    render_pass.setBindGroup(0, self.bind_group, &.{});
    render_pass.setPipeline(self.pipeline);
    render_pass.setVertexBuffer(
        0,
        self.vertex_buffer,
        0,
        self.vertices.items.len * @sizeOf(Vertex),
    );
    render_pass.draw(@intCast(self.vertices.items.len), 1, 0, 0);

    self.vertices.clearRetainingCapacity();
}

pub fn line(self: *Self, p1: Vec3, p2: Vec3, color: Color) !void {
    try self.vertices.appendSlice(&.{
        .{ .pos = p1.toArr(), .col = color },
        .{ .pos = p2.toArr(), .col = color },
    });
}

pub fn aabb(self: *Self, ab: lg.AABB, color: Color) !void {
    const center = ab.center();
    const half_points = ab.max.sub(center);

    const vertices = [_]Vec3{
        ab.min,
        ab.min.add(lg.vec3(2 * half_points.x, 0, 0)),
        ab.max.sub(lg.vec3(0, 2 * half_points.y, 0)),
        ab.min.add(lg.vec3(0, 0, 2 * half_points.z)),
        ab.min.add(lg.vec3(0, 2 * half_points.y, 0)),
        ab.max.sub(lg.vec3(0, 0, 2 * half_points.z)),
        ab.max,
        ab.max.sub(lg.vec3(2 * half_points.x, 0, 0)),
    };

    const indices = [_]usize{
        0, 1, 2, 3,
        0, 4, 5, 6,
        7, 4, 5, 1,
        2, 6, 7, 3,
    };

    var last = indices[0];

    for (1..indices.len) |i| {
        try self.line(
            vertices[indices[last]],
            vertices[indices[i]],
            color,
        );

        last = i;
    }
}

pub fn sphere(self: *Self, sph: lg.Sphere, color: Color) !void {
    const center = sph.center;
    const radius = sph.radius;

    const step_t = 2 * math.pi / 16.0;
    const step_p = math.pi / 8.0;

    for (0..8) |i| {
        const i_f: f32 = @floatFromInt(i);

        var last = center.add(sphereEq(0, i_f * step_p, radius));

        for (0..16) |j| {
            const j_f: f32 = @floatFromInt(j + 1);

            const cur = center.add(sphereEq(j_f * step_t, i_f * step_p, radius));

            try self.line(last, cur, color);

            last = cur;
        }
    }

    const step_t2 = 2 * math.pi / 8.0;
    const step_p2 = math.pi / 16.0;

    for (0..8) |i| {
        const i_f: f32 = @floatFromInt(i);

        var last = center.add(sphereEq(i_f * step_t2, 0, radius));

        for (0..16) |j| {
            const j_f: f32 = @floatFromInt(j + 1);

            const cur = center.add(sphereEq(i_f * step_t2, j_f * step_p2, radius));

            try self.line(last, cur, color);

            last = cur;
        }
    }
}

pub fn sphereEq(theta: f32, phi: f32, radius: f32) Vec3 {
    return vec3(
        radius * @cos(theta) * @sin(phi),
        radius * @sin(theta) * @sin(phi),
        radius * @cos(phi),
    );
}
