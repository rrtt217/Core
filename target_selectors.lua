-- target_selectors.lua
-- Implements the shared command target selector layer for Core, following
-- vanilla Minecraft Java Edition 1.12.2 semantics (the pre-1.13 selector syntax).
--
-- Clean-room sources (see specs/vanilla-1.12.2-command-target-selectors.md in the
-- parent repository for the full list):
--   * "Commands", 1.12.2-era revision (rev 1152284, 2017-09-29):
--     https://minecraft.wiki/w/Commands?oldid=1152284
--   * "Java Edition 17w45a", the 1.13 command rework changelog, used to tell the
--     1.12.2 syntax apart from the 1.13+ syntax:
--     https://minecraft.wiki/w/Java_Edition_17w45a
--
-- ParseSelector() is a pure function of its input string so that the parser can be
-- exercised with a stock Lua interpreter (see tests/test_selectors.lua); only
-- ResolveSelector() touches game objects.

-- The six exported globals do not all fit on one `new globals` directive line, so
-- they are declared read-only and this file is allowed to define them.
-- 111 == "setting non-standard global variable".
-- luacheck: globals ParseSelector ResolveSelector ResolveSelectorToken ResolveTargets
-- luacheck: globals GetTargetName ApplyToTargets MakeSelectorContext GetOriginPosition
-- luacheck: globals cRoot cMonster cBoundingBox Vector3d
-- luacheck: ignore 111

-- The five 1.12.2 selector variables. "@n" did not exist before 1.21 (24w21a),
-- so it is rejected here rather than silently supported.
local SELECTOR_VARIABLES =
{
	p = true,
	r = true,
	a = true,
	e = true,
	s = true,
}

-- Arguments implemented by this branch. 1.12.2 accepted integers only for all of
-- these (17w45a turned the coordinate and rotation arguments into doubles).
local SELECTOR_INTEGER_ARGUMENTS =
{
	c = true,
	r = true,
	rm = true,
	x = true,
	y = true,
	z = true,
	dx = true,
	dy = true,
	dz = true,
	l = true,
	lm = true,
}

-- Arguments whose value is free text.
local SELECTOR_STRING_ARGUMENTS =
{
	type = true,
	name = true,
	m = true,
	team = true,
}

-- Valid 1.12.2 arguments that this branch deliberately does not implement yet.
-- They are recognised so that resolution can fail with a precise reason instead
-- of silently ignoring them (spec section 3.4).
local SELECTOR_UNSUPPORTED_ARGUMENTS =
{
	tag = "scoreboard tags",
	rx = "view angle (pitch)",
	rxm = "view angle (pitch)",
	ry = "view angle (yaw)",
	rym = "view angle (yaw)",
}

-- Only these arguments accept the "!" negation prefix in 1.12.2.
local SELECTOR_NEGATABLE_ARGUMENTS =
{
	type = true,
	name = true,
	m = true,
	team = true,
	tag = true,
}

-- Dynamic 1.12.2 score arguments, e.g. score_points=39 / score_points_min=30.
local SELECTOR_SCORE_ARGUMENT_PATTERN = "^score_[%w_]+$"

-- The 1.12.2 gamemode argument values (the "m=" argument).
local SELECTOR_GAME_MODES =
{
	["0"] = "survival",
	["s"] = "survival",
	["survival"] = "survival",
	["1"] = "creative",
	["c"] = "creative",
	["creative"] = "creative",
	["2"] = "adventure",
	["a"] = "adventure",
	["adventure"] = "adventure",
	["3"] = "spectator",
	["sp"] = "spectator",
	["spectator"] = "spectator",
}





