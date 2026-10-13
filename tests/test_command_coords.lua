-- test_command_coords.lua
--
-- Table-driven tests for Core's 1.12.2 coordinate parsing, and for wiring the command origin into
-- the target selector context.
--
-- Verified specification: specs/vanilla-1.12.2-command-coordinates.md (parent repository).
-- The parser cases pin the 1.12.2 grammar: absolute coordinates, "~" relative to the execution
-- position, and the fact that local coordinates "^" are a 1.13 (17w50a) addition which 1.12.2
-- rejects - that case is the reason this file exists, because "^" is easy to "helpfully" implement.
--
-- Invariants:
--   * ParseCommandCoord() / ParseCommandCoords() are pure functions of their arguments.
--   * MakeSelectorContext() takes the world and the position from the command origin, so a command
--     block (which has no player) resolves its selectors against its own world and position instead
--     of against the default world's spawn.
--
-- Run with:  lua tests/test_command_coords.lua   (from the plugin folder)

if (arg == nil) or (arg[0] == nil) or (arg[0]:find("test_command_coords") == nil) then
	return
end

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../target_selectors.lua")

-- luacheck: new globals cRoot cBoundingBox Vector3d cMonster
-- luacheck: read globals ParseCommandCoord ParseCommandCoords GetOriginPosition MakeSelectorContext ResolveTargets

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
	Check(a_Actual == a_Expected, string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual)))
end

