-- test_movement_commands.lua
--
-- Tests for Core's vanilla 1.12.2 /teleport and /spreadplayers: argument parsing, the destination
-- validation, rotation offsets, the documented random-placement sampler and the two handlers.
--
-- Verified specification: specs/commands/vanilla-1.12.2-movement-commands.md (parent repository).
-- The cases pin what is easy to get wrong: "/teleport" resolves "~" against the command origin (not the
-- target, which is /tp), the rotation pair is all-or-nothing and its "~" is relative to the target,
-- and /spreadplayers must reject a maxRange smaller than spreadDistance + 1.
--
-- Invariants:
--   * The parsers and PickSpreadPositions() are pure; the RNG and the surface lookup are injected.
--   * The sampler never returns two spots closer than spreadDistance and never returns a spot whose
--     column cannot hold a target.
--   * A refused command teleports nobody.
--
-- Run with:  lua tests/test_movement_commands.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_movement.lua")
dofile(ScriptDir .. "/../cmd_teleport.lua")
dofile(ScriptDir .. "/../cmd_spreadplayers.lua")

-- luacheck: ignore 131
-- luacheck: new globals Vector3i E_BLOCK_AIR E_BLOCK_LAVA E_BLOCK_STATIONARY_LAVA E_BLOCK_STONE E_BLOCK_WATER
-- luacheck: new globals MakeSelectorContext ResolveTargets ApplyToTargets GetTargetName

local NumPassed = 0
local NumFailed = 0

local function Check(a_Condition, a_Message)
	if (a_Condition) then
		NumPassed = NumPassed + 1
	else
		NumFailed = NumFailed + 1
		print("FAIL: " .. a_Message)
	end
end

