-- command_presentation.lua
-- Parses the command lines of Core's presentation commands (/title, /particle, /playsound) the way vanilla
-- Java Edition 1.12.2 does.
--
-- Clean-room sources (the full argument tables and the known deviations are in
-- specs/commands/vanilla-1.12.2-presentation-commands.md in the parent repository):
--   * "Commands/title", 1.12.2-era revision (rev 1218226, 2018-06-01):
--     https://minecraft.wiki/w/Commands/title?oldid=1218226
--   * "Commands/particle", 1.12.2-era revision (rev 1186198, 2018-03-04):
--     https://minecraft.wiki/w/Commands/particle?oldid=1186198
--   * "Commands/playsound", 1.12.2-era revision (rev 1218113, 2018-06-01):
--     https://minecraft.wiki/w/Commands/playsound?oldid=1218113
-- The particle-name whitelist below mirrors cProtocol_1_8_0::GetProtocolParticleID()
-- (src/Protocol/Protocol_1_8.cpp), whose unknown-name path logs a warning, fires an ASSERT (a crash in
-- assert-enabled builds) and silently falls back to particle 0 - so the command layer must refuse unknown
-- names before calling into C++ rather than let them through.
--
-- Everything here is a pure function of its inputs: the parsers only look at the engine's token list, so they
-- can be exercised with a stock Lua interpreter (tests/test_presentation_commands.lua). Resolving a "~"
-- coordinate against the command origin and touching game objects is the callers' job.

-- luacheck: new globals ParseTitleLine ParseParticleLine ParsePlaysoundLine ParseTellrawLine ParseStopsoundLine
-- luacheck: new globals IsKnownParticleName IsKnownSoundSource GetAudibleRadius BuildStopSoundPayload
-- luacheck: globals ParseCommandCoord CutRawRemainder CheckTextComponent CheckChatDeliverable

-- The 49 particle names 1.12.2 accepts, in the 1.12.2 spelling (camelCase names such as "mobSpell" are the
-- ones the command used before 1.13 renamed them). The C++ lookup lowercases its input, so this list is
-- matched case-insensitively as well.
local PARTICLE_NAMES =
{
	"explode",
	"largeexplode",
	"hugeexplosion",
	"fireworksspark",
	"bubble",
	"splash",
	"wake",
	"suspended",
	"depthsuspend",
	"crit",
	"magiccrit",
	"smoke",
	"largesmoke",
	"spell",
	"instantspell",
	"mobspell",
	"mobspellambient",
	"witchmagic",
	"dripwater",
	"driplava",
	"angryvillager",
	"happyvillager",
	"townaura",
	"note",
	"portal",
	"enchantmenttable",
	"flame",
	"lava",
	"footstep",
	"cloud",
	"reddust",
	"snowballpoof",
	"snowshovel",
	"slime",
	"heart",
	"barrier",
	"iconcrack",
	"blockcrack",
	"blockdust",
	"droplet",
	"take",
	"mobappearance",
	"dragonbreath",
	"endrod",
	"damageindicator",
	"sweepattack",
	"fallingdust",
	"totem",
	"spit",
}

-- The <source> categories of /playsound and /stopsound. 1.12.2 has exactly these ten; "ui" was added in
-- 1.21.6 and the values double as the wire enum (master = 0 ... voice = 9).
local SOUND_SOURCES =
{
	"master",
	"music",
	"record",
	"weather",
	"block",
	"hostile",
	"neutral",
	"player",
	"ambient",
	"voice",
}

-- The two display modes of /particle. The mode cannot be transmitted (the protocol layer writes the
-- "long distance" flag as false), so it is only validated here - see the spec's deviations.
local PARTICLE_MODES =
{
	normal = true,
	force = true,
}

-- The int32 range the 1.12.2 integer arguments are bounded by.
local INT32_MIN = -2147483648
local INT32_MAX = 2147483647

