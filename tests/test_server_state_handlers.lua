-- test_server_state_handlers.lua
--
-- Handler-level tests for Core's /save-off, /save-on and /setworldspawn: they drive the real handlers
-- through a fake universe and assert which C++ methods were called with which arguments.
--
-- Verified specification: specs/commands/vanilla-1.12.2-server-state-commands.md (parent repository).
-- The cases pin the behaviour that is easy to get wrong: "already in that state" is a FAILURE in
-- vanilla (section 2.1), the saving switch is server-wide although Cuberite stores it per world, and
-- /setworldspawn defaults to the command's position and floors it (section 2.2).
--
-- Invariants:
--   * /save-off and /save-on change all worlds through cRoot:SetSavingEnabled(), and only when at least
--     one world is not already in the requested state.
--   * /setworldspawn writes the spawn of the origin's world (never another world), floors the resolved
--     coordinates, and refuses positions outside the 1.12.2 limits.
--   * A refused command calls neither SetSavingEnabled() nor SetSpawn().
--
-- Run with:  lua tests/test_server_state_handlers.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../cmd_save.lua")
dofile(ScriptDir .. "/../cmd_setworldspawn.lua")

-- luacheck: ignore 131
-- luacheck: new globals cRoot
-- luacheck: globals HandleSaveOffCommand HandleSaveOnCommand HandleConsoleSaveOff HandleConsoleSaveOn
-- luacheck: globals HandleSetWorldspawnCommand HandleConsoleSetWorldspawn

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






-- Stubs ----------------------------------------------------------------------
-- The engine pieces the handlers touch. Only what the commands are supposed to use is implemented.

-- Mirrors core_functions.lua: with a player the message is delivered and nil is returned, without one
-- (the console) the message comes back so the command output carries it.
local LastMessage = nil
SendMessageFailure = function (a_Player, a_Message)
	LastMessage = "failure: " .. tostring(a_Message)
	if (a_Player ~= nil) then
		return nil
	end
	return a_Message
end
SendMessageSuccess = function (a_Player, a_Message)
	LastMessage = "success: " .. tostring(a_Message)
	if (a_Player ~= nil) then
		return nil
	end
	return a_Message
end

-- Records cRoot:SetSavingEnabled() calls; the worlds below are what ForEachWorld() hands out.
local SavedStates = {}
local SaveCalls = {}

local function MakeWorld(a_Name, a_SavingEnabled)
	local World = { Name = a_Name, SavingEnabled = a_SavingEnabled, Spawn = nil }
	function World:IsSavingEnabled()
		return self.SavingEnabled
	end
	function World:SetSpawn(a_X, a_Y, a_Z)
		self.Spawn = { x = a_X, y = a_Y, z = a_Z }
		return SavedStates.SetSpawnResult ~= false
	end
	return World
end






-- The in-game paths receive a player object (the stubs only use its presence), the console ones nil;
-- for the console the message comes back as the return value.
local FakePlayer = {}

local function RunSave(a_Handler, a_Split, a_Player)
	LastMessage = nil
	local Ok, Message, Count = a_Handler(a_Split, a_Player)
	return Ok, Message, Count
end






local Worlds = {}

local function ResetSaveWorlds(a_EnabledList)
	Worlds = {}
	for Index, Enabled in ipairs(a_EnabledList) do
		table.insert(Worlds, MakeWorld("world" .. Index, Enabled))
	end
	cRoot = {
		Get = function ()
			return {
				ForEachWorld = function (_, a_Callback)
					for _, World in ipairs(Worlds) do
						a_Callback(World)
					end
				end,
				SetSavingEnabled = function (_, a_Enabled)
					table.insert(SaveCalls, a_Enabled)
					for _, World in ipairs(Worlds) do
						World.SavingEnabled = a_Enabled
					end
				end,
			}
		end,
	}
	return Worlds
end






-- Local origin fake: /setworldspawn only needs GetWorld() and GetPosition().
local function MakeOrigin(a_World, a_X, a_Y, a_Z)
	return {
		GetWorld = function (self) return a_World end,
		GetPosition = function (self) return { x = a_X, y = a_Y, z = a_Z } end,
	}