-- Parses a selector token such as "@a", "@e[type=cow,c=3]" or "@s[name=Notch]".
-- Returns the selector structure on success, or nil plus a reason on failure.
-- The structure is:
--   {
--     Variable = "a",
--     Arguments = { { Key = "c", Negated = false, Value = "3", Number = 3 }, ... },
--     Lookup = { c = <the same argument>, ... },
--     Raw = "@a[c=3]",
--   }
-- "Unsupported" is set on arguments that are valid 1.12.2 syntax but not
-- implemented by this branch.
function ParseSelector(a_Token)
	if (type(a_Token) ~= "string") then
		return nil, "Selector must be a string"
	end

	local Variable = a_Token:match("^@([a-z])")
	if (Variable == nil) then
		return nil, "Invalid selector \"" .. a_Token .. "\""
	end
	if (SELECTOR_VARIABLES[Variable] == nil) then
		return nil, "Unknown selector variable \"@" .. Variable .. "\""
	end

	local Selector =
	{
		Variable = Variable,
		Arguments = {},
		Lookup = {},
		Raw = a_Token,
	}

	local Tail = a_Token:sub(3)
	if (Tail == "") then
		return Selector
	end

	local Inner = Tail:match("^%[(.*)%]$")
	if (Inner == nil) then
		return nil, "Invalid selector \"" .. a_Token .. "\""
	end

	-- 1.12.2 forbids spaces anywhere inside the brackets and has no quoting at
	-- all (both arrived with 17w45a), so a plain comma split is the whole grammar.
	if (Inner:find("%s") ~= nil) then
		return nil, "Spaces are not allowed in a selector"
	end

	for Part in (Inner .. ","):gmatch("([^,]*),") do
		local Key, Value = Part:match("^([^=]+)=(.*)$")
		if (Key == nil) then
			return nil, "Invalid selector argument \"" .. Part .. "\""
		end
		if (Key:find("^[%a_][%w_]*$") == nil) then
			return nil, "Invalid selector argument name \"" .. Key .. "\""
		end

		local Negated = false
		if (Value:sub(1, 1) == "!") then
			if (not SELECTOR_NEGATABLE_ARGUMENTS[Key]) then
				return nil, "Selector argument \"" .. Key .. "\" cannot be negated"
			end
			Negated = true
			Value = Value:sub(2)
		end

		local Argument =
		{
			Key = Key,
			Negated = Negated,
			Value = Value,
		}

		if (SELECTOR_INTEGER_ARGUMENTS[Key]) then
			if (Value:match("^%-?%d+$") == nil) then
				return nil, "Selector argument \"" .. Key .. "\" expects an integer"
			end
			Argument.Number = tonumber(Value)
		elseif (SELECTOR_STRING_ARGUMENTS[Key]) then
			-- "team=" without a value is meaningful (it matches entities on no
			-- team); every other text argument needs a non-empty value.
			if ((Value == "") and (Key ~= "team")) then
				return nil, "Selector argument \"" .. Key .. "\" expects a value"
			end
		elseif (SELECTOR_UNSUPPORTED_ARGUMENTS[Key] ~= nil) then
			Argument.Unsupported = SELECTOR_UNSUPPORTED_ARGUMENTS[Key]
		elseif (Key:match(SELECTOR_SCORE_ARGUMENT_PATTERN) ~= nil) then
			Argument.Unsupported = "scoreboard objectives"
		else
			return nil, "Unknown selector argument \"" .. Key .. "\""
		end

		if (Selector.Lookup[Key] ~= nil) then
			-- 1.12.2 did not allow repeating an argument (17w45a made it possible).
			return nil, "Duplicate selector argument \"" .. Key .. "\""
		end
		Selector.Lookup[Key] = Argument
		table.insert(Selector.Arguments, Argument)
	end

	return Selector
end





-- Builds the selection origin (world plus position) from the "x"/"y"/"z"
-- arguments, falling back to the execution context. Returns the world and a
-- plain {x, y, z} table.
--
-- 1.12.2 semantics: "x" and "z" were centre-corrected, so "x=0" meant "x=0.5";
-- "y" was not (see the 17w45a changelog: "x and z are no longer center-corrected").
local function GetSelectorOrigin(a_Selector, a_Context)
	local OriginWorld = nil
	local BasePosition = nil
	if (a_Context ~= nil) then
		OriginWorld = a_Context.World
		BasePosition = a_Context.Position
	end

	if (OriginWorld == nil) then
		OriginWorld = cRoot:Get():GetDefaultWorld()
	end

	local X, Y, Z
	if (BasePosition ~= nil) then
		X, Y, Z = BasePosition.x, BasePosition.y, BasePosition.z
	else
		-- No execution position (console / RCON): the world spawn is used. This is
		-- an approximation until the command origin lands with C2 [推测].
		X, Y, Z = OriginWorld:GetSpawnX(), OriginWorld:GetSpawnY(), OriginWorld:GetSpawnZ()
	end

	local Lookup = a_Selector.Lookup
	if (Lookup.x ~= nil) then
		X = Lookup.x.Number + 0.5
	end
	if (Lookup.y ~= nil) then
		Y = Lookup.y.Number
	end
	if (Lookup.z ~= nil) then
		Z = Lookup.z.Number + 0.5
	end

	return OriginWorld, { x = X, y = Y, z = Z }
end





