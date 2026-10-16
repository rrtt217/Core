-- test_presentation_commands.lua
--
-- Table-driven tests for Core's 1.12.2 presentation command parsers (/title, /particle, /playsound) and for
-- the two C++ backed whitelists they rely on.
--
-- Verified specification: specs/commands/vanilla-1.12.2-presentation-commands.md (parent repository).
-- The cases pin the 1.12.2 grammar that is easy to get wrong: the negative "times" values that are clamped
-- instead of refused, the optional count/speed tail of /particle, the required <source> of /playsound, and
-- the 1.13+ spellings (particle names such as "dust", the "ui" sound source, "^" local coordinates) that
-- 1.12.2 must reject.
--
-- Invariants:
--   * ParseTitleLine() / ParseParticleLine() / ParsePlaysoundLine() are pure functions of their token list:
--     they never touch a world, a player or a C++ object, and malformed input yields a reason, not an error.
--   * Every particle name the C++ lookup knows is accepted, and every name it does not know is refused:
--     cProtocol_1_8_0::GetProtocolParticleID() ASSERTS on an unknown name, which aborts an assert-enabled
--     build, so this whitelist is a safety net and not just a message.
--   * The listed 1.12.2 sound sources are accepted and the 1.21.6 addition "ui" is not.
--
-- Run with:  lua tests/test_presentation_commands.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_presentation.lua")

-- luacheck: globals ParseTitleLine ParseParticleLine ParsePlaysoundLine
-- luacheck: globals IsKnownParticleName IsKnownSoundSource GetAudibleRadius

local NumPassed = 0
local NumFailed = 0

local function Check(a_Condition, a_Message)
	if (a_Condition) then
		NumPassed = NumPassed + 1
	else
		NumFailed = NumFailed + 1
		print("FAIL: " .. a_Message)
	end
end

