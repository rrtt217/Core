-- test_advancement_command.lua
--
-- Tests for Core's vanilla 1.12.2 /advancement: argument parsing, tree modes, target handling and
-- the feedback lines. The traversal itself is cPlayer's job (C++), so the player here is a stub that
-- records the (id, mode, criterion) tuple it receives.
--
-- Spec: specs/commands/vanilla-1.12.2-advancement-command.md (parent repository).
-- Run:  lua tests/test_advancement_command.lua   (from the plugin folder)

local ScriptDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
dofile(ScriptDir .. "/../cmd_advancement.lua")

-- luacheck: ignore 131
-- luacheck: new globals ResolveTargets MakeSelectorContext ApplyToTargets SendMessageSuccess SendMessageFailure
-- luacheck: globals HandleAdvancementCommand HandleConsoleAdvancement

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



-- Stubs --------------------------------------------------------------------

local Messages = {}
local CurrentTargets = {}

function SendMessageSuccess(_, a_Message)
	table.insert(Messages, { IsSuccess = true, Text = a_Message })
end

function SendMessageFailure(_, a_Message)
	table.insert(Messages, { IsSuccess = false, Text = a_Message })
end

function MakeSelectorContext()
	return {}
end

function ResolveTargets(a_Token)
	if (a_Token == "P") then
		return { CurrentTargets.P }
	end
	if (a_Token == "none") then
		return {}
	end
	return nil, "No player was found"
end

function ApplyToTargets(a_Targets, a_Fn)
	for _, Target in ipairs(a_Targets) do
		a_Fn(Target)
	end
end



local function MakePlayer(a_Name)
	local Player = {
		Name = a_Name,
		GrantCalls = {},
		RevokeCalls = {},
	}
	function Player:GetName()
		return self.Name
	end
	function Player:IsValidAdvancement(a_ID)
		return (a_ID == "a/root") or (a_ID == "a/child")
	end
	function Player:GrantAdvancementTree(a_ID, a_Mode, a_Criterion)
		table.insert(self.GrantCalls, { ID = a_ID, Mode = a_Mode, Criterion = a_Criterion })
		return 1
	end
	function Player:RevokeAdvancementTree(a_ID, a_Mode, a_Criterion)
		table.insert(self.RevokeCalls, { ID = a_ID, Mode = a_Mode, Criterion = a_Criterion })
		return 1
	end
	function Player:HasAdvancement(a_ID)
		return (a_ID == "a/root")
	end
	function Player:HasAdvancementCriterion(a_ID, a_Criterion)
		return (a_ID == "a/root") and (a_Criterion == "c")
	end
	return Player
end



local function Reset()
	Messages = {}
	CurrentTargets = { P = MakePlayer("Alice") }
	return CurrentTargets.P
end



-- Handlers ------------------------------------------------------------------

