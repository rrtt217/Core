-- test_xp_command.lua
--
-- Tests for Core's vanilla 1.12.2 /xp: the <amount>[L] parser, the level-to-total-experience maths and
-- the handler's target handling.
--
-- Verified specification: specs/commands/vanilla-1.12.2-xp-command.md (parent repository).
-- The cases pin what is easy to get wrong: points and levels are different things ("3L" is levels),
-- the level change keeps the progress inside the level, a level below 0 clamps to 0, and cPlayer only
-- stores the total experience so the conversion has to use the Experience page's formulas.
--
-- Invariants:
--   * ParseXpAmount(), GetXpForLevel() and GetTotalXpForLevelChange() are pure functions.
--   * The handler never calls DeltaExperience() for an "L" amount, and never SetCurrentExperience()
--     for a points amount.
--   * A refused command reaches no player.
--
-- Run with:  lua tests/test_xp_command.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_xp.lua")
dofile(ScriptDir .. "/../cmd_xp.lua")

-- luacheck: ignore 131
-- luacheck: new globals MakeSelectorContext ResolveTargets ApplyToTargets
-- luacheck: globals HandleXPCommand HandleConsoleXP

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






-- <amount>[L] parsing --------------------------------------------------------

local Amount = ParseXpAmount("7")
Check(Amount ~= nil and Amount.Points == 7 and Amount.Levels == nil, "parses experience points")

Amount = ParseXpAmount("+7")
Check(Amount ~= nil and Amount.Points == 7, "accepts a leading plus")

Amount = ParseXpAmount("-5")
Check(Amount ~= nil and Amount.Points == -5, "accepts negative points (see spec section 4.1)")

Amount = ParseXpAmount("3L")
Check(Amount ~= nil and Amount.Levels == 3 and Amount.Points == nil, "parses experience levels")

Amount = ParseXpAmount("-2147483648L")
Check(Amount ~= nil and Amount.Levels == -2147483648, "accepts INT32_MIN levels")

Amount = ParseXpAmount("2147483647")
Check(Amount ~= nil and Amount.Points == 2147483647, "accepts INT32_MAX points")

Check(ParseXpAmount("2147483648") == nil, "rejects points beyond INT32_MAX")
Check(ParseXpAmount("-2147483649") == nil, "rejects points below INT32_MIN")
Check(ParseXpAmount("1.5") == nil, "rejects a fractional amount")
Check(ParseXpAmount("L") == nil, "rejects a bare L")
Check(ParseXpAmount("3LL") == nil, "rejects a doubled L")
Check(ParseXpAmount("abc") == nil, "rejects a non-number")
Check(ParseXpAmount("") == nil, "rejects an empty amount")
Check(ParseXpAmount(nil) == nil, "rejects a missing amount")

-- Level -> total experience (Experience page, 1.12.2 revision) --------------

local ExpectedTotals =
{
	[0] = 0,
	[1] = 7,
	[2] = 16,
	[16] = 352,
	[17] = 394,
	[18] = 441,
	[31] = 1507,
	[32] = 1628,
	[65] = 10670,
}

for Level, Expected in pairs(ExpectedTotals) do
	CheckEquals(GetXpForLevel(Level), Expected, "total experience for level " .. Level)
end

-- Level changes --------------------------------------------------------------

CheckEquals(GetTotalXpForLevelChange(0, 0, 3), 27, "three levels from level 0 keep no progress")
CheckEquals(GetTotalXpForLevelChange(0, 0, 0), 0, "zero levels from level 0")
CheckEquals(GetTotalXpForLevelChange(10, 0, 0), 160, "zero levels keeps the total")

-- Level 5 -> 6 needs 19 XP; half way is 9.5, rounded to 10:
CheckEquals(GetTotalXpForLevelChange(5, 0.5, 1), 82, "one level keeps the progress inside the level")
CheckEquals(GetTotalXpForLevelChange(5, 0.5, -1), 48, "one level down keeps the progress")
CheckEquals(GetTotalXpForLevelChange(2, 0.5, -3), 0, "level below 0 clamps to 0")
CheckEquals(GetTotalXpForLevelChange(0, 0.5, -1), 0, "level -1 clamps to 0")

-- Handler --------------------------------------------------------------------

