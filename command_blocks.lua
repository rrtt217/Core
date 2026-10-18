-- command_blocks.lua
-- Parsers and area geometry for the vanilla 1.12.2 block commands
-- (/setblock, /fill, /clone, /testforblocks).
-- Behaviour and sources: specs/commands/vanilla-1.12.2-block-commands.md
--
-- The parsers are pure: they validate the grammar, the mode whitelists and the 1.12.2 number limits.
-- Block names are resolved later by the handlers through ResolveBlockType() (command_execute.lua),
-- because that needs the engine's item map.
--
-- Two 1.12.2 arguments cannot be honoured and are refused rather than ignored (spec section 4):
-- the SNBT [dataTag] (Lua has no NBT access) and the 1.13+ <state> syntax (no block state registry).

-- The handlers in cmd_*.lua are the only readers of these globals, so luacheck counts them as unused
-- globals in this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: globals ParseSetblockLine ParseFillLine ParseCloneLine ParseTestforblocksLine
-- luacheck: globals NormalizeBox GetVolume IsValidBlockPosition GetCommandWorld BoxesOverlap

local MAX_HORIZONTAL = 30000000
local MAX_BLOCK_Y = 255

local SETBLOCK_MODES = { destroy = true, keep = true, replace = true }
local FILL_MODES = { destroy = true, hollow = true, keep = true, outline = true, replace = true }
local CLONE_MASK_MODES = { filtered = true, masked = true, replace = true }
local CLONE_MODES = { force = true, move = true, normal = true }
local TESTFORBLOCKS_MODES = { all = true, masked = true }



local function IsEmpty(a_Token)
	return (a_Token == nil) or (a_Token == "")
end



local function IsInteger(a_Token)
	return (a_Token ~= nil) and (a_Token:match("^[+-]?%d+$") ~= nil)
end



--- Validates one optional data value. Returns true, value or false, reason.
local function ParseDataValue(a_Token)
	if (not IsInteger(a_Token)) then
		return false, "Invalid block data \"" .. a_Token .. "\""
	end
	local Value = tonumber(a_Token)
	if ((Value < 0) or (Value > 15)) then
		return false, "The block data must be between 0 and 15"
	end
	return true, Value
end



--- Returns true when a token is the beginning of an SNBT data tag.
local function IsDataTag(a_Token)
	return (not IsEmpty(a_Token)) and (a_Token:sub(1, 1) == "{")
end



--- Validates a block-name token. Returns true, or nil plus a reason.
-- 1.12.2 commands take block names ("stone", "minecraft:stone"); the numeric IDs stopped working in
-- commands with 1.8 (14w03a), and the 1.13+ state syntax needs a block-state registry Cuberite lacks.
local function CheckBlockName(a_Token)
	if (a_Token:match("^%d+$") ~= nil) then
		return nil, "Invalid block ID \"" .. a_Token .. "\": 1.12.2 takes block names, not numeric IDs"
	end
	if (a_Token:find("[%[%]]") ~= nil) then
		return nil, "Block states are not supported yet"
	end
	return true
end



--- Parses "/setblock <x> <y> <z> <block> [dataValue] [oldBlockHandling] [dataTag]".
function ParseSetblockLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] .. " <x> <y> <z> <block> [dataValue] [oldBlockHandling] [dataTag]"
	if (IsEmpty(a_Split[5])) then
		return nil, Usage
	end
	local BlockOk, BlockReason = CheckBlockName(a_Split[5])
	if (not BlockOk) then
		return nil, BlockReason
	end

	local Index = 6
	local Data = 0
	if (IsInteger(a_Split[Index])) then
		local Ok, ValueOrReason = ParseDataValue(a_Split[Index])
		if (not Ok) then
			return nil, ValueOrReason
		end
		Data = ValueOrReason
		Index = Index + 1
	end

	local Mode = "replace"
	if (not IsEmpty(a_Split[Index])) then
		if (IsDataTag(a_Split[Index])) then
			return nil, "Data tags are not supported yet"
		end
		if (not SETBLOCK_MODES[a_Split[Index]]) then
			return nil, "Unknown block handling \"" .. a_Split[Index] .. "\""
		end
		Mode = a_Split[Index]
		Index = Index + 1
	end

	if (not IsEmpty(a_Split[Index])) then
		if (IsDataTag(a_Split[Index])) then
			return nil, "Data tags are not supported yet"
		end
		return nil, Usage
	end

	return
	{
		X = a_Split[2],
		Y = a_Split[3],
		Z = a_Split[4],
		Block = a_Split[5],
		Data = Data,
		Mode = Mode,
	}