-- The audible radius of a sound at volume 1.0, in blocks; the radius scales linearly with the volume.
-- /playsound's <minimumVolume> is defined against this sphere.
local AUDIBLE_RADIUS_PER_VOLUME = 16

local PARTICLE_NAME_SET = {}
for _, Name in ipairs(PARTICLE_NAMES) do
	PARTICLE_NAME_SET[Name] = true
end

local SOUND_SOURCE_SET = {}
for _, Name in ipairs(SOUND_SOURCES) do
	SOUND_SOURCE_SET[Name] = true
end






--- Returns whether a_ParticleName is one of the names 1.12.2's /particle accepts.
-- The C++ particle map lowercases before looking up, so this comparison is case-insensitive too.
function IsKnownParticleName(a_ParticleName)
	if (type(a_ParticleName) ~= "string") then
		return false
	end
	return PARTICLE_NAME_SET[a_ParticleName:lower()] == true
end






--- Returns whether a_Source is one of the ten sound categories 1.12.2 knows.
function IsKnownSoundSource(a_Source)
	if (type(a_Source) ~= "string") then
		return false
	end
	return SOUND_SOURCE_SET[a_Source] == true
end






--- Returns whether a_Sound is shaped like a 1.12.2 sound event name: either "path" or "namespace:path",
-- where the parts are made of letters, digits, dots, dashes and underscores (for example "mob.pig.say").
-- The registry lookup vanilla does on top of this needs a sound registry, which this repository does not
-- have (spec section 5, item 6).
local function IsSoundName(a_Sound)
	if (type(a_Sound) ~= "string") then
		return false
	end
	if (a_Sound:match("^[%w_%.%-]+$") ~= nil) then
		return true
	end
	return a_Sound:match("^[%w_%.%-]+:[%w_%.%-]+$") ~= nil
end






--- Returns the audible radius of a sound played at a_Volume, in blocks.
function GetAudibleRadius(a_Volume)
	return a_Volume * AUDIBLE_RADIUS_PER_VOLUME
end






--- Returns a command's arguments: the engine's token list without the command name and without the empty
-- tokens that runs of spaces produce. A quoted empty argument therefore looks like an omitted one; none of
-- these commands has an argument for which that difference matters (spec section 2.1).
local function Arguments(a_Split)
	local Result = {}
	if (type(a_Split) ~= "table") then
		return Result
	end
	for Index = 2, #a_Split do
		local Token = a_Split[Index]
		if ((Token ~= nil) and (Token ~= "")) then
			table.insert(Result, Token)
		end
	end
	return Result
end






--- Returns the command name the usage message should mention ("/title" for players, "title" in the console).
local function CommandName(a_Split, a_Default)
	if (type(a_Split) == "table") and (a_Split[1] ~= nil) and (a_Split[1] ~= "") then
		return a_Split[1]
	end
	return a_Default
end






--- Parses a 1.12.2 integer argument, bounded to the int32 range.
-- Returns the number, or nil plus a reason.
local function ParseIntegerArgument(a_Token, a_Description)
	if ((a_Token == nil) or (a_Token == "")) then
		return nil, "No " .. a_Description .. " was given"
	end
	if (a_Token:match("^[%+%-]?%d+$") == nil) then
		return nil, "Invalid " .. a_Description .. " \"" .. a_Token .. "\""
	end

	local Number = tonumber(a_Token)
	if (Number == nil) or (Number < INT32_MIN) or (Number > INT32_MAX) then
		return nil, "The " .. a_Description .. " must be between " .. INT32_MIN .. " and " .. INT32_MAX
	end
	return Number
end






