-- The console handler is only referenced from Info.lua, so luacheck counts it as an unused global in this
-- file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: globals ParseCommandCoords GetOriginPosition GetEntityInfo
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess cRoot
-- luacheck: globals cBoat cItem Vector3d Vector3i
--
-- Entity names are not listed in this file: entity_names.lua answers "what is this id?" for both this command
-- and the target selector, asking the engine's own mob table for mobs and carrying the non-mob ids once.
local function SpawnEntity(EntityName, World, X, Y, Z, Player)
	local Info = GetEntityInfo(EntityName)
	if (Info == nil) then
		return false
	end

	if (Info.Kind == "mob") then
		return true, World:SpawnMob(X, Y, Z, Info.MobType)
	elseif (Info.Kind == "minecart") then
		return true, World:SpawnMinecart(Vector3d(X, Y, Z), Info.CartType)
	elseif (Info.Kind == "projectile") then
		-- A projectile remembers who shot it and with what. Without a player (the console) there is neither,
		-- so it starts at rest instead of inheriting a look direction - and no nil method is called.
		if (Player ~= nil) then
			return true, World:CreateProjectile(
				Vector3d(X, Y, Z), Info.ProjectileKind, Player, Player:GetEquippedItem(), Player:GetLookVector() * 20
			)
		end
		return true, World:CreateProjectile(Vector3d(X, Y, Z), Info.ProjectileKind, nil, cItem())
	elseif (Info.Kind == "boat") then
		World:SpawnBoat(Vector3d(X, Y, Z), cBoat.bmOak)
	elseif (Info.Kind == "falling_block") then
		World:SpawnFallingBlock(Vector3i(X, Y, Z), E_BLOCK_SAND, 0)
	elseif (Info.Kind == "lightning_bolt") then
		World:CastThunderbolt(Vector3i(X, Y, Z))
	elseif (Info.Kind == "tnt") then
		World:SpawnPrimedTNT(Vector3d(X, Y, Z))
	elseif (Info.Kind == "xp_orb") then
		World:SpawnExperienceOrb(Vector3d(X, Y, Z), 1)
	elseif (Info.Kind == "ender_crystal") then
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

		local Success, EntityId = SpawnEntity(Split[2], World, X, Y, Z, Player)
		if Success then
			Response = SendMessageSuccess(
				Player,
				"Successfully summoned entity at [X:" .. math.floor(X)
					.. " Y:" .. math.floor(Y) .. " Z:" .. math.floor(Z) .. "]"
			)
			if (Player ~= nil) and (type(EntityId) == "number") then
				World:DoWithEntityByID(EntityId,
					function( a_Entity )
						Player:TriggerSummonedEntity( a_Entity )
						return true
					end
				)
			end
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
