-- luacheck: new globals HandleEffectCommand HandleConsoleEffect
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess ResolveTargets GetTargetName
-- luacheck: globals ApplyToTargets MakeSelectorContext

function HandleEffectCommand(Split, Player)
	local Response

	if not Split[4] then
		Split[4] = 30
	end

	if not Split[5] then
		Split[5] = 0
	end

	local EffectID = tonumber(Split[3])
	local Amplifier = tonumber(Split[5])
	local IsSelector = (Split[2] ~= nil) and (Split[2]:sub(1, 1) == "@")

	local ApplyEffect = function(OtherPlayer)
		local Seconds = (tonumber(Split[4]) * 20)

		OtherPlayer:AddEntityEffect(EffectID, Seconds, Amplifier)
	end

	local RemoveEffects = function(OtherPlayer)
		OtherPlayer:ClearEntityEffects()
	end

	-- Applies Callback to every resolved target and builds the success message.
	-- 1.12.2 /effect manages effects on "players and other entities" and documents
	-- "@e is permitted to target entities other than players", so pawns are the kind
	-- (cPawn:AddEntityEffect covers players and monsters alike).
	local ApplyToResolvedTargets = function(Callback, SuccessSingle, SuccessMultiple)
		local Targets, Reason = ResolveTargets(Split[2], MakeSelectorContext(Player), "pawn")
		if Targets == nil then
			Response = SendMessageFailure(Player, Reason)
			return
		end

		local Affected = ApplyToTargets(Targets, Callback)

		if IsSelector then
			Response = SendMessageSuccess(Player, SuccessMultiple(Affected))
		else
			Response = SendMessageSuccess(Player, SuccessSingle(GetTargetName(Targets[1])))
		end
	end

	if Split[3] ~= "clear" then
		if not Split[3] then
			Response = SendMessage(
				Player,
				"Usage: " .. Split[1] .. " <targets> <effect> [seconds] [amplifier] OR " .. Split[1] .. " <targets> clear"
			)
		elseif not EffectID or EffectID < 1 or EffectID > 23 then
			Response = SendMessageFailure(Player, "Invalid effect ID \"" .. Split[3] .. "\"")
		elseif not tonumber(Split[4]) then
			Response = SendMessageFailure(Player, "Invalid duration \"" .. Split[4] .. "\"")
		elseif tonumber(Split[4]) < 0 then
			Response = SendMessageFailure(Player, "The duration in seconds must be at least 0")
		elseif tonumber(Split[4]) > 1000000 then
			Response = SendMessageFailure(Player, "The duration in seconds must be at most 1000000")
		elseif not Amplifier then
			Response = SendMessageFailure(Player, "Invalid amplification amount \"" .. Split[5] .. "\"")
		elseif Amplifier < 0 then
			Response = SendMessageFailure(Player, "The amplification amount must be at least 0")
		elseif Amplifier > 255 then
			Response = SendMessageFailure(Player, "The amplification amount must be at most 255")
		else
			ApplyToResolvedTargets(
				ApplyEffect,
				function (Name)
					return "Successfully added effect to player \"" .. Name .. "\" for " .. Split[4] .. " seconds"
				end,
				function (NumTargets)
					return "Successfully added effect to " .. NumTargets .. " targets for " .. Split[4] .. " seconds"
				end
			)
		end
	else
		ApplyToResolvedTargets(
			RemoveEffects,
			function (Name)
				return "Successfully removed effects from player \"" .. Name .. "\""
			end,
			function (NumTargets)
				return "Successfully removed effects from " .. NumTargets .. " targets"
			end
		)
	end
	return true, Response
end

function HandleConsoleEffect(Split)
	return HandleEffectCommand(Split)
end
