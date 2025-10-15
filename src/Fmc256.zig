const Fmc256 = @This();

const MUL = 0xffff1aa1c69c8d92;
const MOD = (MUL << 192) - 1;

pub const JUMP_SMALL = 1 << 128;
pub const JUMP_BIG = 1 << 192;

pub const JUMP_PHI = blk: {
  const a = (MOD - 1) / 2;
  const aa = a * a;

  // Initial approximation: 0.625
  var x = a * 5 / 8;
  var dec = false;

  // Newton's method iterations
  while (true) {
    const nx = (aa + x * x) / (a + 2 * x);
    if (x == nx or (dec and nx > x)) break;

    dec = nx < x;
    x = nx;
  }

  break :blk x;
};

state: [3]u64,
carry: u64,

/// Construct an RNG from a 256-bit seed
pub fn fromSeed(seed: *const [4]u64) Fmc256 {
  // Some requirements for seeding:
  // - The carry must be less than MUL - 1
  // - The state and carry cannot be all zero
  // For simplicity, initialize the state with any 192-bit seed and set the
  // carry to a value between 1 and MUL - 1
  return .{
    .state = seed[0..3].*,
    .carry = seed[3] % (MUL - 2) + 1,
  };
}

/// Construct an RNG from an entropy byte sequence
pub fn fromBytes(data: []const u8) Fmc256 {
  const S = struct {
    fn safeGet(x: u64) u64 {
      const native_endian = @import("builtin").target.cpu.arch.endian();
      return if (native_endian == .little) x else @byteSwap(x);
    }
  };

  var chunks: [3]u64 = @splat(0);
  var carry: u64 = 0;

  const step = 3 * @sizeOf(u64);
  var idx: usize = 0;

  while (idx + step < data.len) {
    var chunk: [3]u64 = undefined;
    const chunk_ptr: *[step]u8 = @ptrCast(&chunk);
    @memcpy(chunk_ptr, data[idx..idx + step]);
    idx += step;

    inline for (&chunks, chunk) |*item, limb| {
      const m = @as(u128, item.*) * MUL + carry + S.safeGet(limb);
      item.* = @truncate(m);
      carry = @intCast(m >> 64);
    }
  }

  var last: [3]u64 = @splat(0);
  const last_ptr: *[step]u8 = @ptrCast(&last);
  @memcpy(last_ptr[0..data.len - idx], data[idx..]);

  inline for (&chunks, last) |*item, limb| {
    const m = @as(u128, item.*) * MUL + carry + S.safeGet(limb);
    item.* = @truncate(m);
    carry = @intCast(m >> 64);
  }

  return .{ .state = chunks, .carry = if (carry != 0) carry else 1, };
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

pub fn jump(self: *Fmc256, n: comptime_int) void {
  const S = struct {
    fn power(exp: comptime_int) [4]u64 {
      var a: u256 = 1;
      var b = MUL << 128;

      var t = exp;
      while (t > 0) : (t >>= 1) {
        if (t & 1 != 0) {
          const m = @as(u512, a) * b;
          a = @intCast(m % MOD);
        }

        const m = @as(u512, b) * b;
        b = @intCast(m % MOD);
      }

      return .{
        @truncate(a),
        @truncate(a >> 64),
        @truncate(a >> 128),
        @intCast(a >> 192),
      };
    }

    fn fold(state: *[4]u64, shift: *const [4]u64, limb: u64) void {
      var ls: [4]u64 = undefined;
      var hs: [4]u64 = undefined;

      inline for (&ls, &hs, shift) |*l, *h, s| {
        const m = @as(u128, s) * limb;
        l.* = @truncate(m);
        h.* = @intCast(m >> 64);
      }

      var as: [4]u128 = undefined;
      inline for (&as, &hs, state) |*a, h, s| {
        a.* = @as(u128, s) + h;
      }

      as[0] += ls[1];
      as[1] += ls[2] + (as[0] >> 64);
      as[2] += ls[3] + (as[1] >> 64) + @as(u128, ls[0]) * MUL;
      as[3] += as[2] >> 64;

      const m = @as(u128, MUL) * @as(u64, @truncate(as[0])) + as[3];
      state[0] = @truncate(as[1]);
      state[1] = @truncate(as[2]);
      state[2] = @truncate(m);
      state[3] = @intCast(m >> 64);
    }
  };

  if (n >= 5) {
    const p = comptime S.power(n - 5);
    var state: [4]u64 = @splat(0);
    S.fold(&state, &p, self.state[0]);
    S.fold(&state, &p, self.state[1]);
    S.fold(&state, &p, self.state[2]);
    S.fold(&state, &p, self.carry);

    self.state = state[0..3].*;
    self.carry = state[3];
  } else {
    inline for (0..n) |_| {
      self.next();
    }
  }
}

pub fn hash(data: []const u8) u64 {
  var rng = fromBytes(data);
  rng.jump(JUMP_PHI);
  return rng.state[0];
}
