-- cmd_execute.lua
-- Implements the /execute command for Core, following vanilla Java Edition 1.12.2:
--   execute <entity> <x> <y> <z> [detect <x2> <y2> <z2> <block> <dataValue>] <command ...>
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-execute-and-testfor.md

-- luacheck: new globals HandleExecuteCommand HandleConsoleExecute
-- luacheck: globals SendMessage SendMessageFailure SendMessageSuccess ResolveTargets GetTargetName
-- luacheck: globals ApplyToTargets MakeSelectorContext GetOriginPosition ParseCommandCoords
-- luacheck: globals ParseExecuteLine ResolveBlockType IsBlockForbiddenCommand
-- luacheck: globals cRoot cPluginManager cCommandOrigin Vector3d Vector3i

--- Describes why an executed command did not run, for the responding message.
local function DescribeResult(a_Result)
	if (a_Result == cPluginManager.crUnknownCommand) then
		return "Unknown command"
	elseif (a_Result == cPluginManager.crNoPermission) then
		return "You do not have permission to execute that command"
	elseif (a_Result == cPluginManager.crBlocked) then
		return "The command was blocked by a plugin"
	end
	return "The command failed"
end





--- Runs the parsed command once for one selected target.
-- The target supplies the execution position ("coordinates specified with tilde notation are relative to the
-- target, not to the position of the command's execution") and, when it is a player, is also the command's
-- sender ("executes the specified command as if executed by the specified target(s)"), so @s resolves to it
-- and it receives the command's feedback. The permissions come from a_Player, the entity that issued
-- /execute (spec section 3.1).
-- Returns false when the command did not run - a failed detect check (the reason is nil then, the check
-- simply gated it) or a failed dispatch (the reason describes the failure) - otherwise true plus the
-- command's success count and the text it produced.
local function RunForTarget(a_Parse, a_Player, a_Target)
	local World = a_Target:GetWorld()
	if (World == nil) then
		return false, 0, "", "The target is gone"
	end

	local TargetPosition = a_Target:GetPosition()
	local X, Y, Z = ParseCommandCoords(a_Parse.X, a_Parse.Y, a_Parse.Z, TargetPosition)
	if (X == nil) then
		-- The handler probes the coordinate syntax before running anything, so this is only reachable for a
		-- position that cannot carry the offsets (see the caller):
		return false, 0, "", "The coordinates could not be resolved"
	end

	-- detect <x2> <y2> <z2> <block> <dataValue> is a single-block /testforblock-style check that gates the
	-- run; its coordinates are relative to (x, y, z), not to the target:
	if (a_Parse.Detect ~= nil) then
		local CheckX, CheckY, CheckZ = ParseCommandCoords(
			a_Parse.Detect.X, a_Parse.Detect.Y, a_Parse.Detect.Z,
			{ x = X, y = Y, z = Z }
		)
		if (CheckX == nil) then
			return false, 0, "", "The coordinates could not be resolved"
		end

		-- cWorld:GetBlockTypeMeta() answers "readable?, type, meta"; a position outside the world height is
		-- reported as plain air instead of the flag, so accept only an explicit true:
		local Readable, BlockType, BlockMeta = World:GetBlockTypeMeta(
			Vector3i(math.floor(CheckX), math.floor(CheckY), math.floor(CheckZ))
		)
		if (Readable ~= true) then
			return false, 0, "", "The block could not be read"
		end

		-- A failed check is not a failure of the executed command: it simply gates the run (nil reason):
		if (BlockType ~= a_Parse.Detect.Type) then
			return false, 0, ""
		end
		if ((a_Parse.Detect.Data ~= nil) and (BlockMeta ~= a_Parse.Detect.Data)) then
			return false, 0, ""
		end
	end

	-- The command's world, position and sender. A target that is not a player has no sender at all - it cannot
	-- have one in Cuberite, where cCommandOrigin carries a cPlayer (spec section 3.1):
	local CommandOrigin
	if (a_Target:IsPlayer()) then
		CommandOrigin = cCommandOrigin(World, Vector3d(X, Y, Z), a_Target)
	else
		CommandOrigin = cCommandOrigin(World, Vector3d(X, Y, Z))
	end

	local Result, Output, SuccessCount = cRoot:Get():GetPluginManager():ExecuteCommandFromOrigin(
		CommandOrigin,
		a_Player,
		a_Parse.Command
	)

	-- crExecuted == 0 and 0 is true in Lua, so the result is compared, never tested for truth:
	if (Result ~= cPluginManager.crExecuted) then
		return false, 0, "", DescribeResult(Result)
	end
	return true, (tonumber(SuccessCount) or 0), (Output or "")
end





function HandleExecuteCommand(Split, Player, EntireCommand, Origin)
	local Parse, Reason = ParseExecuteLine(Split, EntireCommand)
	if (Parse == nil) then
		return true, SendMessageFailure(Player, Reason), 0
	end

	-- A command block may not reach the administrator commands through /execute either (spec section 3.2). The
	-- console and RCON own the default world at the position (0, 0, 0), while a command block always runs at
	-- the centre of its own block, so its x and z carry the +0.5 offset and can never be 0 - the test therefore
	-- tells the two apart exactly. An origin without a position is treated as a block, so the rule fails closed:
	local Position = GetOriginPosition(Origin)
	local IsBlockOrigin = (Position == nil)
		or ((Position.x ~= 0) or (Position.y ~= 0) or (Position.z ~= 0))
	if ((Player == nil) and IsBlockOrigin and IsBlockForbiddenCommand(Parse.Command)) then
		return true, SendMessageFailure(Player, "Command blocks can not execute \"" .. Parse.Command .. "\""), 0
	end

	-- The coordinate syntax does not depend on the target, so it is checked once, with a probe position, before
	-- anything runs; only the "~" offsets themselves need the target:
	local Probe, CoordReason = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, { x = 0, y = 0, z = 0 })
	if (Probe == nil) then
		return true, SendMessageFailure(Player, CoordReason), 0
	end
	if (Parse.Detect ~= nil) then
		Probe, CoordReason = ParseCommandCoords(Parse.Detect.X, Parse.Detect.Y, Parse.Detect.Z, { x = 0, y = 0, z = 0 })
		if (Probe == nil) then
			return true, SendMessageFailure(Player, CoordReason), 0
		end

		Parse.Detect.Type = ResolveBlockType(Parse.Detect.Block)
		if (Parse.Detect.Type == nil) then
			return true, SendMessageFailure(Player, "Unknown block \"" .. Parse.Detect.Block .. "\""), 0
		end
	end

	-- A named player or a target selector selects the executors ("run once as each of them"):
	local Context = MakeSelectorContext(Player, Origin)

	-- The selection stays inside the origin world: a target of another world is queued for that world's thread a
	-- tick later, where neither the issuing player (whose permissions authorize the executed command) nor the
	-- text the command produced may be used anymore (spec section 5.7). Vanilla spans dimensions; that stays a
	-- recorded deviation until the permission and the count can cross worlds safely.
	Context.LocalOnly = true

	local Targets, ResolveReason = ResolveTargets(Parse.Entity, Context, "entity")
	if (Targets == nil) then
		return true, SendMessageFailure(Player, ResolveReason), 0
	end

	-- Every target runs the command once; the success count adds up what the executed commands report
	-- (vanilla: "commands run using /execute now pass their success value back to the command block"):
	local Ran = 0
	local SuccessCount = 0
	local Output = ""
	local FailureReason = nil
	ApplyToTargets(
		Targets,
		function (Target)
			local TargetRan, TargetCount, TargetOutput, TargetReason = RunForTarget(Parse, Player, Target)
			if (TargetRan) then
				Ran = Ran + 1
				SuccessCount = SuccessCount + TargetCount
				if (TargetOutput ~= "") then
					Output = TargetOutput
				end
			elseif ((TargetReason ~= nil) and (FailureReason == nil)) then
				FailureReason = TargetReason
			end
		end
	)

	if (Ran == 0) then
		if (Parse.Detect ~= nil) and (FailureReason == nil) then
			return true, SendMessageFailure(Player, "The block detection failed"), 0
		end
		return true, SendMessageFailure(Player, FailureReason or "The command was not executed"), 0
	end
	if (Output ~= "") then
		-- The command's own text is what a command block stores as its output:
		return true, Output, SuccessCount
	end
	return true, SendMessageSuccess(Player, "Successfully executed the command on " .. Ran .. " target(s)"), SuccessCount
end

function HandleConsoleExecute(Split, _, EntireCommand, Origin)
	-- Console commands have no player; the engine still passes the origin as the 4th argument:
	return HandleExecuteCommand(Split, nil, EntireCommand, Origin)
end