local function CheckEquals(a_Actual, a_Expected, a_Message)
	Check(
		a_Actual == a_Expected,
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end

--- Checks that a call returns nil plus a reason that contains a_Snippet.
local function CheckRefused(a_Call, a_Snippet, a_Message)
	local Parse, Reason = a_Call()
	Check(Parse == nil, a_Message .. " is refused")
	Check(
		(type(Reason) == "string") and (Reason:find(a_Snippet, 1, true) ~= nil),
		string.format("%s: the reason mentions \"%s\" (got %s)", a_Message, a_Snippet, tostring(Reason))
	)
end

--- Checks that a call survives garbage input instead of raising a Lua error.
local function CheckNoCrash(a_Call, a_Message)
	local Ok, Err = pcall(a_Call)
	Check(Ok, a_Message .. " does not raise (" .. tostring(Err) .. ")")
end






-- The 49 particle names of 1.12.2, transcribed from cProtocol_1_8_0::GetProtocolParticleID()
-- (src/Protocol/Protocol_1_8.cpp) rather than read from the parser, so that the two tables are checked
-- against each other instead of against themselves.
local PROTOCOL_PARTICLE_NAMES =
{
	"explode", "largeexplode", "hugeexplosion", "fireworksspark", "bubble", "splash", "wake", "suspended",
	"depthsuspend", "crit", "magiccrit", "smoke", "largesmoke", "spell", "instantspell", "mobspell",
	"mobspellambient", "witchmagic", "dripwater", "driplava", "angryvillager", "happyvillager", "townaura",
	"note", "portal", "enchantmenttable", "flame", "lava", "footstep", "cloud", "reddust", "snowballpoof",
	"snowshovel", "slime", "heart", "barrier", "iconcrack", "blockcrack", "blockdust", "droplet", "take",
	"mobappearance", "dragonbreath", "endrod", "damageindicator", "sweepattack", "fallingdust", "totem",
	"spit",
}

-- Particle names that only exist from 1.13 on (17w47a renamed the old ones), which must not be accepted.
local NEWER_PARTICLE_NAMES = { "dust", "block", "item", "explosion", "explosion_emitter", "effect" }

-- The ten 1.12.2 sound categories, plus the "ui" category 1.21.6 added.
local SOUND_SOURCES =
{
	"master", "music", "record", "weather", "block",
	"hostile", "neutral", "player", "ambient", "voice",
}
local NEWER_SOUND_SOURCES = { "ui", "MASTER", "records", "ambientmusic" }






local function TestParticleWhitelist()
	CheckEquals(#PROTOCOL_PARTICLE_NAMES, 49, "the 1.12.2 particle table has 49 names")
	for _, Name in ipairs(PROTOCOL_PARTICLE_NAMES) do
		Check(IsKnownParticleName(Name), "the particle \"" .. Name .. "\" is accepted")
	end

	-- The C++ lookup lowercases before matching, so the 1.12.2 camelCase spellings work too:
	Check(IsKnownParticleName("mobSpell"), "the 1.12.2 spelling \"mobSpell\" is accepted")
	Check(IsKnownParticleName("MOBSPELLAMBIENT"), "the lookup is case-insensitive")

	for _, Name in ipairs(NEWER_PARTICLE_NAMES) do
		Check(not IsKnownParticleName(Name), "the 1.13+ particle \"" .. Name .. "\" is refused")
	end
	Check(not IsKnownParticleName(""), "an empty name is refused")
	Check(not IsKnownParticleName(nil), "a nil name is refused")
	Check(not IsKnownParticleName(42), "a number is refused")
end






local function TestSoundSources()
	for _, Source in ipairs(SOUND_SOURCES) do
		Check(IsKnownSoundSource(Source), "the sound source \"" .. Source .. "\" is accepted")
	end
	for _, Source in ipairs(NEWER_SOUND_SOURCES) do
		Check(not IsKnownSoundSource(Source), "the unknown sound source \"" .. Source .. "\" is refused")
	end
	Check(not IsKnownSoundSource(nil), "a nil source is refused")

	CheckEquals(GetAudibleRadius(1.0), 16, "a sound at volume 1.0 is audible within 16 blocks")
	CheckEquals(GetAudibleRadius(0.5), 8, "the audible radius scales with the volume")
end






local function TestTitle()
	-- The three text modes take the rest of the line, spaces included:
	local Parse = ParseTitleLine({ "/title", "@a", "title", "Hello", "world" })
	Check(Parse ~= nil, "/title @a title Hello world parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.Mode, "title", "the mode is title")
		CheckEquals(Parse.Targets, "@a", "the target is @a")
		CheckEquals(Parse.Text, "Hello world", "the text keeps its spaces")
	end

	-- A quoted text arrives as one token, because the engine's splitter already removed the quotes:
	Parse = ParseTitleLine({ "/title", "player1", "subtitle", "Two words" })
	Check((Parse ~= nil) and (Parse.Text == "Two words"), "a quoted subtitle keeps its spaces")

	Parse = ParseTitleLine({ "/title", "@a", "actionbar", "&cHi" })
	Check(
		(Parse ~= nil) and (Parse.Mode == "actionbar") and (Parse.Text == "&cHi"),
		"the action bar text is kept verbatim"
	)

	-- times: three integers in game ticks, and "values below 0 will be treated as 0":
	Parse = ParseTitleLine({ "/title", "@a", "times", "10", "70", "20" })
	Check(Parse ~= nil, "/title @a times 10 70 20 parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.FadeIn, 10, "the fade in time is 10")
		CheckEquals(Parse.Stay, 70, "the stay time is 70")
		CheckEquals(Parse.FadeOut, 20, "the fade out time is 20")
	end

	Parse = ParseTitleLine({ "/title", "@a", "times", "-5", "-1", "0" })
	Check(Parse ~= nil, "negative times are accepted")
	if (Parse ~= nil) then
		CheckEquals(Parse.FadeIn, 0, "a negative fade in is clamped to 0")
		CheckEquals(Parse.Stay, 0, "a negative stay is clamped to 0")
		CheckEquals(Parse.FadeOut, 0, "zero stays zero")
	end

	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "times", "1s", "2", "3" }) end,
		"Invalid fade in",
		"a duration with a unit (1.19.4 syntax)"
	)
	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "times", "2147483648", "0", "0" }) end,
		"must be between",
		"a time outside the int32 range"
	)

	Parse = ParseTitleLine({ "/title", "@a", "clear" })
	Check((Parse ~= nil) and (Parse.Mode == "clear"), "/title @a clear parses")
	Parse = ParseTitleLine({ "/title", "@a", "reset" })
	Check((Parse ~= nil) and (Parse.Mode == "reset"), "/title @a reset parses")

	-- Shape errors and unknown actions:
	CheckRefused(function () return ParseTitleLine({ "/title" }) end, "Usage:", "/title without arguments")
	CheckRefused(function () return ParseTitleLine({ "/title", "@a" }) end, "Usage:", "/title without an action")
	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "title" }) end,
		"No text",
		"/title @a title without text"
	)
	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "times", "1", "2" }) end,
		"Usage:",
		"a short times list"
	)
	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "times", "1", "2", "3", "4" }) end,
		"Unexpected argument",
		"an extra times argument"
	)
	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "clear", "extra" }) end,
		"Unexpected argument",
		"an argument after clear"
	)
	CheckRefused(
		function () return ParseTitleLine({ "/title", "@a", "titles", "x" }) end,
		"Unknown title action",
		"a misspelled action"
	)
