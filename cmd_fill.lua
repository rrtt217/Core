-- cmd_fill.lua
-- Implements the vanilla 1.12.2 /fill command:
--   fill <x1> <y1> <z1> <x2> <y2> <z2> <block> [dataValue] [oldBlockHandling] [dataTag]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-block-commands.md
--
-- The region is filled block by block through cWorld:SetBlock(); /clone uses cBlockArea instead because
-- it has to copy block entities too. The loaded-chunk check runs over the whole region before the first
-- write, so a refusal never leaves a half-filled area.

-- luacheck: ignore 131
-- luacheck: globals HandleFillCommand HandleConsoleFill
-- luacheck: globals ParseFillLine NormalizeBox GetVolume IsValidBlockPosition GetCommandWorld
-- luacheck: globals GetOriginPosition ParseCommandCoords ResolveBlockType
-- luacheck: globals SendMessageFailure SendMessageSuccess

local MAX_FILL_VOLUME = 32768



local function ForEachBlock(a_Box, a_Callback)
	for Y = a_Box.MinY, a_Box.MaxY do
		for Z = a_Box.MinZ, a_Box.MaxZ do
			for X = a_Box.MinX, a_Box.MaxX do
				a_Callback(X, Y, Z)
			end
		end
	end
end



local function IsShell(a_Box, a_X, a_Y, a_Z)
	return
		(a_X == a_Box.MinX) or (a_X == a_Box.MaxX) or
		(a_Y == a_Box.MinY) or (a_Y == a_Box.MaxY) or
		(a_Z == a_Box.MinZ) or (a_Z == a_Box.MaxZ)
end



--- Resolves and validates the two opposite corners. Returns the box or nil plus a reason.
local function ResolveBox(a_Parse, a_Position)
	local X1, Y1, Z1 = ParseCommandCoords(a_Parse.X1, a_Parse.Y1, a_Parse.Z1, a_Position)
	if (X1 == nil) then
		return nil, Y1
	end
	local X2, Y2, Z2 = ParseCommandCoords(a_Parse.X2, a_Parse.Y2, a_Parse.Z2, a_Position)
	if (X2 == nil) then
		return nil, Y2
	end

	local Box = NormalizeBox(math.floor(X1), math.floor(Y1), math.floor(Z1),
		math.floor(X2), math.floor(Y2), math.floor(Z2))
	local Ok, Reason = IsValidBlockPosition(Box.MinX, Box.MinY, Box.MinZ)
	if (not Ok) then
		return nil, Reason
	end
	Ok, Reason = IsValidBlockPosition(Box.MaxX, Box.MaxY, Box.MaxZ)
	if (not Ok) then
		return nil, Reason
	end
	return Box
end



function HandleFillCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseFillLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local World = GetCommandWorld(a_Player, a_Origin)
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to fill blocks in"), 0
	end

	local Box, BoxReason = ResolveBox(Parse, GetOriginPosition(a_Origin))
	if (Box == nil) then
		return true, SendMessageFailure(a_Player, BoxReason), 0
	end

	if (GetVolume(Box) > MAX_FILL_VOLUME) then
		return true, SendMessageFailure(a_Player,
			"The region has more than " .. MAX_FILL_VOLUME .. " blocks"), 0
	end

	local BlockType = ResolveBlockType(Parse.Block)
	if (BlockType == nil) then
		return true, SendMessageFailure(a_Player, "Unknown block \"" .. Parse.Block .. "\""), 0
	end

	local ReplaceType = nil
	if (Parse.Replace ~= nil) then
		ReplaceType = ResolveBlockType(Parse.Replace.Name)
		if (ReplaceType == nil) then
			return true, SendMessageFailure(a_Player,
				"Unknown block \"" .. Parse.Replace.Name .. "\""), 0
		end
	end

	-- Refuse before the first write when any chunk of the region is not loaded:
	local Loaded = true
	ForEachBlock(Box,
		function (a_X, a_Y, a_Z)
			if (Loaded) then
				local BlockValid = World:GetBlockTypeMeta(Vector3i(a_X, a_Y, a_Z))
				if (not BlockValid) then
					Loaded = false
				end
			end
		end
	)
	if (not Loaded) then
		return true, SendMessageFailure(a_Player, "The region is not fully loaded"), 0
	end

	-- "hollow" and "outline" act like "replace" when the region has no interior:
	local SmallRegion =
		((Box.MaxX - Box.MinX) < 2) or ((Box.MaxY - Box.MinY) < 2) or ((Box.MaxZ - Box.MinZ) < 2)
	local Changed = 0

	ForEachBlock(Box,
		function (a_X, a_Y, a_Z)
			local _, OldType, OldMeta = World:GetBlockTypeMeta(Vector3i(a_X, a_Y, a_Z))
			local Action = nil
			local Different = (OldType ~= BlockType) or (OldMeta ~= Parse.Data)

			if (Parse.Mode == "replace") then
				local MatchesFilter = (Parse.Replace == nil) or
					((OldType == ReplaceType) and
					 ((Parse.Replace.Data == nil) or (OldMeta == Parse.Replace.Data)))
				if (MatchesFilter and Different) then
					Action = "set"
				end
			elseif (Parse.Mode == "keep") then
				if ((OldType == E_BLOCK_AIR) and Different) then
					Action = "set"
				end
			elseif (Parse.Mode == "destroy") then
				Action = "destroy"
			elseif ((Parse.Mode == "hollow") or (Parse.Mode == "outline")) then
				if (SmallRegion or IsShell(Box, a_X, a_Y, a_Z)) then
					if (Different) then
						Action = "set"
					end
				elseif (Parse.Mode == "hollow") and (OldType ~= E_BLOCK_AIR) then
					Action = "air"
				end
			end

			if (Action == "set") then
				World:SetBlock(Vector3i(a_X, a_Y, a_Z), BlockType, Parse.Data)
				Changed = Changed + 1
			elseif (Action == "air") then
				World:SetBlock(Vector3i(a_X, a_Y, a_Z), E_BLOCK_AIR, 0)
				Changed = Changed + 1
			elseif (Action == "destroy") then
				if (OldType ~= E_BLOCK_AIR) then
					World:DropBlockAsPickups(Vector3i(a_X, a_Y, a_Z), nil, nil)
				end
				World:SetBlock(Vector3i(a_X, a_Y, a_Z), BlockType, Parse.Data)
				Changed = Changed + 1
			end
		end
	)

	if (Changed == 0) then
		return true, SendMessageFailure(a_Player, "No blocks were changed"), 0
	end
	return true, SendMessageSuccess(a_Player, "Successfully filled " .. Changed .. " blocks"), Changed
end



function HandleConsoleFill(a_Split, _, _, a_Origin)
	return HandleFillCommand(a_Split, nil, nil, a_Origin)
end
