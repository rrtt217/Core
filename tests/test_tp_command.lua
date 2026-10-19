-- test_tp_command.lua
--
-- Tests for Core's vanilla 1.12.2 /tp command: the four forms, the form ambiguity, the target-relative
-- "~" (position AND rotation), the destination-entity forms and the per-target failures.
--
-- Verified specification: specs/commands/vanilla-1.12.2-tp-command.md (parent repository).
-- The cases pin what is easy to get wrong: "/tp" resolves "~" against *each teleported target* (unlike
-- /teleport, which uses the command origin), "tp <x> <y> <z>" and "tp <target> <x> <y> <z>" are told
-- apart by whether the first argument is a coordinate, and the rotation pair is all-or-nothing.
--
-- Invariants:
--   * ParseTPLine() is pure and never accepts a partially specified form.
--   * No handler path teleports anybody when the arguments (or the destination) are invalid.
--   * With several targets, every target gets its own position base.
--
-- Run with:  lua tests/test_tp_command.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_movement.lua")
dofile(ScriptDir .. "/../command_tp.lua")
dofile(ScriptDir .. "/../teleport.lua")

-- luacheck: ignore 131
-- luacheck: new globals Vector3d MakeSelectorContext ResolveTargets ApplyToTargets GetTargetName
-- luacheck: new globals SendMessage SendMessageFailure SendMessageSuccess

local NumPassed = 0
local NumFailed = 0

-- Feedback recorded by the SendMessage* fakes (declared before HasMessage() so it is in scope there).
local Messages = {}

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

--- Returns true when the recorded messages contain a_Text (used for the player path, where
--- SendMessageFailure() returns nil and the text only reaches the Messages list).
local function HasMessage(a_Text)
	for _, Line in ipairs(Messages) do
		if (Line:find(a_Text, 1, true) ~= nil) then
			return true
		end
	end
	return false
end

