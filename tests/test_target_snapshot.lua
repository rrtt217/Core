-- test_target_snapshot.lua
--
-- Table-driven tests for Core's world-tick entity snapshot (target_snapshot.lua).
--
-- Verified specification: the "candidate C phase 1" note in
-- specs/vanilla-1.12.2-command-blocks.md (parent repository). The snapshot exists
-- so that the target selector layer never enumerates entities from a command
-- thread, where taking a world's chunkmap lock while Core's Lua lock is held
-- deadlocks against the world thread (see the spec section for the analysis).
--
-- Invariants:
--   * RefreshWorld() copies values only. No proxy keeps (or exposes) a cEntity
--     reference: ChunkDef.h defines OwnedEntity as std::unique_ptr<cEntity>, so
--     entities can be freed by their world thread at any moment.
--   * A proxy answers the same accessor calls as a live cEntity for everything
--     the selector layer filters on.
--   * GetWorld() of a never-ticked world is empty, and a refresh replaces the
--     previous snapshot instead of appending to it.
--
-- Run with:  lua tests/test_target_snapshot.lua   (from the plugin folder)

if (arg == nil) or (arg[0] == nil) or (arg[0]:find("test_target_snapshot") == nil) then
	return
end

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../target_snapshot.lua")

-- luacheck: globals TargetSnapshot

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
		a_Message .. " (expected " .. tostring(a_Expected) .. ", got " .. tostring(a_Actual) .. ")"
	)
end





--- Mocks a live cEntity with mutable fields, so a test can prove that the proxy
--- copied the values instead of referencing the entity.
local function MakeEntity(a_Fields)
	local Entity = { Fields = a_Fields }

	function Entity:GetUniqueID()          return self.Fields.ID end
	function Entity:IsPlayer()             return self.Fields.Player == true end
	function Entity:IsMob()                return self.Fields.Mob == true end
	function Entity:IsPawn()               return self.Fields.Pawn ~= false end
	function Entity:GetMobType()           return self.Fields.MobType end
	function Entity:GetName()              return self.Fields.Name end
	function Entity:GetCustomName()        return self.Fields.CustomName end
	function Entity:GetXpLevel()           return self.Fields.XpLevel end
	function Entity:IsGameModeSurvival()   return self.Fields.Survival == true end
	function Entity:IsGameModeCreative()   return self.Fields.Creative == true end
	function Entity:IsGameModeAdventure()  return self.Fields.Adventure == true end
	function Entity:IsGameModeSpectator()  return self.Fields.Spectator == true end
	function Entity:GetPosition()          return self.Fields.Position end
	function Entity:GetBoundingBox()       return self.Fields.BoundingBox end

	function Entity:GetTeam()
		local TeamName = self.Fields.TeamName
		if (TeamName == nil) then
			return nil
		end
		return { GetName = function () return TeamName end }
	end

	return Entity
end





local function MakePlayer(a_Name, a_ID)
	return MakeEntity(
		{
			ID = a_ID,
			Player = true,
			Name = a_Name,
			XpLevel = 7,
			Survival = true,
			Position = { x = 1, y = 2, z = 3 },
			BoundingBox = { Tag = "player-box" },
		}
	)
end





local function MakeMonster(a_MobType, a_ID, a_CustomName)
	return MakeEntity(
		{
			ID = a_ID,
			Mob = true,
			MobType = a_MobType,
			CustomName = a_CustomName,
			Position = { x = 4, y = 5, z = 6 },
			BoundingBox = { Tag = "mob-box" },
		}
	)
end





local function MakeWorld(a_Name, a_Entities)
	local World = { Name = a_Name, Entities = a_Entities }

	function World:GetName() return self.Name end

	function World:ForEachEntity(a_Callback)
		for _, Entity in ipairs(self.Entities) do
			if (a_Callback(Entity)) then
				break
			end
		end
	end

	return World
end