--- Parses a 1.12.2 float argument, optionally range-checked.
-- Returns the number, or nil plus a reason.
local function ParseFloatArgument(a_Token, a_Description, a_Minimum, a_Maximum)
	if ((a_Token == nil) or (a_Token == "")) then
		return nil, "No " .. a_Description .. " was given"
	end

	local Number = tonumber(a_Token)
	if (Number == nil) then
		return nil, "Invalid " .. a_Description .. " \"" .. a_Token .. "\""
	end
	if (a_Minimum ~= nil) and (Number < a_Minimum) then
		return nil, "The " .. a_Description .. " must be at least " .. a_Minimum
	end
	if (a_Maximum ~= nil) and (Number > a_Maximum) then
		return nil, "The " .. a_Description .. " must be at most " .. a_Maximum
	end
	return Number
end






--- Checks that a coordinate token is a 1.12.2 coordinate: an absolute number or "~" with an optional offset.
-- The value itself is resolved by the caller against the command origin (ParseCommandCoords); a_Origin is
-- deliberately not consulted here, so that the syntax check is independent of where the command runs.
-- Returns the token's literal value, or nil plus a reason.
local function CheckCoordinate(a_Token, a_Axis, a_Description)
	local Number, Reason = ParseCommandCoord(a_Token, a_Axis, nil)
	if (Number == nil) then
		return nil, "Invalid " .. a_Description .. " \"" .. tostring(a_Token) .. "\" (" .. tostring(Reason) .. ")"
	end
	return Number
end






