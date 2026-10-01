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
		PadCount = "%d/%d", -- on a pad with players on it: how many, of how many it holds
		PadFull = "FULL",
		PadPlaying = "PLAYING", -- on the pad and the sign while the table's game is on
		Waiting = "WAITING",
		Starting = "STARTING %d", -- the sign's pill while a full pad counts down to its game
		-- The popup everyone free in the server gets when a host requests players
		-- (OpponentPrompt).
		Request = {
			NeedsOpponent = "%s needs an opponent...", -- a 1v1 table
			NeedsPlayers = "%s needs players...", -- a 2v2 or 3v3 table
			Join = "Join",
			Dismiss = "Dismiss",
			GamepadHint = "Y · Join",
		},
		-- The host's card (QueueMenu); everyone else sees the sign over the pad (TableSign).
		Queue = {
			GameTitle = "%s %s", -- the game on the host's card: difficulty, then mode ("Classic 1v1")
			PlayerCount = "%d/%d", -- in the people pill: how many are on the pad, of how many it holds
			Levels = { Classic = "Classic", Difficult = "Difficult", Challenger = "Challenger" },
			PlaySolo = "Play solo",
			PlayPC = "Play against PC",
			-- The host's card adds three dots that light up one by one (QueueMenu.dots).
			WaitingForOpponent = "Waiting for opponent", -- a 1v1 pad with room
			WaitingForPlayers = "Waiting for players", -- a 2v2 or 3v3 pad with room
			RequestOpponent = "Request opponent",
			RequestPlayers = "Request players", -- on the team tables
			Requested = "Requested!", -- on the button while the host waits to ask again
			CancelRequest = "Cancel", -- under Requested!: takes the request back
			StartingIn = "Starting in %d", -- the pad is full: the game starts by itself
			GamepadHint = "Y · Menu",
			-- The global queue (designer, 2026-09-28): the host's 4th choice, and the card while
			-- it searches every server for a side of similar rank.
			GlobalQueue = "Join Global Queue",
			GlobalNeeds = "Needs %d on the pad", -- under the greyed button on 2v2 and 3v3
			SearchingWorld = "Searching worldwide", -- the status line, with the dots
			SearchTime = "Searching %d:%02d", -- on the greyed button: minutes and seconds
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
		TimeStopHint = "TIME STOPPED · ONE MORE SHOT",
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
		-- The host card's Abilities: On / Off toggle, and the abilities-off search's offer after
		-- Config.GlobalQueue.NoUltsFallbackSeconds (QueueMenu).
		UltsOn = "Abilities: On",
		UltsOff = "Abilities: Off",
		NoUltsFallback = "Nobody's searching with abilities off. Search with them on?",
		FallbackYes = "Yes",
		FallbackNo = "No",
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
		Numerals = { "I", "II", "III", "IV", "V" },
		Division = "%s %s", -- tier, numeral: "Gold III"
		XpOf = "%s / %s XP", -- the XP bar: "520 / 1,000 XP"
		XpOnly = "%s XP", -- Reyes has no top: just the XP past its start
		ChatTag = "[%s]", -- before a name in chat, the tier in capitals: "[PLATINUM]" (ChatTags)
		VipTag = "[VIP]", -- first before a VIP player's name in chat, in the house rainbow (ChatTags)
	},
	-- The developer chat commands' private replies (DevCommands; shown only to the caller).
	Dev = {
		Help = "Rank and money commands: /rank <tier> [1-5] [xp], /rank unranked, /xp <amount>, /money <amount>, /addmoney <amount>, /result win|lose|draw|firstwin, /newrank [tier] [1-5], /resetdata. Economy commands: /econhelp. Ability commands: /abilityhelp. Put a player's username last to give it to them instead (/rank, /xp, /money, /addmoney, /givecue, /givecase, /spins, /lucky, /ability, /abilitysetup).",
		BadRank = "Try /rank gold 3, /rank reyes or /rank unranked.",
		BadAmount = "Give a whole number, like %s 500.",
		XpNeverLost = "XP is never lost: give a gain, like %s 250.",
		BadResult = "Try /result win, /result lose, /result draw or /result firstwin.",
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
			GiveCase = "%s <%s> [count] [player]", -- the case ids
			OpenCase = "%s <%s>",
			Inv = "%s",
			ClearInv = "%s",
			Dupes = "%s",
			SetDay = "%s <1-%d> [week 1-%d]",
			NewDay = "%s",
			Playtime = "%s <minutes>",
			Buy = "%s <product> [purchaseId]",
			Vip = "%s on|off",
			FastOpen = "%s on|off",
			Party = "%s",
			Policy = "%s restricted|normal",
			Sale = "%s <case> <percent> <minutes>, or %s off",
			Rookie = "%s <real matches>",
			FreeCase = "%s",
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
			GiveCase = "unopened cases",
			OpenCase = "opens one on the reel like the button (gives you one if you have none)",
			Inv = "lists your cues, cases and equipped cue",
			ClearInv = "takes every cue but Classic and every case",
			Dupes = "%d copies each of %d random Common and Uncommon cues (to test selling)",
			SetDay = "your next daily claim becomes that streak day",
			NewDay = "as if a new UTC day began (daily claim, playtime, today's limits)",
			Playtime = "sets today's minutes played",
			Buy = "a Robux purchase's grant, without Robux. Products: %s",
			Vip = "fakes owning the VIP pass for this session",
			FastOpen = "fakes owning Fast Open for this session",
			Party = "starts or extends a Money Party in this server",
			Policy = "fakes PolicyService (restricted: no cases for money)",
			Sale = "a case sale in this server",
			Rookie = "sets your real matches played (the Rookie Boost)",
			FreeCase = "the free-case rule, as if you won a real match",
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
		BadCase = 'No case called "%s". Cases: %s.',
		BadProduct = 'No product called "%s". Products: %s.',
		ClassicCue = "The Classic Cue is always yours.",
		UniqueCue = "The %s is Unique (numbered copies): buy it on the Shop's Limited shelf.",
		UniqueCueBuy = "The %s is Unique (numbered copies): try %s %s.",
		ExclusiveOwned = "You already own the %s (Exclusive: one each).",
		NotGiven = "No %s given (you hold the most allowed).",
		GaveCue = "Gave %s x%d.",
		GaveCase = "Gave %s x%d.",
		Opening = "Opening a %s.",
		InvEquipped = "Equipped: %s",
		InvCases = "Cases: ",
		InvNoCases = "Cases: none",
		InvCues = "Cues (%d kinds, %d copies): ",
		InvNoCues = "Cues: only the Classic Cue",
		InvCount = "%s x%d", -- a cue or case with more than one copy
		InvCopy = "%s #%d", -- a Unique cue's copy number
		Cleared = "Your cues (but Classic) and cases are gone.",
		Dupes = "Gave %d copies each of: %s.",
		DaySet = "Your next daily claim is day %d of week %d.",
		NewDay = "A new day: the daily claim, playtime gifts and today's limits start over.",
		PlaytimeSet = "Today's playtime is %d minutes.",
		Buying = "Granting %s...",
		Bought = "%s granted.",
		BuyFailed = "%s not granted: %s.",
		PassNames = { Vip = "VIP", FastOpen = "Fast Open" },
		PassOn = "%s pass on (faked for this session).",
		PassOff = "%s pass off (faked for this session).",
		VipOfferStays = "VIP from the welcome offer stays: /resetdata clears it.",
		Party = "Money Party on in this server for %d more minutes.",
		PolicyOn = "Paid random items restricted for you (no cases for money).",
		PolicyOff = "Paid random items allowed for you again.",
		SaleOn = "%s: %d%% off in this server for %d minutes.",
		SaleOff = "The case sale is over.",
		SaleNotSold = "The %s is not sold in the shop, so it cannot go on sale.",
		RookieSet = "Real matches set to %d: %d left in the Rookie Boost.",
		FreeCaseGave = "This win gave a %s (win %d today, %d ever).",
		FreeCaseFirst = "Your first win's %s opened into the %s (win %d today, %d ever).",
		FreeCaseNone = "No case this win (win %d today, %d ever).",
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
	},
	-- The rank and money screens (ResultScreen, NewRankPopup, Roadmap, RankHud).
	Progress = {
		WinStreak = "🔥 %d", -- over a player's name: their wins in a row (Nameplates)
		Winner = "WINNER",
		Vs = "VS",
		Draw = "DRAW",
		SoloGame = "SOLO GAME",
		Left = "LEFT", -- on the card of a player who left the match
		NoXp = "No XP: match under a minute",
		SoloNoXp = "Solo games give no XP",
		XpDelta = "+%s XP", -- "+250 XP", "+0 XP" (XP is never lost)
		-- The XP boosts on the result screen (ECONOMY 4.5) and the rank HUD's Rookie pill: a
		-- boost of +100% or more as a multiplier ("ROOKIE x2": 1 + the boost), a smaller one
		-- as a percent ("VIP +50%").
		BoostTimes = {
			Rookie = "ROOKIE x%s",
			FirstWin = "FIRST WIN x%s",
			Vip = "VIP x%s",
			Streak = "STREAK x%s",
		},
		BoostPercent = {
			Rookie = "ROOKIE +%s%%",
			FirstWin = "FIRST WIN +%s%%",
			Vip = "VIP +%s%%",
			Streak = "STREAK +%s%%",
		},
		BallsLine = "Balls pocketed x%d",
		NiceLine = "Nice shots x%d",
		WinBonus = "Win bonus",
		LossBonus = "Match bonus",
		StreakLine = "Win streak", -- the win-streak money (ECONOMY 3.1), from the 3rd win in a row
		RankReward = "Rank reward",
		Total = "Total",
		FreeCase = "+%d %s", -- the free case on the result screen: "+1 Standard Case"
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
		RewardCount = "x%d", -- how many: "x2" (a case's count on NEW RANK!)
		RewardCaseCount = "%s x%d", -- the roadmap's case tile: "Epic Case x2"
		RewardChatTag = "Chat Tag",
		TierCue = "%s Cue", -- a tier with no cue in the catalog: "Platinum Cue"
	},
	-- Cues, cases and rarities by id (Progression/Catalog, Progression/Cases). Placeholder cue
	-- names (2026-09-28, overnight): pool and rooftop words, replaced when real cues arrive.
	Items = {
		Cues = {
			Classic = "Classic Cue",
			ChalkDust = "Chalk Dust Cue",
			CornerPocket = "Corner Pocket Cue",
			RooftopBreeze = "Rooftop Breeze Cue",
			RackRunner = "Rack Runner Cue",
			SideSpin = "Side Spin Cue",
			FeltGreen = "Felt Green Cue",
			BankShot = "Bank Shot Cue",
			Skyline = "Skyline Cue",
			TikiTorch = "Tiki Torch Cue",
			PalmShade = "Palm Shade Cue",
			SunsetRail = "Sunset Rail Cue",
			KickShot = "Kick Shot Cue",
			CushionCrusher = "Cushion Crusher Cue",
			HarborLights = "Harbor Lights Cue",
			Masse = "Massé Cue",
			NeonPocket = "Neon Pocket Cue",
			OceanBreak = "Ocean Break Cue",
			RailRider = "Rail Rider Cue",
			Tidewater = "Tidewater Cue",
			ThunderBreak = "Thunder Break Cue",
			VioletVortex = "Violet Vortex Cue",
			Penthouse = "Penthouse Cue",
			Nightcap = "Nightcap Cue",
			JumpJet = "Jump Jet Cue",
			GoldenBreak = "Golden Break Cue",
			SolarFlare = "Solar Flare Cue",
			CrownJewel = "Crown Jewel Cue",
			Starfall = "Starfall Cue",
			Nebula = "Nebula Cue",
			Eclipse = "Eclipse Cue",
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
			FoundersCue = "Founder's Cue",
			BetaCue = "Beta Cue",
		},
		Cases = {
			Standard = "Standard Case",
			Rare = "Rare Case",
			Epic = "Epic Case",
			Legendary = "Legendary Case",
			Event = "Event Case",
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
		Column = { Shop = "Shop", Inventory = "Inventory", Rewards = "Rewards", Trade = "Trade" },
		-- Each menu's title in its header band.
		Titles = { Shop = "Shop", Inventory = "Inventory", Rewards = "Rewards", Trade = "Trade" },
		-- The tabs under (or beside) each title.
		Tabs = {
			Shop = { Cases = "Cases", Limited = "Limited", Money = "Money", Vip = "VIP" },
			Inventory = { Cues = "Cues", Cases = "Cases", Index = "Index" },
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
			NotLoaded = "Your save is still loading...",
			Teleporting = "You're on your way to a match.",
			Error = "Something went wrong. Try again soon.",
			NotSold = "That isn't for sale.",
			Restricted = "Buying cases isn't available where you live.",
			NotEnoughMoney = "Not enough money.",
			NoCases = "You don't have that case.",
			NoFastOpen = "Open 10 needs Fast Open.",
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
			Closed = "This offer isn't open right now.",
			PartyFull = "The Money Party is already full for the next hour.",
			ComingSoon = "Coming soon!",
			AlreadyClaimed = "Already claimed today. Come back tomorrow!",
			NotReady = "Not ready yet. Keep playing!",
			Unknown = "That code doesn't exist.",
			Used = "You already used that code.",
			Expired = "That code has expired.",
		},
		-- The Shop (ShopMenu and its pages ShopCases, ShopOdds, ShopLimited, ShopMoney, ShopVip).
		-- Case and cue names come from Items; money is "$1,500" (Progression/Format).
		Shop = {
			-- Buying, on every tab.
			Buy = "Buy",
			BuyMany = "Buy %d", -- the bulk button: "Buy 10"
			Need = "Need %s more", -- a buy button while money is short: "Need $1,200 more"
			NeedNotice = "You need %s more. A money pack covers it!", -- after the jump to Money
			ComingSoon = "Coming soon", -- a Robux item whose product is not made yet
			OwnedWord = "Owned",
			-- A Robux price: Roblox's own Robux glyph (U+E002, it renders in our font), then the
			-- number with commas. Keep the glyph when translating.
			Robux = "\u{E002}%s",
			-- The Cases tab.
			Odds = "Odds", -- the button that lists every cue's chance (a word, not only an icon)
			Guarantee = "Guaranteed %s or better", -- the case's lowest rarity, in its colour
			GuaranteeAll = "Any rarity can drop", -- a case whose lowest rarity is the bottom one
			BulkDeal = "Pay for %d", -- the pill on Buy 10: ten for the price of nine
			Owned = "x%d", -- on the chest: how many of that case you have
			SaleOff = "%d%% OFF", -- a case on sale: "20% OFF"
			SaleEnds = "Sale ends in %s",
			Restricted = "Buying cases with money isn't available where you live. Cases you earn still open.",
			Bought = "Bought!", -- the dialog after buying a case
			BoughtOne = "Your %s is in your Inventory.", -- the case's name
			BoughtMany = "%s x%d added to your Inventory.", -- the case's name, how many
			OpenNow = "Open now",
			Later = "Later",
			-- The odds panel.
			OddsTitle = "%s odds", -- "Standard Case odds"
			OddsNote = "Every cue of a rarity has the same chance.",
			OddsTotal = "Total: %s", -- "Total: 100%"
			-- The Limited tab.
			Sold = "%s of %s sold", -- "412 of 1,000 sold"
			SoldNoCap = "%s sold",
			EndsIn = "Ends in %s",
			StartsIn = "Starts in %s",
			OnePerPlayer = "One per player",
			OwnedCopy = "Owned #%s", -- your copy's number
			SoldOut = "Sold out",
			Ended = "Ended",
			-- A Limited not on sale yet; also the short "Coming soon" tag where that does not fit.
			Soon = "Soon",
			LimitedBought = "%s #%s is yours!", -- the cue's name, its copy number
			LimitedEmpty = "Nothing on the Limited shelf right now. Check back soon!",
			-- The Money tab.
			FirstDouble = "First purchase: double money!",
			Double = "x2", -- on every pack while the first purchase is unused
			Bonus = "+%d%%", -- a pack's bonus: "+7%"
			BestPick = "Best pick", -- the pack that covers what you need
			Packs = {
				Pack1 = "Handful",
				Pack2 = "Stack",
				Pack3 = "Bundle",
				Pack4 = "Briefcase",
				Pack5 = "Vault",
				Pack6 = "Bank",
				Pack7 = "Fortune",
			},
			-- The VIP tab.
			Vip = "VIP",
			VipMoney = "%sx money in matches", -- "2x money in matches"
			VipXp = "+%d%% XP", -- "+50% XP"
			VipCue = "The %s", -- "The VIP Cue"
			VipName = "[VIP] chat tag and a rainbow name",
			VipOdds = "Same case odds as everyone", -- VIP never changes case odds
			WelcomeOffer = "Welcome offer: %s", -- half-price VIP, its time left
			WelcomeBack = "Welcome back offer: %s", -- the one comeback window
			StarterPack = "Starter Pack",
			StarterLine = "%s + %s", -- the Starter Cue's name, the money: "Starter Cue + $3,000"
			MoneyParty = "Money Party",
			PartyLine = "%sx money for everyone here for %d min", -- the boost, the minutes
			PartyOn = "Party on! %s left", -- a Money Party running here
			PartyOnBy = "Party on! %s left, from %s", -- the time left, the buyer's username
			PartyFull = "Full for now", -- an hour of Money Party already queued
			FastOpen = "Fast Open",
			FastOpenLine = "Open %d cases at once, no reel. Skip ability spins and Auto Spin",
		},
		-- The Rewards (RewardsMenu and its pages RewardsDaily, RewardsPlaytime, RewardsCodes).
		-- Case names come from Items.Cases; money is "$250" (Progression/Format).
		Rewards = {
			-- The Daily tab.
			Day = "Day %d", -- a tile's heading: "Day 1"
			Claim = "Claim",
			Claimed = "Claimed",
			-- Under the tiles: the week of the four-week cycle and its day-28 prize: "Week 1
			-- of 4: a Legendary Case on day 28" (the week, the weeks, the prize, the day).
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
			Redeemed = "Code redeemed: %s", -- "Code redeemed: +$500 and a Standard Case"
			NoCode = "Type a code first.",
			CodeNote = "Codes give free money, cases and ability spins. Each code works once.",
			-- A reward's words. A few cases: "2 Standard Cases"; one, in a sentence: "a Rare
			-- Case" (a case missing here says CaseManyOther / its plain name).
			CaseMany = {
				Standard = "%d Standard Cases",
				Rare = "%d Rare Cases",
				Epic = "%d Epic Cases",
				Legendary = "%d Legendary Cases",
				Event = "%d Event Cases",
			},
			CaseManyOther = "%d x %s", -- the count, the case's name
			CaseA = {
				Standard = "a Standard Case",
				Rare = "a Rare Case",
				Epic = "an Epic Case",
				Legendary = "a Legendary Case",
				Event = "an Event Case",
			},
			CaseCount = "x%d", -- on a case's picture: "x2"
			-- A reward's ability spins (a reward's `spins` and `lucky`): in a sentence or a chip.
			SpinOne = "1 Ability Spin",
			SpinMany = "%d Ability Spins",
			LuckyOne = "1 Lucky Spin",
			LuckyMany = "%d Lucky Spins",
			SpinChip = "+%d", -- on the spin icon of a tile, NEW RANK! or a roadmap tile: "+2"
			Plus = "%s + %s", -- two parts of one tile's reward: "Epic Case + Legendary Case"
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
		-- The Inventory (InventoryMenu and its pages). Rarity and cue names come from Items.
		Inventory = {
			-- The Cues tab.
			-- The sort button over the grid: "Sort: Rarest first"; each press moves to the next
			-- order (Config.UI.Inventory.SortOrders).
			Sort = "Sort: %s",
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
			CopyShort = "#%s", -- a Unique cue's copy number on its card: "#412"
			Copy = "Copy #%s", -- ...and in its details
			Owned = "You own %s", -- "You own 3"
			Exist = "%s exist", -- copies in the whole game: "1,284 exist"
			ExistOne = "%s exists", -- ...when there is just one
			CantSell = "Can't be sold", -- Exclusive, Unique and Classic cues
			Sell = "Sell %s", -- one copy: "Sell $120"
			SellDuplicates = "Sell duplicates: %s", -- this cue's extra copies
			SellAll = "Sell all duplicates: %s", -- every cue's extra copies, top of the tab
			NoDuplicates = "No duplicates",
			Empty = "No cues yet. Open cases to find some!",
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
			-- The Cases tab.
			CasesHint = "Open a case to win a cue!",
			Open = "Open",
			OpenMany = "Open %s", -- Fast Open: "Open 10"
			BuyMore = "Buy more",
			CasesEmpty = "No cases yet! Win matches or visit the Shop to get some.",
			-- The Index tab.
			Titles = "Titles",
			Progress = "%s / %s", -- cues of the row ever owned: "5 / 7"
			Claim = "Claim",
			Claimed = "Claimed",
			Unknown = "?", -- a cue never owned, on its Index card (its look stays hidden)
			-- The chosen cue's panel: its name, rarity, then one of these.
			Found = "In your collection", -- ever owned (selling it keeps it here)
			NotFound = "Not found yet",
			FindReward = "Find it for +%s", -- a cue not found yet: its finder's money ("$250")
		},
	},
	-- The reminder of the next login-streak reward (Reminders; GDD 14, ECONOMY 10): a toast when
	-- Roblox's menu opens or the window loses focus, and the same line on the result screen.
	Reminders = {
		Money = "Come back tomorrow for %s!", -- "$500"
		Case = "Come back tomorrow for your %s!", -- "Rare Case"
		Cases = "Come back tomorrow for %s!", -- "2 Standard Cases" (Menus.Rewards.CaseMany)
		Bonus = "Come back tomorrow for day %d's %s!", -- "day 28's Legendary Case"
		More = "Come back tomorrow for your %s and more!", -- the best of several parts
		Ready = "Your daily reward is ready! Claim it in Rewards.", -- today's is still waiting
	},
	-- The case opening (CaseOpening: the reel, the prize card, Fast Open's grid and the first
	-- win's reveal on the result screen).
	CaseOpening = {
		FastTitle = "%s x%s", -- Fast Open's title: the case's name and the count ("Standard Case x10")
		FirstWin = "First win! %s", -- the result screen's reveal: the case's name ("Rare Case")
		Opening = "Opening...", -- while the server answers
		-- The server is slow to answer (Config.UI.CaseOpening.WaitCloseSeconds): it may be closed.
		WaitingTouch = "Still opening... Tap to close",
		WaitingMouse = "Still opening... Click to close",
		WaitingPad = "Close", -- after the gamepad's B button picture
		-- Closed before the server answered: a line in the menu under it once the prize is in.
		LateOne = "Your cue is in your Inventory.",
		LateMany = "Your cues are in your Inventory.", -- Fast Open
		SkipTouch = "Tap to skip",
		SkipMouse = "Click to skip",
		SkipPad = "Skip", -- after the gamepad's A button picture
		New = "NEW!", -- a cue never owned before
		NewFound = "NEW! +%s", -- a cue never owned before, and its finder's money ("$250")
		Duplicate = "Duplicate",
		DuplicateCount = "Duplicate x%s", -- copies owned now ("Duplicate x3")
		Exist = "%s exist", -- copies in existence ("1,284 exist")
		ExistOne = "%s exists", -- ...when there is just one
		Equip = "Equip",
		Equipped = "Equipped",
		Sell = "Sell %s", -- one copy's price ("Sell $600")
		Sold = "Sold!",
		OpenNextCount = "Open next (%s)", -- cases of this type left ("Open next (3)")
		OpenAgain = "Open %s again", -- Fast Open ("Open 10 again")
		Done = "Done",
		Continue = "Continue",
		SellTitle = "Sell this cue?",
		-- The rarity, the cue's name, the money: "Sell one Epic Violet Vortex Cue for $600?"
		SellConfirm = "Sell one %s %s for %s?",
		SellYes = "Sell",
		SellNo = "Keep",
	},
	-- The banner at the top middle (Banner). Names are players' usernames.
	Banner = {
		-- "Painicane unboxed a Mythic Starfall Cue!" (username, the cue's name), by rarity.
		Unbox = {
			Common = "%s unboxed a Common %s!",
			Uncommon = "%s unboxed an Uncommon %s!",
			Rare = "%s unboxed a Rare %s!",
			Epic = "%s unboxed an Epic %s!",
			Legendary = "%s unboxed a Legendary %s!",
			Mythic = "%s unboxed a Mythic %s!",
			Secret = "%s unboxed a Secret %s!",
			Default = "%s unboxed %s!",
		},
		PartyStarted = "%s started a Money Party!", -- the buyer's username
		PartyStartedAnon = "A Money Party started!",
		-- The countdown while it runs: the multiplier ("2"), the time left, the buyer.
		Party = "Money Party! %sx money for everyone: %s (from %s)",
		PartyAnon = "Money Party! %sx money for everyone: %s",
		Reyes = "%s reached Reyes!",
		FirstReyes = "%s is the first player ever to reach Reyes!",
		-- A cue new to your Index (not from a case), and its finder's money: the cue's name,
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
			Ghost = "Ghost",
			HeatSeeker = "Heat Seeker",
			Rewind = "Rewind",
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
			Ghost = "Your cue ball phases through every ball that isn't yours. The ball it hits phases through them too, and a ghost pulls it into a pocket it nearly misses.",
			HeatSeeker = "Lock on to one of your balls: the cue ball curves round to hit it, and aimed straight at it, it cuts truer.",
			Rewind = "Miss, and the table rewinds for another 10 s shot with its full path shown. Up to twice.",
			TimeStop = "Time freezes a second after contact: you get 8 seconds to line up one more shot while everything else stands still.",
			ChainLightning = "The ball of yours you hit is charged toward a pocket, and lightning jumps on to three more balls, pushing them toward pockets.",
			Portals = "Place two portals for your whole turn. Balls that enter one fly out of the other, and yours come out lined up on a pocket.",
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
				NoFastOpen = "Auto Spin needs Fast Open.",
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
			Column = "Abilities", -- the left column's tile
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
			-- Fast Open (section 9.6).
			Skip = "Skip",
			AutoSpin = "AUTO SPIN",
			AutoStop = "STOP (%d)", -- Auto Spin running: spins made so far
			AutoTitle = "Auto Spin",
			AutoText = "Spin until you get:",
			AutoStopAt = "%s+", -- a rarity: "Epic+"
			AutoLucky = "Use Lucky Spins",
			-- The leave reminder (Reminders), its top line while today's free spin is unused.
			Reminder = "Your FREE SPIN is ready!",
			ReminderButton = "SPIN",
		},
		-- The aim-phase pick view (UltPick): Heat Seeker's ball, Portals' two spots, chosen in
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
}
