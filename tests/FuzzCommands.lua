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
			-- /execute and /testforblock arguments (relative coordinates, the detect form with its "-1" data
			-- value, and a bare block name):
			"~",
			"~-1",
			"detect",
			"-1",
			"stone",
			-- /title, /particle and /playsound arguments (the three subcommand spellings of /title, a valid
			-- particle name, a valid sound source, and a sound event name):
			"title",
			"clear",
			"particle",
			"explode",
			"master",
			"mob.pig.say",
		},
		-- /execute needs five arguments before its command body, so short argument lists can only reach its
		-- usage message; six is the smallest length that reaches the real parsing:
		maxLen = 6,  -- Max number of elements chosen from "choices"
	},
}
