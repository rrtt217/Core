-- cmd_spreadplayers.lua
-- Implements the vanilla 1.12.2 /spreadplayers command:
--   spreadplayers <x> <z> <spreadDistance> <maxRange> <respectTeams> <player ...>
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-movement-commands.md
--
-- The sampling algorithm is not documented by the allowed sources; command_movement.lua documents and
-- tests the approximation used here. Only loaded chunks are considered when looking for a surface.

-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global in
-- this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: globals HandleSpreadplayersCommand HandleConsoleSpreadplayers
-- luacheck: globals ParseSpreadplayersLine PickSpreadPositions
-- luacheck: globals GetOriginPosition ParseCommandCoord SendMessageFailure SendMessageSuccess
-- luacheck: globals ResolveTargets MakeSelectorContext

local MAX_HORIZONTAL = 30000000



--- Returns the block type at a position (the vector overload avoids the deprecated 3-number form).
local function GetBlockAt(a_World, a_X, a_Y, a_Z)
	return a_World:GetBlock(Vector3i(a_X, a_Y, a_Z))
end



--- Returns the Y a target stands at in the given column, or nil when the column cannot hold one.
-- TryGetHeight() yields the highest non-air block; the target stands one above it (spec section 2.2).
local function GetSurfaceY(a_World, a_BlockX, a_BlockZ)
	local Valid, Height = a_World:TryGetHeight(a_BlockX, a_BlockZ)
	if (not Valid) then
		-- The chunk is not loaded. Generating it from the tick thread would stall the server, so this
		-- candidate is skipped and the sampler retries (recorded deviation, spec section 4.2):
		return nil
	end

	local Under = GetBlockAt(a_World, a_BlockX, Height, a_BlockZ)
	if ((Under == E_BLOCK_AIR) or (Under == E_BLOCK_LAVA) or (Under == E_BLOCK_STATIONARY_LAVA)) then
		return nil
	end

	local FeetY = Height + 1
	for Offset = 0, 1 do
		local Block = GetBlockAt(a_World, a_BlockX, FeetY + Offset, a_BlockZ)
		if ((Block == E_BLOCK_LAVA) or (Block == E_BLOCK_STATIONARY_LAVA)) then
			return nil
		end
	end
	return FeetY
end



--- Groups the targets for the placement: one group per team when a_RespectTeams is true, otherwise one
-- group per entity. Returns an array of arrays.
local function MakeGroups(a_Entities, a_RespectTeams)
	local Groups = {}
	local GroupIndex = {}
	for _, Entity in ipairs(a_Entities) do
		local Key = nil
		if (a_RespectTeams and Entity:IsPlayer()) then
			local Team = Entity:GetTeam()
			if (Team ~= nil) then
				Key = "team:" .. Team:GetName()
			end
		end
		if (Key == nil) then
			Key = "entity:" .. Entity:GetUniqueID()
		end

		local Index = GroupIndex[Key]
		if (Index == nil) then
			table.insert(Groups, {})
			Index = #Groups
			GroupIndex[Key] = Index
		end
		table.insert(Groups[Index], Entity)
	end
	return Groups
end



function HandleSpreadplayersCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseSpreadplayersLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local World = nil
	if (a_Origin ~= nil) then
		World = a_Origin:GetWorld()
	end
	if ((World == nil) and (a_Player ~= nil)) then
		World = a_Player:GetWorld()
	end
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to spread the targets in"), 0
	end

	local Position = GetOriginPosition(a_Origin)
	local CenterX, CoordReason = ParseCommandCoord(Parse.X, "x", Position)
	if (CenterX == nil) then
		return true, SendMessageFailure(a_Player, CoordReason), 0
	end
	local CenterZ
	CenterZ, CoordReason = ParseCommandCoord(Parse.Z, "z", Position)
	if (CenterZ == nil) then
		return true, SendMessageFailure(a_Player, CoordReason), 0
	end
	if ((math.abs(CenterX) >= MAX_HORIZONTAL) or (math.abs(CenterZ) >= MAX_HORIZONTAL)) then
		return true, SendMessageFailure(a_Player,
			"The x and z coordinates must be between -30,000,000 and 30,000,000 (exclusive)"), 0
	end

	-- The surface lookup and the teleport happen in the origin world; spreading targets across worlds
	-- would use one world's height map for another world's entities (recorded deviation, spec section 4.2):
	local Context = MakeSelectorContext(a_Player, a_Origin)
	Context.LocalOnly = true

	-- Several arguments are allowed and they may repeat the same entity; collect each entity once:
	local Seen = {}
	local Entities = {}
	for _, Token in ipairs(Parse.Targets) do
		local Found, TokenReason = ResolveTargets(Token, Context, "entity")
		if (Found == nil) then
			return true, SendMessageFailure(a_Player, TokenReason), 0
		end
		for _, Entity in ipairs(Found) do
			local ID = Entity:GetUniqueID()
			if (not Seen[ID]) then
				Seen[ID] = true
				table.insert(Entities, Entity)
			end
		end
	end
	if (#Entities == 0) then
		return true, SendMessageFailure(a_Player, "No entity was found"), 0
	end

	local Groups = MakeGroups(Entities, Parse.RespectTeams)
	local Positions, PickReason = PickSpreadPositions(#Groups, CenterX, CenterZ, Parse.SpreadDistance,
		Parse.MaxRange,
		function (a_BlockX, a_BlockZ)
			return GetSurfaceY(World, a_BlockX, a_BlockZ)
		end,
		math.random)
	if (Positions == nil) then
		return true, SendMessageFailure(a_Player, PickReason), 0
	end

	local Count = 0
	for Index, Group in ipairs(Groups) do
		local Spot = Positions[Index]
		for _, Entity in ipairs(Group) do
			Entity:TeleportToCoords(Spot.X, Spot.Y, Spot.Z)
			Count = Count + 1
		end
	end

	local Noun = "targets"
	if (Count == 1) then
		Noun = "target"
	end
	return true, SendMessageSuccess(a_Player, string.format("Spread %d %s around %d, %d", Count, Noun,
		math.floor(CenterX), math.floor(CenterZ))), Count
end



function HandleConsoleSpreadplayers(a_Split, _, _, a_Origin)
	return HandleSpreadplayersCommand(a_Split, nil, nil, a_Origin)
end
