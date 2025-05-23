const std = @import("std");
const Datetime = @import("zig-datetime");
const readmeContents = @embedFile("./templates/readme_template.md");
const adrContents = @embedFile("./templates/adr_template.md");
const helpContents = @embedFile("./templates/help.txt");
const templateReadmeContents = @embedFile("./templates/readme_templates_folder.md");

fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs).compare(std.math.CompareOperator.lt);
}

fn readFileIfExists(allocator: std.mem.Allocator, filepath: []const u8) ![]u8 {
    const templateFile = try std.fs.cwd().openFile(filepath, .{});
    defer templateFile.close();

    const fileContents = try templateFile.readToEndAlloc(allocator, std.math.maxInt(usize));
    return fileContents;
}

fn rebuildReadme(allocator: std.mem.Allocator) !void {
    const templateContents = readFileIfExists(allocator, "./adr/templates/template_readme.md") catch readmeContents;
    // TODO: Too many "Datetime"s
    const now = Datetime.datetime.Datetime.now();
    const date = try now.formatHttp(allocator);
    defer allocator.free(date);

    const output = std.mem.replaceOwned(u8, allocator, templateContents, "{{timestamp}}", date) catch @panic("out of memory");
    defer allocator.free(output);

    const files = try getAllFilesInADRDir(allocator);
    defer files.deinit();

    var formattedFiles = std.ArrayList([]const u8).init(allocator);
    defer formattedFiles.deinit();

    std.mem.sort([]const u8, files.items, {}, compareStrings);

    for (files.items) |*str| {
        const new_str = try std.fmt.allocPrint(allocator, " - [{s}](./{s})", .{ str.*, str.* });
        try formattedFiles.append(new_str);
        allocator.free(str.*);
    }

    const replacement = try std.mem.join(allocator, "\n", formattedFiles.items);

    const withContents = std.mem.replaceOwned(u8, allocator, output, "{{contents}}", replacement) catch @panic("out of memory");
    defer allocator.free(withContents);

    const f = try std.fs.cwd().createFile("./adr/README.md", .{});
    defer f.close();
    _ = try f.write(withContents);
}

fn generateADR(allocator: std.mem.Allocator, n: u64, name: []u8) !void {
    const safeName = std.mem.replaceOwned(u8, allocator, name, " ", "-") catch @panic("out of memory");
    defer allocator.free(safeName);
    const paddedNums = try std.fmt.allocPrint(
        allocator,
        "{:0>5}",
        .{n},
    );
    defer allocator.free(paddedNums);
    const fileName = try std.fmt.allocPrint(
        allocator,
        "./adr/{s}-{s}.md",
        .{ paddedNums, safeName },
    );
    defer allocator.free(fileName);

    const heading = try std.fmt.allocPrint(
        allocator,
        "{s} - {s}",
        .{ paddedNums, name },
    );
    defer allocator.free(heading);

    const templateContents = readFileIfExists(allocator, "./adr/templates/template_adr.md") catch adrContents;
    const contents = std.mem.replaceOwned(u8, allocator, templateContents, "{{name}}", heading) catch @panic("Out of memory");
    defer allocator.free(contents);

    const f = try std.fs.cwd().createFile(fileName, .{ .read = true });
    defer f.close();
    try f.writeAll(contents);
}

fn establishCoreFiles() !void {
    const cwd = std.fs.cwd();
    try cwd.makePath("./adr/assets");
    try cwd.makePath("./adr/templates");

    const f = try std.fs.cwd().createFile("./adr/templates/README.md", .{});
    try f.writeAll(templateReadmeContents);
}

fn getAllFilesInADRDir(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var dir = try std.fs.cwd().openDir("./adr", .{ .iterate = true });
    defer dir.close();

    // Create an ArrayList to hold the file names
    var file_list = std.ArrayList([]const u8).init(allocator);

    // Iterate through the directory contents
    var dirIterator = dir.iterate();
    while (try dirIterator.next()) |dirContent| {
        // Append the file name to the ArrayList
        if (!std.mem.eql(u8, dirContent.name, "README.md") and !std.mem.eql(u8, dirContent.name, "assets") and !std.mem.eql(u8, dirContent.name, "templates")) {
            const fileName = try allocator.dupe(u8, dirContent.name);
            try file_list.append(fileName);
        }
    }

    return file_list;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout_file = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);

    const action = if (args.len > 1) args[1] else "";
    if (std.mem.eql(u8, action, "create")) {
        try establishCoreFiles();
        const name = std.mem.join(allocator, " ", args[2..]) catch unreachable;
        if (name.len == 0) {
            _ = try stderr_file.write("No name supplied for the ADR. Command should be: adl create Name of ADR here\n");
        } else {
            const fileList = try getAllFilesInADRDir(allocator);
            defer fileList.deinit();
            try generateADR(allocator, fileList.items.len, name);
            try rebuildReadme(allocator);
        }
        allocator.free(name);
    } else if (std.mem.eql(u8, action, "regen")) {
        try establishCoreFiles();
        try rebuildReadme(allocator);
    } else {
        _ = bw.write(helpContents) catch @panic("Unable to write help contents");
    }
    try bw.flush();
}
