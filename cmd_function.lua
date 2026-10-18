-- cmd_function.lua
-- Implements the vanilla 1.12.2 /function command:
--   function <function> [if|unless] [selector]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-function-command.md
--
-- The function file is read on every call (never cached), so an edited file takes effect immediately.
-- Each line runs through C4's ExecuteCommandFromOrigin() with the same origin, which keeps relative
-- coordinates anchored to the /function call (spec section 2.2, point 6).

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global in
-- this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: globals HandleFunctionCommand HandleConsoleFunction
-- luacheck: globals ParseFunctionLine ParseFunctionSource BuildFunctionPath
-- luacheck: globals GetCommandWorld GetOriginPosition SendMessageFailure SendMessageSuccess
-- luacheck: globals ResolveTargets MakeSelectorContext IsBlockForbiddenCommand
-- luacheck: globals cRoot cFile

-- Spec section 4.1/4.2: a gamerule subsystem does not exist, so the two safety limits are constants.
local MAX_COMMANDS = 65536
local MAX_DEPTH = 32

-- Nesting depth of the currently running /function commands (Lua is single-threaded per world, so one
-- module-level counter is enough).
local Depth = 0



--- Returns the world the command runs in (origin first, then the executing player).
local function GetWorld(a_Player, a_Origin)
	local World = nil
	if (a_Origin ~= nil) then
		World = a_Origin:GetWorld()
	end
	if ((World == nil) and (a_Player ~= nil)) then
		World = a_Player:GetWorld()
	end
	return World
end



--- Mirrors C4's command-block detection: no player and an origin that is not the console's (0, 0, 0).
local function IsBlockOrigin(a_Player, a_Origin)
	if (a_Player ~= nil) then
		return false
	end
	local Position = GetOriginPosition(a_Origin)
	if (Position == nil) then
		return true
	end
	return ((Position.x ~= 0) or (Position.y ~= 0) or (Position.z ~= 0))
end



--- Runs the commands. Returns the number executed, or nil plus a reason.
local function ExecuteCommands(a_Commands, a_Origin, a_Player, a_BlockOrigin)
	local Executed = 0
	for _, Command in ipairs(a_Commands) do
		if (Executed >= MAX_COMMANDS) then
			break
		end
		if (a_BlockOrigin and IsBlockForbiddenCommand(Command)) then
			return nil, "Command blocks can not execute \"" .. Command .. "\""
		end
		cRoot:Get():GetPluginManager():ExecuteCommandFromOrigin(a_Origin, a_Player, Command)
		Executed = Executed + 1
	end
	return Executed
end



function HandleFunctionCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseFunctionLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local World = GetWorld(a_Player, a_Origin)
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to run the function in"), 0
	end

	if (Parse.Condition ~= nil) then
		local Context = MakeSelectorContext(a_Player, a_Origin)
		local Targets, SelectorReason = ResolveTargets(Parse.Selector, Context, "entity")
		if (Targets == nil) then
			return true, SendMessageFailure(a_Player, SelectorReason), 0
		end
		local Found = (#Targets > 0)
		if ((Parse.Condition == "if") and (not Found)) then
			return true, SendMessageFailure(a_Player, "The selector did not match any entity"), 0
		end
		if ((Parse.Condition == "unless") and Found) then
			return true, SendMessageFailure(a_Player, "The selector matched an entity"), 0
		end
	end

	local FilePath = BuildFunctionPath(World:GetDataPath(), Parse.Namespace, Parse.Path)
	if (not cFile:IsFile(FilePath)) then
		return true, SendMessageFailure(a_Player, "Function not found \"" .. Parse.Name .. "\""), 0
	end

	if (Depth >= MAX_DEPTH) then
		return true, SendMessageFailure(a_Player, "Functions are nested too deeply"), 0
	end

	local Commands = ParseFunctionSource(cFile:ReadWholeFile(FilePath))
	local BlockOrigin = IsBlockOrigin(a_Player, a_Origin)
	Depth = Depth + 1
	local Ok, ExecutedOrReason, FailureReason = pcall(ExecuteCommands, Commands, a_Origin, a_Player,
		BlockOrigin)
	Depth = Depth - 1

	if (not Ok) then
		return true, SendMessageFailure(a_Player,
			"A command in the function failed: " .. tostring(ExecutedOrReason)), 0
	end
	if (ExecutedOrReason == nil) then
		return true, SendMessageFailure(a_Player, tostring(FailureReason)), 0
	end

	return true, SendMessageSuccess(a_Player,
		string.format("Executed %d command(s) from function '%s'", ExecutedOrReason, Parse.Name)), 0
end



function HandleConsoleFunction(a_Split, _, _, a_Origin)
	return HandleFunctionCommand(a_Split, nil, nil, a_Origin)
end
