const Fmc256 = @This();

const MUL = 0xfffcb1af7d963b55;
const endian = @import("builtin").target.cpu.arch.endian();

state: [4]u64,

/// Constructs an RNG from a 256-bit seed, maps them into the algebraic ring
pub fn fromSeed(seed: [4]u64) Fmc256 {
  var state: [4]u64 = undefined;
  var carry = seed[3];
  for (state[0..3], seed[0..3]) |*item, limb| {
    const m = @as(u128, limb) * MUL + carry;
    item.* = @truncate(m);
    carry = @intCast(m >> 64);
  }
  state[3] = carry;

  // Ensure non-zero state
  const v: u256 = @bitCast(state);
  if (v == 0) state[0] = 1;
  var result: Fmc256 = .{ .state = state };

  // Ensure state < MOD
  _ = result.next();
  return result;
}

/// Construct an RNG from an arbitrary length entropy sequence
pub fn fromBytes(data: []const u8) Fmc256 {
  const S = struct {
    inline fn mix(state: *[4]u64, chunk: u64) void {
      const m = @as(u128, state[0]) * MUL + state[3] + chunk;
      state[0] = state[1];
      state[1] = state[2];
      state[2] = @truncate(m);
      state[3] = @intCast(m >> 64);
    }
  };

  var state: [4]u64 = @splat(0);
  const step1 = @sizeOf(u64);
  const step3 = 3 * step1;
  var idx: usize = 0;

  while (idx + step3 <= data.len) : (idx += step3) {
    var chunk: [3]u64 = undefined;
    const chunk_ptr: *[step3]u8 = @ptrCast(&chunk);
    @memcpy(chunk_ptr, data[idx..idx + step3]);

    var carry = state[3];
    inline for (state[0..3], &chunk) |*item, x| {
      const limb = if (comptime endian == .little) x else @byteSwap(x);

      const m = @as(u128, item.*) * MUL + carry + limb;
      item.* = @truncate(m);
      carry = @intCast(m >> 64);
    }
    state[3] = carry;
  }

  blk: switch ((data.len - idx) / step1) {
    inline 1...2 => |x| {
      var chunk: u64 = undefined;
      const chunk_ptr: *[step1]u8 = @ptrCast(&chunk);
      @memcpy(chunk_ptr, data[idx..idx + step1]);
      if (comptime endian != .little) chunk = @byteSwap(chunk);

      S.mix(&state, chunk);
      idx += step1;
      continue :blk comptime x - 1;
    },
    inline 0 => {},
    else => unreachable,
  }

  if (idx < data.len) {
    var chunk: u64 = 0;
    blk: switch (data.len - idx) {
      inline 1...(step1 - 1) => |x| {
        const nx = comptime x - 1;
        chunk = (chunk << 8) | data[idx + nx];
        continue :blk nx;
      },
      inline 0 => {},
      else => unreachable,
    }

    S.mix(&state, chunk);
  }

  const v: u256 = @bitCast(state);
  if (v == 0) state[0] = 1;
  return .{ .state = state };
}

/// Generate the next 64-bit output from the generator and advance state by one
pub inline fn next(self: *Fmc256) u64 {
  const result = self.state[2] ^ self.state[3];
  const m = @as(u128, self.state[0]) * MUL + self.state[3];
  self.state[0] = self.state[1];
  self.state[1] = self.state[2];
  self.state[2] = @truncate(m);
  self.state[3] = @intCast(m >> 64);
  return result;
}

