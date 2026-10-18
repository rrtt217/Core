-- test_presentation_commands.lua
--
-- Table-driven tests for Core's 1.12.2 presentation and text commands (/title, /particle, /playsound,
-- /tellraw): their argument parsers, the JSON text-component layer, and the two C++ backed whitelists the
-- command layer relies on.
--
-- Verified specification: specs/commands/vanilla-1.12.2-presentation-commands.md (parent repository).
-- The cases pin the 1.12.2 grammar that is easy to get wrong: the negative "times" values that are clamped
-- instead of refused, the optional count/speed tail of /particle, the required <source> of /playsound, the
-- fact that a JSON component has to come from the raw command line (the engine's splitter strips the quotes),
-- and the 1.13+ spellings (particle names such as "dust", the "ui" sound source, "^" local coordinates) that
-- 1.12.2 must reject.
--
-- Invariants:
--   * ParseTitleLine() / ParseParticleLine() / ParsePlaysoundLine() are pure functions of their token list:
--     they never touch a world, a player or a C++ object, and malformed input yields a reason, not an error.
--   * ParseTellrawLine() and CheckTextComponent() are the only ones that call into the engine, through
--     cJson:Parse(); the tests replace cJson with a small parser of their own (below).
--   * A text component that a 1.12.2 client cannot render on its own ("selector", "score") is refused rather
--     than sent, because a client renders it as the selector text or as nothing at all.
--   * Every particle name the C++ lookup knows is accepted, and every name it does not know is refused:
--     cProtocol_1_8_0::GetProtocolParticleID() ASSERTS on an unknown name, which aborts an assert-enabled
--     build, so this whitelist is a safety net and not just a message.
--   * The listed 1.12.2 sound sources are accepted and the 1.21.6 addition "ui" is not.
--
-- Run with:  lua tests/test_presentation_commands.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_execute.lua")  -- SplitRawCommand(), the mirror of the engine's splitter
dofile(ScriptDir .. "/../command_presentation.lua")
dofile(ScriptDir .. "/../command_text.lua")

-- luacheck: globals ParseTitleLine ParseParticleLine ParsePlaysoundLine ParseTellrawLine ParseStopsoundLine
-- luacheck: globals IsKnownParticleName IsKnownSoundSource GetAudibleRadius BuildStopSoundPayload
-- luacheck: globals CutRawRemainder CheckTextComponent ParseTextArgument CheckChatDeliverable MakeChatSafe
-- luacheck: globals SplitRawCommand cJson

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

--- A minimal JSON parser standing in for the engine's cJson:Parse(), which wraps jsoncpp
-- (src/Bindings/LuaJson.cpp). It is faithful for what these tests need: objects and arrays become tables,
-- scalars become Lua values, a JSON null becomes plain nil, and malformed input returns nil plus a message.
local JSON_NULL = setmetatable({}, { __tostring = function () return "null" end })

local function SkipWhitespace(a_Text, a_Position)
	while (a_Position <= #a_Text) and (a_Text:sub(a_Position, a_Position):match("%s") ~= nil) do
		a_Position = a_Position + 1
	end
	return a_Position
end

local ParseJsonValue  -- forward declaration: ParseJsonValue() and the container parsers call each other

local function ParseJsonString(a_Text, a_Position)
	-- a_Position points at the opening quote:
	local Result = {}
	local Index = a_Position + 1
	while (Index <= #a_Text) do
		local Char = a_Text:sub(Index, Index)
		if (Char == "\"") then
			return table.concat(Result), Index + 1
		end
		if (Char == "\\") then
			local Escape = a_Text:sub(Index + 1, Index + 1)
			local Mapped = ({ ["n"] = "\n", ["t"] = "\t", ["r"] = "\r", ["b"] = "\b", ["f"] = "\f" })[Escape]
			Result[#Result + 1] = Mapped or Escape
			Index = Index + 2
		else
			Result[#Result + 1] = Char
			Index = Index + 1
		end
	end
	return nil, "unterminated string"
end

local function ParseJsonArray(a_Text, a_Position)
	local Result = {}
	local Index = SkipWhitespace(a_Text, a_Position + 1)
	if (a_Text:sub(Index, Index) == "]") then
		return Result, Index + 1
	end
	while true do
		local Value, Next = ParseJsonValue(a_Text, Index)
		if (Value == nil) then
			return nil, Next
		end
		Result[#Result + 1] = Value
		Index = SkipWhitespace(a_Text, Next)
		local Char = a_Text:sub(Index, Index)
		if (Char == "]") then
			return Result, Index + 1
		end
		if (Char ~= ",") then
			return nil, "expected ',' or ']'"
		end
		Index = SkipWhitespace(a_Text, Index + 1)
	end
end

local function ParseJsonObject(a_Text, a_Position)
	local Result = {}
	local Index = SkipWhitespace(a_Text, a_Position + 1)
	if (a_Text:sub(Index, Index) == "}") then
		return Result, Index + 1
	end
	while true do
		local Key, Next = ParseJsonString(a_Text, Index)
		if (Key == nil) then
			return nil, Next
		end
		Index = SkipWhitespace(a_Text, Next)
		if (a_Text:sub(Index, Index) ~= ":") then
			return nil, "expected ':'"
		end
		local Value, ValueNext = ParseJsonValue(a_Text, SkipWhitespace(a_Text, Index + 1))
		if (Value == nil) then
			return nil, ValueNext
		end
		Result[Key] = Value
		Index = SkipWhitespace(a_Text, ValueNext)
		local Char = a_Text:sub(Index, Index)
		if (Char == "}") then
			return Result, Index + 1
		end
		if (Char ~= ",") then
			return nil, "expected ',' or '}'"
		end
		Index = SkipWhitespace(a_Text, Index + 1)
	end
end

ParseJsonValue = function (a_Text, a_Position)
	local Char = a_Text:sub(a_Position, a_Position)
	if (Char == "{") then
		return ParseJsonObject(a_Text, a_Position)
	elseif (Char == "[") then
		return ParseJsonArray(a_Text, a_Position)
	elseif (Char == "\"") then
		return ParseJsonString(a_Text, a_Position)
	elseif (a_Text:sub(a_Position, a_Position + 3) == "true") then
		return true, a_Position + 4
	elseif (a_Text:sub(a_Position, a_Position + 4) == "false") then
		return false, a_Position + 5
	elseif (a_Text:sub(a_Position, a_Position + 3) == "null") then
		return JSON_NULL, a_Position + 4
	end

	local Number = a_Text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", a_Position)
	if (Number ~= nil) and (Number ~= "") then
		return tonumber(Number), a_Position + #Number
	end
	return nil, "unexpected character '" .. Char .. "'"
end

cJson =
{
	Parse = function (a_Self, a_Text)
		assert(a_Self == cJson, "cJson:Parse must be called with colon syntax")
		if (type(a_Text) ~= "string") then
			return nil, "Parsing Json failed: the input is not a string"
		end

		local Value, Next = ParseJsonValue(a_Text, SkipWhitespace(a_Text, 1))
		if (Value == nil) then
			return nil, "Parsing Json failed: " .. tostring(Next)
		end
		if (SkipWhitespace(a_Text, Next) <= #a_Text) then
			return nil, "Parsing Json failed: trailing characters"
		end
		if (Value == JSON_NULL) then
			return nil
		end
		return Value
	end,
}

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






local function TestStopsound()
	-- The payload 1.12.2 sends on the "MC|StopSound" channel is always two length-prefixed strings - the
	-- category, then the sound event - and a part the command did not ask for is an empty string. All three
	-- forms below are the server's actual bytes, captured with ProtoProxy from a vanilla 1.12.2 server.
	CheckEquals(
		BuildStopSoundPayload("weather", "minecraft:weather.rain"),
		"\7weather\22minecraft:weather.rain",
		"both arguments: 07 \"weather\" 16 \"minecraft:weather.rain\""
	)
	CheckEquals(
		BuildStopSoundPayload("weather", nil),
		"\7weather\0",
		"a category alone: 07 \"weather\" 00"
	)
	CheckEquals(
		BuildStopSoundPayload(nil, nil),
		"\0\0",
		"no argument at all: 00 00, not an empty payload"
	)

	-- The length prefix is a VarInt, so a long sound name still encodes correctly:
	local LongName = string.rep("a", 200)
	local LongPayload = BuildStopSoundPayload(nil, LongName)
	CheckEquals(LongPayload:sub(1, 3), "\0\200\1", "an empty category, then a length above 127 as two VarInt bytes")
	CheckEquals(LongPayload:sub(4, 3 + #LongName), LongName, "the name itself is written unchanged")
	CheckEquals(#LongPayload, 3 + #LongName, "the payload is exactly the two length prefixes plus the name")

	-- Parsing:
	local Parse = ParseStopsoundLine({ "/stopsound", "Harry00025", "weather", "minecraft:weather.rain" })
	Check(Parse ~= nil, "the captured command line parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.Targets, "Harry00025", "the target is kept")
		CheckEquals(Parse.Source, "weather", "the category is kept")
		CheckEquals(Parse.Sound, "minecraft:weather.rain", "the sound is kept verbatim")
	end

	Parse = ParseStopsoundLine({ "stopsound", "@a" })
	Check((Parse ~= nil) and (Parse.Source == nil) and (Parse.Sound == nil), "a bare target parses")
	Parse = ParseStopsoundLine({ "stopsound", "@a", "record" })
	Check((Parse ~= nil) and (Parse.Source == "record") and (Parse.Sound == nil), "a category without a sound parses")

	CheckRefused(function () return ParseStopsoundLine({ "/stopsound" }) end, "Usage:", "a missing target")
	CheckRefused(
		function () return ParseStopsoundLine({ "/stopsound", "@a", "ui" }) end,
		"Unknown sound source",
		"the 1.21.6 ui category"
	)
	CheckRefused(
		function () return ParseStopsoundLine({ "/stopsound", "@a", "master", "not a sound" }) end,
		"Invalid sound",
		"a single token that is not shaped like a sound name"
	)
	-- The engine would split that into separate tokens, so the real line is refused as an extra argument:
	CheckRefused(
		function () return ParseStopsoundLine({ "/stopsound", "@a", "master", "not", "a", "sound" }) end,
		"Unexpected argument",
		"a sound name typed with spaces"
	)
	CheckRefused(
		function () return ParseStopsoundLine({ "/stopsound", "@a", "master", "one", "extra" }) end,
		"Unexpected argument",
		"a fourth argument"
	)

	CheckNoCrash(function () return ParseStopsoundLine(nil) end, "a nil token list")
	CheckNoCrash(function () return ParseStopsoundLine({}) end, "an empty token list")
end






local function TestRawRemainder()
	-- The engine's token list has its quotes stripped; the raw remainder must not lose them, because a JSON
	-- component is only valid with them:
	CheckEquals(
		CutRawRemainder({ "/tellraw", "@a", "{\"text\":\"Hi there\"}" }, "/tellraw @a {\"text\":\"Hi there\"}", 2),
		"{\"text\":\"Hi there\"}",
		"the JSON argument survives exactly as typed"
	)
	CheckEquals(
		CutRawRemainder({ "/title", "@a", "title", "Hello", "world" }, "/title @a title Hello world", 3),
		"Hello world",
		"a multi-token plain text is cut out of the raw line"
	)
	-- A quoted argument keeps its quotes in the raw remainder (a JSON component needs them); the plain-text
	-- form of the same argument comes from the tokens instead, so the quotes never reach the screen:
	CheckEquals(
		CutRawRemainder({ "/title", "@a", "title", "a  b" }, "/title @a title \"a  b\"", 3),
		"\"a  b\"",
		"the raw remainder keeps the quotes it was typed with"
	)
	local Quoted = ParseTextArgument(
		CutRawRemainder({ "/title", "@a", "title", "a  b" }, "/title @a title \"a  b\"", 3),
		"a  b"
	)
	Check(
		(Quoted ~= nil) and (Quoted.Kind == "plain") and (Quoted.Text == "a  b"),
		"a quoted plain text is rendered without its quotes"
	)

	-- Anything that does not line up with the token list must give up rather than cut the wrong text:
	CheckEquals(CutRawRemainder({ "/title", "@a" }, "/title @a", 2), nil, "nothing left to cut")
	CheckEquals(CutRawRemainder({ "/title", "@a", "title" }, "/title  @a title", 3), nil, "the token lists differ")
	CheckEquals(CutRawRemainder({ "/title", "@a", "title" }, nil, 1), nil, "no raw command")
	CheckEquals(CutRawRemainder(nil, "/title @a title x", 1), nil, "no token list")

	-- A JSON title only survives when the raw command is available. The token list is what the engine really
	-- produces for the raw line (StringSplitCommandLine removes the quotes it splits on):
	local Split = { "/title", "@a", "title", "{text:Hi there}" }
	local Parse = ParseTitleLine(Split, "/title @a title {\"text\":\"Hi there\"}")
	Check(Parse ~= nil, "a JSON title parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.RawText, "{\"text\":\"Hi there\"}", "the raw text is returned for a JSON component")
		CheckEquals(Parse.Text, "{text:Hi there}", "the joined tokens are what the engine alone would give")
		local Argument = ParseTextArgument(Parse.RawText, Parse.Text)
		Check(
			(Argument ~= nil) and (Argument.Kind == "json") and (Argument.Json == "{\"text\":\"Hi there\"}"),
			"the raw form is the one that is sent"
		)
		-- Without the raw line the engine's mangled token is refused instead of being shown as literal text:
		local Broken, BrokenReason = ParseTextArgument(nil, Parse.Text)
		Check(
			(Broken == nil) and (BrokenReason ~= nil) and (BrokenReason:find("Invalid JSON", 1, true) ~= nil),
			"without the raw line a JSON argument is refused, not mangled"
		)
	end

	Parse = ParseTitleLine({ "/title", "@a", "title", "Hi" })
	Check((Parse ~= nil) and (Parse.RawText == nil), "without a raw command there is no raw text")
end






local function TestTextComponents()
	-- What a 1.12.2 client can render on its own is accepted:
	CheckEquals(CheckTextComponent("{\"text\":\"Hi there\",\"bold\":true}"), nil, "a plain text component is valid")
	CheckEquals(CheckTextComponent("[\"a\",{\"text\":\"b\"}]"), nil, "an array of components is valid")
	CheckEquals(
		CheckTextComponent("{\"text\":\"a\",\"extra\":[{\"text\":\"b\",\"color\":\"red\"}]}"),
		nil,
		"a component with an extra list is valid"
	)

	-- Malformed JSON, and JSON that is not a component:
	local Reason = CheckTextComponent("{\"text\":")
	Check((Reason ~= nil) and (Reason:find("Invalid JSON", 1, true) ~= nil), "unparsable JSON is refused")
	Reason = CheckTextComponent("42")
	Check((Reason ~= nil) and (Reason:find("object or array", 1, true) ~= nil), "a JSON number is not a component")
	Reason = CheckTextComponent("\"just a string\"")
	Check((Reason ~= nil) and (Reason:find("object or array", 1, true) ~= nil), "a bare JSON string is not a component")
	Reason = CheckTextComponent("null")
	Check((Reason ~= nil) and (Reason:find("object or array", 1, true) ~= nil), "a JSON null is not a component")

	-- The server-side components would render wrongly if they were sent unresolved:
	Reason = CheckTextComponent("{\"selector\":\"@a\"}")
	Check((Reason ~= nil) and (Reason:find("selector", 1, true) ~= nil), "the selector component is refused")
	Reason = CheckTextComponent("{\"score\":{\"name\":\"*\",\"objective\":\"obj\"}}")
	Check((Reason ~= nil) and (Reason:find("score", 1, true) ~= nil), "the score component is refused")
	Reason = CheckTextComponent("{\"text\":\"a\",\"extra\":[{\"selector\":\"@p\"}]}")
	Check((Reason ~= nil) and (Reason:find("selector", 1, true) ~= nil), "a nested selector component is refused")

	-- A component that merely mentions the words is fine:
	CheckEquals(CheckTextComponent("{\"text\":\"selector and score\"}"), nil, "the words inside a text are not components")

	-- The chat packet refuses "${", so the command layer reports it instead of claiming a success:
	CheckEquals(CheckChatDeliverable("{\"text\":\"hi\"}"), nil, "ordinary text is deliverable")
	local Forbidden = CheckChatDeliverable("{\"text\":\"${jndi}\"}")
	Check(Forbidden ~= nil, "the ${ sequence is refused")
	-- ... and the reason must itself be deliverable, or the chat packet drops the explanation too:
	CheckEquals(CheckChatDeliverable(Forbidden), nil, "the refusal reason survives the same guard")

	-- A reason that quotes user input has to be made deliverable before it is sent:
	CheckEquals(MakeChatSafe("Unknown particle \"${x}\""), "Unknown particle \"$ {x}\"", "the sequence is broken up")
	CheckEquals(CheckChatDeliverable(MakeChatSafe("a${b}c${d}")), nil, "the result is deliverable")
	CheckEquals(MakeChatSafe("no sequence here"), "no sequence here", "ordinary text is left alone")
	CheckEquals(MakeChatSafe("$${"), "$$ {", "only the sequence itself is broken up")

	-- ParseTextArgument() picks the JSON form only for an argument that starts like JSON:
	local Argument = ParseTextArgument("{\"text\":\"Hi\"}", "{text:Hi}")
	Check(
		(Argument ~= nil) and (Argument.Kind == "json") and (Argument.Json == "{\"text\":\"Hi\"}"),
		"a JSON argument is used verbatim"
	)
	Argument = ParseTextArgument("Hello there", "Hello there")
	Check((Argument ~= nil) and (Argument.Kind == "plain") and (Argument.Text == "Hello there"), "plain text stays plain")
	-- A plain text whose raw form and token form differ keeps the token form, which is the readable one:
	Argument = ParseTextArgument("Hello  there", "Hello there")
	Check(
		(Argument ~= nil) and (Argument.Kind == "plain") and (Argument.Text == "Hello there"),
		"plain text uses the joined tokens"
	)
	-- Without a usable raw remainder the joined tokens are all there is:
	Argument = ParseTextArgument(nil, "{\"text\":\"Hi\"}")
	Check((Argument ~= nil) and (Argument.Kind == "json"), "the token form can still be JSON")
	Argument = ParseTextArgument(nil, nil)
	Check(Argument == nil, "no text at all is refused")
end






local function TestTellraw()
	-- The message comes from the raw line, so its quotes survive:
	local Parse = ParseTellrawLine(
		{ "/tellraw", "@a", "{\"text\":\"Hi there\",\"color\":\"red\"}" },
		"/tellraw @a {\"text\":\"Hi there\",\"color\":\"red\"}"
	)
	Check(Parse ~= nil, "a full /tellraw line parses")
	if (Parse ~= nil) then
		CheckEquals(Parse.Targets, "@a", "the target is kept")
		CheckEquals(Parse.Json, "{\"text\":\"Hi there\",\"color\":\"red\"}", "the component is kept verbatim")
	end

	Parse = ParseTellrawLine({ "tellraw", "player1", "[\"a\",\"b\"]" }, "tellraw player1 [\"a\",\"b\"]")
	Check((Parse ~= nil) and (Parse.Targets == "player1"), "the console spelling (no leading slash) parses too")

	-- Refusals: a missing message, JSON that does not parse, a non-component, a server-side component, and
	-- the sequence the chat packet would drop:
	CheckRefused(
		function () return ParseTellrawLine({ "/tellraw", "@a" }, "/tellraw @a") end,
		"No message",
		"a missing message"
	)
	CheckRefused(function () return ParseTellrawLine({ "/tellraw" }, "/tellraw") end, "Usage:", "a missing target")
	CheckRefused(
		function () return ParseTellrawLine({ "/tellraw", "@a", "{oops}" }, "/tellraw @a {oops}") end,
		"Invalid JSON",
		"malformed JSON"
	)
	CheckRefused(
		function () return ParseTellrawLine({ "/tellraw", "@a", "42" }, "/tellraw @a 42") end,
		"object or array",
		"a JSON scalar"
	)
	CheckRefused(
		function ()
			return ParseTellrawLine({ "/tellraw", "@a", "{\"selector\":\"@a\"}" }, "/tellraw @a {\"selector\":\"@a\"}")
		end,
		"selector",
		"the server-side selector component"
	)
	-- The reason describes the characters instead of quoting them, or it would be dropped as well:
	CheckRefused(
		function ()
			return ParseTellrawLine({ "/tellraw", "@a", "{\"text\":\"${x}\"}" }, "/tellraw @a {\"text\":\"${x}\"}")
		end,
		"dollar sign",
		"a message the chat packet would drop"
	)

	-- Malformed input must not raise:
	CheckNoCrash(function () return ParseTellrawLine(nil, nil) end, "a nil token list")
	CheckNoCrash(function () return ParseTellrawLine({}, "") end, "an empty token list")
	CheckNoCrash(function () return ParseTellrawLine({ "/tellraw", "", "" }, "/tellraw  ") end, "empty tokens")
end






TestParticleWhitelist()
TestSoundSources()
TestTitle()
TestParticle()
TestPlaysound()
TestTitleGarbage()
TestRawRemainder()
TestTextComponents()
TestTellraw()
TestStopsound()

print(string.format("test_presentation_commands: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
