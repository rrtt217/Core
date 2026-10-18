-- test_summon_handler.lua
--
-- Handler-level tests for /summon: every entity id the shared lookup knows must reach the constructor that
-- belongs to its kind, with the argument the lookup carries.
--
-- Why this file exists: entity_names.lua maps an id to a kind, and cmd_summon.lua turns the kind into one of
-- several World:Spawn...() calls. A wrong kind string, or a branch that forgets its constructor, only shows up
-- at runtime as "Unknown entity 'tnt'" for a perfectly valid id. tests/test_entity_names.lua pins the table;
-- this pins the dispatch that consumes it.
--
-- Verified specification: specs/commands/vanilla-1.12.2-command-layer-roadmap.md section 4.1 (/summon).
--
-- Invariants:
--   * Each kind reaches exactly one constructor, with Vector3d / Vector3i coordinates as that API expects.
--   * A projectile summon from the console does not touch the (absent) player - it used to raise
--     "attempt to call method 'GetEquippedItem' (a nil value)".
--
-- Run with:  lua tests/test_summon_handler.lua   (from the plugin folder)

-- The stubs below stand in for engine globals that the module under test reads, so luacheck counts
-- them as unused in this file (131 == "unused global variable").
-- luacheck: ignore 131

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."

-- Engine constants read while entity_names.lua loads.
mtInvalidType = "mtInvalidType"
-- The entity types live on the cEntity class table (tolua registers them inside that module), which is where
-- entity_names.lua reads them from; a bare global would be nil in the real server.
cEntity =
{
	etEntity = "etEntity", etEnderCrystal = "etEnderCrystal", etPlayer = "etPlayer",
	etPickup = "etPickup", etMonster = "etMonster", etFallingBlock = "etFallingBlock",
	etMinecart = "etMinecart", etBoat = "etBoat", etTNT = "etTNT", etProjectile = "etProjectile",
	etExpOrb = "etExpOrb", etFloater = "etFloater", etItemFrame = "etItemFrame",
	etPainting = "etPainting", etLeashKnot = "etLeashKnot", etAreaEffectCloud = "etAreaEffectCloud",
}
E_ITEM_MINECART, E_ITEM_CHEST_MINECART, E_ITEM_FURNACE_MINECART =
	"E_ITEM_MINECART", "E_ITEM_CHEST_MINECART", "E_ITEM_FURNACE_MINECART"
E_ITEM_MINECART_WITH_HOPPER, E_ITEM_MINECART_WITH_TNT = "E_ITEM_MINECART_WITH_HOPPER", "E_ITEM_MINECART_WITH_TNT"
E_BLOCK_SAND = 12
cProjectileEntity =
{
	pkArrow = "pkArrow", pkEgg = "pkEgg", pkEnderPearl = "pkEnderPearl", pkFirework = "pkFirework",
	pkGhastFireball = "pkGhastFireball", pkSplashPotion = "pkSplashPotion", pkFireCharge = "pkFireCharge",
	pkSnowball = "pkSnowball", pkWitherSkull = "pkWitherSkull", pkExpBottle = "pkExpBottle",
}
cBoat = { bmOak = "bmOak" }

-- The engine's mob table: a name (any of its spellings, case-insensitively) resolves to a mob type.
local MOB_TYPES = { creeper = "mtCreeper", cow = "mtCow", cave_spider = "mtCaveSpider", cavespider = "mtCaveSpider" }
cMonster =
{
	StringToMobType = function (a_Self, a_Name)
		assert(a_Self == cMonster, "StringToMobType must be called with colon syntax")
		for Name, MobType in pairs(MOB_TYPES) do
			if (Name:lower() == a_Name:lower()) then
				return MobType
			end
		end
		return mtInvalidType
	end,
}

Vector3d = function (a_X, a_Y, a_Z) return { Kind = "Vector3d", x = a_X, y = a_Y, z = a_Z } end
Vector3i = function (a_X, a_Y, a_Z) return { Kind = "Vector3i", x = a_X, y = a_Y, z = a_Z } end
cItem = function () return { Kind = "cItem" } end

local LastMessage = nil
SendMessage = function (_, a_Message) LastMessage = "info: " .. tostring(a_Message); return nil end
SendMessageSuccess = function (_, a_Message) LastMessage = "success: " .. tostring(a_Message); return nil end
SendMessageFailure = function (_, a_Message) LastMessage = "failure: " .. tostring(a_Message); return nil end

dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../entity_names.lua")
dofile(ScriptDir .. "/../cmd_summon.lua")

-- luacheck: new globals cMonster mtInvalidType cEntity
-- luacheck: new globals E_ITEM_MINECART E_ITEM_CHEST_MINECART E_ITEM_FURNACE_MINECART
-- luacheck: new globals E_ITEM_MINECART_WITH_HOPPER E_ITEM_MINECART_WITH_TNT E_BLOCK_SAND cProjectileEntity
-- luacheck: new globals cBoat Vector3d Vector3i cItem cRoot SendMessage SendMessageSuccess SendMessageFailure
-- luacheck: read globals HandleSummonCommand

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
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end






-- Fakes ----------------------------------------------------------------------

local World = nil

local function MakeWorld()
	local NewWorld = { Calls = {} }

	local function Record(a_Name, ...)
		table.insert(NewWorld.Calls, { Name = a_Name, Args = { ... } })
	end

	NewWorld.SpawnMob = function (_, a_X, a_Y, a_Z, a_MobType) Record("SpawnMob", a_X, a_Y, a_Z, a_MobType) end
	NewWorld.SpawnMinecart = function (_, a_Pos, a_CartType) Record("SpawnMinecart", a_Pos, a_CartType) end
	NewWorld.CreateProjectile = function (_, a_Pos, a_Kind, a_Creator, a_Item, a_Speed)
		Record("CreateProjectile", a_Pos, a_Kind, a_Creator, a_Item, a_Speed)
	end
	NewWorld.SpawnBoat = function (_, a_Pos, a_Material) Record("SpawnBoat", a_Pos, a_Material) end
	NewWorld.SpawnFallingBlock = function (_, a_Pos, a_BlockType, a_BlockMeta)
		Record("SpawnFallingBlock", a_Pos, a_BlockType, a_BlockMeta)
	end
	NewWorld.CastThunderbolt = function (_, a_Pos) Record("CastThunderbolt", a_Pos) end
	NewWorld.SpawnPrimedTNT = function (_, a_Pos) Record("SpawnPrimedTNT", a_Pos) end
	NewWorld.SpawnExperienceOrb = function (_, a_Pos, a_Reward) Record("SpawnExperienceOrb", a_Pos, a_Reward) end
	NewWorld.SpawnEnderCrystal = function (_, a_Pos, a_ShowBottom) Record("SpawnEnderCrystal", a_Pos, a_ShowBottom) end
	return NewWorld
end

local function MakePlayer()
	return
	{
		GetPosX = function () return 1 end,
		GetPosY = function () return 65 end,
		GetPosZ = function () return 2 end,
		GetWorld = function () return World end,
		GetEquippedItem = function () return { Kind = "equipped" } end,
		GetLookVector = function ()
			return setmetatable(
				{ x = 0, y = 0, z = 1 },
				{ __mul = function (a_Self, a_Factor) return { Kind = "speed", Factor = a_Factor } end }
			)
		end,
	}
end

local Origin = nil

local function ResetUniverse()
	World = MakeWorld()
	Origin =
	{
		GetWorld = function () return World end,
		GetPosition = function () return { x = 0, y = 64, z = 0 } end,
	}
	cRoot = { Get = function () return { GetDefaultWorld = function () return World end } end }
	LastMessage = nil
end

