-- target_snapshot.lua
--
-- Snapshots the entity properties that the target selector layer filters on,
-- once per world tick, on the world's own thread.
--
-- Why this exists:
--   Enumerating entities (cWorld:ForEachEntity / cRoot:ForEachPlayer) holds the
--   world's chunkmap lock for the whole callback. A command that already holds
--   Core's Lua lock must therefore not enumerate: the world thread holds the
--   chunkmap lock inside cWorld::TickMobs and then asks for the same Lua lock
--   when a hook fires (Core registers HOOK_TAKE_DAMAGE), so the two threads wait
--   for each other and the server deadlocks. Building the snapshot from
--   HOOK_WORLD_TICK keeps the enumeration on the world thread, where taking that
--   world's own lock is safe.
--
-- Invariants:
--   * A snapshot never stores a cEntity reference. ChunkDef.h defines OwnedEntity
--     as std::unique_ptr<cEntity>, so every entity is uniquely owned by its chunk
--     and can be freed by the world thread at any moment; a stored reference would
--     dangle. Only value copies (unique ID, position, ...) are kept.
--   * Actions never run on snapshots: ApplyToTargets re-resolves them by unique ID
--     on the owning world thread.
--   * A proxy mirrors every accessor the selector layer calls on a live cEntity,
--     so the filtering code stays unchanged (duck typing).
--   * A world that has never ticked has an empty snapshot, which matches the "no
--     entities loaded yet" reality.

-- luacheck: globals TargetSnapshot

TargetSnapshot = {}


--- [WorldName] = { Players = {...}, Pawns = {...} }, rebuilt on every world tick
local g_Worlds = {}


--- Proxies are value copies of entities. They answer the same calls as a live
--- cEntity for everything the selector layer filters on, but they must never be
--- passed to an API that expects a real entity.
local ProxyMeta = {}
ProxyMeta.__index = ProxyMeta

function ProxyMeta:GetUniqueID()          return self.UniqueID end
function ProxyMeta:IsPlayer()             return self.Player end
function ProxyMeta:IsMob()                return self.Mob end
function ProxyMeta.IsPawn()               return true end
function ProxyMeta:GetMobType()           return self.MobType end
function ProxyMeta:GetName()              return self.Name end
function ProxyMeta:GetCustomName()        return self.CustomName end
function ProxyMeta:GetXpLevel()           return self.XpLevel end
function ProxyMeta:IsGameModeSurvival()   return self.Survival end
function ProxyMeta:IsGameModeCreative()   return self.Creative end
function ProxyMeta:IsGameModeAdventure()  return self.Adventure end
function ProxyMeta:IsGameModeSpectator()  return self.Spectator end
function ProxyMeta:GetPosition()          return self.Position end
function ProxyMeta:GetBoundingBox()       return self.BoundingBox end

--- cEntity:GetWorld() returns a cWorld, but carrying a cWorld across ticks is
--- unnecessary: the whole selector layer compares worlds, and the origin is the
--- world the executing player (or the command block) is in. Proxies therefore
--- answer with the world *name*, and the selector layer compares names.
function ProxyMeta:GetWorld()             return self.WorldName end

--- Mirrors cPlayer:GetTeam(), which returns nil or a team object with GetName().
function ProxyMeta:GetTeam()
	local TeamName = self.TeamName
	if (TeamName == nil) then
		return nil
	end
	return { GetName = function () return TeamName end }
end





--- Copies the properties of a live entity into a proxy.
--- Call it only while the entity is known to be alive (inside an enumeration
--- callback, or for the command executor) -- never after the fact.
function TargetSnapshot.MakeProxy(a_Entity, a_WorldName)
	local IsPlayer = a_Entity:IsPlayer()
	local IsMob = (not IsPlayer) and a_Entity:IsMob()

	local TeamName = nil
	if (IsPlayer) then
		local Team = a_Entity:GetTeam()
		if (Team ~= nil) then
			TeamName = Team:GetName()
		end
	end

	local Proxy =
	{
		UniqueID = a_Entity:GetUniqueID(),
		WorldName = a_WorldName,
		Player = IsPlayer,
		Mob = IsMob,
		Position = a_Entity:GetPosition(),
		BoundingBox = a_Entity:GetBoundingBox(),
	}
	if (IsPlayer) then
		Proxy.Name = a_Entity:GetName()
		Proxy.XpLevel = a_Entity:GetXpLevel()
		Proxy.Survival = a_Entity:IsGameModeSurvival()
		Proxy.Creative = a_Entity:IsGameModeCreative()
		Proxy.Adventure = a_Entity:IsGameModeAdventure()
		Proxy.Spectator = a_Entity:IsGameModeSpectator()
		Proxy.TeamName = TeamName
	elseif (IsMob) then
		Proxy.MobType = a_Entity:GetMobType()
		Proxy.CustomName = a_Entity:GetCustomName()
	end
	return setmetatable(Proxy, ProxyMeta)
end





--- Rebuilds one world's snapshot. Must run on that world's own thread: players
--- live in the chunk map too, so the single ForEachEntity pass covers both lists.
function TargetSnapshot.RefreshWorld(a_World)
	local WorldName = a_World:GetName()
	local Snapshot = { Players = {}, Pawns = {} }
	a_World:ForEachEntity(
		function (a_Entity)
			if (not a_Entity:IsPawn()) then
				return false
			end
			local Proxy = TargetSnapshot.MakeProxy(a_Entity, WorldName)
			table.insert(Snapshot.Pawns, Proxy)
			if (Proxy.Player) then
				table.insert(Snapshot.Players, Proxy)
			end
			return false
		end
	)
	g_Worlds[WorldName] = Snapshot
end





--- HOOK_WORLD_TICK handler. cWorld::Tick calls it at the very top, before the
--- chunkmap lock is taken, so this is the one place Core may enumerate safely.
function TargetSnapshot.OnWorldTick(a_World)
	TargetSnapshot.RefreshWorld(a_World)
end





--- Returns the current snapshot of a world; never nil. A world that has not
--- ticked yet yields empty lists, never stale state from a previous world.
function TargetSnapshot.GetWorld(a_WorldName)
	local Snapshot = g_Worlds[a_WorldName]
	if (Snapshot == nil) then
		Snapshot = { Players = {}, Pawns = {} }
		g_Worlds[a_WorldName] = Snapshot
	end
	return Snapshot
end





function TargetSnapshot.GetPlayers(a_WorldName)
	return TargetSnapshot.GetWorld(a_WorldName).Players
end





function TargetSnapshot.GetPawns(a_WorldName)
	return TargetSnapshot.GetWorld(a_WorldName).Pawns
end





--- Concatenates one list of every world that has a snapshot. The order across
--- worlds is unspecified; the selector layer sorts whatever needs ordering.
local function ConcatLists(a_Field)
	local Result = {}
	for _, Snapshot in pairs(g_Worlds) do
		for _, Proxy in ipairs(Snapshot[a_Field]) do
			table.insert(Result, Proxy)
		end
	end
	return Result
end





function TargetSnapshot.GetAllPlayers()
	return ConcatLists("Players")
end





function TargetSnapshot.GetAllPawns()
	return ConcatLists("Pawns")
end
