-- luacheck: new globals HandleClearCommand HandleConsoleClear
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess ResolveTargets
-- luacheck: globals GetTargetName ApplyToTargets MakeSelectorContext

function HandleClearCommand(Split, Player, _, Origin)
	local Response
	local SuccessCount = 0

	local ClearInventory = function(OtherPlayer)
		OtherPlayer:GetInventory():Clear()
	end

	if not Split[2] then
		if not Player then
			Response = SendMessage(nil, "Usage: " .. Split[1] .. " <targets>")
		else
			ClearInventory(Player)
			SuccessCount = 1
			Response = SendMessageSuccess(Player, "You cleared your own inventory")
		end
		return true, Response, SuccessCount
	end

	if not Player or Player:HasPermission("core.admin.clear") then
		-- 1.12.2 /clear takes "player name or target selector". Only players have an
		-- inventory to clear, so "@e" targets are narrowed to players.
		local Targets, Reason = ResolveTargets(Split[2], MakeSelectorContext(Player, Origin), "player")
		if Targets == nil then
			Response = SendMessageFailure(Player, Reason)
		else
			local Affected = ApplyToTargets(Targets, ClearInventory)
			SuccessCount = Affected

			if (Split[2]:sub(1, 1) == "@") and (Affected > 1) then
				Response = SendMessageSuccess(Player, "You cleared the inventory of " .. Affected .. " players")
			else
				Response = SendMessageSuccess(Player, "You cleared the inventory of player \"" .. GetTargetName(Targets[1]) .. "\"")
			end
		end
	end
	return true, Response, SuccessCount
end

function HandleConsoleClear(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleClearCommand(Split, nil, EntireCommand, Origin)
end
