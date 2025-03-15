const Fmc256 = struct {
  const MUL = 0xffbef2eace277705;

  state: [3]u64,
  carry: u64,

  fn fromSeed(seed: *const [4]u64) Fmc256 {
    return .{
      .state = seed[0..3].*,
      .carry = seed[3] % (MUL - 2) + 1,
    };
  }

  fn next(self: *Fmc256) u64 {
    const result = self.state[2] ^ self.carry;
    const m = @as(u128, self.state[0]) * MUL + self.carry;
    self.state[0] = self.state[1];
    self.state[1] = self.state[2];
    self.state[2] = @truncate(m);
    self.carry = @intCast(m >> 64);
    return result;
  }
};

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

  for (0..20) |_| {
    writer.print("{x}\n", .{ rng.next() }) catch return;
  }
}
