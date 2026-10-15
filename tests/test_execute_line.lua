-- test_execute_line.lua
--
-- Table-driven tests for Core's /execute family parsing (command_execute.lua).
--
-- Verified specification: specs/commands/vanilla-1.12.2-execute-and-testfor.md (parent repository).
-- The cases pin the 1.12.2 grammar: <entity> <x> <y> <z> <command ...>, the detect form with its mandatory
-- data value, and the block argument being a *name* (1.8 / 14w03a removed numeric IDs from commands).
--
-- Invariants:
--   * SplitRawCommand() mirrors the engine's StringSplitCommandLine() token by token, so the command body can
--     be cut out of the original command line. Every case below hands the parser the *engine's* token list
--     (as the C++ splitter would produce it, per tests/StringUtils/CommandLineSplitTest.cpp), so a drift
--     between the two splitters fails here.
--   * The command body keeps the original text, quotes included - the engine's tokens have them stripped, so
--     /execute @p ~ ~ ~ tell "First Last" hi must still reach /tell as one quoted argument.
--   * ParseExecuteLine()/ParseTestforblockLine()/HasExtraArgument()/IsBlockForbiddenCommand() are pure
--     functions of their arguments; only ResolveBlockType() reads the engine (stubbed at the bottom).
--
-- Run with:  lua tests/test_execute_line.lua   (from the plugin folder)

if (arg == nil) or (arg[0] == nil) or (arg[0]:find("test_execute_line") == nil) then
	return
end

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_execute.lua")

-- luacheck: new globals cItem StringToItem IsValidBlock
-- luacheck: read globals SplitRawCommand ParseExecuteLine ParseTestforblockLine ResolveBlockType
-- luacheck: read globals HasExtraArgument IsBlockForbiddenCommand

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

local function CheckReason(a_Reason, a_ExpectedFragment, a_Message)
	Check(
		(a_Reason ~= nil) and (a_Reason:find(a_ExpectedFragment, 1, true) ~= nil),
		a_Message .. " (reason should mention \"" .. a_ExpectedFragment .. "\", got " .. tostring(a_Reason) .. ")"
	)
end





--- Renders the token values of a raw command line, for compact expectations.
local function ValuesOf(a_RawCommand)
	local Values = {}
	for _, Span in ipairs(SplitRawCommand(a_RawCommand)) do
		table.insert(Values, Span.Value)
	end
	return table.concat(Values, "|")
end

--- Renders the byte extents of a raw command line's tokens, for compact expectations.
local function OffsetsOf(a_RawCommand)
	local Extents = {}
	for _, Span in ipairs(SplitRawCommand(a_RawCommand)) do
		table.insert(Extents, tostring(Span.First) .. "-" .. tostring(Span.Last))
	end
	return table.concat(Extents, "|")
end

--- Checks the token values of a raw command line against "a|b|c".
local function CheckTokens(a_RawCommand, a_Expected)
	CheckEquals(ValuesOf(a_RawCommand), a_Expected, "SplitRawCommand(\"" .. a_RawCommand .. "\") token values")
end

--- Checks the byte extents of a raw command line's tokens against "1-1|3-3".
local function CheckExtents(a_RawCommand, a_Expected)
	CheckEquals(OffsetsOf(a_RawCommand), a_Expected, "SplitRawCommand(\"" .. a_RawCommand .. "\") token extents")
end

--- Runs ParseExecuteLine() on a raw command line plus the engine's token list and checks the body.
local function CheckBody(a_Split, a_RawCommand, a_ExpectedBody)
	local Parse, Reason = ParseExecuteLine(a_Split, a_RawCommand)
	if (Parse == nil) then
		Check(false, "ParseExecuteLine(\"" .. a_RawCommand .. "\") should parse (reason: " .. tostring(Reason) .. ")")
		return nil
	end
	CheckEquals(Parse.Command, a_ExpectedBody, "command body of \"" .. a_RawCommand .. "\"")
	return Parse
end

