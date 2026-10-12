-- luacheck: new globals HandleKillCommand HandleConsoleKill
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess ResolveTargets
-- luacheck: globals GetTargetName ApplyToTargets MakeSelectorContext dtPlugin

function HandleKillCommand(Split, Player)
	local Response

	local KillTarget = function(Target)
		Target:TakeDamage(dtPlugin, nil, 1000, 1000, 0)
	end

	if not Split[2] then
		if not Player then
			Response = SendMessage(nil, "Usage: " .. Split[1] .. " <targets>")
		else
			KillTarget(Player)
		end
		return true, Response
	end

	-- 1.12.2 /kill takes "player name or target selector" and also kills non-players.
	local Targets, Reason = ResolveTargets(Split[2], MakeSelectorContext(Player), "entity")
	if Targets == nil then
		Response = SendMessageFailure(Player, Reason)
		return true, Response
	end

	local Affected = ApplyToTargets(Targets, KillTarget)

	if (Split[2]:sub(1, 1) == "@") and (Affected > 1) then
		Response = SendMessageSuccess(Player, "Successfully killed " .. Affected .. " targets")
	elseif Targets[1]:IsPlayer() then
		Response = SendMessageSuccess(Player, "Successfully killed player \"" .. GetTargetName(Targets[1]) .. "\"")
	else
		Response = SendMessageSuccess(Player, "Successfully killed target \"" .. GetTargetName(Targets[1]) .. "\"")
	end
	return true, Response
end

function HandleConsoleKill(Split)
	return HandleKillCommand(Split)
end
