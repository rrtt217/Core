-- test_selectors.lua
--
-- Table-driven tests for Core's target selector layer (target_selectors.lua).
--
-- Verified specification: specs/vanilla-1.12.2-command-target-selectors.md
-- (parent repository). The parser cases pin the 1.12.2 grammar, in particular the
-- facts that 1.12.2 had no quoting, no spaces and no repeated arguments (those are
-- 1.13+/17w45a additions).
--
-- Invariants:
--   * ParseSelector() is a pure function of its input string.
--   * ResolveSelector() only reaches the game through duck-typed methods, which
--     this file stubs, so the whole module runs under a stock Lua interpreter.
--
-- Run with:  lua tests/test_selectors.lua   (from the plugin folder)

if (arg == nil) or (arg[0] == nil) or (arg[0]:find("test_selectors") == nil) then
	return
end

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../target_selectors.lua")

-- luacheck: new globals cRoot cBoundingBox Vector3d cMonster
-- luacheck: read globals ParseSelector ResolveSelectorToken ResolveTargets GetTargetName ApplyToTargets

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

local function CheckReason(a_Token, a_ExpectedFragment)
	local Selector, Reason = ParseSelector(a_Token)
	Check(Selector == nil, "ParseSelector(" .. a_Token .. ") should fail")
	Check(
		(Reason ~= nil) and (Reason:find(a_ExpectedFragment) ~= nil),
		"ParseSelector(" .. a_Token .. ") reason should mention \"" .. a_ExpectedFragment
			.. "\" (got " .. tostring(Reason) .. ")"
	)
end





