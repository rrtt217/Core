-- test_function_command.lua
--
-- Tests for Core's vanilla 1.12.2 /function: the name/argument parsers, the .mcfunction line rules and
-- the handler (with the file system and the command executor stubbed).
--
-- Verified specification: specs/commands/vanilla-1.12.2-function-command.md (parent repository).
-- The cases pin what is easy to get wrong: the namespace defaults to "minecraft", a path may not escape
-- the functions folder, comments are "#"-only, if/unless are all-or-nothing pairs, and the same origin is
-- handed to every command so relative coordinates stay anchored to the /function call.
--
-- Invariants:
--   * The parsers are pure.
--   * A condition that is not met runs no command at all.
--   * The commands run in file order through ExecuteCommandFromOrigin().
--
-- Run with:  lua tests/test_function_command.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_function.lua")
dofile(ScriptDir .. "/../cmd_function.lua")

-- luacheck: ignore 131
-- luacheck: new globals cRoot cFile cPluginManager ResolveTargets MakeSelectorContext

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






-- Names ----------------------------------------------------------------------

local Namespace, Path = NormalizeFunctionName("test:hello")
CheckEquals(Namespace, "test", "explicit namespace")
CheckEquals(Path, "hello", "explicit path")

Namespace, Path = NormalizeFunctionName("hello")
CheckEquals(Namespace, "minecraft", "namespace defaults to minecraft")
CheckEquals(Path, "hello", "path without namespace")

Namespace, Path = NormalizeFunctionName("test:example/test")
CheckEquals(Namespace, "test", "nested namespace")
CheckEquals(Path, "example/test", "nested path")

Check(NormalizeFunctionName("test:../escape") == nil, "refuses a parent-directory segment")
Check(NormalizeFunctionName("test:a//b") == nil, "refuses an empty segment")
Check(NormalizeFunctionName("test:/abs") == nil, "refuses an absolute path")
Check(NormalizeFunctionName("test:trailing/") == nil, "refuses a trailing slash")
Check(NormalizeFunctionName("test:a\\b") == nil, "refuses a backslash")
Check(NormalizeFunctionName(":name") == nil, "refuses an empty namespace")
Check(NormalizeFunctionName("a b:c") == nil, "refuses a space")
Check(NormalizeFunctionName("test:.") == nil, "refuses a dot segment")

-- Arguments ------------------------------------------------------------------

local Parse, Reason = ParseFunctionLine({ "function" })
CheckEquals(Parse, nil, "function requires a name")
Check(Reason ~= nil and Reason:find("Usage:", 1, true) ~= nil, "function reports the usage")

Parse = ParseFunctionLine({ "function", "test:hello" })
Check(Parse ~= nil and Parse.Condition == nil, "function without a condition")

Parse = ParseFunctionLine({ "function", "test:hello", "if", "@e" })
Check(Parse ~= nil and Parse.Condition == "if" and Parse.Selector == "@e", "function if")

Parse = ParseFunctionLine({ "function", "test:hello", "unless", "@a" })
Check(Parse ~= nil and Parse.Condition == "unless", "function unless")

Check(ParseFunctionLine({ "function", "test:hello", "if" }) == nil, "function refuses if without a selector")
Check(ParseFunctionLine({ "function", "test:hello", "@e" }) == nil, "function refuses a selector without if/unless")
Check(ParseFunctionLine({ "function", "test:hello", "if", "@e", "extra" }) == nil,
	"function refuses extra arguments")

-- Source splitting -----------------------------------------------------------

