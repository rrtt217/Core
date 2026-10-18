-- test_block_commands.lua
--
-- Tests for Core's vanilla 1.12.2 block commands (/setblock, /fill, /clone, /testforblocks): the four
-- parsers, the area geometry, and the handlers driven through a fake world and a fake cBlockArea.
--
-- Verified specification: specs/commands/vanilla-1.12.2-block-commands.md (parent repository).
-- The cases pin what is easy to get wrong: the data value is a separate argument, the replace filter is
-- only reachable through "<block> <dataValue> replace [name] [data]", SNBT data tags are refused rather
-- than ignored, /fill and /clone refuse a region above 32768 blocks, /testforblocks above 524288, and
-- overlapping source/destination regions need "force".
--
-- Invariants:
--   * The parsers are pure and never touch the engine.
--   * A refused command changes no block (the loaded-chunk check runs before the first write).
--   * The success count is the number of changed (or matching) blocks.
--
-- Run with:  lua tests/test_block_commands.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_blocks.lua")
dofile(ScriptDir .. "/../cmd_setblock.lua")
dofile(ScriptDir .. "/../cmd_fill.lua")
dofile(ScriptDir .. "/../cmd_clone.lua")
dofile(ScriptDir .. "/../cmd_testforblocks.lua")

-- luacheck: ignore 131
-- luacheck: new globals E_BLOCK_AIR E_BLOCK_STONE E_BLOCK_DIRT Vector3i ResolveBlockType cBlockArea

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






-- Parsers --------------------------------------------------------------------

local Parse, Reason = ParseSetblockLine({ "setblock" })
CheckEquals(Parse, nil, "setblock requires its arguments")
Check(Reason ~= nil and Reason:find("Usage:", 1, true) ~= nil, "setblock reports the usage")

Parse = ParseSetblockLine({ "setblock", "1", "2", "3", "stone" })
Check(Parse ~= nil and Parse.Data == 0 and Parse.Mode == "replace", "setblock defaults")

Parse = ParseSetblockLine({ "setblock", "1", "2", "3", "stone", "7", "keep" })
Check(Parse ~= nil and Parse.Data == 7 and Parse.Mode == "keep", "setblock data and mode")

Check(ParseSetblockLine({ "setblock", "1", "2", "3", "stone", "16" }) == nil, "setblock refuses data 16")
Check(ParseSetblockLine({ "setblock", "1", "2", "3", "stone", "bogus" }) == nil,
	"setblock refuses an unknown handling token")
Check(ParseSetblockLine({ "setblock", "1", "2", "3", "stone", "{CustomName:x}" }) == nil,
	"setblock refuses a data tag")
Check(ParseSetblockLine({ "setblock", "1", "2", "3", "stone", "0", "replace", "{x:1}" }) == nil,
	"setblock refuses a data tag after the handling")
Check(ParseSetblockLine({ "setblock", "1", "2", "3", "stone", "0", "replace", "extra" }) == nil,
	"setblock refuses extra arguments")

local NumericParse, NumericReason = ParseSetblockLine({ "setblock", "1", "2", "3", "1" })
CheckEquals(NumericParse, nil, "setblock refuses a numeric block ID")
Check(NumericReason ~= nil and NumericReason:find("numeric IDs", 1, true) ~= nil,
	"setblock explains the numeric block ID refusal")
Check(ParseSetblockLine({ "setblock", "1", "2", "3", "stone[variant=1]" }) == nil,
	"setblock refuses block states")
Check(ParseFillLine({ "fill", "0", "0", "0", "1", "1", "1", "1" }) == nil,
	"fill refuses a numeric block ID")
Check(ParseCloneLine({ "clone", "0", "0", "0", "1", "1", "1", "5", "5", "5", "filtered", "normal",
	"1" }) == nil, "clone refuses a numeric filter block ID")

Parse = ParseFillLine({ "fill", "0", "0", "0", "1", "1", "1", "stone" })
Check(Parse ~= nil and Parse.Mode == "replace" and Parse.Replace == nil, "fill defaults")

Parse = ParseFillLine({ "fill", "0", "0", "0", "1", "1", "1", "stone", "0", "destroy" })
Check(Parse ~= nil and Parse.Mode == "destroy", "fill parses a mode")

Parse = ParseFillLine({ "fill", "0", "0", "0", "1", "1", "1", "stone", "0", "replace", "dirt", "1" })
Check(Parse ~= nil and Parse.Replace ~= nil and Parse.Replace.Name == "dirt" and Parse.Replace.Data == 1,
	"fill parses the replace filter")