local function TestParser()
	-- Valid selectors:
	local Selector = ParseSelector("@a")
	Check(Selector ~= nil, "@a parses")
	CheckEquals(Selector.Variable, "a", "@a variable")
	CheckEquals(#Selector.Arguments, 0, "@a has no arguments")

	Selector = ParseSelector("@e[type=cow]")
	Check(Selector ~= nil, "@e[type=cow] parses")
	CheckEquals(Selector.Lookup.type.Value, "cow", "type value")
	CheckEquals(Selector.Lookup.type.Negated, false, "type not negated")

	Selector = ParseSelector("@e[type=!cow]")
	Check(Selector ~= nil, "@e[type=!cow] parses")
	CheckEquals(Selector.Lookup.type.Negated, true, "type negation")
	CheckEquals(Selector.Lookup.type.Value, "cow", "type value without !")

	Selector = ParseSelector("@p[c=-3]")
	Check(Selector ~= nil, "@p[c=-3] parses")
	CheckEquals(Selector.Lookup.c.Number, -3, "negative count")

	Selector = ParseSelector("@a[team=]")
	Check(Selector ~= nil, "@a[team=] parses")
	CheckEquals(Selector.Lookup.team.Value, "", "empty team value")

	Selector = ParseSelector("@a[team=!]")
	Check(Selector ~= nil, "@a[team=!] parses")
	CheckEquals(Selector.Lookup.team.Negated, true, "negated empty team value")

	-- 1.12.2 had no quoting and no spaces (both are 17w45a additions):
	CheckReason("@a[name=\"First Last\"]", "Spaces")
	CheckReason("@a[ m=1]", "Spaces")
	CheckReason("@a[name=a b]", "Spaces")

	-- Repeated arguments were impossible before 17w45a:
	CheckReason("@a[type=!cow,type=!chicken]", "Duplicate")

	-- Unknown / malformed:
	CheckReason("@n", "Unknown selector variable")
	CheckReason("foo", "Invalid selector")
	CheckReason("@a[foo=1]", "Unknown selector argument")
	CheckReason("@a[c]", "Invalid selector argument")
	CheckReason("@a[]", "Invalid selector argument")
	CheckReason("@a[c=1,]", "Invalid selector argument")
	CheckReason("@a[type=cow", "Invalid selector")
	CheckReason("@a[c=1.5]", "expects an integer")
	CheckReason("@e[x=0.5]", "expects an integer")
	CheckReason("@a[type=!]", "expects a value")
	CheckReason("@a[c=!1]", "cannot be negated")

	-- Valid 1.12.2 syntax that this branch does not implement is parsed but
	-- flagged, so that resolution can fail loudly.
	Selector = ParseSelector("@a[tag=x]")
	Check(Selector ~= nil, "@a[tag=x] parses")
	CheckEquals(Selector.Lookup.tag.Unsupported, "scoreboard tags", "tag is flagged unsupported")

	Selector = ParseSelector("@a[score_points=5]")
	Check(Selector ~= nil, "@a[score_points=5] parses")
	Check(Selector.Lookup.score_points.Unsupported ~= nil, "score argument is flagged unsupported")

	Selector = ParseSelector("@a[score_points_min=5]")
	Check(Selector ~= nil, "@a[score_points_min=5] parses")
	Check(Selector.Lookup.score_points_min.Unsupported ~= nil, "score min argument is flagged unsupported")

	Selector = ParseSelector("@a[rx=90]")
	Check(Selector ~= nil, "@a[rx=90] parses")
	Check(Selector.Lookup.rx.Unsupported ~= nil, "view angle is flagged unsupported")
end





-- Fake universe --------------------------------------------------------------

local DefaultWorld
local SecondWorld

local QueuedTasks = {}
local WriteBacks = {}

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
	-- The real binding is called with colon syntax (the class table is argument #1),
	-- so the stub enforces that shape: a dot call would pass the string as a_Self and
	-- fail here instead of only at runtime.
	StringToMobType = function (a_Self, a_Name)
		assert(a_Self == cMonster, "StringToMobType must be called with colon syntax")
		assert(type(a_Name) == "string", "StringToMobType expects a string argument")
		if ((a_Name == "creeper") or (a_Name == "cow") or (a_Name == "cavespider")) then
			return "type:" .. a_Name
		end
		return "type:invalid"
	end,

	-- Also a C++ static bound with tolua_isusertable (colon syntax).
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

local function MakePlayer(a_Name, a_World, a_X, a_Y, a_Z, a_Properties)
	a_Properties = a_Properties or {}
	local Entity = BaseEntity(a_World, a_X, a_Y, a_Z)
	Entity.Name = a_Name
	Entity.XpLevel = a_Properties.XpLevel or 0
	Entity.GameMode = a_Properties.GameMode or "survival"
	Entity.Team = a_Properties.Team
	Entity.IsPlayer = function () return true end
	Entity.IsMob = function () return false end
	Entity.IsPawn = function () return true end
	Entity.GetName = function (a_Self) return a_Self.Name end
	Entity.GetXpLevel = function (a_Self) return a_Self.XpLevel end
	Entity.GetTeam = function (a_Self) return a_Self.Team end
	Entity.IsGameModeSurvival = function (a_Self) return a_Self.GameMode == "survival" end
	Entity.IsGameModeCreative = function (a_Self) return a_Self.GameMode == "creative" end
	Entity.IsGameModeAdventure = function (a_Self) return a_Self.GameMode == "adventure" end
	Entity.IsGameModeSpectator = function (a_Self) return a_Self.GameMode == "spectator" end
	return Entity
end

local function MakeMob(a_MobType, a_World, a_X, a_Y, a_Z, a_CustomName)
	local Entity = BaseEntity(a_World, a_X, a_Y, a_Z)
	Entity.MobType = "type:" .. a_MobType
	Entity.CustomName = a_CustomName or ""
	Entity.IsPlayer = function () return false end
	Entity.IsMob = function () return true end
	Entity.IsPawn = function () return true end
	Entity.GetMobType = function (a_Self) return a_Self.MobType end
	Entity.GetCustomName = function (a_Self) return a_Self.CustomName end
	return Entity
end

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
			-- D2 queues the other worlds' work on their own threads; the tests run it inline:
			table.insert(QueuedTasks, { World = a_Self, Task = a_Task })
		end,
		SetCommandBlockSuccessCount = function (a_Self, a_X, a_Y, a_Z, a_Count)
			table.insert(WriteBacks, { World = a_Self, X = a_X, Y = a_Y, Z = a_Z, Count = a_Count })
			return true
		end,
	}
end

local Player1
local Player2
local Player3

local function BuildUniverse()
	local RedTeam = { Name = "red", GetName = function (a_Self) return a_Self.Name end }

	DefaultWorld = MakeWorld("world", {})
	SecondWorld = MakeWorld("world_nether", {})

	Player1 = MakePlayer("player1", DefaultWorld, 0, 64, 0, { XpLevel = 10, GameMode = "survival", Team = RedTeam })
	Player2 = MakePlayer("player2", DefaultWorld, 100, 64, 0, { XpLevel = 3, GameMode = "creative" })
	Player3 = MakePlayer("player3", SecondWorld, 5, 64, 5, { XpLevel = 7, GameMode = "survival" })
	local Creeper = MakeMob("creeper", DefaultWorld, 2, 64, 2)
	local Cow = MakeMob("cow", DefaultWorld, 3, 64, 3, "Bessie")
	local CaveSpider = MakeMob("cavespider", DefaultWorld, 10, 64, 10)
	-- Sits inside the box used below, but in another world: position-dependent
	-- selectors must ignore it.
	local NetherZombie = MakeMob("zombie", SecondWorld, 1, 64, 1)

	DefaultWorld.Entities = { Player1, Player2, Creeper, Cow, CaveSpider }
	SecondWorld.Entities = { Player3, NetherZombie }

	local Players = { Player1, Player2, Player3 }
	cRoot =
	{
		Get = function () return cRoot end,
		GetDefaultWorld = function () return DefaultWorld end,
		FindAndDoWithPlayer = function (_, a_Name, a_Callback)
			local lcName = a_Name:lower()
			for _, Player in ipairs(Players) do
				if (Player:GetName():lower():sub(1, #lcName) == lcName) then
					a_Callback(Player)
					return true
				end
			end
			return false
		end,
		ForEachPlayer = function (_, a_Callback)
			for _, Player in ipairs(Players) do
				a_Callback(Player)
			end
		end,
		ForEachWorld = function (_, a_Callback)
			a_Callback(DefaultWorld)
			a_Callback(SecondWorld)
		end,
		GetWorld = function (_, a_Name)
			if (a_Name == DefaultWorld:GetName()) then
				return DefaultWorld
			end
			if (a_Name == SecondWorld:GetName()) then
				return SecondWorld
			end
			return nil
		end,
	}
end

local function NamesOf(a_Entities)
	local Names = {}
	for _, Entity in ipairs(a_Entities) do
		Names[#Names + 1] = Entity:IsPlayer() and Entity:GetName() or Entity:GetMobType()
	end
	table.sort(Names)
	return table.concat(Names, ",")
end

local function ResolveToken(a_Token)
	local Context =
	{
		World = DefaultWorld,
		Position = { x = 0, y = 64, z = 0 },
		Executor = Player1,
	}
	local Entities, Reason = ResolveSelectorToken(a_Token, Context)
	Check(Reason == nil, "Resolving " .. a_Token .. " should succeed (got " .. tostring(Reason) .. ")")
	return Entities or {}
end

local function TestResolver()
	-- @a / @p / @e / @s:
	CheckEquals(NamesOf(ResolveToken("@a")), "player1,player2", "@a is every player of the origin world")
	CheckEquals(NamesOf(ResolveToken("@p")), "player1", "@p is the nearest player")
	CheckEquals(NamesOf(ResolveToken("@p[c=-1]")), "player2", "@p[c=-1] is the farthest same-world player")
	CheckEquals(NamesOf(ResolveToken("@a[c=2]")), "player1,player2", "@a[c=2] keeps the nearest two")
	CheckEquals(
		NamesOf(ResolveToken("@e")),
		"player1,player2,type:cavespider,type:cow,type:creeper",
		"@e is every loaded pawn of the origin world (other worlds are deferred)"
	)
	CheckEquals(NamesOf(ResolveToken("@s")), "player1", "@s is the executing entity")
	CheckEquals(NamesOf(ResolveToken("@p[type=cow]")), "type:cow", "@p[type=cow] switches to entities")

	-- Resolution with no execution context: @s is empty.
	local Entities, Reason = ResolveSelectorToken("@s", nil)
	Check(Reason == nil, "@s with nil context resolves")
	CheckEquals(#Entities, 0, "@s with nil context is empty")

	-- type=:
	CheckEquals(NamesOf(ResolveToken("@e[type=creeper]")), "type:creeper", "type match")
	CheckEquals(NamesOf(ResolveToken("@e[type=Creeper]")), "type:creeper", "type match is case-insensitive")
	CheckEquals(
		NamesOf(ResolveToken("@e[type=cave_spider]")),
		"type:cavespider",
		"type match normalizes underscores"
	)
	CheckEquals(
		NamesOf(ResolveToken("@e[type=player]")),
		"player1,player2",
		"type=player selects the origin world's players"
	)
	CheckEquals(
		NamesOf(ResolveToken("@e[type=!creeper]")),
		"player1,player2,type:cavespider,type:cow",
		"negated type (within the origin world)"
	)
	CheckEquals(#ResolveToken("@a[type=cow]"), 0, "@a never selects non-players")

	-- name=:
	CheckEquals(NamesOf(ResolveToken("@a[name=player2]")), "player2", "name match")
	CheckEquals(#ResolveToken("@a[name=Player2]"), 0, "name match is case-sensitive [推测]")
	CheckEquals(NamesOf(ResolveToken("@e[name=Bessie]")), "type:cow", "name matches custom names")
	CheckEquals(NamesOf(ResolveToken("@a[name=!player1]")), "player2", "negated name (other worlds are deferred)")

	-- c=:
	CheckEquals(NamesOf(ResolveToken("@e[c=1]")), "player1", "c=1 keeps the nearest")

	-- r= / rm=:
	CheckEquals(NamesOf(ResolveToken("@e[r=5]")), "player1,type:cow,type:creeper", "r= radius filter")
	CheckEquals(
		NamesOf(ResolveToken("@e[rm=2]")),
		"player2,type:cavespider,type:cow,type:creeper",
		"rm= radius filter"
	)
	CheckEquals(
		NamesOf(ResolveToken("@e[r=-1]")),
		"player1,player2,type:cavespider,type:cow,type:creeper",
		"r=-1 keeps the execution dimension"
	)

	-- x/y/z move the origin; x and z are centre-corrected, so x=2,z=2 means
	-- (2.5, 2.5) and the creeper at (2, 2) is NOT at distance 0.
	CheckEquals(#ResolveToken("@e[x=2,y=64,z=2,r=0]"), 0, "x/z are centre-corrected")

	-- dx/dy/dz describe a box around the origin. The second-world zombie sits at
	-- (1,64,1), inside that box, and must NOT match (distance has no meaning
	-- across worlds):
	CheckEquals(
		NamesOf(ResolveToken("@e[dx=4,dy=2,dz=4]")),
		"player1,type:cow,type:creeper",
		"dx/dy/dz select a box in the origin world only"
	)

	-- Same for a bare position: x/y/z carry a world, so the colliding zombie in the
	-- other world must not be selected.
	CheckEquals(#ResolveToken("@e[x=1,y=64,z=1,r=0]"), 0, "x/y/z stay in the origin world")

	-- x/y/z alone do not filter, but they still pin the dimension: this is the case
	-- no distance/box check can catch, so it is the real scoping regression test.
	CheckEquals(
		NamesOf(ResolveToken("@e[x=1,y=64,z=1]")),
		"player1,player2,type:cavespider,type:cow,type:creeper",
		"x/y/z alone restrict the candidate set to the origin world"
	)
	CheckEquals(
		NamesOf(ResolveToken("@a[x=1,y=64,z=1]")),
		"player1,player2",
		"x/y/z alone restrict @a to the origin world"
	)

	-- Negative "c=" must reverse the order within the origin world, never pick an
	-- entity of another world ("infinitely far" is not a thing).
	CheckEquals(NamesOf(ResolveToken("@a[c=-1]")), "player2", "c=-1 reverses within the origin world")
	CheckEquals(NamesOf(ResolveToken("@e[c=-1]")), "player2", "c=-1 reverses within the origin world (pawns)")

	-- l= / lm=:
	CheckEquals(NamesOf(ResolveToken("@a[l=5]")), "player2", "l= maximum level")
	CheckEquals(NamesOf(ResolveToken("@a[lm=5]")), "player1", "lm= minimum level (other worlds are deferred)")

	-- m=:
	CheckEquals(NamesOf(ResolveToken("@a[m=creative]")), "player2", "m= gamemode")
	CheckEquals(NamesOf(ResolveToken("@a[m=c]")), "player2", "m= gamemode alias")
	CheckEquals(NamesOf(ResolveToken("@a[m=!creative]")), "player1", "m= negation (other worlds are deferred)")

	-- team=:
	CheckEquals(NamesOf(ResolveToken("@a[team=red]")), "player1", "team= match")
	CheckEquals(NamesOf(ResolveToken("@a[team=]")), "player2", "team= no team (other worlds are deferred)")
	CheckEquals(NamesOf(ResolveToken("@a[team=!red]")), "player2", "team=!red (other worlds are deferred)")
	CheckEquals(NamesOf(ResolveToken("@a[team=!]")), "player1", "team=! any team")

	-- Unsupported arguments must fail loudly, not silently match everyone:
	local Failed, FailedReason = ResolveSelectorToken("@e[tag=x]", nil)
	Check(Failed == nil, "tag= does not resolve")
	Check(
		(FailedReason ~= nil) and (FailedReason:find("not supported") ~= nil),
		"tag= reports missing support (got " .. tostring(FailedReason) .. ")"
	)

	Failed = ResolveSelectorToken("@a[score_points=1]", nil)
	Check(Failed == nil, "score_= does not resolve")

	Failed = ResolveSelectorToken("@a[rx=90]", nil)
	Check(Failed == nil, "view angle does not resolve")
end





local function TestTargets()
	local Context =
	{
		World = DefaultWorld,
		Position = { x = 0, y = 64, z = 0 },
		Executor = Player1,
	}

	-- Plain names resolve through FindAndDoWithPlayer:
	CheckEquals(NamesOf(ResolveTargets("player1", nil, "player")), "player1", "ResolveTargets by name")
	CheckEquals(
		NamesOf(ResolveTargets("@a", Context, "player")),
		"player1,player2",
		"ResolveTargets @a as players (the nether player is deferred)"
	)
	CheckEquals(
		NamesOf(ResolveTargets("@e", Context, "pawn")),
		"player1,player2,type:cavespider,type:cow,type:creeper",
		"ResolveTargets @e as pawns (the nether pawns are deferred)"
	)

	-- A selector whose origin world has nothing of the requested kind is not a failure any more: the
	-- other worlds may still match, and they are visited by their own threads (method D2). The command
	-- then reports a zero count instead of "no target matched" (spec section 7.3):
	local Empty, Reason = ResolveTargets("@e[type=cow]", Context, "player")
	Check(Empty ~= nil, "no origin-world match is not an error: " .. tostring(Reason))
	CheckEquals(#Empty, 0, "no live targets in the origin world")
	Check(Empty.Deferred ~= nil, "the other worlds are still visited")

	-- A selector that is dimension-bound (and therefore never deferred) still fails:
	local Failed, FailedReason = ResolveTargets("@e[type=cow,r=5]", Context, "player")
	Check(Failed == nil, "a dimension-bound selector with no match fails")
	Check(
		(FailedReason ~= nil) and (FailedReason:find("No target matched") ~= nil),
		"empty selector result reason (got " .. tostring(FailedReason) .. ")"
	)

	-- Malformed selector, unknown name and empty token all fail:
	Check(ResolveTargets("@a[", Context, "player") == nil, "malformed selector fails")
	Check(ResolveTargets("nosuchplayer", Context, "player") == nil, "unknown player name fails")
	Check(ResolveTargets("", Context, "player") == nil, "empty target fails")

	-- GetTargetName: players by name, monsters by custom name or type:
	CheckEquals(GetTargetName(Player1), "player1", "GetTargetName for a player")
	local Cows = ResolveTargets("@e[name=Bessie]", Context, "pawn")
	CheckEquals(GetTargetName(Cows[1]), "Bessie", "GetTargetName uses the custom name")
	local Creepers = ResolveTargets("@e[type=creeper]", Context, "pawn")
	CheckEquals(GetTargetName(Creepers[1]), "creeper", "GetTargetName falls back to the mob type")
end

local function TestApply()
	local Context =
	{
		World = DefaultWorld,
		Position = { x = 0, y = 64, z = 0 },
		Executor = Player1,
	}

	local Targets = ResolveTargets("@a", Context, "player")
	CheckEquals(#Targets, 2, "@a selects the origin world's players before applying")

	local Seen = {}
	local Affected = ApplyToTargets(Targets, function (a_Target) table.insert(Seen, a_Target:GetName()) end)
	table.sort(Seen)
	CheckEquals(Affected, 2, "ApplyToTargets reports the origin world's affected targets")
	CheckEquals(
		table.concat(Seen, ","),
		"player1,player2",
		"ApplyToTargets visits the origin world's targets immediately"
	)

	-- A target that vanished between selection and application is skipped:
	local Saved = DefaultWorld.Entities
	local Remaining = {}
	for _, Entity in ipairs(Saved) do
		if (Entity ~= Player2) then
			table.insert(Remaining, Entity)
		end
	end
	DefaultWorld.Entities = Remaining
	local Affected2 = ApplyToTargets(Targets, function () end)
	CheckEquals(Affected2, 1, "vanished targets are skipped")
	DefaultWorld.Entities = Saved
end

BuildUniverse()
TestParser()
TestResolver()
TestTargets()
TestApply()

print(string.format("test_selectors: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
