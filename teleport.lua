-- luacheck: globals ParseCommandCoords GetOriginPosition TeleportToPlayer
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess

--- Handles the in-game /tp command.
-- The engine calls command handlers as (Split, Player, EntireCommand, Origin); a command block has no
-- player, and its origin carries the position relative coordinates resolve against:
-- specs/vanilla-1.12.2-command-coordinates.md
function HandleTPCommand(a_Split, a_Player, _, a_Origin)

	if #a_Split == 2 or #a_Split == 3 then

		if (a_Player == nil) then
			-- No executor entity to teleport (command block / console):
			return true, "No player was found to teleport"
		end

		-- Teleport to player specified in a_Split[2], tell them unless a_Split[3] equals "-h":
		TeleportToPlayer( a_Player, a_Split[2], (a_Split[3] ~= "-h") )
		return true

	elseif #a_Split == 4 then

		-- Teleport to XYZ coords specified in a_Split[2, 3, 4]:
		local X, Y, Z, Reason = ParseCommandCoords(a_Split[2], a_Split[3], a_Split[4], GetOriginPosition(a_Origin))
		if (X == nil) then
			return true, Reason
		end

		if (a_Player == nil) then
			-- Vanilla 1.12.2 /tp without a target teleports the executor, and a command block has none
			-- (the exact message still needs verifying, spec section 6.3):
			return true, "No player was found to teleport"
		end

		a_Player:TeleportToCoords( X, Y, Z )
		SendMessageSuccess( a_Player, "You teleported to [X:" .. X .. " Y:" .. Y .. " Z:" .. Z .. "]" )
		return true

	else
		return true, "Usage: '" .. a_Split[1] .. " <player> [-h]' or '" .. a_Split[1] .. " <x> <y> <z>'"
	end

end
