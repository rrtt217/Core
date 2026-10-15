-- command_execute.lua
-- Parses the command lines of Core's /execute family, following vanilla Java Edition 1.12.2.
--
-- Clean-room sources (the full list is in specs/commands/vanilla-1.12.2-execute-and-testfor.md in the parent
-- repository):
--   * "Commands/execute", 1.12.2-era revision (rev 1130584, 2017-07-26):
--     https://minecraft.wiki/w/Commands/execute?oldid=1130584
--   * "Commands/testforblock", 1.12.2-era revision (rev 1166649, 2017-11-12):
--     https://minecraft.wiki/w/Commands/testforblock?oldid=1166649
--   * "Commands", 1.12.2-era revision (rev 1152284, 2017-09-29) - 1.8 (14w03a) removed numeric IDs from
--     commands: https://minecraft.wiki/w/Commands?oldid=1152284
--
-- Everything here except ResolveBlockType() is a pure function of its inputs, so the parser can be exercised
-- with a stock Lua interpreter (see tests/test_execute_line.lua); only ResolveBlockType() reads the engine's
-- name -> block type map.

-- The exported names do not all fit on one `new globals` directive line, so they are declared read-only and
-- this file is allowed to define them.
-- 111 == "setting non-standard global variable".
-- luacheck: globals SplitRawCommand ParseExecuteLine ParseTestforblockLine ResolveBlockType HasExtraArgument
-- luacheck: globals IsBlockForbiddenCommand
-- luacheck: globals cItem StringToItem IsValidBlock
-- luacheck: ignore 111

-- The two 1.12.2 forms, as documented on the 1.12.2-era page. The command name is prepended by the caller's
-- own name, the way the other Core commands build their usage messages.
local EXECUTE_USAGE_TAIL =
	"<entity> <x> <y> <z> <command ...> OR <entity> <x> <y> <z> detect <x2> <y2> <z2> <block> <dataValue> <command ...>"

-- The five commands a command block refuses to run (cCommandBlockEntity::Execute()). /execute must not become
-- a way around that policy (spec section 3.2).
local BLOCK_FORBIDDEN_COMMANDS =
{
	stop = true,
	restart = true,
	kick = true,
	ban = true,
	ipban = true,
}





--- Splits a raw command line the way the engine's StringSplitCommandLine() does and reports where each token
-- sits inside the raw string.
-- The mirrored rules (src/StringUtils.cpp, pinned by tests/StringUtils/CommandLineSplitTest.cpp) are: only a
-- space separates tokens; every space terminates the current token, even when it is empty; a quoted section
-- (single or double quotes) keeps its spaces and loses its quotes; a backslash escapes the next character
-- verbatim; an unterminated quote runs to the end of the line.
-- Returns an array of { Value = <token>, First = <offset>, Last = <offset> }. The offsets are 1-based byte
-- offsets into a_RawCommand and cover the token's raw characters, quotes included; they are nil for a token
-- that has no characters of its own (the extra token a run of spaces produces).
function SplitRawCommand(a_RawCommand)
	local Spans = {}
	local Current = { Value = "", First = nil, Last = nil }
	local InQuote = false
	local QuoteChar = nil
	local Started = false  -- a quote made the token explicit, so that "" still yields an empty argument

	local Length = #a_RawCommand
	local Index = 1
	while (Index <= Length) do
		local Char = a_RawCommand:sub(Index, Index)
		if (Char == "\\") then
			-- A backslash escapes the next character verbatim (\" -> ", \\ -> \):
			if (Current.First == nil) then
				Current.First = Index
			end
			if (Index < Length) then
				Index = Index + 1
				Current.Value = Current.Value .. a_RawCommand:sub(Index, Index)
			else
				-- A trailing backslash is kept as-is:
				Current.Value = Current.Value .. Char
			end
			Current.Last = Index
			Started = true
		elseif (InQuote) then
			if (Char == QuoteChar) then
				InQuote = false
			else
				Current.Value = Current.Value .. Char
			end
			Current.Last = Index
		elseif ((Char == "\"") or (Char == "'")) then
			InQuote = true
			QuoteChar = Char
			if (Current.First == nil) then
				Current.First = Index
			end
			Current.Last = Index
			Started = true
		elseif (Char == " ") then
			table.insert(Spans, Current)
			Current = { Value = "", First = nil, Last = nil }
			Started = false
		else
			Current.Value = Current.Value .. Char
			if (Current.First == nil) then
				Current.First = Index
			end
			Current.Last = Index
		end
		Index = Index + 1
	end

	if (Current.Value ~= "") or (Started) then
		table.insert(Spans, Current)
	end

	return Spans
