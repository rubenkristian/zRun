//! Microcore entry point for executing one zRun bytecode data block.

const std = @import("std");
const artifact = @import("artifact.zig");
const execution = @import("execution.zig");
const vm = @import("vm.zig");

// Keep the initial runtime heap bounded. This lives in the MCB's zeroed image
// memory and is separate from the bytecode data block supplied by the caller.
var runtime_memory: [8 * 1024 * 1024]u8 align(16) = undefined;
// Decoded bytecode outlives each request. Keep its allocations separate from
// the request arena, which is reset after execution.
var artifact_memory: [256 * 1024]u8 align(16) = undefined;
var cached_function: ?vm.FunctionBytecode = null;

// The MCB image is linked as ET_DYN to retain relocation records. This stub
// satisfies Zig's Linux stdlib fallback; the freestanding VM does not call it.
export fn getauxval(_: usize) callconv(.c) usize {
    return 0;
}

const BytecodeBlockHeader = extern struct {
    magic: [4]u8,
    artifact_length: u32,
    output_capacity: u32,
    output_length: u32,
};

/// Execute a ZBD1 bytecode block. The block contains a 16-byte header, a
/// zRun artifact, and a writable output area. Return 0 on success, 1 for an
/// invalid block/artifact, 2 for a runtime failure, or 3 for a JS exception.
export fn microcore_entry(block_address: [*]u8, block_capacity: usize) callconv(.c) usize {
    if (block_capacity < @sizeOf(BytecodeBlockHeader)) return 1;
    const header: *BytecodeBlockHeader = @ptrCast(@alignCast(block_address));
    if (!std.mem.eql(u8, &header.magic, "ZBD1")) return 1;

    const artifact_start = @sizeOf(BytecodeBlockHeader);
    const artifact_length: usize = header.artifact_length;
    const output_capacity: usize = header.output_capacity;
    if (artifact_length == 0 or artifact_length > block_capacity - artifact_start) return 1;
    const output_start = artifact_start + artifact_length;
    if (output_capacity > block_capacity - output_start) return 1;
    const artifact_bytes = block_address[artifact_start..output_start];
    const output_bytes = block_address[output_start .. output_start + output_capacity];

    if (cached_function == null) {
        var artifact_allocator = std.heap.FixedBufferAllocator.init(&artifact_memory);
        cached_function = artifact.load(artifact_allocator.allocator(), artifact_bytes) catch return 1;
    }

    var fixed = std.heap.FixedBufferAllocator.init(&runtime_memory);
    var arena = std.heap.ArenaAllocator.init(fixed.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // The host program can forward this output through a device or bus.
    var output = std.Io.Writer.fixed(output_bytes);
    var error_buffer: [128]u8 = undefined;
    var errors = std.Io.Writer.Discarding.init(&error_buffer);
    const uncaught = execution.execute(allocator, cached_function.?, &output, &errors.writer, "") catch return 2;
    header.output_length = @intCast(output.end);
    return if (uncaught) 3 else 0;
}
