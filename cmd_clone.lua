-- cmd_clone.lua
-- Implements the vanilla 1.12.2 /clone command:
--   clone <x1> <y1> <z1> <x2> <y2> <z2> <x> <y> <z> [maskMode] [cloneMode] [TileName] [dataValue]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-block-commands.md
--
-- The source region is read through cBlockArea, which also carries the block entities, so the "replace"
-- mask mode copies chests and signs with their contents. "masked" and "filtered" have to be applied block
-- by block and therefore cannot carry block entities (recorded deviation, spec section 4.2).

-- luacheck: ignore 131
-- luacheck: globals HandleCloneCommand HandleConsoleClone
-- luacheck: globals ParseCloneLine NormalizeBox GetVolume IsValidBlockPosition GetCommandWorld BoxesOverlap
-- luacheck: globals GetOriginPosition ParseCommandCoords ResolveBlockType
-- luacheck: globals SendMessageFailure SendMessageSuccess cBlockArea Vector3i

local MAX_CLONE_VOLUME = 32768



--- Resolves the source box and the destination corner. Returns box, destX, destY, destZ or nil + reason.
local function ResolveRegions(a_Parse, a_Position)
	local X1, Y1, Z1 = ParseCommandCoords(a_Parse.X1, a_Parse.Y1, a_Parse.Z1, a_Position)
	if (X1 == nil) then
		return nil, nil, nil, nil, Y1
	end
	local X2, Y2, Z2 = ParseCommandCoords(a_Parse.X2, a_Parse.Y2, a_Parse.Z2, a_Position)
	if (X2 == nil) then
		return nil, nil, nil, nil, Y2
	end
	local X, Y, Z = ParseCommandCoords(a_Parse.X, a_Parse.Y, a_Parse.Z, a_Position)
	if (X == nil) then
		return nil, nil, nil, nil, Y
	end

	local Box = NormalizeBox(math.floor(X1), math.floor(Y1), math.floor(Z1),
		math.floor(X2), math.floor(Y2), math.floor(Z2))
	local Ok, Reason = IsValidBlockPosition(Box.MinX, Box.MinY, Box.MinZ)
	if (not Ok) then
		return nil, nil, nil, nil, Reason
	end

	X, Y, Z = math.floor(X), math.floor(Y), math.floor(Z)
	Ok, Reason = IsValidBlockPosition(X, Y, Z)
	if (not Ok) then
		return nil, nil, nil, nil, Reason
	end
	Ok, Reason = IsValidBlockPosition(X + Box.MaxX - Box.MinX, Y + Box.MaxY - Box.MinY,
		Z + Box.MaxZ - Box.MinZ)
	if (not Ok) then
		return nil, nil, nil, nil, Reason
	end
	return Box, X, Y, Z
end



--- Returns true when every block of the destination region is in a loaded chunk.
local function IsDestinationLoaded(a_World, a_Box, a_DestX, a_DestY, a_DestZ)
	for Y = 0, a_Box.MaxY - a_Box.MinY do
		for Z = 0, a_Box.MaxZ - a_Box.MinZ do
			for X = 0, a_Box.MaxX - a_Box.MinX do
				local BlockValid = a_World:GetBlockTypeMeta(Vector3i(a_DestX + X, a_DestY + Y, a_DestZ + Z))
				if (not BlockValid) then
					return false
				end
			end
		end
	end
	return true
end



function HandleCloneCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseCloneLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local World = GetCommandWorld(a_Player, a_Origin)
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to clone blocks in"), 0
	end

	local Box, DestX, DestY, DestZ, RegionReason = ResolveRegions(Parse, GetOriginPosition(a_Origin))
	if (Box == nil) then
		return true, SendMessageFailure(a_Player, RegionReason), 0
	end

	if (GetVolume(Box) > MAX_CLONE_VOLUME) then
		return true, SendMessageFailure(a_Player,
			"The source region has more than " .. MAX_CLONE_VOLUME .. " blocks"), 0
	end

	local DestBox = NormalizeBox(DestX, DestY, DestZ,
		DestX + Box.MaxX - Box.MinX, DestY + Box.MaxY - Box.MinY, DestZ + Box.MaxZ - Box.MinZ)
	if ((Parse.CloneMode ~= "force") and BoxesOverlap(Box, DestBox)) then
		return true, SendMessageFailure(a_Player, "The source and destination regions overlap"), 0
	end

	local FilterType = nil
	if (Parse.Filter ~= nil) then
		FilterType = ResolveBlockType(Parse.Filter.Name)
		if (FilterType == nil) then
			return true, SendMessageFailure(a_Player,
				"Unknown block \"" .. Parse.Filter.Name .. "\""), 0
		end
	end

	local DataTypes = cBlockArea.baTypes + cBlockArea.baMetas + cBlockArea.baBlockEntities
	local Area = cBlockArea()
	if (not Area:Read(World, Vector3i(Box.MinX, Box.MinY, Box.MinZ),
		Vector3i(Box.MaxX, Box.MaxY, Box.MaxZ), DataTypes)) then
		return true, SendMessageFailure(a_Player, "The source region is not loaded"), 0
	end
	if (not IsDestinationLoaded(World, Box, DestX, DestY, DestZ)) then
		return true, SendMessageFailure(a_Player, "The destination region is not loaded"), 0
	end

	local Changed = 0
	local SizeX = Box.MaxX - Box.MinX + 1
	local SizeY = Box.MaxY - Box.MinY + 1
	local SizeZ = Box.MaxZ - Box.MinZ + 1

	if (Parse.MaskMode == "replace") then
		if (not Area:Write(World, Vector3i(DestX, DestY, DestZ), DataTypes)) then
			return true, SendMessageFailure(a_Player, "The blocks could not be cloned"), 0
		end
		Changed = SizeX * SizeY * SizeZ
	else
		for RelY = 0, SizeY - 1 do
			for RelZ = 0, SizeZ - 1 do
				for RelX = 0, SizeX - 1 do
					local BlockType, BlockMeta = Area:GetRelBlockTypeMeta(Vector3i(RelX, RelY, RelZ))
					local Copy
					if (Parse.MaskMode == "masked") then
						Copy = (BlockType ~= E_BLOCK_AIR)
					else
						Copy = (BlockType == FilterType) and
							((Parse.Filter.Data == nil) or (BlockMeta == Parse.Filter.Data))
					end
					if (Copy) then
						World:SetBlock(Vector3i(DestX + RelX, DestY + RelY, DestZ + RelZ), BlockType,
							BlockMeta)
						Changed = Changed + 1
					end
				end
			end
		end
	end

	if (Parse.CloneMode == "move") then
		for RelY = 0, SizeY - 1 do
			for RelZ = 0, SizeZ - 1 do
				for RelX = 0, SizeX - 1 do
					local Clear = true
					if (Parse.MaskMode == "filtered") then
						local BlockType, BlockMeta = Area:GetRelBlockTypeMeta(Vector3i(RelX, RelY, RelZ))
						Clear = (BlockType == FilterType) and
							((Parse.Filter.Data == nil) or (BlockMeta == Parse.Filter.Data))
					end
					if (Clear) then
						World:SetBlock(Vector3i(Box.MinX + RelX, Box.MinY + RelY, Box.MinZ + RelZ),
							E_BLOCK_AIR, 0)
					end
				end
			end
		end
	end

	if (Changed == 0) then
		return true, SendMessageFailure(a_Player, "No blocks were cloned"), 0
	end
	return true, SendMessageSuccess(a_Player, "Successfully cloned " .. Changed .. " blocks"), Changed
end



function HandleConsoleClone(a_Split, _, _, a_Origin)
	return HandleCloneCommand(a_Split, nil, nil, a_Origin)
end