-- Returns the squared distance between an entity and the origin, or nil when the
-- entity lives in another world.
local function GetSquaredDistance(a_Entity, a_OriginWorld, a_Origin)
	if (a_Entity:GetWorld() ~= a_OriginWorld) then
		return nil
	end
	local Position = a_Entity:GetPosition()
	local dx = Position.x - a_Origin.x
	local dy = Position.y - a_Origin.y
	local dz = Position.z - a_Origin.z
	return (dx * dx) + (dy * dy) + (dz * dz)
end





-- Builds the cBoundingBox described by "dx"/"dy"/"dz" around the origin, or nil
-- when none of them is present. Unspecified deltas default to 0.
local function GetSelectorBox(a_Selector, a_Origin)
	local Lookup = a_Selector.Lookup
	if ((Lookup.dx == nil) and (Lookup.dy == nil) and (Lookup.dz == nil)) then
		return nil
	end

	local DX = 0
	local DY = 0
	local DZ = 0
	if (Lookup.dx ~= nil) then
		DX = Lookup.dx.Number
	end
	if (Lookup.dy ~= nil) then
		DY = Lookup.dy.Number
	end
	if (Lookup.dz ~= nil) then
		DZ = Lookup.dz.Number
	end

	local X1, X2 = a_Origin.x, a_Origin.x + DX
	local Y1, Y2 = a_Origin.y, a_Origin.y + DY
	local Z1, Z2 = a_Origin.z, a_Origin.z + DZ
	return cBoundingBox(
		Vector3d(math.min(X1, X2), math.min(Y1, Y2), math.min(Z1, Z2)),
		Vector3d(math.max(X1, X2), math.max(Y1, Y2), math.max(Z1, Z2))
	)
end