-- Mirrors core_functions.lua: a player receives the message and nil is returned, the console gets the
-- message back so the command output can carry it.
local Messages = {}
SendMessageFailure = function (a_Player, a_Message)
	table.insert(Messages, "failure: " .. tostring(a_Message))
	if (a_Player ~= nil) then
		return nil
	end
	return a_Message
end
SendMessageSuccess = function (a_Player, a_Message)
	table.insert(Messages, "success: " .. tostring(a_Message))
	if (a_Player ~= nil) then
		return nil
	end
	return a_Message
end

MakeSelectorContext = function () return {} end
ApplyToTargets = function (a_Targets, a_Action)
	for _, Target in ipairs(a_Targets) do
		a_Action(Target)
	end
end

local function MakeFakePlayer(a_Name, a_Level, a_Progress, a_Xp)
	local Player = { Name = a_Name, Level = a_Level, Progress = a_Progress, Xp = a_Xp }
	function Player:GetName()
		return self.Name
	end
	function Player:GetXpLevel()
		return self.Level
	end
	function Player:GetXpPercentage()
		return self.Progress
	end
	function Player:GetCurrentXp()
		return self.Xp
	end
	function Player:DeltaExperience(a_Delta)
		self.Delta = a_Delta
		return self.Xp + a_Delta
	end
	function Player:SetCurrentExperience(a_Total)
		self.SetTo = a_Total
		return true
	end
	return Player
end

local Alice = MakeFakePlayer("Alice", 5, 0.5, 100)
ResolveTargets = function (a_Token)
	if (a_Token == "@none") then
		return {}
	end
	return { Alice }
end

Messages = {}
local Ok, Message, Count = HandleXPCommand({ "xp", "5", "Alice" }, nil, nil, {})
CheckEquals(Ok, true, "xp returns true")
CheckEquals(Count, 1, "xp reports one affected player")
CheckEquals(Alice.Delta, 5, "a points amount reaches DeltaExperience")
CheckEquals(Alice.SetTo, nil, "a points amount does not call SetCurrentExperience")
Check(Message == "Given 5 experience to Alice", "console feedback for points")
Check(#Messages == 0, "console feedback does not go through SendMessage*")

Alice.SetTo = nil
Ok, Message, Count = HandleXPCommand({ "xp", "3L", "Alice" }, nil, nil, {})
CheckEquals(Alice.SetTo, GetTotalXpForLevelChange(5, 0.5, 3), "a level amount reaches SetCurrentExperience")
CheckEquals(Alice.Delta, 5, "a level amount does not call DeltaExperience again")
Check(Message == "Given 3 levels to Alice", "console feedback for levels")

Alice.SetTo = nil
Ok, Message, Count = HandleXPCommand({ "xp", "1L", "Alice" }, nil, nil, {})
Check(Message == "Given 1 level to Alice", "singular level feedback")

Ok, Message, Count = HandleXPCommand({ "xp", "5", "@none" }, nil, nil, {})
CheckEquals(Count, 0, "no targets means success count 0")
Check(Message ~= nil and Message:find("No player was found", 1, true) ~= nil,
	"no targets reports No player was found")

Ok, Message, Count = HandleXPCommand({ "xp", "5" }, nil, nil, {})
CheckEquals(Count, 0, "a command block without a player argument does nothing")
Check(Message ~= nil and Message:find("No player was found", 1, true) ~= nil,
	"a command block without a player argument reports No player was found")

Ok, Message, Count = HandleXPCommand({ "xp", "abc", "Alice" }, nil, nil, {})
Check(Message ~= nil and Message:find("Invalid amount", 1, true) ~= nil, "an invalid amount is reported")

-- In-game path: the executor is the default target and feedback goes to the player.
local Bob = MakeFakePlayer("Bob", 0, 0, 0)
ResolveTargets = function () return { Bob } end
Messages = {}
Ok, Message, Count = HandleXPCommand({ "xp", "7" }, Bob, nil, {})
CheckEquals(Count, 1, "in-game xp without a player argument targets the executor")
CheckEquals(Bob.Delta, 7, "the executor receives the points")
Check(Message == nil, "in-game feedback is not returned as console output")
Check(#Messages == 1 and Messages[1] == "success: Given 7 experience to Bob",
	"in-game feedback is sent to the executor")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
