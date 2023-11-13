const std = @import("std");
const mem = std.mem;
const fs = std.fs;

fn discoverDevices(alloc: mem.Allocator) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(alloc);

    var backlight_dir = try fs.openIterableDirAbsolute("/sys/class/backlight", .{});
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
    _ = try std.io.getStdErr().write(help_msg);
}

fn displayDeviceBrightness(alloc: mem.Allocator, name: []const u8) !void {
    const backlight_dir = try std.fs.openDirAbsolute("/sys/class/backlight", .{});
    const device_dir = try backlight_dir.openDir(name, .{});
    const file = try device_dir.openFile("actual_brightness", .{});
    defer file.close();

    const reader = file.reader();
    const content = try reader.readAllAlloc(alloc, 128);

    const stdout = std.io.getStdOut();
    _ = try stdout.write(content);
}

fn setDeviceBrightness(name: []const u8, value: u32) !void {
    const backlight_dir = try std.fs.openDirAbsolute("/sys/class/backlight/", .{});
    const device_dir = try backlight_dir.openDir(name, .{});

    const file = try device_dir.openFile("brightness", .{ .mode = .write_only });
    defer file.close();
    try file.writer().print("{d}", .{value});
}

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var alloc = fba.allocator();

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
                var stdout = std.io.getStdOut();
                for (devices) |dev| {
                    try stdout.writer().print("{s}\n", .{dev});
                }
            } else {
                const val_idx: usize = if (args.len == 3) 2 else 1;

                const val: u32 = if (args[val_idx][0] == 'h')
                    std.fmt.parseInt(u32, args[val_idx][1..], 16) catch {
                        try showHelp();
                        std.os.exit(1);
                        return;
                    }
                else
                    std.fmt.parseInt(u32, args[val_idx], 10) catch {
                        try showHelp();
                        std.os.exit(1);
                        return;
                    };

                const device = if (args.len == 3) args[1] else try getDefaultDeviceName(alloc);

                setDeviceBrightness(device, val) catch |err| switch (err) {
                    error.FileNotFound => {
                        std.log.err("device not found, use \"lis list\" to enumerate devices", .{});
                    },
                    else => return err,
                };
            }
        },
        else => {
            try showHelp();
            std.os.exit(1);
        },
    }
}
