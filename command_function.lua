-- command_function.lua
-- Parsers for the vanilla 1.12.2 /function command and its .mcfunction files.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-function-command.md
--
-- Pure functions only: the file is read and the commands are executed by cmd_function.lua.

-- luacheck: globals ParseFunctionLine NormalizeFunctionName ParseFunctionSource BuildFunctionPath

local function IsEmpty(a_Token)
	return (a_Token == nil) or (a_Token == "")
end



--- Returns true when one path segment is a plain identifier (no ".", "..", separators, colons).
local function IsValidSegment(a_Segment)
	if ((a_Segment == "") or (a_Segment == ".") or (a_Segment == "..")) then
		return false
	end
	return (a_Segment:match("^[%w_%-%.]+$") ~= nil)
end



--- Splits "namespace:path/to/file.mcfunction-name" (namespace defaults to "minecraft").
-- Returns namespace, path or nil, nil plus a reason (spec section 2.2).
function NormalizeFunctionName(a_Token)
	if (IsEmpty(a_Token)) then
		return nil, nil, "No function name was given"
	end

	local Namespace, Path = a_Token:match("^([^:]+):(.+)$")
	if (Namespace == nil) then
		Namespace = "minecraft"
		Path = a_Token
	end

	if ((Namespace:find("/", 1, true) ~= nil) or (Namespace:find("\\", 1, true) ~= nil) or
		(not IsValidSegment(Namespace))) then
		return nil, nil, "Invalid function name \"" .. a_Token .. "\""
	end
	if ((Path:sub(1, 1) == "/") or (Path:sub(-1) == "/") or
		(Path:find("//", 1, true) ~= nil) or (Path:find("\\", 1, true) ~= nil)) then
		return nil, nil, "Invalid function name \"" .. a_Token .. "\""
	end
	for Segment in (Path .. "/"):gmatch("([^/]*)/") do
		if (not IsValidSegment(Segment)) then
			return nil, nil, "Invalid function name \"" .. a_Token .. "\""
		end
	end

	return Namespace, Path
end



--- Parses "/function <function> [if|unless] [selector]".
function ParseFunctionLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] .. " <function> [if|unless] [selector]"
	if (IsEmpty(a_Split[2])) then
		return nil, Usage
	end

	local Namespace, Path, NameReason = NormalizeFunctionName(a_Split[2])
	if (Namespace == nil) then
		return nil, NameReason
	end

	local Condition = nil
	local Selector = nil
	if (not IsEmpty(a_Split[3])) then
		if ((a_Split[3] ~= "if") and (a_Split[3] ~= "unless")) then
			return nil, Usage
		end
		if (IsEmpty(a_Split[4]) or (not IsEmpty(a_Split[5]))) then
			return nil, Usage
		end
		Condition = a_Split[3]
		Selector = a_Split[4]
	end

	return
	{
		Name = a_Split[2],
		Namespace = Namespace,
		Path = Path,
		Condition = Condition,
		Selector = Selector,
	}
end



--- Splits a .mcfunction file into the commands to run.
-- One command per line; blank lines and lines starting with "#" are skipped, and a trailing "\r" is
-- removed (the 1.12.2 comment rule is "# only", spec section 2.2).
function ParseFunctionSource(a_Text)
	local Commands = {}
	for Line in (a_Text .. "\n"):gmatch("([^\n]*)\n") do
		Line = Line:gsub("\r$", "")
		if ((Line ~= "") and (Line:sub(1, 1) ~= "#")) then
			table.insert(Commands, Line)
		end
	end
	return Commands
end



--- Builds the on-disk path of a function inside a world folder (spec section 2.2, point 1).
function BuildFunctionPath(a_DataPath, a_Namespace, a_Path)
	return a_DataPath .. "/data/functions/" .. a_Namespace .. "/" .. a_Path .. ".mcfunction"
end
