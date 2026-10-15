-- test_execute_command.lua
--
-- Behavioural tests for Core's /execute wiring (cmd_execute.lua) with the game stubbed out.
--
-- Verified specification: specs/commands/vanilla-1.12.2-execute-and-testfor.md (parent repository).
-- The cases pin the parts of the 1.12.2 semantics that live in Core rather than in the selector layer:
--   * the selected entity becomes the executed command's sender ("as if executed by the specified target(s)"),
--     while the *permissions* come from the entity that issued /execute (spec section 3.1) - the property that
--     keeps /execute from becoming a privilege escalation;
--   * "~" is relative to the target, not to the issuing position;
--   * an /execute issued by a command block may not reach the administrator commands (spec section 3.2);
--   * the success count adds up what the executed commands report.
--
-- Why this way: the engine's own permission check needs a live cPlayer, which a headless test cannot build
-- (AGENTS.local.md - no client, no oracle). The stub below therefore records what Core hands to the engine, so
-- the wiring is verified even though the engine's check itself is not.
--
-- Run with:  lua tests/test_execute_command.lua   (from the plugin folder)

if (arg == nil) or (arg[0] == nil) or (arg[0]:find("test_execute_command") == nil) then
	return
end

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_execute.lua")
dofile(ScriptDir .. "/../cmd_execute.lua")

-- luacheck: globals cRoot cPluginManager cCommandOrigin Vector3d Vector3i
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess
-- luacheck: globals ResolveTargets ApplyToTargets MakeSelectorContext GetOriginPosition
-- luacheck: globals cItem StringToItem IsValidBlock
-- luacheck: read globals HandleExecuteCommand
-- 111 == "setting non-standard global variable": the definitions below stand in for the engine's API.
-- luacheck: ignore 111

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
		a_Message .. " (expected " .. tostring(a_Expected) .. ", got " .. tostring(a_Actual) .. ")"
	)
end

local function CheckContains(a_Haystack, a_Needle, a_Message)
	local Found = (a_Haystack ~= nil) and (a_Haystack:find(a_Needle, 1, true) ~= nil)
	Check(Found, a_Message .. " (\"" .. tostring(a_Haystack) .. "\" should contain \"" .. a_Needle .. "\")")
end





--- The engine pieces Core talks to, recorded so that the tests can look at them afterwards.
local Engine = {}

--- The world stub, kept outside the per-test state so that ResetEngine() cannot lose it.
--- (It must be defined after Engine so that it closes over the local, not a global.)
local World =
{
	-- Answers "readable?, block type, block meta"; the tests configure each position.
	-- Called with a colon (World:GetBlockTypeMeta(Position)), so the world arrives first:
	GetBlockTypeMeta = function (_, a_Position)
		local Key = a_Position.x .. "," .. a_Position.y .. "," .. a_Position.z
		local Entry = Engine.Blocks[Key]
		if (Entry == nil) then
			return true, 0, 0
		end
		if (Entry == false) then
			return false
		end
		return true, Entry[1], Entry[2]
	end,
}

local function ResetEngine()
	Engine =
	{
		Calls = {},        -- every ExecuteCommandFromOrigin() call: { Origin =, Permission =, Command = }
		Results = {},      -- the results to hand back, consumed in order
		Counts = {},       -- the success counts to hand back, consumed in order
		Outputs = {},      -- the output strings to hand back, consumed in order
		Messages = {},     -- every message Core sent or returned
		Targets = {},      -- what ResolveTargets() should return
		ResolveReason = nil,
		Blocks = {},       -- World:GetBlockTypeMeta() answers, keyed by "x,y,z"
		Context = nil,     -- the selector context Core built
		Applied = {},      -- the targets ApplyToTargets() visited
		World = World,
	}
end

--- A fake entity. a_Position is the table {x, y, z} it sits at.
local function MakeTarget(a_IsPlayer, a_Position, a_Name)
	return
	{
		IsPlayer = function () return a_IsPlayer end,
		GetPosition = function () return { x = a_Position[1], y = a_Position[2], z = a_Position[3] } end,
		GetWorld = function () return Engine.World end,
		GetName = function () return a_Name or "target" end,
		GetUniqueID = function () return a_Name or "target" end,
	}
end

local function MakeOrigin(a_X, a_Y, a_Z)
	return
	{
		GetPosition = function () return { x = a_X, y = a_Y, z = a_Z } end,
		GetWorld = function () return Engine.World end,
		GetPlayer = function () return nil end,
	}
