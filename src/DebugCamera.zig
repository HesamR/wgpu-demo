const std = @import("std");
const log = std.log.scoped(.debug_camera);

const sdl = @import("sdl");
const lg = @import("linalg.zig");

const Self = @This();

speed: f32,
sens: f32,

transform: lg.Transform = lg.Transform.identity,
rot: lg.Vec3 = lg.Vec3.zero,

state: struct {
    w: bool = false,
    s: bool = false,
    a: bool = false,
    d: bool = false,

    right: bool = false,

    dx: f32 = 0,
    dy: f32 = 0,
} = .{},

pub fn init(speed: f32, sens: f32) Self {
    return .{
        .speed = speed,
        .sens = sens,
    };
}

pub fn processInput(self: *Self, event: sdl.Event) void {
    switch (event.type) {
        .key_up, .key_down => {
            const down = event.key.state == .pressed;

            switch (event.key.keysym.keycode) {
                .w => self.state.w = down,
                .s => self.state.s = down,
                .a => self.state.a = down,
                .d => self.state.d = down,

                else => {},
            }
        },

        .mouse_button_up, .mouse_button_down => {
            const down = event.button.state == .pressed;
            switch (event.button.button) {
                .right => self.state.right = down,
                else => {},
            }
        },

        .mouse_motion => {
            self.state.dx = event.motion.xrel;
            self.state.dy = event.motion.yrel;
        },

        else => {},
    }
}

pub fn update(self: *Self, delta_time: f32) !void {
    var dir = lg.Vec3.zero;

    if (self.state.w)
        dir = dir.add(lg.Vec3.forward);
    if (self.state.s)
        dir = dir.sub(lg.Vec3.forward);

    if (self.state.d)
        dir = dir.add(lg.Vec3.right);
    if (self.state.a)
        dir = dir.sub(lg.Vec3.right);

    self.transform.translateLocal(dir.scale(delta_time * self.speed));

    if (self.state.right) {
        try sdl.setRelativeMouseMode(true);

        self.rot = self.rot.add(lg.vec3(self.state.dy, self.state.dx, 0).scale(self.sens));
        self.rot.x = std.math.clamp(self.rot.x, -0.5 * std.math.pi, 0.5 * std.math.pi);

        self.transform.rotation = lg.Quat.fromEulerAngles(self.rot);
    }

    try sdl.setRelativeMouseMode(false);
}

pub fn getMat(self: Self, width: f32, height: f32) lg.Mat4 {
    const forward = self.transform.forward();
    const up = self.transform.up();

    const view = lg.Mat4.fromLookTo(self.transform.position, forward, up);
    const proj = lg.Mat4.fromPerspective(0.33 * std.math.pi, width / height, 0.1, 100);

    return view.mul(proj);
}
