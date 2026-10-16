-- command_text.lua
-- The JSON text-component layer that Core's /tellraw and /title share, plus the two helpers they need to get
-- an argument that the engine's token splitter would otherwise mangle.
--
-- Why the raw command line is needed: the engine splits a command with StringSplitCommandLine(), which treats
-- a double quote as a quote character and removes it, so a JSON component would arrive as
-- "{\"text\":\"Hi there\"}" -> "{text:Hi there}", and reassembling the tokens cannot put the quotes back.
-- CutRawRemainder() therefore cuts the argument out of the raw command line, using the same token spans
-- command_execute.lua uses for the /execute body.
--
-- Clean-room sources (the full list is in specs/commands/vanilla-1.12.2-presentation-commands.md in the
-- parent repository):
--   * "Commands/tellraw", 1.12.2-era revision (rev 1136502, 2018-06-01):
--     https://minecraft.wiki/w/Commands/tellraw?oldid=1136502 - "Must be valid raw JSON text".
--   * "Text component format": "Other types, such as score, selector, and nbt, require additional work from
--     the server ... If the client receives unresolved server-side text components, score and nbt text
--     components display as empty text, but selector text components display the selector itself."
--     https://minecraft.wiki/w/Text_component_format
--   * The "${" guard is this repository's own hardening, see cProtocol_1_8_0::SendChatRaw()
--     (src/Protocol/Protocol_1_8.cpp): a message containing "${" is dropped before it is sent.
--
-- Everything here is a pure function of its inputs except CheckTextComponent(), which calls the engine's JSON
-- parser (cJson:Parse); tests/test_presentation_commands.lua stubs cJson with a small parser of its own.

-- luacheck: new globals CutRawRemainder CheckTextComponent ParseTextArgument CheckChatDeliverable
-- luacheck: globals SplitRawCommand cJson

-- The component keys the server has to resolve before a client can show them. A 1.12.2 client that receives
-- them unresolved renders nothing (score) or the selector text itself (selector), so the command layer
-- refuses them instead of sending something visibly different from vanilla (spec section 5).
local SERVER_SIDE_COMPONENT_KEYS =
{
	score = true,
	selector = true,
}

-- The sequence cProtocol_1_8_0::SendChatRaw() refuses to send (a log4shell hardening measure).
local FORBIDDEN_CHAT_SEQUENCE = "${"






--- Cuts the rest of a command line out of the raw command, after its a_TokenIndex-th token.
-- a_TokenIndex counts the engine's tokens, whose first entry is the command name ("/title", "tellraw", ...).
-- The result keeps its original characters - quotes included - with the spaces that separated it from the
-- previous token removed, so that a JSON text component survives intact.
-- Returns nil when the raw line does not split into the given token list (the caller then falls back to its
-- own tokens) or when there is nothing left.
function CutRawRemainder(a_Split, a_RawCommand, a_TokenIndex)
	if (type(a_Split) ~= "table") or (type(a_RawCommand) ~= "string") then
		return nil
	end

	local Spans = SplitRawCommand(a_RawCommand)
	if (#Spans ~= #a_Split) then
		return nil
	end
	for Index = 1, a_TokenIndex do
		if (Spans[Index] == nil) or (Spans[Index].Value ~= a_Split[Index]) then
			return nil
		end
	end

	local Span = Spans[a_TokenIndex]
	if (Span == nil) or (Span.Last == nil) then
		return nil
	end

	local Remainder = (a_RawCommand:sub(Span.Last + 1):gsub("^ +", ""))
	if (Remainder == "") then
		return nil
	end
	return Remainder
end






--- Returns whether a decoded JSON value contains a component the server has to resolve.
local function ContainsServerSideComponent(a_Value)
	if (type(a_Value) ~= "table") then
		return false
	end

	for Key, Value in pairs(a_Value) do
		if (type(Key) == "string") and SERVER_SIDE_COMPONENT_KEYS[Key] then
			return true
		end
		if (ContainsServerSideComponent(Value)) then
			return true
		end
	end
	return false
end






--- Checks that a_Text is a raw JSON text component this server can send unchanged.
-- Returns nil when it is, or a human-readable reason when it is not: JSON that does not parse, a JSON value
-- that is not a component (the format is an object, or an array of them), or a component the server would
-- have to resolve first.
function CheckTextComponent(a_Text)
	if (type(a_Text) ~= "string") or (a_Text == "") then
		return "No text was given"
	end

	local Value, ParseError = cJson:Parse(a_Text)
	if (ParseError ~= nil) then
		return "Invalid JSON text component: " .. tostring(ParseError)
	end
	if (type(Value) ~= "table") then
		-- Also covers a JSON null, which cJson:Parse() returns as plain nil without an error:
		return "Invalid JSON text component: it must be a JSON object or array"
	end
	if (ContainsServerSideComponent(Value)) then
		return "The \"selector\" and \"score\" text components are not supported yet"
	end
	return nil
end






--- Returns a reason when a_Text cannot be delivered through the chat packet, nil when it can.
-- cProtocol_1_8_0::SendChatRaw() drops every message containing "${", so the command layer refuses such text
-- instead of reporting a success for a message the client never receives (spec section 5).
function CheckChatDeliverable(a_Text)
	if (type(a_Text) == "string") and (a_Text:find(FORBIDDEN_CHAT_SEQUENCE, 1, true) ~= nil) then
		return "A message containing \"" .. FORBIDDEN_CHAT_SEQUENCE .. "\" cannot be sent"
	end
	return nil
end






--- Decides how a command's text argument is sent.
-- a_RawText is the argument exactly as it was typed (nil when the raw command line could not be used);
-- a_PlainText is the same argument rebuilt from the engine's tokens.
-- An argument that starts with "{" or "[" is meant as a JSON text component and is validated as one;
-- anything else is the plain-text form this fork accepts, with "&" colour codes (spec section 2.5).
-- Returns { Kind = "json", Json = <text> } or { Kind = "plain", Text = <plain text> }, or nil plus a reason.
function ParseTextArgument(a_RawText, a_PlainText)
	local Candidate = a_RawText
	if (Candidate == nil) then
		Candidate = a_PlainText
	end
	if (type(Candidate) ~= "string") or (Candidate == "") then
		return nil, "No text was given"
	end

	local FirstChar = Candidate:sub(1, 1)
	if (FirstChar ~= "{") and (FirstChar ~= "[") then
		return { Kind = "plain", Text = a_PlainText or Candidate }
	end

	local Reason = CheckTextComponent(Candidate)
	if (Reason ~= nil) then
		return nil, Reason
	end
	return { Kind = "json", Json = Candidate }
end