end

--- Stubs. The selector layer is exercised by test_selectors.lua, so it is replaced here.
function MakeSelectorContext(a_Player, a_Origin)
	Engine.Context = { Player = a_Player, Origin = a_Origin, LocalOnly = false }
	return Engine.Context
end

function GetOriginPosition(a_Origin)
	if (a_Origin == nil) then
		return nil
	end
	return a_Origin:GetPosition()
end

function ResolveTargets(a_Token, _, a_Kind)
	Engine.ResolveToken = a_Token
	Engine.ResolveKind = a_Kind
	if (Engine.ResolveReason ~= nil) then
		return nil, Engine.ResolveReason
	end
	return Engine.Targets
end

function ApplyToTargets(a_Targets, a_Action)
	for _, Target in ipairs(a_Targets) do
		table.insert(Engine.Applied, Target)
		a_Action(Target)
	end
	return #a_Targets
end

function cCommandOrigin(...)
	local Arguments = { ... }
	local Origin = { World = Arguments[1], Position = Arguments[2], Sender = Arguments[3] }
	return Origin
end

function Vector3d(a_X, a_Y, a_Z)
	return { x = a_X, y = a_Y, z = a_Z }
end

function Vector3i(a_X, a_Y, a_Z)
	return { x = a_X, y = a_Y, z = a_Z }
end

function cItem()
	return {}
end

function StringToItem(a_Name, a_Item)
	local Types = { air = 0, stone = 1, sand = 12 }
	local Type = Types[a_Name:lower()]
	if (Type == nil) then
		return false
	end
	a_Item.m_ItemType = Type
	return true
end

function IsValidBlock(a_Type)
	return ((a_Type >= 0) and (a_Type <= 253)) or (a_Type == 255)
end

function SendMessage(_, a_Message)
	table.insert(Engine.Messages, a_Message)
	return a_Message
end

function SendMessageSuccess(_, a_Message)
	table.insert(Engine.Messages, a_Message)
	return a_Message
end

function SendMessageFailure(_, a_Message)
	table.insert(Engine.Messages, a_Message)
	return a_Message
end

cPluginManager =
{
	crExecuted = 0,
	crUnknownCommand = 1,
	crError = 2,
	crBlocked = 3,
	crNoPermission = 4,
}

Engine.World = World

cRoot =
{
	Get = function ()
		return
		{
			GetPluginManager = function ()
				return
				{
					ExecuteCommandFromOrigin = function (_, a_Origin, a_PermissionPlayer, a_Command)
						table.insert(Engine.Calls,
							{
								Origin = a_Origin,
								Permission = a_PermissionPlayer,
								Command = a_Command,
							}
						)
						local Index = #Engine.Calls
						local Output = Engine.Outputs[Index]
						if (Output == nil) then
							Output = ""
						end
						return Engine.Results[Index] or cPluginManager.crExecuted,
							Output,
							Engine.Counts[Index] or 1
					end,
				}
			end,
			GetDefaultWorld = function () return Engine.World end,
		}
	end,
}

