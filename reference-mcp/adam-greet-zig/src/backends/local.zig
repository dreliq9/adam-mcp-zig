//! Local backend — in-process fakes, no network. The default. Implements §2.6.

const types = @import("../types.zig");

pub const LocalBackend = struct {
    pub const mode_tag: []const u8 = "[LOCAL]";
    pub const available: bool = true;

    pub fn getWeather() types.WeatherSnapshot {
        return .{ .temperature_c = 18.0, .condition = "sunny" };
    }

    pub fn getNextEvent() ?types.CalendarEvent {
        return .{ .title = "Standup", .starts_at = "2026-05-13T09:00:00Z" };
    }

    pub fn getRecentMusic() []const types.MusicTrack {
        const tracks = struct {
            const list = [_]types.MusicTrack{
                .{ .title = "Sample Track", .artist = "Test Artist" },
            };
        };
        return &tracks.list;
    }

    pub fn calendarAuthenticated() bool {
        return true;
    }
};
