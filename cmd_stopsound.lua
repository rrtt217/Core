-- cmd_stopsound.lua
-- Implements the /stopsound command for Core, following vanilla Java Edition 1.12.2:
--   stopsound <player> [source] [sound]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-presentation-commands.md
--
-- 1.12.2 has no Stop Sound packet: the server stops sounds by sending the "MC|StopSound" plugin message to
-- the client, whose payload is the sound category and the sound event as length-prefixed strings (both
-- optional). That is verified against a ProtoProxy capture of a vanilla 1.12.2 server - see
-- BuildStopSoundPayload() and spec section 2.4 - and cClientHandle:SendPluginMessage() is exported, so this
-- command needs no C++ at all.
--
-- The success count is the number of players the message reached, the convention Core's other target-based
-- commands follow.

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global
-- in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleStopsoundCommand HandleConsoleStopsound
-- luacheck: globals SendMessageFailure SendMessageSuccess ResolveTargets ApplyToTargets GetTargetName
-- luacheck: globals MakeSelectorContext MakeChatSafe ParseStopsoundLine BuildStopSoundPayload

-- The vanilla channel name, as captured. It is a 1.12.2-era name: 1.13 replaced it with the Stop Sound
-- packet, so a 1.13+ client ignores this message (spec section 5).
local STOP_SOUND_CHANNEL = "MC|StopSound"






--- Describes what the command stopped, for the response message.
local function DescribeScope(a_Parse)
	if (a_Parse.Sound ~= nil) then
		return "the sound \"" .. a_Parse.Sound .. "\""
	elseif (a_Parse.Source ~= nil) then
		return "the sounds of \"" .. a_Parse.Source .. "\""
	end
	return "all sounds"
end






function HandleStopsoundCommand(Split, Player, _, Origin)
	local Parse, Reason = ParseStopsoundLine(Split)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, MakeChatSafe(Reason)), 0
	end

	-- 1.12.2 takes a player name or a target selector; a non-player match is not a target of this command:
	local Targets, ResolveReason = ResolveTargets(Parse.Targets, MakeSelectorContext(Player, Origin), "player")
	if (Targets == nil) then
		return true, SendMessageFailure(Player, MakeChatSafe(ResolveReason)), 0
	end

	local Payload = BuildStopSoundPayload(Parse.Source, Parse.Sound)

	local ReachedName = nil
	local Reached = ApplyToTargets(
		Targets,
		function (a_Target)
			local Client = a_Target:GetClientHandle()
			if (Client ~= nil) then
				Client:SendPluginMessage(STOP_SOUND_CHANNEL, Payload)
				ReachedName = GetTargetName(a_Target)
			end
		end
	)

	if (Reached == 0) then
		return true, SendMessageFailure(Player, MakeChatSafe("No player was reached")), 0
	end

	local Scope = DescribeScope(Parse)
	if (Reached == 1) then
		return true, SendMessageSuccess(Player, "Successfully stopped " .. Scope .. " for " .. ReachedName), Reached
	end
	return true, SendMessageSuccess(Player, "Successfully stopped " .. Scope .. " for " .. Reached .. " players"), Reached
end






function HandleConsoleStopsound(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleStopsoundCommand(Split, nil, EntireCommand, Origin)
end
