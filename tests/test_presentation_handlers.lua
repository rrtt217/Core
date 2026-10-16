-- test_presentation_handlers.lua
--
-- Handler-level tests for the five presentation commands: they drive the real handlers through a fake
-- universe and assert which C++ methods were called on which receiver, with which arguments.
--
-- Why this file exists: the parsers are covered by tests/test_presentation_commands.lua, but that leaves the
-- glue - the calls into cPlayer / cClientHandle / cWorld - untested, and getting a receiver wrong is easy
-- (cPlayer:SendAboveActionBarMessage() is a cPlayer method while the rest of the /title calls are on
-- cClientHandle, and a wrong receiver only shows up at runtime as "attempt to call method (a nil value)").
-- The fakes below deliberately implement only the methods the commands are allowed to call, so any wrong
-- receiver fails the test.
--
-- Verified specification: specs/commands/vanilla-1.12.2-presentation-commands.md (parent repository).
--
-- Invariants:
--   * /title's six forms each reach the documented protocol action: SendSetTitle / SendSetSubTitle /
--     SendSetRawTitle / SendSetRawSubTitle / SendTitleTimes / SendHideTitle / SendResetTitle.
--   * The action bar goes through cPlayer (SendAboveActionBarMessage for text, SendMessageRaw with
--     ctAboveActionBar for a JSON component).
--   * /stopsound sends the "MC|StopSound" plugin message with the payload captured from a vanilla server.
--   * Refused arguments reach no player at all.
--
-- Run with:  lua tests/test_presentation_handlers.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_coords.lua")
dofile(ScriptDir .. "/../command_execute.lua")  -- SplitRawCommand(), used to recover JSON components
dofile(ScriptDir .. "/../target_selectors.lua")
dofile(ScriptDir .. "/../command_presentation.lua")
dofile(ScriptDir .. "/../command_text.lua")
dofile(ScriptDir .. "/../cmd_title.lua")
dofile(ScriptDir .. "/../cmd_particle.lua")
dofile(ScriptDir .. "/../cmd_playsound.lua")
dofile(ScriptDir .. "/../cmd_stopsound.lua")
dofile(ScriptDir .. "/../cmd_tellraw.lua")

-- The fakes below are defined here and read by the handlers, so luacheck counts them as unused globals in
-- this file (131 == "unused global variable").
-- luacheck: ignore 131
-- luacheck: new globals cRoot cJson cCompositeChat ctAboveActionBar Vector3d Vector3f
-- luacheck: new globals ResolveTargets MakeSelectorContext SendMessageFailure SendMessageSuccess
-- luacheck: globals HandleTitleCommand HandleParticleCommand HandlePlaysoundCommand
-- luacheck: globals HandleStopsoundCommand HandleTellrawCommand ApplyToTargets

local NumPassed = 0
local NumFailed = 0

local function Check(a_Condition, a_Message)
	if (a_Condition) then
		NumPassed = NumPassed + 1
	else
		NumFailed = NumFailed + 1
		print("FAIL: " .. a_Message)
	end
end

local function CheckEquals(a_Actual, a_Expected, a_Message)
	Check(
		a_Actual == a_Expected,
		string.format("%s (expected %s, got %s)", a_Message, tostring(a_Expected), tostring(a_Actual))
	)
end






-- Stubs ----------------------------------------------------------------------
-- The engine pieces the handlers touch. Only what the commands are supposed to use is implemented, so a call
-- to anything else raises instead of silently passing.

-- The parsers (and the real "selector" / "score" detection) are tested in
-- tests/test_presentation_commands.lua; this stub only has to accept the components that reach a handler and
-- to mark the two server-side keys, so that the refusal path is reachable here as well.
cJson =
{
	Parse = function (a_Self, a_Text)
		assert(a_Self == cJson, "cJson:Parse must be called with colon syntax")
		if (a_Text:find("\"selector\"", 1, true) ~= nil) then
			return { selector = "@s" }
		end
		if (a_Text:find("\"score\"", 1, true) ~= nil) then
			return { score = { name = "*" } }
		end
		local FirstChar = a_Text:sub(1, 1)
		if (FirstChar == "{") or (FirstChar == "[") then
			return { text = "stub" }
		end
		return nil, "stub: not a JSON component"
	end,
}

cCompositeChat = function (a_Text)
	return { Text = a_Text }
