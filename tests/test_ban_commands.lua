-- test_ban_commands.lua
--
-- Table-driven tests for the pure parts of Core's vanilla ban commands (/ban-ip, /banlist, /pardon,
-- /pardon-ip): argument parsing, IP-address validation and the /banlist text.
--
-- Verified specification: specs/commands/vanilla-1.12.2-ban-commands.md (parent repository).
-- The cases pin what is easy to get wrong: /ban-ip takes an IP *or an online player's name* and
-- records a default reason, /banlist requires exactly ips|players (a Brigadier literal, therefore
-- case-sensitive), and /pardon-ip insists on a valid address while /pardon does not.
--
-- Invariants:
--   * The functions in command_ban.lua are pure: they never touch a world, a player or the database.
--   * An address is accepted only if it is a valid IPv4 dotted quad or an IPv6 textual form.
--   * A refused argument yields a reason that names the usage or the offending value.
--
-- Run with:  lua tests/test_ban_commands.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../command_ban.lua")

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






-- IP validation --------------------------------------------------------------

local ValidAddresses =
{
	"0.0.0.0",
	"127.0.0.1",
	"192.168.0.1",
	"255.255.255.255",
	"::",
	"::1",
	"2001:db8::1",
	"2001:0db8:0000:0000:0000:ff00:0042:8329",
	"1:2:3:4:5:6:7:8",
	"::ffff:192.0.2.1",
	"1:2:3:4:5:6:192.0.2.1",
	"fe80::1",
	"1:2:3:4:5:6:7::",
}

for _, Address in ipairs(ValidAddresses) do
	Check(IsValidIPAddress(Address), "accepts the valid address " .. Address)
end

local InvalidAddresses =
{
	"",
	"256.0.0.1",
	"1.2.3",
	"1.2.3.4.5",
	"01.2.3.4",
	"1.2.3.-1",
	"1.2.3.4 ",
	"localhost",
	"1:2:3:4:5:6:7",
	"1:2:3:4:5:6:7:8:9",
	"1::2::3",
	"1:::2",
	"fe80::1%eth0",
	"gggg::1",
	":1:2:3:4:5:6:7",
	"12345::",
	"::ffff:192.0.2.256",
	"1:2:3:4:5:6:7:8::",
}

for _, Address in ipairs(InvalidAddresses) do
	Check(not IsValidIPAddress(Address), "rejects the invalid address '" .. Address .. "'")
end

Check(not IsValidIPAddress(nil), "rejects a nil address")

-- /banlist argument ----------------------------------------------------------

CheckEquals(ParseBanlistKind("ips"), "ips", "banlist accepts ips")
CheckEquals(ParseBanlistKind("players"), "players", "banlist accepts players")
CheckEquals(ParseBanlistKind("IPs"), nil, "banlist is case-sensitive (Brigadier literal)")
CheckEquals(ParseBanlistKind(nil), nil, "banlist requires its argument")
local Kind, Reason = ParseBanlistKind("foo")
CheckEquals(Kind, nil, "banlist refuses an unknown argument")
Check(Reason ~= nil and Reason:find("Usage:", 1, true) ~= nil, "banlist explains the usage")

-- /banlist output ------------------------------------------------------------

CheckEquals(FormatBanlist("players", {}), "There are no banned players", "empty player banlist")
CheckEquals(FormatBanlist("ips", {}), "There are no banned IP addresses", "empty IP banlist")
CheckEquals(FormatBanlist("players", { "Alice", "Bob" }),
	"There are 2 banned players: Alice, Bob", "player banlist with entries")
CheckEquals(FormatBanlist("ips", { "1.2.3.4" }),
	"There are 1 banned IP addresses: 1.2.3.4", "IP banlist with one entry")

-- /ban-ip arguments ----------------------------------------------------------

local Args, Usage = ParseBanIPArguments({ "ban-ip" })
CheckEquals(Args, nil, "ban-ip requires its target")
Check(Usage ~= nil and Usage:find("<address|name>", 1, true) ~= nil, "ban-ip explains the usage")

Args = ParseBanIPArguments({ "ban-ip", "1.2.3.4" })
Check(Args ~= nil, "ban-ip parses an address")
CheckEquals(Args.Target, "1.2.3.4", "ban-ip keeps the target")
CheckEquals(Args.Reason, "Banned by an operator.", "ban-ip uses the default reason")

Args = ParseBanIPArguments({ "ban-ip", "Alice", "griefing", "the", "spawn" })
CheckEquals(Args.Reason, "griefing the spawn", "ban-ip joins the reason tokens")

-- /pardon arguments ----------------------------------------------------------

Args, Usage = ParsePardonArguments({ "pardon" })
CheckEquals(Args, nil, "pardon requires a name")
Check(Usage ~= nil and Usage:find("<name>", 1, true) ~= nil, "pardon explains the usage")

Args = ParsePardonArguments({ "pardon", "Alice", "extra" })
CheckEquals(Args, nil, "pardon refuses extra arguments")

Args = ParsePardonArguments({ "pardon", "Alice" })
Check(Args ~= nil and Args.Name == "Alice", "pardon parses a name")

-- /pardon-ip arguments -------------------------------------------------------

Args, Usage = ParsePardonIPArguments({ "pardon-ip" })
CheckEquals(Args, nil, "pardon-ip requires an address")
Check(Usage ~= nil and Usage:find("<address>", 1, true) ~= nil, "pardon-ip explains the usage")

Args, Usage = ParsePardonIPArguments({ "pardon-ip", "not-an-ip" })
CheckEquals(Args, nil, "pardon-ip refuses an invalid address")
Check(Usage ~= nil and Usage:find("Invalid IP address", 1, true) ~= nil, "pardon-ip names the bad value")

Args, Usage = ParsePardonIPArguments({ "pardon-ip", "1.2.3.4", "extra" })
CheckEquals(Args, nil, "pardon-ip refuses extra arguments")

Args = ParsePardonIPArguments({ "pardon-ip", "::1" })
Check(Args ~= nil and Args.IP == "::1", "pardon-ip accepts an IPv6 address")

print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
