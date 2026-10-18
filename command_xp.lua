-- command_xp.lua
-- Parsers and the level/total-experience maths for the vanilla 1.12.2 /xp command.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-xp-command.md
--
-- cPlayer stores only the total experience; the level is derived from it and XpForLevel() is not
-- exported, so the "add levels" form has to convert a level change back into a total here (section 2.2).

-- luacheck: globals ParseXpAmount GetXpForLevel GetTotalXpForLevelChange

local MIN_INT = -2147483648
local MAX_INT = 2147483647



--- Parses the <amount>[L] argument.
-- Returns { Points = n } or { Levels = n }, or nil plus a reason. The 1.12.2 parser takes signed
-- integers with an optional "L" suffix (section 2.1).
function ParseXpAmount(a_Token)
	if ((a_Token == nil) or (a_Token == "")) then
		return nil, "No amount was given"
	end

	local Levels = false
	local Text = a_Token
	if (Text:sub(-1) == "L") then
		Levels = true
		Text = Text:sub(1, -2)
	end

	if (Text:match("^[+-]?%d+$") == nil) then
		return nil, "Invalid amount \"" .. a_Token .. "\""
	end
	local Value = tonumber(Text)
	if ((Value < MIN_INT) or (Value > MAX_INT)) then
		return nil, "The amount must be between " .. MIN_INT .. " and " .. MAX_INT
	end

	if (Levels) then
		return { Levels = Value }
	end
	return { Points = Value }
end



--- Returns the total experience needed to reach a_Level (Experience page, 1.12.2 revision).
function GetXpForLevel(a_Level)
	if (a_Level <= 16) then
		return a_Level * a_Level + 6 * a_Level
	end
	if (a_Level <= 31) then
		return math.floor(2.5 * a_Level * a_Level - 40.5 * a_Level + 360)
	end
	return math.floor(4.5 * a_Level * a_Level - 162.5 * a_Level + 2220)
end



--- Returns the total experience after adding a_DeltaLevels, keeping the progress inside the level.
-- a_Progress is cPlayer:GetXpPercentage() (0..1). A level below 0 clamps to 0 with no progress, which
-- is the "not reduced below 0" rule of section 2.1.
function GetTotalXpForLevelChange(a_CurrentLevel, a_Progress, a_DeltaLevels)
	local TargetLevel = a_CurrentLevel + a_DeltaLevels
	if (TargetLevel < 0) then
		return 0
	end

	local Base = GetXpForLevel(TargetLevel)
	local Next = GetXpForLevel(TargetLevel + 1)
	return Base + math.floor(a_Progress * (Next - Base) + 0.5)
end
