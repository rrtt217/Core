-- cmd_testforblocks.lua
-- Implements the vanilla 1.12.2 /testforblocks command:
--   testforblocks <x1> <y1> <z1> <x2> <y2> <z2> <x> <y> <z> [all|masked]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-block-commands.md
--
-- Both regions are read through cBlockArea (C++ side) and then compared block by block; the success
-- count is the number of matching blocks: the whole volume in "all" mode, the number of non-air source
-- blocks in "masked" mode (spec section 2.5).

-- luacheck: ignore 131
-- luacheck: globals HandleTestforblocksCommand HandleConsoleTestforblocks
-- luacheck: globals ParseTestforblocksLine NormalizeBox GetVolume IsValidBlockPosition GetCommandWorld
-- luacheck: globals GetOriginPosition ParseCommandCoords
-- luacheck: globals SendMessageFailure SendMessageSuccess cBlockArea Vector3i

local MAX_TEST_VOLUME = 524288



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



function HandleTestforblocksCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseTestforblocksLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local World = GetCommandWorld(a_Player, a_Origin)
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to test blocks in"), 0
	end

	local Box, DestX, DestY, DestZ, RegionReason = ResolveRegions(Parse, GetOriginPosition(a_Origin))
	if (Box == nil) then
		return true, SendMessageFailure(a_Player, RegionReason), 0
	end

	if (GetVolume(Box) > MAX_TEST_VOLUME) then
		return true, SendMessageFailure(a_Player,
			"The source region has more than " .. MAX_TEST_VOLUME .. " blocks"), 0
	end

	local DataTypes = cBlockArea.baTypes + cBlockArea.baMetas
	local Source = cBlockArea()
	if (not Source:Read(World, Vector3i(Box.MinX, Box.MinY, Box.MinZ),
		Vector3i(Box.MaxX, Box.MaxY, Box.MaxZ), DataTypes)) then
		return true, SendMessageFailure(a_Player, "The source region is not loaded"), 0
	end
	local Destination = cBlockArea()
	if (not Destination:Read(World, Vector3i(DestX, DestY, DestZ),
		Vector3i(DestX + Box.MaxX - Box.MinX, DestY + Box.MaxY - Box.MinY,
			DestZ + Box.MaxZ - Box.MinZ), DataTypes)) then
		return true, SendMessageFailure(a_Player, "The destination region is not loaded"), 0
	end

	local Matched = 0
	for RelY = 0, Box.MaxY - Box.MinY do
		for RelZ = 0, Box.MaxZ - Box.MinZ do
			for RelX = 0, Box.MaxX - Box.MinX do
				local SourceType, SourceMeta = Source:GetRelBlockTypeMeta(Vector3i(RelX, RelY, RelZ))
				local DestType, DestMeta = Destination:GetRelBlockTypeMeta(Vector3i(RelX, RelY, RelZ))
				if ((Parse.Mode ~= "masked") or (SourceType ~= E_BLOCK_AIR)) then
					if ((SourceType ~= DestType) or (SourceMeta ~= DestMeta)) then
						return true, SendMessageFailure(a_Player, "The blocks do not match"), 0
					end
					Matched = Matched + 1
				end
			end
		end
	end

	return true, SendMessageSuccess(a_Player, "The blocks match"), Matched
end



function HandleConsoleTestforblocks(a_Split, _, _, a_Origin)
	return HandleTestforblocksCommand(a_Split, nil, nil, a_Origin)
end
