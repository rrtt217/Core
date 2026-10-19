-- command_tp.lua
-- Parsers for the vanilla 1.12.2 /tp command (four forms).
-- Behaviour and sources: specs/commands/vanilla-1.12.2-tp-command.md
--
-- Pure functions only: the file is read by teleport.lua, which resolves the targets, the coordinates
-- (each against its own target) and the rotation.
--
-- 1.12.2 /tp is *not* /teleport: its "~" is relative to the teleported target, it has the
-- "teleport to another player" form and its target may be omitted. The two commands were merged in
-- 1.13 (17w45a), which this file deliberately does not implement.

-- luacheck: globals IsTPCoordinateToken ParseTPLine



--- Returns true when a_Token is a coordinate in the 1.12.2 sense: an absolute number, or a token that
-- starts with "~". Local coordinates ("^") are 1.13+ and are therefore *not* coordinates here
-- (spec section 2.4).
function IsTPCoordinateToken(a_Token)
	if ((a_Token == nil) or (a_Token == "")) then
		return false
	end
	if (a_Token:sub(1, 1) == "~") then
		return true
	end
	return (tonumber(a_Token) ~= nil)
end



--- Parses "/tp ..." into one of the four 1.12.2 forms.
-- Returns a table, or nil plus the usage text:
--   { Form = "self",   Destination = <token> }                      -- tp <destination>
--   { Form = "self",   Destination = <token>, Silent = true }        -- tp <destination> -h (Core extension)
--   { Form = "self",   X, Y, Z, Yaw, Pitch }                        -- tp <x> <y> <z> [<yaw> <pitch>]
--   { Form = "target", Target = <token>, Destination = <token> }    -- tp <target> <destination>
--   { Form = "target", Target = <token>, X, Y, Z, Yaw, Pitch }      -- tp <target> <x> <y> <z> [<yaw> <pitch>]
-- The coordinate and rotation tokens stay raw: teleport.lua resolves them per target.
function ParseTPLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] ..
		" <destination> | <x> <y> <z> [<yaw> <pitch>] | <target> <destination> | " ..
		"<target> <x> <y> <z> [<yaw> <pitch>]"

	if ((a_Split[2] == nil) or (a_Split[2] == "")) then
		return nil, Usage
	end

	-- One argument: the executor teleports to the destination entity:
	if (#a_Split == 2) then
		return { Form = "self", Destination = a_Split[2] }
	end

	-- Core extension kept for backward compatibility: "tp <destination> -h" does not notify the
	-- destination (the vanilla command has no such flag):
	if ((#a_Split == 3) and (a_Split[3] == "-h") and (not IsTPCoordinateToken(a_Split[2]))) then
		return { Form = "self", Destination = a_Split[2], Silent = true }
	end

	-- The first argument decides the family: a coordinate means the executor teleports (the target may
	-- be omitted), anything else is the target selector / player name (spec section 2.4):
	if (IsTPCoordinateToken(a_Split[2])) then
		if ((#a_Split ~= 4) and (#a_Split ~= 6)) then
			return nil, Usage
		end
		local Yaw = nil
		local Pitch = nil
		if (#a_Split == 6) then
			Yaw = a_Split[5]
			Pitch = a_Split[6]
		end
		return
		{
			Form = "self",
			X = a_Split[2],
			Y = a_Split[3],
			Z = a_Split[4],
			Yaw = Yaw,
			Pitch = Pitch,
		}
	end

	if (#a_Split == 3) then
		return { Form = "target", Target = a_Split[2], Destination = a_Split[3] }
	end

	if ((#a_Split ~= 5) and (#a_Split ~= 7)) then
		return nil, Usage
	end

	local Yaw = nil
	local Pitch = nil
	if (#a_Split == 7) then
		Yaw = a_Split[6]
		Pitch = a_Split[7]
	end
	return
	{
		Form = "target",
		Target = a_Split[2],
		X = a_Split[3],
		Y = a_Split[4],
		Z = a_Split[5],
		Yaw = Yaw,
		Pitch = Pitch,
	}
end