end






-- /save-off, /save-on --------------------------------------------------------

SavedStates = {}
SaveCalls = {}

local Worlds = ResetSaveWorlds({ true, true })
local Ok, Message, Count = RunSave(HandleSaveOffCommand, { "save-off" }, FakePlayer)
CheckEquals(Ok, true, "save-off succeeds when saving is enabled")
CheckEquals(Count, 1, "save-off reports a success count of 1 when it changes the switch")
CheckEquals(#SaveCalls, 1, "save-off calls SetSavingEnabled once")
CheckEquals(SaveCalls[1], false, "save-off disables saving")
Check(Message == nil or Message == "Automatic saving is now disabled", "save-off reports that saving is disabled")

SaveCalls = {}
Ok, Message, Count = RunSave(HandleSaveOffCommand, { "save-off" }, FakePlayer)
CheckEquals(Ok, true, "save-off still returns true when already disabled")
CheckEquals(Count, 0, "save-off reports a success count of 0 when nothing changed")
CheckEquals(#SaveCalls, 0, "save-off does not call SetSavingEnabled when already disabled")
Check(LastMessage ~= nil and LastMessage:find("already disabled", 1, true) ~= nil,
	"save-off fails with 'already disabled' when the switch is already off")

Worlds = ResetSaveWorlds({ false, true })
SaveCalls = {}
Ok, Message = RunSave(HandleSaveOffCommand, { "save-off" }, FakePlayer)
CheckEquals(#SaveCalls, 1, "save-off acts when at least one world still saves")

Worlds = ResetSaveWorlds({ false, false })
SaveCalls = {}
Ok, Message, Count = RunSave(HandleSaveOnCommand, { "save-on" }, FakePlayer)
CheckEquals(Count, 1, "save-on reports a success count of 1")
CheckEquals(#SaveCalls, 1, "save-on calls SetSavingEnabled once")
CheckEquals(SaveCalls[1], true, "save-on enables saving")
Check(Message == nil or Message == "Automatic saving is now enabled", "save-on reports that saving is enabled")

SaveCalls = {}
Ok, Message = RunSave(HandleSaveOnCommand, { "save-on" }, FakePlayer)
CheckEquals(#SaveCalls, 0, "save-on does not act when every world already saves")
Check(LastMessage ~= nil and LastMessage:find("already enabled", 1, true) ~= nil,
	"save-on fails with 'already enabled' when the switch is already on")

Worlds = ResetSaveWorlds({ true })
SaveCalls = {}
Ok, Message = RunSave(HandleSaveOffCommand, { "save-off", "extra" }, FakePlayer)
CheckEquals(#SaveCalls, 0, "save-off refuses extra arguments without changing the switch")
Check(LastMessage ~= nil and LastMessage:find("Usage:", 1, true) ~= nil,
	"save-off reports the usage on extra arguments")

-- Console wrappers:
Worlds = ResetSaveWorlds({ true })
SaveCalls = {}
Ok, Message = RunSave(HandleConsoleSaveOff, { "save-off" }, nil)
CheckEquals(#SaveCalls, 1, "console save-off uses the same body")
Check(Message == "Automatic saving is now disabled", "console save-off returns the message as output")

-- /setworldspawn -------------------------------------------------------------

SavedStates = {}
local WorldA = MakeWorld("alpha", true)
local WorldB = MakeWorld("beta", true)
local Origin = MakeOrigin(WorldA, 10.7, 64.2, -3.9)

LastMessage = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "1", "2", "3" }, nil, nil, Origin)
CheckEquals(Ok, true, "setworldspawn with coordinates returns true")
Check(WorldA.Spawn ~= nil, "setworldspawn writes the origin world's spawn")
CheckEquals(WorldA.Spawn.x, 1, "setworldspawn x")
CheckEquals(WorldA.Spawn.y, 2, "setworldspawn y")
CheckEquals(WorldA.Spawn.z, 3, "setworldspawn z")
Check(WorldB.Spawn == nil, "setworldspawn never touches another world")

WorldA.Spawn = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn" }, nil, nil, Origin)
Check(WorldA.Spawn ~= nil, "setworldspawn without arguments uses the command position")
CheckEquals(WorldA.Spawn.x, 10, "setworldspawn floors the command x")
CheckEquals(WorldA.Spawn.y, 64, "setworldspawn floors the command y")
CheckEquals(WorldA.Spawn.z, -4, "setworldspawn floors the command z")

WorldA.Spawn = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "~1", "~", "~-2" }, nil, nil, Origin)
Check(WorldA.Spawn ~= nil, "setworldspawn accepts relative coordinates")
CheckEquals(WorldA.Spawn.x, 11, "setworldspawn resolves ~1 against the origin")
CheckEquals(WorldA.Spawn.y, 64, "setworldspawn resolves ~ against the origin")
CheckEquals(WorldA.Spawn.z, -6, "setworldspawn resolves ~-2 against the origin")

WorldA.Spawn = nil
LastMessage = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "0", "257", "0" }, nil, nil, Origin)
Check(WorldA.Spawn == nil, "setworldspawn refuses y above 256")
Check(LastMessage ~= nil and LastMessage:find("between 0 and 256", 1, true) ~= nil,
	"setworldspawn explains the y limit")

WorldA.Spawn = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "0", "256", "0" }, nil, nil, Origin)
Check(WorldA.Spawn ~= nil and WorldA.Spawn.y == 256, "setworldspawn accepts y = 256")