Parse = ParseFillLine({ "fill", "0", "0", "0", "1", "1", "1", "stone", "replace", "dirt" })
Check(Parse == nil, "fill refuses the filter without an explicit data value")

Check(ParseFillLine({ "fill", "0", "0", "0", "1", "1", "1", "stone", "0", "outline", "dirt" }) == nil,
	"fill refuses a filter after a non-replace mode")

Parse = ParseCloneLine({ "clone", "0", "0", "0", "1", "1", "1", "5", "5", "5" })
Check(Parse ~= nil and Parse.MaskMode == "replace" and Parse.CloneMode == "normal", "clone defaults")

Parse = ParseCloneLine({ "clone", "0", "0", "0", "1", "1", "1", "5", "5", "5", "filtered", "force",
	"dirt", "2" })
Check(Parse ~= nil and Parse.MaskMode == "filtered" and Parse.CloneMode == "force" and
	Parse.Filter.Name == "dirt" and Parse.Filter.Data == 2, "clone parses filter and modes")

Check(ParseCloneLine({ "clone", "0", "0", "0", "1", "1", "1", "5", "5", "5", "filtered" }) == nil,
	"clone refuses filtered without a block name")
Check(ParseCloneLine({ "clone", "0", "0", "0", "1", "1", "1", "5", "5", "5", "bogus" }) == nil,
	"clone refuses an unknown mask mode")
Check(ParseCloneLine({ "clone", "0", "0", "0", "1", "1", "1", "5", "5", "5", "replace", "bogus" }) == nil,
	"clone refuses an unknown clone mode")

Parse = ParseTestforblocksLine({ "testforblocks", "0", "0", "0", "1", "1", "1", "5", "5", "5" })
Check(Parse ~= nil and Parse.Mode == "all", "testforblocks defaults to all")
Parse = ParseTestforblocksLine({ "testforblocks", "0", "0", "0", "1", "1", "1", "5", "5", "5", "masked" })
Check(Parse ~= nil and Parse.Mode == "masked", "testforblocks masked")
Check(ParseTestforblocksLine({ "testforblocks", "0", "0", "0", "1", "1", "1", "5", "5", "5", "bogus" }) == nil,
	"testforblocks refuses an unknown mode")

-- Geometry -------------------------------------------------------------------

local Box = NormalizeBox(3, 5, 7, 1, 2, 9)
CheckEquals(Box.MinX, 1, "normalize min x")
CheckEquals(Box.MaxY, 5, "normalize max y")
CheckEquals(GetVolume(Box), 3 * 4 * 3, "box volume")

local Other = NormalizeBox(2, 3, 8, 4, 6, 10)
Check(BoxesOverlap(Box, Other), "overlapping boxes")
Check(not BoxesOverlap(Box, NormalizeBox(10, 10, 10, 11, 11, 11)), "disjoint boxes")

Check(IsValidBlockPosition(0, 0, 0), "accepts y = 0")
Check(IsValidBlockPosition(0, 255, 0), "accepts y = 255")
Check(not IsValidBlockPosition(0, 256, 0), "refuses y = 256")
Check(not IsValidBlockPosition(30000001, 0, 0), "refuses x beyond 30,000,000")

-- Fakes ----------------------------------------------------------------------

E_BLOCK_AIR = 0
E_BLOCK_STONE = 1
E_BLOCK_DIRT = 3

Vector3i = function (a_X, a_Y, a_Z) return { x = a_X, y = a_Y, z = a_Z } end

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

ResolveBlockType = function (a_Name)
	if (a_Name == "stone") then return E_BLOCK_STONE end
	if (a_Name == "dirt") then return E_BLOCK_DIRT end
	return nil
end

local function Key(a_Pos)
	return a_Pos.x .. ":" .. a_Pos.y .. ":" .. a_Pos.z
end

local function MakeWorld()
	local World = { Blocks = {}, Drops = {} }
	function World:GetBlockTypeMeta(a_Pos)
		local Entry = self.Blocks[Key(a_Pos)]
		if (Entry == nil) then
			return true, E_BLOCK_AIR, 0
		end
		return true, Entry.Type, Entry.Meta
	end
	function World:SetBlock(a_Pos, a_Type, a_Meta)
		self.Blocks[Key(a_Pos)] = { Type = a_Type, Meta = a_Meta }
	end
	function World:DropBlockAsPickups(a_Pos)
		table.insert(self.Drops, Key(a_Pos))
	end
	function World:Get(a_X, a_Y, a_Z)
		local Entry = self.Blocks[a_X .. ":" .. a_Y .. ":" .. a_Z]
		if (Entry == nil) then return E_BLOCK_AIR end
		return Entry.Type
	end
	return World
