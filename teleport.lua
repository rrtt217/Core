-- luacheck: globals ParseCommandCoords TeleportToPlayer
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess

--- Handles the in-game /tp command.
-- 1.12.2 is special among the coordinate commands: /tp resolves "~" against the position of the entity
-- being teleported, not against the command's execution position (that is /teleport, and what 1.13
-- unified). See specs/vanilla-1.12.2-command-coordinates.md section 2.1b.
function HandleTPCommand(a_Split, a_Player, _, _)

	if #a_Split == 2 or #a_Split == 3 then

		if (a_Player == nil) then
			-- No executor entity to teleport (command block / console):
			return true, "No player was found to teleport"
		end

		-- Teleport to player specified in a_Split[2], tell them unless a_Split[3] equals "-h":
		TeleportToPlayer( a_Player, a_Split[2], (a_Split[3] ~= "-h") )
		return true

	elseif #a_Split == 4 then

		if (a_Player == nil) then
			-- /tp without a target teleports the executor, and a command block has none (the exact
			-- message still needs verifying, spec section 6.3):
			return true, "No player was found to teleport"
		end

		-- Teleport to XYZ coords specified in a_Split[2, 3, 4]. The base is the teleported entity
		-- itself, which here is the executing player:
		local X, Y, Z, Reason = ParseCommandCoords(a_Split[2], a_Split[3], a_Split[4], a_Player:GetPosition())
		if (X == nil) then
			return true, Reason
		end

		a_Player:TeleportToCoords( X, Y, Z )
		SendMessageSuccess( a_Player, "You teleported to [X:" .. X .. " Y:" .. Y .. " Z:" .. Z .. "]" )
		return true

	else
		return true, "Usage: '" .. a_Split[1] .. " <player> [-h]' or '" .. a_Split[1] .. " <x> <y> <z>'"
	end

end