end

ctAboveActionBar = 2

Vector3d = function (a_X, a_Y, a_Z) return { x = a_X, y = a_Y, z = a_Z } end
Vector3f = function (a_X, a_Y, a_Z) return { x = a_X, y = a_Y, z = a_Z } end

-- Records what a handler said to the command's sender (nil for the console, which gets the text as output).
local LastMessage = nil
SendMessageFailure = function (a_Player, a_Message) LastMessage = "failure: " .. tostring(a_Message); return nil end
SendMessageSuccess = function (a_Player, a_Message) LastMessage = "success: " .. tostring(a_Message); return nil end

-- The selector layer has its own tests; the handlers only need it to hand back the player under test.
local Subject = nil
MakeSelectorContext = function () return {} end
ResolveTargets = function () return { Subject } end

-- The fake client handle: exactly the methods the /title, /playsound and /stopsound glue may use. Note the
-- absence of SendAboveActionBarMessage - that one belongs to cPlayer.
local function MakeClientHandle(a_Player)
	local Client = { Player = a_Player, Calls = {} }
	local function Record(a_CallName, ...)
		table.insert(Client.Calls, { Name = a_CallName, Args = { ... } })
	end

	Client.SendTitleTimes = function (_, a_FadeIn, a_Stay, a_FadeOut)
		Record("SendTitleTimes", a_FadeIn, a_Stay, a_FadeOut)
	end
	Client.SendHideTitle = function () Record("SendHideTitle") end
	Client.SendResetTitle = function () Record("SendResetTitle") end
	Client.SendSetTitle = function (_, a_Chat) Record("SendSetTitle", a_Chat.Text) end
	Client.SendSetSubTitle = function (_, a_Chat) Record("SendSetSubTitle", a_Chat.Text) end
	Client.SendSetRawTitle = function (_, a_Json) Record("SendSetRawTitle", a_Json) end
	Client.SendSetRawSubTitle = function (_, a_Json) Record("SendSetRawSubTitle", a_Json) end
	Client.SendSoundEffect = function (_, a_Name, a_Position, a_Volume, a_Pitch)
		Record("SendSoundEffect", a_Name, a_Position.x, a_Position.y, a_Position.z, a_Volume, a_Pitch)
	end
	Client.SendPluginMessage = function (_, a_Channel, a_Payload)
		Record("SendPluginMessage", a_Channel, a_Payload)
	end
	return Client
end

local NextEntityID = 0

-- The fake player: the cPlayer and cEntity methods the glue may use.
local function MakePlayer(a_Name, a_World, a_X, a_Y, a_Z)
	NextEntityID = NextEntityID + 1
	local Player = {
		Name = a_Name,
		World = a_World,
		Position = { x = a_X, y = a_Y, z = a_Z },
		UniqueID = NextEntityID,
		Calls = {},
	}
	local function Record(a_CallName, ...)
		table.insert(Player.Calls, { Name = a_CallName, Args = { ... } })
	end

	local Client = MakeClientHandle(Player)
	Player.Client = Client

	Player.GetName = function (a_Self) return a_Self.Name end
	Player.GetWorld = function (a_Self) return a_Self.World end
	Player.GetPosition = function (a_Self) return a_Self.Position end
	Player.GetUniqueID = function (a_Self) return a_Self.UniqueID end
	Player.GetClientHandle = function (a_Self) return a_Self.Client end
	Player.IsPlayer = function () return true end
	Player.IsMob = function () return false end
	Player.IsPawn = function () return true end
	Player.SendAboveActionBarMessage = function (_, a_Text) Record("SendAboveActionBarMessage", a_Text) end
	Player.SendMessageRaw = function (_, a_Json, a_Type) Record("SendMessageRaw", a_Json, a_Type) end
	return Player
end

-- The fake world: only ForEachEntity (used by ApplyToTargets) and the particle broadcast.
local function MakeWorld(a_Name, a_Players)
	local World = { Name = a_Name, Players = a_Players, Calls = {} }

	World.GetName = function (a_Self) return a_Self.Name end
	World.ForEachEntity = function (a_Self, a_Callback)
		for _, Player in ipairs(a_Self.Players) do
			if (a_Callback(Player)) then
				return true
			end
		end
		return false
	end
	World.BroadcastParticleEffect = function (_, a_ParticleName, a_Source, a_Offset, a_Data, a_Amount)
		table.insert(World.Calls, {
			Name = "BroadcastParticleEffect",
			Args = {
				a_ParticleName,
				a_Source.x, a_Source.y, a_Source.z,
				a_Offset.x, a_Offset.y, a_Offset.z,
				a_Data, a_Amount,
			},
		})
	end
	return World
