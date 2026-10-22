-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess
-- luacheck: globals ResolveTargets MakeSelectorContext GetTargetName
-- luacheck: globals ValidateScoreboardName ValidateScoreboardDisplayName JoinScoreboardDisplayName
-- luacheck: globals ParseScoreboardTeamOption GetScoreboardTeamTargets
-- luacheck: globals ScoreboardTeamOptionNames
local Criterias =
{
	["achievement"] = cObjective.otAchievement,
	["deathCount"] = cObjective.otDeathCount,
	["dummy"] = cObjective.otDummy,
	["health"] = cObjective.otHealth,
	["playerKillCount"] = cObjective.otPlayerKillCount,
	["stat"] = cObjective.otStat,
	["statBlockMine"] = cObjective.otStatBlockMine,
	["statEntityKill"] = cObjective.otStatEntityKill,
	["statEntityKilledBy"] = cObjective.otStatEntityKilledBy,
	["statItemBreak"] = cObjective.otStatItemCraft,
	["statItemUse"] = cObjective.otStatItemUse,
	["totalKillCount"] = cObjective.otTotalKillCount,
}

local Slots =
{
	["list"]      = { Slot = cScoreboard.dsList,    Name = "list" },
	["sidebar"]   = { Slot = cScoreboard.dsSidebar, Name = "sidebar" },
	["belowname"] = { Slot = cScoreboard.dsName,    Name = "belowName" },
}

-- 1.12.2 has 16 extra "sidebar.team.<color>" display slots. cScoreboard has three display slots (list,
-- sidebar and belowName), so those are reported as unsupported instead of as a usage error (spec
-- section 5). The old table also mapped "count" to cScoreboard.dsCount, which is the enum's sentinel, not
-- a slot: it made SetDisplay() index past m_Display (an ASSERT in Debug, an out-of-bounds write in
-- Release). cScoreboard.dsCount must never reach SetDisplay().
local TEAM_SLOT_PREFIX = "sidebar.team."


