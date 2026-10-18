-- command_movement.lua
-- Parsers and the random-placement helper for the vanilla 1.12.2 /teleport and /spreadplayers.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-movement-commands.md
--
-- Everything here is pure: the world queries and the RNG are passed in, so the tests can drive the
-- placement loop with a fixed sequence (section 2.2 of the spec notes that the vanilla sampling
-- algorithm itself is not documented; this file pins *our* documented approximation).

-- luacheck: globals ParseTeleportLine ParseSpreadplayersLine ParseRotationOffset IsValidTeleportPosition
-- luacheck: globals PickSpreadPositions

local MAX_HORIZONTAL = 30000000
local MAX_TELEPORT_Y = 4096
local SPREAD_MAX_ATTEMPTS = 1000



--- Returns false for NaN and both infinities.
local function IsFinite(a_Number)
	return (a_Number == a_Number) and (a_Number ~= math.huge) and (a_Number ~= -math.huge)
end



--- Parses "<target entity> <x> <y> <z> [<y-rot> <x-rot>]".
-- The coordinate and rotation tokens stay raw; the handler resolves them against the command origin
-- (coordinates) and against each target (rotations).
function ParseTeleportLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] .. " <target entity> <x> <y> <z> [<y-rot> <x-rot>]"
	if ((a_Split[2] == nil) or (a_Split[2] == "")) then
		return nil, Usage
	end
	if ((a_Split[5] == nil) or (a_Split[5] == "")) then
		return nil, Usage
	end

	local Yaw = nil
	local Pitch = nil
	if ((a_Split[6] ~= nil) and (a_Split[6] ~= "")) then
		if ((a_Split[7] == nil) or (a_Split[7] == "")) then
			return nil, Usage
		end
		if ((a_Split[8] ~= nil) and (a_Split[8] ~= "")) then
			return nil, Usage
		end
		Yaw = a_Split[6]
		Pitch = a_Split[7]
	end

	return
	{
		Target = a_Split[2],
		X = a_Split[3],
		Y = a_Split[4],
		Z = a_Split[5],
		Yaw = Yaw,
		Pitch = Pitch,
	}
end



--- Validates a resolved teleport destination (spec section 2.1).
-- Returns true, or false plus a reason.
function IsValidTeleportPosition(a_X, a_Y, a_Z)
	if ((not IsFinite(a_X)) or (not IsFinite(a_Y)) or (not IsFinite(a_Z))) then
		return false, "The coordinates must be finite numbers"
	end
	if ((math.abs(a_X) >= MAX_HORIZONTAL) or (math.abs(a_Z) >= MAX_HORIZONTAL)) then
		return false, "The x and z coordinates must be between -30,000,000 and 30,000,000 (exclusive)"
	end
	if ((a_Y < -MAX_TELEPORT_Y) or (a_Y > MAX_TELEPORT_Y)) then
		return false, "The y coordinate must be between -4096 and 4096"
	end
	return true
end



--- Parses one rotation argument into { Relative = <bool>, Value = <number> }.
-- "~" is relative to the target's own rotation (spec section 2.1, point 5).
function ParseRotationOffset(a_Token)
	if ((a_Token == nil) or (a_Token == "")) then
		return nil, "No rotation was given"
	end

	local Text = a_Token
	local Relative = false
	if (Text:sub(1, 1) == "~") then
		Relative = true
		Text = Text:sub(2)
		if (Text == "") then
			return { Relative = true, Value = 0 }
		end
	end

	local Value = tonumber(Text)
	if ((Value == nil) or (not IsFinite(Value))) then
		return nil, "\"" .. a_Token .. "\" is not a valid rotation"
	end
	return { Relative = Relative, Value = Value }
end



--- Parses "<x> <z> <spreadDistance> <maxRange> <respectTeams> <player ...>" (spec section 2.2).
function ParseSpreadplayersLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] ..
		" <x> <z> <spreadDistance> <maxRange> <respectTeams> <player ...>"
	if ((a_Split[7] == nil) or (a_Split[7] == "")) then
		return nil, Usage
	end

	local SpreadDistance = tonumber(a_Split[4])
	if ((SpreadDistance == nil) or (not IsFinite(SpreadDistance)) or (SpreadDistance < 0)) then
		return nil, "The spread distance must be a number of at least 0.0"
	end

	local MaxRange = tonumber(a_Split[5])
	if ((MaxRange == nil) or (not IsFinite(MaxRange))) then
		return nil, "The maximum range must be a number"
	end
	if (MaxRange < SpreadDistance + 1) then
		return nil, "The maximum range must be at least 1.0 greater than the spread distance"
	end

	if ((a_Split[6] ~= "true") and (a_Split[6] ~= "false")) then
		return nil, "The respectTeams argument must be true or false"
	end

	local Targets = {}
	for Index = 7, #a_Split do
		if ((a_Split[Index] ~= nil) and (a_Split[Index] ~= "")) then
			table.insert(Targets, a_Split[Index])
		end
	end
	if (#Targets == 0) then
		return nil, Usage
	end

	return
	{
		X = a_Split[2],
		Z = a_Split[3],
		SpreadDistance = SpreadDistance,
		MaxRange = MaxRange,
		RespectTeams = (a_Split[6] == "true"),
		Targets = Targets,
	}
end



--- Picks a_GroupCount positions in the square around (a_CenterX, a_CenterZ).
-- a_GetSurfaceY(blockX, blockZ) returns the standing Y for a column, or nil when the column cannot hold a
-- target. a_Random() must return [0, 1). Returns an array of { X, Z, Y } (block centres) or nil + reason.
function PickSpreadPositions(a_GroupCount, a_CenterX, a_CenterZ, a_SpreadDistance, a_MaxRange,
	a_GetSurfaceY, a_Random)
	local Positions = {}
	local MinDistanceSq = a_SpreadDistance * a_SpreadDistance

	for Index = 1, a_GroupCount do
		local Placed = false
		for Attempt = 1, SPREAD_MAX_ATTEMPTS do
			local CandidateX = math.floor(a_CenterX + (a_Random() * 2 - 1) * a_MaxRange) + 0.5
			local CandidateZ = math.floor(a_CenterZ + (a_Random() * 2 - 1) * a_MaxRange) + 0.5

			local FarEnough = true
			for _, Other in ipairs(Positions) do
				local DeltaX = Other.X - CandidateX
				local DeltaZ = Other.Z - CandidateZ
				if ((DeltaX * DeltaX + DeltaZ * DeltaZ) < MinDistanceSq) then
					FarEnough = false
					break
				end
			end

			if (FarEnough) then
				local SurfaceY = a_GetSurfaceY(math.floor(CandidateX), math.floor(CandidateZ))
				if (SurfaceY ~= nil) then
					Positions[Index] = { X = CandidateX, Z = CandidateZ, Y = SurfaceY }
					Placed = true
					break
				end
			end
		end

		if (not Placed) then
			return nil, "Could not find a spot for the targets within the area"
		end
	end

	return Positions
end
