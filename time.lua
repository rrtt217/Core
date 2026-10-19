-- Implements time related commands and console commands


local PlayerTimeAddCommandUsage = "Usage: /time add <value> [world]"
local PlayerTimeSetCommandUsage = "Usage: /time set <day|night|value> [world]"
local ConsoleSetTimeCommandUsage = "Usage: time set <day|night|value> [world]"
local ConsoleAddTimeCommandUsage = "Usage: time add <value> [world]"

-- Times of day and night as defined in vanilla minecraft
local SpecialTimesTable = {
	["day"] = 1000,
	["night"] = 1000 + 12000,
}

local TimeAnimationInProgress = false

-- Used to animate the transition between previous and new times
local function SetTime( World, TimeToSet )

	local CurrentTime = World:GetTimeOfDay()
	local MaxTime = 24000

	-- Handle the cases where TimeToSet < 0 or > 24000
	TimeToSet = TimeToSet % MaxTime

	local AnimationSpeed = 480
	if CurrentTime > TimeToSet then
		AnimationSpeed = -AnimationSpeed
	end

	local function DoAnimation()
		if not TimeAnimationInProgress then
			return
		end
		local TimeOfDay = World:GetTimeOfDay()
		local AnimatedTime = TimeOfDay + AnimationSpeed
		local Animate = (
			((AnimationSpeed > 0) and (AnimatedTime < TimeToSet))
			or ((AnimationSpeed < 0) and (AnimatedTime > TimeToSet))
		)
		if Animate then
			World:SetTimeOfDay(AnimatedTime)
			World:ScheduleTask(1, DoAnimation)
		else
			World:SetTimeOfDay(TimeToSet)
			TimeAnimationInProgress = false
		end
	end


	if TimeAnimationInProgress then
		TimeAnimationInProgress = false
		World:SetTimeOfDay(TimeToSet)
	else
		TimeAnimationInProgress = true
		World:ScheduleTask(1, DoAnimation)
	end
	World:BroadcastChatSuccess("Time was set to " .. TimeToSet)
	LOG("Time in world \"" .. World:GetName() .. "\" was set to " .. TimeToSet) -- Let the console know about time changes

	return true
end


-- Code common to console and in-game `time add` command
local function CommonAddTime( World, Time )

	-- Stop if an invalid world was given
	if not World then
		return true
	end

	local TimeToAdd = tonumber( Time )

	if not TimeToAdd then
		return false
	end

	local TimeToSet = World:GetTimeOfDay() + TimeToAdd
	SetTime( World, TimeToSet )
	
	return true
end



--- Resolves the optional [world] argument of a /time subcommand.
-- Reports an unknown world itself (in-game: chat, console: log) and returns nil, true so the caller
-- knows the failure has already been explained (it used to return silently).
-- Returns World, false when the world resolved (or when no world was given).
local function GetTimeWorld(Split, a_Index, Player)
	local WorldName = Split[a_Index]
	if (WorldName == nil) or (WorldName == "") then
		return GetWorld(nil, Player), false
	end

	local World = GetWorld(WorldName, Player)
	if (World == nil) then
		local Message = "There is no world \"" .. WorldName .. "\""
		if Player then
			SendMessage(Player, Message)
		else
			LOG(Message)
		end
		return nil, true
	end
	return World, false
end



-- Handler for "/time add <amount> [world]" subcommand 
function HandleAddTimeCommand( Split, Player )

	local World, Reported = GetTimeWorld( Split, 4, Player )
	if Reported then
		return true
	end

	if not CommonAddTime( World, Split[3] ) then
		SendMessage( Player, PlayerTimeAddCommandUsage )
	end

	return true
end


-- Handler for console command: time add <value> [WorldName]
function HandleConsoleAddTime(a_Split)

	local World, Reported = GetTimeWorld( a_Split, 4, nil )
	if Reported then
		return true
	end

	if not CommonAddTime( World, a_Split[3] ) then
		LOG(ConsoleAddTimeCommandUsage)
	end

	return true
end


-- Code common to console and in-game `time set` command
local function CommonSetTime( World, Time )

	-- Stop if an invalid world was given
	if not World then
		return true
	end

	-- Handle the vanilla cases of /time set <day|night>, for compatibility
	local TimeToSet = SpecialTimesTable[Time] or tonumber(Time)
	
	if not TimeToSet then
		return false
	else
		SetTime( World, TimeToSet )
	end

	return true
end


-- Handler for "/time set <value> [world]" subcommand 
function HandleSetTimeCommand( Split, Player )

	local World, Reported = GetTimeWorld( Split, 4, Player )
	if Reported then
		return true
	end

	if not CommonSetTime( World, Split[3] ) then
		SendMessage( Player, PlayerTimeSetCommandUsage )
	end

	return true

end


-- Handler for console command: time set <day|night|value> [world]
function HandleConsoleSetTime(a_Split)

	local World, Reported = GetTimeWorld( a_Split, 4, nil )
	if Reported then
		return true
	end

	if not CommonSetTime( World, a_Split[3] ) then
		LOG(ConsoleSetTimeCommandUsage)
	end
	
	return true
end


-- Code common to console and in-game time <day|night> commands
local function CommonSpecialTime( World, TimeName )

	-- Stop if an invalid world was given
	if not World then
		return true
	end
	
	SetTime( World, SpecialTimesTable[TimeName] )

	return true
end


-- Handler for /time <day|night> [world]
function HandleSpecialTimeCommand( Split, Player )

	local World, Reported = GetTimeWorld( Split, 3, Player )
	if Reported then
		return true
	end

	return CommonSpecialTime( World, Split[2] )

end


-- Handler for console command: time <day|night> [world]
function HandleConsoleSpecialTime(a_Split)

	local World, Reported = GetTimeWorld( a_Split, 3, nil )
	if Reported then
		return true
	end

	return CommonSpecialTime( World, a_Split[2] )

end


-- Handler for /time query daytime [world]
function HandleQueryDaytimeCommand( Split, Player )

	local World, Reported = GetTimeWorld( Split, 4, Player )
	if Reported then
		return true
	end

	SendMessage( Player, "The current time in World \"" .. World:GetName() .. "\" is " .. World:GetTimeOfDay() )

	return true
end


-- Handler for console command: time query daytime [world]
function HandleConsoleQueryDaytime(a_Split)

	local World, Reported = GetTimeWorld( a_Split, 4, nil )
	if Reported then
		return true
	end

	LOG( "The current time in World \"" .. World:GetName() .. "\" is " .. World:GetTimeOfDay() )

	return true
end


-- Handler for /time query gametime [world]
function HandleQueryGametimeCommand( Split, Player )

	local World, Reported = GetTimeWorld( Split, 4, Player )
	if Reported then
		return true
	end

	SendMessage( Player, "The World \"" .. World:GetName() .. "\" has existed for " .. World:GetWorldAge() )

	return true
end


-- Handler for console command: time query gametime [world]
function HandleConsoleQueryGametime(a_Split)

	local World, Reported = GetTimeWorld( a_Split, 4, nil )
	if Reported then
		return true
	end

	LOG( "The World \"" .. World:GetName() .. "\" has existed for " .. World:GetWorldAge() )

	return true
end