end



--- Parses "/fill <x1> <y1> <z1> <x2> <y2> <z2> <block> [dataValue] [oldBlockHandling] [dataTag]"
-- plus the replace-filter form "<block> <dataValue> replace [replaceTileName] [replaceDataValue]".
function ParseFillLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] ..
		" <x1> <y1> <z1> <x2> <y2> <z2> <block> [dataValue] [oldBlockHandling] [dataTag]"
	if (IsEmpty(a_Split[8])) then
		return nil, Usage
	end
	local BlockOk, BlockReason = CheckBlockName(a_Split[8])
	if (not BlockOk) then
		return nil, BlockReason
	end

	local Index = 9
	local Data = 0
	local HadData = false
	if (IsInteger(a_Split[Index])) then
		local Ok, ValueOrReason = ParseDataValue(a_Split[Index])
		if (not Ok) then
			return nil, ValueOrReason
		end
		Data = ValueOrReason
		HadData = true
		Index = Index + 1
	end

	local Mode = "replace"
	local ExplicitMode = false
	if (not IsEmpty(a_Split[Index])) then
		if (IsDataTag(a_Split[Index])) then
			return nil, "Data tags are not supported yet"
		end
		if (not FILL_MODES[a_Split[Index]]) then
			return nil, "Unknown block handling \"" .. a_Split[Index] .. "\""
		end
		Mode = a_Split[Index]
		ExplicitMode = true
		Index = Index + 1
	end

	-- The replace filter is only reachable through the documented alternative syntax, which spells
	-- out the data value before "replace":
	local Replace = nil
	if (HadData and ExplicitMode and (Mode == "replace") and (not IsEmpty(a_Split[Index]))) then
		if (IsDataTag(a_Split[Index])) then
			return nil, "Data tags are not supported yet"
		end
		local Name = a_Split[Index]
		local ReplaceOk, ReplaceReason = CheckBlockName(Name)
		if (not ReplaceOk) then
			return nil, ReplaceReason
		end
		Index = Index + 1
		local ReplaceData = nil
		if (IsInteger(a_Split[Index])) then
			local Ok, ValueOrReason = ParseDataValue(a_Split[Index])
			if (not Ok) then
				return nil, ValueOrReason
			end
			ReplaceData = ValueOrReason
			Index = Index + 1
		end
		Replace = { Name = Name, Data = ReplaceData }
	end

	if (not IsEmpty(a_Split[Index])) then
		if (IsDataTag(a_Split[Index])) then
			return nil, "Data tags are not supported yet"
		end
		return nil, Usage
	end

	return
	{
		X1 = a_Split[2],
		Y1 = a_Split[3],
		Z1 = a_Split[4],
		X2 = a_Split[5],
		Y2 = a_Split[6],
		Z2 = a_Split[7],
		Block = a_Split[8],
		Data = Data,
		Mode = Mode,
		Replace = Replace,
	}
end



--- Parses "/clone <x1> <y1> <z1> <x2> <y2> <z2> <x> <y> <z> [maskMode] [cloneMode] [TileName] [dataValue]".
function ParseCloneLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] ..
		" <x1> <y1> <z1> <x2> <y2> <z2> <x> <y> <z> [maskMode] [cloneMode] [TileName] [dataValue]"
	if (IsEmpty(a_Split[10])) then
		return nil, Usage
	end

	local MaskMode = "replace"
	if (not IsEmpty(a_Split[11])) then
		if (not CLONE_MASK_MODES[a_Split[11]]) then
			return nil, "Unknown mask mode \"" .. a_Split[11] .. "\""
		end
		MaskMode = a_Split[11]
	end

	local CloneMode = "normal"
	if (not IsEmpty(a_Split[12])) then
		if (not CLONE_MODES[a_Split[12]]) then
			return nil, "Unknown clone mode \"" .. a_Split[12] .. "\""
		end
		CloneMode = a_Split[12]
	end

	local Filter = nil
	local Index = 13
	if (not IsEmpty(a_Split[Index])) then
		local Name = a_Split[Index]
		local FilterOk, FilterReason = CheckBlockName(Name)
		if (not FilterOk) then
			return nil, FilterReason
		end
		Index = Index + 1
		local FilterData = nil
		if (IsInteger(a_Split[Index])) then
			local Ok, ValueOrReason = ParseDataValue(a_Split[Index])
			if (not Ok) then
				return nil, ValueOrReason
			end
			FilterData = ValueOrReason
			Index = Index + 1
		end
		Filter = { Name = Name, Data = FilterData }
	end
	if (not IsEmpty(a_Split[Index])) then
		return nil, Usage
	end
	if ((MaskMode == "filtered") and (Filter == nil)) then
		return nil, "The filtered mask mode needs a block name"
	end

	return
	{
		X1 = a_Split[2],
		Y1 = a_Split[3],
		Z1 = a_Split[4],
		X2 = a_Split[5],
		Y2 = a_Split[6],
		Z2 = a_Split[7],
		X = a_Split[8],
		Y = a_Split[9],
		Z = a_Split[10],
		MaskMode = MaskMode,
		CloneMode = CloneMode,
		Filter = Filter,
	}