--- Runs HandleExecuteCommand() on a command line, with the engine stubbed as configured.
local function RunCommand(a_Line, a_Player, a_Origin)
	local Split = {}
	for Token in (a_Line .. " "):gmatch("([^ ]*) ") do
		table.insert(Split, Token)
	end
	-- The engine drops a trailing empty token, exactly like StringSplitCommandLine():
	if (Split[#Split] == "") and (a_Line:sub(-1) ~= "\"") then
		table.remove(Split)
	end
	return HandleExecuteCommand(Split, a_Player, a_Line, a_Origin or MakeOrigin(0, 0, 0))
end

--- Returns the message Core answered with the last time (the newest entry).
local function LastMessage()
	return Engine.Messages[#Engine.Messages]
end





local PlayerIssuer = {}

local function TestSenderAndPermission()
	ResetEngine()
	local PlayerTarget = MakeTarget(true, { 100.5, 70, 200.5 }, "Target")
	Engine.Targets = { PlayerTarget }

	local Success, Response, SuccessCount = RunCommand("execute @p ~ ~ ~ give @s stone", PlayerIssuer)

	CheckEquals(Success, true, "the command is handled")
	CheckEquals(#Engine.Calls, 1, "the executed command ran once")
	CheckEquals(Engine.Calls[1].Command, "give @s stone", "the body is the executed command")
	CheckEquals(Engine.Calls[1].Permission, PlayerIssuer, "the permissions come from the issuer, not the target")
	CheckEquals(Engine.Calls[1].Origin.Sender, PlayerTarget, "a player target is the executed command's sender")
	CheckEquals(Engine.Calls[1].Origin.Position.x, 100.5, "~ is relative to the target's x")
	CheckEquals(Engine.Calls[1].Origin.Position.y, 70, "~ is relative to the target's y")
	CheckEquals(Engine.Calls[1].Origin.Position.z, 200.5, "~ is relative to the target's z")
	CheckEquals(Engine.ResolveKind, "entity", "1.12.2 accepts entities, not only players")
	Check(Engine.Context.LocalOnly, "the selection stays in the origin world")
	CheckEquals(SuccessCount, 1, "the executed command's success count is passed through")
	Check(Response ~= nil, "the command answers with something")
end





local function TestRelativeCoordinates()
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 10, 64, 30 }, "Target") }

	RunCommand("execute @p ~ ~-1 ~5 give @s stone", PlayerIssuer)

	CheckEquals(Engine.Calls[1].Origin.Position.x, 10, "~ keeps the target's x")
	CheckEquals(Engine.Calls[1].Origin.Position.y, 63, "~-1 moves one block down")
	CheckEquals(Engine.Calls[1].Origin.Position.z, 35, "~5 offsets by five blocks")
end





local function TestNonPlayerTarget()
	ResetEngine()
	Engine.Targets = { MakeTarget(false, { 5, 60, 5 }, "Cow") }

	RunCommand("execute @e[type=cow] ~ ~ ~ say hi", PlayerIssuer)

	CheckEquals(#Engine.Calls, 1, "a non-player target still runs the command")
	CheckEquals(Engine.Calls[1].Origin.Sender, nil, "a non-player target cannot be a sender")
	CheckEquals(Engine.Calls[1].Permission, PlayerIssuer, "the issuer's permissions are still used")
end





local function TestMultipleTargets()
	ResetEngine()
	Engine.Targets =
	{
		MakeTarget(true, { 1, 1, 1 }, "First"),
		MakeTarget(true, { 2, 2, 2 }, "Second"),
	}
	Engine.Counts = { 2, 1 }

	local Success, _, SuccessCount = RunCommand("execute @a ~ ~ ~ give @s stone", PlayerIssuer)

	CheckEquals(#Engine.Calls, 2, "every target runs the command once")
	CheckEquals(SuccessCount, 3, "the success counts add up")
	CheckEquals(Success, true, "the command succeeds when at least one target ran it")
	CheckContains(LastMessage(), "2 target", "the response mentions how many targets ran it")
end





local function TestDispatchFailure()
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	Engine.Results = { cPluginManager.crNoPermission }

	local Success, Response, SuccessCount = RunCommand("execute @p ~ ~ ~ stop", PlayerIssuer)

	CheckEquals(Success, true, "a refused command is still handled")
	CheckEquals(SuccessCount, 0, "nothing was affected")
	CheckContains(Response, "permission", "the refusal is reported as a permission problem")
end





local function TestCommandBlockGuard()
	-- The console and RCON own the default world at (0, 0, 0); a command block runs at the centre of its own
	-- block, so x and z carry the +0.5 offset:
	local BlockOrigin = MakeOrigin(10.5, 64, 20.5)

	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	local _, Response, SuccessCount = RunCommand("execute @p ~ ~ ~ kick Admin", nil, BlockOrigin)

	CheckEquals(#Engine.Calls, 0, "a command block may not reach kick through /execute")
	CheckEquals(SuccessCount, 0, "nothing was affected")
	CheckContains(Response, "kick", "the refusal names the command")

	-- The same command from the console is allowed (it is the administrator, and the engine checks nothing
	-- for it - a player issuer would be checked instead):
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	RunCommand("execute @p ~ ~ ~ kick Admin", nil, MakeOrigin(0, 0, 0))
	CheckEquals(#Engine.Calls, 1, "the console may run it")

	-- A player issuer is never subject to the command block rule; the engine checks the permission instead:
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	RunCommand("execute @p ~ ~ ~ kick Admin", PlayerIssuer, BlockOrigin)
	CheckEquals(#Engine.Calls, 1, "a player issuer goes through the permission check instead")
end





local function TestDetect()
	ResetEngine()
	Engine.Targets =
	{
		MakeTarget(true, { 10, 64, 30 }, "OnSand"),
		MakeTarget(true, { 50, 64, 30 }, "OnStone"),
	}
	-- The block below each target: sand (type 12) for the first, stone (type 1) for the second:
	Engine.Blocks["10,63,30"] = { 12, 0 }
	Engine.Blocks["50,63,30"] = { 1, 0 }

	local Success, _, SuccessCount = RunCommand(
		"execute @a ~ ~ ~ detect ~ ~-1 ~ sand -1 say hello",
		PlayerIssuer
	)

	CheckEquals(#Engine.Calls, 1, "only the target whose block matched runs the command")
	CheckEquals(Engine.Calls[1].Origin.Position.x, 10, "the matching target is the one on sand")
	CheckEquals(SuccessCount, 1, "the success count comes from the command that ran")
	Check(Success, "the command succeeds when at least one target matched")

	-- -1 matches any data value, while an explicit value must match exactly:
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 10, 64, 30 }, "OnSand") }
	Engine.Blocks["10,63,30"] = { 12, 3 }
	RunCommand("execute @p ~ ~ ~ detect ~ ~-1 ~ sand -1 say hello", PlayerIssuer)
	CheckEquals(#Engine.Calls, 1, "-1 matches any data value")

	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 10, 64, 30 }, "OnSand") }
	Engine.Blocks["10,63,30"] = { 12, 3 }
	RunCommand("execute @p ~ ~ ~ detect ~ ~-1 ~ sand 0 say hello", PlayerIssuer)
	CheckEquals(#Engine.Calls, 0, "an explicit data value must match")

	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 10, 64, 30 }, "OnSand") }
	Engine.Blocks["10,63,30"] = { 12, 0 }
	Engine.Outputs = { "hello" }
	local MatchingSuccess, MatchingResponse = RunCommand("execute @p ~ ~ ~ detect ~ ~-1 ~ sand 0 say hello", PlayerIssuer)
	CheckEquals(#Engine.Calls, 1, "a matching data value runs the command")
	Check(MatchingSuccess, "the command succeeds")
	CheckContains(MatchingResponse, "hello", "the executed command's output is the response")

	-- A check that matches nowhere fails the command without claiming a dispatch failure:
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 50, 64, 30 }, "OnStone") }
	Engine.Blocks["50,63,30"] = { 1, 0 }
	local _, FailedResponse, FailedCount = RunCommand("execute @p ~ ~ ~ detect ~ ~-1 ~ sand -1 say hello", PlayerIssuer)
	CheckEquals(#Engine.Calls, 0, "a failed check runs nothing")
	CheckEquals(FailedCount, 0, "a failed check affects nothing")
	CheckContains(FailedResponse, "detection", "the failed check is reported")
end





local function TestArgumentErrors()
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }

	-- Too few arguments never reaches the selector:
	local _, Response = RunCommand("execute @p ~ ~", PlayerIssuer)
	CheckContains(Response, "Usage", "a short command line reports the usage")
	CheckEquals(#Engine.Calls, 0, "nothing runs")

	-- A bad coordinate is reported before anything runs:
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	_, Response = RunCommand("execute @p ~ nope ~ say hi", PlayerIssuer)
	CheckContains(Response, "not a valid number", "a bad coordinate is reported")
	CheckEquals(#Engine.Calls, 0, "nothing runs")

	-- An unknown block in the detect form is reported:
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	_, Response = RunCommand("execute @p ~ ~ ~ detect ~ ~-1 ~ no_such_block -1 say hi", PlayerIssuer)
	CheckContains(Response, "Unknown block", "an unknown block is reported")

	-- A numeric block ID is not 1.12.2 syntax:
	ResetEngine()
	Engine.Targets = { MakeTarget(true, { 1, 1, 1 }, "Target") }
	_, Response = RunCommand("execute @p ~ ~ ~ detect ~ ~-1 ~ 1 -1 say hi", PlayerIssuer)
	CheckContains(Response, "numeric IDs", "numeric block IDs are refused")

	-- No target at all:
	ResetEngine()
	Engine.ResolveReason = "No target matched the selector \"@a\""
	_, Response = RunCommand("execute @a ~ ~ ~ say hi", PlayerIssuer)
	CheckContains(Response, "No target matched", "the selector's reason is reported")
	CheckEquals(#Engine.Calls, 0, "nothing runs without a target")
end





TestSenderAndPermission()
TestRelativeCoordinates()
TestNonPlayerTarget()
TestMultipleTargets()
TestDispatchFailure()
TestCommandBlockGuard()
TestDetect()
TestArgumentErrors()

print(string.format("test_execute_command: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
