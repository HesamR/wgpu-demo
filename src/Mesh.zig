const std = @import("std");
const log = std.log.scoped(.mesh);

const obj = @import("obj");
const meshopt = @import("meshoptimizer");
const tracy = @import("tracy");

const lg = @import("linalg.zig");

const Self = @This();

pub const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32,
    norm: [3]f32,
};

bounding_sphere: lg.Sphere,
aabb: lg.AABB,

vertices: []Vertex,
indices: []c_uint,
shadow_indices: []c_uint,

pub fn init(allocator: std.mem.Allocator, obj_file: []const u8) !Self {
    var obj_data = try obj.parseObj(allocator, obj_file);
    defer obj_data.deinit(allocator);

    var vertex_list = std.ArrayList(Vertex).init(allocator);
    defer vertex_list.deinit();

    for (obj_data.meshes) |mesh| {
        for (mesh.indices) |face| {
            const pos_idx: usize = @intCast(face.vertex.? * 3);
            const uv_idx: usize = @intCast(face.tex_coord.? * 2);
            const norm_idx: usize = @intCast(face.normal.? * 3);

            try vertex_list.append(.{
                .pos = .{
                    obj_data.vertices[pos_idx],
                    obj_data.vertices[pos_idx + 1],
                    obj_data.vertices[pos_idx + 2],
                },
                .uv = .{
                    obj_data.tex_coords[uv_idx],
                    obj_data.tex_coords[uv_idx + 1],
                },
                .norm = .{
                    obj_data.normals[norm_idx],
                    obj_data.normals[norm_idx + 1],
                    obj_data.normals[norm_idx + 2],
                },
            });
        }
    }

    const remap = try allocator.alloc(c_uint, vertex_list.items.len);
    defer allocator.free(remap);
    const new_vertex_count = meshopt.generateVertexRemap(remap, null, Vertex, vertex_list.items);

    const indices = try allocator.alloc(c_uint, vertex_list.items.len);
    errdefer allocator.free(indices);
    meshopt.remapIndexBuffer(indices, null, remap);
    meshopt.optimizeVertexCache(indices, indices, new_vertex_count);

    const vertices = try allocator.alloc(Vertex, new_vertex_count);
    errdefer allocator.free(vertices);
    meshopt.remapVertexBuffer(Vertex, vertices, vertex_list.items, remap);

    meshopt.optimizeOverdraw(indices, indices, Vertex, vertices, "pos", 1.05);
    _ = meshopt.optimizeVertexFetch(Vertex, vertices, indices, vertices);

    const shadow_indices = try allocator.alloc(c_uint, vertex_list.items.len);
    meshopt.generateShadowIndexBuffer(shadow_indices, indices, Vertex, vertices, @sizeOf([3]f32));
    meshopt.optimizeVertexCache(shadow_indices, shadow_indices, vertices.len);

    const tuple = computeBoundingSphereAndAABB(vertices);

    return .{
        .bounding_sphere = tuple[0],
        .aabb = tuple[1],

        .vertices = vertices,
        .indices = indices,
        .shadow_indices = shadow_indices,
    };
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.vertices);
    allocator.free(self.indices);
    allocator.free(self.shadow_indices);
}

fn computeBoundingSphereAndAABB(vertices: []const Vertex) struct { lg.Sphere, lg.AABB } {
    var min = lg.Vec3.fromArr(vertices[0].pos);
    var max = lg.Vec3.fromArr(vertices[0].pos);

    var center = lg.Vec3.zero;
    for (vertices) |vertex| {
        const pos = lg.Vec3.fromArr(vertex.pos);

        center = center.add(pos);

        if (min.x > pos.x) min.x = pos.x;
        if (min.y > pos.y) min.y = pos.y;
        if (min.z > pos.z) min.z = pos.z;

        if (max.x < pos.x) max.x = pos.x;
        if (max.y < pos.y) max.y = pos.y;
        if (max.z < pos.z) max.z = pos.z;
    }

    center = center.scale(1.0 / @as(f32, @floatFromInt(vertices.len)));

    var radius: f32 = 0;
    for (vertices) |vertex| {
        radius = @max(radius, center.sub(lg.Vec3.fromArr(vertex.pos)).len());
    }

    return .{
        lg.Sphere{
            .center = center,
            .radius = radius,
        },
        lg.AABB{
            .min = min,
            .max = max,
        },
    };
}