local function CheckEquals(a_Actual, a_Expected, a_Message)
	Check(
		a_Actual == a_Expected,
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end

local function CheckClose(a_Actual, a_Expected, a_Message)
	Check(
		(a_Actual ~= nil) and (math.abs(a_Actual - a_Expected) < 1e-9),
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end






-- /teleport parsing ----------------------------------------------------------

local Parse, Reason = ParseTeleportLine({ "teleport" })
CheckEquals(Parse, nil, "teleport requires its arguments")
Check(Reason ~= nil and Reason:find("Usage:", 1, true) ~= nil, "teleport reports the usage")

Parse = ParseTeleportLine({ "teleport", "Alice" })
CheckEquals(Parse, nil, "teleport requires three coordinates")

Parse = ParseTeleportLine({ "teleport", "Alice", "1", "2", "3" })
Check(Parse ~= nil, "teleport parses the minimal form")
CheckEquals(Parse.Target, "Alice", "teleport keeps the target")
CheckEquals(Parse.Yaw, nil, "teleport without rotation has no yaw")

Parse = ParseTeleportLine({ "teleport", "@e", "~", "~5", "~-1", "90", "-10" })
Check(Parse ~= nil and Parse.Yaw == "90" and Parse.Pitch == "-10", "teleport parses the rotation pair")

Parse = ParseTeleportLine({ "teleport", "Alice", "1", "2", "3", "90" })
CheckEquals(Parse, nil, "teleport refuses a single rotation value")

Parse = ParseTeleportLine({ "teleport", "Alice", "1", "2", "3", "90", "0", "extra" })
CheckEquals(Parse, nil, "teleport refuses extra arguments")

-- Destination validation -----------------------------------------------------

local Ok = IsValidTeleportPosition(0, 64, 0)
Check(Ok, "accepts a normal position")
Ok = IsValidTeleportPosition(29999999, 64, -29999999)
Check(Ok, "accepts positions just inside the horizontal limit")
Ok = IsValidTeleportPosition(30000000, 64, 0)
Check(not Ok, "refuses x = 30,000,000 (exclusive)")
Ok = IsValidTeleportPosition(0, 4096, 0)
Check(Ok, "accepts y = 4096")
Ok = IsValidTeleportPosition(0, -4096, 0)
Check(Ok, "accepts y = -4096")
Ok = IsValidTeleportPosition(0, 4097, 0)
Check(not Ok, "refuses y = 4097")
Ok = IsValidTeleportPosition(0, 64, 0 / 0)
Check(not Ok, "refuses NaN")

-- Rotation offsets -----------------------------------------------------------

local Offset = ParseRotationOffset("~")
Check(Offset ~= nil and Offset.Relative and Offset.Value == 0, "~ is a zero relative offset")
Offset = ParseRotationOffset("~5")
Check(Offset ~= nil and Offset.Relative and Offset.Value == 5, "~5 is a relative offset")
Offset = ParseRotationOffset("~-5.5")
Check(Offset ~= nil and Offset.Relative and Offset.Value == -5.5, "~-5.5 is a relative offset")
Offset = ParseRotationOffset("90")
Check(Offset ~= nil and (not Offset.Relative) and Offset.Value == 90, "90 is an absolute rotation")
Check(ParseRotationOffset("€") == nil, "refuses a non-numeric rotation")
Check(ParseRotationOffset("~abc") == nil, "refuses a malformed relative rotation")

-- /spreadplayers parsing -----------------------------------------------------

Parse, Reason = ParseSpreadplayersLine({ "spreadplayers", "0", "0", "2", "10", "true", "@a" })
Check(Parse ~= nil, "spreadplayers parses a full command")
CheckEquals(Parse.RespectTeams, true, "respectTeams true")
CheckEquals(#Parse.Targets, 1, "one target token")

Parse = ParseSpreadplayersLine({ "spreadplayers", "0", "0", "0", "1", "false", "Alice", "@e" })
Check(Parse ~= nil and Parse.RespectTeams == false and #Parse.Targets == 2, "two target tokens")

Check(ParseSpreadplayersLine({ "spreadplayers", "0", "0", "2", "10", "true" }) == nil,
	"spreadplayers requires at least one target")
Check(ParseSpreadplayersLine({ "spreadplayers", "0", "0", "-1", "10", "true", "@a" }) == nil,
	"spreadplayers refuses a negative spread distance")
Check(ParseSpreadplayersLine({ "spreadplayers", "0", "0", "2", "2.5", "true", "@a" }) == nil,
	"spreadplayers refuses maxRange < spreadDistance + 1")
Check(ParseSpreadplayersLine({ "spreadplayers", "0", "0", "2", "3", "yes", "@a" }) == nil,
	"spreadplayers refuses a non-boolean respectTeams")
Check(ParseSpreadplayersLine({ "spreadplayers", "~", "~", "2", "10", "true", "@a" }) ~= nil,
	"spreadplayers accepts relative centre coordinates")

-- Sampler --------------------------------------------------------------------

local function MakeSequence(a_Values)
	local Index = 0
	return function ()
		Index = Index + 1
		return a_Values[(Index - 1) % #a_Values + 1]
	end
end

local FlatSurface = function () return 64 end

local Positions = PickSpreadPositions(1, 0, 0, 0, 10, FlatSurface, MakeSequence({ 0.5, 0.5 }))
Check(Positions ~= nil and #Positions == 1, "places a single target")
CheckClose(Positions[1].X, 0.5, "single target x")
CheckClose(Positions[1].Z, 0.5, "single target z")
CheckEquals(Positions[1].Y, 64, "single target y")

-- Two targets: the first candidate pair would be 1 block apart, which violates spreadDistance = 5, so the
-- sampler must draw a second candidate for the second target (0.5, 0.9 -> block (0, 8)).
Positions = PickSpreadPositions(2, 0, 0, 5, 10, FlatSurface,
	MakeSequence({ 0.5, 0.5, 0.55, 0.5, 0.5, 0.9 }))
Check(Positions ~= nil and #Positions == 2, "places two targets")
Check((Positions[1].X - Positions[2].X) ^ 2 + (Positions[1].Z - Positions[2].Z) ^ 2 >= 25,
	"two targets respect spreadDistance")

-- A column that cannot hold a target is skipped: x = 0 is invalid, x = 1 is fine.
local Surface = function (a_X)
	if (a_X == 0) then
		return nil
	end
	return 64
end
Positions = PickSpreadPositions(1, 0, 0, 0, 10, Surface, MakeSequence({ 0.5, 0.5, 0.55, 0.5 }))
Check(Positions ~= nil and Positions[1].X == 1.5, "skips a column that cannot hold a target")

Positions = PickSpreadPositions(1, 0, 0, 0, 10, function () return nil end, MakeSequence({ 0.5 }))
CheckEquals(Positions, nil, "fails when no column can hold a target")

-- Handler fakes --------------------------------------------------------------

E_BLOCK_AIR = 0
E_BLOCK_STONE = 1
E_BLOCK_LAVA = 10
E_BLOCK_STATIONARY_LAVA = 11

Vector3i = function (a_X, a_Y, a_Z) return { x = a_X, y = a_Y, z = a_Z } end

local Messages = {}
SendMessageFailure = function (a_Player, a_Message)
	table.insert(Messages, "failure: " .. tostring(a_Message))
	if (a_Player ~= nil) then return nil end
	return a_Message
end
SendMessageSuccess = function (a_Player, a_Message)
	table.insert(Messages, "success: " .. tostring(a_Message))
	if (a_Player ~= nil) then return nil end
	return a_Message
end

MakeSelectorContext = function () return {} end
GetTargetName = function (a_Entity) return a_Entity:GetName() end
ApplyToTargets = function (a_Targets, a_Action)
	for _, Target in ipairs(a_Targets) do
		a_Action(Target)
	end
end

local function MakeEntity(a_ID, a_Name)
	local Entity =
	{
		ID = a_ID,
		Name = a_Name,
		Yaw = 10,
		Pitch = 20,
		Teleported = nil,
		SetYawValue = nil,
		SetPitchValue = nil,
	}
	function Entity:GetUniqueID() return self.ID end
	function Entity:GetName() return self.Name end
	function Entity:IsPlayer() return false end
	function Entity:GetYaw() return self.Yaw end
	function Entity:GetPitch() return self.Pitch end
	function Entity:SetYaw(a_Value) self.SetYawValue = a_Value end
	function Entity:SetPitch(a_Value) self.SetPitchValue = a_Value end
	function Entity:TeleportToCoords(a_X, a_Y, a_Z) self.Teleported = { x = a_X, y = a_Y, z = a_Z } end
	return Entity
end

local Pig = MakeEntity(1, "Pig")
ResolveTargets = function () return { Pig } end

local Origin = function (a_X, a_Y, a_Z)
	return
	{
		GetPosition = function () return { x = a_X, y = a_Y, z = a_Z } end,
		GetWorld = function () return nil end,
	}
end

Messages = {}
local Count = nil
local Message = nil
local HandlerOk = HandleTeleportCommand({ "teleport", "@e", "~", "~5", "~-1" }, nil, nil, Origin(10, 64, 10))
CheckEquals(HandlerOk, true, "teleport handler returns true")
Check(Pig.Teleported ~= nil, "teleport reaches the target")
CheckClose(Pig.Teleported.x, 10, "teleport resolves ~ against the origin x")
CheckClose(Pig.Teleported.y, 69, "teleport resolves ~5 against the origin y")
CheckClose(Pig.Teleported.z, 9, "teleport resolves ~-1 against the origin z")

Pig.Teleported = nil
HandleTeleportCommand({ "teleport", "@e", "0", "64", "0", "~90", "~-10" }, nil, nil, Origin(0, 0, 0))
CheckClose(Pig.SetYawValue, 100, "rotation ~ is relative to the target yaw")
CheckClose(Pig.SetPitchValue, 10, "rotation ~ is relative to the target pitch")

ResolveTargets = function () return {} end
Messages = {}
Message, Count = select(2, HandleTeleportCommand({ "teleport", "@e", "0", "64", "0" }, nil, nil, Origin(0, 0, 0)))
Check(Message ~= nil and Message:find("No entity was found", 1, true) ~= nil,
	"teleport reports an empty target set")
CheckEquals(Count, 0, "teleport with no targets has success count 0")

-- /spreadplayers handler -----------------------------------------------------

local function MakeWorld()
	local World = {}
	function World:TryGetHeight(a_X, a_Z)
		return true, 64
	end
	function World:GetBlock(a_Position)
		if (a_Position.y == 64) then
			return E_BLOCK_STONE
		end
		return E_BLOCK_AIR
	end
	return World
end

local World = MakeWorld()
local SpawnOrigin =
{
	GetWorld = function () return World end,
	GetPosition = function () return { x = 0, y = 64, z = 0 } end,
}

local Cow = MakeEntity(2, "Cow")
ResolveTargets = function () return { Cow } end
math.random = function () return 0.5 end

Messages = {}
Ok, Message, Count = HandleSpreadplayersCommand({ "spreadplayers", "~", "~", "2", "10", "false", "@e" },
	nil, nil, SpawnOrigin)
CheckEquals(Ok, true, "spreadplayers handler returns true")
Check(Cow.Teleported ~= nil, "spreadplayers teleports the target")
CheckClose(Cow.Teleported.x, 0.5, "spreadplayers places the target at the block centre")
CheckClose(Cow.Teleported.y, 65, "spreadplayers places the target on top of the surface block")
CheckEquals(Count, 1, "spreadplayers reports one target")
Check(Message ~= nil and Message:find("Spread 1 target", 1, true) ~= nil, "spreadplayers feedback")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
