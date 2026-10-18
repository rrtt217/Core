-- cmd_setblock.lua
-- Implements the vanilla 1.12.2 /setblock command:
--   setblock <x> <y> <z> <block> [dataValue] [oldBlockHandling] [dataTag]
-- Behaviour, sources and the known deviations: specs/commands/vanilla-1.12.2-block-commands.md

-- luacheck: ignore 131
-- luacheck: globals HandleSetBlockCommand HandleConsoleSetBlock
-- luacheck: globals ParseSetblockLine NormalizeBox GetVolume IsValidBlockPosition GetCommandWorld
-- luacheck: globals GetOriginPosition ParseCommandCoords ResolveBlockType
-- luacheck: globals SendMessageFailure SendMessageSuccess

function HandleSetBlockCommand(a_Split, a_Player, _, a_Origin)
	local Parse, Reason = ParseSetblockLine(a_Split)
	if (Parse == nil) then
		return true, SendMessageFailure(a_Player, Reason), 0
	end

	local World = GetCommandWorld(a_Player, a_Origin)
	if (World == nil) then
		return true, SendMessageFailure(a_Player, "There is no world to change a block in"), 0
	end

	local X, Y, Z = ParseCommandCoords(Parse.X, Parse.Y, Parse.Z, GetOriginPosition(a_Origin))
	if (X == nil) then
		-- ParseCommandCoords() reports its failure as nil plus the reason in the second value:
		return true, SendMessageFailure(a_Player, Y), 0
	end
	X, Y, Z = math.floor(X), math.floor(Y), math.floor(Z)

	local Ok, PositionReason = IsValidBlockPosition(X, Y, Z)
	if (not Ok) then
		return true, SendMessageFailure(a_Player, PositionReason), 0
	end

	local BlockType = ResolveBlockType(Parse.Block)
	if (BlockType == nil) then
		return true, SendMessageFailure(a_Player, "Unknown block \"" .. Parse.Block .. "\""), 0
	end

	local BlockValid, OldType, OldMeta = World:GetBlockTypeMeta(Vector3i(X, Y, Z))
	if (not BlockValid) then
		return true, SendMessageFailure(a_Player, "That block is in an unloaded chunk"), 0
	end

	if ((Parse.Mode == "keep") and (OldType ~= E_BLOCK_AIR)) then
		return true, SendMessageFailure(a_Player, "That block is not air"), 0
	end
	if ((Parse.Mode ~= "destroy") and (OldType == BlockType) and (OldMeta == Parse.Data)) then
		return true, SendMessageFailure(a_Player, "That block is already the same"), 0
	end

	if ((Parse.Mode == "destroy") and (OldType ~= E_BLOCK_AIR)) then
		-- The 1.12.2 "destroy" handling drops the old block as if a player had broken it:
		World:DropBlockAsPickups(Vector3i(X, Y, Z), nil, nil)
	end

	World:SetBlock(Vector3i(X, Y, Z), BlockType, Parse.Data)
	return true, SendMessageSuccess(a_Player, "Block placed"), 1
end



function HandleConsoleSetBlock(a_Split, _, _, a_Origin)
	return HandleSetBlockCommand(a_Split, nil, nil, a_Origin)
end
