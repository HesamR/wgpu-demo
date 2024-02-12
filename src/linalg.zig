const std = @import("std");
const tracy = @import("tracy");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = new(0, 0, 0);
    pub const one = new(1, 1, 1);
    pub const up = new(0, 1, 0);
    pub const right = new(1, 0, 0);
    pub const forward = new(0, 0, 1);

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn fromArr(arr: [3]f32) Vec3 {
        return new(arr[0], arr[1], arr[2]);
    }

    pub fn toArr(self: Vec3) [3]f32 {
        return .{ self.x, self.y, self.z };
    }

    pub fn add(lhs: Vec3, rhs: Vec3) Vec3 {
        return new(
            lhs.x + rhs.x,
            lhs.y + rhs.y,
            lhs.z + rhs.z,
        );
    }

    pub fn neg(self: Vec3) Vec3 {
        return new(-self.x, -self.y, -self.z);
    }

    pub fn sub(lhs: Vec3, rhs: Vec3) Vec3 {
        return lhs.add(rhs.neg());
    }

    pub fn scale(self: Vec3, scaler: f32) Vec3 {
        return new(
            self.x * scaler,
            self.y * scaler,
            self.z * scaler,
        );
    }

    pub fn mul(lhs: Vec3, rhs: Vec3) Vec3 {
        return new(
            lhs.x * rhs.x,
            lhs.y * rhs.y,
            lhs.z * rhs.z,
        );
    }

    pub fn rotate(self: Vec3, rotation: Quat) Vec3 {
        return rotation.rotatePoint(self);
    }

    pub fn dot(lhs: Vec3, rhs: Vec3) f32 {
        return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
    }

    pub fn len2(self: Vec3) f32 {
        return self.dot(self);
    }

    pub fn len(self: Vec3) f32 {
        return @sqrt(self.len2());
    }

    pub fn norm(self: Vec3) Vec3 {
        return self.scale(1 / self.len());
    }

    pub fn tryNorm(self: Vec3) ?Vec3 {
        const l = self.len();

        if (l > 0)
            return self.scale(1 / l)
        else
            return null;
    }

    pub fn anyOrthonormal(self: Vec3) Vec3 {
        const sign = std.math.sign(self.z);
        const a = -1.0 / (sign + self.z);
        const b = self.x * self.y * a;

        return new(b, sign + self.y * self.y * a, -self.y);
    }

    pub fn cross(lhs: Vec3, rhs: Vec3) Vec3 {
        return new(
            (lhs.y * rhs.z) - (lhs.z * rhs.y),
            (lhs.z * rhs.x) - (lhs.x * rhs.z),
            (lhs.x * rhs.y) - (lhs.y * rhs.x),
        );
    }

    pub fn eq(lhs: Vec3, rhs: Vec3) bool {
        return std.meta.eql(lhs, rhs);
    }
};

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub const zero = new(0, 0);
    pub const one = new(0, 0);
    pub const right = new(1, 0);
    pub const up = new(0, 1);

    pub fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn toArr(self: Vec2) [2]f32 {
        return new(self.x, self.y);
    }

    pub fn add(lhs: Vec2, rhs: Vec2) Vec2 {
        return new(
            lhs.x + rhs.x,
            lhs.y + rhs.y,
        );
    }

    pub fn neg(self: Vec2) Vec2 {
        return new(-self.x, self.y);
    }

    pub fn sub(lhs: Vec2, rhs: Vec2) Vec2 {
        return lhs.add(rhs.neg());
    }

    pub fn scale(self: Vec2, scaler: f32) Vec2 {
        return new(
            self.x * scaler,
            self.y * scaler,
        );
    }

    pub fn mul(lhs: Vec2, rhs: Vec2) Vec2 {
        return new(
            lhs.x * rhs.x,
            lhs.y * rhs.y,
        );
    }

    pub fn dot(lhs: Vec2, rhs: Vec2) f32 {
        return lhs.x * rhs.x + lhs.y * rhs.y;
    }

    pub fn len2(self: Vec2) f32 {
        return self.dot(self);
    }

    pub fn len(self: Vec2) f32 {
        return @sqrt(self.len2());
    }

    pub fn norm(self: Vec2) Vec2 {
        return self.scale(1 / self.len());
    }

    pub fn tryNorm(self: Vec2) ?Vec2 {
        const l = self.len();

        return if (l > 0)
            self.scale(1 / l)
        else
            null;
    }

    pub fn perpenCw(self: Vec2) Vec2 {
        return new(self.y, -self.x);
    }

    pub fn perpenCcw(self: Vec2) Vec2 {
        return new(-self.y, self.x);
    }

    pub fn cross(lhs: Vec2, rhs: Vec2) f32 {
        return lhs.x * rhs.y - lhs.y * rhs.x;
    }

    pub fn angle(lhs: Vec2, rhs: Vec2) f32 {
        return std.math.acos(
            lhs.dot(rhs) / (lhs.len() * rhs.len()),
        );
    }

    pub fn eq(lhs: Vec2, rhs: Vec2) bool {
        return std.meta.eql(lhs, rhs);
    }
};

