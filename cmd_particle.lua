-- cmd_particle.lua
-- Implements the /particle command for Core, following vanilla Java Edition 1.12.2:
--   particle <name> <x> <y> <z> <xd> <yd> <zd> <speed> [count] [normal|force]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-presentation-commands.md
--
-- Two of the 1.12.2 arguments cannot be honoured with the C++ API this repository exports and are handled
-- explicitly instead of being ignored: <viewers> is refused by the parser (cClientHandle::SendParticleEffect
-- is not exported, so sending to everyone would show the particles to players vanilla excludes), and
-- [normal|force] is validated but has no effect (the protocol layer writes the "long distance" flag as
-- false). The response is sent whether or not anyone was in range: cWorld:BroadcastParticleEffect() reaches
-- every client that has the position's chunk loaded and reports nothing back.

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global
-- in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleParticleCommand HandleConsoleParticle
-- luacheck: globals SendMessageFailure SendMessageSuccess ParseParticleLine ParseCommandCoords GetOriginPosition
-- luacheck: globals MakeChatSafe
-- luacheck: globals Vector3f cRoot

function HandleParticleCommand(Split, Player, _, Origin)
	local Parse, Reason = ParseParticleLine(Split)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, MakeChatSafe(Reason)), 0
	end

	-- The command's world and position: the origin first (a command block or /execute supplies its own),
	-- then the issuing player, then the default world for an origin-less console call:
	local World = nil
	if (Origin ~= nil) then
		World = Origin:GetWorld()
	end
	if (World == nil) and (Player ~= nil) then
		World = Player:GetWorld()
	end
	if (World == nil) then
		World = cRoot:Get():GetDefaultWorld()
	end

	local Position = GetOriginPosition(Origin)
	if (Position == nil) and (Player ~= nil) then
		Position = Player:GetPosition()
	end

	-- The parser only checked the syntax, so that a malformed "~" is reported before anything runs; the
	-- values are resolved here, because only now is the command origin known:
	local X, Y, Z = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, Position)
	local OffsetX, OffsetY, OffsetZ = ParseCommandCoords(Parse.OffsetX, Parse.OffsetY, Parse.OffsetZ, Position)
	if (X == nil) or (OffsetX == nil) then
		return true, SendMessageFailure(Player, MakeChatSafe("The coordinates could not be resolved")), 0
	end

	World:BroadcastParticleEffect(
		Parse.Name,
		Vector3f(X, Y, Z),
		Vector3f(OffsetX, OffsetY, OffsetZ),
		Parse.Speed,
		Parse.Count
	)

	-- The success count is 1: the C++ call reports nothing back, so the number of players that can see the
	-- particles (what a 1.13+ "/execute store result" would read) is not available here (spec section 4):
	return true, SendMessageSuccess(Player, "Successfully created the particle \"" .. Parse.Name .. "\""), 1
end






function HandleConsoleParticle(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleParticleCommand(Split, nil, EntireCommand, Origin)
end
