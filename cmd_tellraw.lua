-- cmd_tellraw.lua
-- Implements the /tellraw command for Core, following vanilla Java Edition 1.12.2:
--   tellraw <player> <raw json message>
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-presentation-commands.md
--
-- 1.12.2 takes a raw JSON text component ("Must be valid raw JSON text"), so the argument is checked with
-- cJson before anything is sent, and only components a 1.12.2 client can render on its own are accepted
-- (see command_text.lua for the server-side "selector" / "score" components).
--
-- The success count is the number of players the message reached, the convention Core's other target-based
-- commands follow.

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global
-- in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleTellrawCommand HandleConsoleTellraw
-- luacheck: globals SendMessageFailure SendMessageSuccess ResolveTargets ApplyToTargets
-- luacheck: globals MakeSelectorContext MakeChatSafe ParseTellrawLine

function HandleTellrawCommand(Split, Player, EntireCommand, Origin)
	local Parse, Reason = ParseTellrawLine(Split, EntireCommand)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, MakeChatSafe(Reason)), 0
	end

	-- 1.12.2 takes a player name or a target selector; a non-player match is not a target of this command:
	local Targets, ResolveReason = ResolveTargets(Parse.Targets, MakeSelectorContext(Player, Origin), "player")
	if (Targets == nil) then
		return true, SendMessageFailure(Player, MakeChatSafe(ResolveReason)), 0
	end

	local ReachedName = nil
	local Reached = ApplyToTargets(
		Targets,
		function (a_Target)
			-- SendMessageRaw() writes the JSON component into the chat packet verbatim, without going through
			-- cCompositeChat, which is what makes an arbitrary component survive:
			a_Target:SendMessageRaw(Parse.Json)
			ReachedName = a_Target:GetName()
		end
	)

	if (Reached == 0) then
		return true, SendMessageFailure(Player, MakeChatSafe("No player was reached")), 0
	end

	if (Reached == 1) then
		return true, SendMessageSuccess(Player, "Successfully sent the message to " .. ReachedName), Reached
	end
	return true, SendMessageSuccess(Player, "Successfully sent the message to " .. Reached .. " players"), Reached
end






function HandleConsoleTellraw(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleTellrawCommand(Split, nil, EntireCommand, Origin)
end