pub fn vec3(x: f32, y: f32, z: f32) Vec3 {
    return Vec3.new(x, y, z);
}

pub fn vec2(x: f32, y: f32) Vec2 {
    return Vec3.new(x, y);
}

pub const Mat4 = struct {
    data: [4][4]f32,

    pub const zero = new(.{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    });

    pub const identity = new(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    });

    pub fn new(data: [4][4]f32) Mat4 {
        return .{ .data = data };
    }

    pub fn tranpose(self: Mat4) Mat4 {
        var res = self;

        inline for (0..4) |i| {
            inline for (i..4) |j| {
                std.mem.swap(f32, &res.data[i][j], &res.data[j][i]);
            }
        }

        return res;
    }

    pub fn mul(lhs: Mat4, rhs: Mat4) Mat4 {
        var res = zero;

        inline for (0..4) |row| {
            inline for (0..4) |col| {
                inline for (0..4) |k| {
                    res.data[col][row] += lhs.data[col][k] * rhs.data[k][row];
                }
            }
        }

        return res;
    }

    pub fn fromLookTo(eye: Vec3, dir: Vec3, up: Vec3) Mat4 {
        const f = dir.norm();
        const s = up.cross(f).norm();
        const u = f.cross(s);

        return new(.{
            .{ s.x, u.x, f.x, 0 },
            .{ s.y, u.y, f.y, 0 },
            .{ s.z, u.z, f.z, 0 },
            .{ -s.dot(eye), -u.dot(eye), -f.dot(eye), 1 },
        });
    }

    pub fn fromLookAt(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
        const dir = target.sub(eye);
        return fromLookTo(eye, dir, up);
    }

    pub fn fromPerspective(fov: f32, aspect_ratio: f32, z_near: f32, z_far: f32) Mat4 {
        var result = zero;

        const h = @cos(fov * 0.5) / @sin(fov * 0.5);
        const w = h / aspect_ratio;
        const r = z_far / (z_far - z_near);

        result.data[0][0] = w;
        result.data[1][1] = h;
        result.data[2][2] = r;
        result.data[2][3] = 1;
        result.data[3][2] = -r * z_near;

        return result;
    }

    pub fn fromPosRotScale(pos: Vec3, rot: Quat, scale: Vec3) Mat4 {
        const axes = rot.rotationAxes();

        const right = axes[0].scale(scale.x);
        const up = axes[1].scale(scale.x);
        const forward = axes[2].scale(scale.x);

        return Mat4.new(.{
            right.toArr() ++ .{0},
            up.toArr() ++ .{0},
            forward.toArr() ++ .{0},
            pos.toArr() ++ .{1},
        });
    }
};

