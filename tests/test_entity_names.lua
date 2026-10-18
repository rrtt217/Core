-- test_entity_names.lua
--
-- Table-driven tests for entity_names.lua, the one lookup that answers "what is this entity id?" for both
-- /summon and the target selector's type= argument.
--
-- Verified specification: specs/commands/vanilla-1.12.2-command-target-selectors.md (type= argument) and
-- specs/commands/vanilla-1.12.2-command-layer-roadmap.md section 4.1 (/summon).
--
-- Invariants:
--   * Mobs are resolved by the engine's own table (cMonster::StringToMobType), not by a Lua copy, so a name
--     the engine knows can never fall out of sync with the selector. This file stubs that table with the
--     same three spellings per mob it has (Cuberite name, vanilla name, 1.12.2 id) and asserts the lookup
--     passes the name through unchanged.
--   * Every non-mob id carries the constructor argument /summon needs and the entity type the selector needs,
--     and its Kind is one the /summon dispatch knows - a typo there would otherwise turn into "Unknown
--     entity" at runtime.
--   * The lookup is case-insensitive (1.11 made entity ids case-insensitive), so no capitalised alias is
--     needed in the table.
--   * The pre-1.11 spellings that only /summon's old hand-written table knew ("PrimedTnt", "MinecartChest",
--     ...) are NOT accepted any more: they were never 1.12.2 ids and existed only in that table.
--
-- Run with:  lua tests/test_entity_names.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."

-- Engine constants entity_names.lua reads while it loads. The values are opaque sentinels: the tests compare
-- them for identity, they never need the numbers.
mtInvalidType = "mtInvalidType"
-- The entity types are constants of the cEntity class table (tolua registers them inside that module), not
-- globals: this mirrors the path entity_names.lua has to use, so a bare "etTNT" (nil in the real server)
-- cannot slip through.
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
cProjectileEntity =
{
	pkArrow = "pkArrow", pkEgg = "pkEgg", pkEnderPearl = "pkEnderPearl", pkFirework = "pkFirework",
	pkGhastFireball = "pkGhastFireball", pkSplashPotion = "pkSplashPotion", pkFireCharge = "pkFireCharge",
	pkSnowball = "pkSnowball", pkWitherSkull = "pkWitherSkull", pkExpBottle = "pkExpBottle",
}

-- Stands in for cMonster::StringToMobType(), which matches g_MobTypeNames: every mob type has a Cuberite
-- name, a vanilla name and a 1.12.2 NBT id, and the match is case-insensitive. Only the mobs used below are
-- listed; anything else must come back as mtInvalidType.
local MOB_TYPES =
{
	creeper = "mtCreeper",
	cow = "mtCow",
	cavespider = "mtCaveSpider",
	cave_spider = "mtCaveSpider",
	CaveSpider = "mtCaveSpider",
	zombie = "mtZombie",
	PigZombie = "mtZombiePigman",
	zombie_pigman = "mtZombiePigman",
}

cMonster =
{
	StringToMobType = function (a_Self, a_Name)
		assert(a_Self == cMonster, "StringToMobType must be called with colon syntax")
		assert(type(a_Name) == "string", "StringToMobType expects a string argument")
		local Exact = MOB_TYPES[a_Name]
		if (Exact ~= nil) then
			return Exact
		end
		for Name, MobType in pairs(MOB_TYPES) do
			if (Name:lower() == a_Name:lower()) then
				return MobType
			end
		end
		return mtInvalidType
	end,
}

dofile(ScriptDir .. "/../entity_names.lua")

-- luacheck: new globals cMonster mtInvalidType cEntity
-- luacheck: new globals cEntity
-- luacheck: new globals E_ITEM_MINECART E_ITEM_CHEST_MINECART E_ITEM_FURNACE_MINECART cEntity
-- luacheck: new globals E_ITEM_MINECART_WITH_HOPPER E_ITEM_MINECART_WITH_TNT cProjectileEntity cEntity
-- luacheck: read globals GetEntityInfo cEntity

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






local function TestMobsComeFromTheEngine()
	local Info = GetEntityInfo("cow")
	Check((Info ~= nil) and (Info.Kind == "mob"), "a mob id resolves to a mob")
	CheckEquals(Info and Info.MobType, "mtCow", "the mob type is the engine's")

	-- The engine's table is case-insensitive and knows three spellings per mob; all of them must reach the
	-- same mob type (this is what the selector always relied on):
	CheckEquals(GetEntityInfo("Cow").MobType, "mtCow", "\"Cow\" resolves")
	CheckEquals(GetEntityInfo("COW").MobType, "mtCow", "\"COW\" resolves")
	CheckEquals(GetEntityInfo("cave_spider").MobType, "mtCaveSpider", "the 1.12.2 id resolves")
	CheckEquals(GetEntityInfo("CaveSpider").MobType, "mtCaveSpider", "the vanilla name resolves")
	CheckEquals(GetEntityInfo("cavespider").MobType, "mtCaveSpider", "Cuberite's own spelling resolves")
	CheckEquals(GetEntityInfo("PigZombie").MobType, "mtZombiePigman", "the pre-1.11 name resolves")

	-- A name the engine does not know is not an entity, even though it looks like one:
	CheckEquals(GetEntityInfo("cowboy"), nil, "an unknown name is not an entity")
end






