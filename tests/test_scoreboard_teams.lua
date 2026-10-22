-- test_scoreboard_teams.lua
--
-- Tests for Core's /scoreboard teams subcommands (1.12.2 shape) and for the display-slot table that the
-- same branch touches.
--
-- Verified specification: specs/commands/vanilla-1.12.2-scoreboard-teams.md (parent repository), whose
-- behaviour comes from the Minecraft Wiki "Scoreboard" page at its 2017-10-06 revision (rev 1156283, the
-- page as it stood after 1.12.2 and before the 1.13 command rework).
--
-- Invariants:
--   * add/remove/empty/join/leave/list/option exist, refuse a missing or unknown team, and report every
--     refusal with a message (no silent failure, no Lua error).
--   * A team created through the command sees invisible teammates (the 1.12.2 default) and keeps the
--     engine's player -> team pointer consistent: SetTeam() is used for online players, so removing the
--     roster or the team never leaves a dangling cTeam pointer behind.
--   * Leaving is a partial success in 1.12.2 (a target that is on no team does not abort the others).
--   * The four option keys this engine has no fields for are refused by name; friendlyfire and
--     seeFriendlyInvisibles are stored.
--   * "count" is not a display slot (it used to reach cScoreboard.dsCount and index past m_Display), and
--     an unknown objective / a missing slot no longer raises.
--
-- Run with:  lua tests/test_scoreboard_teams.lua   (from the plugin folder)

-- luacheck: ignore 131
-- luacheck: new globals cObjective cScoreboard cRoot
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess
-- luacheck: globals ResolveTargets MakeSelectorContext GetTargetName
-- luacheck: globals HandleScoreboardTeamsCommand HandleConsoleScoreboardTeams
-- luacheck: globals HandleScoreboardObjectivesCommand

-- cmd_scoreboard.lua builds its criteria and slot tables from these enums at load time:
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
dofile(ScriptDir .. "/../command_scoreboard.lua")
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