local function TestRefreshAndAccessors()
	local Player = MakePlayer("Alice", 11)
	local Monster = MakeMonster("creeper", 22, "Boomer")
	local Item = MakeEntity({ ID = 33, Pawn = false })
	local World = MakeWorld("world", { Player, Monster, Item })

	TargetSnapshot.RefreshWorld(World)

	local Players = TargetSnapshot.GetPlayers("world")
	local Pawns = TargetSnapshot.GetPawns("world")
	CheckEquals(#Players, 1, "only pawn players are snapshotted as players")
	CheckEquals(#Pawns, 2, "both pawns are snapshotted")
	CheckEquals(Players[1]:GetName(), "Alice", "player name is copied")
	CheckEquals(Players[1]:GetUniqueID(), 11, "player ID is copied")
	CheckEquals(Pawns[1]:GetUniqueID(), 11, "player is also a pawn")
	CheckEquals(Pawns[2]:GetUniqueID(), 22, "monster is a pawn")
end





local function TestProxyMirrorsEntity()
	local Player = MakePlayer("Alice", 11)
	Player.Fields.TeamName = "red"
	local Monster = MakeMonster("creeper", 22, "Boomer")
	local World = MakeWorld("world", { Player, Monster })
	TargetSnapshot.RefreshWorld(World)

	local Pawns = TargetSnapshot.GetPawns("world")
	local PlayerProxy = Pawns[1]
	local MonsterProxy = Pawns[2]

	Check(PlayerProxy:IsPlayer(), "player proxy reports IsPlayer")
	Check(not PlayerProxy:IsMob(), "player proxy is not a mob")
	Check(PlayerProxy:IsPawn(), "player proxy is a pawn")
	CheckEquals(PlayerProxy:GetXpLevel(), 7, "player XP level is copied")
	Check(PlayerProxy:IsGameModeSurvival(), true, "survival flag is copied")
	CheckEquals(PlayerProxy:GetTeam():GetName(), "red", "team name is copied")

	Check(not MonsterProxy:IsPlayer(), "monster proxy is not a player")
	Check(MonsterProxy:IsMob(), "monster proxy reports IsMob")
	CheckEquals(MonsterProxy:GetMobType(), "creeper", "mob type is copied")
	CheckEquals(MonsterProxy:GetCustomName(), "Boomer", "custom name is copied")
	CheckEquals(MonsterProxy:GetPosition().x, 4, "position is copied")
	CheckEquals(MonsterProxy:GetBoundingBox().Tag, "mob-box", "bounding box is copied")
	CheckEquals(MonsterProxy:GetTeam(), nil, "a mob has no team")
end





local function TestProxyKeepsNoEntityReference()
	local Player = MakePlayer("Alice", 11)
	local World = MakeWorld("world", { Player })
	TargetSnapshot.RefreshWorld(World)

	local Proxy = TargetSnapshot.GetPawns("world")[1]

	-- Mutating the live entity after the snapshot must not be observable: that is
	-- what "value copy" means, and it is what makes the snapshot safe to use
	-- after the entity may already have been freed.
	Player.Fields.Name = "Bob"
	Player.Fields.XpLevel = 99
	Player.Fields.Position = { x = 100, y = 100, z = 100 }

	CheckEquals(Proxy:GetName(), "Alice", "later entity mutation does not leak into the proxy")
	CheckEquals(Proxy:GetXpLevel(), 7, "later XP change does not leak into the proxy")
	CheckEquals(Proxy:GetPosition().x, 1, "later position change does not leak into the proxy")

	Check(Proxy.Entity == nil, "proxy exposes no entity reference")
end





local function TestUnknownWorldIsEmpty()
	local Snapshot = TargetSnapshot.GetWorld("never_ticked")
	CheckEquals(#Snapshot.Players, 0, "unknown world has no players")
	CheckEquals(#Snapshot.Pawns, 0, "unknown world has no pawns")
end





local function TestRefreshReplacesPreviousSnapshot()
	local Player = MakePlayer("Alice", 11)
	local World = MakeWorld("world", { Player })
	TargetSnapshot.RefreshWorld(World)
	CheckEquals(#TargetSnapshot.GetPawns("world"), 1, "first refresh snapshots the player")

	-- The player left before the next world tick:
	World.Entities = {}
	TargetSnapshot.RefreshWorld(World)
	CheckEquals(#TargetSnapshot.GetPawns("world"), 0, "second refresh replaces, not appends")
	CheckEquals(#TargetSnapshot.GetPlayers("world"), 0, "players list is replaced too")
end





local function TestMultiWorldAccessors()
	local Overworld = MakeWorld("world", { MakePlayer("Alice", 11) })
	local Nether = MakeWorld("world_nether", { MakePlayer("Bob", 22), MakeMonster("zombie", 33) })
	TargetSnapshot.OnWorldTick(Overworld, 50)
	TargetSnapshot.OnWorldTick(Nether, 50)

	-- The proxy answers with the world *name*, not a cWorld: the selector layer
	-- compares worlds, and a cWorld reference is not safe to carry around.
	CheckEquals(TargetSnapshot.GetPlayers("world_nether")[1]:GetWorld(), "world_nether", "proxy world is a name")

	local AllPlayers = TargetSnapshot.GetAllPlayers()
	CheckEquals(#AllPlayers, 2, "all players across worlds")
	local AllPawns = TargetSnapshot.GetAllPawns()
	CheckEquals(#AllPawns, 3, "all pawns across worlds")
end





TestRefreshAndAccessors()
TestProxyMirrorsEntity()
TestProxyKeepsNoEntityReference()
TestUnknownWorldIsEmpty()
TestRefreshReplacesPreviousSnapshot()
TestMultiWorldAccessors()

print("test_target_snapshot: " .. NumPassed .. " passed, " .. NumFailed .. " failed")
if (NumFailed > 0) then
	os.exit(1)
end
