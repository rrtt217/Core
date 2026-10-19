-- luacheck: globals ResolveTargets ApplyToTargets MakeSelectorContext SendMessageFailure
-- luacheck: globals ParseCommandCoords GetOriginPosition GetSpawnPositionRangeReason

local MAX_SPAWN_HORIZONTAL = 30000000
local MAX_SPAWN_Y = 256



--- Validates the 1.12.2 <x> <y> <z> range of /spawnpoint (spec section 2).
-- The 1.12.2 page states: x and z must be integers within -30,000,000 to 30,000,000 (inclusive),
-- y an integer between 0 and 256 (inclusive). Returns nil when the position is acceptable.
function GetSpawnPositionRangeReason(a_X, a_Y, a_Z)
	if ((math.abs(a_X) > MAX_SPAWN_HORIZONTAL) or (math.abs(a_Z) > MAX_SPAWN_HORIZONTAL)) then
		return "The x and z coordinates must be between -30,000,000 and 30,000,000"
	end
	if ((a_Y < 0) or (a_Y > MAX_SPAWN_Y)) then
		return "The y coordinate must be between 0 and 256"
	end
	return nil
end



function HandleSpawnPointCommand(Split, Player, _, Origin)
	local Response
	local SuccessCount = 0
	
	local X
	local Y
	local Z
	local World = cRoot:Get():GetDefaultWorld()

	-- Relative coordinates resolve against the command's execution position (the origin), not against
	-- the target player (specs/commands/vanilla-1.12.2-command-coordinates.md):
	local BasePosition = GetOriginPosition(Origin)

	if Player then
		X = Player:GetPosX()
		Y = Player:GetPosY()
		Z = Player:GetPosZ()
		World = Player:GetWorld()
	end
	if (BasePosition == nil) and (Player ~= nil) then
		BasePosition = Player:GetPosition()
	end
	if (Origin ~= nil) and (Origin:GetWorld() ~= nil) then
		World = Origin:GetWorld()
	end

	local SetSpawnPoint = function(OtherPlayer, a_Deferred)
		-- A queued action runs one tick later on another world's thread, so it must not touch the
		-- executor's userdata; it behaves like a console run for the feedback line (spec section 7.3):
		local ActingPlayer = Player
		if (a_Deferred) then
			ActingPlayer = nil
		end

		if Split[5] then
			-- ParseCommandCoords() returns X, Y, Z on success and nil, reason on failure, so the
			-- reason arrives in the second value (a four-variable assignment used to read it from the
			-- fourth one, which was always nil and produced an empty failure message):
			local ParsedX, ParsedY, ParsedZ = ParseCommandCoords(Split[3], Split[4], Split[5], BasePosition)
			if (ParsedX == nil) then
				Response = SendMessageFailure(ActingPlayer, ParsedY)
				return
			end

			local RangeReason = GetSpawnPositionRangeReason(ParsedX, ParsedY, ParsedZ)
			if (RangeReason ~= nil) then
				Response = SendMessageFailure(ActingPlayer, RangeReason)
				return
			end

			X, Y, Z = ParsedX, ParsedY, ParsedZ
		end
		
		if Split[6] then
			World = cRoot:Get():GetWorld(Split[6])

			if not World then
				Response = SendMessageFailure(ActingPlayer, "Invalid world \"" .. Split[6] .. "\"")
			end
		end

		if not Response then
			OtherPlayer:SetRespawnPosition(Vector3i(X, Y, Z), World)

			Response = SendMessageSuccess(ActingPlayer,
				"Set the spawn point of player \"" .. OtherPlayer:GetName() .. "\" to (" ..
				math.floor(X) .. ", " .. math.floor(Y) .. ", " .. math.floor(Z) ..
				") in world \"" .. World:GetName() .. "\""
			)
		end
	end

	if (not Player and not Split[5]) or (Split[3] and not Split[5]) then
		Response = SendMessage(Player, "Usage: " .. Split[1] .. " <targets> <x> <y> <z> [world]")
	elseif not Split[2] then
		SetSpawnPoint(Player)
		SuccessCount = 1
	elseif Split[2]:sub(1, 1) == "@" then
		-- 1.12.2 /spawnpoint takes "player name or target selector" (players only).
		local Targets, Reason = ResolveTargets(Split[2], MakeSelectorContext(Player, Origin), "player")
		if Targets == nil then
			Response = SendMessageFailure(Player, Reason)
		else
			SuccessCount = ApplyToTargets(Targets, SetSpawnPoint)
		end
	elseif Split[2] == "" or not cRoot:Get():FindAndDoWithPlayer(Split[2], SetSpawnPoint) then
		Response = SendMessageFailure(Player, "Player \"" .. Split[2] .. "\" not found")
	else
		SuccessCount = 1
	end
	return true, Response, SuccessCount
end

function HandleConsoleSpawnPoint(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleSpawnPointCommand(Split, nil, EntireCommand, Origin)
end