--- Checks that ParseExecuteLine() rejects a raw command line with a message mentioning a_Fragment.
local function CheckExecuteRejected(a_Split, a_RawCommand, a_Fragment)
	local Parse, Reason = ParseExecuteLine(a_Split, a_RawCommand)
	Check(Parse == nil, "ParseExecuteLine(\"" .. a_RawCommand .. "\") should fail")
	CheckReason(Reason, a_Fragment, "ParseExecuteLine(\"" .. a_RawCommand .. "\")")
end





local function TestTokenizer()
	-- The empty and space-only inputs keep the engine's behaviour exactly:
	CheckTokens("", "")
	CheckTokens(" ", "")
	CheckTokens("a", "a")
	CheckTokens("a b", "a|b")
	CheckTokens("a  b", "a||b")
	CheckTokens("  a  b  ", "||a||b|")
	CheckTokens("a ", "a")

	-- Quotes anywhere inside a token keep their spaces and lose the quotes; the extent covers them:
	CheckTokens("say foo\"bar baz\"", "say|foobar baz")
	CheckExtents("say foo\"bar baz\"", "1-3|5-16")
	CheckTokens("\"a b\" c", "a b|c")
	CheckTokens("a 'b c' d", "a|b c|d")
	CheckTokens("a \"b", "a|b")
	CheckTokens("a \"\" b", "a||b")

	-- A backslash escapes the next character verbatim, including a space:
	CheckTokens("a\\ b", "a b")
	CheckExtents("a\\ b", "1-4")
	CheckTokens("a\\\"b c", "a\"b|c")

	-- A tab is not a separator (the engine only splits on spaces):
	CheckTokens("a\tb", "a\tb")

	-- A trailing backslash is kept as-is:
	CheckTokens("a\\", "a\\")
end





local function TestExecuteSyntax()
	-- execute <entity> <x> <y> <z> <command ...>:
	local Parse = CheckBody(
		{ "execute", "@p", "~", "~", "~", "kill", "@p" },
		"execute @p ~ ~ ~ kill @p",
		"kill @p"
	)
	if (Parse ~= nil) then
		CheckEquals(Parse.Entity, "@p", "entity")
		CheckEquals(Parse.X, "~", "x")
		CheckEquals(Parse.Y, "~", "y")
		CheckEquals(Parse.Z, "~", "z")
		Check(Parse.Detect == nil, "no detect block without the keyword")
	end

	-- The keyword is only recognised in the sixth position:
	Parse = CheckBody(
		{ "execute", "@e[type=zombie]", "~", "~-1", "~", "summon", "lightning_bolt" },
		"execute @e[type=zombie] ~ ~-1 ~ summon lightning_bolt",
		"summon lightning_bolt"
	)
	if (Parse ~= nil) then
		CheckEquals(Parse.Y, "~-1", "relative y coordinate")
		CheckEquals(Parse.Entity, "@e[type=zombie]", "selector entity")
	end

	-- "detect" in the sixth position is always the keyword, exactly as in vanilla, so a command of that name
	-- cannot be the body of the short form:
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "detect", "now" },
		"execute @p ~ ~ ~ detect now",
		"Usage"
	)

	-- The body keeps the original text, quotes included (the engine's tokens have them stripped):
	CheckBody(
		{ "execute", "@p", "~", "~", "~", "tell", "First Last", "hi" },
		"execute @p ~ ~ ~ tell \"First Last\" hi",
		"tell \"First Last\" hi"
	)

	-- ... and the original spacing between the arguments:
	CheckBody(
		{ "execute", "@p", "~", "~", "~", "", "kill", "@p" },
		"execute @p ~ ~ ~  kill @p",
		"kill @p"
	)

	-- Too few arguments, or no command at all:
	CheckExecuteRejected({ "execute" }, "execute", "Usage")
	CheckExecuteRejected({ "execute", "@p", "~", "~" }, "execute @p ~ ~", "Usage")
	CheckExecuteRejected({ "execute", "@p", "~", "~", "~" }, "execute @p ~ ~ ~", "Usage")

	-- A token list that does not match the raw command line is refused instead of running something else (the
	-- body would otherwise be cut at the wrong offset):
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "kill", "@p" },
		"execute @p ~ ~ 5 kill @p",
		"Could not parse the command line"
	)
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "kill", "@p", "extra" },
		"execute @p ~ ~ ~ kill @p",
		"Could not parse the command line"
	)
