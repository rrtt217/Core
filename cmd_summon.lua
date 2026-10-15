-- luacheck: globals ParseCommandCoords GetOriginPosition SpawnEntity
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess cRoot
local Minecarts =
{
	["minecart"] = E_ITEM_MINECART,
	["chest_minecart"] = E_ITEM_CHEST_MINECART,
	["furnace_minecart"] = E_ITEM_FURNACE_MINECART,
	["hopper_minecart"] = E_ITEM_MINECART_WITH_HOPPER,
	["tnt_minecart"] = E_ITEM_MINECART_WITH_TNT,

	-- 1.10 and below
	["MinecartChest"] = E_ITEM_CHEST_MINECART,
	["MinecartFurnace"] = E_ITEM_FURNACE_MINECART,
	["MinecartHopper"] = E_ITEM_MINECART_WITH_HOPPER,
	["MinecartRideable"] = E_ITEM_MINECART,
	["MinecartTNT"] = E_ITEM_MINECART_WITH_TNT
}

local Mobs =
{
	["bat"] = mtBat,
	["blaze"] = mtBlaze,
	["cave_spider"] = mtCaveSpider,
	["chicken"] = mtChicken,
	["cow"] = mtCow,
	["creeper"] = mtCreeper,
	["ender_dragon"] = mtEnderDragon,
	["enderman"] = mtEnderman,
	["ghast"] = mtGhast,
	["giant"] = mtGiant,
	["guardian"] = mtGuardian,
	["horse"] = mtHorse,
	["iron_golem"] = mtIronGolem,
	["magma_cube"] = mtMagmaCube,
	["mooshroom"] = mtMooshroom,
	["ocelot"] = mtOcelot,
	["pig"] = mtPig,
	["rabbit"] = mtRabbit,
	["sheep"] = mtSheep,
	["silverfish"] = mtSilverfish,
	["skeleton"] = mtSkeleton,
	["slime"] = mtSlime,
	["snowman"] = mtSnowGolem,
	["spider"] = mtSpider,
	["squid"] = mtSquid,
	["villager"] = mtVillager,
	["witch"] = mtWitch,
	["wither"] = mtWither,
	["wither_skeleton"] = mtWitherSkeleton,
	["wolf"] = mtWolf,
	["zombie"] = mtZombie,
	["zombie_pigman"] = mtZombiePigman,
	["zombie_villager"] = mtZombieVillager,

	-- 1.10 and below
	["Bat"] = mtBat,
	["Blaze"] = mtBlaze,
	["CaveSpider"] = mtCaveSpider,
	["Chicken"] = mtChicken,
	["Cow"] = mtCow,
	["Creeper"] = mtCreeper,
	["EnderDragon"] = mtEnderDragon,
	["Enderman"] = mtEnderman,
	["Ghast"] = mtGhast,
	["Giant"] = mtGiant,
	["Guardian"] = mtGuardian,
	["Horse"] = mtHorse,
	["LavaSlime"] = mtMagmaCube,
	["MushroomCow"] = mtMooshroom,
	["Ozelot"] = mtOcelot,
	["Pig"] = mtPig,
	["Rabbit"] = mtRabbit,
	["Sheep"] = mtSheep,
	["Silverfish"] = mtSilverfish,
	["Skeleton"] = mtSkeleton,
	["Slime"] = mtSlime,
	["SnowMan"] = mtSnowGolem,
	["Spider"] = mtSpider,
	["Squid"] = mtSquid,
	["Villager"] = mtVillager,
	["VillagerGolem"] = mtIronGolem,
	["Witch"] = mtWitch,
	["Wither"] = mtWither,
	["WitherSkeleton"] = mtWitherSkeleton,
	["Wolf"] = mtWolf,
	["Zombie"] = mtZombie,
	["PigZombie"] = mtZombiePigman,
	["ZombieVillager"] = mtZombieVillager
}

