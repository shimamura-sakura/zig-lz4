# zig-lz4
LZ4 decompressor in zig

Input/output is left to the user, see `main.zig` for an example using `std.io.Reader` and `std.ArrayList(u8)`.

The library doesn't allocate memory by itself.