end





--- Returns true when a_Split holds a non-empty token at a_FirstIndex or later.
-- Core's token list keeps the empty tokens that runs of spaces produce, so "is there another argument?" must
-- not be answered by the token count alone.
function HasExtraArgument(a_Split, a_FirstIndex)
	for Index = a_FirstIndex, #a_Split do
		if ((a_Split[Index] ~= nil) and (a_Split[Index] ~= "")) then
			return true
		end
	end
	return false
end





--- Parses the "<block> [<dataValue>]" argument pair of /testforblock and /execute detect.
-- a_IsDataRequired is true for /execute detect, whose 1.12.2 syntax has no optional brackets around the data
-- value. Returns { Name = <name>, Data = <0..15> or nil for "any block data" }, or nil plus a reason.
-- 1.12.2 takes block *names* ("stone", "minecraft:stone"): numeric IDs stopped working in commands with 1.8
-- (14w03a), and Cuberite's own name map would still resolve them, so they are rejected explicitly here. The
-- block state form ("minecraft:stone[variant=1]") needs the block property registry Cuberite does not have.
local function ParseBlockAndData(a_BlockToken, a_DataToken, a_IsDataRequired)
	if ((a_BlockToken == nil) or (a_BlockToken == "")) then
		return nil, "No block was given"
	end
	if (a_BlockToken:find("[%[%]]") ~= nil) then
		return nil, "Block states are not supported yet"
	end
	if (a_BlockToken:match("^%-?%d+$") ~= nil) then
		return nil, "Invalid block ID \"" .. a_BlockToken .. "\": 1.12.2 takes block names, not numeric IDs"
	end

	local Name = a_BlockToken
	local Prefix, Rest = a_BlockToken:match("^([%a_]+):(.*)$")
	if ((Prefix ~= nil) and ((Prefix:lower() ~= "minecraft") or (Rest == ""))) then
		-- "stone:3" was never a 1.12.2 block argument (the data value is a separate argument) even though
		-- Cuberite's name map would read it as one:
		return nil, "Invalid block ID \"" .. a_BlockToken .. "\""
	end
	if (Prefix ~= nil) then
		Name = Rest
	end
	if ((Name == "") or (Name:find("[%^:]") ~= nil) or (Name:match("^[%w_]+$") == nil)) then
		return nil, "Invalid block ID \"" .. a_BlockToken .. "\""
	end

	local Data = nil
	if ((a_DataToken == nil) or (a_DataToken == "")) then
		if (a_IsDataRequired) then
			return nil, "Expected a block data value after the block"
		end
	else
		if (a_DataToken:match("^%-?%d+$") == nil) then
			return nil, "Invalid block data \"" .. a_DataToken .. "\""
		end
		local Number = tonumber(a_DataToken)
		if (Number == -1) then
			-- -1 matches any block data, exactly like an omitted value:
			Data = nil
		elseif ((Number < 0) or (Number > 15)) then
			return nil, "The block data must be between -1 and 15"
		else
			Data = Number
		end
	end

	return { Name = Name, Data = Data }
end





