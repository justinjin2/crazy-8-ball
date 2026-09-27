--!strict
-- Player-facing copy. Add new UI wording here so localization has one source.
return {
	Pull = "PULL",
	-- The zoom guide over the spin button while it is your turn, beside its icon (ZoomHint).
	ZoomHint = "Zoom In/Out",
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
			StartingIn = "Starting in %d", -- the pad is full: the game starts by itself
			GamepadHint = "Y · Menu",
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
}