end





local function TestExecuteDetect()
	-- detect <x2> <y2> <z2> <block> <dataValue> <command ...>; -1 matches any data value:
	local Parse = CheckBody(
		{ "execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "sand", "-1", "kill", "@p" },
		"execute @p ~ ~ ~ detect ~ ~-1 ~ sand -1 kill @p",
		"kill @p"
	)
	if (Parse ~= nil) then
		Check(Parse.Detect ~= nil, "detect is parsed")
		CheckEquals(Parse.Detect.X, "~", "detect x")
		CheckEquals(Parse.Detect.Y, "~-1", "detect y")
		CheckEquals(Parse.Detect.Z, "~", "detect z")
		CheckEquals(Parse.Detect.Block, "sand", "detect block")
		Check(Parse.Detect.Data == nil, "-1 matches any block data")
	end

	-- A block name may carry the minecraft: prefix, and a data value may be given:
	Parse = CheckBody(
		{
			"execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "minecraft:wool", "1",
			"setblock", "~", "~", "~", "air",
		},
		"execute @p ~ ~ ~ detect ~ ~-1 ~ minecraft:wool 1 setblock ~ ~ ~ air",
		"setblock ~ ~ ~ air"
	)
	if (Parse ~= nil) then
		CheckEquals(Parse.Detect.Block, "wool", "the minecraft: prefix is stripped")
		CheckEquals(Parse.Detect.Data, 1, "explicit block data")
	end

	-- The data value is not optional in this form (the 1.12.2 syntax has no brackets around it):
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "sand", "kill", "@p" },
		"execute @p ~ ~ ~ detect ~ ~-1 ~ sand kill @p",
		"Invalid block data"
	)
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "sand", "-1" },
		"execute @p ~ ~ ~ detect ~ ~-1 ~ sand -1",
		"Usage"
	)

	-- 1.12.2 block arguments are names (1.8 / 14w03a removed the numeric IDs):
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "1", "-1", "kill", "@p" },
		"execute @p ~ ~ ~ detect ~ ~-1 ~ 1 -1 kill @p",
		"numeric IDs"
	)

	-- Block states are a separate (unimplemented) feature:
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "minecraft:sand[variant=1]", "-1", "kill", "@p" },
		"execute @p ~ ~ ~ detect ~ ~-1 ~ minecraft:sand[variant=1] -1 kill @p",
		"Block states are not supported yet"
	)

	-- The data value range is -1..15:
	CheckExecuteRejected(
		{ "execute", "@p", "~", "~", "~", "detect", "~", "~-1", "~", "sand", "16", "kill", "@p" },
		"execute @p ~ ~ ~ detect ~ ~-1 ~ sand 16 kill @p",
		"between -1 and 15"
	)
end