--- Returns whether every token up to a_LastArgumentIndex is the token the engine split the same string into.
-- A mismatch would mean this module no longer mirrors StringSplitCommandLine(), and the command body would be
-- cut at the wrong offset - the caller must refuse to run rather than execute something else.
local function RawTokensMatch(a_Split, a_Spans, a_LastArgumentIndex)
	if (#a_Spans ~= #a_Split) then
		return false
	end
	for Index = 1, a_LastArgumentIndex do
		if ((a_Spans[Index] == nil) or (a_Spans[Index].Value ~= a_Split[Index])) then
			return false
		end
	end
	return true
end





--- Cuts the command body out of the raw command line: everything after the a_LastArgumentIndex-th token.
-- The leading spaces that separate the body from the arguments are not part of the command.
local function CutCommandBody(a_RawCommand, a_Spans, a_LastArgumentIndex, a_Usage)
	local Span = a_Spans[a_LastArgumentIndex]
	if ((Span == nil) or (Span.Last == nil)) then
		return nil, a_Usage
	end

	local Body = a_RawCommand:sub(Span.Last + 1)
	Body = Body:gsub("^ +", "")
	if (Body == "") then
		return nil, a_Usage
	end
	return Body
end





--- Parses an /execute command line.
-- a_Split is the engine's token list for a_RawCommand, which the handler receives as its third argument; the
-- command body is cut out of a_RawCommand itself, because the engine's tokens have their quotes stripped.
-- Returns the parsed arguments, or nil plus a reason:
--   {
--     Entity = "@p", X = "~", Y = "~", Z = "~",
--     Detect = { X = "~", Y = "~-1", Z = "~", Block = "sand", Data = -1 or nil } or nil,
--     Command = "kill @p",
--   }
function ParseExecuteLine(a_Split, a_RawCommand)
	if ((type(a_Split) ~= "table") or (type(a_RawCommand) ~= "string")) then
		return nil, "Internal error: the command line was not passed to the parser"
	end

	local CommandName = a_Split[1] or "execute"
	local Usage = "Usage: " .. CommandName .. " " .. EXECUTE_USAGE_TAIL

	-- <entity> <x> <y> <z> <command ...>:
	if (#a_Split < 6) then
		return nil, Usage
	end

	local Detect = nil
	local LastArgumentIndex = 5
	if (a_Split[6] == "detect") then
		-- detect <x2> <y2> <z2> <block> <dataValue> <command ...>:
		if (#a_Split < 12) then
			return nil, Usage
		end

		local Argument, Reason = ParseBlockAndData(a_Split[10], a_Split[11], true)
		if (Argument == nil) then
			return nil, Reason
		end
		Detect =
		{
			X = a_Split[7],
			Y = a_Split[8],
			Z = a_Split[9],
			Block = Argument.Name,
			Data = Argument.Data,
		}
		LastArgumentIndex = 11
	end

	local Spans = SplitRawCommand(a_RawCommand)
	if (not RawTokensMatch(a_Split, Spans, LastArgumentIndex)) then
		return nil, "Could not parse the command line"
	end

	local Body, BodyReason = CutCommandBody(a_RawCommand, Spans, LastArgumentIndex, Usage)
	if (Body == nil) then
		return nil, BodyReason
	end

	return
	{
		Entity = a_Split[2],
		X = a_Split[3],
		Y = a_Split[4],
		Z = a_Split[5],
		Detect = Detect,
		Command = Body,
	}
end





--- Parses a /testforblock command line: <x> <y> <z> <block> [<dataValue>] [<dataTag>].
-- Returns { X =, Y =, Z =, Block = <name>, Data = <0..15> or nil } or nil plus a reason. The optional NBT
-- data tag is a separate feature (it needs an SNBT parser); it is refused rather than ignored.
function ParseTestforblockLine(a_Split)
	if (type(a_Split) ~= "table") then
		return nil, "Internal error: the command line was not passed to the parser"
	end

	local Argument, Reason = ParseBlockAndData(a_Split[5], a_Split[6], false)
	if (Argument == nil) then
		return nil, Reason
	end

	if (HasExtraArgument(a_Split, 7)) then
		return nil, "Block data tags are not supported yet"
	end

	return
	{
		X = a_Split[2],
		Y = a_Split[3],
		Z = a_Split[4],
		Block = Argument.Name,
		Data = Argument.Data,
	}
end





--- Resolves a 1.12.2 block name to a block type, or returns nil when there is no such block.
-- The engine's name map is case-insensitive; its numeric and "name:damage" forms are not reached here, because
-- ParseBlockAndData() has already rejected them.
function ResolveBlockType(a_Name)
	local Item = cItem()
	if (not StringToItem(a_Name, Item)) then
		return nil
	end

	-- StringToItem() also resolves plain items, so ask for a block explicitly:
	if (not IsValidBlock(Item.m_ItemType)) then
		return nil
	end
	return Item.m_ItemType
end





--- Returns whether a command block is forbidden to run a_Command.
-- Command blocks refuse a small set of administrator commands in C++ (cCommandBlockEntity::Execute(), section
-- 2.9 of the command block spec). An /execute issued by a command block enters Core through the console path,
-- where no permission is checked, so the same policy has to be applied to the command /execute runs - otherwise
-- "/execute <target> ~ ~ ~ kick <player>" would be a way around it.
-- The command name is the first token of the body, taken with the engine's own token rules (quotes stripped).
function IsBlockForbiddenCommand(a_Command)
	local Spans = SplitRawCommand(a_Command)
	if (#Spans == 0) then
		return false
	end
	return (BLOCK_FORBIDDEN_COMMANDS[Spans[1].Value] == true)
end