end

local Overworld = nil
local Root = nil

-- Builds a fresh world/player/root set for one case.
local function ResetUniverse(a_PlayerPosition)
	Overworld = MakeWorld("world", {})
	local Position = a_PlayerPosition or {}
	local Player = MakePlayer(
		"Harry00025", Overworld,
		Position.x or 0, Position.y or 64, Position.z or 0
	)
	Overworld.Players = { Player }
	Subject = Player
	LastMessage = nil

	Root = {
		GetDefaultWorld = function () return Overworld end,
		GetWorld = function (_, a_Name) return (a_Name == "world") and Overworld or nil end,
		ForEachWorld = function (_, a_Callback) a_Callback(Overworld) end,
	}
	cRoot = { Get = function () return Root end }
	return Player
end






-- Helpers --------------------------------------------------------------------

local function FindCall(a_Calls, a_Name)
	for _, Call in ipairs(a_Calls) do
		if (Call.Name == a_Name) then
			return Call
		end
	end
	return nil
end

--- Runs one command line through a handler and returns the player, the client handle and the world.
local function Run(a_Handler, a_Line)
	local Split = { a_Line:match("^(%S+)") }
	for Token in a_Line:gmatch("%s+(%S+)") do
		Split[#Split + 1] = Token
	end

	local Player = Subject
	-- Start clean: the assertions below ask "what did this command call?", not "what has ever been called".
	Player.Calls = {}
	Player.Client.Calls = {}
	Overworld.Calls = {}
	LastMessage = nil
	a_Handler(Split, Player, a_Line, nil)
	return Player, Player.Client, Overworld
end






--- Runs one command line through a handler and returns the target's client handle.
-- For the cases that assert on the client handle only; the player itself is never needed there.
local function RunClient(a_Handler, a_Line)
	local _, Client = Run(a_Handler, a_Line)
	return Client
end






local function TestTitleModes()
	-- The plain-text title goes through cCompositeChat, which renders the "&" codes:
	local Player, Client = Run(HandleTitleCommand, "/title @s title Hello")
	local Call = FindCall(Client.Calls, "SendSetTitle")
	Check(Call ~= nil, "/title title reaches SendSetTitle")
	Check(Call ~= nil and Call.Args[1] == "Hello", "the title text is passed on")
	Check(FindCall(Player.Calls, "SendAboveActionBarMessage") == nil, "the title does not use the action bar path")

	Client = RunClient(HandleTitleCommand, "/title @s subtitle Sub")
	Check(FindCall(Client.Calls, "SendSetSubTitle") ~= nil, "/title subtitle reaches SendSetSubTitle")

	-- A JSON component bypasses cCompositeChat and is sent verbatim:
	Client = RunClient(HandleTitleCommand, "/title @s title {\"text\":\"Chapter I\"}")
	Call = FindCall(Client.Calls, "SendSetRawTitle")
	Check(Call ~= nil and Call.Args[1] == "{\"text\":\"Chapter I\"}", "/title title sends a JSON component verbatim")

	Client = RunClient(HandleTitleCommand, "/title @s subtitle {\"text\":\"Sub\"}")
	Call = FindCall(Client.Calls, "SendSetRawSubTitle")
	Check(Call ~= nil and Call.Args[1] == "{\"text\":\"Sub\"}", "/title subtitle sends a JSON component verbatim")

	-- The action bar is the one mode that uses cPlayer, not the client handle:
	local ActionPlayer, ActionClient = Run(HandleTitleCommand, "/title @s actionbar Bar")
	Call = FindCall(ActionPlayer.Calls, "SendAboveActionBarMessage")
	Check(Call ~= nil and Call.Args[1] == "Bar", "/title actionbar reaches cPlayer:SendAboveActionBarMessage")
	Check(
		FindCall(ActionClient.Calls, "SendAboveActionBarMessage") == nil,
		"the action bar is not sent through the client handle"
	)

	local JsonActionPlayer = Run(HandleTitleCommand, "/title @s actionbar {\"text\":\"AB\"}")
	Call = FindCall(JsonActionPlayer.Calls, "SendMessageRaw")
	Check(
		(Call ~= nil) and (Call.Args[1] == "{\"text\":\"AB\"}") and (Call.Args[2] == ctAboveActionBar),
		"a JSON action bar is sent with the above-action-bar chat type"
	)

	-- times / clear / reset:
	Client = RunClient(HandleTitleCommand, "/title @s times 10 70 20")
	Call = FindCall(Client.Calls, "SendTitleTimes")
	Check(Call ~= nil, "/title times reaches SendTitleTimes")
	if (Call ~= nil) then
		CheckEquals(Call.Args[1], 10, "the fade in time arrives")
		CheckEquals(Call.Args[2], 70, "the stay time arrives")
		CheckEquals(Call.Args[3], 20, "the fade out time arrives")
	end

	Client = RunClient(HandleTitleCommand, "/title @s times -5 -1 0")
	Call = FindCall(Client.Calls, "SendTitleTimes")
	Check(Call ~= nil and Call.Args[1] == 0 and Call.Args[2] == 0, "negative times are clamped before they are sent")

	Client = RunClient(HandleTitleCommand, "/title @s clear")
	Check(FindCall(Client.Calls, "SendHideTitle") ~= nil, "/title clear reaches SendHideTitle")
	Client = RunClient(HandleTitleCommand, "/title @s reset")
	Check(FindCall(Client.Calls, "SendResetTitle") ~= nil, "/title reset reaches SendResetTitle")
end






local function TestParticleBroadcast()
	Run(HandleParticleCommand, "/particle explode ~ ~1 ~ 0.5 1 0.5 2 10 force")
	local Call = Overworld.Calls[#Overworld.Calls]
	Check(Call ~= nil, "/particle reaches the world")
	if (Call ~= nil) then
		CheckEquals(Call.Name, "BroadcastParticleEffect", "the particle is broadcast")
		CheckEquals(Call.Args[1], "explode", "the particle name is passed on")
		CheckEquals(Call.Args[2], 0, "x resolves to the player's position")
		CheckEquals(Call.Args[3], 65, "y follows the relative offset")
		CheckEquals(Call.Args[6], 1, "the y spread is passed on")
		CheckEquals(Call.Args[8], 2, "the speed is passed as the particle data")
		CheckEquals(Call.Args[9], 10, "the count is passed on")
	end

	-- A refused particle must not reach the world at all:
	Overworld.Calls = {}
	Run(HandleParticleCommand, "/particle dust ~ ~ ~ 0 0 0 1")
	CheckEquals(#Overworld.Calls, 0, "an unknown particle is not broadcast")
	Check(LastMessage ~= nil and LastMessage:find("Unknown particle", 1, true) ~= nil, "and it is reported")
end






local function TestPlaysoundPerTarget()
	Run(HandlePlaysoundCommand, "/playsound mob.pig.say weather @s ~ ~ ~ 1 0.5 0")
	local Call = FindCall(Subject.Client.Calls, "SendSoundEffect")
	Check(Call ~= nil, "/playsound reaches the target's client handle")
	if (Call ~= nil) then
		CheckEquals(Call.Args[1], "mob.pig.say", "the sound name arrives")
		CheckEquals(Call.Args[2], 0, "the sound is centred on the player")
		CheckEquals(Call.Args[3], 64, "at the player's own height")
		CheckEquals(Call.Args[4], 0, "the x coordinate is passed on")
		CheckEquals(Call.Args[5], 1, "the volume is passed on")
		CheckEquals(Call.Args[6], 0.5, "the pitch is passed on")
	end

	-- A target far outside the audible sphere hears nothing when no minimum volume is given:
	Run(HandlePlaysoundCommand, "/playsound mob.pig.say weather @s 500 64 0 0.1 1 0")
	Check(FindCall(Subject.Client.Calls, "SendSoundEffect") == nil, "an inaudible sound is not sent")
	Check(LastMessage ~= nil and LastMessage:find("hear", 1, true) ~= nil, "and the failure is reported")

	-- With a minimum volume it is re-centred on the target instead:
	Run(HandlePlaysoundCommand, "/playsound mob.pig.say weather @s 500 64 0 0.1 1 0.5")
	local Rerouted = FindCall(Subject.Client.Calls, "SendSoundEffect")
	Check(Rerouted ~= nil, "a minimum volume makes the sound audible again")
	if (Rerouted ~= nil) then
		CheckEquals(Rerouted.Args[2], 0, "the re-centred sound sits on the target")
		CheckEquals(Rerouted.Args[5], 0.5, "and uses the minimum volume")
	end

	-- An unknown category never reaches a client:
	Run(HandlePlaysoundCommand, "/playsound mob.pig.say ui @s")
	Check(FindCall(Subject.Client.Calls, "SendSoundEffect") == nil, "an unknown source is not sent")
	Check(LastMessage ~= nil and LastMessage:find("Unknown sound source", 1, true) ~= nil, "and it is reported")
end






local function TestStopsoundMessage()
	Run(HandleStopsoundCommand, "/stopsound @s weather minecraft:weather.rain")
	local Call = FindCall(Subject.Client.Calls, "SendPluginMessage")
	Check(Call ~= nil, "/stopsound reaches the target's client handle")
	if (Call ~= nil) then
		CheckEquals(Call.Args[1], "MC|StopSound", "the channel is the vanilla one")
		CheckEquals(Call.Args[2], "\7weather\22minecraft:weather.rain", "the payload matches the vanilla capture")
	end

	-- The two shapes the capture does not cover, as implemented:
	Run(HandleStopsoundCommand, "/stopsound @s weather")
	Call = FindCall(Subject.Client.Calls, "SendPluginMessage")
	Check(Call ~= nil and Call.Args[2] == "\7weather", "a category alone sends one string")

	Run(HandleStopsoundCommand, "/stopsound @s")
	Call = FindCall(Subject.Client.Calls, "SendPluginMessage")
	Check(Call ~= nil and Call.Args[2] == "", "no argument sends an empty payload")

	-- Refusals:
	Run(HandleStopsoundCommand, "/stopsound @s ui")
	Check(FindCall(Subject.Client.Calls, "SendPluginMessage") == nil, "an unknown category sends nothing")
	Run(HandleStopsoundCommand, "/stopsound")
	Check(FindCall(Subject.Client.Calls, "SendPluginMessage") == nil, "a missing target sends nothing")
end






local function TestTellrawMessage()
	Run(HandleTellrawCommand, "/tellraw @s {\"text\":\"Hi there\",\"color\":\"red\"}")
	local Call = FindCall(Subject.Calls, "SendMessageRaw")
	Check(Call ~= nil, "/tellraw reaches cPlayer:SendMessageRaw")
	if (Call ~= nil) then
		CheckEquals(Call.Args[1], "{\"text\":\"Hi there\",\"color\":\"red\"}", "the component is passed verbatim")
		CheckEquals(Call.Args[2], nil, "no chat type is forced (the default is the chat box)")
	end

	-- Refused components never reach a player:
	Run(HandleTellrawCommand, "/tellraw @s {\"selector\":\"@s\"}")
	Check(FindCall(Subject.Calls, "SendMessageRaw") == nil, "a server-side component sends nothing")
	Check(LastMessage ~= nil and LastMessage:find("selector", 1, true) ~= nil, "and it is reported")

	Run(HandleTellrawCommand, "/tellraw @s {\"text\":\"${x}\"}")
	Check(FindCall(Subject.Calls, "SendMessageRaw") == nil, "a message the chat packet would drop sends nothing")
end






local function TestNoPlayerReached()
	-- The player is gone between resolving and applying: the command reports it instead of claiming success.
	local Player = Run(HandleTitleCommand, "/title @s title Hello")
	Overworld.Players = {}
	LastMessage = nil
	HandleTitleCommand({ "/title", "@s", "title", "Hello" }, Player, "/title @s title Hello", nil)
	Check(
		(LastMessage ~= nil) and (LastMessage:find("No player was reached", 1, true) ~= nil),
		"a vanished player is reported"
	)
end






ResetUniverse()
TestTitleModes()

ResetUniverse()
TestParticleBroadcast()

ResetUniverse()
TestPlaysoundPerTarget()

ResetUniverse()
TestStopsoundMessage()

ResetUniverse()
TestTellrawMessage()

ResetUniverse()
TestNoPlayerReached()

print(string.format("test_presentation_handlers: %d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
