const std = @import("std");
const log = std.log.scoped(.main_pass);

const wgpu = @import("wgpu");
const tracy = @import("tracy");
const obj = @import("zig-obj");
const nk = @import("nuklear");

const lg = @import("linalg.zig");

const GraphicContext = @import("GraphicContext.zig");
const DebugRenderer = @import("DebugRenderer.zig");
const Mesh = @import("Mesh.zig");

const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32,
    norm: [3]f32,
};

const Uniform = struct {
    mvp: lg.Mat4,
};

const Self = @This();

index_buffer: *wgpu.Buffer,
vertex_buffer: *wgpu.Buffer,
uniform_buffer: *wgpu.Buffer,
draw_cmd_buffer: *wgpu.Buffer,

cmds_count: usize,

pipeline: *wgpu.RenderPipeline,
bind_group: *wgpu.BindGroup,

monkey_sphere: lg.Sphere,
pirate_sphere: lg.Sphere,

pirate_aabb: lg.AABB,

rot: f32 = 0,
space: f32 = 1,
scale: f32 = 1,

pos: lg.Vec3 = lg.Vec3.zero,

pub fn init(allocator: std.mem.Allocator, context: GraphicContext) !Self {
    const monkey_mesh = try Mesh.init(allocator, @embedFile("assets/monkey.obj"));
    defer monkey_mesh.deinit(allocator);

    const pirate_mesh = try Mesh.init(allocator, @embedFile("assets/pirate.obj"));
    defer pirate_mesh.deinit(allocator);

    const index_buffer = context.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = (monkey_mesh.indices.len + pirate_mesh.indices.len) * @sizeOf(c_uint),
    });

    const vertex_buffer = context.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = (monkey_mesh.vertices.len + pirate_mesh.vertices.len) * @sizeOf(Vertex),
    });

    context.queue.writeBuffer(
        index_buffer,
        0,
        @ptrCast(monkey_mesh.indices.ptr),
        monkey_mesh.indices.len * @sizeOf(c_uint),
    );

    context.queue.writeBuffer(
        index_buffer,
        monkey_mesh.indices.len * @sizeOf(c_uint),
        @ptrCast(pirate_mesh.indices.ptr),
        pirate_mesh.indices.len * @sizeOf(c_uint),
    );

    context.queue.writeBuffer(
        vertex_buffer,
        0,
        @ptrCast(monkey_mesh.vertices.ptr),
        monkey_mesh.vertices.len * @sizeOf(Vertex),
    );

    context.queue.writeBuffer(
        vertex_buffer,
        monkey_mesh.vertices.len * @sizeOf(Vertex),
        @ptrCast(pirate_mesh.vertices.ptr),
        pirate_mesh.vertices.len * @sizeOf(Vertex),
    );

    const shader_module = context.device.createShaderModule(.{
        .next_in_chain = @ptrCast(&wgpu.ShaderModuleWGSLDescriptor{
            .code = @embedFile("shaders/shader.wgsl"),
        }),
    });
    defer shader_module.release();

    const bind_group_layout = context.device.createBindGroupLayout(.{
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{.{
            .binding = 0,
            .buffer = .{ .binding_type = .uniform },
            .visibility = .{ .vertex = true, .fragment = true },
        }},
    });
    defer bind_group_layout.release();

    const pipeline_layout = context.device.createPipelineLayout(.{
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{
            bind_group_layout,
        },
    });
    defer pipeline_layout.release();

    const pipeline = context.device.createRenderPipeline(.{
        .layout = pipeline_layout,
        .primitive = .{
            .topology = .triangle_list,
            .cull_mode = .front,
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
                        .format = .float32x3,
                        .offset = @offsetOf(Vertex, "pos"),
                        .shader_location = 0,
                    },
                    .{
                        .format = .float32x2,
                        .offset = @offsetOf(Vertex, "uv"),
                        .shader_location = 1,
                    },
                    .{
                        .format = .float32x3,
                        .offset = @offsetOf(Vertex, "norm"),
                        .shader_location = 2,
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

    const cmds = [_]wgpu.DrawIndexedIndirect{
        .{
            .vertex_count = @intCast(monkey_mesh.indices.len),
            .instance_count = 1,
            .base_index = 0,
            .vertex_offset = 0,
            .base_instance = 0,
        },
        .{
            .vertex_count = @intCast(monkey_mesh.indices.len),
            .instance_count = 1,
            .base_index = 0,
            .vertex_offset = 0,
            .base_instance = 1,
        },
        .{
            .vertex_count = @intCast(pirate_mesh.indices.len),
            .instance_count = 1,
            .base_index = @intCast(monkey_mesh.indices.len),
            .vertex_offset = @intCast(monkey_mesh.vertices.len),
            .base_instance = 2,
        },
        .{
            .vertex_count = @intCast(pirate_mesh.indices.len),
            .instance_count = 1,
            .base_index = @intCast(monkey_mesh.indices.len),
            .vertex_offset = @intCast(monkey_mesh.vertices.len),
            .base_instance = 3,
        },
    };
    const count = wgpu.DrawIndirectCount{ .count = @intCast(cmds.len) };

    const uniform_buffer = context.device.createBuffer(.{
        .usage = .{ .uniform = true, .copy_dst = true },
        .size = @sizeOf(Uniform) * cmds.len,
    });

    const bind_group = context.device.createBindGroup(.{
        .layout = bind_group_layout,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{.{
            .binding = 0,
            .buffer = uniform_buffer,
            .size = @sizeOf(Uniform) * cmds.len,
        }},
    });

    const draw_cmd_buffer = context.device.createBuffer(.{
        .usage = .{ .copy_dst = true, .indirect = true },
        .size = @sizeOf(@TypeOf(count)) + @sizeOf(@TypeOf(cmds)),
    });

    context.queue.writeBuffer(
        draw_cmd_buffer,
        0,
        @ptrCast(&count),
        @sizeOf(wgpu.DrawIndirectCount),
    );

    context.queue.writeBuffer(
        draw_cmd_buffer,
        @sizeOf(wgpu.DrawIndirectCount),
        @ptrCast(&cmds),
        @sizeOf(wgpu.DrawIndexedIndirect) * cmds.len,
    );

    return .{
        .index_buffer = index_buffer,
        .vertex_buffer = vertex_buffer,
        .uniform_buffer = uniform_buffer,
        .draw_cmd_buffer = draw_cmd_buffer,

        .monkey_sphere = monkey_mesh.bounding_sphere,
        .pirate_sphere = pirate_mesh.bounding_sphere,

        .pirate_aabb = pirate_mesh.aabb,

        .cmds_count = cmds.len,

        .pipeline = pipeline,
        .bind_group = bind_group,
    };
}

pub fn deinit(self: Self) void {
    self.bind_group.release();
    self.pipeline.release();
    self.draw_cmd_buffer.release();
    self.uniform_buffer.release();
    self.vertex_buffer.release();
}

pub fn update(
    self: *Self,
    queue: *wgpu.Queue,
    ctx: *nk.Context,
    view_proj: lg.Mat4,
    debug_renderer: *DebugRenderer,
) !void {
    if (ctx.begin(
        "main pass",
        nk.Rect.new(100, 100, 150, 200),
        nk.WindowFlags.default,
    )) {
        ctx.layoutRowDynamic(20, 1);
        ctx.propertyFloat("rotation", 0, &self.rot, 6.29, 0.1, 0.01);
        ctx.propertyFloat("space", 1, &self.space, 4, 0.1, 0.01);
        ctx.propertyFloat("scale", 0.5, &self.scale, 4, 0.1, 0.01);
        ctx.spacer();
        ctx.label("Position: ", nk.TextAlignFlags.left);
        ctx.propertyFloat("x", -4, &self.pos.x, 4, 0.1, 0.01);
        ctx.propertyFloat("y", -4, &self.pos.y, 4, 0.1, 0.01);
        ctx.propertyFloat("z", -4, &self.pos.z, 4, 0.1, 0.01);
    }
    ctx.end();

    var tran1 = lg.Transform.fromPosition(lg.vec3(2 * self.space, 0, 2));
    tran1.scale = lg.Vec3.one.scale(self.scale);
    tran1.rotate(lg.Quat.fromAxisY(self.rot));
    const model1 = tran1.computeMat();

    var tran2 = lg.Transform.fromPosition(lg.vec3(-1 * self.space, 0, 2));
    tran2.rotateAround(lg.vec3(0, 0, 0), lg.Quat.fromAxisY(self.rot));
    const model2 = tran2.computeMat();

    var tran3 = lg.Transform.fromPosition(self.pos);
    const model3 = tran3.computeMat();

    var tran4 = lg.Transform.fromPosition(lg.vec3(1 * self.space, -0.5, 4));
    tran4.lookAt(self.pos);
    const model4 = tran4.computeMat();

    const sp1 = tran1.transformSphere(self.monkey_sphere);
    const sp2 = tran2.transformSphere(self.monkey_sphere);
    const sp3 = tran3.transformSphere(self.pirate_sphere);
    const sp4 = tran4.transformSphere(self.pirate_sphere);

    try debug_renderer.sphere(sp1, DebugRenderer.Color.red);
    try debug_renderer.sphere(sp2, DebugRenderer.Color.green);
    try debug_renderer.sphere(sp3, DebugRenderer.Color.blue);
    try debug_renderer.sphere(sp4, DebugRenderer.Color.yellow);

    try debug_renderer.aabb(self.pirate_aabb, DebugRenderer.Color.white);

    const uniform = [_]Uniform{
        .{ .mvp = model1.mul(view_proj) },
        .{ .mvp = model2.mul(view_proj) },
        .{ .mvp = model3.mul(view_proj) },
        .{ .mvp = model4.mul(view_proj) },
    };

    queue.writeBuffer(
        self.uniform_buffer,
        0,
        @ptrCast(&uniform),
        @sizeOf(@TypeOf(uniform)),
    );
}

pub fn render(self: Self, render_pass: *wgpu.RenderPassEncoder) void {
    render_pass.setBindGroup(0, self.bind_group, &.{});
    render_pass.setPipeline(self.pipeline);

    render_pass.setIndexBuffer(
        self.index_buffer,
        .uint32,
        0,
        self.index_buffer.getSize(),
    );

    render_pass.setVertexBuffer(
        0,
        self.vertex_buffer,
        0,
        self.vertex_buffer.getSize(),
    );

    render_pass.multiDrawIndexedIndirectCount(
        self.draw_cmd_buffer,
        @sizeOf(wgpu.DrawIndirectCount),
        self.draw_cmd_buffer,
        0,
        @intCast(self.cmds_count),
    );
}