--- Runs one /summon line and returns the world's call records.
local function Run(a_Line, a_Player)
	local Split = { a_Line:match("^(%S+)") }
	for Token in a_Line:gmatch("%s+(%S+)") do
		Split[#Split + 1] = Token
	end
	World.Calls = {}
	LastMessage = nil
	HandleSummonCommand(Split, a_Player, a_Line, Origin)
	return World.Calls
end






local function TestDispatch()
	-- One case per kind: the constructor the entity id must reach.
	-- { entity id, expected constructor, expected last argument (nil for the ones that take none) }:
	local CASES =
	{
		{ "cow",              "SpawnMob",           "mtCow" },
		{ "chest_minecart",   "SpawnMinecart",      E_ITEM_CHEST_MINECART },
		{ "hopper_minecart",  "SpawnMinecart",      E_ITEM_MINECART_WITH_HOPPER },
		{ "boat",             "SpawnBoat",          "bmOak" },
		{ "falling_block",    "SpawnFallingBlock",  0 },
		{ "lightning_bolt",   "CastThunderbolt",    nil },
		{ "tnt",              "SpawnPrimedTNT",     nil },
		{ "xp_orb",           "SpawnExperienceOrb", 1 },
		{ "ender_crystal",    "SpawnEnderCrystal",  false },
	}

	for _, Case in ipairs(CASES) do
		local Name, Constructor, LastArgument = Case[1], Case[2], Case[3]
		local Calls = Run("/summon " .. Name .. " 10 70 20", nil)
		CheckEquals(#Calls, 1, "\"" .. Name .. "\" makes exactly one call")
		local Call = Calls[1]
		if (Call ~= nil) then
			CheckEquals(Call.Name, Constructor, "\"" .. Name .. "\" reaches " .. Constructor)
			-- The coordinate argument is the one the API takes:
			if (Constructor == "SpawnMob") then
				CheckEquals(Call.Args[1], 10, "\"" .. Name .. "\" passes plain numbers")
				CheckEquals(Call.Args[3], 20, "\"" .. Name .. "\" passes plain numbers")
			else
				local Position = Call.Args[1]
				Check(Position ~= nil, "\"" .. Name .. "\" passes a position")
				CheckEquals(Position and Position.x, 10, "\"" .. Name .. "\" passes the x coordinate")
				CheckEquals(Position and Position.z, 20, "\"" .. Name .. "\" passes the z coordinate")
			end
			-- ... and the kind's own argument, where the constructor takes one:
			if (LastArgument ~= nil) then
				CheckEquals(Call.Args[#Call.Args], LastArgument, "\"" .. Name .. "\" passes its own kind")
			elseif (Constructor == "CastThunderbolt") or (Constructor == "SpawnPrimedTNT") then
				CheckEquals(#Call.Args, 1, "\"" .. Name .. "\" passes nothing but the position")
			end
		end
	end

	-- A mob name any of the engine's spellings resolves, not just the 1.12.2 id:
	local Calls = Run("/summon CaveSpider 0 64 0", nil)
	CheckEquals(#Calls, 1, "CaveSpider resolves")
	CheckEquals(Calls[1] and Calls[1].Args[4], "mtCaveSpider", "CaveSpider reaches the cave spider mob type")

	-- An id Core cannot create is reported, and nothing is spawned:
	Calls = Run("/summon elder_guardian 0 64 0", nil)
	CheckEquals(#Calls, 0, "an unknown id spawns nothing")
	Check(
		(LastMessage ~= nil) and (LastMessage:find("Unknown entity", 1, true) ~= nil),
		"an unknown id is reported"
	)
end






local function TestProjectiles()
	-- With a player: the projectile inherits the shooter, their item and a look-vector speed.
	local Player = MakePlayer()
	local Calls = Run("/summon arrow 10 70 20", Player)
	CheckEquals(#Calls, 1, "arrow makes one call")
	local Call = Calls[1]
	if (Call ~= nil) then
		CheckEquals(Call.Name, "CreateProjectile", "arrow reaches CreateProjectile")
		CheckEquals(Call.Args[2], cProjectileEntity.pkArrow, "arrow passes its kind")
		CheckEquals(Call.Args[3], Player, "the player is the creator")
		CheckEquals(Call.Args[4] and Call.Args[4].Kind, "equipped", "the player's item is passed")
		CheckEquals(Call.Args[5] and Call.Args[5].Kind, "speed", "the look vector is passed as the speed")
		CheckEquals(Call.Args[5] and Call.Args[5].Factor, 20, "the look vector is scaled")
	end

	-- From the console: no player, so no creator, no item and no speed - and no nil method call.
	Calls = Run("/summon snowball 10 70 20", nil)
	CheckEquals(#Calls, 1, "a console summon makes one call")
	Call = Calls[1]
	if (Call ~= nil) then
		CheckEquals(Call.Name, "CreateProjectile", "a console summon reaches CreateProjectile")
		CheckEquals(Call.Args[2], cProjectileEntity.pkSnowball, "the kind is passed")
		CheckEquals(Call.Args[3], nil, "there is no creator")
		CheckEquals(Call.Args[4] and Call.Args[4].Kind, "cItem", "an empty item stands in for the held one")
		CheckEquals(Call.Args[5], nil, "there is no speed")
	end
	Check(
		(LastMessage ~= nil) and (LastMessage:find("success", 1, true) ~= nil),
		"the console summon reports success instead of raising"
	)
end






ResetUniverse()
TestDispatch()

ResetUniverse()
TestProjectiles()

print(string.format("test_summon_handler: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