WorldA.Spawn = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "0", "-1", "0" }, nil, nil, Origin)
Check(WorldA.Spawn == nil, "setworldspawn refuses negative y")

WorldA.Spawn = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "30000001", "0", "0" }, nil, nil, Origin)
Check(WorldA.Spawn == nil, "setworldspawn refuses x beyond 30,000,000")

WorldA.Spawn = nil
Ok = HandleSetWorldspawnCommand({ "setworldspawn", "30000000", "0", "-30000000" }, nil, nil, Origin)
Check(WorldA.Spawn ~= nil, "setworldspawn accepts the exact horizontal limit")

WorldA.Spawn = nil
LastMessage = nil
Ok, Message = HandleSetWorldspawnCommand({ "setworldspawn", "1", "2" }, nil, nil, Origin)
Check(WorldA.Spawn == nil, "setworldspawn refuses an incomplete coordinate triple")
Check(Message ~= nil and Message:find("No coordinate was given", 1, true) ~= nil,
	"setworldspawn explains the missing coordinate")

WorldA.Spawn = nil
LastMessage = nil
Ok, Message = HandleSetWorldspawnCommand({ "setworldspawn", "1", "2", "3", "4" }, nil, nil, Origin)
Check(WorldA.Spawn == nil, "setworldspawn refuses a fourth coordinate")
Check(Message ~= nil and Message:find("Usage:", 1, true) ~= nil, "setworldspawn reports the usage")

WorldA.Spawn = nil
SavedStates.SetSpawnResult = false
Ok, Message = HandleSetWorldspawnCommand({ "setworldspawn", "1", "2", "3" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("Failed to set the world spawn point", 1, true) ~= nil,
	"setworldspawn reports a failed SetSpawn()")
SavedStates.SetSpawnResult = true

WorldA.Spawn = nil
Ok, Message = HandleConsoleSetWorldspawn({ "setworldspawn", "4", "5", "6" }, nil, nil, Origin)
Check(WorldA.Spawn ~= nil and WorldA.Spawn.x == 4, "console setworldspawn uses the same body")
Check(Message == "Set the world spawn point to (4, 5, 6)", "console setworldspawn returns the message as output")

-- A world-less origin (not produced by the engine, but the handler must not crash):
LastMessage = nil
Ok, Message = HandleSetWorldspawnCommand({ "setworldspawn" }, nil, nil, nil)
Check(Message ~= nil and Message:find("no world", 1, true) ~= nil,
	"setworldspawn refuses to run without a world")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
