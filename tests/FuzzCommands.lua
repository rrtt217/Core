-- FuzzCommands.lua

-- Defines a scenario for fuzzing the commands





scenario
{
	name = "Fuzz all commands",
	world  -- Create a world
	{
		name = "world",
	},
	initializePlugin(),
	connectPlayer  -- Simulate a player connection
	{
		name = "player1",
		worldName = "world",
	},
	connectPlayer
	{
		name = "player2",
		worldName = "world",
	},
	fuzzAllCommands  -- fuzz all registered commands
	{
		playerName = "player1",
		choices =
		{
			"world",
			"first",
			"player1",
			"player2",
			"1",
			-- Target selectors, including malformed input (must not crash):
			"@a",
			"@p",
			"@s",
			"@e[type=cow]",
			"@e[type=!player]",
			"@a[c=1]",
			"@a[",
		},
		maxLen = 1,  -- Max number of elements chosen from "choices"
	},
}
