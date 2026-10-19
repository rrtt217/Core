-- test_spawnpoint_command.lua
--
-- Tests for Core's /spawnpoint: the 1.12.2 coordinate range check and the failure feedback.
--
-- Verified specification: specs/commands/vanilla-1.12.2-spawnpoint-command.md (parent repository).
-- The cases pin the two defects this branch fixes: an out-of-range <y> used to be stored as-is, and a
-- malformed coordinate used to produce an *empty* failure message (ParseCommandCoords() returns
-- "nil, reason", but the handler read the reason from a fourth value).
--
-- Invariants:
--   * A refused position never reaches SetRespawnPosition().
--   * Every refusal produces a non-empty message.
--   * The range follows the 1.12.2 page: x/z inclusive ±30,000,000, y inclusive 0..256.
--
-- Run with:  lua tests/test_spawnpoint_command.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../cmd_spawnpoint.lua")

-- luacheck: ignore 131
-- luacheck: new globals cRoot Vector3i ResolveTargets ApplyToTargets MakeSelectorContext
-- luacheck: new globals SendMessage SendMessageFailure SendMessageSuccess

local NumPassed = 0
local NumFailed = 0
local Messages = {}

local function Check(a_Condition, a_Message)
	if (a_Condition) then
		NumPassed = NumPassed + 1
	else
		NumFailed = NumFailed + 1
		print("FAIL: " .. a_Message)
	end
end

local function HasMessage(a_Text)
	for _, Line in ipairs(Messages) do
		if (Line:find(a_Text, 1, true) ~= nil) then
			return true
		end
	end
	return false
end

Vector3i = function (a_X, a_Y, a_Z) return { x = a_X, y = a_Y, z = a_Z } end

SendMessage = function (a_Player, a_Message) table.insert(Messages, "info: " .. tostring(a_Message)) end
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
ResolveTargets = function () return nil, "unused" end
ApplyToTargets = function (a_Targets, a_Action)
	for _, Target in ipairs(a_Targets) do
		a_Action(Target)
	end
	return #a_Targets
end

local World = { Name = "world" }
function World:GetName() return self.Name end

local Player = { Name = "TestBot", Respawn = nil }
function Player:GetName() return self.Name end
function Player:GetPosX() return 5 end
function Player:GetPosY() return 64 end
function Player:GetPosZ() return 5 end
function Player:GetWorld() return World end
function Player:SetRespawnPosition(a_Position, a_World)
	self.Respawn = { x = a_Position.x, y = a_Position.y, z = a_Position.z, world = a_World }
end

cRoot = {
	Get = function ()
		return {
			GetDefaultWorld = function () return World end,
			GetWorld = function (self, a_Name) if (a_Name == "world") then return World end return nil end,
			FindAndDoWithPlayer = function (self, a_Name, a_Callback)
				if (a_Name == "TestBot") then
					a_Callback(Player)
					return true
				end
				return false
			end,
		}
	end,
}

local Origin = {
	GetWorld = function () return World end,
	GetPosition = function () return { x = 10, y = 20, z = 30 } end,
}

local function Run(a_Split)
	Messages = {}
	Player.Respawn = nil
	local Ok, Response, Count = HandleSpawnPointCommand(a_Split, Player, nil, Origin)
	return Response, Count
end

-- Accepted positions ---------------------------------------------------------

Run({ "spawnpoint", "TestBot", "1", "64", "1" })
Check(Player.Respawn ~= nil and Player.Respawn.x == 1 and Player.Respawn.y == 64 and Player.Respawn.z == 1,
	"a valid position is stored")
Check(HasMessage("Set the spawn point of player \"TestBot\" to (1, 64, 1)"), "a valid position is reported")

Run({ "spawnpoint", "TestBot", "1", "0", "1" })
Check((Player.Respawn ~= nil) and (Player.Respawn.y == 0), "y = 0 is accepted")

Run({ "spawnpoint", "TestBot", "1", "256", "1" })
Check((Player.Respawn ~= nil) and (Player.Respawn.y == 256), "y = 256 is accepted (1.12.2 page: 0..256)")

Run({ "spawnpoint", "TestBot", "30000000", "64", "-30000000" })
Check((Player.Respawn ~= nil) and (Player.Respawn.x == 30000000), "x/z = ±30,000,000 are accepted (inclusive)")

Run({ "spawnpoint", "TestBot", "~", "~", "~" })
Check((Player.Respawn ~= nil) and (Player.Respawn.x == 10) and (Player.Respawn.y == 20) and
	(Player.Respawn.z == 30), "~ resolves against the command origin")

-- Refused positions ----------------------------------------------------------

Run({ "spawnpoint", "TestBot", "1", "300", "1" })
Check(Player.Respawn == nil, "y = 300 is refused")
Check(HasMessage("The y coordinate must be between 0 and 256"), "y = 300 reports the y range")

Run({ "spawnpoint", "TestBot", "1", "-1", "1" })
Check((Player.Respawn == nil) and HasMessage("The y coordinate must be between 0 and 256"),
	"y = -1 is refused")

Run({ "spawnpoint", "TestBot", "1", "257", "1" })
Check((Player.Respawn == nil) and HasMessage("The y coordinate must be between 0 and 256"),
	"y = 257 is refused")

Run({ "spawnpoint", "TestBot", "30000001", "64", "0" })
Check((Player.Respawn == nil) and HasMessage("between -30,000,000 and 30,000,000"),
	"x = 30,000,001 is refused")

Run({ "spawnpoint", "TestBot", "0", "64", "-30000001" })
Check((Player.Respawn == nil) and HasMessage("between -30,000,000 and 30,000,000"),
	"z = -30,000,001 is refused")

-- The malformed-coordinate regression: the message must not be empty -------------

Run({ "spawnpoint", "TestBot", "a", "64", "b" })
Check(Player.Respawn == nil, "a malformed coordinate is refused")
Check(HasMessage("not a valid number"), "a malformed coordinate names the offending value")

local EmptyFailure = false
for _, Line in ipairs(Messages) do
	if (Line == "failure: " or Line == "failure: nil") then
		EmptyFailure = true
	end
end
Check((not EmptyFailure), "a refused position never reports an empty message")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
