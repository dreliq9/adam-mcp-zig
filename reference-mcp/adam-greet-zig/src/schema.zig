//! Tool input schemas — Pydantic equivalent. Implements §1.2 + §2.9.
//!
//! PORT-NOTE [equivalent]: Python uses `pydantic.BaseModel` with Field
//!   constraints. Zig uses plain structs; std.json.parseFromValue
//!   handles parsing. Per-field constraints (min_length, ge/le) are
//!   PORT-NOTE [deferred-B] — Phase B will add a @validates extension
//!   that checks bounds after parsing.

pub const GreetingInput = struct {
    name: []const u8,
    /// 0..10 — checked at runtime by the tool body in Phase A.
    formality: u8 = 5,
};

pub const PersonalizedGreetingInput = struct {
    name: []const u8,
};

pub const RecordGreetingInput = struct {
    greeting: []const u8,
};

pub const RecentGreetingsInput = struct {
    /// 1..100
    n: u8 = 5,
};

pub const MorningBriefingInput = struct {
    name: []const u8,
    force: bool = false,
};

pub const RawGreetingInput = struct {
    template: []const u8,
};