end



--- Parses "/testforblocks <x1> <y1> <z1> <x2> <y2> <z2> <x> <y> <z> [mode]".
function ParseTestforblocksLine(a_Split)
	local Usage = "Usage: " .. a_Split[1] ..
		" <x1> <y1> <z1> <x2> <y2> <z2> <x> <y> <z> [all|masked]"
	if (IsEmpty(a_Split[10])) then
		return nil, Usage
	end

	local Mode = "all"
	if (not IsEmpty(a_Split[11])) then
		if (not TESTFORBLOCKS_MODES[a_Split[11]]) then
			return nil, "Unknown mode \"" .. a_Split[11] .. "\""
		end
		Mode = a_Split[11]
		if (not IsEmpty(a_Split[12])) then
			return nil, Usage
		end
	end

	return
	{
		X1 = a_Split[2],
		Y1 = a_Split[3],
		Z1 = a_Split[4],
		X2 = a_Split[5],
		Y2 = a_Split[6],
		Z2 = a_Split[7],
		X = a_Split[8],
		Y = a_Split[9],
		Z = a_Split[10],
		Mode = Mode,
	}
end



--- Turns two opposite corners into a box of integer block coordinates.
function NormalizeBox(a_X1, a_Y1, a_Z1, a_X2, a_Y2, a_Z2)
	return
	{
		MinX = math.min(a_X1, a_X2),
		MinY = math.min(a_Y1, a_Y2),
		MinZ = math.min(a_Z1, a_Z2),
		MaxX = math.max(a_X1, a_X2),
		MaxY = math.max(a_Y1, a_Y2),
		MaxZ = math.max(a_Z1, a_Z2),
	}
end



--- Number of blocks in a closed box.
function GetVolume(a_Box)
	return (a_Box.MaxX - a_Box.MinX + 1) * (a_Box.MaxY - a_Box.MinY + 1) * (a_Box.MaxZ - a_Box.MinZ + 1)
end



--- Returns true when two closed boxes share at least one block.
function BoxesOverlap(a_First, a_Second)
	return
		(a_First.MinX <= a_Second.MaxX) and (a_First.MaxX >= a_Second.MinX) and
		(a_First.MinY <= a_Second.MaxY) and (a_First.MaxY >= a_Second.MinY) and
		(a_First.MinZ <= a_Second.MaxZ) and (a_First.MaxZ >= a_Second.MinZ)
end



--- Validates a block position (spec section 2.1, point 3). Returns true, or false plus a reason.
function IsValidBlockPosition(a_X, a_Y, a_Z)
	if ((math.abs(a_X) > MAX_HORIZONTAL) or (math.abs(a_Z) > MAX_HORIZONTAL)) then
		return false, "The x and z coordinates must be between -30,000,000 and 30,000,000"
	end
	if ((a_Y < 0) or (a_Y > MAX_BLOCK_Y)) then
		return false, "The y coordinate must be between 0 and 255"
	end
	return true
end



--- Returns the world a command runs in (origin first, then the executing player).
function GetCommandWorld(a_Player, a_Origin)
	local World = nil
	if (a_Origin ~= nil) then
		World = a_Origin:GetWorld()
	end
	if ((World == nil) and (a_Player ~= nil)) then
		World = a_Player:GetWorld()
	end
	return World
end
