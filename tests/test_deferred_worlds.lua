-- test_deferred_worlds.lua
--
-- Verifies method D2 of Core's target selector layer: the origin world is resolved and acted on
-- immediately (the engine holds its lock, so the count and the effect are exact), the other worlds are
-- queued onto their own threads, and the command block's success count is written back once every other
-- world has reported.
--
-- Verified specification: specs/commands/vanilla-1.12.2-command-coordinates.md sections 2.1c and 7 (parent
-- repository). The behaviour under test is the only way to keep vanilla's cross-dimension selectors
-- while never taking another world's lock from plugin Lua.
--
-- Invariants:
--   * Only a world with no lock of its own is queued; nothing here ever touches another world directly.
--   * Deferral happens only for dimension-agnostic selectors ("@a"/"@e"/"@r" without positional,
--     distance, sort/limit arguments or "@p"), and only for commands without an executor - a queued
--     action must not carry an executor reference across ticks.
--   * The write-back is queued to the origin world and happens exactly once, with the sum of the
--     origin world's count and every other world's report.
--
-- Run with:  lua tests/test_deferred_worlds.lua   (from the plugin folder)

if (arg == nil) or (arg[0] == nil) or (arg[0]:find("test_deferred_worlds") == nil) then
	return
end

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../target_selectors.lua")

-- luacheck: new globals cRoot cBoundingBox Vector3d cMonster
-- luacheck: read globals ResolveTargets ApplyToTargets

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
	local Detail = string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	Check(a_Actual == a_Expected, Detail)
end



-- Fake universe --------------------------------------------------------------

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
	StringToMobType = function (_, a_Name)
		return "type:" .. a_Name
	end,
	MobTypeToString = function (_, a_Type)
		return (a_Type:gsub("^type:", ""))
	end,
}

local NextEntityID = 0

local function MakePawn(a_World, a_X, a_Y, a_Z)
	NextEntityID = NextEntityID + 1
	local Entity =
	{
		UniqueID = NextEntityID,
		World = a_World,
		Position = { x = a_X, y = a_Y, z = a_Z },
		GetUniqueID = function (a_Self) return a_Self.UniqueID end,
		GetWorld = function (a_Self) return a_Self.World end,
		GetPosition = function (a_Self) return a_Self.Position end,
		IsPlayer = function () return false end,
		IsMob = function () return true end,
		IsPawn = function () return true end,
		GetMobType = function () return "type:zombie" end,
		GetCustomName = function () return "" end,
		GetBoundingBox = function (a_Self)
			return MakeBox(
				a_Self.Position.x - 0.3, a_Self.Position.y, a_Self.Position.z - 0.3,
				a_Self.Position.x + 0.3, a_Self.Position.y + 1.8, a_Self.Position.z + 0.3
			)
		end,
	}
	return Entity
end

local QueuedTasks = {}
local WriteBacks = {}

local function MakeWorld(a_Name, a_Entities)
	return
	{
		Name = a_Name,
		Entities = a_Entities,
		GetName = function (a_Self) return a_Self.Name end,
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
		QueueTask = function (a_Self, a_Task)
			table.insert(QueuedTasks, { World = a_Self, Task = a_Task })
		end,
		SetCommandBlockSuccessCount = function (a_Self, a_X, a_Y, a_Z, a_Count)
			table.insert(WriteBacks, { World = a_Self, X = a_X, Y = a_Y, Z = a_Z, Count = a_Count })
			return true
		end,
	}
end

