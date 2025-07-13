const std = @import("std");
const mem = std.mem;
const fs = std.fs;

fn discoverDevices(alloc: mem.Allocator) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(alloc);

    var backlight_dir = try fs.openDirAbsolute("/sys/class/backlight", .{ .iterate = true });
    defer backlight_dir.close();

    var iter = backlight_dir.iterate();
    while (try iter.next()) |entry| {
        try out.append(try alloc.dupe(u8, entry.name));
    }

    return out.items;
}

fn getDefaultDeviceName(alloc: mem.Allocator) ![]const u8 {
    const devices = try discoverDevices(alloc);
    return devices[0];
}

const help_msg =
    \\usage: lis ([device_name]? [brightness] | "list")
    \\  by default shows current brightness
    \\  
    \\  when supplied with brightness, sets the value for device or
    \\  default device when unspecified.
    \\  (you can use hex by appending h before brightness value). 
    \\
    \\  list will print out all available devices
    \\
    \\EXAMPLE:
    \\  show current brightness:
    \\
    \\  $ lis
    \\
    \\  set current brightness (in decimal):
    \\
    \\  $ lis 234
    \\
    \\  set current brightness on device "amdgpu_bl1" (in hex):
    \\
    \\  $ lis amdgpu_bl1 h9c
    \\
    \\
;

fn showHelp() !void {
    _ = try std.fs.File.stderr().write(help_msg);
}

fn readValue(arena: mem.Allocator, device: []const u8, value_name: []const u8) !u32 {
    const backlight_dir = try std.fs.openDirAbsolute("/sys/class/backlight", .{});
    const device_dir = try backlight_dir.openDir(device, .{});
    const file = try device_dir.openFile(value_name, .{});
    defer file.close();
    const content = try file.readToEndAlloc(arena, 128);
    defer arena.free(content);

    std.log.debug("{s}.{s} = '{s}'", .{ device, value_name, content });

    return try std.fmt.parseInt(u32, content[0 .. content.len - 1], 10);
}

fn displayDeviceBrightness(alloc: mem.Allocator, device: []const u8) !void {
    const stdout = std.fs.File.stdout();
    const value = try readValue(alloc, device, "actual_brightness");
    _ = try stdout.deprecatedWriter().print("{d}\n", .{value});
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn invLerp(a: f32, b: f32, t: f32) f32 {
    return (t - a) / (b - a);
}

fn remap(a: f32, b: f32, c: f32, d: f32, t: f32) f32 {
    const rel = invLerp(a, b, t);
    return lerp(c, d, rel);
}

fn setDeviceBrightness(arena: mem.Allocator, name: []const u8, value: u32) !void {
    const backlight_dir = try std.fs.openDirAbsolute("/sys/class/backlight/", .{});
    const device_dir = try backlight_dir.openDir(name, .{});

    const max_brightness = try readValue(arena, name, "max_brightness");
    const remapped = remap(0, 255, 0, @floatFromInt(max_brightness), @floatFromInt(value));
    std.log.debug("orig = {d}, remapped = {d}", .{ value, @as(u32, @intFromFloat(remapped)) });

    const file = try device_dir.openFile("brightness", .{ .mode = .write_only });
    defer file.close();
    try file.deprecatedWriter().print("{d}", .{remapped});
}

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const args = try std.process.argsAlloc(alloc);
    switch (args.len) {
        1 => {
            const name: []const u8 = try getDefaultDeviceName(alloc);
            try displayDeviceBrightness(alloc, name);
        },
        2, 3 => {
            if (mem.eql(u8, args[1], "--help") or mem.eql(u8, args[1], "-h")) {
                try showHelp();
            } else if (mem.eql(u8, args[1], "list")) {
                const devices = try discoverDevices(alloc);
                var stdout = std.fs.File.stdout();
                for (devices) |dev| {
                    try stdout.deprecatedWriter().print("{s}\n", .{dev});
                }
            } else {
                const val_idx: usize = if (args.len == 3) 2 else 1;

                const val: u32 = if (args[val_idx][0] == 'h')
                    std.fmt.parseInt(u32, args[val_idx][1..], 16) catch {
                        try showHelp();
                        std.posix.exit(1);
                        return;
                    }
                else
                    std.fmt.parseInt(u32, args[val_idx], 10) catch {
                        try showHelp();
                        std.posix.exit(1);
                        return;
                    };

                const device = if (args.len == 3) args[1] else try getDefaultDeviceName(alloc);

                setDeviceBrightness(alloc, device, val) catch |err| switch (err) {
                    error.FileNotFound => {
                        std.log.err("device not found, use \"lis list\" to enumerate devices", .{});
                    },
                    else => return err,
                };
            }
        },
        else => {
            try showHelp();
            std.posix.exit(1);
        },
    }
}
