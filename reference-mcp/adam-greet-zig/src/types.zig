//! Domain types. Implements §2.9.

pub const WeatherSnapshot = struct {
    temperature_c: f32,
    condition: []const u8,
};

pub const CalendarEvent = struct {
    title: []const u8,
    starts_at: []const u8,
};

pub const MusicTrack = struct {
    title: []const u8,
    artist: []const u8,
};

pub const MorningContext = struct {
    weather: WeatherSnapshot,
    next_event: ?CalendarEvent = null,
    recent_music: []const MusicTrack = &.{},
};
