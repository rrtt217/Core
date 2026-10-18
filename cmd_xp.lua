-- cmd_xp.lua
-- Implements the vanilla 1.12.2 /xp command:
--   xp <amount> [player]
--   xp <amount>L [player]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-xp-command.md
--
-- The "L" form adds or removes levels while keeping the progress inside the current level, which is
-- not a cPlayer method: the level is converted to a total experience value by command_xp.lua.

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global in
-- this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleXPCommand HandleConsoleXP
-- luacheck: globals ParseXpAmount GetTotalXpForLevelChange
-- luacheck: globals SendMessageFailure SendMessageSuccess ResolveTargets MakeSelectorContext ApplyToTargets

--- Applies the parsed amount to a_Target. Returns true when the player was updated.
local function ApplyAmount(a_Target, a_Amount)
	if (a_Amount.Levels ~= nil) then
		local NewTotal = GetTotalXpForLevelChange(a_Target:GetXpLevel(), a_Target:GetXpPercentage(),
			a_Amount.Levels)
		return a_Target:SetCurrentExperience(NewTotal)
	end
	return (a_Target:DeltaExperience(a_Amount.Points) ~= -1)
end



--- Builds the one-line feedback for a_Target.
local function MakeMessage(a_Amount, a_Name)
	if (a_Amount.Levels ~= nil) then
		local Noun = "levels"
		if (math.abs(a_Amount.Levels) == 1) then
			Noun = "level"
		end
		return string.format("Given %d %s to %s", a_Amount.Levels, Noun, a_Name)
	end
	return string.format("Given %d experience to %s", a_Amount.Points, a_Name)
end



function HandleXPCommand(a_Split, a_Player, _, a_Origin)
	local Usage = "Usage: " .. a_Split[1] .. " <amount>[L] [player]"
	local Amount, Reason = ParseXpAmount(a_Split[2])
	if (Amount == nil) then
		return true, SendMessageFailure(a_Player, Reason or Usage), 0
	end

	local Targets
	if ((a_Split[3] ~= nil) and (a_Split[3] ~= "")) then
		Targets, Reason = ResolveTargets(a_Split[3], MakeSelectorContext(a_Player, a_Origin), "player")
		if (Targets == nil) then
			return true, SendMessageFailure(a_Player, Reason), 0
		end
	else
		if (a_Player == nil) then
			-- Vanilla: the player argument is not optional in command blocks (spec section 2.1):
			return true, SendMessageFailure(a_Player, "No player was found"), 0
		end
		Targets = { a_Player }
	end

	if (#Targets == 0) then
		return true, SendMessageFailure(a_Player, "No player was found"), 0
	end

	-- Only the players the command reaches right now are reported; targets in other worlds are queued
	-- by the selector layer and run one tick later (C1 section 7), without a chat line here.
	local Names = {}
	ApplyToTargets(Targets,
		function (a_Target)
			if (ApplyAmount(a_Target, Amount)) then
				local Name = a_Target:GetName()
				table.insert(Names, Name)
				if (a_Player ~= nil) then
					SendMessageSuccess(a_Player, MakeMessage(Amount, Name))
				end
			end
		end
	)

	if (#Names == 0) then
		return true, SendMessageFailure(a_Player, "Could not update the experience of any player"), 0
	end
	if (a_Player ~= nil) then
		return true, nil, #Names
	end

	local Lines = {}
	for _, Name in ipairs(Names) do
		table.insert(Lines, MakeMessage(Amount, Name))
	end
	return true, table.concat(Lines, "; "), #Names
end



function HandleConsoleXP(a_Split, _, _, a_Origin)
	return HandleXPCommand(a_Split, nil, nil, a_Origin)
end
