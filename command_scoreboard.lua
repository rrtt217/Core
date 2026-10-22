-- command_scoreboard.lua
-- Implements the pure parts of Core's /scoreboard teams subcommands, following vanilla Minecraft Java
-- Edition 1.12.2 semantics (the pre-1.13 /scoreboard command).
--
-- Clean-room source (see specs/commands/vanilla-1.12.2-scoreboard-teams.md in the parent repository):
--   * Minecraft Wiki "Scoreboard", 2017-10-06 revision (rev 1156283) -- the Teams section and the
--     Teams commands table: https://minecraft.wiki/w/Scoreboard?oldid=1156283
--
-- Nothing in this file touches a game object, so tests/test_scoreboard_teams.lua exercises it with a
-- stock Lua interpreter; the handler in cmd_scoreboard.lua does the engine-side work.

-- luacheck: ignore 131
-- luacheck: globals SCOREBOARD_NAME_MAX_LENGTH SCOREBOARD_DISPLAY_NAME_MAX_LENGTH
-- luacheck: globals SCOREBOARD_TEAM_OPTIONS SCOREBOARD_TEAM_OPTIONS_UNSUPPORTED
-- luacheck: globals ValidateScoreboardName ValidateScoreboardDisplayName
-- luacheck: globals JoinScoreboardDisplayName ParseScoreboardTeamBool ParseScoreboardTeamOption
-- luacheck: globals GetScoreboardTeamTargets ScoreboardTeamOptionNames

-- 1.12.2 caps team and objective names at 16 characters and display names at 32 (Scoreboard, Teams
-- commands table).
SCOREBOARD_NAME_MAX_LENGTH = 16
SCOREBOARD_DISPLAY_NAME_MAX_LENGTH = 32

-- The team option keys this server can store and send to the clients in the Teams packet.
-- deathMessageVisibility is recognised but refused: it has no field in the packet and its chat filter is
-- not implemented yet (spec section 6-4).
SCOREBOARD_TEAM_OPTIONS =
{
	color = true,
	collisionRule = true,
	friendlyfire = true,
	nametagVisibility = true,
	seeFriendlyInvisibles = true,
}

SCOREBOARD_TEAM_OPTIONS_UNSUPPORTED =
{
	deathMessageVisibility = true,
}

-- The value sets of the 1.12.2 team options (Minecraft Wiki "Scoreboard", Teams commands table).
local TEAM_COLORS =
{
	aqua = true, black = true, blue = true, dark_aqua = true,
	dark_blue = true, dark_gray = true, dark_green = true, dark_purple = true,
	dark_red = true, gold = true, gray = true, green = true,
	light_purple = true, red = true, white = true, yellow = true,
}

local TEAM_VISIBILITY_VALUES =
{
	always = true,
	hideForOtherTeams = true,
	hideForOwnTeam = true,
	never = true,
}

local TEAM_COLLISION_RULES =
{
	always = true,
	pushOtherTeams = true,
	pushOwnTeam = true,
	never = true,
}

-- The six option keys of 1.12.2, in the order the wiki lists them. Only used by the "unknown option"
-- message, so that a typo reports the accepted set instead of a bare refusal.
local TEAM_OPTION_ORDER =
{
	"color",
	"friendlyfire",
	"seeFriendlyInvisibles",
	"nametagVisibility",
	"deathMessageVisibility",
	"collisionRule",
}





--- Returns the option keys 1.12.2 defines, comma-separated, for the "unknown option" message.
function ScoreboardTeamOptionNames()
	return table.concat(TEAM_OPTION_ORDER, ", ")
end





