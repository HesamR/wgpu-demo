const std = @import("std");

parent: std.mem.Allocator,

const Self = @This();

const Metadata = extern struct {
    magic: u32 = magic_number,
    size: usize,
};

const magic_number = 0x07230203;
const default_alignment = 16;
const metadata_size = std.mem.alignForward(
    usize,
    @sizeOf(Metadata),
    default_alignment,
);

pub fn init(parent: std.mem.Allocator) Self {
    return .{ .parent = parent };
}

pub fn alloc(self: Self, size: usize) ![*]align(default_alignment) u8 {
    const len = size + metadata_size;
    const mem = try self.parent.alignedAlloc(u8, default_alignment, len);

    const len_ptr: *Metadata = @ptrCast(mem.ptr);
    len_ptr.* = .{
        .size = size + metadata_size,
    };

    return @ptrFromInt(@intFromPtr(mem.ptr) + metadata_size);
}

pub fn free(self: Self, ptr: *anyopaque) void {
    const start = @intFromPtr(ptr) - metadata_size;
    const metadata = @as(*Metadata, @ptrFromInt(start)).*;

    std.debug.assert(metadata.magic == magic_number);

    const buf = @as([*]align(default_alignment) u8, @ptrFromInt(start))[0..metadata.size];

    self.parent.free(buf);
}