end






local function TestParticle()
	local Parse = ParseParticleLine({ "/particle", "explode", "~", "~1", "~-1", "1", "1", "1", "0.5", "10", "force" })
	Check(Parse ~= nil, "a full /particle line parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.Name, "explode", "the particle name is kept")
		CheckEquals(Parse.X, "~", "the x coordinate stays a token")
		CheckEquals(Parse.Y, "~1", "the y coordinate stays a token")
		CheckEquals(Parse.Z, "~-1", "the z coordinate stays a token")
		CheckEquals(Parse.OffsetX, "1", "the x spread is kept")
		CheckEquals(Parse.Speed, 0.5, "the speed is a number")
		CheckEquals(Parse.Count, 10, "the count is a number")
		CheckEquals(Parse.Mode, "force", "the display mode is kept")
	end

	-- The shortest 1.12.2 form: no count, no mode. An omitted count is the single-particle form:
	Parse = ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "1" })
	Check(Parse ~= nil, "the minimal /particle line parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.Count, 0, "an omitted count behaves like 0")
		CheckEquals(Parse.Mode, nil, "an omitted mode stays nil")
	end

	-- count 0 is legal and means "one particle"; "normal" is a legal mode:
	Parse = ParseParticleLine({ "/particle", "reddust", "0", "0", "0", "0", "1", "0", "1", "0", "normal" })
	Check((Parse ~= nil) and (Parse.Count == 0) and (Parse.Mode == "normal"), "count 0 and the normal mode parse")

	-- The 1.12.2 camelCase spelling works, exactly like the C++ lookup:
	Parse = ParseParticleLine({ "/particle", "mobSpell", "0", "0", "0", "0", "0", "0", "0" })
	Check((Parse ~= nil) and (Parse.Name == "mobSpell"), "a camelCase particle name is passed through unchanged")

	CheckRefused(
		function () return ParseParticleLine({ "/particle", "dust", "0", "0", "0", "0", "0", "0", "1" }) end,
		"Unknown particle",
		"a 1.13 particle name"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "-1" }) end,
		"must be at least 0",
		"a negative speed"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "fast" }) end,
		"Invalid speed",
		"a non-numeric speed"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "1", "-1" }) end,
		"must be at least 0",
		"a negative count"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "1", "1.5" }) end,
		"Invalid count",
		"a fractional count"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "1", "1", "loud" }) end,
		"Invalid display mode",
		"a misspelled display mode"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "^", "0", "0", "0", "0", "0", "1" }) end,
		"Invalid x coordinate",
		"a local (^) coordinate, which is 1.13 syntax"
	)
	CheckRefused(
		function ()
			return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0", "1", "1", "normal", "@a" })
		end,
		"viewers",
		"the unsupported <viewers> argument"
	)
	CheckRefused(
		function ()
			return ParseParticleLine(
				{ "/particle", "blockcrack", "0", "0", "0", "0", "0", "0", "1", "1", "normal", "@a", "1" }
			)
		end,
		"parameters",
		"the unsupported [params ...] tail"
	)
	CheckRefused(
		function () return ParseParticleLine({ "/particle", "explode", "0", "0", "0", "0", "0", "0" }) end,
		"Usage:",
		"a line without the speed"
	)

	-- Malformed input must not raise:
	CheckNoCrash(function () return ParseParticleLine(nil) end, "a nil token list")
	CheckNoCrash(function () return ParseParticleLine({}) end, "an empty token list")
	CheckNoCrash(function () return ParseParticleLine({ "/particle" }) end, "only the command name")
	CheckNoCrash(function () return ParseParticleLine({ "/particle", "", "", "", "", "", "", "", "" }) end, "empty tokens")
	CheckNoCrash(
		function () return ParseParticleLine({ "/particle", "explode", "~", "~", "~", "~", "~", "~", "~" }) end,
		"a tilde speed"
	)
