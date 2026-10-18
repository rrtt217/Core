-- command_ban.lua
-- Parsers, IP validation and list formatting for the vanilla 1.12.2 ban commands
-- (/ban-ip, /banlist, /pardon, /pardon-ip). The database side lives in banlist.lua.
-- Behaviour and sources: specs/commands/vanilla-1.12.2-ban-commands.md
--
-- The functions here are pure: they never touch Cuberite objects, so the tests can pin the 1.12.2
-- grammar (an online player's name may stand in for an IP, /pardon-ip insists on a valid address,
-- /banlist requires its ips|players argument) without a fake universe.

-- luacheck: globals IsValidIPAddress ParseBanIPArguments ParseBanlistKind ParsePardonArguments
-- luacheck: globals ParsePardonIPArguments FormatBanlist

-- The reason recorded when the command does not supply one (spec section 2.1):
local DEFAULT_BAN_REASON = "Banned by an operator."



--- Returns true for a dotted-quad IPv4 address (four decimal octets, 0-255, no leading zeros).
local function IsIPv4(a_Token)
	local A, B, C, D = a_Token:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if (A == nil) then
		return false
	end
	for _, Octet in ipairs({ A, B, C, D }) do
		if (#Octet > 3) then
			return false
		end
		if ((#Octet > 1) and (Octet:sub(1, 1) == "0")) then
			return false
		end
		if (tonumber(Octet) > 255) then
			return false
		end
	end
	return true
end



--- Counts the colon-separated hexadecimal groups of a non-empty IPv6 fragment.
-- Returns -1 when a group is empty or is not 1-4 hexadecimal digits.
local function CountHexGroups(a_Text)
	local Count = 0
	for Group in (a_Text .. ":"):gmatch("([^:]*):") do
		if ((Group == "") or (Group:match("^%x%x?%x?%x?$") == nil)) then
			return -1
		end
		Count = Count + 1
	end
	return Count
end



--- Returns true for an IPv6 address in its textual form.
-- Accepts at most one "::", 1-4 hexadecimal digit groups and a trailing dotted-quad (which stands for
-- the last two groups), without zone identifiers.
local function IsIPv6(a_Token)
	if ((a_Token:find(":", 1, true) == nil) or (a_Token:find("[^%x:%.]") ~= nil)) then
		return false
	end

	-- An embedded IPv4 tail counts as two groups; rewrite it so the group counting below is uniform:
	local Text = a_Token
	local Tail = Text:match("([^:]+)$")
	if ((Tail ~= nil) and (Tail:find(".", 1, true) ~= nil)) then
		if (not IsIPv4(Tail)) then
			return false
		end
		Text = Text:sub(1, #Text - #Tail) .. "0:0"
	end

	local DoubleAt = Text:find("::", 1, true)
	if (DoubleAt == nil) then
		return (CountHexGroups(Text) == 8)
	end

	if (Text:find("::", DoubleAt + 1, true) ~= nil) then
		-- More than one "::":
		return false
	end
	local Left = Text:sub(1, DoubleAt - 1)
	local Right = Text:sub(DoubleAt + 2)
	local LeftCount = 0
	local RightCount = 0
	if (Left ~= "") then
		LeftCount = CountHexGroups(Left)
		if (LeftCount < 0) then
			return false
		end
	end
	if (Right ~= "") then
		RightCount = CountHexGroups(Right)
		if (RightCount < 0) then
			return false
		end
	end
	-- "::" stands for at least one zero group, so the explicit groups must leave a gap:
	return (LeftCount + RightCount <= 7)
end



--- Returns true if a_Token is a valid IPv4 or IPv6 address (spec section 2.5).
function IsValidIPAddress(a_Token)
	if ((a_Token == nil) or (a_Token == "")) then
		return false
	end
	if (a_Token:find(":", 1, true) ~= nil) then
		return IsIPv6(a_Token)
	end
	return IsIPv4(a_Token)
end



--- Parses the /ban-ip arguments. Returns { Target = <address|name>, Reason = <text> } or nil + usage.
function ParseBanIPArguments(a_Split)
	if ((a_Split[2] == nil) or (a_Split[2] == "")) then
		return nil, "Usage: " .. a_Split[1] .. " <address|name> [reason ...]"
	end

	local Reason = DEFAULT_BAN_REASON
	if ((a_Split[3] ~= nil) and (a_Split[3] ~= "")) then
		Reason = table.concat(a_Split, " ", 3)
	end
	return { Target = a_Split[2], Reason = Reason }
end



--- Parses the /banlist argument. Returns "ips" or "players", or nil + usage.
function ParseBanlistKind(a_Token)
	if (a_Token == "ips") then
		return "ips"
	end
	if (a_Token == "players") then
		return "players"
	end
	return nil, "Usage: /banlist <ips|players>"
end



--- Renders the /banlist output for the given kind and entries (spec section 2.2).
function FormatBanlist(a_Kind, a_Entries)
	if (#a_Entries == 0) then
		if (a_Kind == "ips") then
			return "There are no banned IP addresses"
		end
		return "There are no banned players"
	end

	local Noun = "banned players"
	if (a_Kind == "ips") then
		Noun = "banned IP addresses"
	end
	return string.format("There are %d %s: %s", #a_Entries, Noun, table.concat(a_Entries, ", "))
end



--- Parses the /pardon argument. Returns { Name = <name> } or nil + usage.
function ParsePardonArguments(a_Split)
	if ((a_Split[2] == nil) or (a_Split[2] == "")) then
		return nil, "Usage: " .. a_Split[1] .. " <name>"
	end
	if ((a_Split[3] ~= nil) and (a_Split[3] ~= "")) then
		return nil, "Usage: " .. a_Split[1] .. " <name>"
	end
	return { Name = a_Split[2] }
end



--- Parses the /pardon-ip argument. Returns { IP = <address> } or nil + reason.
function ParsePardonIPArguments(a_Split)
	if ((a_Split[2] == nil) or (a_Split[2] == "")) then
		return nil, "Usage: " .. a_Split[1] .. " <address>"
	end
	if ((a_Split[3] ~= nil) and (a_Split[3] ~= "")) then
		return nil, "Usage: " .. a_Split[1] .. " <address>"
	end
	if (not IsValidIPAddress(a_Split[2])) then
		return nil, "Invalid IP address \"" .. a_Split[2] .. "\""
	end
	return { IP = a_Split[2] }
end