local function CheckClose(a_Actual, a_Expected, a_Message)
	Check(
		(a_Actual ~= nil) and (math.abs(a_Actual - a_Expected) < 1e-9),
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end






-- Parsing --------------------------------------------------------------------

local Parse = ParseTPLine({ "tp", "Alice" })
Check(Parse ~= nil and Parse.Form == "self" and Parse.Destination == "Alice", "tp <destination>")

Parse = ParseTPLine({ "tp", "Alice", "-h" })
Check(Parse ~= nil and Parse.Form == "self" and Parse.Destination == "Alice" and Parse.Silent,
	"tp <destination> -h keeps the silent flag")

Parse = ParseTPLine({ "tp", "100", "~3", "100" })
Check(Parse ~= nil and Parse.Form == "self" and Parse.X == "100" and Parse.Y == "~3" and Parse.Z == "100"
	and Parse.Yaw == nil, "tp <x> <y> <z>")

Parse = ParseTPLine({ "tp", "~", "~", "~", "~10", "~" })
Check(Parse ~= nil and Parse.Form == "self" and Parse.Yaw == "~10" and Parse.Pitch == "~",
	"tp <x> <y> <z> <yaw> <pitch>")

Parse = ParseTPLine({ "tp", "@a", "@s" })
Check(Parse ~= nil and Parse.Form == "target" and Parse.Target == "@a" and Parse.Destination == "@s",
	"tp <target> <destination>")

Parse = ParseTPLine({ "tp", "@e", "100", "64", "100" })
Check(Parse ~= nil and Parse.Form == "target" and Parse.X == "100" and Parse.Z == "100" and Parse.Yaw == nil,
	"tp <target> <x> <y> <z>")

Parse = ParseTPLine({ "tp", "@p", "~", "~", "~", "~10", "~" })
Check(Parse ~= nil and Parse.Form == "target" and Parse.Yaw == "~10",
	"tp <target> <x> <y> <z> <yaw> <pitch>")

Parse = ParseTPLine({ "tp", "^", "^", "^" })
Check(Parse == nil, "caret tokens do not form a coordinate form (1.13+ notation)")

Parse = ParseTPLine({ "tp" })
Check(Parse == nil, "no arguments is a usage error")
Check(ParseTPLine({ "tp", "100", "64" }) == nil, "two coordinates are a usage error")
Check(ParseTPLine({ "tp", "100", "64", "100", "90" }) == nil, "a single rotation is a usage error")
Check(ParseTPLine({ "tp", "@e", "100", "64", "100", "90" }) == nil,
	"a single target rotation is a usage error")
Check(ParseTPLine({ "tp", "@e", "100", "64", "100", "90", "0", "extra" }) == nil,
	"extra arguments are a usage error")
Check(IsTPCoordinateToken("~") and IsTPCoordinateToken("~5") and IsTPCoordinateToken("-3.5"),
	"coordinate tokens")
Check((not IsTPCoordinateToken("@p")) and (not IsTPCoordinateToken("Alice")) and
	(not IsTPCoordinateToken("^")) and (not IsTPCoordinateToken("")), "non-coordinate tokens")

-- Handler fakes --------------------------------------------------------------

Vector3d = function (a_X, a_Y, a_Z) return { x = a_X, y = a_Y, z = a_Z } end

Messages = {}
SendMessage = function (a_Player, a_Message)
	table.insert(Messages, "tell: " .. tostring(a_Message))
end
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

local function MakeEntity(a_ID, a_Name, a_X, a_Y, a_Z, a_World)
	local Entity =
	{
		ID = a_ID,
		Name = a_Name,
		X = a_X or 0,
		Y = a_Y or 0,
		Z = a_Z or 0,
		Yaw = 10,
		Pitch = 20,
		World = a_World or "overworld",
		Teleported = nil,
		TeleportedToEntity = nil,
		SetYawValue = nil,
		SetPitchValue = nil,
		MovedToWorld = nil,
	}
	function Entity:GetUniqueID() return self.ID end
	function Entity:GetName() return self.Name end
	function Entity:IsPlayer() return false end
	function Entity:GetWorld() return self.World end
	function Entity:GetPosX() return self.X end
	function Entity:GetPosY() return self.Y end
	function Entity:GetPosZ() return self.Z end
	function Entity:GetYaw() return self.Yaw end
	function Entity:GetPitch() return self.Pitch end
	function Entity:SetYaw(a_Value) self.SetYawValue = a_Value end
	function Entity:SetPitch(a_Value) self.SetPitchValue = a_Value end
	function Entity:TeleportToCoords(a_X, a_Y, a_Z) self.Teleported = { x = a_X, y = a_Y, z = a_Z } end
	function Entity:TeleportToEntity(a_Target) self.TeleportedToEntity = a_Target:GetName() end
	function Entity:MoveToWorld(a_World, a_SendRespawn, a_Position)
		self.MovedToWorld = { world = a_World, position = a_Position }
		self.World = a_World
	end
	return Entity
end

local function MakePlayer(a_ID, a_Name, a_X, a_Y, a_Z, a_World)
	local Player = MakeEntity(a_ID, a_Name, a_X, a_Y, a_Z, a_World)
	function Player:IsPlayer() return true end
	return Player
end

local Origin = function (a_X, a_Y, a_Z)
	return
	{
		GetPosition = function () return { x = a_X, y = a_Y, z = a_Z } end,
		GetWorld = function () return nil end,
	}
end






-- Form 2: tp <x> <y> <z> resolves "~" against the executor ---------------------

local Alice = MakePlayer(1, "Alice", 10.5, 64, 10.5)
Messages = {}
local Ok, Message, Count = HandleTPCommand({ "tp", "~", "~5", "~-1" }, Alice, nil, Origin(0, 0, 0))
CheckEquals(Ok, true, "form 2 returns true")
Check(Alice.Teleported ~= nil, "form 2 teleports the executor")
CheckClose(Alice.Teleported.x, 10.5, "form 2 resolves ~ against the executor x")
CheckClose(Alice.Teleported.y, 69, "form 2 resolves ~5 against the executor y")
CheckClose(Alice.Teleported.z, 9.5, "form 2 resolves ~-1 against the executor z")
CheckEquals(Count, 1, "form 2 success count")
Check(#Messages == 1 and Messages[1]:find("You teleported to", 1, true) ~= nil, "form 2 feedback")

-- Form 2 with rotation: "~" is relative to the executor's own rotation.
Alice.Teleported = nil
HandleTPCommand({ "tp", "0", "64", "0", "~90", "~-10" }, Alice, nil, Origin(0, 0, 0))
CheckClose(Alice.SetYawValue, 100, "form 2 rotation ~ is relative to the executor yaw")
CheckClose(Alice.SetPitchValue, 10, "form 2 rotation ~ is relative to the executor pitch")

-- Form 2 without an executor (command block / console):
Messages = {}
local _, Msg, Cnt = HandleTPCommand({ "tp", "0", "64", "0" }, nil, nil, Origin(0, 0, 0))
Check(Msg ~= nil and Msg:find("No player was found to teleport", 1, true) ~= nil,
	"form 2 without an executor fails")
CheckEquals(Cnt, 0, "form 2 without an executor has success count 0")

-- Form 4: every target resolves "~" against its OWN position -------------------

local Pig = MakeEntity(2, "Pig", 0, 64, 0)
local Cow = MakeEntity(3, "Cow", 100, 70, 100)
ResolveTargets = function () return { Pig, Cow } end
Messages = {}
HandleTPCommand({ "tp", "@e", "~", "~5", "~" }, Alice, nil, Origin(0, 0, 0))
CheckClose(Pig.Teleported.y, 69, "form 4 uses the first target's own y")
CheckClose(Cow.Teleported.y, 75, "form 4 uses the second target's own y")
CheckClose(Cow.Teleported.x, 100, "form 4 keeps an absolute x")

-- Form 4 rotation: each target's own yaw/pitch.
Pig.SetYawValue = nil
Cow.SetYawValue = nil
HandleTPCommand({ "tp", "@e", "0", "64", "0", "~10", "~" }, Alice, nil, Origin(0, 0, 0))
CheckClose(Pig.SetYawValue, 20, "form 4 rotation ~ is relative to the first target")
CheckClose(Cow.SetYawValue, 20, "form 4 rotation ~ is relative to the second target")

-- Form 4 range check is per target: Pig is fine, Cow (x = 30000000) is out of range.
local Far = MakeEntity(4, "Far", 29999999, 64, 0)
ResolveTargets = function () return { Pig, Far } end
Messages = {}
Pig.Teleported = nil
Far.Teleported = nil
Ok, Message, Count = HandleTPCommand({ "tp", "@e", "~5", "~", "~" }, Alice, nil, Origin(0, 0, 0))
Check(Pig.Teleported ~= nil, "form 4 teleports the in-range target")
CheckEquals(Far.Teleported, nil, "form 4 refuses the out-of-range target")
CheckEquals(Count, 1, "form 4 success count counts only the teleported targets")

-- Form 4 syntax error: nobody is teleported (the player path reports through SendMessageFailure).
Pig.Teleported = nil
Messages = {}
local OkBad, MsgBad, CntBad = HandleTPCommand({ "tp", "@e", "abc", "~", "~" }, Alice, nil, Origin(0, 0, 0))
CheckEquals(Pig.Teleported, nil, "form 4 with a bad coordinate teleports nobody")
Check(HasMessage("not a valid number"), "form 4 bad coordinate reason")
CheckEquals(CntBad, 0, "form 4 bad coordinate has success count 0")

-- Form 3: tp <target> <destination> -------------------------------------------

local Bob = MakePlayer(5, "Bob", 50.5, 65, 50.5)
ResolveTargets = function (a_Token)
	if (a_Token == "Alice") then
		return { Alice }
	end
	if (a_Token == "@a") then
		return { Alice, Bob }
	end
	return { Bob }
end
Messages = {}
Alice.TeleportedToEntity = nil
Ok, Message, Count = HandleTPCommand({ "tp", "@a", "@s" }, Alice, nil, Origin(0, 0, 0))
Check(Alice.TeleportedToEntity ~= nil, "form 3 teleports the first target to the destination entity")
Check(Count >= 1, "form 3 success count")

-- A target in another dimension fails individually (spec section 2.5).
local NetherPig = MakeEntity(6, "NetherPig", 0, 64, 0, "world_nether")
ResolveTargets = function (a_Token)
	if (a_Token == "@a") then
		return { Alice, NetherPig }
	end
	return { Bob }
end
Messages = {}
Alice.TeleportedToEntity = nil
NetherPig.TeleportedToEntity = nil
local OkDim, MsgDim, CntDim = HandleTPCommand({ "tp", "@a", "Bob" }, Alice, nil, Origin(0, 0, 0))
Check(Alice.TeleportedToEntity ~= nil, "form 3 still teleports the same-dimension target")
CheckEquals(NetherPig.TeleportedToEntity, nil, "form 3 refuses the other-dimension target")
Check(HasMessage("not in the same dimension"), "form 3 reports the other-dimension failure")

-- Form 1: tp <destination> ----------------------------------------------------

Messages = {}
Alice.TeleportedToEntity = nil
Ok, Message, Count = HandleTPCommand({ "tp", "Bob" }, Alice, nil, Origin(0, 0, 0))
Check(Alice.TeleportedToEntity == "Bob", "form 1 teleports the executor to the destination entity")
CheckEquals(Count, 1, "form 1 success count")
Check(#Messages >= 1 and Messages[1]:find("You teleported to Bob", 1, true) ~= nil, "form 1 feedback")

-- Form 1 with -h does not notify the destination.
Messages = {}
HandleTPCommand({ "tp", "Bob", "-h" }, Alice, nil, Origin(0, 0, 0))
local ToldBob = false
for _, Line in ipairs(Messages) do
	if (Line:find("teleported to you", 1, true) ~= nil) then
		ToldBob = true
	end
end
Check((not ToldBob), "form 1 -h does not tell the destination")

-- Form 1 to self is refused.
ResolveTargets = function (a_Token)
	if (a_Token == "Alice") then
		return { Alice }
	end
	return { Bob }
end
Messages = {}
local OkSelf, MsgSelf, CntSelf = HandleTPCommand({ "tp", "Alice" }, Alice, nil, Origin(0, 0, 0))
Check(HasMessage("Y' can't teleport to yerself"), "form 1 to self is refused")

-- The destination must resolve to a single entity.
ResolveTargets = function () return { Bob, Pig } end
Messages = {}
local OkMulti, MsgMulti, CntMulti = HandleTPCommand({ "tp", "Bob" }, Alice, nil, Origin(0, 0, 0))
Check(HasMessage("single entity"), "a multi-entity destination is refused")
CheckEquals(CntMulti, 0, "a refused destination has success count 0")

-- No target matched.
ResolveTargets = function () return nil, "No target matched the selector \"@e\"" end
Messages = {}
local OkEmpty, MsgEmpty, CntEmpty = HandleTPCommand({ "tp", "@e", "0", "64", "0" }, Alice, nil, Origin(0, 0, 0))
Check(HasMessage("No target matched"), "an empty selector fails")
CheckEquals(CntEmpty, 0, "an empty selector has success count 0")

-- Console path: the feedback comes back as the returned string.
ResolveTargets = function () return { Cow } end
local OkConsole, MsgConsole, CntConsole = HandleTPCommand({ "tp", "@e", "0", "64", "0" }, nil, nil, Origin(0, 0, 0))
Check(MsgConsole ~= nil and MsgConsole:find("Teleported Cow", 1, true) ~= nil, "console feedback is returned")
CheckEquals(CntConsole, 1, "console success count")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
