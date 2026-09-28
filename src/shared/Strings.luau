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
	},
	-- The developer chat commands' private replies (DevCommands; shown only to the caller).
	Dev = {
		Help = "Rank and money commands: /rank <tier> [1-5] [xp], /rank unranked, /xp <amount>, /money <amount>, /addmoney <amount>, /result win|lose|draw, /newrank [tier] [1-5], /resetdata",
		BadRank = "Try /rank gold 3, /rank reyes or /rank unranked.",
		BadAmount = "Give a whole number, like %s 500.",
		BadResult = "Try /result win, /result lose or /result draw.",
		NotLoaded = "Your save is not loaded yet.",
		RankSet = "Rank set to %s.",
		MoneySet = "Money set to %s.",
		Reset = "Your save was reset.",
	},
	-- The rank and money screens (ResultScreen, NewRankPopup, Roadmap, RankHud).
	Progress = {
		WinStreak = "🔥 %d", -- over a player's name: their wins in a row (Nameplates)
		Winner = "WINNER",
		Vs = "VS",
		Draw = "DRAW",
		SoloGame = "SOLO GAME",
		Left = "LEFT", -- on the card of a player who left the match
		NoXpLost = "No XP lost",
		NoXp = "No XP: match under a minute",
		SoloNoXp = "Solo games give no XP",
		XpDelta = "%s XP", -- "+250 XP", "-150 XP"
		BallsLine = "Balls pocketed x%d",
		NiceLine = "Nice shots x%d",
		WinBonus = "Win bonus",
		LossBonus = "Match bonus",
		RankReward = "Rank reward",
		Total = "Total",
		TapToContinue = "Tap to continue",
		Continue = "Continue",
		NewRank = "NEW RANK!",
		NewTier = "%s!", -- the tier's name, huge: "PLATINUM!"
		RankDown = "Rank down: %s",
		RankedTitle = "Ranked",
		RankedSubtitle = "Win matches, climb the ranks and earn rewards!",
		EarnXp = "Win matches to earn XP",
		TopRank = "You are at the top!",
		CurrentRank = "Current Rank", -- the tag over your tier, and under your rank on its card
		NextRank = "Next Rank", -- the tag over the next tier
		NextDivision = "Next: %s", -- your next division: "Next: Gold IV"
		RewardsFor = "Rewards for %s", -- the chosen tier's rewards: "Rewards for Platinum I"
		RewardMoney = "Money",
		RewardCase = "Case", -- a general case for every tier for now (designer, 2026-09-27)
		RewardCount = "x%d", -- how many: "x1"
		RewardChatTag = "Chat Tag",
		TierCue = "%s Cue", -- the tier's cue: "Platinum Cue"
		Soon = "Soon", -- a reward not given yet
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