--- Returns the raw remainder of the command line that starts at the a_ArgumentIndex-th argument.
-- The engine drops the quotes it splits on, so a JSON text component can only be recovered from the raw
-- command line (see command_text.lua). This returns nil whenever the raw line and the token list do not line
-- up exactly - a run of spaces produces empty tokens that Arguments() drops, which shifts the indices - and
-- the caller then falls back to the tokens it has.
local function GetRawRemainder(a_Split, a_RawCommand, a_Args, a_ArgumentIndex)
	if (a_RawCommand == nil) or (type(a_Split) ~= "table") then
		return nil
	end
	if (#a_Args ~= (#a_Split - 1)) then
		return nil
	end
	-- Arguments are the engine's tokens without the command name, so the token before argument i is token i;
	-- cutting after it leaves exactly the arguments from i onwards:
	return CutRawRemainder(a_Split, a_RawCommand, a_ArgumentIndex)
end






--- Parses a /title command line.
-- a_RawCommand is the command as it was typed; it is only used to recover a JSON text component, which the
-- engine's token splitter would otherwise have stripped of its quotes.
-- Returns one of
--   { Mode = "title"|"subtitle"|"actionbar", Targets = <token>, Text = <text>, RawText = <text>|nil }
--   { Mode = "times", Targets = <token>, FadeIn = <int>, Stay = <int>, FadeOut = <int> }
--   { Mode = "clear"|"reset", Targets = <token> }
-- or nil plus a reason.
function ParseTitleLine(a_Split, a_RawCommand)
	local Args = Arguments(a_Split)
	local Usage = "Usage: " .. CommandName(a_Split, "title")
		.. " <player> title|subtitle|actionbar <text> OR <player> times <fadeIn> <stay> <fadeOut>"
		.. " OR <player> clear|reset"

	if (#Args < 2) then
		return nil, Usage
	end

	local Targets = Args[1]
	local Mode = Args[2]

	if ((Mode == "title") or (Mode == "subtitle") or (Mode == "actionbar")) then
		-- The text is everything that is left: vanilla takes a raw JSON text component here and consumes the
		-- rest of the line. Both forms are returned - the tokens joined back with single spaces (the plain
		-- text this fork accepts, rendered with "&" colour codes) and the raw remainder (which still has the
		-- quotes a JSON component needs) - and the caller picks one (spec section 2.5).
		if (#Args < 3) then
			return nil, "No text was given"
		end
		return
		{
			Mode = Mode,
			Targets = Targets,
			Text = table.concat(Args, " ", 3),
			RawText = GetRawRemainder(a_Split, a_RawCommand, Args, 3),
		}
	end

	if (Mode == "times") then
		if (#Args < 5) then
			return nil, Usage
		end
		if (#Args > 5) then
			return nil, "Unexpected argument \"" .. Args[6] .. "\""
		end

		local Names = { "fade in", "stay", "fade out" }
		local Times = {}
		for Index = 1, 3 do
			local Number, Reason = ParseIntegerArgument(Args[Index + 2], Names[Index])
			if (Number == nil) then
				return nil, Reason
			end
			-- "values below 0 will be treated as 0" (spec section 2.1):
			Times[Index] = math.max(Number, 0)
		end
		return
		{
			Mode = Mode,
			Targets = Targets,
			FadeIn = Times[1],
			Stay = Times[2],
			FadeOut = Times[3],
		}
	end

	if ((Mode == "clear") or (Mode == "reset")) then
		if (#Args > 2) then
			return nil, "Unexpected argument \"" .. Args[3] .. "\""
		end
		return { Mode = Mode, Targets = Targets }
	end

	return nil, "Unknown title action \"" .. Mode .. "\""
end






--- Parses a /particle command line.
-- Returns
--   {
--     Name = <particle name>,
--     X = <token>, Y = <token>, Z = <token>,                      -- position, may be "~"-relative
--     OffsetX = <token>, OffsetY = <token>, OffsetZ = <token>,    -- spread, may be "~"-relative
--     Speed = <number>, Count = <int>, Mode = "normal"|"force"|nil,
--   }
-- or nil plus a reason. The coordinates stay tokens because only the caller knows the command origin.
function ParseParticleLine(a_Split)
	local Args = Arguments(a_Split)
	local Usage = "Usage: " .. CommandName(a_Split, "particle")
		.. " <name> <x> <y> <z> <xd> <yd> <zd> <speed> [count] [normal|force]"

	-- <name> <x> <y> <z> <xd> <yd> <zd> <speed>:
	if (#Args < 8) then
		return nil, Usage
	end

	local Name = Args[1]
	if (not IsKnownParticleName(Name)) then
		return nil, "Unknown particle \"" .. Name .. "\""
	end

	local Axes = { "x", "y", "z" }
	for Index = 1, 3 do
		local _, Reason = CheckCoordinate(Args[Index + 1], Axes[Index], Axes[Index] .. " coordinate")
		if (Reason ~= nil) then
			return nil, Reason
		end
		local _, OffsetReason = CheckCoordinate(Args[Index + 4], Axes[Index], Axes[Index] .. " spread")
		if (OffsetReason ~= nil) then
			return nil, OffsetReason
		end
	end

	local Speed, SpeedReason = ParseFloatArgument(Args[8], "speed", 0)
	if (Speed == nil) then
		return nil, SpeedReason
	end

	-- "[count] ... Must be at least 0 (which produces one particle)"; an omitted count behaves like 0, which
	-- is the single-particle form (spec section 2.2):
	local Count = 0
	if (Args[9] ~= nil) then
		local CountReason
		Count, CountReason = ParseIntegerArgument(Args[9], "count")
		if (Count == nil) then
			return nil, CountReason
		end
		if (Count < 0) then
			return nil, "The count must be at least 0"
		end
	end

	local Mode = nil
	if (Args[10] ~= nil) then
		if (not PARTICLE_MODES[Args[10]]) then
			return nil, "Invalid display mode \"" .. Args[10] .. "\""
		end
		Mode = Args[10]
	end

	-- [params ...] carries the block or item of the blockdust / blockcrack / fallingdust / iconcrack
	-- particles; reading it needs the numeric id + data encoding 1.12.2 uses, which is not implemented
	-- (spec section 3). It comes last, so it is checked before <viewers>, which precedes it:
	if (Args[12] ~= nil) then
		return nil, "Particle parameters are not supported yet"
	end

	-- <viewers> would need a per-player particle send, which cClientHandle does not export: broadcasting to
	-- everyone instead would show the particles to players vanilla excludes, so the argument is refused
	-- rather than ignored (spec section 5, item 3):
	if (Args[11] ~= nil) then
		return nil, "Selecting the viewers of a particle is not supported yet"
	end

	return
	{
		Name = Name,
		X = Args[2],
		Y = Args[3],
		Z = Args[4],
		OffsetX = Args[5],
		OffsetY = Args[6],
		OffsetZ = Args[7],
		Speed = Speed,
		Count = Count,
		Mode = Mode,
	}
end






--- Parses a /playsound command line.
-- Returns
--   {
--     Sound = <sound event>, Source = <category>, Targets = <token>,
--     X = <token>|nil, Y = <token>|nil, Z = <token>|nil,   -- nil means "the execution position"
--     Volume = <number>, Pitch = <number>, MinimumVolume = <number>,
--   }
-- or nil plus a reason.
function ParsePlaysoundLine(a_Split)
	local Args = Arguments(a_Split)
	local Usage = "Usage: " .. CommandName(a_Split, "playsound")
		.. " <sound> <source> <player> [x] [y] [z] [volume] [pitch] [minimumVolume]"

	-- <sound> <source> <player> are all required in 1.12.2 (the <source> argument was made mandatory in
	-- 16w02a; it only became optional again in 24w09a, long after 1.12.2 - spec section 2.3):
	if (#Args < 3) then
		return nil, Usage
	end

	local Sound = Args[1]
	-- 1.12.2 resolves the name against the sound registry, which this repository does not have, so only the
	-- shape of a resource location is checked here; an unknown event is sent and ignored by the client
	-- (spec section 5, item 6):
	if (not IsSoundName(Sound)) then
		return nil, "Invalid sound \"" .. Sound .. "\""
	end

	local Source = Args[2]
	if (not IsKnownSoundSource(Source)) then
		return nil, "Unknown sound source \"" .. Source .. "\""
	end

	local Targets = Args[3]

	-- The nine optional arguments are consumed in the order 1.12.2 declares them, so coordinates have to be
	-- given as a triple before any of the three floats is reached:
	local X, Y, Z = nil, nil, nil
	if (Args[4] ~= nil) then
		if (#Args < 6) then
			return nil, Usage
		end

		local Axes = { "x", "y", "z" }
		for Index = 1, 3 do
			local _, Reason = CheckCoordinate(Args[Index + 3], Axes[Index], Axes[Index] .. " coordinate")
			if (Reason ~= nil) then
				return nil, Reason
			end
		end
		X, Y, Z = Args[4], Args[5], Args[6]
	end

	local Volume, Pitch, MinimumVolume = 1.0, 1.0, 0.0
	local Reason
	if (Args[7] ~= nil) then
		Volume, Reason = ParseFloatArgument(Args[7], "volume", 0)
		if (Volume == nil) then
			return nil, Reason
		end
	end
	if (Args[8] ~= nil) then
		Pitch, Reason = ParseFloatArgument(Args[8], "pitch", 0, 2)
		if (Pitch == nil) then
			return nil, Reason
		end
	end
	if (Args[9] ~= nil) then
		MinimumVolume, Reason = ParseFloatArgument(Args[9], "minimum volume", 0, 1)
		if (MinimumVolume == nil) then
			return nil, Reason
		end
	end
	if (Args[10] ~= nil) then
		return nil, "Unexpected argument \"" .. Args[10] .. "\""
	end

	return
	{
		Sound = Sound,
		Source = Source,
		Targets = Targets,
		X = X,
		Y = Y,
		Z = Z,
		Volume = Volume,
		Pitch = Pitch,
		MinimumVolume = MinimumVolume,
	}
end






--- Parses a /tellraw command line: tellraw <player> <raw json message>
-- The message has to come from the raw command line: the engine's tokens have their quotes removed, so
-- reassembling them would turn {"text":"Hi there"} into {text:Hi there}.
-- Returns { Targets = <token>, Json = <json text> } or nil plus a reason.
-- This is the one parser in this file that calls into the engine (cJson:Parse, through CheckTextComponent),
-- because a /tellraw argument is only meaningful once it is known to be a component the client can render.
function ParseTellrawLine(a_Split, a_RawCommand)
	local Args = Arguments(a_Split)
	local Usage = "Usage: " .. CommandName(a_Split, "tellraw") .. " <player> <raw json message>"

	if (#Args < 1) then
		return nil, Usage
	end
	if (#Args < 2) then
		return nil, "No message was given"
	end

	local Json = GetRawRemainder(a_Split, a_RawCommand, Args, 2) or table.concat(Args, " ", 2)

	local Reason = CheckTextComponent(Json)
	if (Reason ~= nil) then
		return nil, Reason
	end

	-- /tellraw always goes through the chat packet, which drops a message containing "${":
	local Deliverable = CheckChatDeliverable(Json)
	if (Deliverable ~= nil) then
		return nil, Deliverable
	end

	return { Targets = Args[1], Json = Json }
end






--- Returns a_Value encoded the way the protocol writes a VarInt (7 bits per byte, high bit = "more").
local function EncodeVarInt(a_Value)
	local Bytes = {}
	local Remaining = a_Value
	repeat
		local Byte = Remaining % 128
		Remaining = math.floor(Remaining / 128)
		if (Remaining > 0) then
			Byte = Byte + 128
		end
		Bytes[#Bytes + 1] = string.char(Byte)
	until (Remaining <= 0)
	return table.concat(Bytes)
end






--- Builds the payload of the "MC|StopSound" plugin message, which is how 1.12.2 implements /stopsound.
-- The client parses it as zero, one or two length-prefixed strings, in this order: the sound category, then
-- the sound event. An omitted string means "every..." for that part, so an empty payload stops everything.
-- The two-string form is verified byte-for-byte against a ProtoProxy capture of a vanilla 1.12.2 server
-- (`/stopsound Harry00025 weather minecraft:weather.rain` produced 07 "weather" 16 "minecraft:weather.rain");
-- the zero- and one-string forms follow from the client's parsing and from the 1.13 Stop Sound packet, whose
-- flags cover the same three cases - see the spec's deviations.
function BuildStopSoundPayload(a_Source, a_Sound)
	local Payload = ""
	if (a_Source ~= nil) then
		Payload = Payload .. EncodeVarInt(#a_Source) .. a_Source
	end
	if (a_Sound ~= nil) then
		Payload = Payload .. EncodeVarInt(#a_Sound) .. a_Sound
	end
	return Payload
end






--- Parses a /stopsound command line: stopsound <player> [source] [sound]
-- Returns { Targets = <token>, Source = <category>|nil, Sound = <sound event>|nil } or nil plus a reason.
-- The sound name is passed through exactly as typed: the capture that pinned this command down shows a
-- namespaced name reaching the client unchanged, and nothing in the allowed sources says a bare name is
-- expanded to "minecraft:..." first (spec section 2.4).
function ParseStopsoundLine(a_Split)
	local Args = Arguments(a_Split)
	local Usage = "Usage: " .. CommandName(a_Split, "stopsound") .. " <player> [source] [sound]"

	if (#Args < 1) then
		return nil, Usage
	end
	if (#Args > 3) then
		return nil, "Unexpected argument \"" .. Args[4] .. "\""
	end

	local Source = nil
	if (Args[2] ~= nil) then
		if (not IsKnownSoundSource(Args[2])) then
			return nil, "Unknown sound source \"" .. Args[2] .. "\""
		end
		Source = Args[2]
	end

	local Sound = nil
	if (Args[3] ~= nil) then
		if (not IsSoundName(Args[3])) then
			return nil, "Invalid sound \"" .. Args[3] .. "\""
		end
		Sound = Args[3]
	end

	return { Targets = Args[1], Source = Source, Sound = Sound }
end