local Projectiles =
{
	["arrow"] = cProjectileEntity.pkArrow,
	["egg"] = cProjectileEntity.pkEgg,
	["ender_pearl"] = cProjectileEntity.pkEnderPearl,
	["fireworks_rocket"] = cProjectileEntity.pkFirework,
	["fireball"] = cProjectileEntity.pkGhastFireball,
	["potion"] = cProjectileEntity.pkSplashPotion,
	["small_fireball"] = cProjectileEntity.pkFireCharge,
	["snowball"] = cProjectileEntity.pkSnowball,
	["wither_skull"] = cProjectileEntity.pkWitherSkull,
	["xp_bottle"] = cProjectileEntity.pkExpBottle,

	-- 1.10 and below
	["Arrow"] = cProjectileEntity.pkArrow,
	["Fireball"] = cProjectileEntity.pkGhastFireball,
	["FireworksRocketEntity"] = cProjectileEntity.pkFirework,
	["SmallFireball"] = cProjectileEntity.pkFireCharge,
	["Snowball"] = cProjectileEntity.pkSnowball,
	["ThrownEgg"] = cProjectileEntity.pkEgg,
	["ThrownEnderpearl"] = cProjectileEntity.pkEnderPearl,
	["ThrownExpBottle"] = cProjectileEntity.pkExpBottle,
	["ThrownPotion"] = cProjectileEntity.pkSplashPotion,
	["WitherSkull"] = cProjectileEntity.pkWitherSkull
}

local function SpawnEntity(EntityName, World, X, Y, Z, Player)
	if EntityName == "boat" or EntityName == "Boat" then
		local Material = cBoat.bmOak

		World:SpawnBoat(Vector3d(X, Y, Z), Material)
	elseif EntityName == "falling_block" or EntityName == "FallingSand" then
		local BlockType = E_BLOCK_SAND
		local BlockMeta = 0

		World:SpawnFallingBlock(Vector3i(X, Y, Z), BlockType, BlockMeta)
	elseif EntityName == "lightning_bolt" or EntityName == "LightningBolt" then
		World:CastThunderbolt(Vector3i(X, Y, Z))
	elseif Minecarts[EntityName] then
		World:SpawnMinecart(Vector3d(X, Y, Z), Minecarts[EntityName])
	elseif Mobs[EntityName] then
		World:SpawnMob(X, Y, Z, Mobs[EntityName])
	elseif Projectiles[EntityName] then
		World:CreateProjectile(Vector3d(X, Y, Z), Projectiles[EntityName], Player, Player:GetEquippedItem(), Player:GetLookVector() * 20)
	elseif EntityName == "tnt" or EntityName == "PrimedTnt" then
		World:SpawnPrimedTNT(Vector3d(X, Y, Z))
	elseif EntityName == "xp_orb" or EntityName == "XPOrb" then
		local Reward = 1

		World:SpawnExperienceOrb(Vector3d(X, Y, Z), Reward)
	elseif EntityName == "ender_crystal" or EntityName == "EnderCrystal" then
		World:SpawnEnderCrystal(Vector3d(X, Y, Z), false)
	else
		return false
	end
	return true
end

function HandleSummonCommand(Split, Player, _, Origin)
	local Response

	if not Split[2] or (not Player and not Split[5]) then
		Response = SendMessage(Player, "Usage: " .. Split[1] .. " <entityname> [x] [y] [z]")
	else
		local X
		local Y
		local Z
		local World = cRoot:Get():GetDefaultWorld()

		-- The command's execution position: a command block's own position, a player's feet. Relative
		-- coordinates are resolved against it (specs/commands/vanilla-1.12.2-command-coordinates.md):
		local BasePosition = GetOriginPosition(Origin)
		if (BasePosition == nil) and (Player ~= nil) then
			BasePosition = Player:GetPosition()
		end

		if (Origin ~= nil) and (Origin:GetWorld() ~= nil) then
			World = Origin:GetWorld()
		elseif Player then
			World = Player:GetWorld()
		end

		if Split[5] then
			local Reason
			X, Y, Z, Reason = ParseCommandCoords(Split[3], Split[4], Split[5], BasePosition)
			if (X == nil) then
				return true, SendMessageFailure(Player, Reason)
			end
		elseif Player then
			X = Player:GetPosX()
			Y = Player:GetPosY()
			Z = Player:GetPosZ()
		end

		if SpawnEntity(Split[2], World, X, Y, Z, Player) then
			Response = SendMessageSuccess(Player, "Successfully summoned entity at [X:" .. math.floor(X) .. " Y:" .. math.floor(Y) .. " Z:" .. math.floor(Z) .. "]")
		else
			Response = SendMessageFailure(Player, "Unknown entity '" .. Split[2] .. "'")
		end
	end
	return true, Response
end

function HandleConsoleSummon(Split, _, EntireCommand, Origin)
	-- The engine passes the origin as the 4th argument; console commands have no player:
	return HandleSummonCommand(Split, nil, EntireCommand, Origin)
end
