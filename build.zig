const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;

  const search = b.addExecutable(.{
    .name = "search",
    .target = target,
    .optimize = optimize,
    .strip = strip,
  });

  search.addCSourceFiles(.{
    .files = &.{ "src/search.cpp" },
    .flags = &.{ "-Werror", "-Wall", "-Wextra", "-std=c++17", "-pedantic" },
  });

  search.linkLibCpp();
  search.linkSystemLibrary("gmp");
  search.linkSystemLibrary("ntl");

  b.installArtifact(search);

  const search_cmd = b.addRunArtifact(search);
  if (b.args) |args| {
    search_cmd.addArgs(args);
  }

  const search_run = b.step("search", "Search for an MWC multiplier");
  search_run.dependOn(&search_cmd.step);

  const example = b.addExecutable(.{
    .name = "example",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .strip = strip,
  });

  b.installArtifact(example);

  const example_cmd = b.addRunArtifact(example);
  if (b.args) |args| {
    example_cmd.addArgs(args);
  }

  const example_run = b.step("example", "Run the example");
  example_run.dependOn(&example_cmd.step);
}
