const std = @import("std");
const lz4 = @import("lz4.zig");

var output: std.ArrayList(u8) = undefined;

fn readFn(userdata: *anyopaque, buffer: []u8) anyerror!void {
    const r: *std.io.Reader = @ptrCast(@alignCast(userdata));
    return r.readSliceAll(buffer);
}

fn copyFn(userdata: *anyopaque, length: u32) anyerror!void {
    const r: *std.io.Reader = @ptrCast(@alignCast(userdata));
    // std.debug.print("literal {}\n", .{length});
    const buffer = try output.addManyAsSlice(length);
    try r.readSliceAll(buffer);
}

fn skipFn(userdata: *anyopaque, length: u8) anyerror!void {
    const r: *std.io.Reader = @ptrCast(@alignCast(userdata));
    try r.discardAll(length);
}

fn matchFn(userdata: *anyopaque, offset: u16, length: u32) anyerror!void {
    _ = userdata;
    // std.debug.print("match offset {} length {}\n", .{ offset, length });
    try output.ensureUnusedCapacity(length);
    if (offset > output.items.len) return error.LZ4_OffsetTooLarge;
    const match_beg = output.items.ptr + output.items.len - offset;
    const match_dst = output.addManyAsSliceAssumeCapacity(length);
    for (match_dst, 0..) |*dst, i| dst.* = match_beg[i];
}

pub fn main() anyerror!void {
    const file = try std.fs.cwd().openFileZ("test.txt.lz4", .{});
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(&buffer);

    output = .init(std.heap.smp_allocator);
    defer output.deinit();

    try lz4.decompressFrame(.{
        .userdata = &reader.interface,
        .readFn = &readFn,
        .copyFn = &copyFn,
        .skipFn = &skipFn,
        .matchFn = &matchFn,
    });

    std.debug.print("{}\n", .{output.items.len});

    try std.fs.cwd().writeFile(.{ .data = output.items, .sub_path = "test.decompress" });
}