local function TestNonMobEntities()
	-- Every non-mob id Core can create, with what /summon needs to create it and what the selector needs to
	-- recognise one. Transcribed from entity_names.lua's table on purpose, so that a missing or mistyped
	-- entry fails here instead of turning into "Unknown entity" at runtime.
	local CASES =
	{
		{ "tnt",            "tnt",            cEntity.etTNT },
		{ "boat",           "boat",           cEntity.etBoat },
		{ "falling_block",  "falling_block",  cEntity.etFallingBlock },
		{ "xp_orb",         "xp_orb",         cEntity.etExpOrb },
		{ "ender_crystal",  "ender_crystal",  cEntity.etEnderCrystal },
		{ "minecart",       "minecart",       cEntity.etMinecart },
		{ "chest_minecart", "minecart",       cEntity.etMinecart },
		{ "furnace_minecart", "minecart",     cEntity.etMinecart },
		{ "hopper_minecart", "minecart",      cEntity.etMinecart },
		{ "tnt_minecart",   "minecart",       cEntity.etMinecart },
		{ "arrow",          "projectile",     cEntity.etProjectile },
		{ "egg",            "projectile",     cEntity.etProjectile },
		{ "ender_pearl",    "projectile",     cEntity.etProjectile },
		{ "fireworks_rocket", "projectile",   cEntity.etProjectile },
		{ "fireball",       "projectile",     cEntity.etProjectile },
		{ "potion",         "projectile",     cEntity.etProjectile },
		{ "small_fireball", "projectile",     cEntity.etProjectile },
		{ "snowball",       "projectile",     cEntity.etProjectile },
		{ "wither_skull",   "projectile",     cEntity.etProjectile },
		{ "xp_bottle",      "projectile",     cEntity.etProjectile },
		-- Selectable but not creatable: the entity type exists, Core cannot make one.
		{ "item",              "selector_only", cEntity.etPickup },
		{ "item_frame",        "selector_only", cEntity.etItemFrame },
		{ "painting",          "selector_only", cEntity.etPainting },
		{ "leash_knot",        "selector_only", cEntity.etLeashKnot },
		{ "area_effect_cloud", "selector_only", cEntity.etAreaEffectCloud },
		{ "eye_of_ender",      "selector_only", cEntity.etFloater },
	}

	for _, Case in ipairs(CASES) do
		local Name, Kind, EntityType = Case[1], Case[2], Case[3]
		local Info = GetEntityInfo(Name)
		Check(Info ~= nil, "\"" .. Name .. "\" resolves")
		if (Info ~= nil) then
			CheckEquals(Info.Kind, Kind, "\"" .. Name .. "\" has the kind the dispatch handles")
			CheckEquals(Info.EntityType, EntityType, "\"" .. Name .. "\" carries the entity type the selector compares")
		end
	end

	-- Lightning has no entity behind it in Cuberite (it is a world effect), so the selector cannot match one:
	local Lightning = GetEntityInfo("lightning_bolt")
	Check((Lightning ~= nil) and (Lightning.Kind == "lightning_bolt"), "lightning_bolt resolves")
	CheckEquals(Lightning and Lightning.EntityType, nil, "lightning_bolt has no entity type")

	-- The constructor arguments are the ones the spawn call takes:
	CheckEquals(GetEntityInfo("chest_minecart").CartType, E_ITEM_CHEST_MINECART, "the chest minecart's item type")
	CheckEquals(GetEntityInfo("potion").ProjectileKind, cProjectileEntity.pkSplashPotion, "the potion's projectile kind")
	CheckEquals(GetEntityInfo("wither_skull").ProjectileKind, cProjectileEntity.pkWitherSkull, "the wither skull's kind")

	-- Case-insensitive, like the mobs:
	CheckEquals(GetEntityInfo("TNT").Kind, "tnt", "\"TNT\" resolves")
	CheckEquals(GetEntityInfo("Boat").Kind, "boat", "\"Boat\" resolves")
	CheckEquals(GetEntityInfo("XP_ORB").Kind, "xp_orb", "\"XP_ORB\" resolves")
end






local function TestUnknownAndOldSpellings()
	-- Nothing in the engine's table, nothing in the non-mob table:
	CheckEquals(GetEntityInfo("elder_guardian"), nil, "an id Core cannot create is not an entity")
	-- "item" itself is in the table now (selector-only); an entity Cuberite has no class for is not:
	CheckEquals(GetEntityInfo("armor_stand"), nil, "an entity type Cuberite lacks is not an entity here")
	CheckEquals(GetEntityInfo("minecraft:tnt"), nil, "entity ids are not namespaced in 1.12.2 commands")

	-- The pre-1.11 spellings only /summon's old table knew are gone with that table:
	CheckEquals(GetEntityInfo("PrimedTnt"), nil, "\"PrimedTnt\" is not a 1.12.2 id")
	CheckEquals(GetEntityInfo("FallingSand"), nil, "\"FallingSand\" is not a 1.12.2 id")
	CheckEquals(GetEntityInfo("LightningBolt"), nil, "\"LightningBolt\" is not a 1.12.2 id")
	CheckEquals(GetEntityInfo("EnderCrystal"), nil, "\"EnderCrystal\" is not a 1.12.2 id")
	CheckEquals(GetEntityInfo("XPOrb"), nil, "\"XPOrb\" is not a 1.12.2 id")
	CheckEquals(GetEntityInfo("MinecartChest"), nil, "\"MinecartChest\" is not a 1.12.2 id")
	CheckEquals(GetEntityInfo("ThrownEgg"), nil, "\"ThrownEgg\" is not a 1.12.2 id")

	-- Malformed input must not raise:
	CheckEquals(GetEntityInfo(nil), nil, "nil is not an entity")
	CheckEquals(GetEntityInfo(""), nil, "an empty name is not an entity")
	CheckEquals(GetEntityInfo(42), nil, "a number is not an entity")
end






TestMobsComeFromTheEngine()
TestNonMobEntities()
TestUnknownAndOldSpellings()

print(string.format("test_entity_names: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
