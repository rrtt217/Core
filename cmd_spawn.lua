-- luacheck: new globals HandleSpawnCommand HandleConsoleSpawn
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess ResolveTargets GetTargetName
-- luacheck: globals ApplyToTargets MakeSelectorContext

function HandleSpawnCommand(Split, Player)
	local Response

	local MoveToSpawn = function(OtherPlayer)
		local World = OtherPlayer:GetWorld()

		OtherPlayer:TeleportToCoords(World:GetSpawnX(), World:GetSpawnY(), World:GetSpawnZ())
	end

	if not Split[2] then
		if not Player then
			Response = SendMessage(nil, "Usage: " .. Split[1] .. " <targets>")
		else
			MoveToSpawn(Player)
			Response = SendMessageSuccess(Player, "Successfully moved to world spawn")
		end
		return true, Response
	end

	if not Player or Player:HasPermission("core.spawn.others") then
		local Targets, Reason = ResolveTargets(Split[2], MakeSelectorContext(Player), "player")
		if Targets == nil then
			Response = SendMessageFailure(Player, Reason)
		else
			local Affected = ApplyToTargets(Targets, MoveToSpawn)

			if (Split[2]:sub(1, 1) == "@") and (Affected > 1) then
				Response = SendMessageSuccess(Player, "Successfully returned " .. Affected .. " players to world spawn")
			else
				Response = SendMessageSuccess(
					Player,
					"Successfully returned player \"" .. GetTargetName(Targets[1]) .. "\" to world spawn"
				)
			end
		end
	end
	return true, Response
end

function HandleConsoleSpawn(Split)
	return HandleSpawnCommand(Split)
end
