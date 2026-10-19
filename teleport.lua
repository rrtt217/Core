-- teleport.lua
-- Implements the vanilla 1.12.2 /tp command (four forms).
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-tp-command.md
--
-- "/tp" is not "/teleport": its "~" resolves against each teleported target (position and rotation),
-- its target may be omitted and it has the "teleport to another entity" form. The two commands were
-- merged in 1.13 (17w45a); /teleport keeps the origin-relative semantics in cmd_teleport.lua.

-- luacheck: ignore 131
-- luacheck: globals ParseTPLine ParseCommandCoords IsValidTeleportPosition ParseRotationOffset
-- luacheck: globals ResolveTargets MakeSelectorContext ApplyToTargets GetTargetName
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess

local SELF_NOT_FOUND = "No player was found to teleport"



--- Formats a coordinate for the feedback text ("5" for whole blocks, two decimals otherwise).
local function FormatCoordinate(a_Value)
	if (a_Value == math.floor(a_Value)) then
		return string.format("%d", a_Value)
	end
	return string.format("%.2f", a_Value)
end



--- Returns a_Target's current position as a plain {x =, y =, z =} table: the base of its "~".
local function GetTargetPosition(a_Target)
	return { x = a_Target:GetPosX(), y = a_Target:GetPosY(), z = a_Target:GetPosZ() }
end



--- Resolves a rotation token against a_Target's current rotation (spec section 2.3).
local function ResolveRotation(a_Token, a_Current)
	local Offset, Reason = ParseRotationOffset(a_Token)
	if (Offset == nil) then
		return nil, Reason
	end
	if (Offset.Relative) then
		return a_Current + Offset.Value
	end
	return Offset.Value
end