local Commands = ParseFunctionSource("# a comment\nsay hi\r\n\nsay bye\n")
CheckEquals(#Commands, 2, "skips comments and blank lines")
CheckEquals(Commands[1], "say hi", "strips the carriage return")
CheckEquals(Commands[2], "say bye", "keeps the second command")

Commands = ParseFunctionSource("#only comment")
CheckEquals(#Commands, 0, "a file with only a comment has no commands")

Commands = ParseFunctionSource("")
CheckEquals(#Commands, 0, "an empty file has no commands")

-- Path -----------------------------------------------------------------------

CheckEquals(BuildFunctionPath("world", "test", "example/hello"),
	"world/data/functions/test/example/hello.mcfunction", "function path")

-- Handler --------------------------------------------------------------------

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

local Files = {}
cFile =
{
	IsFile = function (a_Self, a_Path)
		assert(a_Self == cFile, "cFile:IsFile must be called with colon syntax")
		return (Files[a_Path] ~= nil)
	end,
	ReadWholeFile = function (a_Self, a_Path)
		assert(a_Self == cFile, "cFile:ReadWholeFile must be called with colon syntax")
		return Files[a_Path] or ""
	end,
}

local Executed = {}
local LastOrigin = nil
cRoot =
{
	Get = function ()
		return
		{
			GetPluginManager = function ()
				return
				{
					ExecuteCommandFromOrigin = function (_, a_Origin, a_Player, a_Command)
						LastOrigin = a_Origin
						table.insert(Executed, a_Command)
						return 0, "", 0
					end,
				}
			end,
		}
	end,
}

cPluginManager = { crExecuted = 0 }

local SelectorTargets = {}
MakeSelectorContext = function () return {} end
ResolveTargets = function ()
	return SelectorTargets
end

IsBlockForbiddenCommand = function (a_Command)
	return (a_Command == "stop") or (a_Command == "kick")
end

local World = { GetDataPath = function () return "world" end }
local Origin = function (a_X, a_Y, a_Z)
	return
	{
		GetWorld = function () return World end,
		GetPosition = function () return { x = a_X, y = a_Y, z = a_Z } end,
	}
end

Files["world/data/functions/test/hello.mcfunction"] = "# comment\nsay hi\nsay bye\n"

Executed = {}
Messages = {}
local Ok, Message, Count = HandleConsoleFunction({ "function", "test:hello" }, nil, nil, Origin(0, 0, 0))
CheckEquals(Ok, true, "function returns true")
CheckEquals(#Executed, 2, "runs every command in the file")
CheckEquals(Executed[1], "say hi", "first command in file order")
CheckEquals(Executed[2], "say bye", "second command in file order")
Check(LastOrigin ~= nil, "the origin is passed to the command executor")
Check(Message ~= nil and Message:find("Executed 2 command(s) from function 'test:hello'", 1, true) ~= nil,
	"function feedback")
CheckEquals(Count, 0, "function reports a success count of 0")

Messages = {}
Ok, Message = HandleConsoleFunction({ "function", "test:missing" }, nil, nil, Origin(0, 0, 0))
Check(Message ~= nil and Message:find("Function not found", 1, true) ~= nil, "missing function")

SelectorTargets = {}
Executed = {}
Messages = {}
Ok, Message = HandleConsoleFunction({ "function", "test:hello", "if", "@e" }, nil, nil, Origin(0, 0, 0))
Check(Message ~= nil and Message:find("did not match", 1, true) ~= nil, "if without a match fails")
CheckEquals(#Executed, 0, "if without a match runs nothing")

SelectorTargets = { {} }
Executed = {}
Messages = {}
Ok, Message = HandleConsoleFunction({ "function", "test:hello", "unless", "@e" }, nil, nil, Origin(0, 0, 0))
Check(Message ~= nil and Message:find("matched an entity", 1, true) ~= nil, "unless with a match fails")
CheckEquals(#Executed, 0, "unless with a match runs nothing")

SelectorTargets = {}
Executed = {}
Ok, Message = HandleConsoleFunction({ "function", "test:hello", "unless", "@e" }, nil, nil, Origin(0, 0, 0))
CheckEquals(#Executed, 2, "unless without a match runs the function")

-- A command block (non-zero origin, no player) may not run the forbidden commands through a function:
Files["world/data/functions/test/forbidden.mcfunction"] = "stop\n"
Executed = {}
Messages = {}
Ok, Message = HandleConsoleFunction({ "function", "test:forbidden" }, nil, nil, Origin(5, 64, 5))
Check(Message ~= nil and Message:find("Command blocks can not execute", 1, true) ~= nil,
	"command blocks cannot run forbidden commands through a function")
CheckEquals(#Executed, 0, "the forbidden command is not executed")

-- An invalid name is refused before any file access:
Messages = {}
Ok, Message = HandleConsoleFunction({ "function", "test:../escape" }, nil, nil, Origin(0, 0, 0))
Check(Message ~= nil and Message:find("Invalid function name", 1, true) ~= nil,
	"invalid function names are refused")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
