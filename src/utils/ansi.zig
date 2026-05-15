const std = @import("std");

pub const Reset = "\x1b[0m";
pub const Bold = "\x1b[1m";
pub const Dim = "\x1b[2m";
pub const Italic = "\x1b[3m";
pub const Underline = "\x1b[4m";

pub const Red = "\x1b[31m";
pub const Green = "\x1b[32m";
pub const Yellow = "\x1b[33m";
pub const Blue = "\x1b[34m";
pub const Magenta = "\x1b[35m";
pub const Cyan = "\x1b[36m";
pub const White = "\x1b[37m";
pub const Gray = "\x1b[90m";
pub const BrightRed = "\x1b[91m";
pub const BrightGreen = "\x1b[92m";
pub const BrightYellow = "\x1b[93m";
pub const BrightBlue = "\x1b[94m";
pub const BrightMagenta = "\x1b[95m";
pub const BrightCyan = "\x1b[96m";
pub const BrightWhite = "\x1b[97m";

pub fn colorize(comptime color: []const u8, text: []const u8) []const u8 {
    return color ++ text ++ Reset;
}
