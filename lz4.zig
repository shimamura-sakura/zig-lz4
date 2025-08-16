const std = @import("std");

pub const Err = error{
    EndOfStream,
    LZ4_WrongMagic,
    LZ4_WrongFlagVersion,
};

pub const FLG = packed struct(u8) {
    dict_id: bool,
    _: u1,
    c_checksum: bool,
    c_size: bool,
    b_checksum: bool,
    b_indep: bool,
    version: u2,
};

pub const BD = packed struct(u8) {
    _0: u4,
    block_maxsize: u3,
    _1: u1,
};

pub const Token = packed struct(u8) {
    len_match: u4,
    len_literal: u4,
};

pub const Ctx = struct {
    userdata: *anyopaque,
    skipFn: *const fn (userdata: *anyopaque, length: u8) anyerror!void,
    readFn: *const fn (userdata: *anyopaque, buffer: []u8) anyerror!void,
    copyFn: *const fn (userdata: *anyopaque, length: u32) anyerror!void,
    matchFn: *const fn (userdata: *anyopaque, offset: u16, length: u32) anyerror!void,
};

pub const Frame = struct {
    bd: BD,
    flg: FLG,
    content_size: u64 = 0,
    dictionary_id: u32 = 0,
    fn read(ctx: Ctx) anyerror!Frame {
        var a6: extern struct { magic: [4]u8, flg: FLG, bd: BD } = undefined;
        try ctx.readFn(ctx.userdata, std.mem.asBytes(&a6));
        if (std.mem.readInt(u32, &a6.magic, .little) != 0x184D2204) return Err.LZ4_WrongMagic;
        if (a6.flg.version != 1) return Err.LZ4_WrongFlagVersion;
        var a12 = std.mem.zeroes([12]u8);
        if (a6.flg.c_size) try ctx.readFn(ctx.userdata, a12[0..8]);
        if (a6.flg.dict_id) try ctx.readFn(ctx.userdata, a12[8..12]);
        try ctx.skipFn(ctx.userdata, 1);
        return .{
            .bd = a6.bd,
            .flg = a6.flg,
            .content_size = std.mem.readInt(u64, a12[0..8], .little),
            .dictionary_id = std.mem.readInt(u32, a12[8..12], .little),
        };
    }
};

pub fn decompressFrame(ctx: Ctx) anyerror!void {
    const frame = try Frame.read(ctx);
    while (true) {
        var blocksize: u32 = undefined;
        try ctx.readFn(ctx.userdata, @ptrCast(&blocksize));
        blocksize = std.mem.littleToNative(u32, blocksize);
        if (blocksize == 0) break;
        if (blocksize >> 31 == 1) try ctx.copyFn(ctx.userdata, blocksize << 1 >> 1) //
        else try decompressBlock(ctx, blocksize);
        if (frame.flg.b_checksum) try ctx.skipFn(ctx.userdata, 4);
    }
    if (frame.flg.c_checksum) try ctx.skipFn(ctx.userdata, 4);
}

pub fn decompressBlock(ctx: Ctx, blocksize: u32) anyerror!void {
    var b: [1]u8 = undefined;
    var left = blocksize;
    while (true) {
        try ctx.readFn(ctx.userdata, &b);
        left -= 1;
        const token: Token = @bitCast(b);
        var literal_length: u32 = token.len_literal;
        if (token.len_literal == 15) while (true) {
            try ctx.readFn(ctx.userdata, &b);
            left -= 1;
            literal_length += b[0];
            if (b[0] < 255) break;
        };
        try ctx.copyFn(ctx.userdata, literal_length);
        left -= literal_length;
        if (left == 0) break;
        var match_offset: u16 = undefined;
        try ctx.readFn(ctx.userdata, @ptrCast(&match_offset));
        left -= 2;
        match_offset = std.mem.littleToNative(u16, match_offset);
        var match_length: u32 = token.len_match + @as(u32, 4);
        if (token.len_match == 15) while (true) {
            try ctx.readFn(ctx.userdata, &b);
            left -= 1;
            match_length += b[0];
            if (b[0] < 255) break;
        };
        try ctx.matchFn(ctx.userdata, match_offset, match_length);
    }
}
