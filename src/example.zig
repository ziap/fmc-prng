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

  var jumped = rng;
  jumped.jump(Fmc256.JUMP_SMALL);

  for (0..20) |_| {
    writer.print("{x} - {x}\n", .{ rng.next(), jumped.next() }) catch return;
  }
}