local function TestTestforblockLine()
	local Parse, Reason = ParseTestforblockLine({ "testforblock", "0", "64", "0", "minecraft:stone" })
	if (Parse == nil) then
		Check(false, "testforblock should parse (reason: " .. tostring(Reason) .. ")")
	else
		CheckEquals(Parse.X, "0", "x")
		CheckEquals(Parse.Y, "64", "y")
		CheckEquals(Parse.Z, "0", "z")
		CheckEquals(Parse.Block, "stone", "block name without the prefix")
		Check(Parse.Data == nil, "no data value means any data value")
	end

	Parse = ParseTestforblockLine({ "testforblock", "~", "~-1", "~", "stone", "1" })
	if (Parse == nil) then
		Check(false, "testforblock with a data value should parse")
	else
		CheckEquals(Parse.Data, 1, "explicit data value")
	end

	Parse = ParseTestforblockLine({ "testforblock", "0", "64", "0", "stone", "-1" })
	if (Parse == nil) then
		Check(false, "testforblock with -1 should parse")
	else
		Check(Parse.Data == nil, "-1 matches any data value")
	end

	Parse = ParseTestforblockLine({ "testforblock", "0", "64", "0", "stone", "" })
	if (Parse == nil) then
		Check(false, "a spare space after the block should still parse")
	else
		Check(Parse.Data == nil, "an empty data token is an omitted data value")
	end

	Parse, Reason = ParseTestforblockLine({ "testforblock", "0", "64", "0" })
	Check(Parse == nil, "a missing block should fail")
	CheckReason(Reason, "No block", "missing block")

	Parse, Reason = ParseTestforblockLine({ "testforblock", "0", "64", "0", "1" })
	Check(Parse == nil, "a numeric block ID should fail")
	CheckReason(Reason, "numeric IDs", "numeric block ID")

	Parse, Reason = ParseTestforblockLine({ "testforblock", "0", "64", "0", "stone:3" })
	Check(Parse == nil, "the Cuberite name:damage form should fail")
	CheckReason(Reason, "Invalid block ID", "name:damage block")

	Parse, Reason = ParseTestforblockLine({ "testforblock", "0", "64", "0", "stone", "16" })
	Check(Parse == nil, "a data value above 15 should fail")
	CheckReason(Reason, "between -1 and 15", "data value range")

	Parse, Reason = ParseTestforblockLine({ "testforblock", "0", "64", "0", "stone", "0", "{CustomName:Fred}" })
	Check(Parse == nil, "an NBT data tag should be refused")
	CheckReason(Reason, "data tags are not supported", "unsupported data tag")
end





local function TestHasExtraArgument()
	Check(not HasExtraArgument({ "testfor", "@a" }, 3), "no third token")
	Check(not HasExtraArgument({ "testfor", "@a", "" }, 3), "an empty third token is not an argument")
	Check(not HasExtraArgument({ "testfor", "@a", "", "" }, 3), "empty tokens are not arguments")
	Check(HasExtraArgument({ "testfor", "@a", "{}" }, 3), "a data tag is an argument")
	Check(HasExtraArgument({ "testfor", "@a", "", "{}" }, 3), "a data tag after an empty token is an argument")
end





local function TestForbiddenCommands()
	Check(IsBlockForbiddenCommand("stop"), "stop is forbidden for command blocks")
	Check(IsBlockForbiddenCommand("kick SomePlayer"), "a command with arguments keeps its first token")
	Check(IsBlockForbiddenCommand("ban SomePlayer"), "ban is forbidden for command blocks")
	Check(IsBlockForbiddenCommand("\"stop\" all"), "quoted command names are recognised")
	Check(not IsBlockForbiddenCommand("say stop"), "say is allowed")
	Check(not IsBlockForbiddenCommand(""), "an empty command is not forbidden")
	Check(not IsBlockForbiddenCommand("stopwatch"), "a longer name is not the stop command")
end





local function TestResolveBlockType()
	-- StringToItem()/IsValidBlock() are the engine's functions, stubbed here with just enough behaviour to
	-- pin the glue: an item name must not resolve to a block type.
	cItem = function ()
		return { m_ItemType = 0 }
	end
	StringToItem = function (a_Name, a_Item)
		local Types = { stone = 1, sand = 12, apple = 260 }
		local Type = Types[a_Name:lower()]
		if (Type == nil) then
			return false
		end
		a_Item.m_ItemType = Type
		return true
	end
	IsValidBlock = function (a_Type)
		return ((a_Type >= 0) and (a_Type <= 253)) or (a_Type == 255)
	end

	CheckEquals(ResolveBlockType("stone"), 1, "a known block name resolves to its type")
	CheckEquals(ResolveBlockType("SAND"), 12, "the engine's name map is case-insensitive")
	Check(ResolveBlockType("apple") == nil, "an item is not a block")
	Check(ResolveBlockType("no_such_block") == nil, "an unknown name does not resolve")
end





TestTokenizer()
TestExecuteSyntax()
TestExecuteDetect()
TestTestforblockLine()
TestHasExtraArgument()
TestForbiddenCommands()
TestResolveBlockType()

print(string.format("test_execute_line: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