--- Returns nil if a_Name is usable as a scoreboard name, or the reason it is not.
-- A name is a single word (the command splitter has already guaranteed that) of at most 16 characters.
function ValidateScoreboardName(a_Name)
	if (type(a_Name) ~= "string") or (a_Name == "") then
		return "No name was given"
	end
	if (#a_Name > SCOREBOARD_NAME_MAX_LENGTH) then
		return 'The name "' .. a_Name .. '" is too long (' .. SCOREBOARD_NAME_MAX_LENGTH .. " characters at most)"
	end
	return nil
end





--- Returns nil if a_Name is usable as a display name, or the reason it is not.
-- 1.12.2 allows up to 32 characters; the display name defaults to the internal name.
function ValidateScoreboardDisplayName(a_Name)
	if (type(a_Name) ~= "string") then
		return "No display name was given"
	end
	if (#a_Name > SCOREBOARD_DISPLAY_NAME_MAX_LENGTH) then
		return 'The display name "' .. a_Name .. '" is too long (' ..
			SCOREBOARD_DISPLAY_NAME_MAX_LENGTH .. " characters at most)"
	end
	return nil
end





--- Joins the tokens from a_FirstIndex on with single spaces, the way 1.12.2's trailing "..." arguments
-- consume the rest of the command line. Returns nil when there is no such token.
function JoinScoreboardDisplayName(a_Split, a_FirstIndex)
	if (a_Split[a_FirstIndex] == nil) then
		return nil
	end
	return table.concat(a_Split, " ", a_FirstIndex)
end





--- Parses the value of the friendlyfire and seeFriendlyInvisibles options.
-- 1.12.2 documents the two values as "true" and "false"; only those spellings are accepted. Whether the
-- original parser ignored case is unverified (spec section 5), so this is deliberately exact.
function ParseScoreboardTeamBool(a_Value)
	if (a_Value == "true") then
		return true
	end
	if (a_Value == "false") then
		return false
	end
	return nil
end





--- Parses a "teams option" key/value pair.
-- Returns { Key = <key>, Value = <value> } on success, or nil plus the reason it was refused.
-- The value types follow 1.12.2: friendlyfire / seeFriendlyInvisibles are true/false, color is a color
-- name or "reset", and the two rule keys take their documented strings. The one key this server cannot
-- apply yet is recognised, so the refusal names it instead of pretending it is a typo.
function ParseScoreboardTeamOption(a_Key, a_Value)
	if (a_Key == "friendlyfire") or (a_Key == "seeFriendlyInvisibles") then
		local Value = ParseScoreboardTeamBool(a_Value)
		if (Value == nil) then
			return nil, 'The value of "' .. a_Key .. '" must be "true" or "false"'
		end
		return { Key = a_Key, Value = Value }
	end

	if (a_Key == "color") then
		if ((a_Value == "reset") or (TEAM_COLORS[a_Value])) then
			return { Key = a_Key, Value = a_Value }
		end
		return nil, 'The value of "color" must be a color name or "reset"'
	end

	if (a_Key == "nametagVisibility") then
		if (TEAM_VISIBILITY_VALUES[a_Value]) then
			return { Key = a_Key, Value = a_Value }
		end
		return nil, 'The value of "nametagVisibility" must be always, hideForOtherTeams, hideForOwnTeam or never'
	end

	if (a_Key == "collisionRule") then
		if (TEAM_COLLISION_RULES[a_Value]) then
			return { Key = a_Key, Value = a_Value }
		end
		return nil, 'The value of "collisionRule" must be always, pushOtherTeams, pushOwnTeam or never'
	end

	if (SCOREBOARD_TEAM_OPTIONS_UNSUPPORTED[a_Key]) then
		return nil, 'Team option "' .. a_Key .. '" is not supported by this server yet'
	end
	return nil, 'Unknown team option "' .. tostring(a_Key) .. '". Valid options are: ' .. ScoreboardTeamOptionNames()
end





--- Returns the target tokens of "teams join <team> ..." and "teams leave ..." (everything from
-- a_FirstIndex on). Never nil; an empty list means "the executing entity", as 1.12.2 documents.
function GetScoreboardTeamTargets(a_Split, a_FirstIndex)
	local Targets = {}
	for Index = a_FirstIndex, #a_Split do
		table.insert(Targets, a_Split[Index])
	end
	return Targets
end
