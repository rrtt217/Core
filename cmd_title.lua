-- cmd_title.lua
-- Implements the /title command for Core, following vanilla Java Edition 1.12.2:
--   title <player> title|subtitle|actionbar <text>
--   title <player> times <fadeIn> <stay> <fadeOut>
--   title <player> clear|reset
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-presentation-commands.md
--
-- The success count is the number of players the command reached, which is the convention Core's other
-- target-based commands follow (a command block stores it as its SuccessCount).

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global
-- in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleTitleCommand HandleConsoleTitle
-- luacheck: globals SendMessageFailure SendMessageSuccess ResolveTargets ApplyToTargets GetTargetName
-- luacheck: globals MakeSelectorContext ParseTitleLine
-- luacheck: globals cCompositeChat

-- The text each mode sets, and the verb that describes it, for the response message.
local TITLE_ACTIONS =
{
	title     = { Verb = "Set",     Object = "the title" },
	subtitle  = { Verb = "Set",     Object = "the subtitle" },
	actionbar = { Verb = "Set",     Object = "the action bar text" },
	times     = { Verb = "Set",     Object = "the title times" },
	clear     = { Verb = "Cleared", Object = "the title" },
	reset     = { Verb = "Reset",   Object = "the title" },
}






--- Applies one parsed /title action to one player.
local function ApplyTitle(a_Client, a_Parse)
	if (a_Parse.Mode == "times") then
		-- The values are already clamped to at least 0 by the parser (1.12.2 treats a negative time as 0):
		a_Client:SendTitleTimes(a_Parse.FadeIn, a_Parse.Stay, a_Parse.FadeOut)
	elseif (a_Parse.Mode == "clear") then
		-- Protocol action 4: the title disappears, but its text is kept for the next SendTitleTimes() -
		-- that is what separates "clear" from "reset":
		a_Client:SendHideTitle()
	elseif (a_Parse.Mode == "reset") then
		-- Protocol action 5: the text is erased and the times are restored to their defaults:
		a_Client:SendResetTitle()
	elseif (a_Parse.Mode == "actionbar") then
		a_Client:SendAboveActionBarMessage(a_Parse.Text)
	elseif (a_Parse.Mode == "subtitle") then
		-- cCompositeChat parses "&" colour codes and serialises to the JSON component SendSetTitle sends:
		a_Client:SendSetSubTitle(cCompositeChat(a_Parse.Text))
	else
		a_Client:SendSetTitle(cCompositeChat(a_Parse.Text))
	end
end






function HandleTitleCommand(Split, Player, _, Origin)
	local Parse, Reason = ParseTitleLine(Split)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, Reason), 0
	end

	-- /title takes players only ("fails ... if player fails to evaluate to one or more online players"), so
	-- the selector layer filters "@e" down to the players it matched:
	local Targets, ResolveReason = ResolveTargets(Parse.Targets, MakeSelectorContext(Player, Origin), "player")
	if (Targets == nil) then
		return true, SendMessageFailure(Player, ResolveReason), 0
	end

	local ReachedName = nil
	local Affected = ApplyToTargets(
		Targets,
		function (a_Target)
			local Client = a_Target:GetClientHandle()
			if (Client ~= nil) then
				ApplyTitle(Client, Parse)
				ReachedName = GetTargetName(a_Target)
			end
		end
	)

	if (Affected == 0) then
		return true, SendMessageFailure(Player, "No player was reached"), 0
	end

	local Action = TITLE_ACTIONS[Parse.Mode]
	if (Affected == 1) then
		return true, SendMessageSuccess(
			Player,
			"Successfully " .. Action.Verb:lower() .. " " .. Action.Object .. " for " .. ReachedName
		), Affected
	end
	return true, SendMessageSuccess(
		Player,
		"Successfully " .. Action.Verb:lower() .. " " .. Action.Object .. " for " .. Affected .. " players"
	), Affected
end






function HandleConsoleTitle(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleTitleCommand(Split, nil, EntireCommand, Origin)
end
