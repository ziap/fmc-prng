const Fmc256 = @import("Fmc256.zig");

const std = @import("std");

pub fn main() !void {
  var buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
  defer buffer.flush() catch {};
  var writer = buffer.writer();

  var rng = Fmc256.fromSeed(&.{
    0x243f6a8885a308d3,
    0x13198a2e03707344,
    0xa4093822299f31d0,
    0x082efa98ec4e6c89,
  });

  const n = 50_000_000;

  var jumped = rng;
  for (0..n) |_| _ = rng.next();

  jumped.jump(n);

  for (0..20) |_| {
    const x1 = rng.next();
    const x2 = jumped.next();
    if (x1 != x2) unreachable;
    writer.print("{x} - {x}\n", .{ x1, x2 }) catch return;
  }

  buffer.flush() catch return;

  writer.writeAll("Hashing test\n") catch return;
  inline for (0..20) |byte| {
    writer.print("{x}\n", .{ Fmc256.hash(&(.{0} ** 23 ++ .{ byte })) }) catch return;
  }

  const input = "the quick brown fox jumps over the lazy dog";
  writer.print("{x}\n", .{ Fmc256.hash(input) }) catch return;
}
