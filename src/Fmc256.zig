const Fmc256 = @This();

const MUL = 0xfd47b3f4e954a25e;

state: [3]u64,
carry: u64,

pub fn fromSeed(seed: *const [4]u64) Fmc256 {
  return .{
    .state = seed[0..3].*,
    .carry = seed[3] % (MUL - 2) + 1,
  };
}

pub fn next(self: *Fmc256) u64 {
  const result = self.state[2] ^ self.carry;
  const m = @as(u128, self.state[0]) * MUL + self.carry;
  self.state[0] = self.state[1];
  self.state[1] = self.state[2];
  self.state[2] = @truncate(m);
  self.carry = @intCast(m >> 64);
  return result;
}