local function CheckEquals(a_Actual, a_Expected, a_Message)
	Check(
		a_Actual == a_Expected,
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end

local function HasMessage(a_Text)
	for _, Line in ipairs(Messages) do
		if (Line:find(a_Text, 1, true) ~= nil) then
			return true
		end
	end
	return false
end

-- Stubs ----------------------------------------------------------------------

SendMessage = function (a_Player, a_Message)
	table.insert(Messages, "info: " .. tostring(a_Message))
	if (a_Player ~= nil) then return nil end
	return a_Message
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

-- The real selector layer touches worlds; these tests only need to know that a selector token reaches it
-- and that whatever it returns is put on the team.
local SelectorMatches = {}
MakeSelectorContext = function () return { World = nil } end
ResolveTargets = function (a_Token)
	local Matches = SelectorMatches[a_Token]
	if (Matches == nil) then
		return nil, 'No target matched the selector "' .. a_Token .. '"'
	end
	return Matches
end
GetTargetName = function (a_Entity)
	return a_Entity:GetName()
end

-- Fake cTeam: the state the command writes, nothing else.
local function MakeTeam(a_Name, a_DisplayName)
	local Team =
	{
		Name = a_Name,
		DisplayName = a_DisplayName,
		Players = {},
		FriendlyFire = true,
		SeeFriendlyInvisible = false,
		Color = "",
		NameTagVisibility = "always",
		CollisionRule = "always",
		DeathMessageVisibility = "always",
	}
	function Team:GetName() return self.Name end
	function Team:GetDisplayName() return self.DisplayName end
	function Team:GetNumPlayers() return #self.Players end
	function Team:HasPlayer(a_PlayerName)
		for _, Name in ipairs(self.Players) do
			if (Name == a_PlayerName) then return true end
		end
		return false
	end
	function Team:AddPlayer(a_PlayerName)
		if (self:HasPlayer(a_PlayerName)) then return false end
		table.insert(self.Players, a_PlayerName)
		return true
	end
	function Team:RemovePlayer(a_PlayerName)
		for Index, Name in ipairs(self.Players) do
			if (Name == a_PlayerName) then
				table.remove(self.Players, Index)
				return true
			end
		end
		return false
	end
	function Team:Reset() self.Players = {} end
	function Team:SetFriendlyFire(a_Value) self.FriendlyFire = a_Value end
	function Team:AllowsFriendlyFire() return self.FriendlyFire end
	function Team:SetCanSeeFriendlyInvisible(a_Value) self.SeeFriendlyInvisible = a_Value end
	function Team:CanSeeFriendlyInvisible() return self.SeeFriendlyInvisible end
	function Team:SetColor(a_Value) self.Color = a_Value end
	function Team:GetColor() return self.Color end
	function Team:SetNameTagVisibility(a_Value) self.NameTagVisibility = a_Value end
	function Team:GetNameTagVisibility() return self.NameTagVisibility end
	function Team:SetCollisionRule(a_Value) self.CollisionRule = a_Value end
	function Team:GetCollisionRule() return self.CollisionRule end
	function Team:SetDeathMessageVisibility(a_Value) self.DeathMessageVisibility = a_Value end
	function Team:GetDeathMessageVisibility() return self.DeathMessageVisibility end
	return Team
end

local Teams = {}
local Objectives = {}
local DisplayCalls = {}

local Scoreboard = {}
function Scoreboard:GetTeam(a_Name) return Teams[a_Name] end
function Scoreboard:RegisterTeam(a_Name, a_DisplayName)
	if (Teams[a_Name] ~= nil) then return nil end
	local Team = MakeTeam(a_Name, a_DisplayName)
	Teams[a_Name] = Team
	return Team
end
function Scoreboard:RemoveTeam(a_Name)
	if (Teams[a_Name] == nil) then return false end
	Teams[a_Name] = nil
	return true
end
function Scoreboard:ForEachTeam(a_Callback)
	local Names = {}
	for Name in pairs(Teams) do
		table.insert(Names, Name)
	end
	table.sort(Names)
	for _, Name in ipairs(Names) do
		if (a_Callback(Teams[Name])) then return false end
	end
	return true
end
function Scoreboard:GetObjective(a_Name)
	for _, Objective in ipairs(Objectives) do
		if (Objective:GetName() == a_Name) then return Objective end
	end
	return nil
end
function Scoreboard:SetDisplay(a_Name, a_Slot)
	table.insert(DisplayCalls, { Name = a_Name, Slot = a_Slot })
end

local OnlinePlayers = {}
local World = { Name = "world" }
function World:GetName() return self.Name end
function World:GetScoreBoard() return Scoreboard end
function World:ForEachPlayer(a_Callback)
	for _, Player in ipairs(OnlinePlayers) do
		if (a_Callback(Player)) then return false end
	end
	return true
end

local OtherWorld = { Name = "other" }
function OtherWorld:GetName() return self.Name end
function OtherWorld:GetScoreBoard() return Scoreboard end

local function MakePlayer(a_Name, a_World)
	local Player = { Name = a_Name, World = a_World or World, Team = nil }
	function Player:GetName() return self.Name end
	function Player:GetWorld() return self.World end
	function Player:GetTeam() return self.Team end
	function Player:IsPlayer() return true end
	function Player:SetTeam(a_Team)
		if (self.Team == a_Team) then return end
		if (self.Team ~= nil) then
			self.Team:RemovePlayer(self.Name)
		end
		self.Team = a_Team
		if (a_Team ~= nil) then
			a_Team:AddPlayer(self.Name)
		end
	end
	return Player
end

local Root = {}
function Root:GetDefaultWorld() return World end
function Root:FindAndDoWithPlayer(a_Name, a_Callback)
	for _, Player in ipairs(OnlinePlayers) do
		if (Player:GetName() == a_Name) then
			a_Callback(Player)
			return true
		end
	end
	return false
end
cRoot =
{
	Get = function () return Root end,
}

local ConsoleOrigin =
{
	GetPlayer = function () return nil end,
	GetWorld = function () return World end,
}

local function ResetUniverse()
	Teams = {}
	Objectives = {}
	DisplayCalls = {}
	Messages = {}
	OnlinePlayers = {}
	SelectorMatches = {}
end

local function AddObjective(a_Name, a_DisplayName)
	local Objective = { Name = a_Name, DisplayName = a_DisplayName or a_Name }
	function Objective:GetName() return self.Name end
	function Objective:GetDisplayName() return self.DisplayName end
	table.insert(Objectives, Objective)
	return Objective
end

-- Runs one command through the real handler; a Lua error is recorded as a failed check instead of
-- aborting the test run.
local function Run(a_Split, a_Player, a_Origin)
	Messages = {}
	local Called, Ok, Response, Count = pcall(HandleScoreboardTeamsCommand, a_Split, a_Player, nil, a_Origin)
	Check(Called, "the teams handler must not raise (" .. tostring(Ok) .. ")")
	if (not Called) then return nil, nil, nil end
	return Ok, Response, Count
end

local function RunConsole(a_Split)
	Messages = {}
	local Called, Ok, Response, Count = pcall(HandleConsoleScoreboardTeams, a_Split, nil, nil, ConsoleOrigin)
	Check(Called, "the console teams handler must not raise (" .. tostring(Ok) .. ")")
	if (not Called) then return nil, nil, nil end
	return Ok, Response, Count
end

-- Pure parsing ---------------------------------------------------------------

CheckEquals(ValidateScoreboardName("red"), nil, "a short team name is accepted")
CheckEquals(ValidateScoreboardName(string.rep("a", 16)), nil, "a 16-character team name is accepted")
Check(ValidateScoreboardName(string.rep("a", 17)) ~= nil, "a 17-character team name is refused")
CheckEquals(ValidateScoreboardDisplayName(string.rep("d", 32)), nil, "a 32-character display name is accepted")
Check(ValidateScoreboardDisplayName(string.rep("d", 33)) ~= nil, "a 33-character display name is refused")
CheckEquals(JoinScoreboardDisplayName({ "teams", "add", "red", "Red", "Team" }, 4), "Red Team",
	"the display name is the rest of the line")
CheckEquals(JoinScoreboardDisplayName({ "teams", "add", "red" }, 4), nil, "no trailing token means no display name")
CheckEquals(ParseScoreboardTeamBool("true"), true, "true parses")
CheckEquals(ParseScoreboardTeamBool("false"), false, "false parses")
CheckEquals(ParseScoreboardTeamBool("TRUE"), nil, "TRUE is not the documented spelling")
CheckEquals(ParseScoreboardTeamBool("1"), nil, "1 is not a boolean")
CheckEquals(ParseScoreboardTeamOption("friendlyfire", "false").Value, false, "friendlyfire parses")
CheckEquals(ParseScoreboardTeamOption("seeFriendlyInvisibles", "true").Value, true, "seeFriendlyInvisibles parses")
CheckEquals(ParseScoreboardTeamOption("color", "red").Value, "red", "a color name parses")
CheckEquals(ParseScoreboardTeamOption("color", "reset").Value, "reset", "color reset parses")
local Option, Reason = ParseScoreboardTeamOption("color", "bogus")
CheckEquals(Option, nil, "an unknown color name is refused")
Check(Reason ~= nil and Reason:find("color name", 1, true) ~= nil, "the color refusal names the accepted values")
CheckEquals(ParseScoreboardTeamOption("nametagVisibility", "never").Value, "never", "nametagVisibility parses")
Option, Reason = ParseScoreboardTeamOption("nametagVisibility", "sometimes")
CheckEquals(Option, nil, "an unknown nametagVisibility value is refused")
Check(Reason ~= nil and Reason:find("hideForOwnTeam", 1, true) ~= nil, "the nametagVisibility refusal lists the values")
CheckEquals(ParseScoreboardTeamOption("collisionRule", "pushOtherTeams").Value, "pushOtherTeams", "collisionRule parses")
Option, Reason = ParseScoreboardTeamOption("collisionRule", "sometimes")
CheckEquals(Option, nil, "an unknown collisionRule value is refused")
Check(Reason ~= nil and Reason:find("pushOwnTeam", 1, true) ~= nil, "the collisionRule refusal lists the values")
Option, Reason = ParseScoreboardTeamOption("deathMessageVisibility", "never")
CheckEquals(Option, nil, "deathMessageVisibility is still refused")
Check(Reason ~= nil and Reason:find("not supported", 1, true) ~= nil, "the deathMessageVisibility refusal names the engine gap")
Option, Reason = ParseScoreboardTeamOption("bogus", "x")
CheckEquals(Option, nil, "an unknown option is refused")
Check(Reason ~= nil and Reason:find("Unknown team option", 1, true) ~= nil, "an unknown option is reported as such")
CheckEquals(#GetScoreboardTeamTargets({ "scoreboard", "teams", "join", "red", "a", "b" }, 5), 2,
	"join takes every trailing token as a target")
CheckEquals(#GetScoreboardTeamTargets({ "scoreboard", "teams", "leave" }, 4), 0,
	"leave without targets yields an empty target list")

-- add ------------------------------------------------------------------------

ResetUniverse()
local Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
CheckEquals(Run({ "scoreboard", "teams", "add", "red" }, Sender), true, "teams add returns true")
Check(Teams.red ~= nil, "teams add creates the team")
CheckEquals(Teams.red:GetDisplayName(), "red", "the display name defaults to the team name")
CheckEquals(Teams.red:CanSeeFriendlyInvisible(), true, "a new team sees invisible teammates (1.12.2 default)")
Check(HasMessage('Team "red" has been created'), "teams add reports success")

Run({ "scoreboard", "teams", "add", "red" }, Sender)
Check(HasMessage('Team "red" already exists'), "a duplicate team is refused")

Run({ "scoreboard", "teams", "add", "blue", "Blue", "Team" }, Sender)
Check(Teams.blue ~= nil and Teams.blue:GetDisplayName() == "Blue Team", "a multi-word display name is kept")

Run({ "scoreboard", "teams", "add", string.rep("x", 17) }, Sender)
Check(HasMessage("is too long"), "an over-long team name is refused")

Run({ "scoreboard", "teams", "add", "green", string.rep("d", 33) }, Sender)
Check(Teams.green == nil and HasMessage("is too long"), "an over-long display name is refused")

Run({ "scoreboard", "teams", "add" }, Sender)
Check(Teams.red ~= nil and HasMessage("/scoreboard teams add"), "a missing name reports the usage")

-- join -----------------------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
local Other = MakePlayer("Second")
OnlinePlayers = { Sender, Other }
Teams = { red = MakeTeam("red", "red") }

Run({ "scoreboard", "teams", "join", "red", "TestBot" }, Sender)
Check(Sender:GetTeam() == Teams.red, "join moves the online player onto the team")
Check(Teams.red:HasPlayer("TestBot"), "join writes the roster")
Check(HasMessage('Team "red": added 1 member(s)'), "join reports the count")

Run({ "scoreboard", "teams", "join", "red", "OfflineName" }, Sender)
Check(Teams.red:HasPlayer("OfflineName"), "join accepts an offline name (1.12.2 allows it)")

SelectorMatches["@a"] = { Sender, Other }
Run({ "scoreboard", "teams", "join", "red", "@a" }, Sender)
Check(Sender:GetTeam() == Teams.red and Other:GetTeam() == Teams.red, "a selector puts every match on the team")
Check(HasMessage('Team "red": added 2 member(s)'), "a selector reports every match")

Run({ "scoreboard", "teams", "join", "blue", "TestBot" }, Sender)
Check(HasMessage('Team "blue" does not exist'), "join refuses an unknown team")

Run({ "scoreboard", "teams", "join", "red" }, Sender)
Check(Sender:GetTeam() == Teams.red, "join without targets puts the command's player on the team")

Run({ "scoreboard", "teams", "join", "red" }, nil, ConsoleOrigin)
Check(HasMessage("No entity was specified to join"), "join without targets refuses the console")

Run({ "scoreboard", "teams", "join", "red", "*" }, Sender)
Check(HasMessage("does not expose yet"), "the * target is refused (no tracked-entity list)")

Run({ "scoreboard", "teams", "join", "red", "@e[type=none]" }, Sender)
Check(HasMessage('No target matched the selector "@e[type=none]"'), "a selector with no match is reported")

local FarPlayer = MakePlayer("Far", OtherWorld)
OnlinePlayers = { Sender, FarPlayer }
Run({ "scoreboard", "teams", "join", "red", "Far" }, Sender)
Check(HasMessage("is in another world"), "a target in another world is refused")

Run({ "scoreboard", "teams", "join" }, Sender)
Check(HasMessage("/scoreboard teams join"), "join without a team reports the usage")

-- leave ----------------------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
Teams = { red = MakeTeam("red", "red") }
Sender:SetTeam(Teams.red)
Sender:SetTeam(Teams.red)
Run({ "scoreboard", "teams", "leave", "TestBot" }, Sender)
Check(Sender:GetTeam() == nil, "leave clears the online player's team pointer")
Check(not Teams.red:HasPlayer("TestBot"), "leave clears the roster")

Teams.red:AddPlayer("Ghost")
Run({ "scoreboard", "teams", "leave", "Ghost" }, Sender)
Check(not Teams.red:HasPlayer("Ghost"), "leave removes an offline name from its team")

Run({ "scoreboard", "teams", "leave", "Nobody" }, Sender)
Check(HasMessage("is not on a team"), "leave refuses a target that is on no team")

Teams.red:AddPlayer("Ghost")
Run({ "scoreboard", "teams", "leave", "Ghost", "Nobody" }, Sender)
Check(not Teams.red:HasPlayer("Ghost"), "leave still removes the target that was on a team")
Check(HasMessage("is not on a team"), "leave reports the partial failure (1.12.2 partial success)")

Sender:SetTeam(Teams.red)
Run({ "scoreboard", "teams", "leave" }, Sender)
Check(Sender:GetTeam() == nil, "leave without targets takes the command's player off the team")

Run({ "scoreboard", "teams", "leave" }, nil, ConsoleOrigin)
Check(HasMessage("No entity was specified to leave"), "leave without targets refuses the console")

-- empty ----------------------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
Teams = { red = MakeTeam("red", "red") }
Sender:SetTeam(Teams.red)
Teams.red:AddPlayer("Ghost")
Run({ "scoreboard", "teams", "empty", "red" }, Sender)
Check(Sender:GetTeam() == nil, "empty clears the online player's team pointer")
CheckEquals(Teams.red:GetNumPlayers(), 0, "empty clears the whole roster")
Check(HasMessage('Team "red" has been emptied'), "empty reports success")

Run({ "scoreboard", "teams", "empty", "red" }, Sender)
Check(HasMessage('Team "red" has no members'), "empty refuses an already empty team")

Run({ "scoreboard", "teams", "empty", "blue" }, Sender)
Check(HasMessage('Team "blue" does not exist'), "empty refuses an unknown team")

Run({ "scoreboard", "teams", "empty", "red", "extra" }, Sender)
Check(HasMessage("/scoreboard teams empty"), "empty refuses extra arguments")

-- remove ---------------------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
Teams = { red = MakeTeam("red", "red") }
Sender:SetTeam(Teams.red)
Run({ "scoreboard", "teams", "remove", "red" }, Sender)
Check(Sender:GetTeam() == nil, "remove clears the online player's team pointer first")
Check(Teams.red == nil, "remove deletes the team")
Check(HasMessage('Team "red" has been removed'), "remove reports success")

Run({ "scoreboard", "teams", "remove", "red" }, Sender)
Check(HasMessage('Team "red" does not exist'), "remove refuses an unknown team")

-- list -----------------------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
Run({ "scoreboard", "teams", "list" }, Sender)
Check(HasMessage("There are no teams on the scoreboard"), "list refuses an empty scoreboard")

Teams = { red = MakeTeam("red", "Red Team"), blue = MakeTeam("blue", "Blue Team") }
Teams.red:AddPlayer("A")
Teams.red:AddPlayer("B")
Teams.blue:AddPlayer("C")
Run({ "scoreboard", "teams", "list" }, Sender)
Check(HasMessage("DisplayName -> Name : Members"), "list prints a header")
Check(Messages[1] == "info: DisplayName -> Name : Members", "the header is delivered before the team lines")
Check(Messages[2] ~= nil and Messages[2]:find("Blue Team -> blue: 1 member(s)", 1, true) ~= nil,
	"the first team line (teams are sorted by name) follows the header")
Check(HasMessage("Blue Team -> blue: 1 member(s)"), "list prints every team")

Run({ "scoreboard", "teams", "list", "red" }, Sender)
Check(HasMessage('Team "red" has 2 member(s)'), "list <team> reports the named team")

Teams.blue:Reset()
Run({ "scoreboard", "teams", "list", "blue" }, Sender)
Check(HasMessage('Team "blue" has no members'), "list <team> refuses an empty team")

Run({ "scoreboard", "teams", "list", "green" }, Sender)
Check(HasMessage('Team "green" does not exist'), "list <team> refuses an unknown team")

Run({ "scoreboard", "teams", "list", "red", "extra" }, Sender)
Check(HasMessage("/scoreboard teams list"), "list refuses extra arguments")

-- option ---------------------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
Teams = { red = MakeTeam("red", "red") }

Run({ "scoreboard", "teams", "option", "red", "friendlyfire", "false" }, Sender)
CheckEquals(Teams.red:AllowsFriendlyFire(), false, "option friendlyfire is stored")
Check(HasMessage("friendlyfire is now false"), "option friendlyfire reports success")

Run({ "scoreboard", "teams", "option", "red", "seeFriendlyInvisibles", "false" }, Sender)
CheckEquals(Teams.red:CanSeeFriendlyInvisible(), false, "option seeFriendlyInvisibles is stored")

Run({ "scoreboard", "teams", "option", "red", "color", "blue" }, Sender)
CheckEquals(Teams.red:GetColor(), "blue", "option color is stored")
Check(HasMessage("color is now blue"), "option color reports success")

Run({ "scoreboard", "teams", "option", "red", "color", "reset" }, Sender)
CheckEquals(Teams.red:GetColor(), "", "option color reset clears the color")

Run({ "scoreboard", "teams", "option", "red", "color", "bogus" }, Sender)
Check(HasMessage("must be a color name"), "an unknown color name is refused")

Run({ "scoreboard", "teams", "option", "red", "nametagVisibility", "never" }, Sender)
CheckEquals(Teams.red:GetNameTagVisibility(), "never", "option nametagVisibility is stored")
Check(HasMessage("nametagVisibility is now never"), "option nametagVisibility reports success")

Run({ "scoreboard", "teams", "option", "red", "nametagVisibility", "sometimes" }, Sender)
Check(HasMessage("hideForOtherTeams"), "an unknown nametagVisibility value is refused")

Run({ "scoreboard", "teams", "option", "red", "collisionRule", "pushOwnTeam" }, Sender)
CheckEquals(Teams.red:GetCollisionRule(), "pushOwnTeam", "option collisionRule is stored")
Check(HasMessage("collisionRule is now pushOwnTeam"), "option collisionRule reports success")

Run({ "scoreboard", "teams", "option", "red", "collisionRule", "sometimes" }, Sender)
Check(HasMessage("pushOtherTeams"), "an unknown collisionRule value is refused")

Run({ "scoreboard", "teams", "option", "red", "deathMessageVisibility", "never" }, Sender)
Check(HasMessage("not supported by this server yet"), "deathMessageVisibility is still refused")
CheckEquals(Teams.red:GetDeathMessageVisibility(), "always", "the refused option does not change the team")

Run({ "scoreboard", "teams", "option", "red", "bogus", "x" }, Sender)
Check(HasMessage("Unknown team option"), "an unknown option key is refused")

Run({ "scoreboard", "teams", "option", "red", "friendlyfire", "maybe" }, Sender)
Check(HasMessage('must be "true" or "false"'), "a non-boolean option value is refused")

Run({ "scoreboard", "teams", "option", "blue", "friendlyfire", "true" }, Sender)
Check(HasMessage('Team "blue" does not exist'), "option refuses an unknown team")

Run({ "scoreboard", "teams", "option", "red", "friendlyfire" }, Sender)
Check(HasMessage("/scoreboard teams option"), "option reports the usage when a value is missing")

Run({ "scoreboard", "teams", "option", "red", "friendlyfire", "true", "extra" }, Sender)
Check(HasMessage("/scoreboard teams option"), "option refuses extra arguments")

-- the subcommand list --------------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
Run({ "scoreboard", "teams" }, Sender)
Check(HasMessage("add, remove, empty, join, leave, list, option"), "teams without a subcommand lists them")
Run({ "scoreboard", "teams", "bogus" }, Sender)
Check(HasMessage("add, remove, empty, join, leave, list, option"), "an unknown subcommand lists them")

-- display slots (C6 side fix) ------------------------------------------------

ResetUniverse()
Sender = MakePlayer("TestBot")
OnlinePlayers = { Sender }
AddObjective("t1", "T1")

local function RunObjectives(a_Split)
	Messages = {}
	local Called, Ok, Response = pcall(HandleScoreboardObjectivesCommand, a_Split, Sender)
	Check(Called, "the objectives handler must not raise (" .. tostring(Ok) .. ")")
	if (not Called) then return nil, nil end
	return Ok, Response
end

RunObjectives({ "scoreboard", "objectives", "setdisplay", "list", "t1" })
CheckEquals(#DisplayCalls, 1, "setdisplay reaches cScoreboard:SetDisplay")
Check(DisplayCalls[1] ~= nil and DisplayCalls[1].Name == "t1", "setdisplay passes the objective name")
Check(DisplayCalls[1] ~= nil and DisplayCalls[1].Slot == cScoreboard.dsList, "setdisplay passes dsList")
Check(HasMessage("has been placed on list"), "setdisplay reports the slot")

DisplayCalls = {}
RunObjectives({ "scoreboard", "objectives", "setdisplay", "belowName", "t1" })
Check(DisplayCalls[1] ~= nil and DisplayCalls[1].Slot == cScoreboard.dsName, "belowName maps to dsName")

DisplayCalls = {}
RunObjectives({ "scoreboard", "objectives", "setdisplay", "count", "t1" })
CheckEquals(#DisplayCalls, 0, "count never reaches SetDisplay (it is the enum sentinel, not a slot)")
Check(HasMessage('Unknown display slot "count"'), "count is reported as an unknown slot")

DisplayCalls = {}
RunObjectives({ "scoreboard", "objectives", "setdisplay", "sidebar.team.red", "t1" })
CheckEquals(#DisplayCalls, 0, "the team sidebar slots never reach SetDisplay")
Check(HasMessage("not supported by this server yet"), "the team sidebar slots are reported as unsupported")

DisplayCalls = {}
RunObjectives({ "scoreboard", "objectives", "setdisplay", "list", "nope" })
CheckEquals(#DisplayCalls, 0, "an unknown objective never reaches SetDisplay")
Check(HasMessage('Unknown objective "nope"'), "an unknown objective is reported")

RunObjectives({ "scoreboard", "objectives", "setdisplay" })
Check(HasMessage("/scoreboard objectives setdisplay"), "a missing slot reports the usage")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