pub const Jump = struct {
  /// The algorithm's implicit modulus: MUL * 2^192 - 1
  const MOD = (MUL << 192) - 1;

  data: [4]u64,

  /// Montogomery style multiply-reduce routine, computes x*y*R^-1, R=2^320
  fn multiply(x: *const [4]u64, y: *const [4]u64) [4]u64 {
    var state: [4]u64 = @splat(0);

    inline for (y) |limb| {
      var ls: [4]u64 = undefined;
      var hs: [4]u64 = undefined;

      inline for (&ls, &hs, x) |*l, *h, s| {
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

    return state;
  }

  /// Split a 256-bit integer into four 64-bit little-endian limbs.  
  fn toParts(n: u256) [4]u64 {
    return .{
      @truncate(n),
      @truncate(n >> 64),
      @truncate(n >> 128),
      @intCast(n >> 192),
    };
  }

  /// Compute the jump multiplier multiplied by R that corresponds to advancing
  /// the generator by 'n' steps in O(log n)
  pub fn steps(n: u256) Jump {
    const r = (1 << 320) % MOD;
    const m = MUL << 128;

    if (@inComptime()) {
      // Use explicit mod, so only initialize with R instead of 1
      var a: u256 = r;
      var b: u256 = m;

      var t = n;
      while (t > 0) : (t >>= 1) {
        if (t & 1 != 0) a = @intCast(@as(u512, a) * b % MOD);
        b = @intCast(@as(u512, b) * b % MOD);
      }

      return .{ .data = toParts(a) };
    }

    // Use the multiply-reduction routine, so both the identity and base needs
    // to be multiplied by R
    var a = comptime toParts(r);
    var b = comptime toParts(m * r % MOD);

    var t = n;
    while (t > 0) : (t >>= 1) {
      if (t & 1 != 0) a = multiply(&a, &b);
      b = multiply(&b, &b);
    }

    return .{ .data = a };
  }

  /// The default step size for generating multiple uncorrelated generators
  /// Equals "golden ratio" - 1 when multiplied by the period of the generator
  /// Repeatedly jumping produces a low-discrepancy sequence of generators
  pub const default = default: {
    const a = (MOD - 1) / 2;
    const aa = a * a;

    var x = a / 2;
    var dec = false;

    // Newton's method iterations
    while (true) {
      const nx = (aa + x * x) / (a + x + x);
      if (x == nx or (dec and nx > x)) break;

      dec = nx < x;
      x = nx;
    }

    break :default steps(x);
  };
};

/// Advance the generator by the specified `Jump` multiplier
pub inline fn jump(self: *Fmc256, n: Jump) void {
  self.state = Jump.multiply(&self.state, &n.data);
}

/// Fill a buffer with values randomly generated from the generator
pub fn fill(self: *Fmc256, buffer: []u8) void {
  var idx: usize = 0;
  const step1 = @sizeOf(u64);
  const step3 = 3 * step1;

  while (idx + step3 <= buffer.len) : (idx += step3) {
    var chunk: [3]u64 = undefined;
    var carry = self.state[3];
    inline for (0..3, &chunk, self.state[0..3]) |i, *item, *limb| {
      item.* = self.state[comptime (i + 2) % 3] ^ carry;
      const m = @as(u128, limb.*) * MUL + carry;
      limb.* = @truncate(m);
      carry = @intCast(m >> 64);
    }
    self.state[3] = carry;

    if (comptime endian != .little) {
      for (&chunk) |*item| {
        item.* = @byteSwap(item.*);
      }
    }
    const chunk_ptr: *const [step3]u8 = @ptrCast(&chunk);
    @memcpy(buffer[idx..idx + step3], chunk_ptr);
  }

  blk: switch ((buffer.len - idx) / step1) {
    inline 1...2 => |x| {
      const n = self.next();
      const chunk = if (comptime endian == .little) n else @byteSwap(n);
      const chunk_ptr: *const [step1]u8 = @ptrCast(&chunk);
      @memcpy(buffer[idx..idx + step1], chunk_ptr);
      idx += step1;
      continue :blk comptime x - 1;
    },
    inline 0 => {},
    else => unreachable,
  }

  if (idx < buffer.len) {
    const n = self.next();
    blk: switch (buffer.len - idx) {
      inline 1...(step1 - 1) => |x| {
        const nx = comptime x - 1;
        buffer[idx + nx] = @truncate(n >> comptime (8 * nx));
        continue :blk nx;
      },
      inline 0 => {},
      else => unreachable,
    }
  }
}