function HandleScoreboardObjectivesCommand(Split, Player)
	local Response
	local Scoreboard
	local MultiLineResponse = {}

	if Player then
		Scoreboard = Player:GetWorld():GetScoreBoard()
	else
		Scoreboard = cRoot:Get():GetDefaultWorld():GetScoreBoard()
	end

	local SendListObjectives = function(Objective)
		table.insert(MultiLineResponse, SendMessage(Player, Objective:GetDisplayName() .. " -> " .. Objective:GetName() .. ": " .. get_key_for_value(Criterias, Objective:GetType())))
	end

	if not Split[3] then
		Response = SendMessageFailure(Player, "add, remove, list, setdisplay, modify")

	elseif Split[3] == "list" then
		Response = SendMessage(Player, cCompositeChat():AddTextPart("DisplayName -> Name : Type", "2n"))
		Scoreboard:ForEachObjective(SendListObjectives)

	elseif Split[3] == "remove" then
		if not Split[4] then
			Response = SendMessage(Player, "/scoreboard objectives remove <objective>")
		elseif Scoreboard:RemoveObjective(Split[4]) then
			Response = SendMessageSuccess(Player, Split[4] .. " has been removed")
		else
			Response = SendMessageFailure(Player, Split[4] .. " does not exist")
		end

	elseif Split[3] == "add" then
		if not Split[4] or not Criterias[Split[5]:lower()] or not Split[6] then
			Response = SendMessage(Player, "/scoreboard objectives add <name> <criteria> <displayName>")
		else
			local Name = Split[4]
			local Criteria = Criterias[Split[5]:lower()]
			local DisplayName = Split[6]

			Scoreboard:RegisterObjective(Name, DisplayName, Criteria)
			Response = SendMessageSuccess(Player, "Objective " .. DisplayName .. " has been created")
		end

	elseif Split[3] == "setdisplay" then
		local SlotName = Split[4]
		local SlotInfo = (SlotName ~= nil) and Slots[SlotName:lower()] or nil
		if (SlotName == nil) or (Split[5] == nil) then
			Response = SendMessage(Player, "/scoreboard objectives setdisplay <slot> <objective>")
		elseif (SlotInfo == nil) then
			if (SlotName:lower():sub(1, #TEAM_SLOT_PREFIX) == TEAM_SLOT_PREFIX) then
				Response = SendMessageFailure(Player, "The sidebar.team.* display slots are not supported by this server yet")
			else
				Response = SendMessageFailure(Player, 'Unknown display slot "' .. SlotName .. '". Valid slots are: list, sidebar, belowName')
			end
		else
			local Objective = Scoreboard:GetObjective(Split[5])
			if (Objective == nil) then
				Response = SendMessageFailure(Player, 'Unknown objective "' .. Split[5] .. '"')
			else
				Scoreboard:SetDisplay(Objective:GetName(), SlotInfo.Slot)
				Response = SendMessageSuccess(Player, "Objective " .. Objective:GetName() .. " has been placed on " .. SlotInfo.Name)
			end
		end

	elseif Split[3] == "modify" then
		if not Split[4] or Split[5] ~= "displayName" or Split[6] then
			Response = SendMessage(Player, "/scoreboard objectives modify <objective> displayname <newName>")
		else
			local Objective = Scoreboard:GetObjective(Split[4])
			local NewName = Split[6]

			Objective:SetDisplayName(NewName)
			Response = SendMessageSuccess(Player, "Objective " .. Objective:getName() .. " has been renamed to " .. NewName)
		end
	end

	table.insert(MultiLineResponse, 1, Response) -- Add the response of the command as first line
	return true, table.concat(MultiLineResponse, "\n")
end

--- Returns the named objective, or nil after reporting that it does not exist.
-- The players subcommands used to index the result unconditionally, so an unknown objective raised a
-- Lua error ("attempt to index local 'TargetedObjective'") and surfaced as a generic command failure.
local function GetObjectiveOrReport(a_Scoreboard, a_Name, a_Player)
	local Objective = a_Scoreboard:GetObjective(a_Name)
	if not Objective then
		return nil, SendMessageFailure(a_Player, "Unknown objective \"" .. a_Name .. "\"")
	end
	return Objective
end



function HandleScoreboardPlayersCommand(Split, Player)
	local Scoreboard
	local Response
	local TargetedPlayer = Split[4]
	local MultiLineResponse = {}

	if Player then
		Scoreboard = Player:GetWorld():GetScoreBoard()
	else
		Scoreboard = cRoot:Get():GetDefaultWorld():GetScoreBoard()
	end

	local ListPlayerObjective = function(Objective)
		local Score = Objective:GetScore(TargetedPlayer)
		if Score then
			table.insert(MultiLineResponse,SendMessage(GlobalPlayer, Objective:GetDisplayName() .. " -> " .. Score))
		end
	end

	local ResetAllObjectives = function(Objective)
		Objetive:ResetScore(TargetedPlayer)
	end

	if not Split[3] then
		Response = SendMessageFailure(Player, "list, reset, get, set, add, remove, operation")

	elseif Split[3] == "list" then
		if not Split[4] then
			Response = SendMessage(Player, "/scoreboard players list <player>")
		else
			Response = SendMessage(Player, "List of scores for " .. TargetedPlayer .. ": ")
			Scoreboard:ForEachObjective(ListPlayerObjective)
		end

	elseif Split[3] == "reset" then
		if not Split[4] then
			Response = SendMessage(Player, "/scoreboard players reset (<player>)")
		else
			if Split[5] then
				local Objective, ObjectiveError = GetObjectiveOrReport(Scoreboard, Split[5], Player)
				if not Objective then
					return true, ObjectiveError
				end
				Objective:ResetScore(TargetedPlayer)
			else
				Scoreboard:ForEachObjective(ResetAllObjectives)
			end
			Response = SendMessageSuccess(Player, "Player's Score(s) has successfully been reseted")
		end

	elseif Split[3] == "get" then
		if not Split[4] or not Split[5] then
			Response = SendMessage(Player, "/scoreboard players get <player> <objective>")
		else
			local TargetedObjective, ObjectiveError = GetObjectiveOrReport(Scoreboard, Split[5], Player)
			if not TargetedObjective then
				return true, ObjectiveError
			end
			Response = SendMessage(Player, TargetedObjective:GetScore(TargetedPlayer))
		end

	elseif Split[3] == "set" then
		if not Split[4] or not Split[5] or not Split[6] then
			Response = SendMessage(Player, "/scoreboard players set <player> <objective> <ammount>")
		else	
			local TargetedObjective, ObjectiveError = GetObjectiveOrReport(Scoreboard, Split[5], Player)
			if not TargetedObjective then
				return true, ObjectiveError
			end
			TargetedObjective:SetScore(TargetedPlayer, Split[6])
			Response = SendMessageSuccess(Player, "Score " .. Split[6] .. " successfully assigned to " .. TargetedPlayer)
		end

	elseif Split[3] == "add" then
		if not Split[4] or not Split[5] or not Split[6] then
			Response = SendMessage(Player, "/scoreboard players set <player> <objective> <ammount>")
		else	
			local TargetedObjective, ObjectiveError = GetObjectiveOrReport(Scoreboard, Split[5], Player)
			if not TargetedObjective then
				return true, ObjectiveError
			end
			TargetedObjective:AddScore(TargetedPlayer, Split[6])
			Response = SendMessageSuccess(Player, "Score " .. Split[6] .. " successfully increased to " .. TargetedPlayer)
		end

	elseif Split[3] == "remove" then
		if not Split[4] or not Split[5] or not Split[6] then
			Response = SendMessage(Player, "/scoreboard players set <player> <objective> <ammount>")
		else	
			local TargetedObjective, ObjectiveError = GetObjectiveOrReport(Scoreboard, Split[5], Player)
			if not TargetedObjective then
				return true, ObjectiveError
			end
			TargetedObjective:SubScore(TargetedPlayer, Split[6])
			Response = SendMessageSuccess(Player, "Score " .. Split[6] .. " successfully decreased to " .. TargetedPlayer)
		end

	elseif Split[3] == "operation" then
		if not Split[4] or not Split[5] or not Split[6] or not Split[7] or not Split[8] then
			Response = SendMessage(Player, "/scoreboard players operation <targetPlayer> <targetObjective> <operation> <sourcePlayer> <sourceObjective>")
		else
			local TargetedObjective, ObjectiveError = GetObjectiveOrReport(Scoreboard, Split[5], Player)
			if not TargetedObjective then
				return true, ObjectiveError
			end
			local Operator = Split[6]
			local SourcePlayer = Split[7]
			local SourceObjective, SourceError = GetObjectiveOrReport(Scoreboard, Split[8], Player)
			if not SourceObjective then
				return true, SourceError
			end

			if Operator == "+=" then
				TargetedObjective:SetScore(TargetedPlayer, TargetedObjective:GetScore(TargetedPlayer) + SourceObjective:GetScore(SourcePlayer))
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " increased by " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
			elseif Operator == "-=" then
				TargetedObjective:SetScore(TargetedPlayer, TargetedObjective:GetScore(TargetedPlayer) - SourceObjective:GetScore(SourcePlayer))
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " decreased by " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
			elseif Operator == "*=" then
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " multiplied by " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
				TargetedObjective:SetScore(TargetedPlayer, TargetedObjective:GetScore(TargetedPlayer) * SourceObjective:GetScore(SourcePlayer))
			elseif Operator == "/=" then
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " divided by " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
				TargetedObjective:SetScore(TargetedPlayer, TargetedObjective:GetScore(TargetedPlayer) / SourceObjective:GetScore(SourcePlayer))
			elseif Operator == "%=" then
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " moduled by " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
				TargetedObjective:SetScore(TargetedPlayer, TargetedObjective:GetScore(TargetedPlayer) % SourceObjective:GetScore(SourcePlayer))
			elseif Operator == "=" then
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " set to " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
				TargetedObjective:SetScore(TargetedPlayer, SourceObjective:GetScore(SourcePlayer))
			elseif Operator == "<" then
				if SourceObjective:GetScore(SourcePlayer) < TargetedObjective:GetScore(TargetedPlayer) then
					TargetedObjective:SetScore(TargetedPlayer, SourceObjective:GetScore(SourcePlayer))
					Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " set to " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
				end
			elseif Operator == ">" then
				if SourceObjective:GetScore(SourcePlayer) > TargetedObjective:GetScore(TargetedPlayer) then
					TargetedObjective:SetScore(TargetedPlayer, SourceObjective:GetScore(SourcePlayer))
					Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " set to " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName())
				end
			elseif Operator == "><" then
				local temp = SourceObjective:GetScore(SourcePlayer)
				SourceObjective:SetScore(TargetedObjective:GetScore(TargetedPlayer))
				TargetedObjective:SetScore(TargetedPlayer, SourceObjective:GetScore(SourcePlayer))
				Response = SendMessage(Player, TargetedObjective:GetDisplayName() .. ":" .. TargetedPlayer:GetName() .. " and " .. SourceObjective:GetDisplayName() .. ":" .. SourcePlayer:GetName() .. " have been switched")
			else
				Response = SendMessage(Player, "operators: +=, -=, *=, /=, %=, =, <, >, ><")
			end
		end
	end

	table.insert(MultiLineResponse, 1, Response) -- Add the response of the command as first line
	return true, table.concat(MultiLineResponse, "\n")
end

--- Returns the scoreboard and the world a /scoreboard command operates on.
-- Vanilla keeps one scoreboard per server; Cuberite keeps one per world (a pre-existing deviation), so
-- the command uses the sender's world and the console uses the default world.
local function GetScoreboardContext(a_Player)
	if (a_Player ~= nil) then
		local World = a_Player:GetWorld()
		return World:GetScoreBoard(), World
	end
	local World = cRoot:Get():GetDefaultWorld()
	return World:GetScoreBoard(), World
end





--- Returns the team a scoreboard name currently belongs to, or nil.
-- cTeam exposes HasPlayer() but no member enumeration in this engine, so the reverse lookup walks the
-- teams; vanilla keeps a reverse index.
local function FindTeamOfName(a_Scoreboard, a_Name)
	local Found = nil
	a_Scoreboard:ForEachTeam(
		function (a_Team)
			if (a_Team:HasPlayer(a_Name)) then
				Found = a_Team
				return true
			end
			return false
		end
	)
	return Found
end





--- Clears every online player of a_World off a_Team and then empties the roster.
-- cPlayer keeps a raw cTeam pointer. Removing the roster or the team without clearing that pointer would
-- leave it dangling, and cPlayer:GetTeam() would then hand a freed object to Lua. cPlayer:SetTeam(nullptr)
-- clears the pointer and removes the name from the old team in one step; a bare Reset() cannot do that.
local function ClearOnlineTeamMembers(a_World, a_Team)
	local TeamName = a_Team:GetName()
	if (a_World ~= nil) then
		a_World:ForEachPlayer(
			function (a_Player)
				local PlayerTeam = a_Player:GetTeam()
				if ((PlayerTeam ~= nil) and (PlayerTeam:GetName() == TeamName)) then
					a_Player:SetTeam(nil)
				end
				return false
			end
		)
	end
	a_Team:Reset()
end





--- Resolves the target tokens of "teams join" and "teams leave".
-- A selector is resolved through the shared target selector layer against the command's world (teams are
-- kept per world here). A plain name addresses a scoreboard name, which 1.12.2 allows to be offline or to
-- not exist at all. Returns a list of { Name = <scoreboard name>, Player = <cPlayer or nil> }, or nil plus
-- the reason one of the tokens was refused.
local function ResolveTeamTargets(a_World, a_Context, a_Tokens)
	local Targets = {}
	for _, Token in ipairs(a_Tokens) do
		if (Token == "*") then
			-- 1.12.2 expands "*" to every entity the scoreboard tracks; this engine exposes no such list.
			return nil, 'The "*" target needs the scoreboard\'s tracked-entity list, which this server does not expose yet'
		elseif (Token:sub(1, 1) == "@") then
			local Entities, Reason = ResolveTargets(Token, a_Context, "entity")
			if (Entities == nil) then
				return nil, Reason
			end
			for _, Entity in ipairs(Entities) do
				local IsPlayer = Entity:IsPlayer()
				table.insert(Targets, { Name = GetTargetName(Entity), Player = (IsPlayer and Entity or nil) })
			end
		else
			local Online = nil
			cRoot:Get():FindAndDoWithPlayer(
				Token,
				function (a_Player)
					Online = a_Player
				end
			)
			if ((Online ~= nil) and (a_World ~= nil) and (Online:GetWorld():GetName() ~= a_World:GetName())) then
				return nil, 'Player "' .. Token .. '" is in another world; this server keeps teams per world'
			end
			table.insert(Targets, { Name = Token, Player = Online })
		end
	end
	return Targets
