--!strict
-- Player-facing copy. Add new UI wording here so localization has one source.
return {
	Pull = "PULL",
	-- The zoom guide over the spin button while it is your turn, beside its icon (ZoomHint).
	ZoomHint = "Zoom In/Out",
	-- The controller guide at the bottom left while it is your turn on a gamepad (PadGuide).
	PadGuide = {
		Turn = "Turn", -- the left stick, left and right
		FineAim = "Fine aim", -- the D-pad, left and right
		Zoom = "Zoom", -- the right stick, up and down
		SpinAngle = "Spin & angle", -- hold L1
		Shoot = "Shoot", -- X (Xbox A)
		-- While L1 holds the spin panel open:
		Spin = "Spin", -- the left stick
		Angle = "Angle", -- the right stick, up and down: the cue's angle
		CenterSpin = "Center spin", -- Y (spelt like the spin panel's Center button)
		Ult = "Ability", -- X (Xbox X, PlayStation Square) while your ability bar is ready
	},
	PowerPercent = "%d%%",
	Spin = { Center = "Center", Done = "Done", Degrees = "%d°" },
	Match = {
		Mode = "%dv%d", -- a table's mode: 1v1, 2v2, 3v3
		-- The queue pad (TableService) and the sign floating over its table (TableSign).
		SoloTitle = "SOLO",
		PadJoin = "JOIN", -- on an empty pad, under its mode
		PadArrow = "JOIN", -- under the arrow bobbing over a pad with room
		PadCount = "%d/%d", -- on a pad with players on it: how many, of how many it holds
		PadFull = "FULL",
		PadPlaying = "PLAYING", -- on the pad and the sign while the table's game is on
		Waiting = "WAITING",
		Starting = "STARTING %d", -- the sign's pill while a full pad counts down to its game
		-- The popup everyone free in the server gets when a host with no friend in the server
		-- steps onto a pad (OpponentPrompt; TableService.askForOpponent).
		Request = {
			NeedsOpponent = "%s needs an opponent!", -- a 1v1 table
			NeedsPlayers = "%s needs players!", -- a 2v2 or 3v3 table
			Join = "Join",
			Dismiss = "Dismiss",
			GamepadHint = "Y · Join",
		},
		-- The matchmaking bar above the hotbar (MatchBar; designer, 2026-10-07), for everyone
		-- on a waiting pad. TableSign also reads PlayerCount and Levels.
		Queue = {
			PlayerCount = "%d/%d", -- in the people chip: how many are on the pad, of how many it holds
			Levels = { Classic = "Classic", Difficult = "Difficult", Challenger = "Challenger" },
			-- The bar adds three dots that light up one by one (MatchBar.dots).
			WaitingForOpponent = "Waiting for opponent", -- a 1v1 pad with room
			WaitingForPlayers = "Waiting for players", -- a 2v2 or 3v3 pad with room
			StartingIn = "Starting in %d", -- the pad is full: the game starts by itself
			-- The host's one choice, a few seconds after stepping on.
			NoWait = "Don't want to wait?",
			NoWaitPad = "Don't want to wait? Y", -- the same, while a gamepad is in use
			PlayGlobal = "Play Global",
			Searching = "Searching... %s", -- the search's time, "0:07"
			MatchFound = "Match found!",
		},
		OpenTable = "OPEN TABLE",
		Solids = "SOLIDS",
		Stripes = "STRIPES",
		-- The status card's one line (MatchHUD), kept short to fit beside the clock on a phone.
		-- The popup when the groups are decided (MatchHUD): your group.
		GroupPopup = {
			Solids = "YOU ARE SOLIDS",
			Stripes = "YOU ARE STRIPES",
		},
		Status = {
			-- The turn popup (MatchHUD) when a turn starts.
			YourTurn = "YOUR TURN",
			TheirTurn = "OPPONENT'S TURN",
			AllyTurn = "ALLY'S TURN", -- a teammate is shooting
		},
		Playing = "%s IS PLAYING",
		ChoosePocket = "CHOOSE POCKET",
		Aim = "AIM & SHOOT",
		Rolling = "BALLS ROLLING",
		Foul = "FOUL",
		Fouled = "%s fouled",
		-- The foul popup (MatchHUD): FOUL! and the broken rule in a few plain words, for
		-- players who have never played 8-ball. Keyed by the server's foul reason, with the
		-- wrong first contact split three ways (open table, own group, the 8).
		FoulPopup = "FOUL!",
		FoulShort = {
			Scratch = "Scratched the white ball",
			OffTable = "A ball flew off the table",
			NoContact = "The white ball hit nothing",
			WrongContactOpen = "Hit the 8 first",
			WrongContactOwn = "Hit the other group's ball first",
			WrongContactEight = "Didn't hit the 8 first",
			NoRail = "No ball reached a rail",
			IllegalBreak = "The break was too weak",
			Timeout = "Ran out of time",
			Departure = "The shooter left",
			Reset = "The shooter reset",
			EightBack = "The 8 was put back on the table", -- the tutorial's game 1
		},
		Win = "YOU WIN!",
		Lose = "YOU LOSE!",
		Draw = "MATCH ENDED",
		Yes = "Yes",
		No = "No",
		Confirm = "Done",
		LeaveQuestion = "Are you sure you want to leave?",
		SurrenderHint = "Yes requests a team surrender. Every teammate must agree.",
		VoteQuestion = "Surrender this match?",
		VoteHint = "Every teammate must vote Yes. The match clock keeps running.",
		Voted = "Your vote is in",
		VoteCount = "%d/%d agreed · %.0fs",
		-- The coin flip, a few words at a time (designer, 2026-09-27): your side while it
		-- spins, then who breaks once it lands. WHO BREAKS? is for someone watching.
		CoinYouAre = { Heads = "YOU ARE HEADS", Tails = "YOU ARE TAILS" },
		CoinTitle = "WHO BREAKS?",
		CoinYouBreak = "YOU BREAK",
		CoinBreaks = "%s BREAKS",
		CoinTeam = "TEAM %s · %s",
		Breaker = "%s breaks",
		You = "YOU",
		Active = "SHOOTING",
		EightLocked = "8 LOCKED",
		EightReady = "8 READY",
		Pocket = "Pocket %d",
		InvalidTarget = "INVALID FIRST TARGET",
		CallHint = "Select a blue pocket",
		ClockRuns = "The match clock keeps running.",
		Rejected = "Action unavailable — check your turn",
		LeaveSoloGame = "Yes ends your solo game now.",
		SoloEnded = "Solo game ended",
		FoulReasons = {
			Scratch = "Cue ball scratched",
			OffTable = "Ball flew off the table",
			NoContact = "No ball contacted",
			WrongContact = "Wrong first contact",
			NoRail = "No pocket or rail after contact",
			IllegalBreak = "Illegal break",
			Timeout = "Shooting time expired",
			Departure = "Shooter disconnected",
			Reset = "Shooter reset",
			EightBack = "8-ball put back", -- the tutorial's game 1 (Tutorial/Rig)
			wrong_first = "Wrong first contact",
			no_contact = "No ball contacted",
			scratch = "Cue ball scratched",
			no_rail = "No pocket or rail after contact",
			illegal_break = "Illegal break",
			timeout = "Shooting time expired",
			disconnect = "Shooter disconnected",
			reset = "Shooter reset",
			wrong_first_contact = "Wrong first contact",
			no_first_contact = "No ball contacted",
			no_rail_or_pocket = "No pocket or rail after contact",
			death = "Shooter reset",
		},
		ResultReasons = {
			LegalEight = "Called 8-ball pocketed",
			EarlyEight = "8-ball pocketed early",
			WrongPocket = "8-ball in the wrong pocket",
			FoulEight = "Foul on an 8-ball pocket",
			EightOffTable = "8-ball flew off the table",
			Surrender = "Team surrendered",
			EmptyTeam = "A team has left",
			Timeouts = "Two consecutive shooting timeouts",
			legal_eight = "Called 8-ball pocketed",
			early_eight = "8-ball pocketed early",
			wrong_pocket = "8-ball in the wrong pocket",
			foul_eight = "Foul on an 8-ball pocket",
			surrender = "Team surrendered",
			empty_team = "Opposing team left",
			timeouts = "Two consecutive shooting timeouts",
			timeout_forfeit = "Two consecutive shooting timeouts",
		},
		Team = "TEAM %s",
		YourTeam = "YOUR TEAM",
		Opponent = "OPPONENT",
		OpponentTeam = "OPPOSING TEAM",
		AvatarFallback = "?",
		Leave = "Leave",
		LeaveSolo = "Leaving forfeits this match. The match clock continues.",
		LeaveTeam = "Yes requests a team surrender. Every connected teammate must agree. The match clock continues.",
		VoteTitle = "SURRENDER VOTE",
		VoteBody = "Your team has requested a surrender. Every connected teammate must agree.",
		VoteProgress = "%d/%d agreed · %ds left",
		VoteWaiting = "Your vote is in. Waiting for your teammates.",
		ClocksContinue = "Match clocks continue",
		BackToQueue = "Returning to the table area",
		CoinHeadGlyph = "H",
		CoinTailGlyph = "T",
		PlacementHint = "Drag the cue ball anywhere · shoot any time",
		PlacementHintGamepad = "Hold LT + left stick to move the cue ball · shoot any time",
		-- The break's hint: short, in capitals (designer, 2026-09-27).
		BreakPlacement = "DRAG BALL ANYWHERE ON LINE",
		BreakPlacementGamepad = "HOLD LT + LEFT STICK TO SLIDE ON LINE",
		PlacementBlocked = "No room there",
		PocketLabel = "Pocket %d",
		PlacementHandle = "MOVE",
		NiceShot = "NICE SHOT!", -- over the pocket after a bank, combo, kick or carom
		MoveClock = "MOVE %ds", -- under the big clock: seconds left to move the cue ball
		-- Rewind's redo turn, under the big clock: its shot clock in seconds.
		SecondChance = "SECOND CHANCE: %ds",
		-- Time Stop's stopped time, the shooter's instruction line.
		TimeStopHint = "TIME STOPPED · HIT ONE OF YOUR BALLS",
	},
	-- Saves (PlayerData): the kick messages when a save cannot be used.
	-- The global queue's teleports and why one did not happen (GlobalQueue, TeleportScreen).
	GlobalQueue = {
		FoundTitle = "MATCH FOUND",
		Joining = "Joining the arena...",
		ToLobby = "Back to the lobby...",
		Failed = {
			Studio = "Teleports only work in the published game.",
			Teleport = "Couldn't join the match. Try again.",
			Store = "The global queue isn't answering. Try again.",
			Party = "Your party changed, so the search stopped.",
		},
	},
	-- The arena's card while players arrive (ArenaStatus).
	Arena = {
		WaitingFor = "Waiting for players %d/%d",
		NoOpponent = "Your opponent couldn't join. Searching again...",
		NotYours = "That match wasn't yours. Back to the lobby...",
		Started = "Your match already started. Back to the lobby...",
		Rejoin = "We couldn't take you back to the lobby. Please join the game again.",
	},
	-- The row under a finished two-sided game (PostMatch, on the result screen).
	PostMatch = {
		Rematch = "Rematch",
		RematchVotes = "Rematch %d/%d", -- how many have pressed it, of everyone
		RematchWaiting = "Waiting %d/%d", -- after you pressed it
		Another = "Play another", -- a new opponent from the global queue (arena)
		Lobby = "Lobby", -- back to the lobby server you came from (arena)
		Leave = "Leave", -- a lobby table: no rematch, the table frees
		OpponentLeft = "Opponent left",
		TeamWaiting = "Team %d/%d", -- Play another in a team game waits for every teammate
		Series = "SERIES", -- over the score
		SeriesScore = "%d - %d", -- your side first
		Countdown = "%d", -- seconds left to choose
		Searching = "Searching %d:%02d",
		Cancel = "Cancel",
		SeriesPill = "Series %d-%d", -- the match bar during a rematch, your side first
	},
	Save = {
		LoadFailed = "Couldn't load your save. Please rejoin.",
		SessionEnded = "Your save was opened on another server. Please rejoin.",
	},
	-- Ranks: names and the rank's words beside the badge (Progression/Ranks, RankHud, the
	-- roadmap). A rank is shown as "Gold III", "Reyes" or "Unranked".
	Ranks = {
		Unranked = "Unranked",
		Tiers = {
			Bronze = "Bronze",
			Silver = "Silver",
			Gold = "Gold",
			Platinum = "Platinum",
			Diamond = "Diamond",
			Expert = "Expert",
			Veteran = "Veteran",
			Master = "Master",
			Grandmaster = "Grandmaster",
			Reyes = "Reyes",
		},
		-- A line under a tier's name on the rank roadmap (designer, 2026-10-03).
		Titles = { Reyes = "The King" } :: { [string]: string },
		Numerals = { "I", "II", "III", "IV", "V" },
		Division = "%s %s", -- tier, numeral: "Gold III"
		XpOf = "%s / %s XP", -- the XP bar: "520 / 1,000 XP"
		XpOnly = "%s XP", -- Reyes has no top: just the XP past its start
		OneMoreWin = "ONE MORE WIN!", -- under the XP bar when one win ranks up (GUI lane)
		ChatTag = "[%s]", -- before a name in chat, the tier in capitals: "[PLATINUM]" (ChatTags)
		VipTag = "[VIP]", -- first before a VIP player's name in chat, in the house rainbow (ChatTags)
	},
	-- The developer chat commands' private replies (DevCommands; shown only to the caller).
	Dev = {
		Help = "Rank and money commands: /rank <tier> [1-5] [xp], /rank unranked, /xp <amount>, /money <amount>, /addmoney <amount>, /result win|lose|draw|firstwin, /newrank [tier] [1-5], /resetdata. Economy commands: /econhelp. Ability commands: /abilityhelp. Put a player's username last to give it to them instead (/rank, /xp, /money, /addmoney, /givecue, /giveblock, /spins, /lucky, /ability, /abilitysetup).",
		BadRank = "Try /rank gold 3, /rank reyes or /rank unranked.",
		BadAmount = "Give a whole number, like %s 500.",
		XpNeverLost = "XP is never lost: give a gain, like %s 250.",
		BadResult = "Try /result win, /result lose, /result draw or /result firstwin; a loss may add early, pocket, foul or off.",
		NotLoaded = "Your save is not loaded yet.",
		RankSet = "Rank set to %s.",
		MoneySet = "Money set to %s.",
		Reset = "Your save was reset.",
		-- The economy commands (/econhelp). Usage: the alias first (%s), then what follows it;
		-- What: one line on what it does. A bad argument answers Try with the usage.
		EconHelp = "Economy commands (they act on you; [player]: a username in this server, to give it to them):",
		HelpLine = "%s: %s",
		Try = "Try %s.",
		Usage = {
			GiveCue = "%s <id|name> [count] [player]",
			GiveBlock = "%s <%s> [count] [player]", -- the lucky block kinds
			Cutscene = "%s <%s>", -- the rarities with a cutscene
			GiftDrop = "%s",
			Inv = "%s",
			ClearInv = "%s",
			Dupes = "%s",
			SetDay = "%s <1-%d> [week 1-%d]",
			NewDay = "%s",
			Playtime = "%s <minutes>",
			Buy = "%s <product> [purchaseId]",
			Vip = "%s on|off",
			Party = "%s",
			Policy = "%s restricted|normal",
			Restock = "%s uncommon|rare|epic|legendary|mystery",
			Code = "%s on|off <CODE>, or %s list",
			Limited = "%s start [minutes] | end | off",
			UltBar = "%s <0-%d>",
			UltFull = "%s",
			UltArm = "%s",
			Spins = "%s <0-%d> [player]",
			Lucky = "%s <0-%d> [player]",
			Pity = "%s <0-%d>",
			FreeSpin = "%s",
			Ult = "%s <id|name> [player]",
			UltsAll = "%s on|off",
			OpUlt = "%s",
			-- The look check's tools (Studio only).
			Slowmo = "%s <%s-%s>, or %s",
			Hold = "%s <0-%s>, or %s",
			AbilitySetup = "%s <id|name> [player]",
		},
		What = {
			GiveCue = "copies of a cue, by id or name (not Classic or a Unique cue)",
			GiveBlock = "lucky blocks into your hotbar",
			Cutscene = "plays a rare pull's cutscene on its own (nothing is given)",
			GiftDrop = "the first-leave Gift again: a leave now, then it falls from the sky",
			Inv = "lists your cues, lucky blocks and equipped cue",
			ClearInv = "takes every cue but Classic and every lucky block",
			Dupes = "%d copies each of %d random Common and Uncommon cues (to test selling)",
			SetDay = "your next daily claim becomes that streak day",
			NewDay = "as if a new UTC day began (daily claim, playtime, today's limits)",
			Playtime = "sets today's minutes played",
			Buy = "a Robux purchase's grant, without Robux. Products: %s",
			Vip = "fakes owning the VIP pass for this session",
			Party = "starts or extends a Money Party in this server",
			Policy = "fakes PolicyService (restricted: no lucky blocks for money)",
			Restock = "this server shows a restock with that item until the real one ends",
			Code = "switches a like code on or off in every server",
			Limited = "opens or closes the Limited cues in this server (start: now, 14 days or the minutes)",
			UltBar = "sets your ability bar at your table",
			UltFull = "fills your ability bar",
			UltArm = "fills your bar and arms your equipped ability at once (practice in solo)",
			Spins = "sets the Ability Spins you hold",
			Lucky = "sets the Lucky Spins you hold",
			Pity = "sets pity (%d: the next spin is the pity spin)",
			FreeSpin = "today's free spin is ready again",
			Ult = "puts any ability in your selected slot (no spin used)",
			UltsAll = "every ability (placeholders too) rolls and plays for you this session",
			OpUlt = "fills the other side's ability bars at your table (the QA opponent's)",
			-- The look check's tools (Studio only).
			Slowmo = "Studio only: every shot replay at your table at that rate, for everyone (1 or nothing: normal)",
			Hold = "Studio only: every shot replay at your table stops at that many seconds in and stays (nothing: let go)",
			AbilitySetup = "puts that ability in your selected slot, or a named player's (your account only)",
		},
		BadCue = 'No cue called "%s". Use an id (ChalkDust) or a name (chalk dust).',
		BadProduct = 'No product called "%s". Products: %s.',
		ClassicCue = "The Classic Cue is always yours.",
		GaveOwnerCopy = "Gave %s (your owner copy: no number, not counted, never traded).",
		UniqueOwned = "You already own the %s (Unique: one each).",
		UniqueOwnerOnly = "The %s is Unique: an unnumbered copy goes only to your own account.",
		ExclusiveOwned = "You already own the %s (Exclusive: one each).",
		NotGiven = "No %s given (you hold the most allowed).",
		GaveCue = "Gave %s x%d.",
		GaveBlock = "Gave %s x%d.",
		BadBlock = 'No lucky block called "%s". Blocks: %s.',
		Cutscene = "Playing the %s cutscene.", -- the rarity
		GiftDrop = "The Gift is falling (its 12 hours run from now).",
		GiftDropBusy = "No Gift drop here (an arena, or your save is not loaded).",
		InvEquipped = "Equipped: %s",
		InvBlocks = "Lucky blocks: ",
		InvNoBlocks = "Lucky blocks: none",
		InvCues = "Cues (%d kinds, %d copies): ",
		InvNoCues = "Cues: only the Classic Cue",
		InvCount = "%s x%d", -- a cue or block with more than one copy
		InvCopy = "%s #%d", -- a Unique cue's copy number
		Cleared = "Your cues (but Classic) and lucky blocks are gone.",
		Dupes = "Gave %d copies each of: %s.",
		DaySet = "Your next daily claim is day %d of week %d.",
		NewDay = "A new day: the daily claim, playtime gifts and today's limits start over.",
		PlaytimeSet = "Today's playtime is %d minutes.",
		Buying = "Granting %s...",
		Bought = "%s granted.",
		BuyFailed = "%s not granted: %s.",
		PassNames = { Vip = "VIP" },
		PassOn = "%s pass on (faked for this session).",
		PassOff = "%s pass off (faked for this session).",
		VipOfferStays = "VIP from the welcome offer stays: /resetdata clears it.",
		Party = "Money Party on in this server for %d more minutes.",
		PolicyOn = "Paid random items restricted for you (no lucky blocks for money).",
		PolicyOff = "Paid random items allowed for you again.",
		RestockForced = "This server's restock now has the %s item until the real one ends.",
		RestockNone = "No restock with that item soon.",
		CodeOn = "%s is on in every server.",
		CodeOff = "%s is off in every server.",
		CodeFailed = "%s could not be saved; try again.",
		CodeNotLive = "%s is not a like code. Like codes: %s.",
		CodeList = "Like codes on: %s. Off: %s.",
		CodeNone = "none",
		LimitedStart = "The Limited cues are on sale in this server for %d minutes.",
		LimitedEnd = "The Limited cues ended in this server.",
		LimitedOff = "The Limited cues are back to Config's start time in this server.",
		-- The ability commands (/abilityhelp; the old /ulthelp still works).
		UltHelp = "Ability commands (they act on you only):",
		UltBarSet = "Your ability bar is %d%%.",
		UltArmed = "%s armed for your next shot.",
		UltNotDone = "Not done: %s.",
		UltReasons = {
			NoTable = "you are not in a game at a table",
			Off = "abilities are off at your table",
			NotReady = "your bar is not full",
			Used = "you have used your abilities this game",
			NotYourTurn = "it is not your turn",
			Moving = "the balls are still moving",
			Break = "not on the break",
			Armed = "an ability is already armed",
			BallInHand = "you already have ball in hand",
		},
		SpinsSet = "You hold %d Ability Spins.",
		LuckySet = "You hold %d Lucky Spins.",
		PitySet = "Pity is %d (the %dth spin without an Epic or better is one).",
		FreeSpinReady = "Today's free spin is ready again.",
		UltSet = "%s is in your selected slot.",
		BadUlt = 'No ability called "%s". Abilities: %s.',
		-- A giving command for someone else (the last word their username): its answers.
		ForPlayer = "[%s] %s",
		NoPlayer = "No one called %s is in this server.",
		UltsAllOn = "Every ability rolls and plays for you this session.",
		UltsAllOff = "Only the built abilities roll and play for you again.",
		OpUlt = "Filled %d bar(s) on the other side.",
		OpUltNone = "No bar filled (no table, abilities off, or nobody on the other side).",
		-- The look check's tools (/slowmo, /hold: Studio only; /abilitysetup: the designer only).
		StudioOnly = "%s works in Studio only.",
		SlowmoSet = "Replays at table %d play at x%s.",
		SlowmoOff = "Replays at table %d play at normal speed.",
		HoldSet = "Replays at table %d stop at %s s.",
		HoldOff = "Replays at table %d play through again.",
		AbilitySet = "Your ability is now %s.",
		BotRankSet = "Bots you meet now play at %s.",
		BotRankOff = "Bots you meet play at your own tier again.",
		BotRankBad = 'No tier called "%s". Tiers: %s, or off.',
		LobbyBotsOn = "Lobby bots on: the server looks like %d people.",
		LobbyBotsCount = "Lobby bots on: %d of them.",
		LobbyBotsOff = "Lobby bots off.",
		LobbyBotsBad = "Try /lobbybots on, /lobbybots off or /lobbybots <count>.",
		-- /solo and /bot (temporary, 2026-10-07: the pad has no solo or PC button now).
		PlayNeedPad = "Stand on a 1v1 pad first (alone, before the game).",
		PlaySearching = "Cancel the search first (the red X), then try again.",
		PlayFailed = "Could not start it: the pad needs just you on it, before the game.",
		SoloStarted = "Solo game started.",
		BotStarted = "Game against the computer started.",
		BotBad = 'No tier called "%s". Tiers: %s.',
		TutorialStep = "Your tutorial is at %s.",
		TutorialBad = "Try /tutorial reset, skip, off or step <name>. Steps: %s.",
	},
	-- The rank and money screens (ResultScreen, NewRankPopup, Roadmap, RankHud).
	Progress = {
		WinStreak = "🔥 %d", -- over a player's name: their wins in a row (Nameplates)
		Winner = "WINNER",
		Vs = "VS",
		Draw = "DRAW",
		-- Over the losing side (red, like WINNER); with why under it when an 8-ball rule lost
		-- it for you (keyed by ShotJudge's reason); a team game says "Your team".
		Loss = "DEFEAT",
		LossReasons = {
			EarlyEight = "You pocketed the 8 ball early.",
			WrongPocket = "You pocketed the 8 ball in the wrong pocket.",
			FoulEight = "You fouled while pocketing the 8 ball.",
			EightOffTable = "You knocked the 8 ball off the table.",
		},
		LossReasonsTeam = {
			EarlyEight = "Your team pocketed the 8 ball early.",
			WrongPocket = "Your team pocketed the 8 ball in the wrong pocket.",
			FoulEight = "Your team fouled while pocketing the 8 ball.",
			EightOffTable = "Your team knocked the 8 ball off the table.",
		},
		SoloGame = "SOLO GAME",
		Left = "LEFT", -- on the card of a player who left the match
		NoXp = "No XP: match under a minute",
		SoloNoXp = "Solo games give no XP",
		XpDelta = "+%s XP", -- "+100 XP", "+0 XP" (XP is never lost)
		-- The XP boosts on the result screen (ECONOMY 4.5; only the streak since 2026-10-02):
		-- a boost of +100% or more as a multiplier ("STREAK x2": 1 + the boost), a smaller one
		-- as a percent ("STREAK +25%").
		BoostTimes = {
			Streak = "STREAK x%s",
		},
		BoostPercent = {
			Streak = "STREAK +%s%%",
		},
		BallsLine = "Balls pocketed x%d",
		NiceLine = "Nice shots x%d",
		WinBonus = "Win bonus",
		LossBonus = "Match bonus",
		StreakLine = "Win streak", -- the win-streak money (ECONOMY 3.1), from the 3rd win in a row
		RankReward = "Rank reward",
		Total = "Total",
		WinBlock = "+%d %s", -- the win's lucky block on the result screen: "+1 Mystery Lucky Block"
		TapToContinue = "Tap to continue",
		Continue = "Continue",
		NewRank = "NEW RANK!",
		NewTier = "%s!", -- the tier's name, huge: "PLATINUM!"
		RankedTitle = "Ranked",
		RankedSubtitle = "Win matches, climb the ranks and earn rewards!",
		EarnXp = "Win matches to earn XP",
		TopRank = "You are at the top!",
		CurrentRank = "Current Rank", -- the tag over your tier, and under your rank on its card
		NextRank = "Next Rank", -- the tag over the next tier
		NextDivision = "Next: %s", -- your next division: "Next: Gold IV"
		RewardsFor = "Rewards for %s", -- the chosen tier's rewards: "Rewards for Platinum I"
		RewardMoney = "Money",
		RewardCount = "x%d", -- how many: "x2" (a block's count on NEW RANK!)
		RewardBlockCount = "%s x%d", -- the roadmap's block tile: "Epic Lucky Block x2"
		RewardChatTag = "Chat Tag",
		TierCue = "%s Cue", -- a tier with no cue in the catalog: "Platinum Cue"
	},
	-- Cues and rarities by id (Progression/Catalog, Progression/BlockOdds). The cue names are
	-- the cue skins' (assets/cue/skins/<id>.json `name`, plus "Cue").
	Items = {
		Cues = {
			Classic = "Classic Cue",
			MidnightCue = "Midnight Cue",
			ArcticCue = "Arctic Cue",
			CherryCue = "Cherry Cue",
			CarbonCue = "Carbon Cue",
			HeritageCue = "Heritage Cue",
			MonarchCue = "Monarch Cue",
			CobaltCue = "Cobalt Cue",
			GummyCue = "Gummy Cue",
			FlareCue = "Flare Cue",
			HornetCue = "Hornet Cue",
			VenomCue = "Venom Cue",
			LagoonCue = "Lagoon Cue",
			SpliceCue = "Splice Cue",
			CosmoCue = "Cosmo Cue",
			GildedCue = "Gilded Cue",
			PixelCue = "Pixel Cue",
			HoneycombCue = "Honeycomb Cue",
			NeonCue = "Neon Cue",
			NatureCue = "Nature Cue",
			CandyCue = "Candy Cue",
			FrostbiteCue = "Frostbite Cue",
			PlasmaCue = "Plasma Cue",
			BlazeCue = "Blaze Cue",
			PhantomCue = "Phantom Cue",
			TidalCue = "Tidal Cue",
			SakuraCue = "Sakura Cue",
			VoidCue = "Void Cue",
			ShootingStarCue = "Shooting Star Cue",
			MagmaCue = "Magma Cue",
			ToxicCue = "Toxic Cue",
			BloodMoonCue = "Blood Moon Cue",
			PrismCue = "Prism Cue",
			AuroraCue = "Aurora Cue",
			DiscoCue = "Disco Cue",
			HackedCue = "Hacked Cue",
			ChromaCue = "Chroma Cue",
			ThunderstrikeCue = "Thunderstrike Cue",
			PhoenixCue = "Phoenix Cue",
			KrakenCue = "Kraken Cue",
			SeraphCue = "Seraph Cue",
			InfernalCue = "Infernal Cue",
			ClockworkCue = "Clockwork Cue",
			CelestialDragonCue = "Celestial Dragon Cue",
			KitsuneCue = "Kitsune Cue",
			ApexCue = "Apex Cue",
			EclipseCue = "Eclipse Cue",
			BronzeCue = "Bronze Cue",
			SilverCue = "Silver Cue",
			GoldCue = "Gold Cue",
			PlatinumCue = "Platinum Cue",
			DiamondCue = "Diamond Cue",
			ExpertCue = "Expert Cue",
			VeteranCue = "Veteran Cue",
			MasterCue = "Master Cue",
			GrandmasterCue = "Grandmaster Cue",
			ReyesCue = "Reyes Cue",
			VipCue = "VIP Cue",
			StarterCue = "Starter Cue",
			BetaCue = "Beta Cue",
			FireworkCue = "Firework Cue",
		},
		Rarities = {
			Common = "Common",
			Uncommon = "Uncommon",
			Rare = "Rare",
			Epic = "Epic",
			Legendary = "Legendary",
			Mythic = "Mythic",
			Secret = "Secret",
			Exclusive = "Exclusive",
			Ranked = "Ranked",
			Unique = "Unique",
			Default = "Default",
		},
		-- Titles a player can hold (the Index rows' "Collector" titles were dropped 2026-09-28).
		Titles = {
			FirstReyes = "The First Reyes",
		},
	},
	-- The left column and the full menus (MenuColumn, MenuFrame and the four menus).
	Menus = {
		-- Each column tile's word, across its bottom edge (real text, never in the image).
		-- The left column's words, in capitals (designer, 2026-10-06).
		Column = {
			Shop = "SHOP",
			Inventory = "CUES", -- the Cues menu (renamed from Inventory, concept 2, 2026-10-08)
			Rewards = "REWARDS",
			Trade = "TRADE",
			FreeReward = "FREE REWARD",
		},
		-- Each menu's title in its header band.
		Titles = {
			Shop = "Shop",
			Inventory = "Cues",
			Index = "Index", -- the Cues menu's title while its Index shows
			Rewards = "Rewards",
			Trade = "Trade",
			FreeReward = "Free Reward",
		},
		-- The tabs under (or beside) each title.
		Tabs = {
			Inventory = { Cues = "My Cues", Index = "Index" }, -- the Cues menu's switch
			Rewards = { Daily = "Daily", Playtime = "Playtime", Codes = "Codes" },
		},
		Loading = "Loading...", -- a page whose contents have not arrived
		-- The confirm dialog's default buttons.
		Yes = "Yes",
		No = "No",
		DotMore = "%d+", -- the red dot over too many to count: "9+"
		DotReady = "!", -- the red dot on Rewards while something can be claimed
		-- Time left: "23:59:12", "14:32", "6d 4h".
		TimeHours = "%d:%02d:%02d",
		TimeMinutes = "%d:%02d",
		TimeDays = "%dd %dh",
		-- A request that did not work, by the reason the client or server gave; the menus add
		-- their own reasons here. Anything unknown says Default.
		Reasons = {
			Network = "Couldn't reach the server. Try again.",
			Busy = "One moment...",
			Default = "That didn't work. Try again.",
			-- The server's answers (Items, Store, Rewards; the codes are listed in Net.luau).
			BadRequest = "That didn't work. Try again.",
			TooFast = "Slow down a little!",
			NoGift = "That one can't be gifted.",
			GiftSelf = "Pick someone else to gift!",
			GiftGone = "They left the server.",
			GiftNotLoaded = "They are still loading. Try again in a moment.",
			NotLoaded = "Your save is still loading...",
			Teleporting = "You're on your way to a match.",
			Error = "Something went wrong. Try again soon.",
			NotSold = "That isn't for sale.",
			Restricted = "Buying lucky blocks isn't available where you live.",
			NotEnoughMoney = "Not enough money.",
			NotOwned = "You don't own that cue.",
			CantSell = "This cue can't be sold.",
			Equipped = "Equip another cue first.",
			Claimed = "Already claimed.",
			Incomplete = "Collect every cue in this row first.",
			NoReward = "This row has no reward.",
			NotStarted = "Not on sale yet.",
			Ended = "This offer has ended.",
			SoldOut = "Sold out!",
			Owned = "You already own this.",
			VipOnly = "This one is for VIPs.",
			NoTimer = "That lucky block is ready already.",
			Closed = "This offer isn't open right now.",
			PartyFull = "The Money Party is already full for the next hour.",
			ComingSoon = "Coming soon!",
			AlreadyClaimed = "Already claimed today. Come back tomorrow!",
			NotReady = "Not ready yet. Keep playing!",
			Unknown = "That code doesn't exist.",
			Used = "You already used that code.",
			Expired = "That code has expired.",
			NotMember = "Join the group first, then claim!",
			-- Trading (TradeRequest's reasons; NotOwned, Owned and Busy above serve trades too).
			NotHere = "That player isn't here anymore.",
			Self = "You can't trade with yourself.",
			NoInvite = "That trade invite has expired.",
			NoSession = "That trade has closed.",
			Empty = "Both sides need at least one item.",
			NotTradable = "That item can't be traded.",
			PaidBlocked = "Bought items can't be traded where you live.",
			Changed = "Something changed. Check the trade and accept again.",
		},
		-- The Shop (ShopMenu), emptied for the GUI overhaul (designer, 2026-10-04): the frame
		-- and its four jump buttons. The ult screen's buy buttons still use Need, NeedNotice,
		-- ComingSoon, Soon and Robux. Money is "$1,500" (Progression/Format).
		Shop = {
			Need = "Need %s more", -- a buy button while money is short: "Need $1,200 more"
			NeedNotice = "You need %s more. A money pack covers it!", -- after the jump to Money
			ComingSoon = "Coming soon", -- a Robux item whose product is not made yet
			-- A Robux price: Roblox's own Robux glyph (U+E002, it renders in our font), then the
			-- number with commas. Keep the glyph when translating.
			Robux = "\u{E002}%s",
			-- A Limited not on sale yet; also the short "Coming soon" tag where that does not fit.
			Soon = "Soon",
			-- The jump buttons down the right side (designer, 2026-10-04).
			Jump = {
				Featured = "Featured",
				Blocks = "Blocks",
				Money = "Money",
				Passes = "Passes",
			},
			New = "NEW", -- a red badge on a jump button and the Shop tile
			-- The Featured page (the lively Shop, 2026-10-06): its header and the Grand
			-- Opening card. The subtitle's middle word (Limited) is set in yellow by the code.
			Featured = {
				Header = "FEATURED",
				Title = "GRAND OPENING",
				Subtitle = "LUCKY BLOCK • %s • YOU COULD PULL...",
				Limited = "LIMITED",
				-- The lucky block's odds: a sky-blue badge on the block ("i") that opens a
				-- small card listing every outcome (Roblox's paid-random-items rule: all of
				-- them, adding up to 100%, before buying).
				OddsBadge = "i",
				OddsTitle = "Chances",
				OddsTotal = "Total: %s", -- under the list: "Total: 100%"
				-- The live timer under the block: "Ends in 20d 23h", in the last day
				-- "Ends in 23h 59m", in the last hour "Ends in 59:59".
				EndsIn = "Ends in %s",
				Days = "%dd %dh",
				Hours = "%dh %dm",
				Minutes = "%d:%02d",
				New = "NEW", -- the tilted red tag on the block
				-- The cue cards' names, each in two colours ("BETA" cyan, "CUE" pink).
				BetaName = { "BETA", " CUE" },
				FireworkName = { "FIREWORK", " CUE" },
				Unique = "UNIQUE",
				-- A pack's size, between its Robux and money buttons (which show only prices).
				Blocks = { One = "%d block", Many = "%d blocks" },
				BoughtOne = "Your %s is in your hotbar!",
				BoughtMany = "%d %s are in your hotbar!",
			},
			MoreBelow = "More deals coming soon!", -- the white sheet below the Grand Opening card
			BlocksHeader = "BLOCKS", -- the next section's header under the card ("- BLOCKS -")
			-- The Gift Player popup (the purple gift square beside a Robux button).
			GiftTitle = "Gift Player",
			GiftButton = "Gift",
			GiftNobody = "No one else is here to gift right now.",
		},
		-- The Rewards (RewardsMenu and its pages RewardsDaily, RewardsPlaytime, RewardsCodes).
		-- Block names come from Strings.LuckyBlocks.Names; money is "$250" (Progression/Format).
		Rewards = {
			-- The Daily tab.
			Day = "Day %d", -- a tile's heading: "Day 1"
			Claim = "Claim",
			Claimed = "Claimed",
			-- Under the tiles: the week of the four-week cycle and its day-28 prize: "Week 1
			-- of 4: a Legendary Lucky Block on day 28" (the week, the weeks, the prize, the day).
			WeekLine = "Week %d of %d: %s on day %d",
			NextIn = "Next reward in %s", -- once today is claimed: "Next reward in 5:12:03"
			-- A banner over the tiles while an Index row's reward waits (it is claimed in the
			-- Inventory's Index tab; the button goes there).
			IndexReady = "An Index reward is ready!",
			OpenIndex = "Open Index",
			-- The Playtime tab.
			GiftTime = "%s / %s", -- played today, of the gift's time: "4:12 / 10:00"
			PlayedToday = "Played today: %s", -- "Played today: 24:13"
			GiftsReset = "New gifts in %s", -- "New gifts in 5:12:03"
			-- The Codes tab.
			CodeTitle = "Got a code?",
			CodeHint = "Enter code", -- in the empty box
			Redeem = "Redeem",
			Redeemed = "Code redeemed: %s", -- "Code redeemed: +$500 and a Mystery Lucky Block"
			NoCode = "Type a code first.",
			CodeNote = "Codes give free money, lucky blocks and ability spins. Each code works once.",
			-- A reward's lucky blocks in words. Several: "2 Mystery Lucky Blocks"; one, in a
			-- sentence: "a Rare Lucky Block" (a kind missing here says BlockManyOther / its
			-- plain name from LuckyBlocks.Names).
			BlockMany = {
				Standard = "%d Standard Lucky Blocks",
				Uncommon = "%d Uncommon Lucky Blocks",
				Rare = "%d Rare Lucky Blocks",
				Epic = "%d Epic Lucky Blocks",
				Legendary = "%d Legendary Lucky Blocks",
				Mythic = "%d Mythic Lucky Blocks",
				Mystery = "%d Mystery Lucky Blocks",
			},
			BlockManyOther = "%d x %s", -- the count, the block's name
			BlockA = {
				Standard = "a Standard Lucky Block",
				Uncommon = "an Uncommon Lucky Block",
				Rare = "a Rare Lucky Block",
				Epic = "an Epic Lucky Block",
				Legendary = "a Legendary Lucky Block",
				Mythic = "a Mythic Lucky Block",
				Mystery = "a Mystery Lucky Block",
			},
			BlockCount = "x%d", -- on a block's picture: "x2"
			-- A reward's ability spins (a reward's `spins` and `lucky`): in a sentence or a chip.
			SpinOne = "1 Ability Spin",
			SpinMany = "%d Ability Spins",
			LuckyOne = "1 Lucky Spin",
			LuckyMany = "%d Lucky Spins",
			SpinChip = "+%d", -- on the spin icon of a tile, NEW RANK! or a roadmap tile: "+2"
			Plus = "%s + %s", -- two parts of one tile's reward: "$500 + 2 Mystery Lucky Blocks"
			And = "%s and %s", -- the last two parts of what a claim gave
			List = "%s, %s", -- the parts before them
		},
		-- The Trade menu (TradeMenu): trading itself comes in a later update.
		Trade = {
			Soon = "SOON", -- the gold pill
			Note = "Trading is coming soon!",
			Detail = "Soon you can swap cues with the players in your server.",
			Button = "Trade", -- a player's greyed button
			Pressed = "Trading is coming soon!", -- pressing a greyed Trade button
			Empty = "No one else is in this server yet.",
		},
		-- The Cues menu (InventoryMenu and its views; "Inventory" in code). Rarity and cue names
		-- come from Items.
		Inventory = {
			-- My Cues. The tiles beside the panel: Sort (the order's name hangs under it; each
			-- press moves to the next of Config.UI.Inventory.SortOrders) and Sell dupes (the
			-- money it would pay hangs under it; "Sell all" until 2026-10-08).
			SortTile = "Sort",
			SellDupesTile = "Sell dupes",
			SortOrders = {
				RarestFirst = "Rarest first",
				CommonFirst = "Common first",
				MostCopies = "Most copies",
				NameAZ = "Name A-Z",
			},
			New = "NEW", -- the gold pill on a cue until it is seen
			Equipped = "Equipped", -- the green pill, and the Equip button once it is
			Equip = "Equip",
			Count = "x%s", -- copies owned, on the card: "x3"
			CopyShort = "#%s", -- a numbered copy's chip over its card's name: "#412"
			Copy = "Copy #%s", -- ...and in its details
			Owned = "You own %s", -- "You own 3"
			Exist = "%s exist", -- copies in the whole game: "1,284 exist"
			ExistOne = "%s exists", -- ...when there is just one
			CantSell = "Can't be sold", -- Exclusive, Unique and Classic cues
			Sell = "Sell %s", -- one copy: "Sell $120"
			SellDuplicates = "Sell duplicates: %s", -- this cue's extra copies
			Empty = "No cues yet. Open lucky blocks to find some!",
			-- The confirm dialogs (red sells, blue keeps).
			SellYes = "Sell",
			SellNo = "Keep",
			ConfirmSellTitle = "Sell this cue?",
			ConfirmSell = "Sell one %s for %s?", -- the cue's name, the money
			ConfirmDuplicatesTitle = "Sell duplicates?",
			ConfirmDuplicates = "Sell the duplicates of %s for %s? You keep one.",
			ConfirmAllTitle = "Sell all duplicates?",
			ConfirmAll = "Sell every duplicate for %s? You keep one of each cue.",
			Sold = "Sold for %s!",
			SoldAll = "Sold your duplicates for %s!",
			NothingToSell = "No duplicates to sell.",
			EquippedNotice = "%s equipped!", -- the cue's name
			-- The Index view.
			Titles = "Titles",
			Progress = "%s / %s", -- cues of the row ever owned: "5 / 7"
			Claim = "Claim",
			Claimed = "Claimed",
			Unknown = "?", -- a cue never owned, on its Index card (its look stays hidden)
			-- The chosen cue's panel: its name, rarity, then one of these.
			Found = "In your collection", -- ever owned (selling it keeps it here)
			NotFound = "Not found yet",
			FindReward = "Find it for +%s", -- a cue not found yet: its finder's money ("$250")
			-- The chosen cue's big card (GUI lane, 2026-10-03).
			Odds = "%s chance", -- a cue's rarity per Mystery block: "4.2% chance"
			Joined = "%s · %s", -- the chance and how many exist: "4.2% chance · 1,284 exist"
			SellSome = "Sell duplicates", -- opens the count chooser
			SellCount = "Sell %s for %s", -- the count and the money: "Sell 3 for $360"
			Max = "Max",
			ConfirmSellCount = "Sell %s x %s for %s? You keep one.", -- count, cue, money
			Close = "Close",
		},
	},
	-- Lucky blocks (the test build, 2026-10-03; LuckyHotbar, LuckyWorld, LuckyOpening).
	LuckyBlocks = {
		Names = {
			Standard = "Standard Lucky Block",
			Uncommon = "Uncommon Lucky Block",
			Rare = "Rare Lucky Block",
			Epic = "Epic Lucky Block",
			Legendary = "Legendary Lucky Block",
			Mythic = "Mythic Lucky Block",
			Mystery = "Mystery Lucky Block",
			GrandOpening = "Grand Opening Lucky Block",
			Lucky8 = "Lucky 8 Block",
			Sky = "Sky Lucky Block",
			Starter = "Starter Lucky Block",
			Gift = "Gift Lucky Block",
		} :: { [string]: string },
		-- Over a held block whose timer is done (designer, 2026-10-05), where its countdown was.
		Ready = "READY!",
		-- The Gift's fall from the sky, the first time a player comes back (GiftDrop).
		GiftTitle = "A GIFT FELL FROM THE SKY!",
		GiftSub = "Thanks for coming back. Pick it up!",
		GiftPickUp = "Pick up",
		-- The kinds' short names (the Mystery block's odds list).
		Short = {
			Standard = "Standard",
			Uncommon = "Uncommon",
			Rare = "Rare",
			Epic = "Epic",
			Legendary = "Legendary",
			Mythic = "Mythic",
		} :: { [string]: string },
		ReadyIn = "Ready in %s", -- a block still on its timer: "Ready in 1:42"
		Bag = "Bag", -- the hotbar's bag button and the panel's title
		BagCount = "+%d", -- blocks waiting in the bag
		BagHint = "Click a block to equip it, or drag it to the hotbar", -- under the bag's grid
		BagHintPad = "Press A on a block to equip it", -- the same on a gamepad
		BagEmpty = "No lucky blocks yet",
		SkipUnavailable = "Timer skips are unavailable right now. You can still wait for the timer.",
		Open = "Open", -- the prompt over a thrown block
		YouGot = "YOU GOT %s!", -- the result card: the cue's name
		Continue = "Tap to continue",
		ContinuePad = "Press A to continue",
		ContinueMouse = "Click to continue",
		-- A refused BlockRequest (LuckyBlocks.Reasons).
		Reasons = {
			BadRequest = "Something went wrong. Try again.",
			TooFast = "Slow down a little.",
			NotLoaded = "Your save is still loading.",
			NotOwned = "That block is gone.",
			NotReady = "Not ready yet.",
			NotHeld = "Hold the block first.",
			Busy = "Move to a clear spot, or wait for this block to finish opening.",
			NoBody = "You can't throw that right now.",
			TooFar = "Get closer to the block.",
			NotLanded = "Wait for it to land.",
			Reveal = "Tap the Mystery block's slot to open it!",
			NotMystery = "That block opens in the world.",
			Error = "Something went wrong. Try again.",
		} :: { [string]: string },
		-- A ready Mystery block's hotbar slot (designer, 2026-10-07: like Star Drop).
		OpenSlot = "OPEN!",
		-- The Mystery block's upgrade screen (MysteryReveal).
		Reveal = {
			Title = "MYSTERY", -- over the block before the first press
			Tiers = {
				Standard = "STANDARD",
				Uncommon = "UNCOMMON",
				Rare = "RARE",
				Epic = "EPIC",
				Legendary = "LEGENDARY",
				Mythic = "MYTHIC",
			} :: { [string]: string },
			Chances = "UPGRADE CHANCES", -- over the dots
			Tap = "Tap!", -- under the block while presses are left
			TapMouse = "Click!",
			TapPad = "Press A",
			Collect = "Tap to collect", -- after the last press
			CollectMouse = "Click to collect",
			CollectPad = "Press A to collect",
		},
	},
	-- The lucky block reel's skip hint (LuckyOpening, UltSpinAnim, PullCutscene, ResultCutscene).
	Reel = {
		SkipTouch = "Tap to skip",
		SkipMouse = "Click to skip",
		SkipPad = "Skip", -- after the gamepad's A button picture
	},
	-- The Free Reward page (FreeRewardMenu; GUI lane, D4).
	FreeReward = {
		GroupTitle = "Join the group",
		GroupLine = "Plus +%s%% money from every match while you are in it.",
		Join = "Join",
		FavoriteTitle = "Favorite the game",
		FavoriteLine = "Tap the star, then come back here.",
		Favorite = "Favorite",
		Claim = "Claim",
		LikeToo = "Liking the game helps us too!",
		AllDone = "All claimed. Thank you!",
		NotYet = "Not favorited yet. Try again!",
		NotMember = "Join the group first, then press Claim.",
	},
	-- The Settings screen (SettingsMenu; GUI lane, C10).
	Settings = {
		Title = "Settings",
		Rows = {
			Sfx = "Sound effects",
			LowFx = "Lower effects",
			ShowFlag = "Show my country flag",
		},
		Lines = {
			Sfx = "Clicks, shots and ability sounds.",
			LowFx = "Fewer particles. Smoother on slower devices.",
			ShowFlag = "Other players see it in the player list.",
		},
		On = "ON",
		Off = "OFF",
	},
	-- The player list and the global boards (PlayerList, Leaderboards; GUI lane, C7).
	PlayerList = {
		Header = "Players (%s)", -- people here
		WinsColumn = "Wins", -- vs players
		MoneyColumn = "Money",
		Wins = "%s wins", -- vs players (the lobby signs)
		You = "You",
		Trade = "Trade",
		AddFriend = "Add friend",
		Profile = "View profile",
		TradeSent = "Trade request sent!",
		-- The lobby signs.
		SignWins = "MOST WINS VS PLAYERS",
		SignRank = "HIGHEST RANK",
		SignEmpty = "Be the first!",
	},
	-- The trade screen (TradeMenu; GUI lane, D12). Names are usernames.
	Trade = {
		Title = "Trade with %s",
		You = "You",
		Ready = "READY",
		NotReady = "Not ready",
		TheyReady = "READY!",
		Waiting = "Waiting...",
		Undo = "Undo READY",
		YourItems = "Your items",
		TheirItems = "Their items",
		TapToAdd = "Tap an item to add it",
		TapToAsk = "Tap an item to ask for it",
		TheyWant = "They want this!",
		Asked = "Asked!",
		NoItems = "Nothing you can trade yet",
		TheyHaveNone = "They have nothing to trade yet",
		Full = "Your side is full",
		Lopsided = {
			Mine = "Careful! You give far more than you get!",
			Theirs = "Big deal for you: they give far more!",
		},
		Problems = {
			Empty = "Both sides need at least one item",
			NotTradable = "One of these items can't be traded",
			NotOwned = "One of these items is gone",
			PaidBlocked = "Bought items can't be traded here",
			Owned = "One of these cues is one per player, and it's already owned",
		},
		Closed = {
			Done = "TRADE DONE!",
			Cancelled = "Trade cancelled",
			Left = "They left the server",
			Failed = "The trade failed. Nothing moved.",
		},
		Invite = "%s wants to trade!",
		Accept = "Accept",
		Decline = "Decline",
		Declined = "%s said no",
		Reasons = {
			NotHere = "They are not here anymore",
			Busy = "They are already trading",
			NoInvite = "That invite ran out",
			NoSession = "This trade is over",
			Full = "You asked for enough already",
			TooFast = "Slow down a little",
			Default = "That didn't work. Try again",
		},
	},
	-- The hub's small corner buttons (HubCorners; GUI lane, C2).
	Corners = {
		Challenge = "Daily Challenge",
		ChallengeSoon = "Daily Challenges are coming soon!",
		Invite = "Invite",
		InviteFailed = "Invites are not available right now.",
		Plus = "Plus",
		Settings = "Settings",
		-- The open offers under the Daily Challenge (no popups; designer 2026-10-03).
		Starter = "Starter Pack",
		Vip = "VIP %d%% OFF", -- VIP's welcome offer: "VIP 50% OFF"
	},
	-- The banner at the top middle (Banner). Names are players' usernames.
	Banner = {
		-- "Painicane unboxed a Legendary Cue!" (username), by rarity; never the cue's name
		-- (designer 2026-10-05).
		Unbox = {
			Common = "%s unboxed a Common Cue!",
			Uncommon = "%s unboxed an Uncommon Cue!",
			Rare = "%s unboxed a Rare Cue!",
			Epic = "%s unboxed an Epic Cue!",
			Legendary = "%s unboxed a Legendary Cue!",
			Mythic = "%s unboxed a Mythic Cue!",
			Secret = "%s unboxed a Secret Cue!",
			Default = "%s unboxed a Cue!",
		},
		-- A Mythic or Secret pull, announced in every server (designer 2026-10-05): the
		-- username; never the cue's name.
		Global = {
			Mythic = "[GLOBAL]: %s pulled a Mythical Cue!",
			Secret = "[GLOBAL]: %s pulled a Secret Cue!",
		},
		PartyStarted = "%s started a Money Party!", -- the buyer's username
		PartyStartedAnon = "A Money Party started!",
		-- The countdown while it runs: the multiplier ("2"), the time left, the buyer.
		Party = "Money Party! %sx money for everyone: %s (from %s)",
		PartyAnon = "Money Party! %sx money for everyone: %s",
		Reyes = "%s reached Reyes!",
		FirstReyes = "%s is the first player ever to reach Reyes!",
		-- A cue new to your Index (not from a block), and its finder's money: the cue's name,
		-- then "$500".
		Found = "New in your Index: %s! +%s",
		FoundNoMoney = "New in your Index: %s!",
		-- An ability spin landing a Legendary (this server) or a Mythic (every server): the
		-- username, then the ability's name (in its rarity colour).
		Ult = {
			Legendary = "%s rolled the Legendary ability %s!",
			Mythic = "%s rolled the Mythic ability %s!",
			Default = "%s rolled %s!",
		},
	},
	-- Ultimates (docs/prompts/ULTIMATES_PROMPT.md): the catalog's names and one-line
	-- descriptions (placeholder text; each ult's own session rewrites its line), rarity words.
	-- Players call them Abilities (designer, 2026-09-28: "Ult doesn't look right"), so every
	-- line here says ability / ABILITY; the keys and the code keep the name Ult.
	Ults = {
		Names = {
			Magnet = "Magnet",
			EaglesEye = "Eagle's Eye",
			SuperBounce = "Super Bounce",
			Rewind = "Rewind",
			CatchABall = "Catch-a-Ball",
			LookOverThere = "Look Over There!",
			Verity = "Verity",
			TimeStop = "Time Stop",
			ChainLightning = "Chain Lightning",
			Portals = "Portals",
			SteelBall = "Steel Ball",
			BlackFlash = "Black Flash",
			BlackHole = "Black Hole",
			GuangdongTiger = "Guangdong Tiger",
		},
		Descriptions = {
			Magnet = "The first ball your next shot hits is pulled into a pocket it nearly misses.",
			EaglesEye = "See the full path of your shot, every bounce included.",
			SuperBounce = "The cue ball turns rainbow and keeps bouncing. The first ball of yours it hits bounces too, and boings off a pocket's jaw straight in.",
			CatchABall = "Your cue ball becomes a catch ball. The first ball it hits is caught inside, then it hops to your nearest ball and catches that too. Both count as pocketed.",
			LookOverThere = "Point up and yell! While your opponent looks away, move the cue ball anywhere you like before they turn back. Then take your shot.",
			Verity = "Hi, I'm Verity! Trust me... The first ball you hit gets eaten (it counts as pocketed), then she rolls on, shoving every ball out of her way.",
			Rewind = "Miss, and the table rewinds for another 10 s shot with its full path shown. Up to twice.",
			TimeStop = "Time freezes a second after contact: you get 8 seconds for one more shot while everything stands still. Hit one of your balls and it rolls into a pocket when time resumes.",
			ChainLightning = "Lightning strikes the ball of yours you hit and drives it into a pocket, then jumps on to the next ball, pushing it toward a pocket.",
			Portals = "Place two portals for your whole turn. Balls that roll over one fly out of the other, and yours fly out into the pocket nearest the exit.",
			SteelBall = "The ball of yours you hit is guided in, and the cue ball curves on to your next, guiding it in or lining it up.",
			BlackFlash = "The first ball you hit shatters in a black flash, counted as pocketed, and the blast nudges the balls round it toward pockets.",
			BlackHole = "A black hole opens at your first hit and swallows the balls near it, counted as pocketed.",
			GuangdongTiger = "A giant tiger swipes the balls near your first hit off the table, counted as pocketed.",
		},
		Rarities = {
			Common = "Common",
			Uncommon = "Uncommon",
			Rare = "Rare",
			Epic = "Epic",
			Legendary = "Legendary",
			Mythic = "Mythic",
		},
		ComingSoon = "Coming soon", -- a placeholder ability (no effect yet)
		-- The activation cutscene (UltCutscene): this over the panel's top edge, the ult's name
		-- (Names above) over its bottom edge.
		Cutscene = {
			Title = "ABILITY",
		},
		-- The ability bar in a match (UltHud, UltBar), and the NO ABILITIES pills (MatchHUD, the result
		-- screen).
		Hud = {
			Title = "ABILITY", -- over the bar
			Percent = "%d%%", -- in the bar: "34%"
			Ready = "READY! %d%%", -- the full bar: "READY! 100%"
			Gain = "+%d", -- a gain floating up from the bar: "+34"
			-- The prompt over the ready bar. %s is where the key or the controller button's
			-- picture goes (keep it when translating).
			PressKey = "PRESS %s TO ACTIVATE",
			Tap = "TAP TO ACTIVATE", -- on touch, where the whole bar is the button
			Armed = "%s: NEXT SHOT", -- your armed ability, its name in upper case: "MAGNET: NEXT SHOT"
			OpponentArmed = "Opponent's ability: %s", -- theirs: "Opponent's ability: MAGNET"
			NoUlts = "NO ABILITIES", -- an abilities-off queue match, on the match bar and the result screen
			-- Why a press did nothing (UltNotice's reason, from Ults/Match.check and UltService).
			Refused = {
				NotReady = "Your ability bar isn't full yet",
				Break = "No abilities on the break",
				NotYourTurn = "Only on your turn, before you shoot",
				Moving = "Wait for the balls to stop",
				Armed = "Your ability is already armed",
				Used = "No more abilities this game",
				Off = "Abilities are off at this table",
				BallInHand = "You already have ball in hand!", -- Look Over There!
				TooFast = "Slow down a little!",
				Busy = "One moment...",
				Default = "You can't use your ability right now",
			},
		},
		-- The spin service's answers (UltRequest and UltAuto; the codes are listed in Net.luau
		-- and Ults/SpinView.Reasons). Anything unknown says Strings.Menus.Reasons.Default.
		Spins = {
			Reasons = {
				BadRequest = "That didn't work. Try again.",
				TooFast = "Slow down a little!",
				Busy = "One moment...",
				NotLoaded = "Your save is still loading...",
				Teleporting = "You're on your way to a match.",
				NotLive = "Ability spins are coming soon!",
				NotOwned = "Buy this slot first.",
				Locked = "Slot locked",
				NoSpins = "No spins left.",
				NoLucky = "No Lucky Spins left.",
				LuckyClosed = "Lucky Spins open once rarer abilities are in the game.",
				Confirm = "Replace %s?", -- the ability's name, upper case in its rarity colour
				AutoRunning = "Stop Auto Spin first.",
				NoVip = "Auto Spin needs VIP.",
				Restricted = "Buying spins isn't available where you live. Free spins still work.",
				NotEnoughMoney = "Not enough money.",
				TooMany = "You hold the most spins allowed.",
				Owned = "You already own this slot.",
				ComingSoon = "Coming soon!",
				Error = "Something went wrong. Try again soon.",
			},
			-- Why Auto Spin stopped (UltAuto's reason); the others use Reasons above.
			AutoStops = {
				Reached = "Auto Spin: got %s!", -- the ability's name
				Stopped = "Auto Spin stopped.",
				Closing = "Auto Spin stopped: the server is restarting.",
				Confirm = "Auto Spin stopped before replacing %s.", -- the ability's name
				Locked = "Auto Spin stopped: the slot is locked.",
				NoSpins = "Auto Spin stopped: no spins left.",
				NoLucky = "Auto Spin stopped: no Lucky Spins left.",
			},
			Bought = "+%d spins!", -- money spins bought: "+5 spins!"
		},
		-- The spin screen (UltScreen and its parts; reference 09). Ability and rarity names come from
		-- Names and Rarities above; money is "$1,750" (Progression/Format); a Robux price is
		-- Strings.Menus.Shop.Robux.
		Screen = {
			Column = "ABILITIES", -- the left column's tile, in capitals
			Current = "CURRENT ABILITY:",
			DescriptionSoon = "%s (Coming soon)", -- a placeholder ability's description
			-- The slot cards.
			None = "NONE", -- an empty slot, or one not bought yet
			Equipped = "EQUIPPED",
			Select = "SELECT",
			Purchase = "PURCHASE %s", -- the R$ price: "PURCHASE \u{E002}59"
			Soon = "Soon", -- a slot pass or spin pack whose product is not made yet
			-- The bottom centre.
			Spin = "SPIN",
			FreeSpin = "FREE SPIN", -- while today's free spin is unused
			SlotLocked = "SLOT LOCKED", -- SPIN greyed while the selected slot is locked
			SpinsLeft = "SPINS LEFT: %s",
			LuckySpins = "LUCKY SPINS: %s",
			Back = "BACK TO MENU",
			-- The odds.
			Odds = "Odds", -- the phone's button and the popup's title
			OddsBar = "%s %s", -- a rarity bar: "Common 55%"
			OddsSoon = "Soon", -- a placeholder ability in a bar's list (it can't be rolled yet)
			LuckyOdds = "Lucky odds", -- the switch that shows a Lucky Spin's odds
			PityNote = "Spin %d without an Epic or better is always Epic or better.",
			-- The code box. %s is the code, or the likes, drawn in gold (keep it when translating).
			CodeLine = "USE CODE %s FOR FREE SPINS",
			NextCode = "NEXT CODE AT %s LIKES",
			-- The bottom right.
			Pity = "Pity: %s / %s",
			BuySpins = "Buy spins", -- the phone's button and the popup's title
			Buy = "BUY %d",
			BuyLucky = "BUY LUCKY %d",
			Robux = "R$", -- the R$ / $ toggle's halves
			Money = "$",
			BoughtOne = "+1 spin!", -- money spins bought (more: Spins.Bought)
			Prompted = "Finish the purchase in the Roblox window.",
			-- Replacing an Epic or better (the title is Spins.Reasons.Confirm: "Replace BLACK FLASH?").
			ReplaceText = "Your %s will be replaced by a new ability.", -- the ability's name
			ReplaceYes = "Replace",
			ReplaceNo = "Keep",
			PityHit = "PITY!", -- over the name when the pity spin landed
			-- VIP's Skip and Auto Spin (section 9.6).
			Skip = "Skip",
			AutoSpin = "AUTO SPIN",
			AutoStop = "STOP (%d)", -- Auto Spin running: spins made so far
			AutoTitle = "Auto Spin",
			AutoText = "Spin until you get:",
			AutoStopAt = "%s+", -- a rarity: "Epic+"
			AutoLucky = "Use Lucky Spins",
		},
		-- Catch-a-Ball's popups over the catch ball (CatchABallFx).
		Catch = {
			Gotcha = "GOTCHA!",
			Double = "DOUBLE CATCH!",
			BrokeFree = "IT BROKE FREE!",
		},
		-- Verity's speech bubble (src/client/VerityFx.luau): when she refuses the 8.
		Verity = {
			NotThe8 = "NOT THE 8!",
		},
		-- Look Over There! (LookOverThereFx): what the shooter "says" in the chat (a bubble and
		-- a chat line in their name; the designer's own words, spelling and all), and the
		-- sneak's prompt (by the last input) and countdown on the shooter's screen.
		LookOverThere = {
			Shout = "OMG LOOKK AT THAT!",
			MoveTouch = "QUICK! DRAG THE CUE BALL ANYWHERE!",
			MoveMouse = "QUICK! DRAG THE CUE BALL ANYWHERE!",
			MovePad = "QUICK! MOVE THE CUE BALL WITH THE STICK!",
			Countdown = "%.1f", -- the seconds left: "2.4"
		},
		-- The aim-phase pick view (UltPick): a lock-on's ball, Portals' two spots, chosen in
		-- the top-down view before the shot. The title pill follows the last input (touch,
		-- mouse or gamepad).
		Pick = {
			OwnBallTouch = "TAP ONE OF YOUR BALLS",
			OwnBallMouse = "CLICK ONE OF YOUR BALLS",
			OwnBallPad = "PICK ONE OF YOUR BALLS",
			PortalA = "PLACE PORTAL A",
			PortalB = "PLACE PORTAL B",
			Adjust = "DRAG TO ADJUST, THEN CONFIRM", -- both placed (touch and mouse)
			AdjustPad = "MOVE TO ADJUST, THEN CONFIRM", -- both placed (gamepad)
			Blocked = "KEEP CLEAR OF BALLS, RAILS AND POCKETS", -- a portal on a refused spot
			TooClose = "MOVE THE PORTALS APART",
			Confirm = "CONFIRM",
			Reset = "RESET",
			LetterA = "A", -- on the portals' rings
			LetterB = "B",
			-- The controller guide's words while picking (PadGuide).
			Pad = {
				Move = "Move", -- the left stick
				NextBall = "Next ball", -- the D-pad
				Pick = "Pick", -- A (PlayStation Cross)
				Place = "Place",
				Switch = "Switch portal", -- Y (PlayStation Triangle)
				Reset = "Reset", -- L1
				Confirm = "Confirm", -- X (PlayStation Square)
			},
		},
	},
	-- The bots (the Bots lane). Names: "Bronze Bot" for Play against PC; the made-up names of
	-- disguised bots are built from these parts (src/shared/Bots/Look.luau) and checked on the
	-- server so none is a real username.
	Bots = {
		PcName = "%s Bot", -- the tier's name: "Gold Bot"
		Angry = "AUGHHHH!", -- the tutorial bot's last word (bubble and chat)
		ChatLine = "%s: %s", -- the chat line a bot "says": name, words
		FillPc = "Fill with PC", -- 2v2/3v3 host card, once the host's side is full
		NameParts = {
			Adjectives = {
				"Pixel",
				"Shadow",
				"Turbo",
				"Frosty",
				"Sunny",
				"Lucky",
				"Cosmic",
				"Silent",
				"Crazy",
				"Happy",
				"Fuzzy",
				"Golden",
				"Mighty",
				"Swift",
				"Sneaky",
				"Royal",
				"Neon",
				"Spicy",
				"Sleepy",
				"Epic",
				"Tiny",
				"Brave",
				"Icy",
				"Wild",
				"Cool",
				"Super",
				"Mega",
				"Dark",
				"Blue",
				"Red",
				"Toxic",
				"Electric",
				"Lazy",
				"Salty",
				"Chill",
				"Bouncy",
				"Hyper",
				"Stormy",
				"Rusty",
				"Velvet",
			},
			Nouns = {
				"Panda",
				"Strike",
				"Toast",
				"Fern",
				"Fox",
				"Wolf",
				"Ninja",
				"Dragon",
				"Noodle",
				"Tiger",
				"Sky",
				"Blade",
				"Comet",
				"Pickle",
				"Waffle",
				"Shark",
				"Bunny",
				"Rocket",
				"Knight",
				"Ghost",
				"Taco",
				"Cookie",
				"Storm",
				"Falcon",
				"Hero",
				"Gamer",
				"Cat",
				"Potato",
				"Bean",
				"Mango",
				"Pixel",
				"Viper",
				"Otter",
				"Raven",
				"Bear",
				"Muffin",
				"Kid",
				"Wizard",
				"Llama",
				"Penguin",
			},
			FirstNames = {
				"mikey",
				"jayden",
				"lily",
				"maya",
				"ethan",
				"ava",
				"liam",
				"noah",
				"emma",
				"zoe",
				"leo",
				"mia",
				"owen",
				"ella",
				"lucas",
				"chloe",
				"ryan",
				"nina",
				"kai",
				"jake",
				"sofia",
				"max",
				"ruby",
				"eli",
				"luna",
				"aiden",
				"isla",
				"ben",
				"ivy",
				"dylan",
				"grace",
				"tyler",
				"aria",
				"caleb",
				"hazel",
				"mason",
				"nora",
				"logan",
			},
			Joins = { "plays", "rblx", "yt", "xd", "official", "gaming", "pro", "fan" },
		},
	},
	-- The first-time tutorial (src/client/Tutorial*.luau; docs/prompts/TUTORIAL_PROMPT.md). The
	-- big instruction line at the top of the screen; a line with a device in its name has one
	-- version per device (Mouse, Touch, Gamepad).
	Tutorial = {
		Skip = "Skip tutorial",
		SkipAsk = "Skip the tutorial?",
		SkipYes = "Yes",
		SkipNo = "No",
		JoinTable = "Join a table!",
		WaitTable = "Waiting for a free table...",
		Finding = "Finding you an opponent...",
		-- Game 1's lessons (the TutorialLesson attribute), per device.
		Break = {
			Mouse = "Pull the power bar all the way down!",
			Touch = "Drag the power bar all the way down!",
			Gamepad = "Hold A to power up, then let go!",
		},
		Aim = {
			Mouse = "Drag to aim at a glowing ball!",
			Touch = "Swipe to aim at a glowing ball!",
			Gamepad = "Tilt the left stick to aim!",
		},
		AimShoot = {
			Mouse = "Now pull the power bar to shoot!",
			Touch = "Now pull the power bar to shoot!",
			Gamepad = "Now hold A, then let go!",
		},
		Ability = {
			Mouse = "Press G to use your ability!",
			Touch = "Tap your ability!",
			Gamepad = "Press X to use your ability!",
		},
		Pick = {
			Mouse = "Click one of your balls!",
			Touch = "Tap one of your balls!",
			Gamepad = "Pick one of your balls with A!",
		},
		PickConfirm = {
			Mouse = "Now click Confirm!",
			Touch = "Now tap Confirm!",
			Gamepad = "Now press X to confirm!",
		},
		BallInHand = {
			Mouse = "Ball in hand! Drag the white ball anywhere.",
			Touch = "Ball in hand! Drag the white ball anywhere.",
			Gamepad = "Ball in hand! Hold L2 and tilt the left stick to move it.",
		},
		-- After game 1 (step 5): the Standard lucky block in the hotbar, held, thrown and
		-- opened (designer, 2026-10-04).
		BlockHold = {
			Mouse = "You won a lucky block! Click it to hold it.",
			Touch = "You won a lucky block! Tap it to hold it.",
			Gamepad = "You won a lucky block! Press RB to hold it.",
		},
		BlockThrow = {
			Mouse = "Now click anywhere to throw it!",
			Touch = "Now tap the ground to throw it!",
			Gamepad = "Now press R2 to throw it!",
		},
		BlockOpen = {
			Mouse = "Walk up and hold E to open it!",
			Touch = "Walk up and hold the button to open it!",
			Gamepad = "Walk up and hold X to open it!",
		},
		-- The Equip step: the new Uncommon cue, equipped through the Cues menu.
		EquipOpen = {
			Mouse = "Equip your new cue! Click Cues.",
			Touch = "Equip your new cue! Tap Cues.",
			Gamepad = "Equip your new cue! Open Cues with A.",
		},
		EquipCard = {
			Mouse = "Click your new cue!",
			Touch = "Tap your new cue!",
			Gamepad = "Press A on your new cue!",
		},
		EquipButton = {
			Mouse = "Click Equip!",
			Touch = "Tap Equip!",
			Gamepad = "Press A to equip it!",
		},
		RareBlock = "Your Rare Lucky Block opens in 5 minutes! Tap it to see.", -- its hotbar slot
		Abilities = {
			Mouse = "Click Abilities!",
			Touch = "Tap Abilities!",
			Gamepad = "Press X to open Abilities!",
		},
		Spin = {
			Mouse = "Click SPIN for a new ability!",
			Touch = "Tap SPIN for a new ability!",
			Gamepad = "Press A to SPIN for a new ability!",
		},
		Code = "Type RELEASE for 3 more spins!",
		CodeRedeem = {
			Mouse = "Type RELEASE, then click Redeem!",
			Touch = "Type RELEASE, then tap Redeem!",
			Gamepad = "Type RELEASE, then press Redeem!",
		},
		CodeOdds = {
			Mouse = "Click Odds, then type RELEASE for 3 more spins!",
			Touch = "Tap Odds, then type RELEASE for 3 more spins!",
			Gamepad = "Open Odds, then type RELEASE for 3 more spins!",
		},
		Back = {
			Mouse = "Click Back!",
			Touch = "Tap Back!",
			Gamepad = "Press B to go back!",
		},
		Eight = {
			Mouse = "SELECT WHICH POCKET!",
			Touch = "SELECT WHICH POCKET!",
			Gamepad = "SELECT WHICH POCKET! D-pad to choose, A to select.",
		},
		-- Game 2 (step 6): back to the lobby after the global queue's game.
		Lobby = {
			Mouse = "Click Lobby!",
			Touch = "Tap Lobby!",
			Gamepad = "Press A to go to the lobby!",
		},
		-- The real server's nudges (step 7), one at a time.
		Nudge = {
			Rank = "Claim your rank rewards!",
			Inventory = "Your cues live in the Cues menu!",
			Shop = "Check out the Shop!",
			FreeReward = "Claim your free reward!",
			BlockReady = "Your block is ready!", -- the Rare block's hotbar slot at 0
		},
	},
	-- Rank rewards held until claimed (RankClaim; the roadmap's claim block, NEW RANK!).
	RankClaim = {
		ClaimLine = "Claim your rewards in Rank!",
		Claim = "CLAIM",
		Ready = "Rewards ready!",
	},
}
