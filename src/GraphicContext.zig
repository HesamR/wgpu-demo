const std = @import("std");
const log = std.log.scoped(.graphic_context);

const sdl = @import("sdl");
const wgpu = @import("wgpu");

const Self = @This();

instance: *wgpu.Instance,
surface: *wgpu.Surface,
adapter: *wgpu.Adapter,
device: *wgpu.Device,
queue: *wgpu.Queue,

depth_buffer: *wgpu.Texture,
depth_buffer_view: *wgpu.TextureView,
depth_buffer_format: wgpu.TextureFormat,

surface_config: SurfaceConfig,

window: *sdl.Window,

const SurfaceConfig = struct {
    present_mode: wgpu.PresentMode,
    alpha_mode: wgpu.CompositeAlphaMode,
    format: wgpu.TextureFormat,
    usage: wgpu.TextureUsageFlags,
};

extern fn GetModuleHandleW(module_name: ?[*:0]const u16) ?std.os.windows.HINSTANCE;

fn handleLog(
    level: wgpu.LogLevel,
    message: [*:0]const u8,
    userdata: ?*anyopaque,
) callconv(.C) void {
    _ = userdata;
    switch (level) {
        .info => log.info("{s}", .{message}),
        .warn => log.warn("{s}", .{message}),
        .err => log.err("{s}", .{message}),
        .debug => log.debug("{s}", .{message}),
        .trace => log.debug("[trace] {s}", .{message}),
        else => {},
    }
}

pub fn init(width: u32, height: u32) !Self {
    try sdl.init(.{
        .events = true,
        .video = true,
    });

    const window = try sdl.Window.create(
        "Grafik App",
        @intCast(width),
        @intCast(height),
        .{},
    );

    wgpu.setLogCallback(handleLog, null);
    wgpu.setLogLevel(.info);

    const instance = wgpu.Instance.create(.{
        .next_in_chain = @ptrCast(&wgpu.InstanceExtras{
            .backends = wgpu.InstanceBackendFlags.primary,
            .flags = .{
                .validation = true,
                .debug = true,
            },
        }),
    });
    errdefer instance.release();

    const win_props = try window.getProperties();

    const surface_desc = wgpu.SurfaceDescriptorFromWindowsHWND{
        .h_instance = win_props.get("SDL.window.win32.instance", null).?,
        .hwnd = win_props.get("SDL.window.win32.hwnd", null).?,
    };

    const surface = instance.createSurface(
        .{ .next_in_chain = @ptrCast(&surface_desc) },
    );
    errdefer surface.release();

    const adapter = try instance.requestAdapter(.{
        .compatible_surface = surface,
        .power_preference = .high_performance,
    });
    errdefer adapter.release();

    const device = try adapter.requestDevice(.{
        .required_features_count = 1,
        .required_features = &[_]wgpu.FeatureName{
            .multi_draw_indirect_count,
            .indirect_first_instance,
        },
    });
    errdefer device.release();

    const queue = device.getQueue();

    const surface_caps = surface.getCapabilities(adapter);
    defer surface_caps.freeMembers();

    const surface_usage = wgpu.TextureUsageFlags{
        .render_attachment = true,
    };
    const surface_format = surface_caps.formats[0];
    const alpha_mode = surface_caps.alpha_modes[0];
    const present_mode = surface_caps.present_modes[0];

    surface.configure(.{
        .device = device,
        .usage = surface_usage,
        .format = surface_format,
        .alpha_mode = alpha_mode,
        .present_mode = present_mode,
        .width = width,
        .height = height,
    });

    const depth_buffer = device.createTexture(.{
        .usage = .{ .render_attachment = true },
        .format = .depth32_float,
        .size = .{ .width = 960, .height = 540 },
    });

    const depth_buffer_view = depth_buffer.createView(.{});

    return .{
        .instance = instance,
        .surface = surface,
        .adapter = adapter,
        .device = device,
        .queue = queue,

        .depth_buffer = depth_buffer,
        .depth_buffer_view = depth_buffer_view,
        .depth_buffer_format = .depth32_float,

        .surface_config = .{
            .present_mode = present_mode,
            .alpha_mode = alpha_mode,
            .format = surface_format,
            .usage = surface_usage,
        },

        .window = window,
    };
}

pub fn configureSurface(self: *Self) !void {
    var width: i32 = 0;
    var height: i32 = 0;
    try self.window.getSize(&width, &height);

    if (width == 0 or height == 0) return;

    self.surface.configure(.{
        .device = self.device,
        .format = self.surface_config.format,
        .usage = self.surface_config.usage,
        .alpha_mode = self.surface_config.alpha_mode,
        .present_mode = self.surface_config.present_mode,
        .width = @intCast(width),
        .height = @intCast(height),
    });

    self.depth_buffer_view.release();
    self.depth_buffer.destroy();

    const depth_buffer = self.device.createTexture(.{
        .usage = .{ .render_attachment = true },
        .format = .depth32_float,
        .size = .{
            .width = @intCast(width),
            .height = @intCast(height),
        },
    });

    const depth_buffer_view = depth_buffer.createView(.{});

    self.depth_buffer = depth_buffer;
    self.depth_buffer_view = depth_buffer_view;
}

pub fn deinit(self: Self) void {
    self.depth_buffer_view.release();
    self.depth_buffer.release();
    self.queue.release();
    self.device.release();
    self.adapter.release();
    self.surface.unconfigure();
    self.surface.release();
    self.instance.release();

    self.window.destroy();
    sdl.quit();
}
