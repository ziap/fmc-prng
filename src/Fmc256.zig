const Fmc256 = @This();

const MUL = 0xfd47b3f4e954a25e;
const MOD = (MUL << 192) - 1;

pub const JUMP_SMALL = (MOD >> 128) / 3 * 3;
pub const JUMP_BIG = (MOD >> 64) / 3 * 3;

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

fn jumpMultiplier(N: comptime_int) u256 {
  var a: comptime_int = 1;
  var b: comptime_int = MUL;

  var x = N;
  while (x > 0) : (x >>= 1) {
    if (x & 1 != 0) {
      a = (a * b) % MOD;
    }

    b = (b * b) % MOD;
  }

  return a;
}

pub fn jump(self: *Fmc256, N: comptime_int) void {
  const a = ((
    (@as(u512, self.state[0]) << 0) |
    (@as(u512, self.state[1]) << 64) |
    (@as(u512, self.state[2]) << 128) |
    (@as(u512, self.carry) << 192)
  ) * comptime jumpMultiplier(N / 3)) % MOD;

  self.state[0] = @truncate(a >> 0);
  self.state[1] = @truncate(a >> 64);
  self.state[2] = @truncate(a >> 128);
  self.carry = @intCast(a >> 192);

  inline for (0..N % 3) |_| {
    _ = self.next();
  }
}