pub const Quat = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub const identity = new(0, 0, 0, 1);

    pub fn new(x: f32, y: f32, z: f32, w: f32) Quat {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn fromVec3(vec: Vec3, w: f32) Quat {
        return .{ .x = vec.x, .y = vec.y, .z = vec.z, .w = w };
    }

    pub fn fromAxis(axis: Vec3, angle: f32) Quat {
        const w = @cos(angle / 2);
        const n = @sin(angle / 2);

        const ax = axis.scale(n);

        return fromVec3(ax, w);
    }

    pub fn fromAxisX(angle: f32) Quat {
        return fromAxis(Vec3.right, angle);
    }

    pub fn fromAxisY(angle: f32) Quat {
        return fromAxis(Vec3.up, angle);
    }

    pub fn fromAxisZ(angle: f32) Quat {
        return fromAxis(Vec3.forward, angle);
    }

    pub fn fromEulerAngles(v: Vec3) Quat {
        const x = fromAxisX(v.x);
        const y = fromAxisY(v.y);
        const z = fromAxisZ(v.z);

        return z.mul(y.mul(x));
    }

    pub fn fromRotationAxes(right: Vec3, up: Vec3, forward: Vec3) Quat {
        if (forward.z <= 0.0) {
            const dif10 = up.y - right.x;
            const omm22 = 1.0 - forward.z;

            if (dif10 <= 0.0) {
                const four_xsq = omm22 - dif10;
                const inv4x = 0.5 / @sqrt(four_xsq);
                return new(
                    four_xsq * inv4x,
                    (right.y + up.x) * inv4x,
                    (right.z + forward.x) * inv4x,
                    (up.z - forward.y) * inv4x,
                );
            } else {
                const four_ysq = omm22 + dif10;
                const inv4y = 0.5 / @sqrt(four_ysq);
                return new(
                    (right.y + up.x) * inv4y,
                    four_ysq * inv4y,
                    (up.z + forward.y) * inv4y,
                    (forward.x - right.z) * inv4y,
                );
            }
        } else {
            const sum10 = up.y + right.x;
            const opm22 = 1.0 + forward.z;

            if (sum10 <= 0.0) {
                const four_zsq = opm22 - sum10;
                const inv4z = 0.5 / @sqrt(four_zsq);

                return new(
                    (right.z + forward.x) * inv4z,
                    (up.z + forward.y) * inv4z,
                    four_zsq * inv4z,
                    (right.y - up.x) * inv4z,
                );
            } else {
                const four_wsq = opm22 + sum10;
                const inv4w = 0.5 / @sqrt(four_wsq);

                return new(
                    (up.z - forward.y) * inv4w,
                    (forward.x - right.z) * inv4w,
                    (right.y - up.x) * inv4w,
                    four_wsq * inv4w,
                );
            }
        }
    }

    pub fn fromLookTo(look_dir: Vec3, up_dir: Vec3) Quat {
        const forward_axis = look_dir.tryNorm() orelse Vec3.forward;
        const nz_up_dir = up_dir.tryNorm() orelse Vec3.up;

        const right_axis = nz_up_dir.cross(forward_axis).tryNorm() orelse nz_up_dir.anyOrthonormal();
        const up_axis = forward_axis.cross(right_axis);

        return Quat.fromRotationAxes(right_axis, up_axis, forward_axis);
    }

    pub fn add(lhs: Quat, rhs: Quat) Quat {
        return new(
            lhs.x + rhs.x,
            lhs.y + rhs.y,
            lhs.z + rhs.z,
            lhs.w + rhs.w,
        );
    }

    pub fn neg(self: Quat) Quat {
        return new(
            -self.x,
            -self.y,
            -self.z,
            -self.w,
        );
    }

    pub fn sub(lhs: Quat, rhs: Quat) Quat {
        return add(lhs, neg(rhs));
    }

    pub fn scale(self: Quat, scaler: f32) Quat {
        return new(
            self.x * scaler,
            self.y * scaler,
            self.z * scaler,
            self.w * scaler,
        );
    }

    pub fn mul(lhs: Quat, rhs: Quat) Quat {
        const x = (lhs.x * rhs.w) + (lhs.y * rhs.z) -
            (lhs.z * rhs.y) + (lhs.w * rhs.x);

        const y = (-lhs.x * rhs.z) + (lhs.y * rhs.w) +
            (lhs.z * rhs.x) + (lhs.w * rhs.y);

        const z = (lhs.x * rhs.y) - (lhs.y * rhs.x) +
            (lhs.z * rhs.w) + (lhs.w * rhs.z);

        const w = (-lhs.x * rhs.x) - (lhs.y * rhs.y) -
            (lhs.z * rhs.z) + (lhs.w * rhs.w);

        return new(x, y, z, w);
    }

    pub fn dot(lhs: Quat, rhs: Quat) f32 {
        return lhs.x * rhs.x +
            lhs.y * rhs.y +
            lhs.z * rhs.z +
            lhs.w * rhs.w;
    }

    pub fn len2(self: Quat) f32 {
        return self.dot(self);
    }

    pub fn len(self: Quat) f32 {
        return @sqrt(self.len2());
    }

    pub fn norm(self: Quat) Quat {
        return self.scale(1 / self.len());
    }

    pub fn rotatePoint(self: Quat, point: Vec3) Vec3 {
        const axis = vec3(self.x, self.y, self.z);
        const axis_len2 = axis.len2();

        return point
            .scale(self.w * self.w - axis_len2)
            .add(axis.scale(point.dot(axis) * 2))
            .add(axis.cross(point).scale(self.w * 2));
    }

    pub fn rotationAxes(self: Quat) [3]Vec3 {
        const xx = self.x * self.x;
        const yy = self.y * self.y;
        const zz = self.z * self.z;
        const xy = self.x * self.y;
        const xz = self.x * self.z;
        const yz = self.y * self.z;
        const wx = self.w * self.x;
        const wy = self.w * self.y;
        const wz = self.w * self.z;

        const right = vec3(
            1 - 2 * (yy + zz),
            2 * (xy + wz),
            2 * (xz - wy),
        );

        const up = vec3(
            2 * (xy - wz),
            1 - 2 * (xx + zz),
            2 * (yz + wx),
        );

        const forward = vec3(
            2 * (xz + wy),
            2 * (yz - wx),
            1 - 2 * (xx + yy),
        );

        return .{ right, up, forward };
    }
};

