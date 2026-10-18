-- entity_names.lua
-- One answer to "what is this entity id?", shared by /summon and the target selector's type= argument, so
-- that both accept exactly the same names.
--
-- Mobs are deliberately NOT listed here. The engine already owns that table: cMonster::StringToMobType()
-- matches g_MobTypeNames, which maps every mob type to its Cuberite name, its vanilla name and its 1.12.2
-- NBT id, case-insensitively. Duplicating those names in Lua would only let the two copies drift apart, so
-- both consumers ask the engine instead.
--
-- Everything else has no engine-side name map - /summon has to call a different constructor per kind, and the
-- selector needs the entity type to match it - so that mapping lives here once. Two kinds of entry live here:
-- the entities /summon can create, and the ones only the selector can see (Kind = "selector_only": the
-- entity type exists and can be selected, but Core has no way to create one, so /summon reports them as
-- unknown). What is missing is a deliberate omission: an entity Cuberite has no class for at all.

-- luacheck: new globals GetEntityInfo
-- luacheck: globals cMonster cBoat cEntity cProjectileEntity mtInvalidType
-- luacheck: globals E_ITEM_MINECART E_ITEM_CHEST_MINECART E_ITEM_FURNACE_MINECART
-- luacheck: globals E_ITEM_MINECART_WITH_HOPPER E_ITEM_MINECART_WITH_TNT
-- luacheck: ignore 111

-- The ids of everything that is not a mob, with what /summon needs to create it and what the selector needs
-- to recognise one. EntityType is the cEntity type the selector compares against; it is nil for the ids that
-- have no entity behind them (Cuberite models lightning as a world effect).
-- The entity types are constants of the cEntity class table, not globals: cEntity.etTNT, cEntity.etPickup, ...
-- (tolua registers them inside the cEntity module). Reading them as bare globals yields nil, which would
-- silently make every non-mob id unmatchable.
local ET = cEntity
local Pk = cProjectileEntity

local NON_MOB_ENTITIES =
{
	-- name              kind              EntityType          constructor argument
	tnt                = { Kind = "tnt",           EntityType = ET.etTNT },
	boat               = { Kind = "boat",          EntityType = ET.etBoat },
	falling_block      = { Kind = "falling_block", EntityType = ET.etFallingBlock },
	xp_orb             = { Kind = "xp_orb",        EntityType = ET.etExpOrb },
	ender_crystal      = { Kind = "ender_crystal", EntityType = ET.etEnderCrystal },
	lightning_bolt     = { Kind = "lightning_bolt" },

	minecart           = { Kind = "minecart", EntityType = ET.etMinecart, CartType = E_ITEM_MINECART },
	chest_minecart     = { Kind = "minecart", EntityType = ET.etMinecart, CartType = E_ITEM_CHEST_MINECART },
	furnace_minecart   = { Kind = "minecart", EntityType = ET.etMinecart, CartType = E_ITEM_FURNACE_MINECART },
	hopper_minecart    = { Kind = "minecart", EntityType = ET.etMinecart, CartType = E_ITEM_MINECART_WITH_HOPPER },
	tnt_minecart       = { Kind = "minecart", EntityType = ET.etMinecart, CartType = E_ITEM_MINECART_WITH_TNT },

	arrow              = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkArrow },
	egg                = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkEgg },
	ender_pearl        = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkEnderPearl },
	fireworks_rocket   = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkFirework },
	fireball           = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkGhastFireball },
	potion             = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkSplashPotion },
	small_fireball     = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkFireCharge },
	snowball           = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkSnowball },
	wither_skull       = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkWitherSkull },
	xp_bottle          = { Kind = "projectile", EntityType = ET.etProjectile, ProjectileKind = Pk.pkExpBottle },

	-- Selectable, but not creatable: these exist as entity types and /summon cannot make one (no NBT, no
	-- spawn branch), so only the selector half of this table applies to them.
	item               = { Kind = "selector_only", EntityType = ET.etPickup },
	item_frame         = { Kind = "selector_only", EntityType = ET.etItemFrame },
	painting           = { Kind = "selector_only", EntityType = ET.etPainting },
	leash_knot         = { Kind = "selector_only", EntityType = ET.etLeashKnot },
	area_effect_cloud  = { Kind = "selector_only", EntityType = ET.etAreaEffectCloud },
	eye_of_ender       = { Kind = "selector_only", EntityType = ET.etFloater },
}






--- Returns what an entity id names, or nil when Core does not know it.
-- { Kind = "mob", MobType = <eMonsterType> } for anything the engine's mob table knows, otherwise the
-- non-mob descriptor above (Kind plus the constructor argument and the entity type).
-- The lookup is case-insensitive: 1.11 made entity ids case-insensitive (the selector spec cites it), and it
-- is what makes the capitalised pre-1.11 spellings ("Creeper", "TNT") keep working without a name list.
function GetEntityInfo(a_Name)
	if (type(a_Name) ~= "string") or (a_Name == "") then
		return nil
	end

	local NonMob = NON_MOB_ENTITIES[a_Name:lower()]
	if (NonMob ~= nil) then
		return NonMob
	end

	local MobType = cMonster:StringToMobType(a_Name)
	if (MobType ~= mtInvalidType) then
		return { Kind = "mob", MobType = MobType }
	end
	return nil
end