end

local function MakeOrigin(a_World, a_X, a_Y, a_Z)
	return
	{
		GetWorld = function () return a_World end,
		GetPosition = function () return { x = a_X, y = a_Y, z = a_Z } end,
	}
end

local function MakeArea()
	local Area = { Data = {}, Size = { x = 0, y = 0, z = 0 }, Origin = { x = 0, y = 0, z = 0 } }
	function Area:Read(a_World, a_P1, a_P2)
		self.Origin = { x = a_P1.x, y = a_P1.y, z = a_P1.z }
		self.Size = { x = a_P2.x - a_P1.x + 1, y = a_P2.y - a_P1.y + 1, z = a_P2.z - a_P1.z + 1 }
		for Y = 0, self.Size.y - 1 do
			for Z = 0, self.Size.z - 1 do
				for X = 0, self.Size.x - 1 do
					local _, Type, Meta = a_World:GetBlockTypeMeta(Vector3i(a_P1.x + X, a_P1.y + Y,
						a_P1.z + Z))
					self.Data[X .. ":" .. Y .. ":" .. Z] = { Type = Type, Meta = Meta }
				end
			end
		end
		return true
	end
	function Area:Write(a_World, a_Pos)
		for Y = 0, self.Size.y - 1 do
			for Z = 0, self.Size.z - 1 do
				for X = 0, self.Size.x - 1 do
					local Entry = self.Data[X .. ":" .. Y .. ":" .. Z]
					a_World:SetBlock(Vector3i(a_Pos.x + X, a_Pos.y + Y, a_Pos.z + Z), Entry.Type,
						Entry.Meta)
				end
			end
		end
		return true
	end
	function Area:GetRelBlockTypeMeta(a_Pos)
		local Entry = self.Data[a_Pos.x .. ":" .. a_Pos.y .. ":" .. a_Pos.z]
		return Entry.Type, Entry.Meta
	end
	return Area
end

cBlockArea = setmetatable(
	{ baTypes = 1, baMetas = 2, baBlockEntities = 32 },
	{ __call = function () return MakeArea() end }
)

-- /setblock ------------------------------------------------------------------

local World = MakeWorld()
local Origin = MakeOrigin(World, 0, 0, 0)
local Ok, Message, Count = HandleSetBlockCommand({ "setblock", "1", "5", "1", "stone" }, nil, nil, Origin)
CheckEquals(Ok, true, "setblock returns true")
CheckEquals(World:Get(1, 5, 1), E_BLOCK_STONE, "setblock places the block")
CheckEquals(Count, 1, "setblock success count")
Check(Message == "Block placed", "setblock feedback")