end





--- Implements the 1.12.2 /scoreboard teams subcommands.
-- add / remove / empty / join / leave / list / option; the behaviour and its sources are in
-- specs/commands/vanilla-1.12.2-scoreboard-teams.md (parent repository).
function HandleScoreboardTeamsCommand(Split, Player, EntireCommand, Origin)
	local Scoreboard, World = GetScoreboardContext(Player)
	local Response
	local SuccessCount = 0
	local MultiLineResponse = {}
	local Subcommand = Split[3]

	-- The entity a "join" or "leave" without targets applies to: the sender, or the player behind a
	-- command block's origin. The console has neither.
	local Executor = Player
	if (Executor == nil) and (Origin ~= nil) then
		Executor = Origin:GetPlayer()
	end

	if (Subcommand == nil) then
		Response = SendMessageFailure(Player, "add, remove, empty, join, leave, list, option")

	elseif (Subcommand == "add") then
		local Name = Split[4]
		if (Name == nil) then
			Response = SendMessage(Player, "/scoreboard teams add <name> [display name...]")
		else
			local DisplayName = JoinScoreboardDisplayName(Split, 5)
			if (DisplayName == nil) then
				DisplayName = Name
			end
			local NameReason = ValidateScoreboardName(Name)
			local DisplayReason = ValidateScoreboardDisplayName(DisplayName)
			if (NameReason ~= nil) then
				Response = SendMessageFailure(Player, NameReason)
			elseif (DisplayReason ~= nil) then
				Response = SendMessageFailure(Player, DisplayReason)
			elseif (Scoreboard:GetTeam(Name) ~= nil) then
				Response = SendMessageFailure(Player, 'Team "' .. Name .. '" already exists')
			else
				local Team = Scoreboard:RegisterTeam(Name, DisplayName, "", "")
				if (Team == nil) then
					Response = SendMessageFailure(Player, 'Failed to create team "' .. Name .. '"')
				else
					-- 1.12.2 teams see invisible teammates unless that option is turned off (spec section 1.3).
					Team:SetCanSeeFriendlyInvisible(true)
					Response = SendMessageSuccess(Player, 'Team "' .. Name .. '" has been created')
					SuccessCount = 1
				end
			end
		end

	elseif (Subcommand == "remove") then
		local Name = Split[4]
		if (Name == nil) or (Split[5] ~= nil) then
			Response = SendMessage(Player, "/scoreboard teams remove <name>")
		else
			local Team = Scoreboard:GetTeam(Name)
			if (Team == nil) then
				Response = SendMessageFailure(Player, 'Team "' .. Name .. '" does not exist')
			else
				ClearOnlineTeamMembers(World, Team)
				Scoreboard:RemoveTeam(Name)
				Response = SendMessageSuccess(Player, 'Team "' .. Name .. '" has been removed')
				SuccessCount = 1
			end
		end

	elseif (Subcommand == "empty") then
		local Name = Split[4]
		if (Name == nil) or (Split[5] ~= nil) then
			Response = SendMessage(Player, "/scoreboard teams empty <name>")
		else
			local Team = Scoreboard:GetTeam(Name)
			if (Team == nil) then
				Response = SendMessageFailure(Player, 'Team "' .. Name .. '" does not exist')
			elseif (Team:GetNumPlayers() == 0) then
				Response = SendMessageFailure(Player, 'Team "' .. Name .. '" has no members')
			else
				ClearOnlineTeamMembers(World, Team)
				Response = SendMessageSuccess(Player, 'Team "' .. Name .. '" has been emptied')
				SuccessCount = 1
			end
		end

	elseif (Subcommand == "join") then
		local TeamName = Split[4]
		if (TeamName == nil) then
			Response = SendMessage(Player, "/scoreboard teams join <team> [targets...]")
		else
			local Team = Scoreboard:GetTeam(TeamName)
			if (Team == nil) then
				Response = SendMessageFailure(Player, 'Team "' .. TeamName .. '" does not exist')
			else
				local Context = MakeSelectorContext(Player, Origin)
				local Tokens = GetScoreboardTeamTargets(Split, 5)
				local Targets, Reason = ResolveTeamTargets(World, Context, Tokens)
				if (Targets ~= nil) and (#Targets == 0) then
					if (Executor == nil) then
						Targets, Reason = nil, "No entity was specified to join the team"
					else
						Targets = { { Name = Executor:GetName(), Player = Executor } }
					end
				end
				if (Targets == nil) then
					Response = SendMessageFailure(Player, Reason)
				else
					for _, Target in ipairs(Targets) do
						if (Target.Player ~= nil) then
							Target.Player:SetTeam(Team)
						else
							Team:AddPlayer(Target.Name)
						end
					end
					Response = SendMessageSuccess(Player, 'Team "' .. TeamName .. '": added ' .. #Targets .. " member(s)")
					SuccessCount = #Targets
				end
			end
		end

	elseif (Subcommand == "leave") then
		local Context = MakeSelectorContext(Player, Origin)
		local Tokens = GetScoreboardTeamTargets(Split, 4)
		local Targets, Reason = ResolveTeamTargets(World, Context, Tokens)
		if (Targets ~= nil) and (#Targets == 0) then
			if (Executor == nil) then
				Targets, Reason = nil, "No entity was specified to leave its team"
			else
				Targets = { { Name = Executor:GetName(), Player = Executor } }
			end
		end
		if (Targets == nil) then
			Response = SendMessageFailure(Player, Reason)
		else
			local Removed = 0
			local NotOnTeam = nil
			for _, Target in ipairs(Targets) do
				local CurrentTeam = FindTeamOfName(Scoreboard, Target.Name)
				if (CurrentTeam == nil) and (Target.Player ~= nil) then
					CurrentTeam = Target.Player:GetTeam()
				end
				if (CurrentTeam == nil) then
					NotOnTeam = NotOnTeam or Target.Name
				else
					if (Target.Player ~= nil) then
						Target.Player:SetTeam(nil)
					else
						CurrentTeam:RemovePlayer(Target.Name)
					end
					Removed = Removed + 1
				end
			end
			if (Removed == 0) then
				Response = SendMessageFailure(Player, '"' .. tostring(NotOnTeam) .. '" is not on a team')
			else
				local Message = "Removed " .. Removed .. " member(s) from their team(s)"
				if (NotOnTeam ~= nil) then
					-- 1.12.2 allows a partial success for leave (the wiki notes MC-106681).
					Message = Message .. '; "' .. NotOnTeam .. '" is not on a team'
				end
				Response = SendMessageSuccess(Player, Message)
				SuccessCount = Removed
			end
		end

	elseif (Subcommand == "list") then
		local Name = Split[4]
		if (Split[5] ~= nil) then
			Response = SendMessage(Player, "/scoreboard teams list [team]")
		elseif (Name == nil) then
			local Lines = {}
			Scoreboard:ForEachTeam(
				function (a_Team)
					table.insert(Lines, a_Team:GetDisplayName() .. " -> " .. a_Team:GetName() .. ": " ..
						a_Team:GetNumPlayers() .. " member(s)")
					return false
				end
			)
			if (#Lines == 0) then
				Response = SendMessageFailure(Player, "There are no teams on the scoreboard")
			else
				-- The header is sent before the lines so that a player sees it first; SendMessage() delivers
				-- to a player immediately and only returns the text for the console.
				Response = SendMessage(Player, "DisplayName -> Name : Members")
				for _, Line in ipairs(Lines) do
					table.insert(MultiLineResponse, SendMessage(Player, Line))
				end
				SuccessCount = 1
			end
		else
			local Team = Scoreboard:GetTeam(Name)
			if (Team == nil) then
				Response = SendMessageFailure(Player, 'Team "' .. Name .. '" does not exist')
			elseif (Team:GetNumPlayers() == 0) then
				Response = SendMessageFailure(Player, 'Team "' .. Name .. '" has no members')
			else
				-- 1.12.2 also prints the member names; cTeam has no member enumeration here (spec section 5).
				Response = SendMessage(Player, 'Team "' .. Team:GetName() .. '" has ' .. Team:GetNumPlayers() .. " member(s)")
				SuccessCount = 1
			end
		end

	elseif (Subcommand == "option") then
		local TeamName, Key, Value = Split[4], Split[5], Split[6]
		if (TeamName == nil) or (Key == nil) or (Value == nil) or (Split[7] ~= nil) then
			Response = SendMessage(Player, "/scoreboard teams option <team> <option> <value>")
		else
			local Team = Scoreboard:GetTeam(TeamName)
			if (Team == nil) then
				Response = SendMessageFailure(Player, 'Team "' .. TeamName .. '" does not exist')
			else
				local Option, Reason = ParseScoreboardTeamOption(Key, Value)
				if (Option == nil) then
					Response = SendMessageFailure(Player, Reason)
				else
					if (Option.Key == "friendlyfire") then
						Team:SetFriendlyFire(Option.Value)
					elseif (Option.Key == "seeFriendlyInvisibles") then
						Team:SetCanSeeFriendlyInvisible(Option.Value)
					elseif (Option.Key == "color") then
						-- "reset" clears the color; cTeam stores the vanilla color name ("" = no color):
						Team:SetColor((Option.Value == "reset") and "" or Option.Value)
					elseif (Option.Key == "nametagVisibility") then
						Team:SetNameTagVisibility(Option.Value)
					elseif (Option.Key == "collisionRule") then
						Team:SetCollisionRule(Option.Value)
					end
					Response = SendMessageSuccess(Player, 'Team "' .. TeamName .. '": ' .. Key .. " is now " .. tostring(Option.Value))
					SuccessCount = 1
				end
			end
		end

	else
		Response = SendMessageFailure(Player, "add, remove, empty, join, leave, list, option")
	end

	table.insert(MultiLineResponse, 1, Response) -- Add the response of the command as first line
	return true, table.concat(MultiLineResponse, "\n"), SuccessCount
end





-- Handle commands for console

function HandleConsoleScoreboardObjectives(Split)
	return HandleScoreboardObjectivesCommand(Split)
end

function HandleConsoleScoreboardPlayers(Split)
	return HandleScoreboardPlayersCommand(Split)
end

function HandleConsoleScoreboardTeams(Split, _, EntireCommand, Origin)
	return HandleScoreboardTeamsCommand(Split, nil, EntireCommand, Origin)
end
