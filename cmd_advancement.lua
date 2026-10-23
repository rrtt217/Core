-- cmd_advancement.lua
-- Implements the vanilla 1.12.2 /advancement command:
--   advancement grant|revoke <player> only|until|from|through <advancement> [criterion]
--   advancement grant|revoke <player> everything
--   advancement test <player> <advancement> [criterion]
-- The tree traversal lives in cPlayer (GrantAdvancementTree / RevokeAdvancementTree); this file
-- parses the arguments, resolves the targets and reports the feedback.
-- Behaviour and known deviations: specs/commands/vanilla-1.12.2-advancement-command.md

-- luacheck: ignore 131
-- luacheck: new globals HandleAdvancementCommand HandleConsoleAdvancement
-- luacheck: globals ResolveTargets MakeSelectorContext ApplyToTargets SendMessageSuccess SendMessageFailure

local VALID_MODES =
{
	["only"] = true,
	["until"] = true,
	["from"] = true,
	["through"] = true,
}



--- Returns the usage line for the command name in a_Split[1].
local function Usage(a_Command)
	return "Usage: " .. a_Command ..
		" grant|revoke <player> only|until|from|through <advancement> [criterion], or " ..
		a_Command .. " grant|revoke <player> everything, or " ..
		a_Command .. " test <player> <advancement> [criterion]"
end



--- Formats the advancement part of a feedback line.
local function Describe(a_ID, a_Criterion)
	if (a_ID == "") then
		return "all advancements"
	end
	if (a_Criterion ~= nil) then
		return a_ID .. " (" .. a_Criterion .. ")"
	end
	return a_ID
end



--- Sends one feedback line to the command sender, or accumulates it for the console.
local function Report(a_Player, a_IsSuccess, a_Line, a_Lines)
	if (a_Player ~= nil) then
		if a_IsSuccess then
			SendMessageSuccess(a_Player, a_Line)
		else
			SendMessageFailure(a_Player, a_Line)
		end
	else
		table.insert(a_Lines, a_Line)
	end
end



function HandleAdvancementCommand(a_Split, a_Player, _, a_Origin)
	local Command = a_Split[1] or "/advancement"
	local Sub = a_Split[2]
	if ((Sub ~= "grant") and (Sub ~= "revoke") and (Sub ~= "test")) then
		return true, SendMessageFailure(a_Player, Usage(Command)), 0
	end

	local TargetsToken = a_Split[3]
	if (TargetsToken == nil) then
		return true, SendMessageFailure(a_Player, Usage(Command)), 0
	end
	local Targets, Reason = ResolveTargets(TargetsToken, MakeSelectorContext(a_Player, a_Origin), "player")
	if (Targets == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end
	if (#Targets == 0) then
		return true, SendMessageFailure(a_Player, "No player was found"), 0
	end

	local Mode
	local ID
	local Criterion
	if (Sub == "test") then
		ID = a_Split[4]
		Criterion = a_Split[5]
		if (ID == nil) then
			return true, SendMessageFailure(a_Player, Usage(Command)), 0
		end
	else
		Mode = a_Split[4]
		if (Mode == "everything") then
			ID = ""
			Criterion = nil
		elseif (Mode ~= nil) and VALID_MODES[Mode] then
			ID = a_Split[5]
			Criterion = a_Split[6]
			if (ID == nil) then
				return true, SendMessageFailure(a_Player, Usage(Command)), 0
			end
		else
			return true, SendMessageFailure(a_Player, Usage(Command)), 0
		end
	end

	local Lines = {}
	local Successes = 0
	ApplyToTargets(Targets,
		function (a_Target)
			local Name = a_Target:GetName()
			if (Sub == "test") then
				local Has
				if (Criterion ~= nil) then
					Has = a_Target:HasAdvancementCriterion(ID, Criterion)
				else
					Has = a_Target:HasAdvancement(ID)
				end
				local Desc = Describe(ID, Criterion)
				if Has then
					Successes = Successes + 1
					Report(a_Player, true, Name .. " has " .. Desc, Lines)
				else
					Report(a_Player, false, Name .. " does not have " .. Desc, Lines)
				end
				return
			end

			if ((Mode ~= "everything") and not a_Target:IsValidAdvancement(ID)) then
				Report(a_Player, false, "Unknown advancement " .. ID, Lines)
				return
			end

			local Changed
			if (Sub == "grant") then
				Changed = a_Target:GrantAdvancementTree(ID, Mode, Criterion or "")
			else
				Changed = a_Target:RevokeAdvancementTree(ID, Mode, Criterion or "")
			end
			if ((Changed == nil) or (Changed < 0)) then
				Report(a_Player, false, "Unknown advancement " .. ID, Lines)
				return
			end
			if (Changed == 0) then
				Report(a_Player, false, "No change for " .. Name, Lines)
				return
			end

			Successes = Successes + 1
			local Verb = (Sub == "grant") and "Granted " or "Revoked "
			local Preposition = (Sub == "grant") and " to " or " from "
			Report(a_Player, true, Verb .. Describe(ID, Criterion) .. Preposition .. Name, Lines)
		end
	)

	if (a_Player ~= nil) then
		return true, nil, Successes
	end
	return true, table.concat(Lines, "; "), Successes
end



function HandleConsoleAdvancement(a_Split, _, _, a_Origin)
	return HandleAdvancementCommand(a_Split, nil, nil, a_Origin)
end