end






local function TestPlaysound()
	local Parse = ParsePlaysoundLine({ "/playsound", "mob.pig.say", "master", "@a" })
	Check(Parse ~= nil, "the shortest /playsound line parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.Sound, "mob.pig.say", "the sound name is kept")
		CheckEquals(Parse.Source, "master", "the source is kept")
		CheckEquals(Parse.Targets, "@a", "the target is kept")
		CheckEquals(Parse.X, nil, "an omitted x stays nil (the execution position)")
		CheckEquals(Parse.Volume, 1.0, "the volume defaults to 1.0")
		CheckEquals(Parse.Pitch, 1.0, "the pitch defaults to 1.0")
		CheckEquals(Parse.MinimumVolume, 0.0, "the minimum volume defaults to 0.0")
	end

	Parse = ParsePlaysoundLine(
		{ "/playsound", "minecraft:mob.pig.say", "record", "player1", "~", "~1", "~-1", "2", "0.5", "0.3" }
	)
	Check(Parse ~= nil, "the full /playsound line parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.X, "~", "the x coordinate stays a token")
		CheckEquals(Parse.Volume, 2, "the volume is a number")
		CheckEquals(Parse.Pitch, 0.5, "the pitch is a number")
		CheckEquals(Parse.MinimumVolume, 0.3, "the minimum volume is a number")
	end

	-- The 1.12.2 range rules ("Must be at least 0.0" / "between 0.0 and 2.0" / "between 0.0 and 1.0"):
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "master", "@a", "~", "~", "~", "-1" }) end,
		"volume must be at least 0",
		"a negative volume"
	)
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "master", "@a", "~", "~", "~", "1", "2.5" }) end,
		"pitch must be at most 2",
		"a pitch above 2.0"
	)
	CheckRefused(
		function ()
			return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "master", "@a", "~", "~", "~", "1", "1", "1.5" })
		end,
		"minimum volume must be at most 1",
		"a minimum volume above 1.0"
	)

	-- The source argument is required in 1.12.2 and is one of ten categories:
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "@a" }) end,
		"Usage:",
		"a line without the source"
	)
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "ui", "@a" }) end,
		"Unknown sound source",
		"the 1.21.6 \"ui\" category"
	)
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "not a sound", "master", "@a" }) end,
		"Invalid sound",
		"a sound name with a space"
	)
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob:pig:say", "master", "@a" }) end,
		"Invalid sound",
		"a sound name with two colons"
	)

	-- The coordinates are consumed as a triple, so a partial triple is a usage error:
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "master", "@a", "1", "2" }) end,
		"Usage:",
		"a partial coordinate triple"
	)
	CheckRefused(
		function () return ParsePlaysoundLine({ "/playsound", "mob.pig.say", "master", "@a", "^", "^", "^" }) end,
		"Invalid x coordinate",
		"local (^) coordinates"
	)
	CheckRefused(
		function ()
			return ParsePlaysoundLine(
				{ "/playsound", "mob.pig.say", "master", "@a", "~", "~", "~", "1", "1", "0", "extra" }
			)
		end,
		"Unexpected argument",
		"a tenth argument"
	)

	CheckNoCrash(function () return ParsePlaysoundLine(nil) end, "a nil token list")
	CheckNoCrash(function () return ParsePlaysoundLine({}) end, "an empty token list")
	CheckNoCrash(
		function () return ParsePlaysoundLine({ "/playsound", "", "", "", "", "", "", "", "", "", "" }) end,
		"empty tokens"
	)
end






local function TestTitleGarbage()
	CheckNoCrash(function () return ParseTitleLine(nil) end, "a nil token list")
	CheckNoCrash(function () return ParseTitleLine({}) end, "an empty token list")
	CheckNoCrash(function () return ParseTitleLine({ "/title", "", "", "" }) end, "empty tokens")
	CheckNoCrash(function () return ParseTitleLine({ "/title", "@a", "times", "+", "-", "." }) end, "sign-only times")
end






TestParticleWhitelist()
TestSoundSources()
TestTitle()
TestParticle()
TestPlaysound()
TestTitleGarbage()

print(string.format("test_presentation_commands: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
