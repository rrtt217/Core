-- cmd_testforblock.lua
-- Implements the /testforblock command for Core, following vanilla Java Edition 1.12.2:
--   testforblock <x> <y> <z> <block> [<dataValue>]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-execute-and-testfor.md
-- On success the command reports a success count of 1, which is what a comparator reads from the command block
-- that ran it.

-- luacheck: new globals HandleTestforblockCommand HandleConsoleTestforblock
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess GetOriginPosition ParseCommandCoords
-- luacheck: globals ParseTestforblockLine ResolveBlockType
-- luacheck: globals cRoot Vector3i

function HandleTestforblockCommand(Split, Player, _, Origin)
	if (not Split[5]) then
		return true, SendMessageFailure(Player, "Usage: " .. Split[1] .. " <x> <y> <z> <block> [<dataValue>]"), 0
	end

	local Parse, Reason = ParseTestforblockLine(Split)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, Reason), 0
	end

	-- "May use tilde notation to specify a position relative to the command's execution". On failure
	-- ParseCommandCoords() returns nil plus the reason as its second value:
	local CoordX, CoordY, CoordZ = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, GetOriginPosition(Origin))
	if (CoordX == nil) then
		return true, SendMessageFailure(Player, CoordY), 0
	end
	local BlockX = math.floor(CoordX)
	local BlockY = math.floor(CoordY)
	local BlockZ = math.floor(CoordZ)
	local Where = BlockX .. ", " .. BlockY .. ", " .. BlockZ

	local BlockType = ResolveBlockType(Parse.Block)
	if (BlockType == nil) then
		return true, SendMessageFailure(Player, "Unknown block \"" .. Parse.Block .. "\""), 0
	end

	local World = nil
	if (Origin ~= nil) then
		World = Origin:GetWorld()
	end
	if (World == nil) then
		World = cRoot:Get():GetDefaultWorld()
	end

	-- cWorld:GetBlockTypeMeta() answers "readable?, type, meta". Its two failure shapes are distinguishable: a
	-- chunk that is not loaded answers false, while a position outside the world height answers plain air (the
	-- first value is then a number, not the flag):
	local Readable, FoundType, FoundMeta = World:GetBlockTypeMeta(Vector3i(BlockX, BlockY, BlockZ))
	if (Readable == false) then
		return true, SendMessageFailure(Player, "The chunk of the block at " .. Where .. " is not loaded"), 0
	end
	if (Readable ~= true) then
		return true, SendMessageFailure(Player, "The block at " .. Where .. " is outside of the world"), 0
	end

	if (FoundType ~= BlockType) then
		return true, SendMessageFailure(Player, "The block at " .. Where .. " is not \"" .. Parse.Block .. "\""), 0
	end
	if ((Parse.Data ~= nil) and (FoundMeta ~= Parse.Data)) then
		return true, SendMessageFailure(Player, "The block at " .. Where .. " has a different block data"), 0
	end

	-- 1.12.2: "On success, returns a success count of 1":
	return true, SendMessageSuccess(Player, "The block at " .. Where .. " is \"" .. Parse.Block .. "\""), 1
end

function HandleConsoleTestforblock(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleTestforblockCommand(Split, nil, EntireCommand, Origin)
end
