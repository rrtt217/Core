-- test_scoreboard_reset.lua
--
-- Tests for Core's /scoreboard players reset when no objective is named: the handler must remove the
-- target's score from every objective.
--
-- Verified specification: specs/commands/vanilla-1.12.2-scoreboard-reset-fix.md (parent repository).
-- The regression this pins: the ResetAllObjectives() closure declared its parameter as "Objective" but
-- read "Objetive", so `/scoreboard players reset <player>` raised
--   cmd_scoreboard.lua:130: attempt to index a nil value (global 'Objetive')
-- and the command answered with the engine's generic "Something went wrong while executing command".
--
-- Invariants:
--   * One ResetScore() call per objective, with the target's name.
--   * The handler returns true and reports success when it ran.
--   * Naming an objective still resets only that objective; an unknown one is still refused.
--
-- Run with:  lua tests/test_scoreboard_reset.lua   (from the plugin folder)

-- luacheck: ignore 131
-- luacheck: new globals cObjective cScoreboard
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess
-- luacheck: globals HandleScoreboardPlayersCommand

-- cmd_scoreboard.lua builds its criteria and slot tables from these enums at load time, so the fake
-- enums have to exist before the file is loaded:
cObjective =
{
	otAchievement = 1,
	otDeathCount = 2,
	otDummy = 3,
	otHealth = 4,
	otPlayerKillCount = 5,
	otStat = 6,
	otStatBlockMine = 7,
	otStatEntityKill = 8,
	otStatEntityKilledBy = 9,
	otStatItemCraft = 10,
	otStatItemUse = 11,
	otTotalKillCount = 12,
}
cScoreboard =
{
	dsList = 0,
	dsSidebar = 1,
	dsName = 2,
	dsCount = 3,
}

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../cmd_scoreboard.lua")

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

-- Stubs for core_functions.lua's message helpers. With a player the message is delivered and nil is
-- returned, so the recorded text is what the assertions inspect.
SendMessage = function (a_Player, a_Message)
	table.insert(Messages, "info: " .. tostring(a_Message))
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

-- Only the methods the reset path uses; every other handler branch stays unused.
local function MakeObjective(a_Name)
	local Objective = { Name = a_Name, Reset = {} }
	function Objective:GetName() return self.Name end
	function Objective:GetDisplayName() return self.Name end
	function Objective:ResetScore(a_Target) table.insert(self.Reset, a_Target) end
	return Objective
end

local Objectives = {}
local Scoreboard = {}
function Scoreboard:GetObjective(a_Name)
	for _, Objective in ipairs(Objectives) do
		if (Objective:GetName() == a_Name) then
			return Objective
		end
	end
	return nil
end
function Scoreboard:ForEachObjective(a_Callback)
	for _, Objective in ipairs(Objectives) do
		a_Callback(Objective)
	end
end

local World = {}
function World:GetScoreBoard() return Scoreboard end

local Player = {}
function Player:GetName() return "TestBot" end
function Player:GetWorld() return World end

local function Run(a_Split)
	Messages = {}
	return HandleScoreboardPlayersCommand(a_Split, Player)
end

-- resetting every objective (the regression) ---------------------------------

Objectives = { MakeObjective("alpha"), MakeObjective("beta") }
local Called, HandlerOk = pcall(Run, { "scoreboard", "players", "reset", "TestBot" })
Check(Called, "reset without an objective must not raise a Lua error (" .. tostring(HandlerOk) .. ")")
Check((not Called) or (HandlerOk == true), "reset without an objective returns true")
Check(#Objectives[1].Reset == 1, "the first objective is reset once")
Check(Objectives[1].Reset[1] == "TestBot", "the first objective is reset for the target")
Check(#Objectives[2].Reset == 1, "the second objective is reset once")
Check(Objectives[2].Reset[1] == "TestBot", "the second objective is reset for the target")
Check(HasMessage("success:"), "reset without an objective reports success")
Check(not HasMessage("failure:"), "reset without an objective reports no failure")

-- resetting one named objective ----------------------------------------------

Objectives = { MakeObjective("alpha"), MakeObjective("beta") }
Called, HandlerOk = pcall(Run, { "scoreboard", "players", "reset", "TestBot", "beta" })
Check(Called, "reset with an objective must not raise a Lua error (" .. tostring(HandlerOk) .. ")")
Check((not Called) or (HandlerOk == true), "reset with an objective returns true")
Check(#Objectives[1].Reset == 0, "a named objective leaves the other objectives alone")
Check(#Objectives[2].Reset == 1, "the named objective is reset once")
Check(Objectives[2].Reset[1] == "TestBot", "the named objective is reset for the target")

-- an unknown objective is still refused ---------------------------------------

Objectives = { MakeObjective("alpha") }
Called, HandlerOk = pcall(Run, { "scoreboard", "players", "reset", "TestBot", "nope" })
Check(Called, "an unknown objective must not raise a Lua error (" .. tostring(HandlerOk) .. ")")
Check(HasMessage('Unknown objective "nope"'), "an unknown objective is reported")
Check(#Objectives[1].Reset == 0, "an unknown objective resets nothing")

-- a missing target reports the usage ------------------------------------------

Objectives = {}
Called, HandlerOk = pcall(Run, { "scoreboard", "players", "reset" })
Check(Called, "a missing target must not raise a Lua error (" .. tostring(HandlerOk) .. ")")
Check(HasMessage("/scoreboard players reset"), "a missing target reports the usage")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