--- Runs every queued task, including the ones they queue in turn (the write-back is queued by a
--- reporting task), and returns how many tasks ran.
local function RunQueuedTasks()
	local Ran = 0
	for _ = 1, 16 do
		local Tasks = QueuedTasks
		QueuedTasks = {}
		if (#Tasks == 0) then
			return Ran
		end
		for _, Entry in ipairs(Tasks) do
			Entry.Task()
			Ran = Ran + 1
		end
	end
	error("the queued tasks keep queueing more tasks")
end



-- Tests ----------------------------------------------------------------------

local Overworld
local Nether
local OverworldZombie
local NetherZombie

local function BuildUniverse()
	OverworldZombie = MakePawn(nil, 0, 64, 0)
	NetherZombie = MakePawn(nil, 5, 64, 5)
	Overworld = MakeWorld("world", { OverworldZombie })
	Nether = MakeWorld("world_nether", { NetherZombie })
	OverworldZombie.World = Overworld
	NetherZombie.World = Nether

	cRoot =
	{
		Get = function () return cRoot end,
		GetDefaultWorld = function () return Overworld end,
		GetWorld = function (_, a_Name)
			if (a_Name == "world") then return Overworld end
			if (a_Name == "world_nether") then return Nether end
			return nil
		end,
		ForEachWorld = function (_, a_Callback)
			a_Callback(Overworld)
			a_Callback(Nether)
			return false
		end,
		FindAndDoWithPlayer = function () return false end,
	}
end

--- A command block origin: a world and a position, but no executor.
local function MakeCommandBlockContext()
	return
	{
		World = Overworld,
		Position = { x = 0.5, y = 64, z = 0.5 },
		Executor = nil,
	}
end



local function TestCommandBlockDefersOtherWorlds()
	BuildUniverse()
	QueuedTasks = {}
	WriteBacks = {}

	local Context = MakeCommandBlockContext()
	local Targets, Reason = ResolveTargets("@e", Context, "entity")
	Check(Targets ~= nil, "the selector resolves: " .. tostring(Reason))
	CheckEquals(Targets and #Targets or -1, 1, "the origin world's pawn is the only live candidate")
	Check(Targets and Targets.Deferred ~= nil, "the other worlds are recorded for deferral")
	local Deferred = Targets and Targets.Deferred
	CheckEquals(Deferred and #Deferred.Worlds or -1, 1, "exactly one other world")
	CheckEquals(Deferred and Deferred.Worlds[1], "world_nether", "the other world is the nether")
	Check(Targets and Targets.Deferred and Targets.Deferred.Writable, "a command block's count can be corrected")

	local Acted = {}
	local Affected = ApplyToTargets(Targets, function (a_Entity) table.insert(Acted, a_Entity) end)
	CheckEquals(Affected, 1, "the origin world is acted on immediately")
	CheckEquals(#Acted, 1, "exactly one immediate action")
	CheckEquals(Acted[1], OverworldZombie, "the immediate action hit the origin world's pawn")
	CheckEquals(#QueuedTasks, 1, "one task was queued for the other world")
	CheckEquals(#WriteBacks, 0, "nothing is written back before the other world reports")

	CheckEquals(RunQueuedTasks(), 2, "the reporting task and the write-back task both ran")
	CheckEquals(#Acted, 2, "the queued task acted on the other world")
	CheckEquals(Acted[2], NetherZombie, "the queued action hit the nether pawn")

	CheckEquals(#WriteBacks, 1, "the count is written back exactly once")
	if (#WriteBacks == 1) then
		CheckEquals(WriteBacks[1].World, Overworld, "the write-back targets the origin world")
		CheckEquals(WriteBacks[1].X, 0, "the block X comes from the origin position")
		CheckEquals(WriteBacks[1].Y, 64, "the block Y comes from the origin position")
		CheckEquals(WriteBacks[1].Z, 0, "the block Z comes from the origin position")
		CheckEquals(WriteBacks[1].Count, 2, "the count is the sum of both worlds")
	end
end



local function TestNoDeferralWhenDimensionBoundOrExecuted()
	BuildUniverse()
	QueuedTasks = {}
	WriteBacks = {}

	-- A positional/distance argument pins the selector to the executing dimension (spec section 2.1c):
	local Positioned = ResolveTargets("@e[r=1000]", MakeCommandBlockContext(), "entity")
	Check(Positioned ~= nil, "the position-based selector resolves")
	Check(Positioned and Positioned.Deferred == nil, "a position-based selector is not deferred")
	ApplyToTargets(Positioned, function () end)
	CheckEquals(#QueuedTasks, 0, "nothing is queued for a position-based selector")

	-- ... and so does a negative radius, which only restates the dimension restriction:
	local NegativeRadius = ResolveTargets("@e[rm=-1]", MakeCommandBlockContext(), "entity")
	Check(NegativeRadius ~= nil, "the negative-radius selector resolves")
	Check(NegativeRadius and NegativeRadius.Deferred == nil, "a negative radius is not deferred")
	CheckEquals(#QueuedTasks, 0, "nothing is queued for a negative radius")

	-- A command with an executor defers the other worlds too, but has no command block whose count could
	-- be corrected, and the queued action must not receive the executor (spec section 7.3):
	local Player = MakePawn(Overworld, 1, 64, 1)
	Player.IsPlayer = function () return true end
	Player.IsMob = function () return false end
	local ExecutedContext = { World = Overworld, Position = { x = 1, y = 64, z = 1 }, Executor = Player }
	local Executed, ExecutedReason = ResolveTargets("@e", ExecutedContext, "entity")
	Check(Executed ~= nil, "the executor's selector resolves: " .. tostring(ExecutedReason))
	Check(Executed and Executed.Deferred ~= nil, "an executed command defers the other worlds too")
	Check(
		not (Executed and Executed.Deferred and Executed.Deferred.Writable),
		"a player command has nothing to write back"
	)

	local Flags = {}
	ApplyToTargets(Executed, function (_, a_Deferred)
		table.insert(Flags, a_Deferred and "deferred" or "live")
	end)
	RunQueuedTasks()
	table.sort(Flags)
	CheckEquals(table.concat(Flags, ","), "deferred,live", "the live action is live and the queued one is deferred")
	CheckEquals(#WriteBacks, 0, "nothing is written back for an executed command")

	-- "@s" is the entity executing the command, which always lives in the origin world:
	local Self, SelfReason = ResolveTargets("@s", ExecutedContext, "entity")
	Check(Self ~= nil, "@s resolves: " .. tostring(SelfReason))
	Check(Self and Self.Deferred == nil, "@s is never deferred")
end



local function TestConsoleDefersButDoesNotWriteBack()
	BuildUniverse()
	QueuedTasks = {}
	WriteBacks = {}

	-- The console sits at (0, 0, 0) with no executor: its cross-world work is still queued, but there is
	-- no command block whose count could be corrected (spec section 7.3):
	local Context = { World = Overworld, Position = { x = 0, y = 0, z = 0 }, Executor = nil }
	local Targets, Reason = ResolveTargets("@e", Context, "entity")
	Check(Targets ~= nil, "the console's selector resolves: " .. tostring(Reason))
	Check(Targets and Targets.Deferred ~= nil, "the console defers the other worlds")
	Check(not (Targets and Targets.Deferred and Targets.Deferred.Writable), "the console has nothing to write back")

	local Acted = {}
	ApplyToTargets(Targets, function (a_Entity) table.insert(Acted, a_Entity) end)
	RunQueuedTasks()
	CheckEquals(#Acted, 2, "both worlds were acted on")
	CheckEquals(#WriteBacks, 0, "no write-back for the console")
end



local function TestEmptyOriginWorldStillQueues()
	BuildUniverse()
	QueuedTasks = {}
	WriteBacks = {}

	-- The origin world has no matching pawn at all, but the nether does: the command must still succeed
	-- and the deferred world must still be visited:
	Overworld.Entities = {}
	local Context = MakeCommandBlockContext()
	local Targets, Reason = ResolveTargets("@e", Context, "entity")
	Check(Targets ~= nil, "an empty origin world is not an error when other worlds are deferred: " ..
		tostring(Reason))
	CheckEquals(Targets and #Targets or -1, 0, "no live targets")

	local Acted = {}
	local Immediate = ApplyToTargets(Targets, function (a_Entity) table.insert(Acted, a_Entity) end)
	CheckEquals(Immediate, 0, "nothing happens immediately")
	RunQueuedTasks()
	CheckEquals(#Acted, 1, "the deferred world was acted on")
	CheckEquals(#WriteBacks, 1, "the count is still written back")
	if (#WriteBacks == 1) then
		CheckEquals(WriteBacks[1].Count, 1, "the count is the deferred world's report")
	end
end



TestCommandBlockDefersOtherWorlds()
TestNoDeferralWhenDimensionBoundOrExecuted()
TestConsoleDefersButDoesNotWriteBack()
TestEmptyOriginWorldStillQueues()

print(string.format("test_deferred_worlds: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