pub const Sphere = struct {
    center: Vec3,
    radius: f32,
};

pub const AABB = struct {
    min: Vec3,
    max: Vec3,

    pub fn center(self: AABB) Vec3 {
        return self.max.add(self.min).scale(0.5);
    }
};

pub const Transform = struct {
    position: Vec3,
    rotation: Quat,
    scale: Vec3,

    pub const identity = new(
        Vec3.zero,
        Quat.identity,
        Vec3.one,
    );

    pub fn new(pos: Vec3, rot: Quat, scale: Vec3) Transform {
        return .{ .position = pos, .rotation = rot, .scale = scale };
    }

    pub fn fromPosition(pos: Vec3) Transform {
        return new(pos, Quat.identity, Vec3.one);
    }

    pub fn fromRotation(rot: Quat) Transform {
        return new(Vec3.zero, rot, Vec3.one);
    }

    pub fn fromScale(scale: Vec3) Transform {
        return new(Vec3.zero, Quat.identity, scale);
    }

    pub fn up(self: Transform) Vec3 {
        return self.rotation.rotatePoint(Vec3.up);
    }

    pub fn right(self: Transform) Vec3 {
        return self.rotation.rotatePoint(Vec3.right);
    }

    pub fn forward(self: Transform) Vec3 {
        return self.rotation.rotatePoint(Vec3.forward);
    }

    pub fn translate(self: *Transform, v: Vec3) void {
        self.position = self.position.add(v);
    }

    pub fn translateLocal(self: *Transform, v: Vec3) void {
        const sum = self.right().scale(v.x)
            .add(self.up().scale(v.y))
            .add(self.forward().scale(v.z));

        self.position = self.position.add(sum);
    }

    pub fn translateAround(self: *Transform, point: Vec3, rotation: Quat) void {
        self.position = point.add(self.position.sub(point).rotate(rotation));
    }

    pub fn rotate(self: *Transform, rotation: Quat) void {
        self.rotation = rotation.mul(self.rotation);
    }

    pub fn rotateLocal(self: *Transform, rotation: Quat) void {
        self.rotation = self.rotation.mul(rotation);
    }

    pub fn rotateAround(self: *Transform, point: Vec3, rotation: Quat) void {
        self.translateAround(point, rotation);
        self.rotate(rotation);
    }

    pub fn lookTo(self: *Transform, look_dir: Vec3) void {
        self.rotation = Quat.fromLookTo(look_dir, self.up());
    }

    pub fn lookAt(self: *Transform, target: Vec3) void {
        self.lookTo(target.sub(self.position));
    }

    pub fn transformPoint(self: Transform, point: Vec3) Vec3 {
        return point
            .mul(self.scale)
            .rotate(self.rotation)
            .add(self.position);
    }

    pub fn transformSphere(self: Transform, sphere: Sphere) Sphere {
        const new_center = self.transformPoint(sphere.center);
        const new_radius = @max(self.scale.x, @max(self.scale.y, self.scale.z)) * sphere.radius;

        return .{ .center = new_center, .radius = new_radius };
    }

    pub fn mul(lhs: Transform, rhs: Transform) Transform {
        return new(
            lhs.transformPoint(rhs.position),
            lhs.rotation.mul(rhs.rotation),
            lhs.scale.mul(rhs.scale),
        );
    }

    pub fn computeMat(self: Transform) Mat4 {
        return Mat4.fromPosRotScale(
            self.position,
            self.rotation,
            self.scale,
        );
    }
};
