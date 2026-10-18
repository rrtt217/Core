-- cmd_save.lua
-- Implements the vanilla 1.12.2 /save-off and /save-on commands.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-server-state-commands.md
--
-- The two commands share one body: vanilla treats automatic saving as one server-wide switch, while
-- Cuberite stores it per world. cRoot:SetSavingEnabled() flips every world, so "is the switch already in
-- the requested position?" means "do all worlds already have that value?" (spec section 2.1).

-- The handlers are only referenced from Info.lua, so luacheck counts them as unused globals in this
-- file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals HandleSaveOffCommand HandleSaveOnCommand HandleConsoleSaveOff HandleConsoleSaveOn
-- luacheck: globals cRoot SendMessageFailure SendMessageSuccess

--- Returns true if at least one world's automatic-saving switch equals a_Enabled.
local function HasWorldWithSaving(a_Enabled)
	local Found = false
	cRoot:Get():ForEachWorld(
		function (a_World)
			if (a_World:IsSavingEnabled() == a_Enabled) then
				Found = true
			end
		end
	)
	return Found
end



--- Shared body of /save-off and /save-on.
-- a_Enable is true for /save-on and false for /save-off. Both commands take no arguments, and the one
-- that would not change anything fails (spec section 2.1). The third return value is the command's
-- success count: 1 when the switch moved, 0 when nothing was done.
local function SetAutomaticSaving(a_Split, a_Player, a_Enable)
	if ((a_Split[2] ~= nil) and (a_Split[2] ~= "")) then
		return true, SendMessageFailure(a_Player, "Usage: " .. a_Split[1]), 0
	end

	if (a_Enable) then
		if (not HasWorldWithSaving(false)) then
			return true, SendMessageFailure(a_Player, "Automatic saving is already enabled"), 0
		end
		cRoot:Get():SetSavingEnabled(true)
		return true, SendMessageSuccess(a_Player, "Automatic saving is now enabled"), 1
	end

	if (not HasWorldWithSaving(true)) then
		return true, SendMessageFailure(a_Player, "Automatic saving is already disabled"), 0
	end
	cRoot:Get():SetSavingEnabled(false)
	return true, SendMessageSuccess(a_Player, "Automatic saving is now disabled"), 1
end



function HandleSaveOffCommand(a_Split, a_Player)
	return SetAutomaticSaving(a_Split, a_Player, false)
end



function HandleSaveOnCommand(a_Split, a_Player)
	return SetAutomaticSaving(a_Split, a_Player, true)
end



function HandleConsoleSaveOff(a_Split)
	return SetAutomaticSaving(a_Split, nil, false)
end



function HandleConsoleSaveOn(a_Split)
	return SetAutomaticSaving(a_Split, nil, true)
end
