-- command_coords.lua
-- Parses 1.12.2 command coordinates (absolute and relative "~") against a command origin.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-command-coordinates.md

-- luacheck: globals GetOriginPosition ParseCommandCoord ParseCommandCoords



--- Returns the position a command executes from, as a plain {x =, y =, z =} table.
-- Returns nil when the origin carries no position (console / RCON build a cCommandOrigin with
-- m_Position == (0, 0, 0) and no player), so callers can tell "at the world origin" from "unknown".
function GetOriginPosition(a_Origin)
	if (a_Origin == nil) then
		return nil
	end
	if (a_Origin.GetPosition == nil) then
		return nil
	end

	local Position = a_Origin:GetPosition()
	if (Position == nil) then
		return nil
	end

	return { x = Position.x, y = Position.y, z = Position.z }
end



--- Parses a single coordinate argument the way Java 1.12.2 does.
-- a_Token    the raw argument: "12", "-3.5", "~", "~5", "~-2"
-- a_Axis     "x", "y" or "z" - which component of a_Position the tilde is relative to
-- a_Position the execution position ({x =, y =, z =}) or nil when there is none
-- Returns the resolved number, or nil plus a human-readable reason.
function ParseCommandCoord(a_Token, a_Axis, a_Position)
	if (a_Token == nil) then
		return nil, "No coordinate was given"
	end

	a_Token = tostring(a_Token)
	if (a_Token == "") then
		return nil, "An empty coordinate was given"
	end

	if (a_Token:sub(1, 1) == "^") then
		-- Local coordinates were added in 1.13 (17w50a); 1.12.2 has no such notation, so the
		-- argument is simply not a number (spec section 2.3):
		return nil, "'" .. a_Token .. "' is not a valid number"
	end

	if (a_Token:sub(1, 1) == "~") then
		local Offset = a_Token:sub(2)
		local Number = 0
		if (Offset ~= "") then
			Number = tonumber(Offset)
			if (Number == nil) then
				return nil, "'" .. a_Token .. "' is not a valid number"
			end
		end

		if (a_Position == nil) then
			-- No execution position is known; a lone "~" is then 0 and "~N" is N. Callers that need
			-- a real base (command blocks, players) always pass one.
			return Number
		end

		return a_Position[a_Axis] + Number
	end

	local Number = tonumber(a_Token)
	if (Number == nil) then
		return nil, "'" .. a_Token .. "' is not a valid number"
	end
	return Number
end



--- Parses a whole x/y/z coordinate triple.
-- Returns x, y, z, or nil plus a human-readable reason.
function ParseCommandCoords(a_X, a_Y, a_Z, a_Position)
	local X, Reason = ParseCommandCoord(a_X, "x", a_Position)
	if (X == nil) then
		return nil, Reason
	end

	local Y
	Y, Reason = ParseCommandCoord(a_Y, "y", a_Position)
	if (Y == nil) then
		return nil, Reason
	end

	local Z
	Z, Reason = ParseCommandCoord(a_Z, "z", a_Position)
	if (Z == nil) then
		return nil, Reason
	end

	return X, Y, Z
end
