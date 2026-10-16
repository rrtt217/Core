-- cmd_title.lua
-- Implements the /title command for Core, following vanilla Java Edition 1.12.2:
--   title <player> title|subtitle|actionbar <text>
--   title <player> times <fadeIn> <stay> <fadeOut>
--   title <player> clear|reset
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-presentation-commands.md
--
-- The text argument accepts both forms: a raw JSON text component (what 1.12.2 requires, and what the
-- command_text.lua layer validates) and, as a convenience this fork adds, a plain string where "&" is a
-- colour code. Which one is used follows from the text itself - an argument that starts with "{" or "[" is
-- JSON, anything else is plain text.
--
-- The success count is the number of players the command reached, which is the convention Core's other
-- target-based commands follow (a command block stores it as its SuccessCount).

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global
-- in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleTitleCommand HandleConsoleTitle
-- luacheck: globals SendMessageFailure SendMessageSuccess ResolveTargets ApplyToTargets GetTargetName
-- luacheck: globals MakeSelectorContext ParseTitleLine ParseTextArgument CheckChatDeliverable
-- luacheck: globals cCompositeChat ctAboveActionBar

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

-- The three modes that carry a text argument.
local TEXT_MODES =
{
	title = true,
	subtitle = true,
	actionbar = true,
}






--- Applies one parsed /title action to one player.
-- a_Text is the parsed text argument ({ Kind = "json"|"plain", ... }) for the text modes, nil otherwise.
local function ApplyTitle(a_Player, a_Parse, a_Text)
	local Client = a_Player:GetClientHandle()
	if (Client == nil) then
		return
	end

	if (a_Parse.Mode == "times") then
		-- The values are already clamped to at least 0 by the parser (1.12.2 treats a negative time as 0):
		Client:SendTitleTimes(a_Parse.FadeIn, a_Parse.Stay, a_Parse.FadeOut)
	elseif (a_Parse.Mode == "clear") then
		-- Protocol action 4: the title disappears, but its text is kept for the next SendTitleTimes() -
		-- that is what separates "clear" from "reset":
		Client:SendHideTitle()
	elseif (a_Parse.Mode == "reset") then
		-- Protocol action 5: the text is erased and the times are restored to their defaults:
		Client:SendResetTitle()
	elseif (a_Parse.Mode == "actionbar") then
		-- The action bar goes through the chat packet, so a raw component is sent with the "above action bar"
		-- chat type (the same thing the Title packet's action 2 does, per the 1.12.2 protocol notes):
		if (a_Text.Kind == "json") then
			a_Player:SendMessageRaw(a_Text.Json, ctAboveActionBar)
		else
			Client:SendAboveActionBarMessage(a_Text.Text)
		end
	elseif (a_Parse.Mode == "subtitle") then
		if (a_Text.Kind == "json") then
			Client:SendSetRawSubTitle(a_Text.Json)
		else
			-- cCompositeChat parses "&" colour codes and serialises to the JSON component that is sent:
			Client:SendSetSubTitle(cCompositeChat(a_Text.Text))
		end
	elseif (a_Text.Kind == "json") then
		Client:SendSetRawTitle(a_Text.Json)
	else
		Client:SendSetTitle(cCompositeChat(a_Text.Text))
	end
end






function HandleTitleCommand(Split, Player, EntireCommand, Origin)
	local Parse, Reason = ParseTitleLine(Split, EntireCommand)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, Reason), 0
	end

	-- The text modes carry an argument that is either a JSON component or plain text; it is resolved once,
	-- before anything runs, so that a bad component is reported without touching any player:
	local Text = nil
	if (TEXT_MODES[Parse.Mode]) then
		local Argument, TextReason = ParseTextArgument(Parse.RawText, Parse.Text)
		if (Argument == nil) then
			return true, SendMessageFailure(Player, TextReason), 0
		end

		if (Parse.Mode == "actionbar") then
			-- The action bar is sent through the chat packet, which drops a message containing "${":
			local Deliverable = CheckChatDeliverable((Argument.Kind == "json") and Argument.Json or Argument.Text)
			if (Deliverable ~= nil) then
				return true, SendMessageFailure(Player, Deliverable), 0
			end
		end
		Text = Argument
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
			ApplyTitle(a_Target, Parse, Text)
			ReachedName = GetTargetName(a_Target)
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
