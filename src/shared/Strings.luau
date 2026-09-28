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
		Numerals = { "I", "II", "III", "IV", "V" },
		Division = "%s %s", -- tier, numeral: "Gold III"
		XpOf = "%s / %s XP", -- the XP bar: "520 / 1,000 XP"
		XpOnly = "%s XP", -- Reyes has no top: just the XP past its start
		ChatTag = "[%s]", -- before a name in chat, the tier in capitals: "[PLATINUM]" (ChatTags)
		VipTag = "[VIP]", -- after the rank tag for a VIP player, in the house rainbow (ChatTags)
	},
	-- The developer chat commands' private replies (DevCommands; shown only to the caller).
	Dev = {
		Help = "Rank and money commands: /rank <tier> [1-5] [xp], /rank unranked, /xp <amount>, /money <amount>, /addmoney <amount>, /result win|lose|draw|firstwin, /newrank [tier] [1-5], /resetdata. Economy commands: /econhelp",
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
		EconHelp = "Economy commands (they act on you only):",
		HelpLine = "%s: %s",
		Try = "Try %s.",
		Usage = {
			GiveCue = "%s <id|name> [count]",
			GiveCase = "%s <%s> [count]", -- the case ids
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
		-- Index row titles (ECONOMY 18), once a rarity row is complete.
		Titles = {
			Common = "Common Collector",
			Uncommon = "Uncommon Collector",
			Rare = "Rare Collector",
			Epic = "Epic Collector",
			Legendary = "Legendary Collector",
			Mythic = "Mythic Collector",
			Secret = "Secret Keeper",
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
			VipTag = "[VIP] chat tag",
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
			FastOpenLine = "Open %d cases at once, no reel",
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
			CodeNote = "Codes give free money and cases. Each code works once.",
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
			All = "All", -- the filter chip for every cue (the others are the rarities' names)
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
			EmptyFilter = "No %s cues yet. Open cases to find some!", -- a rarity's name
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
			NoTitles = "Complete a row to earn a title!",
			Progress = "%s / %s", -- cues of the row ever owned: "5 / 7"
			Claim = "Claim",
			Claimed = "Claimed",
			Unknown = "?", -- a cue never owned: its name stays hidden
			NotFound = "Not found yet. Keep opening cases!",
			CueInfo = "%s: %s", -- pressing a found cue: "Starfall Cue: Mythic"
			TitleEarned = "Title earned: %s!",
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
		SkipTouch = "Tap to skip",
		SkipMouse = "Click to skip",
		SkipPad = "Skip", -- after the gamepad's A button picture
		New = "NEW!", -- a cue never owned before
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
	},
}