local function CheckClose(a_Actual, a_Expected, a_Message)
	Check(
		(type(a_Actual) == "number") and (math.abs(a_Actual - a_Expected) < 1e-9),
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end



-- Fake universe --------------------------------------------------------------
-- The same duck-typed shapes the real bindings offer, so the selector layer runs under stock Lua.

local function MakeBox(MinX, MinY, MinZ, MaxX, MaxY, MaxZ)
	return
	{
		Min = { x = MinX, y = MinY, z = MinZ },
		Max = { x = MaxX, y = MaxY, z = MaxZ },
		DoesIntersect = function (a_Self, a_Other)
			return (a_Self.Min.x < a_Other.Max.x) and (a_Self.Max.x > a_Other.Min.x)
				and (a_Self.Min.y < a_Other.Max.y) and (a_Self.Max.y > a_Other.Min.y)
				and (a_Self.Min.z < a_Other.Max.z) and (a_Self.Max.z > a_Other.Min.z)
		end,
	}
end

cBoundingBox = function (a_Min, a_Max)
	return MakeBox(a_Min.x, a_Min.y, a_Min.z, a_Max.x, a_Max.y, a_Max.z)
end

Vector3d = function (a_X, a_Y, a_Z)
	return { x = a_X, y = a_Y, z = a_Z }
end

cMonster =
{
	StringToMobType = function (a_Self, a_Name)
		assert(a_Self == cMonster, "StringToMobType must be called with colon syntax")
		return "type:" .. a_Name
	end,
	MobTypeToString = function (a_Self, a_Type)
		assert(a_Self == cMonster, "MobTypeToString must be called with colon syntax")
		return (a_Type:gsub("^type:", ""))
	end,
}

local NextEntityID = 0

local function BaseEntity(a_World, a_X, a_Y, a_Z)
	NextEntityID = NextEntityID + 1
	return
	{
		UniqueID = NextEntityID,
		World = a_World,
		Position = { x = a_X, y = a_Y, z = a_Z },
		GetUniqueID = function (a_Self) return a_Self.UniqueID end,
		GetWorld = function (a_Self) return a_Self.World end,
		GetPosition = function (a_Self) return a_Self.Position end,
		GetBoundingBox = function (a_Self)
			return MakeBox(
				a_Self.Position.x - 0.3, a_Self.Position.y, a_Self.Position.z - 0.3,
				a_Self.Position.x + 0.3, a_Self.Position.y + 1.8, a_Self.Position.z + 0.3
			)
		end,
	}
end

local function MakePlayer(a_Name, a_World, a_X, a_Y, a_Z)
	local Entity = BaseEntity(a_World, a_X, a_Y, a_Z)
	Entity.Name = a_Name
	Entity.IsPlayer = function () return true end
	Entity.IsMob = function () return false end
	Entity.IsPawn = function () return true end
	Entity.GetName = function (a_Self) return a_Self.Name end
	Entity.GetXpLevel = function () return 0 end
	Entity.GetTeam = function () return nil end
	Entity.IsGameModeSurvival = function () return true end
	Entity.IsGameModeCreative = function () return false end
	Entity.IsGameModeAdventure = function () return false end
	Entity.IsGameModeSpectator = function () return false end
	return Entity
end

local function MakeMob(a_MobType, a_World, a_X, a_Y, a_Z)
	local Entity = BaseEntity(a_World, a_X, a_Y, a_Z)
	Entity.MobType = "type:" .. a_MobType
	Entity.IsPlayer = function () return false end
	Entity.IsMob = function () return true end
	Entity.IsPawn = function () return true end
	Entity.GetMobType = function (a_Self) return a_Self.MobType end
	Entity.GetCustomName = function () return "" end
	return Entity
end

local function MakeWorld(a_Name, a_Entities)
	return
	{
		Name = a_Name,
		Entities = a_Entities,
		ForEachEntity = function (a_Self, a_Callback)
			for _, Entity in ipairs(a_Self.Entities) do
				a_Callback(Entity)
			end
		end,
		ForEachPlayer = function (a_Self, a_Callback)
			for _, Entity in ipairs(a_Self.Entities) do
				if (Entity:IsPlayer()) then
					a_Callback(Entity)
				end
			end
		end,
		GetSpawnX = function () return 0 end,
		GetSpawnY = function () return 64 end,
		GetSpawnZ = function () return 0 end,
	}
end

--- Builds a stand-in for cCommandOrigin with the same duck-typed accessors.
local function MakeOrigin(a_World, a_X, a_Y, a_Z, a_Player)
	return
	{
		World = a_World,
		Position = { x = a_X, y = a_Y, z = a_Z },
		Player = a_Player,
		GetWorld = function (a_Self) return a_Self.World end,
		GetPosition = function (a_Self) return a_Self.Position end,
		GetPlayer = function (a_Self) return a_Self.Player end,
		HasPlayer = function (a_Self) return a_Self.Player ~= nil end,
	}
end



-- Tests ----------------------------------------------------------------------

local function TestParser()
	local Position = { x = 100, y = 64, z = -20 }

	CheckClose(ParseCommandCoord("12", "x", Position), 12, "absolute integer")
	CheckClose(ParseCommandCoord("-3.5", "y", Position), -3.5, "absolute fraction")
	CheckClose(ParseCommandCoord("~", "x", Position), 100, "a lone tilde is the execution position")
	CheckClose(ParseCommandCoord("~5", "z", Position), -15, "tilde with an offset")
	CheckClose(ParseCommandCoord("~-2.5", "y", Position), 61.5, "tilde with a negative offset")

	local X, Y, Z = ParseCommandCoords("~", "64", "~-10", Position)
	CheckClose(X, 100, "mixed: x is relative")
	CheckClose(Y, 64, "mixed: y stays absolute")
	CheckClose(Z, -30, "mixed: z is relative")

	-- Local coordinates are 1.13+ (17w50a); 1.12.2 has no such notation:
	local Value, Reason = ParseCommandCoord("^3", "x", Position)
	CheckEquals(Value, nil, "caret notation is rejected")
	Check((type(Reason) == "string") and (Reason:find("not a valid number") ~= nil), "caret gives a parse error")

	CheckEquals(ParseCommandCoord("abc", "x", Position), nil, "garbage is rejected")
	CheckEquals(ParseCommandCoord("~abc", "x", Position), nil, "garbage after a tilde is rejected")
	CheckEquals(ParseCommandCoord("", "x", Position), nil, "an empty token is rejected")
	CheckEquals(ParseCommandCoord(nil, "x", Position), nil, "a missing token is rejected")

	-- Without a known execution position the tilde degenerates to a plain offset:
	CheckClose(ParseCommandCoord("~", "x", nil), 0, "a lone tilde without a position is 0")
	CheckClose(ParseCommandCoord("~7", "x", nil), 7, "a tilde offset without a position")

	-- GetOriginPosition() must not choke on the shapes it can meet:
	CheckEquals(GetOriginPosition(nil), nil, "no origin, no position")
	CheckEquals(GetOriginPosition({}), nil, "an origin without GetPosition has no position")
	CheckClose(GetOriginPosition(MakeOrigin(nil, 1, 2, 3)).y, 2, "the origin position is copied out")
end



local function TestSelectorContext()
	local Nether = MakeWorld("world_nether", {})
	local Origin = MakeOrigin(Nether, 5, 64, 5)

	-- The command block case: an origin, no player.
	local Context = MakeSelectorContext(nil, Origin)
	Check(Context ~= nil, "a command block still gets a selector context")
	CheckEquals(Context.World, Nether, "the context world comes from the origin")
	CheckClose(Context.Position.x, 5, "the context position comes from the origin")
	CheckEquals(Context.Executor, nil, "a command block has no executor")

	-- A player command: the executor is the player, world and position still come from the origin.
	local Overworld = MakeWorld("world", {})
	local Player = MakePlayer("player1", Overworld, 0, 64, 0)
	local PlayerOrigin = MakeOrigin(Overworld, 0, 64, 0, Player)
	local PlayerContext = MakeSelectorContext(Player, PlayerOrigin)
	CheckEquals(PlayerContext.Executor, Player, "the executor is the player")
	CheckEquals(PlayerContext.World, Overworld, "the player context world")

	-- Callers that have no origin keep the previous fallback:
	local LegacyContext = MakeSelectorContext(Player, nil)
	CheckEquals(LegacyContext.World, Overworld, "without an origin the player's world is used")
	CheckClose(LegacyContext.Position.x, 0, "without an origin the player's position is used")
end



local function TestWorldScoping()
	-- "distance" is a 1.13 argument; 1.12.2 uses the radius arguments "r"/"rm".
	-- The two zombies sit at the same coordinates - only their world tells them apart, which is
	-- exactly what a command block in the nether needs the origin for. A third zombie sits on the
	-- overworld's spawn so the origin-less fallback can be told apart from the origin path.
	local NetherZombie = MakeMob("zombie", nil, 5, 64, 5)
	local OverworldZombie = MakeMob("zombie", nil, 5, 64, 5)
	local SpawnZombie = MakeMob("zombie", nil, 0, 64, 0)
	local Nether = MakeWorld("world_nether", { NetherZombie })
	local Overworld = MakeWorld("world", { OverworldZombie, SpawnZombie })
	NetherZombie.World = Nether
	OverworldZombie.World = Overworld
	SpawnZombie.World = Overworld

	cRoot =
	{
		Get = function () return cRoot end,
		GetDefaultWorld = function () return Overworld end,
		ForEachWorld = function (_, a_Callback)
			a_Callback(Overworld)
			a_Callback(Nether)
		end,
	}

	local Origin = MakeOrigin(Nether, 5, 64, 5)
	local Targets, TargetsReason = ResolveTargets("@e[r=5]", MakeSelectorContext(nil, Origin), "entity")
	Check(Targets ~= nil, "the selector resolves at all: " .. tostring(TargetsReason))
	CheckEquals(Targets and #Targets or -1, 1, "exactly one entity is in range for the command block")
	if (Targets ~= nil) and (#Targets == 1) then
		CheckEquals(Targets[1]:GetWorld(), Nether, "the selected entity is in the origin's world")
		CheckEquals(Targets[1], NetherZombie, "the selected entity is the nether one")
	end

	-- Counter-check: with no origin the previous approximation is still what happens (the default
	-- world and its spawn), which is the behaviour the origin now replaces.
	local LegacyTargets, LegacyReason = ResolveTargets("@e[r=5]", MakeSelectorContext(nil, nil), "entity")
	Check(LegacyTargets ~= nil, "the origin-less selector resolves at all: " .. tostring(LegacyReason))
	CheckEquals(LegacyTargets and #LegacyTargets or -1, 1, "without an origin the default world spawn is used")
	if (LegacyTargets ~= nil) and (#LegacyTargets == 1) then
		CheckEquals(LegacyTargets[1]:GetWorld(), Overworld, "the fallback uses the default world")
		CheckEquals(LegacyTargets[1], SpawnZombie, "the fallback uses the default world's spawn")
	end
end



TestParser()
TestSelectorContext()
TestWorldScoping()

print(string.format("test_command_coords: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
