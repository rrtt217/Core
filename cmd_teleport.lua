-- cmd_teleport.lua
-- Implements the vanilla 1.12.2 /teleport command:
--   teleport <target entity> <x> <y> <z> [<y-rot> <x-rot>]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-movement-commands.md
--
-- /teleport is not /tp: the coordinates are relative to the command's execution position, while /tp
-- resolves "~" against the entity being teleported (spec section 2.1, point 4). /tp keeps its own
-- semantics in teleport.lua.

-- The handler is only referenced from Info.lua, so luacheck counts it as an unused global in this file
-- (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: globals HandleTeleportCommand HandleConsoleTeleportCommand
-- luacheck: globals ParseTeleportLine ParseRotationOffset IsValidTeleportPosition
-- luacheck: globals GetOriginPosition ParseCommandCoords SendMessageFailure SendMessageSuccess
-- luacheck: globals ResolveTargets MakeSelectorContext ApplyToTargets GetTargetName

--- Formats a coordinate for the feedback text ("5" for whole blocks, two decimals otherwise).
local function FormatCoordinate(a_Value)
	if (a_Value == math.floor(a_Value)) then
		return string.format("%d", a_Value)
	end
	return string.format("%.2f", a_Value)
end



--- Resolves an offset against a_Target's current rotation.
local function ApplyOffset(a_Offset, a_Current)
	if (a_Offset.Relative) then
		return a_Current + a_Offset.Value
	end
	return a_Offset.Value
end



function HandleTeleportCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseTeleportLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local YawOffset = nil
	local PitchOffset = nil
	if (Parse.Yaw ~= nil) then
		YawOffset, Reason = ParseRotationOffset(Parse.Yaw)
		if (YawOffset == nil) then
			return true, SendMessageFailure(a_Player, Reason), 0
		end
		PitchOffset, Reason = ParseRotationOffset(Parse.Pitch)
		if (PitchOffset == nil) then
			return true, SendMessageFailure(a_Player, Reason), 0
		end
	end

	-- The coordinates resolve against the command origin, not against the targets (spec section 2.1).
	-- On failure ParseCommandCoords() returns the reason as its second value (see cmd_testforblock.lua):
	local X, Y, Z = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, GetOriginPosition(a_Origin))
	if (X == nil) then
		return true, SendMessageFailure(a_Player, Y), 0
	end

	local Ok, PositionReason = IsValidTeleportPosition(X, Y, Z)
	if (not Ok) then
		return true, SendMessageFailure(a_Player, PositionReason), 0
	end

	local Targets, TargetReason = ResolveTargets(Parse.Target, MakeSelectorContext(a_Player, a_Origin), "entity")
	if (Targets == nil) then
		return true, SendMessageFailure(a_Player, TargetReason), 0
	end
	if (#Targets == 0) then
		return true, SendMessageFailure(a_Player, "No entity was found"), 0
	end

	-- Only the targets reached right now are reported; targets in other worlds are queued by the
	-- selector layer and teleported one tick later without a chat line here (C1 section 7).
	local Names = {}
	ApplyToTargets(Targets,
		function (a_Target)
			a_Target:TeleportToCoords(X, Y, Z)
			if (YawOffset ~= nil) then
				a_Target:SetYaw(ApplyOffset(YawOffset, a_Target:GetYaw()))
				a_Target:SetPitch(ApplyOffset(PitchOffset, a_Target:GetPitch()))
			end

			local Name = GetTargetName(a_Target)
			table.insert(Names, Name)
			if (a_Player ~= nil) then
				SendMessageSuccess(a_Player, string.format("Teleported %s to %s, %s, %s", Name,
					FormatCoordinate(X), FormatCoordinate(Y), FormatCoordinate(Z)))
			end
		end
	)

	if (#Names == 0) then
		return true, SendMessageFailure(a_Player, "Could not teleport any entity"), 0
	end
	if (a_Player ~= nil) then
		return true, nil, #Names
	end

	local Lines = {}
	for _, Name in ipairs(Names) do
		table.insert(Lines, string.format("Teleported %s to %s, %s, %s", Name,
			FormatCoordinate(X), FormatCoordinate(Y), FormatCoordinate(Z)))
	end
	return true, table.concat(Lines, "; "), #Names
end


function HandleConsoleTeleportCommand(a_Split, _, _, a_Origin)
	return HandleTeleportCommand(a_Split, nil, nil, a_Origin)
end
