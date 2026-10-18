-- cmd_setworldspawn.lua
-- Implements the vanilla 1.12.2 /setworldspawn command.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-server-state-commands.md
--
-- /setworldspawn writes the spawn of the world the command originates from; it is not a selector command
-- and never touches another world. Core's own /setspawn (the executor's feet) is kept as it was.

-- The handlers are only referenced from Info.lua, so luacheck counts them as unused globals in this
-- file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleSetWorldspawnCommand HandleConsoleSetWorldspawn
-- luacheck: globals GetOriginPosition ParseCommandCoords SendMessageFailure SendMessageSuccess

-- 1.12.2 limits (spec section 2.2): x and z within +-30,000,000, y between 0 and 256.
local MAX_HORIZONTAL = 30000000
local MAX_SPAWN_Y = 256



--- Returns false for NaN and both infinities, which tonumber() can let through ("1e400").
local function IsFinite(a_Number)
	return (a_Number == a_Number) and (a_Number ~= math.huge) and (a_Number ~= -math.huge)
end



--- Resolves the three coordinates, either from the arguments or from the command position.
-- Returns x, y, z (and a nil reason) or nil, nil, nil plus a reason. ParseCommandCoords() reports its
-- failure as "nil, reason", so its second value is moved to the fourth here.
local function ParseSpawnPosition(a_Split, a_Position, a_Usage)
	if ((a_Split[2] == nil) or (a_Split[2] == "")) then
		if (a_Position == nil) then
			-- No coordinates and no position to default to (should not happen: the engine gives every
			-- origin a position once it has a world):
			return nil, nil, nil, a_Usage
		end
		return a_Position.x, a_Position.y, a_Position.z
	end

	if ((a_Split[5] ~= nil) and (a_Split[5] ~= "")) then
		return nil, nil, nil, a_Usage
	end
	local X, Y, Z = ParseCommandCoords(a_Split[2], a_Split[3], a_Split[4], a_Position)
	if (X == nil) then
		return nil, nil, nil, Y
	end
	return X, Y, Z
end



--- Shared body of the in-game and console forms.
-- The third return value is the command's success count (command blocks store it): 1 on success, 0 on
-- every refused path.
function HandleSetWorldspawnCommand(a_Split, a_Player, _, a_Origin)
	local Usage = "Usage: " .. a_Split[1] .. " [<x> <y> <z>]"

	local World
	if (a_Origin ~= nil) then
		World = a_Origin:GetWorld()
	end
	if ((World == nil) and (a_Player ~= nil)) then
		World = a_Player:GetWorld()
	end
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to set the spawn of"), 0
	end

	local Position = GetOriginPosition(a_Origin)
	local X, Y, Z, Reason = ParseSpawnPosition(a_Split, Position, Usage)
	if (X == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	if ((not IsFinite(X)) or (not IsFinite(Y)) or (not IsFinite(Z))) then
		return true, SendMessageFailure(a_Player, "The coordinates must be finite numbers"), 0
	end

	-- Vanilla floors the position to a block coordinate:
	X, Y, Z = math.floor(X), math.floor(Y), math.floor(Z)

	if ((math.abs(X) > MAX_HORIZONTAL) or (math.abs(Z) > MAX_HORIZONTAL)) then
		return true, SendMessageFailure(a_Player,
			"The x and z coordinates must be between -30,000,000 and 30,000,000"), 0
	end
	if ((Y < 0) or (Y > MAX_SPAWN_Y)) then
		return true, SendMessageFailure(a_Player, "The y coordinate must be between 0 and 256"), 0
	end

	if (not World:SetSpawn(X, Y, Z)) then
		return true, SendMessageFailure(a_Player, "Failed to set the world spawn point"), 0
	end
	return true, SendMessageSuccess(a_Player,
		string.format("Set the world spawn point to (%d, %d, %d)", X, Y, Z)), 1
end



function HandleConsoleSetWorldspawn(a_Split, _, _, a_Origin)
	return HandleSetWorldspawnCommand(a_Split, nil, nil, a_Origin)
end
