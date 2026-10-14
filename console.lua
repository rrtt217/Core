
-- console.lua
-- luacheck: globals ParseCommandCoords cRoot

-- Implements things related to console commands
-- TODO: remove this file, migrate commands below to unified cmd_*.lua format





function HandleConsolePlugins(Split)
	-- Enumerate the plugins:
	local PluginTable = {}
	cPluginManager:Get():ForEachPlugin(
		function (a_CBPlugin)
			table.insert(PluginTable,
				{
					Name = a_CBPlugin:GetName(),
					Folder = a_CBPlugin:GetFolderName(),
					Status = a_CBPlugin:GetStatus(),
					LoadError = a_CBPlugin:GetLoadError()
				}
			)
		end
	)
	table.sort(PluginTable,
		function (a_Plugin1, a_Plugin2)
			return (string.lower(a_Plugin1.Folder) < string.lower(a_Plugin2.Folder))
		end
	)

	-- Prepare a translation table for the status:
	local StatusName =
	{
		[cPluginManager.psLoaded]   = "Loaded  ",
		[cPluginManager.psUnloaded] = "Unloaded",
		[cPluginManager.psError]    = "Error   ",
		[cPluginManager.psNotFound] = "NotFound",
		[cPluginManager.psDisabled] = "Disabled",
	}

	-- Generate the output:
	local Out = {}
	table.insert(Out, "There are ")
	table.insert(Out, #PluginTable)
	table.insert(Out, " plugins, ")
	table.insert(Out, cPluginManager:Get():GetNumLoadedPlugins())
	table.insert(Out, " loaded:\n")
	for _, plg in ipairs(PluginTable) do
		table.insert(Out, "  ")
		table.insert(Out, StatusName[plg.Status] or "        ")
		table.insert(Out, " ")
		table.insert(Out, plg.Folder)
		if (plg.Name ~= plg.Folder) then
			table.insert(Out, " (API name ")
			table.insert(Out, plg.Name)
			table.insert(Out, ")")
		end
		if (plg.Status == cPluginManager.psError) then
			table.insert(Out, " ERROR: ")
			table.insert(Out, plg.LoadError or "<unknown>")
		end
		table.insert(Out, "\n")
	end
	return true, table.concat(Out, "")
end





function HandleConsoleTeleport(Split, _, _, _)
	-- These locals must be declared before the closures below: a closure that assigns a name which the
	-- enclosing scope declares *later* writes a global instead, and the outer read never sees it.
	local IsPlayerOnline = false
	local FirstPlayerOnline = false
	local PosX, PosY, PosZ

	local TeleportToCoords = function(TargetPlayer)
		if (TargetPlayer:GetName() == Split[2]) then
			IsPlayerOnline = true
			TargetPlayer:TeleportToCoords(PosX, PosY, PosZ)
		end
	end

	local GetPlayerCoords = function(SourcePlayer)
		if (SourcePlayer:GetName() == Split[3]) then
			PosX = SourcePlayer:GetPosX()
			PosY = SourcePlayer:GetPosY()
			PosZ = SourcePlayer:GetPosZ()
			FirstPlayerOnline = true
		end
	end

	local TeleportToPlayer = function(TargetPlayer)
		if (TargetPlayer:GetName() == Split[2]) then
			TargetPlayer:TeleportToCoords(PosX, PosY, PosZ)
			IsPlayerOnline = true
		end
	end

	if (#Split == 3) then
		cRoot:Get():FindAndDoWithPlayer(Split[3], GetPlayerCoords)
		if (FirstPlayerOnline) then
			cRoot:Get():FindAndDoWithPlayer(Split[2], TeleportToPlayer)
			if (IsPlayerOnline) then
				return true, "Teleported " .. Split[2] .." to " .. Split[3]
			end
			return true, "Player " .. Split[2] .." not found"
		end
		return true, "Player " .. Split[3] .." not found"

	elseif (#Split == 5) then
		-- 1.12.2 /tp resolves "~" against the entity being teleported, not against the command source
		-- (spec section 2.1b), so the target has to be found before the coordinates can be parsed:
		local TargetFound = false
		local ParseError = nil
		local Destination = nil

		local TeleportTarget = function(TargetPlayer)
			if (TargetPlayer:GetName() ~= Split[2]) then
				return
			end
			TargetFound = true

			local X, Y, Z, Reason = ParseCommandCoords(Split[3], Split[4], Split[5], TargetPlayer:GetPosition())
			if (X == nil) then
				ParseError = Reason
				return
			end

			TargetPlayer:TeleportToCoords(X, Y, Z)
			IsPlayerOnline = true
			Destination = "[X:" .. X .. " Y:" .. Y .. " Z:" .. Z .. "]"
		end

		cRoot:Get():FindAndDoWithPlayer(Split[2], TeleportTarget)

		if (ParseError ~= nil) then
			return true, ParseError
		end
		if (IsPlayerOnline) then
			return true, "You teleported " .. Split[2] .. " to " .. Destination
		end
		return true, "Player not found"

	else
		return true, "Usage: '" .. Split[1] .. " <target player> <destination player>' or 'tp <target player> <x> <y> <z>'"
	end
end