local function MatchesTypeArgument(a_Entity, a_Argument)
	local Matches
	if (a_Argument.Value == "player") then
		Matches = a_Entity:IsPlayer()
	elseif (a_Entity:IsMob()) then
		-- Entity IDs are compared case-insensitively and without the underscore
		-- separator, so both "Creeper" and "cave_spider" resolve. Whether 1.12.2
		-- itself was case-sensitive is contradictory in the sources [待核].
		-- NOTE: StringToMobType is a C++ static, but tolua++ binds it with
		-- tolua_isusertable(tolua_S, 1, "cMonster"), so it must be called with
		-- colon syntax (the class table becomes argument #1). Calling it with a
		-- dot raises "argument #1 is 'string'; 'cMonster' expected".
		local Normalized = (a_Argument.Value:lower():gsub("_", ""))
		Matches = (a_Entity:GetMobType() == cMonster:StringToMobType(Normalized))
	else
		Matches = false
	end
	return (a_Argument.Negated and not Matches) or ((not a_Argument.Negated) and Matches)
end





local function MatchesNameArgument(a_Entity, a_Argument)
	local Name
	if (a_Entity:IsPlayer()) then
		Name = a_Entity:GetName()
	else
		Name = a_Entity:GetCustomName()
	end
	-- 1.12.2 matched the name exactly. Case sensitivity is [推测，置信度中].
	local Matches = (Name == a_Argument.Value)
	return (a_Argument.Negated and not Matches) or ((not a_Argument.Negated) and Matches)
end





local function MatchesLevelArgument(a_Entity, a_Argument, a_IsMinimum)
	if (not a_Entity:IsPlayer()) then
		return false
	end
	local Level = a_Entity:GetXpLevel()
	if (a_IsMinimum) then
		return Level >= a_Argument.Number
	end
	return Level <= a_Argument.Number
end





local function MatchesGameModeArgument(a_Entity, a_Argument)
	if (not a_Entity:IsPlayer()) then
		return false
	end

	local GameMode = SELECTOR_GAME_MODES[a_Argument.Value:lower()]
	if (GameMode == nil) then
		-- The parser accepted the value; report the unknown gamemode as no match.
		-- (Whether 1.12.2 also accepted "-1" is unresolved [待核].)
		return false
	end

	local Matches
	if (GameMode == "survival") then
		Matches = a_Entity:IsGameModeSurvival()
	elseif (GameMode == "creative") then
		Matches = a_Entity:IsGameModeCreative()
	elseif (GameMode == "adventure") then
		Matches = a_Entity:IsGameModeAdventure()
	else
		Matches = a_Entity:IsGameModeSpectator()
	end
	return (a_Argument.Negated and not Matches) or ((not a_Argument.Negated) and Matches)
end





local function MatchesTeamArgument(a_Entity, a_Argument)
	local TeamName = nil
	if (a_Entity:IsPlayer()) then
		local Team = a_Entity:GetTeam()
		if (Team ~= nil) then
			TeamName = Team:GetName()
		end
	end

	-- "team=" matches "on no team", "team=!" matches "on any team", and
	-- "team=T" / "team=!T" match the named team.
	local OnTeam
	if (a_Argument.Value == "") then
		OnTeam = (TeamName == nil)
	else
		OnTeam = (TeamName == a_Argument.Value)
	end
	return (a_Argument.Negated and not OnTeam) or ((not a_Argument.Negated) and OnTeam)
end





local function MatchesSelectorArgument(a_Entity, a_Argument, a_OriginWorld, a_Box, a_Distance)
	local Key = a_Argument.Key
	if (Key == "type") then
		return MatchesTypeArgument(a_Entity, a_Argument)
	elseif (Key == "name") then
		return MatchesNameArgument(a_Entity, a_Argument)
	elseif (Key == "m") then
		return MatchesGameModeArgument(a_Entity, a_Argument)
	elseif (Key == "team") then
		return MatchesTeamArgument(a_Entity, a_Argument)
	elseif (Key == "l") then
		return MatchesLevelArgument(a_Entity, a_Argument, false)
	elseif (Key == "lm") then
		return MatchesLevelArgument(a_Entity, a_Argument, true)
	elseif ((Key == "r") or (Key == "rm")) then
		if (a_Argument.Number < 0) then
			-- A negative radius means "same dimension, any distance" in 1.12.2, in both arguments
			-- (maintainer's live 1.12.2 observation, 2026-10-13; the wiki documents the r= wording and
			-- the live run shows rm= behaves the same). The dimension half is what the whole argument
			-- boils down to here, because SelectorNeedsOrigin() already keeps candidates inside the
			-- origin world for both keys:
			return (a_Entity:GetWorld() == a_OriginWorld)
		end
		-- Bound inclusivity is [待核]; inclusive is used here.
		if (Key == "r") then
			return (a_Distance ~= nil) and (a_Distance <= (a_Argument.Number * a_Argument.Number))
		end
		return (a_Distance ~= nil) and (a_Distance >= (a_Argument.Number * a_Argument.Number))
	elseif ((Key == "dx") or (Key == "dy") or (Key == "dz")) then
		if (a_Box == nil) then
			return true
		end
		-- The box lives in the origin world; an entity of another world must not
		-- match just because its coordinates coincide.
		return (a_Entity:GetWorld() == a_OriginWorld)
			and a_Entity:GetBoundingBox():DoesIntersect(a_Box)
	end

	-- x/y/z only move the origin; c= is applied when the result is ordered.
	return true
end





local function MatchesSelector(a_Entity, a_Selector, a_OriginWorld, a_Box, a_Distance)
	for _, Argument in ipairs(a_Selector.Arguments) do
		if (not MatchesSelectorArgument(a_Entity, Argument, a_OriginWorld, a_Box, a_Distance)) then
			return false
		end
	end
	return true
end





-- Calls the callback for every loaded entity of every loaded world.
--- Names of every world except the origin one, collected without touching any world's lock:
-- cRoot::ForEachWorld only walks the world map and GetName() is a plain accessor, so a command that
-- may span dimensions can learn the other worlds without risking the cross-world lock order
-- (spec section 7.2).
local function GetDeferredWorldNames(a_OriginWorld)
	local Names = {}
	if (a_OriginWorld == nil) then
		return Names
	end
	local OriginName = a_OriginWorld:GetName()
	cRoot:Get():ForEachWorld(
		function (a_World)
			if (a_World:GetName() ~= OriginName) then
				table.insert(Names, a_World:GetName())
			end
			return false
		end
	)
	return Names
end





-- Collects the candidate entities for a selector, before any filtering.
-- "@s" is the executing entity (an empty set when there is none), "@a" is every
-- player, "@e" is every loaded pawn, and "@p"/"@r" start from the players but
-- switch to the pawn set when a "type" argument is given (1.12.2 behaviour).
-- Returns whether the selector uses any argument whose meaning depends on the
-- execution position. Distance is only well defined inside a single world, so
-- such selectors must be evaluated in the origin world only: comparing
-- coordinates across worlds is meaningless (and "@p" is "nearest" by definition).
local function SelectorNeedsOrigin(a_Selector)
	local Lookup = a_Selector.Lookup
	return (Lookup.x ~= nil) or (Lookup.y ~= nil) or (Lookup.z ~= nil)
		or (Lookup.dx ~= nil) or (Lookup.dy ~= nil) or (Lookup.dz ~= nil)
		or (Lookup.r ~= nil) or (Lookup.rm ~= nil)
		or (Lookup.c ~= nil)
		or (a_Selector.Variable == "p")
end





-- Calls the callback for every loaded pawn of a single world. Players live in the
-- chunk map as well (cWorld::AddEntity puts them in both), so this covers them.
local function ForEachWorldPawn(a_World, a_Callback)
	a_World:ForEachEntity(
		function (a_Entity)
			if (a_Entity:IsPawn()) then
				a_Callback(a_Entity)
			end
			return false
		end
	)
end





-- Collects the candidate entities for a selector, before any filtering.
--
-- a_NeedsOrigin selects the candidate set:
--   * true  -> only a_OriginWorld (position/distance-dependent selectors);
--   * false -> every loaded world (the global "@a"/"@e"/"@r" set).
-- "@s" is the executing entity (an empty set when there is none), "@a" is every
-- player, "@e" is every loaded pawn, and "@p"/"@r" start from the players but
-- switch to the pawn set when a "type" argument is given (1.12.2 behaviour).
local function CollectSelectorCandidates(a_Selector, a_Executor, a_OriginWorld)
	local Candidates = {}
	local Variable = a_Selector.Variable

	if (Variable == "s") then
		if (a_Executor ~= nil) then
			table.insert(Candidates, a_Executor)
		end
		return Candidates
	end

	if (a_OriginWorld == nil) then
		-- GetSelectorOrigin() always yields a world (the default world as a last resort), so this is
		-- only reachable for callers that pass no context at all:
		return Candidates
	end

	local UseEntities = (a_Selector.Lookup.type ~= nil)
	local WantPawns = (Variable == "e")
		or (UseEntities and ((Variable == "p") or (Variable == "r")))

	-- Candidates are restricted to the origin world. Vanilla's bare "@e"/"@a" do span
	-- dimensions (spec section 2.1c), but the other worlds are queued by ApplyToTargets() and resolved
	-- on their own threads, so no other world's lock is ever taken from here (spec section 7.2).
	-- (Vanilla also selects items, minecarts and the like with "@e"; that is a known deviation until a
	-- verified 1.12.2 entity-ID mapping exists.)
	if (WantPawns) then
		ForEachWorldPawn(a_OriginWorld, function (a_Entity) table.insert(Candidates, a_Entity) end)
	else
		a_OriginWorld:ForEachPlayer(function (a_Player) table.insert(Candidates, a_Player) end)
	end
	return Candidates
end





-- Applies the "c=" count, the distance ordering and (for "@r") the random pick.
local function ApplySelectorCountAndOrder(a_Selector, a_Matches, a_OriginWorld, a_Origin)
	local Variable = a_Selector.Variable

	local Count = nil
	local Reversed = false
	if (a_Selector.Lookup.c ~= nil) then
		Count = a_Selector.Lookup.c.Number
		if (Count < 0) then
			-- A negative count reverses the distance order in 1.12.2.
			Reversed = true
			Count = -Count
		end
	end

	if (Variable == "s") then
		return a_Matches
	end

	if (Variable == "r") then
		if (Count == nil) then
			Count = 1
		end
		local Result = {}
		local Pool = {}
		for Index, Entity in ipairs(a_Matches) do
			Pool[Index] = Entity
		end
		for _ = 1, Count do
			if (#Pool == 0) then
				break
			end
			local Pick = math.random(#Pool)
			table.insert(Result, Pool[Pick])
			table.remove(Pool, Pick)
		end
		return Result
	end

	-- Ordered selection is only ever reached with a position-dependent selector,
	-- so the candidates are already restricted to the origin world and every one
	-- of them has a well-defined distance.
	if (Variable ~= "p") and (Count == nil) then
		-- "@a"/"@e" without "c=": the global set, in iteration order.
		return a_Matches
	end

	-- "@p", "@a" and "@e" are ordered by distance, nearest first; ties are left
	-- unspecified [待核].
	local Ordered = {}
	for _, Entity in ipairs(a_Matches) do
		local Distance = GetSquaredDistance(Entity, a_OriginWorld, a_Origin)
		if (Distance ~= nil) then
			table.insert(Ordered, { Entity = Entity, Distance = Distance })
		end
	end

	table.sort(Ordered, function (a_Left, a_Right) return a_Left.Distance < a_Right.Distance end)

	if (Reversed) then
		local Flipped = {}
		for Index = #Ordered, 1, -1 do
			table.insert(Flipped, Ordered[Index])
		end
		Ordered = Flipped
	end

	if ((Variable == "p") and (Count == nil)) then
		Count = 1
	end

	local Result = {}
	for _, Entry in ipairs(Ordered) do
		if ((Count ~= nil) and (#Result >= Count)) then
			break
		end
		table.insert(Result, Entry.Entity)
	end
	return Result
end





-- Resolves a parsed selector to a list of entities. Returns the (possibly empty)
-- list on success, or nil plus a reason when the selector cannot be resolved.
--
-- The context is optional and reserved for the C2 command-execution context:
--   { World = <cWorld>, Position = <Vector3d>, Executor = <cEntity> }
-- When it is nil, "@s" resolves to nothing and the origin falls back to the
-- default world's spawn point.
function ResolveSelector(a_Selector, a_Context)
	if (type(a_Selector) ~= "table") or (a_Selector.Variable == nil) then
		return nil, "Invalid selector"
	end

	for _, Argument in ipairs(a_Selector.Arguments) do
		if (Argument.Unsupported ~= nil) then
			return nil, "Selector argument \"" .. Argument.Key .. "\" (" .. Argument.Unsupported .. ") is not supported yet"
		end
	end

	local Executor = nil
	if (a_Context ~= nil) then
		Executor = a_Context.Executor
	end

	local OriginWorld, Origin = GetSelectorOrigin(a_Selector, a_Context)
	local Box = GetSelectorBox(a_Selector, Origin)

	local Matches = {}
	for _, Entity in ipairs(CollectSelectorCandidates(a_Selector, Executor, OriginWorld)) do
		local Distance = GetSquaredDistance(Entity, OriginWorld, Origin)
		if (MatchesSelector(Entity, a_Selector, OriginWorld, Box, Distance)) then
			table.insert(Matches, Entity)
		end
	end

	return ApplySelectorCountAndOrder(a_Selector, Matches, OriginWorld, Origin)
end





-- Parses and resolves a selector token in one call.
function ResolveSelectorToken(a_Token, a_Context)
	local Selector, Reason = ParseSelector(a_Token)
	if (Selector == nil) then
		return nil, Reason
	end
	return ResolveSelector(Selector, a_Context)
end





-- Builds a selector context from the player running a command, so that "@s" and
-- the distance-based selectors use the player's world and position. Returns nil
-- for the console (and for command blocks until C2 supplies an origin).
--- Builds the context a target selector is resolved against.
-- The world and the position come from the command origin (cCommandOrigin), so a command block or
-- the console resolves its selectors against its own position instead of the default world's spawn.
-- a_Player is only used as a fallback for callers that have no origin, and as the executor.
function MakeSelectorContext(a_Player, a_Origin)
	local World = nil
	local Position = nil

	if (a_Origin ~= nil) then
		World = a_Origin:GetWorld()
		Position = GetOriginPosition(a_Origin)
	end

	if (a_Player ~= nil) then
		if (World == nil) then
			World = a_Player:GetWorld()
		end
		if (Position == nil) then
			Position = a_Player:GetPosition()
		end
	end

	local Executor = a_Player
	if (Executor == nil) and (a_Origin ~= nil) then
		Executor = a_Origin:GetPlayer()
	end

	return
	{
		World = World,
		Position = Position,
		Executor = Executor,
		Origin = a_Origin,
	}
end





-- Returns whether an entity satisfies the target kind requested by a command.
-- "entity" currently behaves like "pawn", because the selector layer only yields
-- pawns (see the "@e" known deviation in the spec).
local function MatchesTargetKind(a_Entity, a_Kind)
	if ((a_Kind == nil) or (a_Kind == "pawn") or (a_Kind == "entity")) then
		return a_Entity:IsPawn()
	end
	if (a_Kind == "player") then
		return a_Entity:IsPlayer()
	end
	return false
end





-- Resolves a command's target argument: a target selector ("@..."), or an online
-- player name. a_Kind narrows the accepted entities to "player", "pawn" (players
-- and monsters, the default) or "entity".
--
-- Returns the list of targets (never empty) on success, or nil plus a failure
-- reason. Vanilla 1.12.2 uses the same "player name or target selector" argument
-- for the commands this serves.
--- Builds the descriptor for the worlds that a cross-dimension selector still has to visit.
-- Returns nil when the selector is dimension-bound (positional / distance / "@p"), when the command has
-- an executor (a queued action must not carry an executor reference across ticks, spec section 7.3), or
-- when the origin is the only world.
local function GetSelectorDeferral(a_Token, a_Context)
	if (a_Context == nil) or (a_Context.LocalOnly) then
		return nil
	end
	if (type(a_Token) ~= "string") or (a_Token:sub(1, 1) ~= "@") then
		return nil
	end
	local Selector = ParseSelector(a_Token)
	if (Selector == nil) or SelectorNeedsOrigin(Selector) then
		return nil
	end
	if (Selector.Variable == "s") then
		-- "@s" is the executing entity itself, which always lives in the origin world:
		return nil
	end
	local OriginWorld = a_Context.World
	if (OriginWorld == nil) then
		return nil
	end
	local Names = GetDeferredWorldNames(OriginWorld)
	if (#Names == 0) then
		return nil
	end

	-- Only a command block can have its success count corrected afterwards: the console sits at
	-- (0, 0, 0) and a player command has an executor (spec section 7.3):
	local Writable = false
	local Position = a_Context.Position
	if (a_Context.Executor == nil) and (Position ~= nil)
		and ((Position.x ~= 0) or (Position.y ~= 0) or (Position.z ~= 0)) then
		Writable = true
	end

	return
	{
		Worlds = Names,
		Selector = a_Token,
		OriginWorldName = OriginWorld:GetName(),
		Position = Position,
		Writable = Writable,
	}
end



--- Pending write-backs: Key -> { WorldName, X, Y, Z, Total, Remaining }.
-- All Lua runs under the plugin's own lock, so no further synchronisation is needed here.
local PendingResults = {}
local NextPendingKey = 0



local function NewPendingResult(a_Deferred, a_InitialCount)
	NextPendingKey = NextPendingKey + 1

	local Position = a_Deferred.Position
	PendingResults[NextPendingKey] =
	{
		WorldName = a_Deferred.OriginWorldName,
		X = math.floor(Position.x),
		Y = math.floor(Position.y),
		Z = math.floor(Position.z),
		Total = a_InitialCount,
		Remaining = #a_Deferred.Worlds,
	}
	return NextPendingKey
end



local function ReportDeferredResult(a_Key, a_Count)
	local Entry = PendingResults[a_Key]
	if (Entry == nil) then
		return
	end

	Entry.Total = Entry.Total + a_Count
	Entry.Remaining = Entry.Remaining - 1
	if (Entry.Remaining > 0) then
		return
	end

	PendingResults[a_Key] = nil

	local World = cRoot:Get():GetWorld(Entry.WorldName)
	if (World == nil) then
		return
	end

	-- The write-back has to happen on the origin world's own thread: writing into it from the reporting
	-- world would take two world locks and re-create the very order we are avoiding (spec section 7.2):
	World:QueueTask(
		function ()
			local TargetWorld = cRoot:Get():GetWorld(Entry.WorldName)
			if (TargetWorld ~= nil) then
				TargetWorld:SetCommandBlockSuccessCount(Entry.X, Entry.Y, Entry.Z, Entry.Total)
			end
		end
	)
end



--- Resolves a deferred selector inside one world, on that world's own thread.
local function ResolveDeferredTargets(a_Deferred, a_World)
	local Entities = ResolveSelectorToken(
		a_Deferred.Selector,
		{ World = a_World, Position = nil, Executor = nil, LocalOnly = true }
	)
	if (Entities == nil) then
		return {}
	end

	local Targets = {}
	for _, Entity in ipairs(Entities) do
		if (MatchesTargetKind(Entity, a_Deferred.Kind)) then
			table.insert(Targets, Entity)
		end
	end
	return Targets
end



function ResolveTargets(a_Token, a_Context, a_Kind)
	if (type(a_Token) ~= "string") or (a_Token == "") then
		return nil, "No target given"
	end

	if (a_Token:sub(1, 1) ~= "@") then
		-- A plain argument addresses an online player by name only.
		local Found
		if (not cRoot:Get():FindAndDoWithPlayer(a_Token, function (a_Player) Found = a_Player end)) then
			return nil, "Player \"" .. a_Token .. "\" not found"
		end
		return { Found }
	end

	local Entities, Reason = ResolveSelectorToken(a_Token, a_Context)
	if (Entities == nil) then
		return nil, Reason
	end

	local Deferred = GetSelectorDeferral(a_Token, a_Context)

	local Targets = {}
	for _, Entity in ipairs(Entities) do
		if (MatchesTargetKind(Entity, a_Kind)) then
			table.insert(Targets, Entity)
		end
	end
	if (#Targets == 0) and (Deferred == nil) then
		return nil, "No target matched the selector \"" .. a_Token .. "\""
	end
	if (Deferred ~= nil) then
		-- The other worlds still have to be visited; ApplyToTargets() queues that work:
		Deferred.Kind = a_Kind
		Targets.Deferred = Deferred
	end
	return Targets
end





-- Runs a_Action on every selected target while the engine holds that target's
-- world lock.
--
-- The selection is re-enumerated per world and the action runs *inside* the
-- enumeration callback: cWorld::ForEachEntity / ForEachPlayer hold the world's
-- chunkmap lock for the whole callback, and cEntity::Destroy() only defers the
-- real removal (via QueueTask), so acting there -- even killing -- is safe.
-- Doing it after the enumeration returns would touch another world's entities
-- with no lock held.
--
-- Entities are matched by UniqueID, never by Lua object reference: references
-- must not be carried across worlds, and a target that vanished in between is
-- simply skipped. Returns the number of targets the action ran on.
--- Runs the action on the resolved targets (which all live in one world) and returns how many it ran
-- on. Enumerating that world is safe from here: it is the world the command executes in, whose lock the
-- engine already holds (spec section 3.1 of the command execution threading spec).
local function ApplyToTargetsHere(a_Targets, a_Action, a_Deferred)
	local ByWorld = {}
	local Order = {}
	for _, Entity in ipairs(a_Targets) do
		local World = Entity:GetWorld()
		local Ids = ByWorld[World]
		if (Ids == nil) then
			Ids = {}
			ByWorld[World] = Ids
			table.insert(Order, { World = World, Ids = Ids })
		end
		Ids[Entity:GetUniqueID()] = true
	end

	local Affected = 0
	for _, Entry in ipairs(Order) do
		Entry.World:ForEachEntity(
			function (a_Entity)
				local Id = a_Entity:GetUniqueID()
				if (Entry.Ids[Id]) then
					Entry.Ids[Id] = nil  -- never run the action twice on one entity
					a_Action(a_Entity, a_Deferred)
					Affected = Affected + 1
				end
				return false
			end
		)
	end
	return Affected
end



--- Applies the action to the resolved targets: the origin world immediately (the engine already holds
-- that world's lock, so this keeps the exact count and the same-tick effect), the other worlds through
-- their own task queues. Returns the number of targets affected in the origin world; the other worlds
-- report their counts later and the command block's success count is corrected then
-- (method D2, spec section 7).
function ApplyToTargets(a_Targets, a_Action)
	local Affected = ApplyToTargetsHere(a_Targets, a_Action)

	local Deferred = a_Targets.Deferred
	if (Deferred == nil) then
		return Affected
	end

	local Key = nil
	if (Deferred.Writable) then
		Key = NewPendingResult(Deferred, Affected)
	end

	for _, WorldName in ipairs(Deferred.Worlds) do
		local World = cRoot:Get():GetWorld(WorldName)
		if (World == nil) then
			-- The world vanished between listing it and queueing; do not leave the write-back waiting:
			if (Key ~= nil) then
				ReportDeferredResult(Key, 0)
			end
		else
			World:QueueTask(
				function ()
					-- Runs on that world's own thread, so resolving and acting here only takes its lock:
					local Targets = ResolveDeferredTargets(Deferred, World)
					-- a_Deferred = true tells the action that it runs on another world's thread one tick
					-- later, so it must not touch the executor (spec section 7.3):
					local Count = ApplyToTargetsHere(Targets, a_Action, true)
					if (Key ~= nil) then
						ReportDeferredResult(Key, Count)
					end
				end
			)
		end
	end

	return Affected
end





-- Returns a human-readable name for a resolved target: the player name, the
-- monster's custom name, or the monster's type name. cEntity has no GetName(), so
-- messages about "@e" targets must go through this.
function GetTargetName(a_Entity)
	if (a_Entity:IsPlayer()) then
		return a_Entity:GetName()
	end
	if (a_Entity:IsMob()) then
		local CustomName = a_Entity:GetCustomName()
		if ((CustomName ~= nil) and (CustomName ~= "")) then
			return CustomName
		end
		-- MobTypeToString is a C++ static bound with tolua_isusertable, so it needs
		-- colon syntax (see the StringToMobType note above).
		return cMonster:MobTypeToString(a_Entity:GetMobType())
	end
	return "?"
end
