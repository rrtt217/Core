
-- Info.lua

-- Implements the g_PluginInfo standard plugin description

g_PluginInfo = 
{
	Name = "Core",
	SourceLocation = "https://github.com/cuberite/Core",
	Description = [[Implements some of the basic commands needed to run a simple server.]],
	
	Commands =
	{
		["/about"] = 
		{
			Alias = "/abt",
			Permission = "core.version",
			Handler = HandleVersionCommand,
			HelpString = "Shows the version of the server software.",
		},

		["/ban"] = 
		{
			Permission = "core.ban",
			Handler = HandleBanCommand,
			HelpString = "Bans a player.",
		},

		["/ban-ip"] =
		{
			Permission = "core.ban-ip",
			Handler = HandleBanIPCommand,
			HelpString = "Bans an IP address, or the IP address of an online player.",
		},

		["/banlist"] =
		{
			Permission = "core.banlist",
			Handler = HandleBanlistCommand,
			HelpString = "Lists the banned IP addresses or the banned players.",
			ParameterCombinations =
			{
				{
					Params = "ips",
					Help = "Lists the banned IP addresses.",
				},
				{
					Params = "players",
					Help = "Lists the banned players.",
				},
			},
		},

		["/clear"] = 
		{
			Permission = "core.clear",
			Handler = HandleClearCommand,
			HelpString = "Clears the inventory of a player.",
		},

		["/clone"] =
		{
			Permission = "core.clone",
			Handler = HandleCloneCommand,
			HelpString = "Clones a region of blocks to another place.",
			ParameterCombinations =
			{
				{
					Params = "x1 y1 z1 x2 y2 z2 x y z [maskMode] [cloneMode] [TileName] [dataValue]",
					Help = "Clones the source region to the destination corner.",
				},
			},
		},

		["/do"] = 
		{
			Permission = "core.do",
			Handler = HandleDoCommand,
			HelpString = "Runs a command as a player.",
		},

		["/difficulty"] = 
		{
			Permission = "core.difficulty",
			Handler = HandleDifficultyCommand,
			HelpString = "Changes the difficulty level of the world you're located in.",
		},

		["/effect"] = 
		{
			Permission = "core.effect",
			Handler = HandleEffectCommand,
			HelpString = "Adds an effect to players or other entities (player name or target selector).",
		},

		["/enchant"] = 
		{
			Permission = "core.enchant",
			Handler = HandleEnchantCommand,
			HelpString = "Adds an enchantment to a specified player's held item.",
			ParameterCombinations =
			{
				{
					Params = "player enchantmentID",
					Help = "Adds the specified enchantment to the specified player's currently held item.",
				},
				{
					Params = "player enchantmentID level",
					Help = "Adds the specified enchantment of the given level to the specified player's currently held item.",
				},
			},
		},

		["/execute"] = 
		{
			Permission = "core.execute",
			Handler = HandleExecuteCommand,
			HelpString = "Runs a command on behalf of another entity, from that entity's position.",
			ParameterCombinations =
			{
				{
					Params = "entity x y z command",
					Help = "Runs the command as the selected entity, at the given position (~ is relative to it).",
				},
				{
					Params = "entity x y z detect x2 y2 z2 block dataValue command",
					Help = "Runs the command only when the block at x2 y2 z2 (relative to x y z) is the given block.",
				},
			},
		},

		["/fill"] =
		{
			Permission = "core.fill",
			Handler = HandleFillCommand,
			HelpString = "Fills a region of blocks with the given block.",
			ParameterCombinations =
			{
				{
					Params = "x1 y1 z1 x2 y2 z2 block [dataValue] [oldBlockHandling]",
					Help = "Fills the region; oldBlockHandling is destroy, hollow, keep, outline or replace.",
				},
			},
		},

		["/function"] =
		{
			Permission = "core.function",
			Handler = HandleFunctionCommand,
			HelpString = "Runs the commands of a .mcfunction file from the world's data/functions folder.",
			ParameterCombinations =
			{
				{
					Params = "function",
					Help = "Runs the function (namespace:path, the namespace defaults to minecraft).",
				},
				{
					Params = "function if selector",
					Help = "Runs the function only when the selector matches at least one entity.",
				},
				{
					Params = "function unless selector",
					Help = "Runs the function only when the selector matches no entity.",
				},
			},
		},

		["/give"] = 
		{
			Permission = "core.give",
			Handler = HandleGiveCommand,
			HelpString = "Gives an item to a player.",
			ParameterCombinations = 
			{
				{
					Params = "player item",
					Help = "Gives the player one of the specified item.",
				},
				{
					Params = "player item amount",
					Help = "Gives the player the given amount of the specified item.",
				},
				{
					Params = "player item amount data",
					Help = "Gives the player the given amount of the specified item with the given data value.",
				},
				{
					Params = "player item amount data dataTag",
					Help = "Gives the player the given amount of the specified item with the given data value and DataTag.",
				},
			},
		},

		["/gamemode"] = 
		{
			Alias = "/gm",
			Permission = "core.changegm",
			Handler = HandleChangeGMCommand,
			HelpString = "Changes a player's gamemode.",
			ParameterCombinations = 
			{
				{
					Params = "gamemode",
					Help = "Changes your own gamemode.",
				},
				{
					Params = "gamemode player",
					Help = "Changes the gamemode of the specified player, rather then your own.",
				},
			},
		},

		["/help"] = 
		{
			Alias = "/?",
			Permission = "core.help",
			Handler = HandleHelpCommand,
			HelpString = "Shows available commands.",
		},

		["/ienchant"] = 
		{
			Permission = "core.enchant.self",
			Handler = HandleEnchantCommand,
			HelpString = "Adds an enchantment to an item.",
			ParameterCombinations =
			{
				{
					Params = "enchantmentID",
					Help = "Adds the specified enchantment to the currently held item.",
				},
				{
					Params = "enchantmentID level",
					Help = "Adds the specified enchantment of the given level to the currently held item.",
				},
			},
		},

		["/item"] = 
		{
			Alias = "/i",
			Permission = "core.item",
			Handler = HandleItemCommand,
			HelpString = "Gives your player an item.",
			ParameterCombinations = 
			{
				{
					Params = "item",
					Help = "Gives the caller one of the specified item.",
				},
				{
					Params = "item amount",
					Help = "Gives the caller the given amount of the specified item.",
				},
				{
					Params = "item amount data",
					Help = "Gives the caller the given amount of the specified item with the given data value.",
				},
				{
					Params = "item amount data dataTag",
					Help = "Gives the caller the given amount of the specified item with the given data value and DataTag.",
				},
			},
		},

		["/kick"] = 
		{
			Permission = "core.kick",
			Handler = HandleKickCommand,
			HelpString = "Kicks a player.",
		},

		["/kill"] = 
		{
			Permission = "core.kill",
			Handler = HandleKillCommand,
			HelpString = "Kills a player.",
		},

		["/list"] = 
		{
			Permission = "core.list",
			Handler = HandleListCommand,
			HelpString = "Shows a list of connected players.",
		},

		["/listgroups"] =
		{
			Permission = "core.listgroups",
			Handler = HandleListGroupsCommand,
			HelpString = "Shows a list of the available groups.",
			Alias = "/groups",
		},

		["/listranks"] =
		{
			Permission = "core.listranks",
			Handler = HandleListRanksCommand,
			HelpString = "Shows a list of the available ranks.",
			Alias = "/ranks",
		},

		["/me"] = 
		{
			Permission = "core.me",
			Handler = HandleMeCommand,
			HelpString = "Broadcasts what you are doing.",
		},

		["/motd"] = 
		{
			Permission = "core.motd",
			Handler = HandleMOTDCommand,
			HelpString = "Shows the message of the day.",
		},

		["/numchunks"] =
		{
			Permission = "core.numchunks",
			Handler =  HandleNumChunksCommand,
			HelpString = "Shows number of chunks currently loaded.",
		},

		["/plugins"] = 
		{
			Alias = "/pl",
			Permission = "core.plugins",
			Handler = HandlePluginsCommand,
			HelpString = "Shows a list of the plugins.",
			ParameterCombinations =
			{
				{
					Params = "[<status>] [<status>] ...",
					Help = "Filters the plugin list to show only the plugins with the specified status (default: loaded).",
				},
			},
		},

		["/portal"] =
		{
			Alias = "/world",
			Permission = "core.portal",
			Handler = HandlePortalCommand,
			HelpString = "Moves your player to a different world.",
		},
		
		["/r"] =
		{
			Permission = "core.tell",
			Handler = HandleRCommand,
			HelpString = "Replies to the latest private message you received.",
		},
        
		["/rank"] =
		{
			Permission = "core.rank",
			Handler = HandleRankCommand,
			HelpString = "Shows or sets a player's rank.",
		},

		["/op"] =
		{
			Permission = "core.rank",
			Handler = HandleOpCommand,
			HelpString = "Add a player to the administrator rank.",
		},

		["/pardon"] =
		{
			Permission = "core.pardon",
			Handler = HandlePardonCommand,
			HelpString = "Removes a player from the banlist.",
		},

		["/pardon-ip"] =
		{
			Permission = "core.pardon-ip",
			Handler = HandlePardonIPCommand,
			HelpString = "Removes an IP address from the banlist.",
		},

		["/particle"] =
		{
			Permission = "core.particle",
			Handler = HandleParticleCommand,
			HelpString = "Creates particles at the given position.",
			ParameterCombinations =
			{
				{
					Params = "name x y z xd yd zd speed",
					Help = "Creates the named particle at the given position, with the given spread and speed.",
				},
				{
					Params = "name x y z xd yd zd speed count",
					Help = "Creates the given number of particles (0 creates a single particle).",
				},
				{
					Params = "name x y z xd yd zd speed count normal|force",
					Help = "Also sets the display mode, normal or force.",
				},
			},
		},

		["/players"] =
		{
			Permission = "core.players",
			Handler =  HandlePlayersCommand,
			HelpString = "Shows a list of all connected players.",
		},

		["/playsound"] =
		{
			Permission = "core.playsound",
			Handler = HandlePlaysoundCommand,
			HelpString = "Plays a sound for the given players (player name or target selector).",
			ParameterCombinations =
			{
				{
					Params = "sound source player",
					Help = "Plays the sound at the player's own position.",
				},
				{
					Params = "sound source player x y z",
					Help = "Plays the sound from the given position (~ is relative to the command).",
				},
				{
					Params = "sound source player x y z volume pitch minimumVolume",
					Help = "Also sets the volume, the pitch, and the volume heard by players out of range.",
				},
			},
		},

		["/regen"] =
		{
			Permission = "core.regen",
			Handler = HandleRegenCommand,
			HelpString = "Regenerates a chunk.",
		},

		["/reload"] = 
		{
			Permission = "core.reload",
			Handler = HandleReloadCommand,
			HelpString = "Reloads all plugins.",
		},

		["/save-all"] = 
		{
			Permission = "core.save-all",
			Handler = HandleSaveAllCommand,
			HelpString = "Saves all worlds.",
		},

		["/save-off"] =
		{
			Permission = "core.save-off",
			Handler = HandleSaveOffCommand,
			HelpString = "Disables automatic saving of all worlds.",
		},

		["/save-on"] =
		{
			Permission = "core.save-on",
			Handler = HandleSaveOnCommand,
			HelpString = "Enables automatic saving of all worlds.",
		},

		["/say"] = 
		{
			Permission = "core.say",
			Handler = HandleSayCommand,
			HelpString = "Sends a message in the chat to other players.",
		},

		["/scoreboard"] =
		{
			HelpString = "Manages and displays scores for various scoreboard objectives. ",
			Subcommands =
			{
				objectives =
				{
					HelpString = "Manage Objectives",
					Permission = "core.scoreboard.objectives",
					Handler = HandleScoreboardObjectivesCommand,
					ParameterCombinations =
					{
						{
							Params = "list",
							Help = "List all existing objectives with their display names and criteria.",
						},
						{
							Params = "add objective criteria displayName",
							Help = "Create a new objective with the given internal objective name, specified criterion, and the optional display name.",
						},
						{
							Params = "remove objective",
							Help = "Delete the named objective from the scoreboard system.",
						},
						{
							Params = "setdisplay slot objective",
							Help = "Display score info for the objective in the given slot.",
						},
						{
							Params = "modify objective displayname name",
							Help = "Change the display name of the scoreboard in display slots.",
						},
						-- Not implemented yet
						-- {
						-- 	Params = "modify objective rendertype (hearts|integer)",
						-- 	Help = "Change the display format for scores in the tab player list.",
						-- },
					},
				},
				players =
				{
					HelpString = "Manage Players",
					Permission = "core.scoreboard.players",
					Handler = HandleScoreboardPlayersCommand,
					ParameterCombinations =
					{
						-- Not Implemented yet
						-- {
						-- 	Params = "list",
						-- 	Help = "Lists all score holders which are tracked in some way by the scoreboard system.",
						-- },
						{
							Params = "list player",
							Help = "Lists all score holders which are tracked in some way by the scoreboard system for a player.",
						},
						{
							Params = "get player objective",
							Help = "Return the scoreboard value.",
						},
						{
							Params = "set player objective score",
							Help = "Set the target's scores in the given objective, overwriting any previous score.",
						},
						{
							Params = "add player objective score",
							Help = "Increments the target's scores in the given objective.",
						},
						{
							Params = "remove player objective score",
							Help = "Decrements the target's scores in the given objective.",
						},
						{
							Params = "reset player",
							Help = "Deletes all scores for the targets",
						},
						{
							Params = "reset player objective",
							Help = "Delete score for the targets in the specified objective",
						},
						{
							Params = "operation targetPlayer targetObjective operation sourcePlayer sourceObjective",
							Help = "Applies an arithmetic operation altering the target's scores in the target objective, using source's scores in the source objective as input",
						},
					},
				},
				teams =
				{
					HelpString = "Manage Teams",
					Permission = "core.scoreboard.teams",
					Handler = HandleScoreboardTeamsCommand,
					ParameterCombinations =
					{
						{
							Params = "add name [display name...]",
							Help = "Create a new team with the given internal name and the optional display name.",
						},
						{
							Params = "remove name",
							Help = "Delete the named team from the scoreboard system.",
						},
						{
							Params = "empty name",
							Help = "Remove all members from the named team.",
						},
						{
							Params = "join team [targets...]",
							Help = "Put the given targets on the team; without targets, the command's player joins.",
						},
						{
							Params = "leave [targets...]",
							Help = "Remove the given targets from their teams; without targets, the command's player leaves.",
						},
						{
							Params = "list [team]",
							Help = "List all teams with their display names and member counts, or the named team.",
						},
						{
							Params = "option team option value",
							Help = "Change a team option (friendlyfire, seeFriendlyInvisibles).",
						},
					},
				},
			},
		},

		["/seed"] =
		{
			Permission = "core.seed",
			Handler = HandleSeedCommand,
			HelpString = "Shows the seed of the given world name or current world, if not given.",
		},

		["/setblock"] =
		{
			Permission = "core.setblock",
			Handler = HandleSetBlockCommand,
			HelpString = "Changes a single block.",
			ParameterCombinations =
			{
				{
					Params = "x y z block [dataValue] [oldBlockHandling]",
					Help = "Places the block; oldBlockHandling is destroy, keep or replace.",
				},
			},
		},

		["/setspawn"] = 
		{
			Permission = "core.setspawn",
			Handler = HandleSetSpawnCommand,
			HelpString = "Changes the world's spawn point.",
		},

		["/setworldspawn"] =
		{
			Permission = "core.setworldspawn",
			Handler = HandleSetWorldspawnCommand,
			HelpString = "Sets the spawn point of the world the command runs in (vanilla name).",
			ParameterCombinations =
			{
				{
					Params = "",
					Help = "Sets the world spawn to the command's position.",
				},
				{
					Params = "<x> <y> <z>",
					Help = "Sets the world spawn to the given coordinates (relative coordinates are allowed).",
				},
			},
		},

		["/spawn"] = 
		{
			Permission = "core.spawn",
			Handler = HandleSpawnCommand,
			HelpString = "Returns a player to the spawn point.",
		},

		["/spawnpoint"] = 
		{
			Permission = "core.spawnpoint",
			Handler = HandleSpawnPointCommand,
			HelpString = "Sets the spawn point for a player.",
		},

		["/spreadplayers"] =
		{
			Permission = "core.spreadplayers",
			Handler = HandleSpreadplayersCommand,
			HelpString = "Spreads the targets randomly on the surface around the given centre.",
			ParameterCombinations =
			{
				{
					Params = "x z spreadDistance maxRange respectTeams player ...",
					Help = "Spreads the targets on the surface of a square around (x, z).",
				},
			},
		},

		["/stopsound"] =
		{
			Permission = "core.stopsound",
			Handler = HandleStopsoundCommand,
			HelpString = "Stops sounds for the given players (player name or target selector).",
			ParameterCombinations =
			{
				{
					Params = "player",
					Help = "Stops every sound the players can hear.",
				},
				{
					Params = "player source",
					Help = "Stops the sounds of one category (master, music, record, weather, block, hostile, neutral, player, ambient, voice).",
				},
				{
					Params = "player source sound",
					Help = "Stops one sound event, for example minecraft:weather.rain.",
				},
			},
		},

		["/stop"] = 
		{
			Permission = "core.stop",
			Handler = HandleStopCommand,
			HelpString = "Stops the server.",
		},

		["/sudo"] = 
		{
			Permission = "core.sudo",
			Handler = HandleSudoCommand,
			HelpString = "Runs a command as a player, ignoring permissions.",
		},

		["/summon"] = 
		{
			Permission = "core.summon",
			Handler = HandleSummonCommand,
			HelpString = "Summons an entity in the world.",
		},

		["/teleport"] =
		{
			Permission = "core.teleport",
			Handler = HandleTeleportCommand,
			HelpString = "Teleports entities to the given position (relative coordinates use the command position).",
			ParameterCombinations =
			{
				{
					Params = "target x y z",
					Help = "Teleports the targets to the given position.",
				},
				{
					Params = "target x y z y-rot x-rot",
					Help = "Teleports the targets to the given position and rotation.",
				},
			},
		},

		["/tell"] = 
		{
			Permission = "core.tell",
			Alias = "/msg",
			Handler = HandleTellCommand,
			HelpString = "Sends a private message to a player.",
		},

		["/tellraw"] =
		{
			Permission = "core.tellraw",
			Handler = HandleTellrawCommand,
			HelpString = "Sends a raw JSON text component to the given players (player name or target selector).",
			ParameterCombinations =
			{
				{
					Params = "player message",
					Help = "Sends the JSON text component, for example {\"text\":\"Hi there!\",\"bold\":true}.",
				},
			},
		},

		["/testfor"] = 
		{
			Permission = "core.testfor",
			Handler = HandleTestforCommand,
			HelpString = "Counts the entities (player name or target selector) matching the given conditions.",
		},

		["/testforblock"] = 
		{
			Permission = "core.testforblock",
			Handler = HandleTestforblockCommand,
			HelpString = "Tests whether the block at the given position is the given block.",
			ParameterCombinations =
			{
				{
					Params = "x y z block",
					Help = "Tests for the given block (name, e.g. minecraft:stone) at x y z, with any data value.",
				},
				{
					Params = "x y z block dataValue",
					Help = "Tests for the given block and data value (-1 matches any data value) at x y z.",
				},
			},
		},

		["/testforblocks"] =
		{
			Permission = "core.testforblocks",
			Handler = HandleTestforblocksCommand,
			HelpString = "Tests whether two regions of blocks match.",
			ParameterCombinations =
			{
				{
					Params = "x1 y1 z1 x2 y2 z2 x y z [all|masked]",
					Help = "Compares the source region with the destination region.",
				},
			},
		},

		["/time"] = 
		{
			HelpString = "Sets or displays the time.",
			Subcommands = 
			{
				day = 
				{
					HelpString = "Sets the time to day.",
					Permission = "core.time.set",
					Handler = HandleSpecialTimeCommand,
					ParameterCombinations = 
					{
						{
							Params = "world",
							Help = "Sets the time in the specified world, rather than the current world.",
						},
					},
				},
				night = 
				{
					HelpString = "Sets the time to night.",
					Permission = "core.time.set",
					Handler = HandleSpecialTimeCommand,
					ParameterCombinations = 
					{
						{
							Params = "world",
							Help = "Sets the time in the specified world, rather than the current world.",
						},
					},
				},
				set = 
				{
					HelpString = "Sets the time to a given value.",
					Permission = "core.time.set",
					Handler = HandleSetTimeCommand,
					ParameterCombinations = 
					{
						{
							Params = "value",
							Help = "Sets the time to the given value.",
						},
						{
							Params = "day",
							Help = "Sets the time to day.",
						},
						{
							Params = "night",
							Help = "Sets the time to night.",
						},
						{
							Params = "value world",
							Help = "Sets the time to the given value in the specified world, rather than the current world.",
						},
						{
							Params = "day world",
							Help = "Sets the time to day in the specified world, rather than the current world.",
						},
						{
							Params = "night world",
							Help = "Sets the time to night in the specified world, rather than the current world.",
						},
					},
				},
				add = 
				{
					HelpString = "Adds a given value to the current time.",
					Permission = "core.time.set",
					Handler = HandleAddTimeCommand,
					ParameterCombinations = 
					{
						{
							Params = "value",
							Help = "Adds the value given to the current time.",
						},
						{
							Params = "value world",
							Help = "Adds the value to the time in the given world, rather than the current world.",
						},
					},
				},
				query = 
				{
					Subcommands = 
					{
						daytime = 
						{
							HelpString = "Displays the current time.",
							Permission = "core.time.query.daytime",
							Handler = HandleQueryDaytimeCommand,
							ParameterCombinations = 
							{
								{
									Params = "world",
									Help = "Displays the time in the specified world, rather than the current world.",
								},
							},
						},
						gametime =
						{
							HelpString = "Displays the amount of time elapsed since start.",
							Permission = "core.time.query.gametime",
							Handler = HandleQueryGametimeCommand,
							ParameterCombinations = 
							{
								{
									Params = "world",
									Help = "Displays the time in the specified world, rather than the current world",
								},
							},
						},
					},
				},
			},
		},

		["/title"] =
		{
			Permission = "core.title",
			Handler = HandleTitleCommand,
			HelpString = "Controls the screen title shown to the given players (player name or target selector).",
			ParameterCombinations =
			{
				{
					Params = "player title|subtitle|actionbar text",
					Help = "Sets the title, the subtitle or the action bar text ('&' colour codes are supported).",
				},
				{
					Params = "player times fadeIn stay fadeOut",
					Help = "Sets the fade in, stay and fade out times, in game ticks.",
				},
				{
					Params = "player clear",
					Help = "Removes the title from the screen (the text is kept).",
				},
				{
					Params = "player reset",
					Help = "Clears the text and restores the default times.",
				},
			},
		},

		["/toggledownfall"] = 
		{
			Permission = "core.toggledownfall",
			Handler = HandleToggleDownfallCommand,
			HelpString = "Toggles the weather between clear skies and rain.",
			ParameterCombinations =
			{
				{
					Params = "world",
					Help = "Toggles the weather in the specified world, rather than the current world.",
				},
			},
		},

		["/tp"] = 
		{
			Permission = "core.teleport",
			Handler = HandleTPCommand,
			HelpString = "Teleports entities (1.12.2 /tp: relative coordinates use each target's position).",
			ParameterCombinations =
			{
				{
					Params = "<destination>",
					Help = "Teleports your player to another entity.",
				},
				{
					Params = "<x> <y> <z> [<yaw> <pitch>]",
					Help = "Teleports your player to the given position.",
				},
				{
					Params = "<target> <destination>",
					Help = "Teleports the targets to another entity.",
				},
				{
					Params = "<target> <x> <y> <z> [<yaw> <pitch>]",
					Help = "Teleports the targets to the given position.",
				},
			},
		},

		["/tps"] = 
		{
			Permission = "core.tps",
			Handler = HandleTpsCommand,
			HelpString = "Returns the tps (ticks per second) from the server.",
		},

		["/unban"] = 
		{
			Permission = "core.unban",
			Handler = HandleUnbanCommand,
			HelpString = "Unbans a player.",
		},

		["/unloadchunks"] =
		{
			Permission = "core.unloadchunks",
			Handler = HandleUnloadChunksCommand,
			HelpString = "Unloads all unused chunks.",
		},

		["/unrank"] =
		{
			Permission = "core.unrank",
			Handler = HandleUnrankCommand,
			HelpString = "Add a player to the default rank.",
			Alias = "/deop",
		},

		["/unsafegive"] = 
		{
			Permission = "core.give.unsafe",
			Handler = HandleUnsafeGiveCommand,
			HelpString = "Gives an item to a player, even if the item is blacklisted.",
			ParameterCombinations = 
			{
				{
					Params = "player item",
					Help = "Gives the player one of the specified item.",
				},
				{
					Params = "player item amount",
					Help = "Gives the player the given amount of the specified item.",
				},
				{
					Params = "player item amount data",
					Help = "Gives the player the given amount of the specified item with the given data value.",
				},
				{
					Params = "player item amount data dataTag",
					Help = "Gives the player the given amount of the specified item with the given data value and DataTag.",
				},
			},
		},

		["/unsafeitem"] = 
		{
			Permission = "core.item.unsafe",
			Handler = HandleUnsafeItemCommand,
			HelpString = "Gives your player an item, even if the item is blacklisted.",
			ParameterCombinations = 
			{
				{
					Params = "item",
					Help = "Gives the caller one of the specified item.",
				},
				{
					Params = "item amount",
					Help = "Gives the caller the given amount of the specified item.",
				},
				{
					Params = "item amount data",
					Help = "Gives the caller the given amount of the specified item with the given data value.",
				},
				{
					Params = "item amount data dataTag",
					Help = "Gives the caller the given amount of the specified item with the given data value and DataTag.",
				},
			},
		},

		["/version"] = 
		{
			Alias = "/ver",
			Permission = "core.version",
			Handler = HandleVersionCommand,
			HelpString = "Shows the version of the server software.",
		},

		["/viewdistance"] = 
		{
			Permission = "core.viewdistance",
			Handler = HandleViewDistanceCommand,
			HelpString = "Changes your view distance.",
		},

		["/weather"] = 
		{
			Permission = "core.weather",
			Handler = HandleWeatherCommand,
			HelpString = "Changes the world's weather.",
			ParameterCombinations =
			{
				{
					Params = "weather",
					Help = "Set the weather to to the given condition, can be: clear, rain, or thunder.",
				},
				{
					Params = "weather DurationInSeconds",
					Help = "Set the weather to the given condition, for the specified duration.",
				},
				{
					Params = "weather world",
					Help = "Set the weather to the given condition in the given world, rather than the default world.",
				},
				{
					Params = "weather DurationInSeconds world",
					Help = "Set the weather to the given condition, have it last for the specified duration, in the given world.",
				},
			},
		},

		["/whitelist"] =
		{
			HelpString= "Manages the whitelist.",
			Subcommands =
			{
				add =
				{
					HelpString = "Adds a player to the whitelist.",
					Permission = "core.whitelist",
					Handler = HandleWhitelistAddCommand,
					ParameterCombinations =
					{
						{
							Params = "player",
							Help = "Adds the specified player to the whitelist.",
						},
					},
				},
				list =
				{
					HelpString = "Shows a list of all players on the whitelist.",
					Permission = "core.whitelist",
					Handler = HandleWhitelistListCommand,
				},
				off =
				{
					HelpString = "Turns whitelist processing off.",
					Permission = "core.whitelist",
					Handler = HandleWhitelistOffCommand,
				},
				on =
				{
					HelpString= "Turns whitelist processing on.",
					Permission = "core.whitelist",
					Handler = HandleWhitelistOnCommand,
				},
				remove =
				{
					HelpString = "Removes a player from the whitelist.",
					Permission = "core.whitelist",
					Handler = HandleWhitelistRemoveCommand,
					ParameterCombinations =
					{
						{
							Params = "player",
							Help = "Removes the specified player from the whitelist.",
						},
					},
				},
			},  -- Subcommands
		},  -- /whitelist

		["/worlds"] = 
		{
			Permission = "core.worlds",
			Handler = HandleWorldsCommand,
			HelpString = "Shows a list of all the worlds.",
		},

		["/xp"] =
		{
			Permission = "core.xp",
			Handler = HandleXPCommand,
			HelpString = "Adds experience points, or experience levels when the amount ends with L.",
			ParameterCombinations =
			{
				{
					Params = "amount [player]",
					Help = "Adds (or with a negative amount removes) that many experience points.",
				},
				{
					Params = "amountL [player]",
					Help = "Adds (or with a negative amount removes) that many experience levels.",
				},
			},
		},
	},  -- Commands


	
	ConsoleCommands =
	{
		["about"] = 
		{
			Handler = HandleVersionCommand,
			HelpString = "Shows the version of the server software.",
		},

		["ban"] =
		{
			Handler =  HandleConsoleBan,
			HelpString = "Bans a player by name.",
		},

		["ban-ip"] =
		{
			Handler = HandleConsoleBanIPAddress,
			HelpString = "Bans an IP address, or the IP address of an online player.",
		},

		["banip"] =
		{
			Handler =  HandleConsoleBanIP,
			HelpString = "Bans a player by IP.",
			Alias = "ipban",
		},

		["banlist"] =
		{
			Handler = HandleConsoleBanList,
			HelpString = "Shows the banned players (banlist players) or IP addresses (banlist ips).",
		},

		["banlist ips"] =
		{
			-- This is a dummy entry only to generate the documentation
			-- the real processing is done by the "banlist" command
			Handler =  HandleConsoleBanList,
			HelpString = "Shows a list of all players banned by IP.",
		},

		["clear"] =
		{
			Handler =  HandleConsoleClear,
			HelpString = "Clears the inventory of a player.",
		},

		["deop"] =
		{
			Handler = HandleConsoleUnrank,
			HelpString = "Resets a player's rank to default.",
		},
		
		["effect"] =
		{
			Handler =  HandleConsoleEffect,
			HelpString = "Adds an effect to players or other entities (player name or target selector).",
		},

		["enchant"] = 
		{
			Handler = HandleConsoleEnchant,
			HelpString = "Adds an enchantment to a specified player's held item.",
			ParameterCombinations =
			{
				{
					Params = "player enchantmentID",
					Help = "Adds the specified enchantment to the specified player's currently held item.",
				},
				{
					Params = "player enchantmentID level",
					Help = "Adds the specified enchantment of the given level to the specified player's currently held item.",
				},
			},
		},

		["execute"] = 
		{
			Handler = HandleConsoleExecute,
			HelpString = "Runs a command on behalf of another entity, from that entity's position.",
		},

		["function"] =
		{
			Handler = HandleConsoleFunction,
			HelpString = "Runs the commands of a .mcfunction file from the world's data/functions folder.",
		},

		["gamemode"] =
		{
			Handler =  HandleConsoleGamemode,
			HelpString = "Changes a player's gamemode.",
			ParameterCombinations = 
			{
				{
					Params = "gamemode player",
					Help = "Changes the gamemode of the given player.",
				},
			},
		},

		["gm"] =
		{
			Handler =  HandleConsoleGamemode,
			HelpString = "Changes a player's gamemode.",
			ParameterCombinations = 
			{
				{
					Params = "gamemode player",
					Help = "Changes the gamemode of the given player.",
				},
			},
		},

		["give"] =
		{
			Handler =  HandleConsoleGive,
			HelpString = "Gives an item to a player.",
			ParameterCombinations = 
			{
				{
					Params = "player item",
					Help = "Gives the player one of the specified item.",
				},
				{
					Params = "player item amount",
					Help = "Gives the player the given amount of the specified item.",
				},
				{
					Params = "player item amount data",
					Help = "Gives the player the given amount of the specified item with the given data value.",
				},
				{
					Params = "player item amount data dataTag",
					Help = "Gives the player the given amount of the specified item with the given data value and DataTag.",
				},
			},
		},

		["groups"] =
		{
			Handler =  HandleConsoleListGroups,
			HelpString = "Shows a list of all the available groups.",
		},

		["kick"] =
		{
			Handler =  HandleConsoleKick,
			HelpString = "Kicks a player by name.",
		},

		["kill"] =
		{
			Handler =  HandleConsoleKill,
			HelpString = "Kills a player.",
		},

		["list"] =
		{
			Handler =  HandleConsoleList,
			HelpString = "Shows a list of all connected players in a machine-readable format.",
		},

		["listgroups"] =
		{
			Handler =  HandleConsoleListGroups,
			HelpString = "Shows a list of all the available groups.",
		},

		["listranks"] =
		{
			Handler =  HandleConsoleListRanks,
			HelpString = "Shows a list of all the available ranks.",
		},

		["numchunks"] =
		{
			Handler =  HandleConsoleNumChunks,
			HelpString = "Shows number of chunks currently loaded.",
		},

		["particle"] =
		{
			Handler = HandleConsoleParticle,
			HelpString = "Creates particles at the given position.",
		},

		["players"] =
		{
			Handler =  HandleConsolePlayers,
			HelpString = "Shows a list of all connected players.",
		},

		["playsound"] =
		{
			Handler = HandleConsolePlaysound,
			HelpString = "Plays a sound for the given players (player name or target selector).",
		},

		["plugins"] =
		{
			Handler = HandleConsolePlugins,
			HelpString = "Shows a list of the plugins.",
		},

		["rank"] =
		{
			Handler =  HandleConsoleRank,
			HelpString = "Shows or sets a player's rank.",
		},

		["op"] =
		{
			Handler = HandleConsoleOp,
			HelpString = "Add a player to the Admin rank.",
		},

		["pardon"] =
		{
			Handler = HandleConsolePardon,
			HelpString = "Removes a player from the banlist.",
		},

		["pardon-ip"] =
		{
			Handler = HandleConsolePardonIP,
			HelpString = "Removes an IP address from the banlist.",
		},

		["msg"] =
		{
			Handler = HandleConsoleTell,
			HelpString = "Sends a private message to a player.",
		},

		["r"] =
		{
			Handler = HandleConsoleR,
			HelpString = "Replies to the latest private message you received.",
		},

		["ranks"] =
		{
			Handler =  HandleConsoleListRanks,
			HelpString = "Shows a list of all the available ranks.",
		},
		
		["regen"] =
		{
			Handler = HandleConsoleRegen,
			Alias = "regeneratechunk",
			HelpString = "Regenerates a chunk.",
			ParameterCombinations =
			{
				{
					Params = "chunkX chunkZ",
					Help = "Regenerates the specified chunk in the default world.",
				},
				{
					Params = "chunkX chunkZ world",
					Help = "Regenerates the specified chunk in the specified world.",
				}
			},
		},  -- regen

		["tell"] =
		{
			Handler = HandleConsoleTell,
			HelpString = "Sends a private message to a player.",
		},

		["tellraw"] =
		{
			Handler = HandleConsoleTellraw,
			HelpString = "Sends a raw JSON text component to the given players (player name or target selector).",
		},

		["save-all"] =
		{
			Handler =  HandleConsoleSaveAll,
			HelpString = "Saves all worlds.",
		},

		["save-off"] =
		{
			Handler = HandleConsoleSaveOff,
			HelpString = "Disables automatic saving of all worlds.",
		},

		["save-on"] =
		{
			Handler = HandleConsoleSaveOn,
			HelpString = "Enables automatic saving of all worlds.",
		},

		["seed"] =
		{
			Handler = HandleConsoleSeed,
			HelpString = "Shows the seed of the given world name or default world, if not given.",
		},

		["say"] =
		{
			Handler = HandleConsoleSay,
			HelpString = "Sends a chat message to all players.",
		},

		["scoreboard"] =
		{
			HelpString = "Manages and displays scores for various scoreboard objectives. ",
			Subcommands =
			{
				objectives =
				{
					HelpString = "Manage Objectives",
					Permission = "core.scoreboard.objectives",
					Handler = HandleConsoleScoreboardObjectives,
					ParameterCombinations =
					{
						{
							Params = "list",
							Help = "List all existing objectives with their display names and criteria.",
						},
						{
							Params = "add objective criteria displayName",
							Help = "Create a new objective with the given internal objective name, specified criterion, and the optional display name.",
						},
						{
							Params = "remove objective",
							Help = "Delete the named objective from the scoreboard system.",
						},
						{
							Params = "setdisplay slot objective",
							Help = "Display score info for the objective in the given slot.",
						},
						{
							Params = "modify objective displayname name",
							Help = "Change the display name of the scoreboard in display slots.",
						},
						-- Not implemented yet
						-- {
						-- 	Params = "modify objective rendertype (hearts|integer)",
						-- 	Help = "Change the display format for scores in the tab player list.",
						-- },
					},
				},
				players =
				{
					HelpString = "Manage Players",
					Permission = "core.scoreboard.players",
					Handler = HandleConsoleScoreboardPlayers,
					ParameterCombinations =
					{
						-- Not Implemented yet
						-- {
						-- 	Params = "list",
						-- 	Help = "Lists all score holders which are tracked in some way by the scoreboard system.",
						-- },
						{
							Params = "list player",
							Help = "Lists all score holders which are tracked in some way by the scoreboard system for a player.",
						},
						{
							Params = "get player objective",
							Help = "Return the scoreboard value.",
						},
						{
							Params = "set player objective score",
							Help = "Set the target's scores in the given objective, overwriting any previous score.",
						},
						{
							Params = "add player objective score",
							Help = "Increments the target's scores in the given objective.",
						},
						{
							Params = "remove player objective score",
							Help = "Decrements the target's scores in the given objective.",
						},
						{
							Params = "reset player",
							Help = "Deletes all scores for the targets",
						},
						{
							Params = "reset player objective",
							Help = "Delete score for the targets in the specified objective",
						},
						{
							Params = "operation targetPlayer targetObjective operation sourcePlayer sourceObjective",
							Help = "Applies an arithmetic operation altering the target's scores in the target objective, using source's scores in the source objective as input",
						},
					},
				},
				teams =
				{
					HelpString = "Manage Teams",
					Permission = "core.scoreboard.teams",
					Handler = HandleConsoleScoreboardTeams,
					ParameterCombinations =
					{
						{
							Params = "add name [display name...]",
							Help = "Create a new team with the given internal name and the optional display name.",
						},
						{
							Params = "remove name",
							Help = "Delete the named team from the scoreboard system.",
						},
						{
							Params = "empty name",
							Help = "Remove all members from the named team.",
						},
						{
							Params = "join team [targets...]",
							Help = "Put the given targets on the team.",
						},
						{
							Params = "leave [targets...]",
							Help = "Remove the given targets from their teams.",
						},
						{
							Params = "list [team]",
							Help = "List all teams with their display names and member counts, or the named team.",
						},
						{
							Params = "option team option value",
							Help = "Change a team option (friendlyfire, seeFriendlyInvisibles).",
						},
					},
				},
			},
		},

		["spawnpoint"] = 
		{
			Handler = HandleConsoleSpawnPoint,
			HelpString = "Sets the spawn point for a player.",
		},

		["spawn"] =
		{
			Handler = HandleConsoleSpawn,
			HelpString = "Returns a player to the spawn point.",
		},

		["setworldspawn"] =
		{
			Handler = HandleConsoleSetWorldspawn,
			HelpString = "Sets the spawn point of the default world (vanilla name).",
		},

		["spreadplayers"] =
		{
			Handler = HandleConsoleSpreadplayers,
			HelpString = "Spreads the targets randomly on the surface around the given centre.",
		},

		["stopsound"] =
		{
			Handler = HandleConsoleStopsound,
			HelpString = "Stops sounds for the given players (player name or target selector).",
		},

		["summon"] = 
		{
			Handler = HandleConsoleSummon,
			HelpString = "Summons an entity in the world.",
		},

		["testfor"] = 
		{
			Handler = HandleConsoleTestfor,
			HelpString = "Counts the entities (player name or target selector) matching the given conditions.",
		},

		["testforblock"] = 
		{
			Handler = HandleConsoleTestforblock,
			HelpString = "Tests whether the block at the given position is the given block.",
		},

		["time"] = 
		{
			HelpString = "Sets or displays the time.",
			Subcommands = 
			{
				day =
				{
					Handler = HandleConsoleSpecialTime,
					HelpString = "Sets the time to day.",
					ParameterCombinations =
					{
						{
							Params = "WorldName",
							Help = "Set the time in the specified world, rather than the default world.",
						},
					},
				},
				night =
				{
					Handler = HandleConsoleSpecialTime,
					HelpString = "Sets the time to night.",
					ParameterCombinations =
					{
						{
							Params = "WorldName",
							Help = "Set the time in the specified world, rather than the default world.",
						},
					},
				},
				set =
				{
					Handler = HandleConsoleSetTime,
					HelpString = "Sets the time to a given value.",
					ParameterCombinations =
					{
						{
							Params = "time",
							Help = "Sets the time to the given value."
						},
						{
							Params = "day",
							Help = "Sets the time to day.",
						},
						{
							Params = "night",
							Help = "Sets the time to night.",
						},
						{
							Params = "time WorldName",
							Help = "Sets the time to the given value in the specified world, rather than the default world.",
						},
						{
							Params = "day WorldName",
							Help = "Sets the time to day in the specified world, rather than the default world.",
						},
						{
							Params = "night WorldName",
							Help = "Sets the time to night in the specified world, rather than the default world.",
						},
					},
				},
				add =
				{
					Handler = HandleConsoleAddTime,
					HelpString = "Adds a given value to the current time.",
					ParameterCombinations =
					{
						{
							Params = "amount",
							Help = "Adds the given value to the current time."
						},
						{
							Params = "add WorldName",
							Help = "Adds the value to the time in the specified world, rather than the default world.",
						},
					},
				},
				query =
				{
					Subcommands =
					{
						daytime =
						{
							Handler = HandleConsoleQueryDaytime,
							HelpString = "Displays the current time.",
							ParameterCombinations =
							{
								{
									Params = "WorldName",
									Help = "Displays the time in the specified world, rather than the default world.",
								},
							},
						},
						gametime =
						{
							Handler = HandleConsoleQueryGametime,
							HelpString = "Displays the amount of time elapsed since start.",
							ParameterCombinations =
							{
								{
									Params = "WorldName",
									Help = "Display the time in the given world, rather than the default world",
								},
							},
						},
					},
				},
			},
		},

		["title"] =
		{
			Handler = HandleConsoleTitle,
			HelpString = "Controls the screen title shown to the given players (player name or target selector).",
		},

		["toggledownfall"] =
		{
			Handler = HandleConsoleToggleDownfall,
			HelpString = "Toggles the weather between clear skies and rain.",
			ParameterCombinations =
			{
				{
					Params = "WorldName",
					Help = "Changes the weather in the specified world, rather than the default world.",
				},
			},
		},

		["teleport"] =
		{
			Handler = HandleConsoleTeleportCommand,
			HelpString = "Teleports entities to the given position (vanilla syntax).",
		},

		["tp"] =
		{
			Handler = HandleConsoleTPCommand,
			HelpString = "Teleports entities (vanilla 1.12.2 /tp syntax).",
		},

		["tps"] =
		{
			Handler =  HandleConsoleTps,
			HelpString =  "Returns the tps (ticks per second) from the server.",
		},

		["unban"] =
		{
			Handler =  HandleConsoleUnban,
			HelpString = "Unbans a player by name.",
		},

		["unbanip"] =
		{
			Handler =  HandleConsoleUnbanIP,
			HelpString = "Unbans a player by IP.",
		},

		["unloadchunks"] =
		{
			Handler = HandleConsoleUnloadChunks,
			HelpString = "Unloads all unused chunks.",
		},
		
		["unrank"] =
		{
			Handler = HandleConsoleUnrank,
			HelpString = "Resets a player's rank to default.",
		},
		
		["unsafegive"] =
		{
			Handler =  HandleConsoleUnsafeGive,
			HelpString = "Gives an item to a player, even if the item is blacklisted.",
			ParameterCombinations = 
			{
				{
					Params = "player item",
					Help = "Gives the player one of the specified item.",
				},
				{
					Params = "player item amount",
					Help = "Gives the player the given amount of the specified item.",
				},
				{
					Params = "player item amount data",
					Help = "Gives the player the given amount of the specified item with the given data value.",
				},
				{
					Params = "player item amount data dataTag",
					Help = "Gives the player the given amount of the specified item with the given data value and DataTag.",
				},
			},
		},

		["version"] = 
		{
			Handler = HandleVersionCommand,
			HelpString = "Shows the version of the server software.",
		},

		["weather"] =
		{
			Handler = HandleConsoleWeather,
			HelpString = "Changes the world's weather.",
			ParameterCombinations =
			{
				{
					Params = "weather",
					Help = "Sets the weather to to the given condition, can be: clear, rain, or thunder.",
				},
				{
					Params = "weather DurationInSeconds",
					Help = "Sets the weather to the given condition, for the specified duration.",
				},
				{
					Params = "weather world",
					Help = "Sets the weather to the given condition in the given world, rather than the default world.",
				},
				{
					Params = "weather DurationInSeconds world",
					Help = "Sets the weather to the given condition, have it last for the specified duration, in the given world.",
				},
			},
		},

		["whitelist"] =
		{
			HelpString= "Manages the whitelist.",
			Subcommands =
			{
				add =
				{
					HelpString = "Adds a player to the whitelist.",
					Handler = HandleConsoleWhitelistAdd,
					ParameterCombinations =
					{
						{
							Params = "player",
							Help = "Adds the specified player to the whitelist.",
						},
					},
				},
				list =
				{
					HelpString = "Shows a list of all players on the whitelist.",
					Handler = HandleConsoleWhitelistList,
				},
				off =
				{
					HelpString = "Turns off whitelist processing.",
					Handler = HandleConsoleWhitelistOff,
				},
				on =
				{
					HelpString = "Turns on whitelist processing.",
					Handler = HandleConsoleWhitelistOn,
				},
				remove =
				{
					HelpString = "Removes a player from the whitelist.",
					Handler = HandleConsoleWhitelistRemove,
					ParameterCombinations =
					{
						{
							Params = "PlayerName",
							Help = "Removes the specified player from the whitelist.",
						},
					},
				},
			},  -- Subcommands
		},  -- whitelist

		["worlds"] = 
		{
			Handler = HandleConsoleWorlds,
			HelpString = "Shows a list of all the worlds.",
		},

		["xp"] =
		{
			Handler = HandleConsoleXP,
			HelpString = "Adds experience points (or, with an L suffix, levels) to a player.",
		},

		["clone"] =
		{
			Handler = HandleConsoleClone,
			HelpString = "Clones a region of blocks to another place.",
		},

		["fill"] =
		{
			Handler = HandleConsoleFill,
			HelpString = "Fills a region of blocks with the given block.",
		},

		["setblock"] =
		{
			Handler = HandleConsoleSetBlock,
			HelpString = "Changes a single block.",
		},

		["testforblocks"] =
		{
			Handler = HandleConsoleTestforblocks,
			HelpString = "Tests whether two regions of blocks match.",
		},
	},  -- ConsoleCommands
	Permissions = 
	{
		["core.changegm"] =
		{
			Description = "Allows players to change gamemodes.",
			RecommendedGroups = "admins",
		},

		["core.enchant"] =
		{
			Description = "Allows players to add an enchantment to a player's held item.",
			RecommendedGroups = "admins",
		},

		["core.enchant.self"] =
		{
			Description = "Allows players to add an enchantment to their own held item.",
			RecommendedGroups = "admins",
		},

		["core.give"] =
		{
			Description = "Allows players to give items to other players.",
			RecommendedGroups = "admins",
		},

		["core.give.unsafe"] =
		{
			Description = "Allows players to give items to other players, even if the item is blacklisted.",
			RecommendedGroups = "none",
		},

		["core.item"] =
		{
			Description = "Allows players to give items to themselves.",
			RecommendedGroups = "admins",
		},

		["core.item.unsafe"] =
		{
			Description = "Allows players to give items to themselves, even if the item is blacklisted.",
			RecommendedGroups = "none",
		},

		["core.time.set"] = 
		{
			Description = "Allows players to set the time of day.",
			RecommendedGroups = "admins",
		},

		["core.time.query.daytime"] =
		{
			Description = "Allows players to display the time of day.",
			RecommendedGroups = "everyone",
		},

		["core.time.query.gametime"] =
		{
			Description = "Allows players to display how long the world has existed.",
		},
		
		["core.toggledownfall"] =
		{
			Description = "Allows players to toggle the weather between clear skies and rain.",
			RecommendedGroups = "admins",
		},
		
		["core.weather"] =
		{
			Description = "Allows players to change the weather.",
			RecommendedGroups = "admins",
		},
		

		["core.whitelist"] =
		{
			Description = "Allows players to manage the whitelist.",
			RecommendedGroups = "admins",
		},

		["core.version"] =
		{
			Description = "Shows the version of the server software.",
		},
	},  -- Permissions
}  -- g_PluginInfo


