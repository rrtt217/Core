-- cmd_testfor.lua
-- Implements the /testfor command for Core, following vanilla Java Edition 1.12.2:
--   testfor <player> [dataTag]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-execute-and-testfor.md
-- The success count is the number of matched targets, which is what a comparator reads from the command block
-- that ran the command.

-- luacheck: new globals HandleTestforCommand HandleConsoleTestfor
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess ResolveTargets GetTargetName
-- luacheck: globals MakeSelectorContext HasExtraArgument

function HandleTestforCommand(Split, Player, _, Origin)
	if (not Split[2]) then
		return true, SendMessageFailure(Player, "Usage: " .. Split[1] .. " <target>"), 0
	end

	if (HasExtraArgument(Split, 3)) then
		-- 1.12.2 takes an optional NBT data tag here; matching it needs an SNBT parser, which Core does not
		-- have yet, so the argument is refused instead of being ignored (spec section 5.5):
		return true, SendMessageFailure(Player, "Data tags are not supported yet"), 0
	end

	-- 1.12.2: "Must be a player name or target selector (@e is permitted to target entities other than
	-- players)". The selector layer yields players and monsters (its documented @e deviation):
	local Context = MakeSelectorContext(Player, Origin)

	-- The count stays inside the origin world: the selector layer defers the other worlds to their own threads,
	-- where a count could only be written back asynchronously, so a position-independent selector such as "@a"
	-- would silently count 0 there (spec section 5.7). Vanilla spans dimensions - a recorded deviation.
	Context.LocalOnly = true

	local Targets, Reason = ResolveTargets(Split[2], Context, "entity")
	if (Targets == nil) then
		return true, SendMessageFailure(Player, Reason), 0
	end

	-- The count is the number of matches. ResolveTargets() returns the origin world's matches; a selector that
	-- also spans other worlds is reported separately by the selector layer (see the spec's deviations):
	local Count = #Targets
	if (Count == 1) then
		return true, SendMessageSuccess(Player, "Found " .. GetTargetName(Targets[1])), Count
	end
	return true, SendMessageSuccess(Player, "Found " .. Count .. " matching targets"), Count
end

function HandleConsoleTestfor(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleTestforCommand(Split, nil, EntireCommand, Origin)
end
