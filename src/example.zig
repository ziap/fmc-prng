const Fmc256 = @import("Fmc256.zig");

const std = @import("std");

pub fn main() !void {
  var buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
  defer buffer.flush() catch {};
  var writer = buffer.writer();

  const rng = Fmc256.fromBytes(&.{ 42 });
  rng.jump(.default);

  const n = 1_000_000;
  var rng1 = rng;

  for (1..n) |i| {
    var jumped = rng;
    jumped.jump(.steps(i));
    _ = rng1.next();

    const s1: u256 = @bitCast(jumped.state);
    const s2: u256 = @bitCast(rng1.state);

    if (s1 != s2) unreachable;
  }

  var jumped = rng;
  jumped.jump(comptime .steps(n));
  _ = rng1.next();

  writer.writeAll("Jump/next test\n") catch return;
  for (0..50) |_| {
    const x1 = rng1.next();
    const x2 = jumped.next();
    if (x1 != x2) unreachable;
    writer.print("{x:0>16} - {x:0>16}\n", .{ x1, x2 }) catch return;
  }
}