--- Resolves the destination entity of forms 1 and 3; it must resolve to exactly one entity.
local function ResolveDestination(a_Token, a_Context)
	local Targets, Reason = ResolveTargets(a_Token, a_Context, "entity")
	if (Targets == nil) then
		return nil, Reason
	end
	if (#Targets == 0) then
		-- A selector that only matched entities in other worlds lands here too: the destination must be
		-- reachable right now (spec section 4.2):
		return nil, "No entity was found"
	end
	if (#Targets > 1) or (Targets.Deferred ~= nil) then
		return nil, "The destination must be a single entity"
	end
	return Targets[1]
end



--- Resolves the entities to teleport: the executor for the self forms, the selector otherwise.
local function ResolveTeleportedTargets(a_Parse, a_Player, a_Context)
	if (a_Parse.Form == "self") then
		if (a_Player == nil) then
			return nil, SELF_NOT_FOUND
		end
		return { a_Player }
	end

	local Targets, Reason = ResolveTargets(a_Parse.Target, a_Context, "entity")
	if (Targets == nil) then
		return nil, Reason
	end
	if (#Targets == 0) then
		return nil, "No entity was found"
	end
	return Targets
end



function HandleTPCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseTPLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local Context = MakeSelectorContext(a_Player, a_Origin)

	-- Syntax checks first, so a bad command never teleports part of its targets:
	if (Parse.Yaw ~= nil) then
		local Offset, RotationReason = ParseRotationOffset(Parse.Yaw)
		if (Offset == nil) then
			return true, SendMessageFailure(a_Player, RotationReason), 0
		end
		Offset, RotationReason = ParseRotationOffset(Parse.Pitch)
		if (Offset == nil) then
			return true, SendMessageFailure(a_Player, RotationReason), 0
		end
	end
	if (Parse.X ~= nil) then
		-- Without a base the relative tokens resolve to their offsets, which still catches syntax
		-- errors; the per-target range check happens below, against each target's own position:
		local X, CoordinateReason = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, nil)
		if (X == nil) then
			return true, SendMessageFailure(a_Player, CoordinateReason), 0
		end
	end

	-- The feedback is collected so the console path can return it as one string:
	local Lines = {}
	local SuccessCount = 0
	local function Report(a_Line, a_IsFailure)
		if (a_Player ~= nil) then
			if (a_IsFailure) then
				SendMessageFailure(a_Player, a_Line)
			else
				SendMessageSuccess(a_Player, a_Line)
			end
		end
		table.insert(Lines, a_Line)
	end

	-- Forms 1 and 3 teleport to an entity:
	if (Parse.Destination ~= nil) then
		local Destination, DestinationReason = ResolveDestination(Parse.Destination, Context)
		if (Destination == nil) then
			return true, SendMessageFailure(a_Player, DestinationReason), 0
		end

		if (Parse.Form == "self") then
			if (a_Player == nil) then
				return true, SendMessageFailure(a_Player, SELF_NOT_FOUND), 0
			end
			if (a_Player == Destination) then
				return true, SendMessageFailure(a_Player, "Y' can't teleport to yerself"), 0
			end
			-- Historical Core behaviour: a destination in another world moves the executor there. The
			-- vanilla rule for this form is unverified (spec section 4.5):
			if (a_Player:GetWorld() ~= Destination:GetWorld()) then
				a_Player:MoveToWorld(Destination:GetWorld(), true,
					Vector3d(Destination:GetPosX() + 0.5, Destination:GetPosY(), Destination:GetPosZ() + 0.5))
			else
				a_Player:TeleportToEntity(Destination)
			end
			local Line = "You teleported to " .. GetTargetName(Destination)
			Report(Line, false)
			if ((not Parse.Silent) and Destination:IsPlayer()) then
				SendMessage(Destination, a_Player:GetName() .. " teleported to you")
			end
			return true, Line, 1
		end

		-- Form 3: every target goes to the destination entity; a target in another dimension fails
		-- individually, the rest still teleport (spec section 2.5):
		local Targets, TargetReason = ResolveTeleportedTargets(Parse, a_Player, Context)
		if (Targets == nil) then
			return true, SendMessageFailure(a_Player, TargetReason), 0
		end
		ApplyToTargets(Targets, function (a_Target, a_Deferred)
			if (a_Target:GetWorld() ~= Destination:GetWorld()) then
				if (not a_Deferred) then
					Report(GetTargetName(a_Target) .. " is not in the same dimension as " ..
						GetTargetName(Destination), true)
				end
				return
			end
			a_Target:TeleportToEntity(Destination)
			SuccessCount = SuccessCount + 1
			if (not a_Deferred) then
				Report("Teleported " .. GetTargetName(a_Target) .. " to " .. GetTargetName(Destination), false)
			end
		end)
	else
		-- Forms 2 and 4 teleport to coordinates, resolved against each target's own position:
		local Targets, TargetReason = ResolveTeleportedTargets(Parse, a_Player, Context)
		if (Targets == nil) then
			return true, SendMessageFailure(a_Player, TargetReason), 0
		end
		ApplyToTargets(Targets, function (a_Target, a_Deferred)
			local X, Y, Z = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, GetTargetPosition(a_Target))
			local Ok, PositionReason = IsValidTeleportPosition(X, Y, Z)
			if (not Ok) then
				if (not a_Deferred) then
					Report(GetTargetName(a_Target) .. ": " .. PositionReason, true)
				end
				return
			end

			a_Target:TeleportToCoords(X, Y, Z)
			if (Parse.Yaw ~= nil) then
				a_Target:SetYaw(ResolveRotation(Parse.Yaw, a_Target:GetYaw()))
				a_Target:SetPitch(ResolveRotation(Parse.Pitch, a_Target:GetPitch()))
			end
			SuccessCount = SuccessCount + 1

			if (not a_Deferred) then
				if (Parse.Form == "self") then
					Report(string.format("You teleported to [X:%s Y:%s Z:%s]",
						FormatCoordinate(X), FormatCoordinate(Y), FormatCoordinate(Z)), false)
				else
					Report(string.format("Teleported %s to %s, %s, %s", GetTargetName(a_Target),
						FormatCoordinate(X), FormatCoordinate(Y), FormatCoordinate(Z)), false)
				end
			end
		end)
	end

	if (SuccessCount == 0) then
		return true, SendMessageFailure(a_Player, "Could not teleport any entity"), 0
	end
	if (a_Player ~= nil) then
		return true, nil, SuccessCount
	end
	return true, table.concat(Lines, "; "), SuccessCount
end



--- Console / command-block entry point: the same four forms, with no executor (spec section 3).
function HandleConsoleTPCommand(a_Split, _, _, a_Origin)
	return HandleTPCommand(a_Split, nil, nil, a_Origin)
end