Messages = {}
Ok, Message = HandleSetBlockCommand({ "setblock", "1", "5", "1", "stone" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("already the same", 1, true) ~= nil,
	"setblock refuses an identical block")

Messages = {}
Ok, Message = HandleSetBlockCommand({ "setblock", "1", "5", "1", "dirt", "0", "keep" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("not air", 1, true) ~= nil, "setblock keep refuses a non-air block")

World:SetBlock(Vector3i(2, 5, 2), E_BLOCK_DIRT, 0)
World.Drops = {}
HandleSetBlockCommand({ "setblock", "2", "5", "2", "stone", "0", "destroy" }, nil, nil, Origin)
CheckEquals(World:Get(2, 5, 2), E_BLOCK_STONE, "setblock destroy places the block")
CheckEquals(#World.Drops, 1, "setblock destroy drops the old block")

Messages = {}
Ok, Message = HandleSetBlockCommand({ "setblock", "1", "5", "1", "bogus" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("Unknown block", 1, true) ~= nil, "setblock refuses an unknown block")

-- /fill ----------------------------------------------------------------------

World = MakeWorld()
Origin = MakeOrigin(World, 0, 0, 0)
Ok, Message, Count = HandleFillCommand({ "fill", "0", "5", "0", "1", "5", "1", "stone" }, nil, nil, Origin)
CheckEquals(Ok, true, "fill returns true")
CheckEquals(Count, 4, "fill changes four blocks")
CheckEquals(World:Get(0, 5, 0), E_BLOCK_STONE, "fill sets the first block")
CheckEquals(World:Get(1, 5, 1), E_BLOCK_STONE, "fill sets the last block")

Messages = {}
Ok, Message = HandleFillCommand({ "fill", "0", "5", "0", "1", "5", "1", "stone" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("No blocks were changed", 1, true) ~= nil,
	"fill refuses a region that changes nothing")

World:SetBlock(Vector3i(5, 5, 5), E_BLOCK_DIRT, 0)
Count = nil
Ok, Message, Count = HandleFillCommand({ "fill", "5", "5", "5", "5", "5", "5", "stone", "0", "keep" },
	nil, nil, Origin)
CheckEquals(Ok, true, "fill keep succeeds on a non-air block with no change")
Check(Message ~= nil and Message:find("No blocks were changed", 1, true) ~= nil,
	"fill keep does nothing on a non-air block")

Messages = {}
Ok, Message = HandleFillCommand({ "fill", "0", "0", "0", "32", "32", "32", "stone" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("more than 32768", 1, true) ~= nil, "fill refuses a too large region")

Messages = {}
Ok, Message = HandleFillCommand({ "fill", "0", "5", "0", "2", "7", "2", "stone", "0", "hollow" },
	nil, nil, Origin)
CheckEquals(Ok, true, "fill hollow succeeds on a 3x3x3 region")
CheckEquals(World:Get(1, 6, 1), E_BLOCK_AIR, "fill hollow clears the interior")
CheckEquals(World:Get(0, 5, 0), E_BLOCK_STONE, "fill hollow fills the shell")

-- /clone ---------------------------------------------------------------------

World = MakeWorld()
Origin = MakeOrigin(World, 0, 0, 0)
World:SetBlock(Vector3i(0, 5, 0), E_BLOCK_STONE, 0)
World:SetBlock(Vector3i(1, 5, 1), E_BLOCK_DIRT, 0)
Ok, Message, Count = HandleCloneCommand({ "clone", "0", "5", "0", "1", "5", "1", "5", "5", "5" },
	nil, nil, Origin)
CheckEquals(Ok, true, "clone returns true")
CheckEquals(Count, 4, "clone copies four blocks")
CheckEquals(World:Get(5, 5, 5), E_BLOCK_STONE, "clone copies the first block")
CheckEquals(World:Get(6, 5, 6), E_BLOCK_DIRT, "clone copies the second block")

Messages = {}
Ok, Message = HandleCloneCommand({ "clone", "0", "5", "0", "1", "5", "1", "0", "5", "0" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("overlap", 1, true) ~= nil, "clone refuses an overlap")

Messages = {}
Ok, Message = HandleCloneCommand({ "clone", "0", "5", "0", "1", "5", "1", "9", "5", "9",
	"filtered", "normal", "dirt" }, nil, nil, Origin)
CheckEquals(Ok, true, "clone filtered succeeds")
CheckEquals(World:Get(9, 5, 9), E_BLOCK_AIR, "clone filtered skips non-matching blocks")
CheckEquals(World:Get(10, 5, 10), E_BLOCK_DIRT, "clone filtered copies the matching block")

-- /testforblocks -------------------------------------------------------------

World = MakeWorld()
Origin = MakeOrigin(World, 0, 0, 0)
World:SetBlock(Vector3i(0, 5, 0), E_BLOCK_STONE, 0)
World:SetBlock(Vector3i(1, 5, 1), E_BLOCK_DIRT, 0)
World:SetBlock(Vector3i(5, 5, 5), E_BLOCK_STONE, 0)
World:SetBlock(Vector3i(6, 5, 6), E_BLOCK_DIRT, 0)

Ok, Message, Count = HandleTestforblocksCommand(
	{ "testforblocks", "0", "5", "0", "1", "5", "1", "5", "5", "5" }, nil, nil, Origin)
CheckEquals(Ok, true, "testforblocks matches")
CheckEquals(Count, 4, "testforblocks all counts the whole volume")

World:SetBlock(Vector3i(6, 5, 6), E_BLOCK_STONE, 0)
Messages = {}
Ok, Message = HandleTestforblocksCommand(
	{ "testforblocks", "0", "5", "0", "1", "5", "1", "5", "5", "5" }, nil, nil, Origin)
Check(Message ~= nil and Message:find("do not match", 1, true) ~= nil, "testforblocks reports a mismatch")

-- masked: the source air blocks match anything and are not counted.
World:SetBlock(Vector3i(0, 5, 0), E_BLOCK_AIR, 0)
World:SetBlock(Vector3i(5, 5, 5), E_BLOCK_STONE, 0)
World:SetBlock(Vector3i(6, 5, 6), E_BLOCK_DIRT, 0)
Ok, Message, Count = HandleTestforblocksCommand(
	{ "testforblocks", "0", "5", "0", "1", "5", "1", "5", "5", "5", "masked" }, nil, nil, Origin)
CheckEquals(Ok, true, "testforblocks masked matches")
CheckEquals(Count, 1, "testforblocks masked counts only non-air source blocks")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