do
	local P = Reset()
	local Handled, Message, Count = HandleAdvancementCommand({ "/advancement", "grant", "P", "only", "a/root" }, P)
	Check(Handled, "grant only is handled")
	CheckEquals(Count, 1, "grant only reports one change")
	CheckEquals(#P.GrantCalls, 1, "grant only calls the tree once")
	CheckEquals(P.GrantCalls[1].ID, "a/root", "grant only passes the id")
	CheckEquals(P.GrantCalls[1].Mode, "only", "grant only passes the mode")
	CheckEquals(P.GrantCalls[1].Criterion, "", "grant only defaults the criterion to empty")
	CheckEquals(Messages[1].Text, "Granted a/root to Alice", "grant only feedback")
	Check(Messages[1].IsSuccess, "grant only feedback is a success")
end

do
	local P = Reset()
	local _, _, Count = HandleAdvancementCommand({ "/advancement", "grant", "P", "until", "a/child", "c" }, P)
	CheckEquals(Count, 1, "grant until with a criterion succeeds")
	CheckEquals(P.GrantCalls[1].Mode, "until", "until mode is passed through")
	CheckEquals(P.GrantCalls[1].Criterion, "c", "criterion is passed through")
	CheckEquals(Messages[1].Text, "Granted a/child (c) to Alice", "criterion is shown in the feedback")
end

do
	local P = Reset()
	HandleAdvancementCommand({ "/advancement", "grant", "P", "through", "a/root" }, P)
	CheckEquals(P.GrantCalls[1].Mode, "through", "through mode is accepted")
end

do
	local P = Reset()
	HandleAdvancementCommand({ "/advancement", "grant", "P", "everything" }, P)
	CheckEquals(P.GrantCalls[1].ID, "", "everything passes an empty id")
	CheckEquals(P.GrantCalls[1].Mode, "everything", "everything mode is passed")
	CheckEquals(Messages[1].Text, "Granted all advancements to Alice", "everything feedback")
end

do
	local P = Reset()
	local _, _, Count = HandleAdvancementCommand({ "/advancement", "revoke", "P", "only", "a/child" }, P)
	CheckEquals(Count, 1, "revoke succeeds")
	CheckEquals(P.RevokeCalls[1].ID, "a/child", "revoke passes the id")
	CheckEquals(Messages[1].Text, "Revoked a/child from Alice", "revoke feedback")
end

do
	local P = Reset()
	local _, _, Count = HandleAdvancementCommand({ "/advancement", "test", "P", "a/root" }, P)
	CheckEquals(Count, 1, "test reports a held advancement")
	CheckEquals(Messages[1].Text, "Alice has a/root", "test success feedback")
	Check(Messages[1].IsSuccess, "test success is a success")

	Messages = {}
	_, _, Count = HandleAdvancementCommand({ "/advancement", "test", "P", "a/child" }, P)
	CheckEquals(Count, 0, "test reports a missing advancement")
	CheckEquals(Messages[1].Text, "Alice does not have a/child", "test failure feedback")
	Check(not Messages[1].IsSuccess, "test failure is a failure")

	Messages = {}
	_, _, Count = HandleAdvancementCommand({ "/advancement", "test", "P", "a/root", "c" }, P)
	CheckEquals(Count, 1, "test checks the criterion")
end

do
	local P = Reset()
	local _, _, Count = HandleAdvancementCommand({ "/advancement", "grant", "P", "only", "x/y" }, P)
	CheckEquals(Count, 0, "unknown advancement fails")
	CheckEquals(#P.GrantCalls, 0, "unknown advancement reaches no tree call")
	CheckEquals(Messages[1].Text, "Unknown advancement x/y", "unknown advancement feedback")
	Check(not Messages[1].IsSuccess, "unknown advancement is a failure")
end

do
	local P = Reset()
	local _, _, Count = HandleAdvancementCommand({ "/advancement", "grant", "P", "sideways", "a/root" }, P)
	CheckEquals(Count, 0, "unknown mode fails")
	CheckEquals(#P.GrantCalls, 0, "unknown mode reaches no tree call")
	Check(string.find(Messages[1].Text, "Usage:", 1, true) ~= nil, "unknown mode prints the usage")
end

do
	local P = Reset()
	local _, _, Count = HandleAdvancementCommand({ "/advancement", "grant", "none", "only", "a/root" }, P)
	CheckEquals(Count, 0, "empty target list fails")
	CheckEquals(#P.GrantCalls, 0, "empty target list reaches no tree call")
end

do
	Reset()
	local Handled, Message, Count = HandleConsoleAdvancement({ "/advancement", "test", "P", "a/root" }, nil, nil, nil)
	Check(Handled, "console handler is handled")
	CheckEquals(Count, 1, "console handler reports the success count")
	CheckEquals(Message, "Alice has a/root", "console handler returns the feedback line")
end



print(string.format("%d passed, %d failed", NumPassed, NumFailed))
if (NumFailed > 0) then
	os.exit(1)
end
