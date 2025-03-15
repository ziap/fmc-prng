const std = @import("std");
const Fmc256 = @import("Fmc256.zig");

// Vectorized PCG-32 that outputs a pair of 32-bit number at a time
// Original PCG-32 from: <https://www.pcg-random.org/download.html>
const Pcg32x2 = struct {
  state: u64,

  fn next(self: *Pcg32x2) u64 {
    const s0 = self.state;
    const s1 = s0 *% 0x5851f42d4c957f2d +% 0x14057b7ef767814f;
    self.state = s0 *% 0x685f98a2018fade9 +% 0x1a08ee1184ba6d32;
    const s: @Vector(2, u64) = .{ s0, s1 };

    const mask: @Vector(2, u64) = comptime @splat(0xffffffff);
    const xorshifted = ((s ^ (s >> @splat(18))) >> @splat(27)) & mask;
    const rot: @Vector(2, u5) = @intCast(s >> @splat(59));
    const out = (xorshifted >> rot) | (xorshifted << -% rot);

    return (out[0] << 32) | @as(u32, @truncate(out[1]));
  }
};

// Adapted from: <https://github.com/numpy/numpy/issues/13635#issuecomment-506088698>
const PcgDXSM = struct {
  state: u128,

  fn next(self: *PcgDXSM) u64 {
    const MUL = 0xda942042e4dd58b5;
    const INC = 0x5851f42d4c957f2d14057b7ef767814f;

    const state = self.state;
    self.state = self.state *% MUL +% INC;

    var hi: u64 = @intCast(state >> 64);
    const lo: u64 = @truncate(state);

    hi = (hi ^ (hi >> 32)) *% MUL;
    return (hi ^ (hi >> 48)) *% (lo | 1);
  }
};

// The minimal-standard PRNG
// Adapted from: <https://github.com/lemire/testingRNG/blob/master/source/lehmer64.h>
const Lehmer64 = struct {
  state: u128,

  fn next(self: *Lehmer64) u64 {
    self.state *%= 0xda942042e4dd58b5;
    return @intCast(self.state >> 64);
  }
};

// Adapted from: <https://prng.di.unimi.it/xoshiro256plusplus.c>
const Xoshiro256 = struct {
  s: [4]u64,

  fn next(self: *Xoshiro256) u64 {
    const S = struct {
      inline fn rotl(data: u64, rot: u6) u64 {
        return (data << rot) | (data >> -% rot);
      }
    };

    const r = S.rotl(self.s[0] +% self.s[3], 23) +% self.s[0];
    const t = self.s[1] << 17;

    self.s[2] ^= self.s[0];
    self.s[3] ^= self.s[1];
    self.s[1] ^= self.s[2];
    self.s[0] ^= self.s[3];

    self.s[2] ^= t;
    self.s[3] = S.rotl(self.s[3], 45);

    return r;
  }
};

// Adapted from: <https://prng.di.unimi.it/splitmix64.c>
const Splitmix64 = struct {
  state: u64,

  fn next(self: *Splitmix64) u64 {
    var z = self.state;
    self.state +%= 0x9e3779b97f4a7c15;

    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
  }
};

// A variant of Wyrand before this commit:
// <https://github.com/wangyi-fudan/wyhash/commit/16ca96d36251bd63d15a6d7b4abb2f04199de889>
// It is slower but has better statistical quality than the current version,
// which was shown to fail PractRand:
// <https://github.com/wangyi-fudan/wyhash/issues/135>
const Wyrand = struct {
  state: u64,

  fn next(self: *Wyrand) u64 {
    var s = self.state;
    self.state +%= 0x9e3779b97f4a7c55;

    inline for (.{0xa3b195354a39b70d, 0x1b03738712fad5c9}) |m| {
      const z = @as(u128, s) *% m;
      s = @as(u64, @intCast(z >> 64)) ^ @as(u64, @truncate(z));
    }

    return s;
  }
};

const generators = .{ Fmc256, Pcg32x2, PcgDXSM, Lehmer64, Xoshiro256, Splitmix64, Wyrand };

fn monteCarloPI64(rng: anytype, count: u64) f64 {
  var hit: u64 = 0;
  for (0..count) |_| {
    const n = rng.next();
    const x: u32 = @truncate(n);
    const y: u32 = @intCast(n >> 32);

    const xx = @as(u64, x) * @as(u64, x);
    const yy = @as(u64, y) * @as(u64, y);

    if (xx +% yy >= xx) hit += 1;
  }

  return @as(f64, @floatFromInt(4 * hit)) / @as(f64, @floatFromInt(count));
}

fn binom(n: comptime_int) @Vector(n + 1, f64) {
  var result: [n + 1]f64 = .{ 0} ** (n + 1);
  result[0] = 1;
  for (1..n + 1) |i| {
    for (0..i) |j| {
      result[i - j] += result[i - j - 1];
    }
  }
  
  return result;
}

fn hammingWeight64(rng: anytype, count: u64) f64 {
  var hit: [65]f64 = .{ 0 } ** 65;

  for (0..count) |_| {
    hit[@popCount(rng.next())] += 1;
  }

  const hit_v: @Vector(65, f64) = hit;
  const scale: @Vector(65, f64) = @splat(@as(f64, @floatFromInt(count)) / 18446744073709551616);
  const expected = binom(64) * scale;

  const d = hit_v - expected;
  const chi_squared = @reduce(.Add, d * d / expected);

  return chi_squared;
}

pub fn main() !void {
  var buffer = std.io.bufferedWriter(std.io.getStdOut().writer());
  defer buffer.flush() catch {};
  var writer = buffer.writer();

  var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
  defer arena.deinit();
  const allocator = arena.allocator();

  const args = try std.process.argsAlloc(allocator);

  const n = blk: {
    const default: usize = 1 << 32;
    if (args.len <= 1) {
      break :blk default;
    } else {
      break :blk std.fmt.parseInt(usize, args[1], 10) catch default;
    }
  };
  const entropy_raw: u256 = 0x243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89;
  const entropy_pool: *const [256]u8 = @ptrCast(&entropy_raw);

  const testNames = .{ "Monte Carlo PI estimation", "Hamming weight Chi-squared" };
  const tests64 = .{ monteCarloPI64, hammingWeight64 };

  inline for (testNames, tests64) |testName, test64| {
    writer.writeAll("Running test " ++ testName ++ "\n") catch return;
    buffer.flush() catch return;
    inline for (generators) |Rng| {
      var rng: Rng = undefined;

      if (@hasField(Rng, "fromSeed")) {
        rng = Rng.fromSeed(@ptrCast(&entropy_pool));
      } else {
        const rng_size = @sizeOf(Rng);
        const rng_ptr: *[rng_size]u8 = @ptrCast(&rng);
        @memcpy(rng_ptr, entropy_pool[0..rng_size]);
      }

      var timer = try std.time.Timer.start();
      const result = test64(&rng, n);
      const elapsed: f64 = @floatFromInt(timer.read());

      writer.print("{} - {d} - {d}ms\n", .{
        Rng,
        result,
        elapsed / std.time.ns_per_ms
      }) catch return;
      buffer.flush() catch return;
    }

    writer.writeAll("-" ** 80 ++ "\n") catch return;
    buffer.flush() catch return;
  }
}
