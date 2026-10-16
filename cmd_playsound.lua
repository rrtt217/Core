-- cmd_playsound.lua
-- Implements the /playsound command for Core, following vanilla Java Edition 1.12.2:
--   playsound <sound> <source> <player> [x] [y] [z] [volume] [pitch] [minimumVolume]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-presentation-commands.md
--
-- The <source> category is validated but cannot be transmitted: the protocol layer writes the sound category
-- as 0 (master) for every sound (src/Protocol/Protocol_1_10.cpp). The sound is sent to each target
-- individually through cClientHandle:SendSoundEffect(), which is what makes the command's <player> argument
-- meaningful, and a target outside the sound's audible sphere is either re-centred on that target at
-- <minimumVolume> or left out, exactly as the 1.12.2 page describes.
--
-- The success count is the number of players the sound reached.

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global
-- in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandlePlaysoundCommand HandleConsolePlaysound
-- luacheck: globals SendMessageFailure SendMessageSuccess ResolveTargets ApplyToTargets
-- luacheck: globals MakeSelectorContext ParsePlaysoundLine GetAudibleRadius GetOriginPosition ParseCommandCoords
-- luacheck: globals Vector3d

--- Returns the squared distance between a_Target's position and the point (a_X, a_Y, a_Z).
-- cEntity has no distance helper bound to Lua, and comparing squares avoids a square root per target.
local function GetSquaredDistanceTo(a_Target, a_X, a_Y, a_Z)
	local Position = a_Target:GetPosition()
	local DeltaX = Position.x - a_X
	local DeltaY = Position.y - a_Y
	local DeltaZ = Position.z - a_Z
	return (DeltaX * DeltaX) + (DeltaY * DeltaY) + (DeltaZ * DeltaZ)
end






function HandlePlaysoundCommand(Split, Player, _, Origin)
	local Parse, Reason = ParsePlaysoundLine(Split)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, Reason), 0
	end

	-- 1.12.2 takes a player name or a target selector, and the 1.8 note on the page is explicit that even
	-- "@e" cannot reach non-players here, so the selector layer filters down to players:
	local Targets, ResolveReason = ResolveTargets(Parse.Targets, MakeSelectorContext(Player, Origin), "player")
	if (Targets == nil) then
		return true, SendMessageFailure(Player, ResolveReason), 0
	end

	-- Omitting the coordinates means "where the command runs": resolving a missing triple as "~" against the
	-- origin is that same rule, and keeps the resolution in one place:
	local Position = GetOriginPosition(Origin)
	if (Position == nil) and (Player ~= nil) then
		Position = Player:GetPosition()
	end

	local X, Y, Z = ParseCommandCoords(Parse.X or "~", Parse.Y or "~", Parse.Z or "~", Position)
	if (X == nil) then
		return true, SendMessageFailure(Player, "The coordinates could not be resolved"), 0
	end

	-- A sound at <volume> is audible inside a sphere of volume * 16 blocks; <minimumVolume> is the volume
	-- targets outside it hear the sound at, from a position close to themselves (spec section 2.3):
	local Radius = GetAudibleRadius(Parse.Volume)
	local Reached = 0
	local ReachedName = nil

	ApplyToTargets(
		Targets,
		function (a_Target)
			local Client = a_Target:GetClientHandle()
			if (Client == nil) then
				return
			end

			local SoundX, SoundY, SoundZ, Volume = X, Y, Z, Parse.Volume
			if (GetSquaredDistanceTo(a_Target, X, Y, Z) > (Radius * Radius)) then
				if (Parse.MinimumVolume <= 0) then
					-- Nothing to hear: the sound would be silent for this target anyway, so it is not sent.
					return
				end

				local TargetPosition = a_Target:GetPosition()
				SoundX, SoundY, SoundZ = TargetPosition.x, TargetPosition.y, TargetPosition.z
				Volume = Parse.MinimumVolume
			end

			Client:SendSoundEffect(Parse.Sound, Vector3d(SoundX, SoundY, SoundZ), Volume, Parse.Pitch)
			Reached = Reached + 1
			ReachedName = a_Target:GetName()
		end
	)

	-- 1.12.2 "fails ... if the targets are unable to hear the sound from where it is played":
	if (Reached == 0) then
		return true, SendMessageFailure(Player, "No target was able to hear the sound"), 0
	end

	if (Reached == 1) then
		return true, SendMessageSuccess(
			Player,
			"Successfully played the sound \"" .. Parse.Sound .. "\" for " .. ReachedName
		), Reached
	end
	return true, SendMessageSuccess(
		Player,
		"Successfully played the sound \"" .. Parse.Sound .. "\" for " .. Reached .. " players"
	), Reached
end






function HandleConsolePlaysound(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandlePlaysoundCommand(Split, nil, EntireCommand, Origin)
end
