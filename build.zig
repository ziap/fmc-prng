const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;

  const search_module = b.createModule(.{
    .target = target,
    .optimize = optimize,
    .strip = strip,
    .link_libcpp = true,
  });

  search_module.addCSourceFiles(.{
    .files = &.{ "src/search.cpp" },
    .flags = &.{ "-Werror", "-Wall", "-Wextra", "-std=c++17", "-pedantic" },
  });

  search_module.linkSystemLibrary("gmp", .{});
  search_module.linkSystemLibrary("ntl", .{});

  const search = b.addExecutable(.{
    .name = "search",
    .root_module = search_module,
  });

  b.installArtifact(search);

  const search_cmd = b.addRunArtifact(search);
  if (b.args) |args| {
    search_cmd.addArgs(args);
  }

  const search_run = b.step("search", "Search for an MWC multiplier");
  search_run.dependOn(&search_cmd.step);

  const example = b.addExecutable(.{
    .name = "example",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/example.zig"),
      .target = target,
      .optimize = optimize,
      .strip = strip,
    }),
  });

  b.installArtifact(example);

  const example_cmd = b.addRunArtifact(example);
  if (b.args) |args| {
    example_cmd.addArgs(args);
  }

  const example_run = b.step("example", "Run the example");
  example_run.dependOn(&example_cmd.step);

  const speed_test = b.addExecutable(.{
    .name = "speed_test",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/speed-test.zig"),
      .target = target,
      .optimize = optimize,
      .strip = strip,
    }),
  });

  b.installArtifact(speed_test);

  const speed_test_cmd = b.addRunArtifact(speed_test);
  if (b.args) |args| {
    speed_test_cmd.addArgs(args);
  }

  const speed_test_run = b.step("speed-test", "Run the speed test");
  speed_test_run.dependOn(&speed_test_cmd.step);
}
