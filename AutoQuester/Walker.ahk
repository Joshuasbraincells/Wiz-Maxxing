; Walker.ahk - walks the wizard towards the current quest goal by following the yellow quest arrow,
; one step per WalkStep() call. AHK v1.1, functions only. Shared by AutoQuester.ahk (walking only)
; and AutoFarmer\Autofarmer.ahk (battles and walking in one loop), so walking fixes go here.
;
; Needs, from the script that includes it: the super-globals GameLeft, GameTop, GameW, GameH (the
; game's client area, kept up to date by its UpdateGameRect()), GameExe and GameClass, and an
; #Include of ArrowReader.ahk. Call WalkerInit() once at start.

global ArriveDist, TurnRate, AheadAngle, TurnInPlace, StuckTime, UnstickTries, UnreadLimit, MinMatch
global NearDist, TalkMax, TalkGap, PushTime, PushStraightDist, PushStraightTime, BackupTime, UnstickTurn, UnstickBias, BiasTime
global HiddenWalkTime, PushHiddenTime, LoadSpaceWait, LoadSpaceMax, GateDist, GateWait, SigilWait
global FastStuckTime, StillFrac, MemNear, MemAhead, TurnSettle, TransportWait
global WkGoalZones, WkKnownZones, WkZonesFile, WkPromptDest, WkTransUsed, WkTransSeen, WkTransStep, WkTransStepAt, WkWaitWhat
global WkPromptUsed, WkZoneFrom, WkZoneAt, WkPressAt, DialogQuiet, WkQuietUntil, WkQuietLogged
;A loading screen per the game's log: a zone transfer under way (WkLoading), when the last one finished
global WkLoading, WkLoadedAt, SkipGap, WkDlgLook
global CollectWait, RoamRadius, ChaseTime, CollectMax
global WkCollect, WkGoalReadAt, WkArr1At, WkFoesAt, WkChaseFrom, WkChaseSkipUntil, WkRoamLeg, WkRoamLegAt, WkRoamSide
global Walking, HeldW, KeysDown, Refocus, StatusText, StatusKind, StatusPrefix
global WkBestDist, WkBestTime, WkLastRead, WkSide, WkTries, WkNear, WkFar, WkArrived, WkTalk, WkPushUntil
global WkSeenAt, WkHidden, WkHiddenAt, WkBias, WkBiasUntil, WkPrevMovedH, WkLastBoxOff, WkLastMode, WkBackups, WkBackupsFrom
global WkDialog, WkPushes, WkPushStart, WkStraight, WkStraightAt
global WkTalkDist, WkArrDist, WkLoadAt, WkSpaceAt, WkGoneSpaces
global WkGateAt, WkGateClicks, WkGateX, WkGateLook, WkSigilUntil, WkFarAt, WkSigilSeen
global WkSnapPrev, WkSnapAt, WkTurnAt, WkWalkFrom, WkStill, WkMotion, WkMem, WkMemFile, WkEsc
;AutoFarmer's "a battle is on" flag (blank in AutoQuester on its own): never talk or push on during a battle
global inbattle

;Settings and starting state. Returns false if the arrow shapes (resources\arrow_refs.txt) are missing
WalkerInit(prefix := "AutoQuester")
	{
	;---- Settings ----
	ArriveDist := 15     ;stop when the distance on the arrow is this or less (walks again when a new goal appears)
	TurnRate := 0.15     ;degrees the wizard turns per ms of holding A/D (measured: 22.5 degrees per 150 ms)
	TurnSettle := 500    ;ms the camera takes to catch up after a turn: don't steer on the arrow before then
	AheadAngle := 12     ;arrow within this many degrees of straight ahead: just walk
	TurnInPlace := 60    ;arrow further off than this: stop and turn on the spot first
	StuckTime := 4000    ;ms of walking without getting any closer = stuck, try to get around
	UnstickTries := 5    ;give up after this many tries at getting round the same obstacle
	UnreadLimit := 3000  ;ms without a readable distance before it stops and waits
	MinMatch := 0.6      ;how well a yellow shape must match the arrow (real arrows score 0.9-1.0)
	NearDist := 30       ;the number can't be read after it was this or less: next to the goal (lone digits often don't OCR)
	TalkMax := 15        ;at the goal: press X, then Space (up to this many times) while the dialogue is open
	TalkGap := 350       ;ms between Space presses
	PushTime := 8000     ;nobody to talk to: walk on into the goal (doorway, loading point) for up to this long
	PushStraightDist := 6 ;...and once this close, stop steering and walk straight through it
	PushStraightTime := 3000 ;...for at most this long (a loading point triggers well within it)
	BackupTime := 800    ;stuck: back up this long (ms) before turning away
	UnstickTurn := 75    ;stuck: turn this many degrees to one side and walk along the obstacle
	UnstickBias := 40    ;after that, keep aiming this many degrees off the goal on that side...
	BiasTime := 3000     ;...easing back to the goal over this many ms, so it doesn't walk straight back in
	HiddenWalkTime := 1500 ;arrow hidden while walking (an arch, door frame or pillar): keep walking this long before stopping
	PushHiddenTime := 2000 ;...and while pushing into a doorway: keep walking straight on this long (a loading screen also hides it)
	LoadSpaceWait := 4000 ;after a loading screen: no arrow for this long = maybe a dialogue that opened by itself, press Space
	LoadSpaceMax := 40    ;...every 1.5 s, at most this many times
	GateDist := 60       ;a World Gate's prompt shows up with the arrow last this close: the arrow leads there (another world), so use it
	GateWait := 6000     ;ms to wait for the Spiral Map after pressing X at a World Gate
	SigilWait := 30000   ;at a sigil (dungeon entrance, "Press X to Enter"): after X, stand still this long (ms)
	SkipGap := 70        ;a dialogue box showing (NEXT / DONE / MORE): Space every this many ms until it's gone
	DialogQuiet := 20000 ;after a dialogue X opened has closed: no X at any prompt for this long (ms), so it walks
	                     ;away instead of talking to the same NPC again and again
	TransportWait := 15000 ;after using a boat or the like ("BOAT TO GOBBLERTON ... to Use"): stand still this long
	FastStuckTime := 1200 ;...or stuck after this long already if the picture has stopped moving too (W held,
	StillFrac := 0.15     ;   and less than this share of the picture changed between two looks, twice)
	MemNear := 15         ;a remembered obstacle: same zone and the distance to the goal within this of it
	MemAhead := 25        ;...and on the way to one (this much further from the goal): keep to the side that worked
	CollectWait := 5000   ;a "collect / defeat N things" goal (the line under the arrow): arrived and nothing changed for this long = collect
	RoamRadius := 70      ;collecting: stay within this distance of where the arrow leads
	ChaseTime := 12000    ;collecting: walk towards a monster's name label at most this long, then look elsewhere
	CollectMax := 900000  ;collecting: give up on a goal after this long (ms) and just wait

	Walking := 0, HeldW := 0, KeysDown := 0, Refocus := 0, WkFarAt := 0, WkTurnAt := 0, WkWalkFrom := 0
	WkGoalZones := [], WkTransUsed := {}, WkTransSeen := "", WkTransStep := 0, WkTransStepAt := 0, WkWaitWhat := "sigil"
	WkPromptUsed := {}, WkZoneFrom := "", WkZoneAt := 0, WkPressAt := 0, WkQuietUntil := 0, WkQuietLogged := 0
	WkLoading := 0, WkLoadedAt := 0, WkDlgLook := 0
	WkCollect := "", WkGoalReadAt := 0
	WalkMemLoad()
	WalkZonesLoad()
	StatusText := "", StatusKind := "", StatusPrefix := prefix
	WalkReset()
	return IsObject(ArrowRefs())
	}

;Forget progress (new goal, or walking switched back on)
WalkReset()
	{
	WkBestDist := "", WkBestTime := A_TickCount, WkLastRead := A_TickCount
	WkSide := 1, WkTries := 0, WkNear := 0, WkFar := 0, WkArrived := 0, WkTalk := 0, WkPushUntil := 0
	WkDialog := 0, WkPushes := 0, WkPushStart := 0, WkStraight := 0, WkStraightAt := 0
	WkTalkDist := "", WkArrDist := "", WkLoadAt := 0, WkSpaceAt := 0, WkGoneSpaces := 0
	WkGateAt := 0, WkGateClicks := 0, WkGateX := 0, WkGateLook := 0, WkSigilUntil := 0, WkSigilSeen := 0
	WkBackups := 0, WkBackupsFrom := 0
	WkSeenAt := 0, WkHidden := 0, WkHiddenAt := 0, WkBias := 0, WkBiasUntil := 0, WkPrevMovedH := "", WkLastBoxOff := 0, WkLastMode := 0
	WkSnapPrev := "", WkSnapAt := 0, WkStill := 0, WkMotion := "", WkEsc := ""
	WkArr1At := 0, WkFoesAt := 0, WkChaseFrom := 0, WkChaseSkipUntil := 0, WkRoamLeg := 0, WkRoamLegAt := 0, WkRoamSide := 1
	}

;A line in AutoFarmer's debug.log (when the including script has DebugLog), so walker problems leave evidence
WalkLog(text)
	{
	if (IsFunc("DebugLog"))
		Func("DebugLog").Call("Walk: " text)
	}

;One step towards the quest goal: read the arrow, then walk / turn / stop. Call it over and over while
;there's no battle; with no arrow on screen it just lets go of the keys. Takes up to about a second
;(longer while getting round an obstacle). Returns false when walking is off.
;At the goal (WkArrived): 2 = talking (X, then Space to skip the dialogue), 3 = pushing on into it
;(doorway or loading point), 4 = at a World Gate (X, then Go To World on the Spiral Map), 5 = entering
;a sigil (X, then stand still SigilWait), 6 = pressed X at a prompt on the way (Space through what it
;opens), 7 = collecting (a "collect / defeat N things" goal: walk into monsters, roam the area),
;1 = done, waiting for the next goal to show up
WalkStep()
	{
	if (!Walking)
		return false
	if (!GameActive())
		{
		if (KeysDown)
			ReleaseKeys(), Refocus := 1
		SetStatus("paused - click into Wizard101 to carry on")
		WkBestTime := A_TickCount, WkLastRead := A_TickCount
		Sleep, 300
		return true
		}
	if (Refocus)
		ReleaseKeys(), Refocus := 0
	if (inbattle && WkArrived >= 2)
		WalkReset()
	;At a World Gate: the Spiral Map covers the arrow, so no reading it
	if (WkArrived = 4)
		return GateStep()
	;Entering a sigil (X pressed): stand still while it counts down and the dungeon loads, then carry
	;on like after a loading screen. Short steps, so AutoFarmer still notices a battle meanwhile
	if (WkArrived = 5)
		{
		if (A_TickCount < WkSigilUntil)
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			;X opened a dialogue instead of a dungeon (e.g. "you spot an access grate..." with Back and
			;Done): Space through it like after any other prompt (WkArrived = 6)
			if (WkWaitWhat = "sigil" && A_TickCount > WkGateLook)
				{
				WkGateLook := A_TickCount + 1000
				if (WalkDialogOpen())
					{
					WalkLog("sigil: X opened a dialogue, not a dungeon - pressing Space through it")
					WkArrived := 6, WkPressAt := A_TickCount, WkTalk := 0, WkDialog := 0, WkSpaceAt := 0
					return true
					}
				}
			SetStatus((WkWaitWhat = "sigil" ? "entering the sigil" : "on the way (" WkWaitWhat ")") " - waiting " Ceil((WkSigilUntil - A_TickCount) / 1000) " s")
			Sleep, 300
			return true
			}
		WalkLog((WkWaitWhat = "sigil" ? "sigil" : "transport") ": waited " Round((WkWaitWhat = "sigil" ? SigilWait : TransportWait) / 1000) " s - walking on")
		WalkReset()
		WkLoadAt := A_TickCount
		return true
		}
	;Reading the arrow is a lot of per-pixel script work: run it at full speed (AutoFarmer keeps the
	;default speed for everything else, so its loop doesn't hog the CPU)
	batch := A_BatchLines
	SetBatchLines, -1
	h := ReadArrow(dist, score)
	SetBatchLines, %batch%
	if (!Walking)
		return false
	seen := (h != "" && score >= MinMatch)
	;Where the arrow was found: pushed up (by a talk prompt) or in its usual spot, bright or in shadow
	info := ArrowInfo()
	boxOff := (seen && info.boxY != "" && info.homeY != "") ? info.homeY - info.boxY : 0
	moved := seen && (boxOff > 12 * info.scale || boxOff < -12 * info.scale)
	if (seen)
		{
		WkSeenAt := A_TickCount, WkLoadAt := 0
		if (IsObject(WkTransSeen))
			WkTransSeen.seenAfter := 1
		;Found again: the next time it goes, start over (with a back-up; see below)
		WkHidden := 0
		if (moved != (WkLastBoxOff != 0) || info.mode != WkLastMode)
			WalkLog("arrow " (moved ? "pushed up " boxOff " px (talk prompt?)" : "in its usual spot") (info.mode = 1 ? ", dark (shadow test)" : info.mode = 2 ? ", under water" : "") " - heading " Round(h) ", distance " (dist = "" ? "?" : dist) ", match " Round(score, 2))
		WkLastBoxOff := moved ? boxOff : 0, WkLastMode := info.mode
		}

	;A dialogue box (its NEXT / DONE / MORE / BACK button showing - it covers or pushes up the arrow):
	;Space through it as fast as the game takes it, whatever the walker was doing
	if ((!seen || moved) && !inbattle && A_TickCount > WkDlgLook)
		{
		WkDlgLook := A_TickCount + 400
		if (WalkDialogOpen())
			return WalkSkipDialog()
		}

	;The arrow led to a World Gate (the goal is in another world) or a sigil (a dungeon entrance):
	;close to it, its prompt pushes the arrow up or covers it. Only when the arrow was last this close,
	;so walking past a World Gate or a sigil on the way somewhere else doesn't count
	if (seen && dist != "" && dist > GateDist)
		WkFarAt := A_TickCount
	near := (WkBestDist != "" && WkBestDist <= GateDist) || (seen && dist != "" && dist <= GateDist)
	;Standing on a sigil (or started there) its prompt covers the arrow and no distance reads at all.
	;If the arrow hasn't shown a far-off goal lately, the sigil is where it led - checked a few times
	;over a second or two first, so a passing frame without the arrow doesn't count
	hiddenHere := !seen && A_TickCount - WkFarAt > 10000
	if (!hiddenHere)
		WkSigilSeen := 0
	if ((WkArrived <= 1 || WkArrived = 3 || WkArrived = 7) && !inbattle && (!seen || moved) && A_TickCount > WkGateLook)
		{
		WkGateLook := A_TickCount + ((seen && !near) ? 1500 : 700)
		prompt := InteractPrompt()
		if (prompt = "gate" && near)
			{
			StartGate("World Gate prompt showing, the arrow led here (distance " (WkBestDist = "" ? dist : WkBestDist) ")")
			return true
			}
		;Just out of a dialogue X opened: no X at any prompt for a while (walk away from it), so the same
		;NPC or object can't be talked to over and over
		if ((prompt = "sigil" || prompt = "press") && A_TickCount < WkQuietUntil)
			{
			if (!WkQuietLogged)
				WkQuietLogged := 1, WalkLog("prompt showing, but a dialogue just closed - no X for " Ceil((WkQuietUntil - A_TickCount) / 1000) " s")
			prompt := ""
			}
		;A sigil: always in (once per 10 minutes for the same one) - but not straight back into the
		;dungeon just left: coming out puts you right at its sigil
		WkSigilSeen := 0
		if (prompt = "sigil")
			{
			WalkZone()
			if (InStr(WkZoneFrom, "/Interiors/") && A_TickCount - WkZoneAt < 90000)
				{
				if (!WkPromptUsed.HasKey("exitlog") || A_TickCount - WkPromptUsed["exitlog"] > 30000)
					WkPromptUsed["exitlog"] := A_TickCount, WalkLog("sigil: just came out of " WkZoneFrom " - not going straight back in")
				}
			else if (WalkPromptFree(WkPromptDest, 600000))
				{
				StartSigil("sigil prompt showing (" (near ? "the arrow led here" : "pressing X at every prompt") ")")
				return true
				}
			}
		;Any other "Press X ..." prompt (talk, collect, open...): press X - once a minute for the same one -
		;then Space through whatever it opens and walk on
		if (prompt = "press" && WalkPromptFree(WkPromptDest, 60000))
			{
			StartPressX(WkPromptDest)
			return true
			}
		;A boat or the like ("BOAT TO GOBBLERTON", "Press X or click to Use") covering the arrow: use it
		;if it goes where the quest is, otherwise step out of it and walk on
		if (prompt = "transport" && WalkTransport(WkPromptDest, seen))
			return true
		}

	;Pressed X at a prompt on the way (WkArrived = 6): a dialogue or the like covers the arrow - Space
	;through it; once the arrow is back (or nothing opened within a second), walk on
	if (WkArrived = 6)
		{
		if ((!seen || WalkDialogOpen()) && A_TickCount - WkPressAt < 60000)
			{
			if (!WkDialog)
				WalkLog("pressed X: something opened (arrow covered) - pressing Space")
			WkDialog := 1
			if (WkTalk < TalkMax * 3 && A_TickCount - WkSpaceAt > TalkGap)
				PressKey("Space"), WkTalk += 1, WkSpaceAt := A_TickCount
			SetStatus("pressed X - Space through what it opened")
			Sleep, 100
			return true
			}
		if (WkDialog || A_TickCount - WkPressAt > 1200)
			{
			WalkLog("pressed X: " (WkDialog ? "done after " WkTalk " Space presses" : "nothing opened") " - walking on" (WkDialog ? " (no X at prompts for " Round(DialogQuiet / 1000) " s)" : ""))
			WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			if (WkDialog)
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
			}
		Sleep, 100
		return true
		}

	;A "collect / defeat N things" goal: the arrow only leads to the area, and standing there does
	;nothing. Walk into the monsters there, or roam about the spot (CollectStep)
	if (WkArrived = 7)
		return CollectStep(seen, h, dist)
	if ((WkArrived = 0 || WkArrived = 1) && !inbattle && seen && dist != "" && dist <= RoamRadius && CollectCheck(dist))
		return true

	;Talking (after X). The dialogue box covers the arrow, so: no arrow = dialogue open, press Space to
	;skip through it. Arrow back with a new goal = done, walk on. Arrow still there with the same goal
	;(nobody to talk to: a doorway or loading point) = push on into it. The wizard doesn't move while
	;talking, so a distance that's changed from the one at X means a new goal, even a close one
	if (WkArrived = 2)
		{
		WkFar := (seen && dist != "" && (dist > ArriveDist + 20 || DistChanged(dist, WkTalkDist))) ? WkFar + 1 : 0
		if (WkFar >= 2)
			{
			WalkLog("talk: next goal (distance " dist ") after " WkTalk " Space presses")
			if (WkDialog)
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
			WalkReset()
			SetStatus("next goal (distance " dist ") - walking on")
			return true
			}
		;One far reading: wait for a second before deciding it's a new goal
		if (WkFar = 1)
			{
			Sleep, 100
			return true
			}
		if (!seen)
			{
			;X at a World Gate opens the Spiral Map (it covers the arrow too): Go To World, not Space
			if (WkTalk < 3 && IsObject(SpiralMapButton()))
				{
				WalkLog("talk: the Spiral Map opened - it's a World Gate")
				WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
				return true
				}
			if (!WkDialog)
				WalkLog("talk: dialogue open (arrow covered) - pressing Space")
			WkDialog := 1
			if (WkTalk < TalkMax)
				{
				PressKey("Space")
				WkTalk += 1
				SetStatus("talking - Space to skip the dialogue (" WkTalk " of " TalkMax ")")
				Sleep, %TalkGap%
				}
			else
				{
				;A long dialogue (or a press lost while a page slid in): keep skipping, more slowly
				if (WkTalk < TalkMax * 3 && A_TickCount - WkSpaceAt > 1500)
					PressKey("Space"), WkTalk += 1, WkSpaceAt := A_TickCount
				SetStatus("waiting - dialogue or loading screen")
				Sleep, 300
				}
			return true
			}
		;Arrow visible: give a slow dialogue two Space presses to show up first
		if (!WkDialog && WkTalk < 2)
			{
			PressKey("Space")
			WkTalk += 1
			SetStatus("talking - Space (" WkTalk ")")
			Sleep, %TalkGap%
			return true
			}
		if (WkDialog)
			WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
		StartPush(WkDialog ? "same goal after the dialogue" : "nobody to talk to (no dialogue opened)", dist)
		return true
		}

	if (!seen)
		{
		;Pushing into a doorway and the arrow went: the door frame between the camera and the wizard,
		;or the loading screen starting. Stopping would leave a door frame hiding it for good, so walk
		;straight on for a moment either way
		if (WkArrived = 3 && !inbattle && A_TickCount < WkPushUntil && A_TickCount - WkSeenAt < PushHiddenTime)
			{
			if (!WkStraight)
				{
				WkStraight := 1, WkStraightAt := A_TickCount
				WalkLog("push: arrow hidden (door frame or loading screen?) - walking straight on")
				}
			HoldW(1)
			if (!Walking)
				return false
			SetStatus("pushing on straight - arrow hidden (door frame or loading screen?)")
			Sleep, 100
			return true
			}
		;Walking and the arrow went: an arch, door frame or pillar between the camera and the wizard.
		;Stopping would freeze the view with it still hidden, so keep walking for a moment
		if (WkArrived = 0 && HeldW && !inbattle && A_TickCount - WkSeenAt < HiddenWalkTime)
			{
			SetStatus("walking on - arrow hidden (behind something?)")
			Sleep, 100
			return true
			}
		if (KeysDown)
			ReleaseKeys()
		;Walking into a doorway and the arrow stayed gone: a loading screen, carry on normally afterwards
		if (WkArrived = 3)
			{
			WalkLog("push: arrow gone - loading screen?")
			WkArrived := 0, WkSeenAt := 0, WkPushes := 0
			WkLoadAt := A_TickCount, WkGoneSpaces := 0, WkSpaceAt := 0
			}
		;Lost it while walking: the arrow is drawn at the wizard's feet, so a pillar or wall between the
		;camera and the wizard hides it - or the wizard's own mount, when it points back towards the
		;camera. Back up, then turn 70 degrees at a time (a full circle at most) until it shows again
		;(also when it hasn't shown at all since walking was switched on - started right there - but not
		;after a loading screen: then it's a dialogue, see below)
		else if (WkArrived = 0 && !inbattle && !WkSigilSeen && WkHidden < 6 && A_TickCount - WkHiddenAt > 1500
			&& (WkSeenAt ? A_TickCount - WkSeenAt > 1000 && A_TickCount - WkSeenAt < 30000 : !WkLoadAt)
			&& !WalkLoadingScreen())
			{
			;Only turn when it stays gone: a moment out of sight just gets a back-up - unless it has
			;already backed up twice in the last 20 s (the arrow keeps going at the same place)
			if (A_TickCount - WkBackupsFrom > 20000)
				WkBackups := 0, WkBackupsFrom := A_TickCount
			if (WkHidden = 0 && WkBackups >= 2)
				WkHidden := 1
			if (WkHidden = 0)
				WkBackups += 1
			WkHidden += 1, WkHiddenAt := A_TickCount
			WalkLog("arrow hidden (behind something, or under the mount?) - " (WkHidden = 1 ? "backing up" : "turning 70 degrees (" WkHidden - 1 " of 5)"))
			SetStatus("arrow hidden - " (WkHidden = 1 ? "backing up" : "turning") " to find it again")
			if (WkHidden = 1)
				BackUp(600)
			else
				Turn(70 * WkSide)
			WkHiddenAt := A_TickCount
			return Walking ? true : false
			}
		;Still no arrow a while after a loading screen: a new zone can open a dialogue by itself, which
		;covers the arrow. Press Space now and then to get through it (a jump if there's nothing open)
		if (WkLoadAt && !inbattle && A_TickCount - WkLoadAt > LoadSpaceWait && A_TickCount - WkSpaceAt > 1500 && WkGoneSpaces < LoadSpaceMax)
			{
			if (!WkGoneSpaces)
				WalkLog("no arrow " Round((A_TickCount - WkLoadAt) / 1000) " s after the loading screen - pressing Space in case a dialogue opened")
			PressKey("Space")
			WkGoneSpaces += 1, WkSpaceAt := A_TickCount
			}
		SetStatus("waiting - no quest arrow on screen (battle, loading or dialogue?)")
		WkBestDist := "", WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
		Sleep, 300
		return true
		}

	;Pushing on into the goal (doorway, loading point): follow the arrow until right at it, then stop
	;steering (it swings about on top of the goal) and walk straight through. A loading screen hides
	;the arrow (handled above); otherwise it gives up after PushTime
	if (WkArrived = 3)
		{
		if (dist != "")
			{
			WkLastRead := A_TickCount
			;The goal was reached and the quest moved on: the arrow jumps away (while still following
			;the arrow in, a jump of 15 is enough - it only gets closer then)
			WkFar := (WkBestDist != "" && dist > WkBestDist + (WkStraight ? 60 : 15)) ? WkFar + 1 : 0
			if (WkFar >= 2)
				{
				WalkLog("push: next goal (distance " dist ") - walking on")
				WalkReset()
				SetStatus("next goal (distance " dist ") - walking on")
				return true
				}
			if (dist < WkBestDist || WkBestDist = "")
				WkBestDist := dist
			}
		if (A_TickCount > WkPushUntil || (WkStraight && A_TickCount - WkStraightAt > PushStraightTime))
			{
			HoldW(0)
			WkArrived := 1, WkFar := 0, WkArrDist := dist
			WalkLog("push: no loading screen after " Round((A_TickCount - WkPushStart) / 1000, 1) " s (distance " (dist = "" ? "?" : dist) ") - waiting for the next goal")
			SetStatus("arrived" (dist = "" ? "" : " (distance " dist ")") " - waiting for the next goal")
			return true
			}
		if (!WkStraight && ((dist != "" && dist <= PushStraightDist) || (dist = "" && (WkBestDist = "" || WkBestDist <= NearDist))))
			{
			;Face the goal first if it's off to the side. Not if it's behind: then the wizard has just
			;walked over the goal point, and turning round would walk it away from a door beyond it
			if (Abs(h) > AheadAngle && Abs(h) <= 120)
				{
				HoldW(0)
				Turn(h)
				if (!Walking)
					return false
				}
			WkStraight := 1, WkStraightAt := A_TickCount
			WalkLog("push: at the goal (distance " (dist = "" ? "?" : dist) ") - walking straight on through it")
			}
		;(right after a turn the arrow doesn't show it yet: see TurnSettle)
		if (!WkStraight && A_TickCount - WkTurnAt < TurnSettle)
			{
			Sleep, 50
			return true
			}
		if (WkStraight)
			HoldW(1)
		else if (Abs(h) > TurnInPlace)
			{
			HoldW(0)
			Turn(h)
			}
		else
			{
			HoldW(1)
			if (Abs(h) > AheadAngle)
				Turn(h)
			}
		if (!Walking)
			return false
		SetStatus("pushing on " (WkStraight ? "straight" : "- arrow " Round(h) " degrees") ", distance " (dist = "" ? "?" : dist))
		Sleep, 50
		return true
		}

	if (dist != "")
		{
		WkLastRead := A_TickCount
		;Arrived: stay put until the distance is clearly bigger again (the next goal). After two pushes
		;at the same goal it needs a much bigger jump, so it doesn't go back and forth over the spot
		if (WkArrived)
			{
			;The wizard stands still while it waits here, so a distance that's changed is a new goal,
			;even a close one (the next NPC in the same room)
			if (WkArrDist = "")
				WkArrDist := dist
			changed := DistChanged(dist, WkArrDist)
			WkFar := (changed || dist > ArriveDist + (WkPushes >= 2 ? 60 : 5)) ? WkFar + 1 : 0
			if (WkFar < 2)
				{
				SetStatus("arrived (distance " dist ") - waiting for the next goal")
				Sleep, 400
				return true
				}
			;A new goal: it may be pushed into twice again
			if (changed || dist > ArriveDist + 60)
				WkPushes := 0
			WalkLog("arrived: distance now " dist " (was " WkArrDist ") - walking on")
			WkArrived := 0, WkFar := 0, WkArrDist := "", WkBestDist := "", WkBestTime := A_TickCount, WkTries := 0
			}
		;Two readings in a row, so one misread number can't stop us early
		WkNear := dist <= ArriveDist ? WkNear + 1 : 0
		if (WkNear >= 2)
			{
			StartTalk(dist)
			return true
			}
		;Progress = closer than ever before, or a new goal further away
		if (WkBestDist = "" || dist < WkBestDist - 1 || dist > WkBestDist + 50)
			WkBestDist := dist, WkBestTime := A_TickCount, WkTries := 0
		;Got round an obstacle: clearly closer than where it got stuck. Remember which way worked there
		if (IsObject(WkEsc))
			{
			;(too long ago - a battle or a loading screen in between - and it proves nothing)
			if (A_TickCount - WkEsc.at > 20000)
				WkEsc := ""
			else if (dist < WkEsc.dist - 10)
				{
				if (WkEsc.zone != "")
					WalkMemLearn(WkEsc.zone, WkEsc.dist, WkEsc.side, WkEsc.walkMs, true)
				WalkLog("got round the obstacle at distance " WkEsc.dist " going " (WkEsc.side > 0 ? "right" : "left") (WkEsc.zone != "" ? " - remembered for " WkEsc.zone : ""))
				WkEsc := ""
				}
			}
		;On the way to an obstacle remembered from before: keep to the side that got round it then (not
		;while already getting round something)
		if (A_TickCount > WkBiasUntil && WkTries = 0 && !IsObject(WkEsc) && WkMem.Length())
			{
			spot := WalkMemAhead(WalkZone(), dist)
			if (IsObject(spot))
				{
				spot.preAt := A_TickCount
				WkBias := UnstickBias * spot.side, WkBiasUntil := A_TickCount + BiasTime
				WalkLog("remembered obstacle ahead (" spot.zone ", distance " spot.dist ") - keeping to the " (spot.side > 0 ? "right" : "left"))
				}
			}
		}
	else if (WkArrived)
		{
		Sleep, 400
		return true
		}
	else if (WkBestDist != "" && WkBestDist <= NearDist && A_TickCount - WkLastRead > 1000)
		{
		;Was close and now the number won't read (Windows OCR misses lone digits): we're at the goal
		StartTalk("?")
		return true
		}
	else if (A_TickCount - WkLastRead > UnreadLimit)
		{
		;No number has read since the arrow came back (after a battle, a hidden arrow or a restart):
		;a lone digit, which Windows OCR misses - so the goal is under 10 away. Treat it as arrived
		if (WkBestDist = "")
			{
			WkBestDist := 9
			StartTalk("?")
			return true
			}
		if (KeysDown)
			ReleaseKeys()
		SetStatus("waiting - can't read the distance on the arrow")
		WkBestTime := A_TickCount
		Sleep, 300
		return true
		}
	;The camera swings round after the wizard about half a second late (measured 2026-10-16: a 62
	;degree turn showed on screen 0.35-0.47 s after the key came up), so right after a turn the arrow
	;still shows part of it. Steering on that turns too far again - the zig-zags and circles. Wait for
	;it, walking on (or standing) as before
	if (A_TickCount - WkTurnAt < TurnSettle)
		{
		Sleep, 50
		return true
		}
	;Arrow pushed up by the talk prompt (next to an NPC): the prompt slides in and out, so readings
	;jump. Only act once two readings agree, and don't fine-steer - just walk until clear of the NPC
	fine := true
	if (moved)
		{
		stable := (WkPrevMovedH != "" && Abs(ArrowWrap(h - WkPrevMovedH)) <= 30)
		WkPrevMovedH := h
		if (!stable)
			{
			HoldW(0)
			SetStatus("waiting - arrow moving (talk prompt?)")
			Sleep, 150
			WkBestTime := A_TickCount
			return true
			}
		fine := false
		}
	else
		WkPrevMovedH := ""
	;After getting round an obstacle, keep aiming a bit off to that side for a while
	steer := h
	if (A_TickCount < WkBiasUntil)
		steer := h + WkBias * (WkBiasUntil - A_TickCount) / BiasTime
	if (Abs(steer) > TurnInPlace)
		{
		HoldW(0)
		SetStatus("turning " (steer < 0 ? "left " : "right ") Round(Abs(steer)) " degrees")
		Turn(steer)
		if (!Walking)
			return false
		Sleep, 150
		WkBestTime := A_TickCount
		;Turning doesn't count against the unreadable-distance timers, except next to the goal: there
		;the wizard keeps walking over the goal point and turning back, which would put them off forever
		if (WkBestDist != "" && WkBestDist > NearDist)
			WkLastRead := A_TickCount
		return true
		}
	HoldW(1)
	if (fine && Abs(steer) > AheadAngle)
		Turn(steer)
	if (!Walking)
		return false
	SetStatus("walking - arrow " Round(h) " degrees, distance " (dist = "" ? "?" : dist) (steer != h ? " (keeping clear of the obstacle)" : "") (fine ? "" : " (talk prompt showing)"))
	;Is the wizard actually moving? With W held, the picture moves along. Two looks in a row where it
	;has hardly changed = walking into something, so don't wait the full StuckTime
	still := WalkStill()
	if (still != "")
		WkStill := (still && dist != "") ? WkStill + 1 : 0
	slowStuck := A_TickCount - WkBestTime > StuckTime
	if (slowStuck || (WkStill >= 2 && A_TickCount - WkBestTime > FastStuckTime))
		{
		zone := WalkZone()
		stuckAt := WkBestDist != "" ? WkBestDist : dist
		;The last try didn't get round: if that was a remembered way, it's trusted less now (and isn't
		;tried again straight away)
		memFailed := false
		if (IsObject(WkEsc))
			{
			if (WkEsc.mem && A_TickCount - WkEsc.at <= 20000)
				WalkMemLearn(WkEsc.zone, WkEsc.dist, WkEsc.side, WkEsc.walkMs, false), memFailed := true
			WkEsc := ""
			}
		if (WkTries >= UnstickTries)
			{
			WalkLog("stuck: gave up after " UnstickTries " tries")
			Walking := 0
			ReleaseKeys()
			SetStatus("stuck - couldn't get around the obstacle. Move the wizard a bit and press F8")
			return false
			}
		SetStatus("stuck - backing up and going around (try " WkTries + 1 " of " UnstickTries ")")
		;Each try walks further along the obstacle, on alternate sides, then keeps aiming off to that
		;side. The first try at an obstacle remembered from before goes the way that worked then
		walkMs := 900 * (WkTries + 1)
		walkMs := walkMs > 3600 ? 3600 : walkMs
		side := WkSide, fromMem := false
		spot := (WkTries = 0 && !memFailed && zone != "" && stuckAt != "") ? WalkMemFind(zone, stuckAt) : ""
		if (IsObject(spot))
			side := spot.side, walkMs := spot.walkMs, fromMem := true
		WalkLog("stuck at distance " (stuckAt = "" ? "?" : stuckAt) " (" (slowStuck ? "no closer in " Round(StuckTime / 1000) " s" : "picture not moving: " WkMotion " changed") "): try " WkTries + 1 " - back up, turn " UnstickTurn " degrees " (side > 0 ? "right" : "left") ", walk " walkMs " ms" (fromMem ? " (the way that worked here before)" : ""))
		Unstick(side, walkMs)
		WkEsc := {zone: zone, dist: stuckAt, side: side, walkMs: walkMs, mem: fromMem, at: A_TickCount}
		WkBias := UnstickBias * side, WkBiasUntil := A_TickCount + BiasTime
		WkSide := -side, WkTries += 1
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkStill := 0, WkSnapPrev := ""
		if (!Walking)
			return false
		}
	Sleep, 50
	return true
	}

;True if the distance has clearly changed from was (the wizard was standing still, so it's a new
;goal). Lone digits misread easily (5 / 9, 3 / 8), so one of the two has to be 10 or more
DistChanged(dist, was)
	{
	if (dist = "" || was = "" || was = "?")
		return false
	return Abs(dist - was) > 3 && (dist >= 10 || was >= 10)
	}

;At the goal: stop, press X (talk / use), then WalkStep presses Space through the dialogue
StartTalk(d)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	;A World Gate's prompt: Go To World instead. A sigil's: enter it and wait
	prompt := InteractPrompt()
	if (prompt = "gate")
		{
		StartGate("at the goal (distance " d ") and it's a World Gate")
		return
		}
	if (prompt = "sigil")
		{
		StartSigil("at the goal (distance " d ") and it's a sigil")
		return
		}
	WkArrived := 2, WkTalk := 0, WkFar := 0, WkNear := 0, WkDialog := 0, WkTalkDist := d
	PressKey("x")
	WalkLog("talk: at the goal (distance " d "), pressed X")
	SetStatus("talking - pressed X at the goal (distance " d ")")
	Sleep, 600
	}

;Walk on into the goal (doorway / loading point), at most twice for the same goal
StartPush(why, d)
	{
	if (WkPushes >= 2)
		{
		WalkLog("push: " why " - already pushed twice here, waiting for the next goal")
		WkArrived := 1, WkFar := 0, WkArrDist := (d = "?" ? "" : d)
		SetStatus("arrived - waiting for the next goal")
		return
		}
	WkPushes += 1, WkArrived := 3, WkFar := 0, WkStraight := 0
	WkPushStart := A_TickCount, WkPushUntil := A_TickCount + PushTime
	WalkLog("push: " why " (distance " (d = "" ? "?" : d) ") - walking on into it, try " WkPushes)
	SetStatus("pushing on - walking into the goal (doorway or loading point?)")
	}

;The arrow led to a World Gate (its prompt is showing): stop and press X to open the Spiral Map,
;then GateStep clicks Go To World
StartGate(why)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
	PressKey("x")
	WalkLog("gate: " why " - pressed X")
	SetStatus("World Gate - pressed X, waiting for the Spiral Map")
	Sleep, 800
	}

;A "Press X ..." prompt on the way: stop, press X, then WalkStep (WkArrived = 6) presses Space
;through whatever it opens and walks on
StartPressX(key)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WkPromptUsed[key = "" ? "?" : key] := A_TickCount
	WkArrived := 6, WkPressAt := A_TickCount, WkTalk := 0, WkDialog := 0, WkSpaceAt := 0
	PressKey("x")
	WalkLog("prompt '" SubStr(key, 1, 40) "' - pressed X")
	SetStatus("pressed X at a prompt")
	Sleep, 400
	}

;True if that prompt hasn't been used (X pressed) in the last ms. The key is the prompt's letters as
;OCR read them, which can come out a little different each time: nearly the same letters count as the
;same prompt
WalkPromptFree(key, ms)
	{
	key := (key = "") ? "?" : key
	for used, at in WkPromptUsed
		if (A_TickCount - at <= ms && (used = key || (StrLen(key) > 6 && WalkEditDistance(used, key) <= StrLen(key) // 4)))
			return false
	return true
	}

;Spaces through an open dialogue box every SkipGap ms, looking again every 4 presses, until it's gone
;(at most 80). Counts as the dialogue the talking / pressed-X steps are waiting for, and starts the
;no-X time after it (DialogQuiet)
WalkSkipDialog()
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	presses := 0
	Loop, 80
		{
		PressKey("Space"), presses += 1
		Sleep, %SkipGap%
		if (!Walking)
			return false
		if (Mod(A_Index, 4) = 0 && !WalkDialogOpen())
			break
		}
	WalkLog("dialogue: skipped with " presses " Space presses")
	SetStatus("dialogue skipped (" presses " Space presses)")
	WkDialog := 1, WkTalk += presses, WkSpaceAt := A_TickCount
	WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
	WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return true
	}

;True if a dialogue box is open at the bottom of the game: its DONE / NEXT / BACK / MORE buttons, read by OCR
WalkDialogOpen()
	{
	s := ArrowScale().scale
	t := OcrRect(Round(GameLeft + GameW / 2 - 480 * s), Round(GameTop + GameH - 170 * s), Round(960 * s), Round(168 * s))
	return !ErrorLevel && RegExMatch(t, "\b(DONE|D0NE|NEXT|BACK|MORE)\b")
	}

;The arrow led to a sigil (a dungeon entrance: its prompt says "Press X to Enter"): stop, press X, and
;stand still for SigilWait while it counts down and the dungeon loads (WalkStep's WkArrived = 5)
StartSigil(why)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WkArrived := 5, WkSigilUntil := A_TickCount + SigilWait, WkWaitWhat := "sigil"
	WkPromptUsed[WkPromptDest = "" ? "?" : WkPromptDest] := A_TickCount
	PressKey("x")
	WalkLog("sigil: " why " - pressed X, waiting " Round(SigilWait / 1000) " s")
	SetStatus("entering the sigil - pressed X")
	}

;A boat or the like ("<SOMETHING> TO <PLACE>", "Press X ... to Use") covers the arrow. Use it if
;the place is the zone one of the quest's goals is in (the game's log names the goals' zones, e.g.
;Karamelle/Interiors/KM_Z10_UnderwaterGrotto, and KM_Z10 is Karamelle/KM_Z10_Gobblerton), we're not
;in that zone already, and it wasn't used in the last 10 minutes. Can't tell where it goes (a zone
;never visited): use it the second time it gets in the way without the goal getting closer. Otherwise
;step out of it, so the arrow shows again, and walk on. True if it did something
WalkTransport(dest, arrowSeen := false)
	{
	zone := WalkZone()
	leads := WalkTransportLeads(dest, zone)
	recent := WkTransUsed.HasKey(dest) && A_TickCount - WkTransUsed[dest] < 600000
	;Second time at the same one, the goal no closer, can't tell where it goes
	;(and the arrow showed again in between: it really was walked on from, and came back here)
	again := IsObject(WkTransSeen) && WkTransSeen.dest = dest && A_TickCount - WkTransSeen.at < 180000
		&& WkTransSeen.seenAfter && (WkBestDist = "" || WkTransSeen.dist = "" || WkBestDist > WkTransSeen.dist - 20)
	if (!recent && (leads = 1 || (leads = "" && again && !arrowSeen)))
		{
		StartTransport(dest, leads = 1 ? "it goes to the quest's zone" : "can't tell where it goes, and walking on didn't get any closer")
		return true
		}
	;Its prompt only pushes the arrow up: nothing in the way, walk on
	if (arrowSeen)
		return false
	if (!IsObject(WkTransSeen) || WkTransSeen.dest != dest || A_TickCount - WkTransSeen.at >= 180000)
		WkTransSeen := {dest: dest, at: A_TickCount, dist: WkBestDist, seenAfter: 0}
	;Step out of it (not over and over at the same spot)
	if (WkTransStep >= 3 && A_TickCount - WkTransStepAt < 60000)
		return false
	WkTransStep := (A_TickCount - WkTransStepAt < 60000) ? WkTransStep + 1 : 1, WkTransStepAt := A_TickCount
	WalkLog("transport: '" dest "' covers the arrow - " (recent ? "used it in the last 10 minutes" : leads = 0 ? "it doesn't go to the quest's zone" : "can't tell where it goes yet") ", stepping out of it")
	SetStatus("stepping out of the " dest " prompt")
	BackUp(900)
	if (!Walking || !GameActive())
		return true
	Turn(60 * WkSide)
	HoldW(1)
	HoldFor(1000)
	HoldW(0)
	WkSide := -WkSide, WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return true
	}

;1 if a "... TO <dest>" transport goes to the zone of one of the quest's goals (and not the zone
;we're in), 0 if it goes somewhere else, "" if it can't tell
WalkTransportLeads(dest, zone)
	{
	destName := WalkLetters(dest)
	if (StrLen(destName) < 3 || !WkGoalZones.Length())
		return ""
	;The zone whose name is closest to it - the game's title font fools OCR ("GOBBLERTON" can come out
	;as "coeeLERTON"), so up to a third of the letters may be off, if no other zone is as close
	destKey := "", best := "", tie := false
	for knownZone in WkKnownZones
		{
		zoneName := WalkLetters(RegExReplace(RegExReplace(knownZone, "^.*/"), "i)^[A-Z]+_Z\d+_"))
		if (zoneName = "")
			continue
		off := WalkEditDistance(destName, zoneName)
		if (off > StrLen(zoneName) // 3)
			continue
		if (best = "" || off < best)
			best := off, destKey := WalkZoneKey(knownZone), tie := false
		else if (off = best && WalkZoneKey(knownZone) != destKey)
			tie := true
		}
	if (destKey = "" || tie)
		return ""
	if (destKey = WalkZoneKey(zone))
		return 0
	for i, goalZone in WkGoalZones
		if (WalkZoneKey(goalZone) = destKey)
			return 1
	return 0
	}

;Just the letters, in capitals, with the digits OCR mistakes for letters turned back (0 O, 1 I, 5 S, 8 B)
WalkLetters(text)
	{
	StringUpper, text, text
	return RegExReplace(StrReplace(StrReplace(StrReplace(StrReplace(text, "0", "O"), "1", "I"), "5", "S"), "8", "B"), "[^A-Z]")
	}

;How many single-letter changes (add, drop or swap one) turn a into b
WalkEditDistance(a, b)
	{
	lenB := StrLen(b), prevRow := []
	Loop, % lenB + 1
		prevRow[A_Index] := A_Index - 1
	Loop, Parse, a
		{
		row := [A_Index]
		charA := A_LoopField
		Loop, % lenB
			row[A_Index + 1] := Min(prevRow[A_Index + 1] + 1, row[A_Index] + 1, prevRow[A_Index] + (charA == SubStr(b, A_Index, 1) ? 0 : 1))
		prevRow := row
		}
	return prevRow[lenB + 1]
	}

;The part of a zone name shared by a zone and the places inside it: "KM_Z10" for both
;Karamelle/KM_Z10_Gobblerton and Karamelle/Interiors/KM_Z10_UnderwaterGrotto
WalkZoneKey(zoneName)
	{
	return RegExMatch(zoneName, "i)([A-Z]+_Z\d+)", key) ? key1 : zoneName
	}

;Uses a boat or the like: X, then stand still while it moves us and the new zone loads
StartTransport(dest, why)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WkTransUsed[dest] := A_TickCount, WkTransSeen := ""
	WkArrived := 5, WkSigilUntil := A_TickCount + TransportWait, WkWaitWhat := dest
	PressKey("x")
	WalkLog("transport: '" dest "' covers the arrow and " why " - pressed X, waiting " Round(TransportWait / 1000) " s")
	SetStatus("using the " dest " - pressed X")
	}

;One step at a World Gate (after X). The Spiral Map opens with the quest's world picked, so click its
;Go To World button (at most 3 times). The map gone after a click = the loading screen into the new
;world, handled like a door's. No map within GateWait: X once more, then back to walking
GateStep()
	{
	btn := SpiralMapButton()
	if (!Walking)
		return false
	if (IsObject(btn))
		{
		if (WkGateClicks >= 3)
			{
			WalkLog("gate: clicked Go To World 3 times and the Spiral Map is still open - stopped")
			Walking := 0
			ReleaseKeys()
			SetStatus("stopped - World Gate: pick the world and click Go To World, then press F8")
			return false
			}
		WkGateClicks += 1
		WalkLog("gate: Spiral Map open - clicking Go To World at " btn.x - GameLeft "," btn.y - GameTop " (try " WkGateClicks ")")
		SetStatus("World Gate - clicking Go To World")
		WalkClick(btn.x, btn.y)
		WkGateAt := A_TickCount
		Sleep, 1500
		return Walking ? true : false
		}
	if (WkGateClicks)
		{
		WalkLog("gate: Spiral Map closed - loading the new world")
		WalkReset()
		WkLoadAt := A_TickCount
		SetStatus("waiting - loading the new world")
		return true
		}
	if (A_TickCount - WkGateAt > GateWait)
		{
		if (WkGateX < 2)
			{
			WalkLog("gate: no Spiral Map " Round(GateWait / 1000) " s after X - pressing X again")
			WkGateX += 1, WkGateAt := A_TickCount
			PressKey("x")
			Sleep, 800
			return Walking ? true : false
			}
		;Not a World Gate after all (or out of reach): walk on, and don't look for one again for a while
		WalkLog("gate: no Spiral Map after pressing X twice - walking on")
		WkArrived := 0, WkGateLook := A_TickCount + 15000
		WkBestTime := A_TickCount, WkLastRead := A_TickCount
		return true
		}
	SetStatus("World Gate - waiting for the Spiral Map")
	Sleep, 300
	return true
	}

;Which prompt panel is showing at the bottom of the game: "gate" (a World Gate: titled World Gate,
;"Press X or click to Interact"), "sigil" (a dungeon entrance: "Press X to Enter", with Team Up),
;"transport" (a boat or the like: titled e.g. "BOAT TO GOBBLERTON", "Press X or click to Use" - where it
;goes in WkPromptDest), "press" (any other "Press X ..." prompt) or "". WkPromptDest also tells one
;prompt from another. Read by OCR; the panel grows with the UI like the arrow does
InteractPrompt()
	{
	WkPromptDest := ""
	s := ArrowScale().scale
	t := OcrRect(Round(GameLeft + GameW / 2 - 330 * s), Round(GameTop + GameH - 300 * s), Round(660 * s), Round(240 * s))
	if (ErrorLevel)
		return ""
	if (RegExMatch(t, "i)w[o0]rld\s*gate") && RegExMatch(t, "i)interact"))
		return "gate"
	if (RegExMatch(t, "i)to\s*enter"))
		{
		WkPromptDest := SubStr(WalkLetters(RegExMatch(t, "m`n)^\s*TO\s+(.+?)\s*$", sigil) ? sigil1 : t), 1, 60)
		return "sigil"
		}
	;(the title is in capitals; the quest line under it isn't, so "Talk To Rosina" doesn't count)
	if (RegExMatch(t, "i)to\s*use") && RegExMatch(t, "m`n)^\s*[A-Z][A-Z']*(?:\s+[A-Z][A-Z']*)*\s+TO\s+(\S.*?)\s*$", title))
		{
		WkPromptDest := Trim(title1)
		return "transport"
		}
	;Any other prompt: "Press X to Talk", "... or click to Interact", "to Collect"... The key that tells one
	;prompt from another: its title line (an NPC's or object's name, in capitals) - the quest line OCR
	;picks up under it changes from read to read - else all its letters
	if (RegExMatch(t, "i)\bpress\b") && RegExMatch(t, "i)\bto\s+[a-z]{3,}"))
		{
		WkPromptDest := RegExMatch(t, "m`n)^\s*([A-Z][A-Z'.\- ]{3,}?)\s*$", cap) ? WalkLetters(cap1) : SubStr(WalkLetters(t), 1, 60)
		return "press"
		}
	return ""
	}

;Screen {x, y} of the middle of the Spiral Map's Go To World button, or "" if the map isn't open.
;Read by OCR in the lower right part of the map (it sits in the middle of the game, sized with the UI)
SpiralMapButton()
	{
	s := ArrowScale().scale
	x := Round(GameLeft + GameW / 2 + 60 * s), y := Round(GameTop + GameH / 2 + 200 * s)
	w := Round(500 * s), h := Round(240 * s)
	if (y + h > GameTop + GameH)
		h := GameTop + GameH - y
	OcrRect(x, y, w, h, "en", 1, lineRects)
	if (ErrorLevel || !IsObject(lineRects))
		return ""
	for each, line in lineRects
		if (RegExMatch(line.text, "i)go\s*to\s*w[o0]rld"))
			return {x: Round(line.x + line.w / 2), y: Round(line.y + line.h / 2)}
	return ""
	}

;Moves the mouse there and clicks (screen coordinates), only while walking is on and Wizard101 has focus
WalkClick(x, y)
	{
	if (!Walking || !GameActive())
		return
	MouseMove, %x%, %y%, 1
	Sleep, 40
	if (Walking && GameActive())
		Click
	Sleep, 100
	}

;One key press (down and up), only while walking is on and Wizard101 has focus
PressKey(key)
	{
	Critical
	if (Walking && GameActive())
		Send, {Blind}{%key%}
	Critical, Off
	}

;Switches walking on or off (F8). Off lets go of every key straight away
WalkToggle()
	{
	Walking := !Walking
	if (Walking)
		{
		WalkReset()
		SetStatus("walking on")
		}
	else
		{
		if (KeysDown || HeldW)
			{
			if (!GameActive())
				Refocus := 1
			ReleaseKeys()
			}
		SetStatus("walking off - press F8 to walk again")
		;Keys let go while another window had focus: give Wizard101 one clean release when it's back
		if (Refocus)
			SetTimer, WalkerRefocusWatch, 250
		}
	}

WalkerRefocusWatch()
	{
	if (Walking || !Refocus)
		{
		SetTimer, WalkerRefocusWatch, Off
		return
		}
	if (GameActive())
		{
		ReleaseKeys()
		Refocus := 0
		SetTimer, WalkerRefocusWatch, Off
		}
	}

;Holds A (goal to the left) or D (goal to the right) long enough to turn h degrees
Turn(h)
	{
	Critical
	if (!Walking || !GameActive())
		{
		Critical, Off
		return
		}
	key := h < 0 ? "a" : "d"
	ms := Round(Abs(h) / TurnRate)
	ms := ms < 30 ? 30 : ms > 800 ? 800 : ms
	KeysDown := 1
	Send, {Blind}{%key% down}
	Critical, Off
	HoldFor(ms)
	Send, {Blind}{%key% up}
	WkTurnAt := A_TickCount
	}

;Back up, turn UnstickTurn degrees to one side and walk along the obstacle for walkMs
Unstick(side, walkMs)
	{
	BackUp(BackupTime)
	if (!Walking || !GameActive())
		return
	Turn(UnstickTurn * side)
	if (!Walking || !GameActive())
		return
	HoldW(1)
	HoldFor(walkMs)
	}

;Holds S for ms (W let go first)
BackUp(ms)
	{
	HoldW(0)
	Critical
	if (!Walking || !GameActive())
		{
		Critical, Off
		return
		}
	KeysDown := 1
	Send, {Blind}{s down}
	Critical, Off
	HoldFor(ms)
	Send, {Blind}{s up}
	WkTurnAt := A_TickCount
	}

;Waits ms, but returns early (false) once walking is stopped or Wizard101 loses focus
HoldFor(ms)
	{
	stopAt := A_TickCount + ms
	while (A_TickCount < stopAt)
		{
		if (!Walking)
			return false
		if (!GameActive())
			{
			if (KeysDown || HeldW)
				ReleaseKeys(), Refocus := 1
			return false
			}
		left := stopAt - A_TickCount
		Sleep, % left < 50 ? left : 50
		}
	return true
	}

HoldW(on)
	{
	Critical
	if (on && !HeldW && Walking && GameActive())
		{
		KeysDown := 1
		Send, {Blind}{w down}
		HeldW := 1, WkWalkFrom := A_TickCount
		}
	else if (!on && HeldW)
		{
		Send, {Blind}{w up}
		HeldW := 0
		}
	Critical, Off
	}

;{Blind} so an Alt/Ctrl/Shift the user is holding isn't let go
ReleaseKeys()
	{
	Send, {Blind}{w up}{a up}{s up}{d up}
	HeldW := 0, KeysDown := 0
	}

GameActive()
	{
	return WinActive("ahk_class " GameClass " ahk_exe " GameExe)
	}

;Shows what the walker is doing in the tray tip. In AutoFarmer each new kind of status (walking,
;turning, arrived, stuck...) also goes to debug.log
SetStatus(text)
	{
	if (text = StatusText)
		return
	StatusText := text
	Menu, Tray, Tip, % StatusPrefix ": " SubStr(text, 1, 110)
	kind := StrSplit(text, " ")[1]
	if (kind != StatusKind)
		{
		StatusKind := kind
		if (IsFunc("DebugLog"))
			Func("DebugLog").Call("Walk: " text)
		}
	}

;---- Collecting: "collect / defeat N things" goals ----

;Close to the goal (or stuck near it): is it a goal to collect or defeat a number of things? Then start
;collecting (WkArrived = 7) - straight away when the arrow got there, else once nothing has changed for
;CollectWait. After a battle (or X at a prompt) with the same goal still on: carry on collecting. The
;goal line is read at most every 3 s. True if collecting started
CollectCheck(dist)
	{
	if (WkArrived = 1 && !WkArr1At)
		WkArr1At := A_TickCount
	going := IsObject(WkCollect) && !WkCollect.gaveUp
	if (going && A_TickCount - WkCollect.sureAt < 20000)
		{
		StartCollect(WkCollect.text, "same goal as before")
		return true
		}
	;(collecting before a battle or a prompt: check the goal line at once, wherever the arrow is)
	there := going || (dist <= ArriveDist) || (WkArrived = 1 && A_TickCount - WkArr1At > CollectWait) || (A_TickCount - WkBestTime > 8000)
	if (!there || A_TickCount - WkGoalReadAt < 3000)
		return false
	WkGoalReadAt := A_TickCount
	text := WalkGoalText()
	if (text = "")
		return false
	;(a goal it collected at for CollectMax without it changing: leave it be)
	if (IsObject(WkCollect) && WkCollect.gaveUp && CollectSameGoal(text, WkCollect.text))
		return false
	if (IsObject(WkCollect) && CollectSameGoal(text, WkCollect.text))
		{
		WkCollect.sureAt := A_TickCount
		StartCollect(WkCollect.text, "same goal as before")
		return true
		}
	if (!CollectGoal(text))
		return false
	WkCollect := {text: text, from: A_TickCount, sureAt: A_TickCount, last: text, gaveUp: 0, battles: 0}
	StartCollect(text, "a goal to collect / defeat things")
	return true
	}

StartCollect(text, why)
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WkArrived := 7, WkChaseFrom := 0, WkRoamLeg := 0, WkRoamLegAt := 0, WkFoesAt := 0
	WalkLog("collect: '" text "' - " why " - looking for monsters, roaming the area")
	SetStatus("collecting - " SubStr(text, 1, 60))
	}

;One step of collecting. Monster name labels on screen: walk into the biggest (a battle starts on
;contact; AutoFarmer fights it). None: roam about the spot in a widening square (walking over things
;picks them up; their "Press X" prompts are taken above), heading back once RoamRadius away. Ends when
;the goal line under the arrow changes (done, or the next goal), or after CollectMax
CollectStep(seen, h, dist)
	{
	;Is it still the same goal? (every 4 s, when the arrow and so its line are showing)
	if (seen && A_TickCount - WkGoalReadAt > 4000)
		{
		WkGoalReadAt := A_TickCount
		text := WalkGoalText()
		if (text != "" && !CollectSameGoal(text, WkCollect.text))
			{
			WalkLog("collect: the goal is now '" text "' (was '" WkCollect.text "') - following the arrow again")
			WkCollect := ""
			ReleaseKeys()
			WalkReset()
			return true
			}
		if (text != "")
			{
			WkCollect.sureAt := A_TickCount
			if (text != WkCollect.last)
				WkCollect.last := text, WalkLog("collect: " text)
			}
		}
	if (A_TickCount - WkCollect.from > CollectMax)
		{
		WalkLog("collect: still '" WkCollect.text "' after " Round(CollectMax / 60000) " minutes - giving up, waiting here")
		WkCollect.gaveUp := 1
		ReleaseKeys()
		WkArrived := 1, WkArrDist := dist, WkFar := 0
		return true
		}
	;Right after a turn the picture is still swinging round: don't steer on it yet
	if (A_TickCount - WkTurnAt < TurnSettle)
		{
		Sleep, 50
		return true
		}
	;Monsters?
	if (A_TickCount - WkFoesAt > 600)
		{
		WkFoesAt := A_TickCount
		foes := (A_TickCount > WkChaseSkipUntil) ? WalkFoes() : []
		if (foes.Length())
			{
			foe := foes[1]
			if (!WkChaseFrom)
				{
				WkChaseFrom := A_TickCount
				WalkLog("collect: monster label on screen (" foes.Length() " in all, " foe.n " px, " Round((foe.x - GameLeft) / GameW * 100) "% across) - walking into it")
				}
			if (A_TickCount - WkChaseFrom > ChaseTime)
				{
				WalkLog("collect: no battle after " Round(ChaseTime / 1000) " s of walking at it - looking elsewhere")
				WkChaseFrom := 0, WkChaseSkipUntil := A_TickCount + 15000
				HoldW(0)
				Turn(120 * WkRoamSide)
				return Walking ? true : false
				}
			;(the camera shows about 40 degrees either side of straight ahead)
			ang := (foe.x - (GameLeft + GameW / 2)) / (GameW / 2) * 40
			if (Abs(ang) > 30)
				{
				HoldW(0)
				Turn(ang)
				}
			else
				{
				HoldW(1)
				if (Abs(ang) > 6)
					Turn(ang * 0.7)
				}
			SetStatus("collecting - walking into a monster (" Round(ang) " degrees)")
			return Walking ? true : false
			}
		if (WkChaseFrom)
			WalkLog("collect: lost sight of the monster - roaming"), WkChaseFrom := 0
		}
	else if (WkChaseFrom)
		{
		Sleep, 50
		return true
		}
	;Roaming. Too far from the spot: back towards it (the arrow), then a new square
	if (seen && dist != "" && dist > RoamRadius)
		{
		if (WkRoamLeg)
			WalkLog("collect: " dist " away from the spot - heading back"), WkRoamLeg := 0
		if (Abs(h) > TurnInPlace)
			HoldW(0), Turn(h)
		else
			{
			HoldW(1)
			if (Abs(h) > AheadAngle)
				Turn(h)
			}
		SetStatus("collecting - back towards the spot (distance " dist ")")
		return Walking ? true : false
		}
	;Walking into something: back off and turn the other way
	if (HeldW && WalkStill() = 1)
		{
		WalkLog("collect: walked into something - backing off, turning")
		BackUp(600)
		Turn(110 * WkRoamSide)
		WkRoamSide := -WkRoamSide, WkRoamLegAt := A_TickCount
		return Walking ? true : false
		}
	;A widening square: legs 2 s, 2 s, 2.5 s, 2.5 s, 3 s... with a quarter turn between
	if (!WkRoamLeg || A_TickCount - WkRoamLegAt > 2000 + (WkRoamLeg // 2) * 500)
		{
		if (WkRoamLeg)
			Turn(90 * WkRoamSide)
		WkRoamLeg += 1, WkRoamLegAt := A_TickCount
		}
	HoldW(1)
	SetStatus("collecting - roaming the area (leg " WkRoamLeg ")")
	Sleep, 100
	return Walking ? true : false
	}

;The quest goal's line under the arrow (e.g. "Defeat Frost Fins in Kataba IceBlock (2 of 5)"), read by
;OCR just below where the last arrow read found the arrow. "" if it can't be read
WalkGoalText()
	{
	info := ArrowInfo()
	if (info.pvx = "" || info.pvy = "")
		return ""
	s := info.scale ? info.scale : 1
	t := OcrRect(Round(info.pvx - 450 * s), Round(info.pvy + 28 * s), Round(900 * s), Round(60 * s))
	return ErrorLevel ? "" : Trim(RegExReplace(t, "\s+", " "))
	}

;True if a goal line is about collecting or defeating a number of things: a count ("(2 of 5)", "2/5")
;or a word like Collect / Defeat / Gather
CollectGoal(text)
	{
	return RegExMatch(text, "i)\(\s*\d+\s*(of|/)\s*\d+\s*\)|\b\d+\s*/\s*\d+\b|\b(collect|defeat|gather|recover|retrieve|obtain|destroy|hunt|catch|kill|harvest|loot|acquire)\b")
	}

;True if two goal lines are the same goal: the same letters (bar a few OCR slips), not counting the
;count, which goes up as things are collected
CollectSameGoal(a, b)
	{
	a := WalkLetters(RegExReplace(a, "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?")), b := WalkLetters(RegExReplace(b, "i)\(?\s*\d+\s*(of|/)\s*\d+\s*\)?"))
	if (a = "" || b = "")
		return a = b
	return a = b || WalkEditDistance(a, b) <= (StrLen(a) > 10 ? StrLen(a) // 5 : 2)
	}

;Monsters on screen: their name labels (crimson text, e.g. "FROST FIN" over "RANK 15 ELITE"; other
;names are white, green or blue) in the game shrunk to about 240 rows (GDI COLORONCOLOR keeps each
;picked pixel's own colour). Not the bars at the top and bottom (the health globe is red). [{x, y, n},
;...] in screen pixels, the biggest label first (n = crimson samples; nearer monsters have bigger labels)
WalkFoes()
	{
	step := Round(GameH / 240), step := step < 2 ? 2 : step, sw := GameW // step, sh := GameH // step
	foes := []
	VarSetCapacity(bi, 40, 0)
	NumPut(40, bi, 0, "UInt"), NumPut(sw, bi, 4, "Int"), NumPut(-sh, bi, 8, "Int")
	NumPut(1, bi, 12, "UShort"), NumPut(32, bi, 14, "UShort")
	sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
	bits := 0, cells := {}
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", &bi, "UInt", 0, "Ptr*", bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm && bits)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		DllCall("SetStretchBltMode", "Ptr", mdc, "Int", 3)
		if (DllCall("StretchBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", sw, "Int", sh
			, "Ptr", sdc, "Int", GameLeft, "Int", GameTop, "Int", GameW, "Int", GameH, "UInt", 0x00CC0020))
			{
			DllCall("GdiFlush")
			batch := A_BatchLines
			SetBatchLines, -1
			cw := sw // 40, ch := sh // 45, cw := cw < 1 ? 1 : cw, ch := ch < 1 ? 1 : ch
			y1 := Round(sh * 0.08), y2 := Round(sh * 0.80)
			Loop, % y2 - y1
				{
				y := y1 + A_Index - 1, rowAt := bits + y * sw * 4
				Loop, %sw%
					{
					c := NumGet(rowAt + (A_Index - 1) * 4, "UInt"), r := (c >> 16) & 0xFF
					if (r < 120)
						continue
					g := (c >> 8) & 0xFF, b := c & 0xFF
					if (g > 75 || r - g < 80 || b - g < 25 || r - b < 30)
						continue
					x := A_Index - 1, key := (y // ch) * 1000 + x // cw
					if (!cells.HasKey(key))
						cells[key] := {n: 0, sx: 0, sy: 0, x1: x, x2: x}
					cell := cells[key], cell.n += 1, cell.sx += x, cell.sy += y
					if (x < cell.x1)
						cell.x1 := x
					if (x > cell.x2)
						cell.x2 := x
					}
				}
			SetBatchLines, %batch%
			}
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm, "Ptr")
		DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
	;Neighbouring cells make one label (a name and the rank line under it)
	done := {}
	for key, cell in cells
		{
		if (done.HasKey(key))
			continue
		todo := [key], done[key] := 1, n := 0, sx := 0, sy := 0, x1 := cell.x1, x2 := cell.x2
		while (todo.Length())
			{
			k := todo.Pop(), c := cells[k], n += c.n, sx += c.sx, sy += c.sy
			x1 := c.x1 < x1 ? c.x1 : x1, x2 := c.x2 > x2 ? c.x2 : x2
			for each, dk in [1, -1, 1000, -1000, 999, 1001, -999, -1001]
				if (cells.HasKey(k + dk) && !done.HasKey(k + dk))
					done[k + dk] := 1, todo.Push(k + dk)
			}
		;(a label is text: at least 10 samples and 2% of the width - not a red flag in the scenery)
		if (n >= 10 && x2 - x1 + 1 >= sw * 0.02)
			{
			at := 1
			while (at <= foes.Length() && foes[at].n >= n)
				at++
			foes.InsertAt(at, {x: GameLeft + Round((sx / n + 0.5) * step), y: GameTop + Round((sy / n + 0.5) * step), n: n})
			}
		}
	return foes
	}

;---- Is the wizard moving? A tiny grey copy of the game compared with the one before ----

;The game shrunk to 64x40 (GDI averages it), as grey levels, leaving out the wizard's column (the
;wizard and the arrow move with you) and the bars of buttons at the top and bottom
WalkSnap()
	{
	snapW := 64, snapH := 40, snap := ""
	VarSetCapacity(bi, 40, 0)
	NumPut(40, bi, 0, "UInt"), NumPut(snapW, bi, 4, "Int"), NumPut(-snapH, bi, 8, "Int")
	NumPut(1, bi, 12, "UShort"), NumPut(32, bi, 14, "UShort")
	sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", &bi, "UInt", 0, "Ptr*", bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm && bits)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		DllCall("SetStretchBltMode", "Ptr", mdc, "Int", 4)
		DllCall("SetBrushOrgEx", "Ptr", mdc, "Int", 0, "Int", 0, "Ptr", 0)
		if (DllCall("StretchBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", snapW, "Int", snapH
			, "Ptr", sdc, "Int", GameLeft, "Int", GameTop, "Int", GameW, "Int", GameH, "UInt", 0x00CC0020))
			{
			DllCall("GdiFlush")
			snap := []
			Loop, % snapH
				{
				row := A_Index - 1
				if (row < snapH * 0.10 || row >= snapH * 0.75)
					continue
				Loop, % snapW
					{
					col := A_Index - 1
					if (col >= snapW * 0.35 && col < snapW * 0.65)
						continue
					bgr := NumGet(bits + 0, (row * snapW + col) * 4, "UInt")
					snap.Push(((bgr >> 16 & 0xFF) * 299 + (bgr >> 8 & 0xFF) * 587 + (bgr & 0xFF) * 114) // 1000)
					}
				}
			}
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm, "Ptr")
		DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
	return snap
	}

;1 if the picture has hardly changed since the last look (W held, no turn or backing up since - nor
;the camera still swinging round after one), 0 if
;it has, "" if there's nothing fair to compare with yet. Standing still or walking into a wall: 0-1%
;of it changes between looks; walking: 45-85% (measured on recorded frames, 2026-10-16)
WalkStill()
	{
	nowMs := A_TickCount
	if (IsObject(WkSnapPrev) && nowMs - WkSnapAt < 300)
		return ""
	batch := A_BatchLines
	SetBatchLines, -1
	snap := WalkSnap()
	result := ""
	if (IsObject(snap) && IsObject(WkSnapPrev) && snap.Length() && snap.Length() = WkSnapPrev.Length()
		&& nowMs - WkSnapAt <= 1500 && WkSnapAt > WkTurnAt + TurnSettle && WkSnapAt > WkWalkFrom + 200)
		{
		;A cell counts as changed by more than a bit of its brightness (dark places change less)
		changedCells := 0
		for i, grey in snap
			if (Abs(grey - WkSnapPrev[i]) > 3 + (grey + WkSnapPrev[i]) // 25)
				changedCells += 1
		WkMotion := Round(changedCells / snap.Length(), 2)
		result := WkMotion < StillFrac ? 1 : 0
		}
	SetBatchLines, %batch%
	WkSnapPrev := snap, WkSnapAt := nowMs
	return result
	}

;A loading screen, or just after one with no arrow seen since (the game's log, read now): then the
;arrow isn't behind something - no backing up or turning, just wait for it (and press Space now and
;then for a dialogue the new zone may open: WkLoadAt)
WalkLoadingScreen()
	{
	WalkZone(true)
	if (!WkLoading && !(WkLoadedAt && WkLoadedAt > WkSeenAt))
		return false
	if (!WkLoadAt)
		{
		WkLoadAt := A_TickCount, WkGoneSpaces := 0, WkSpaceAt := 0
		WalkLog("loading screen (the game's log) - waiting for the arrow, no turning")
		}
	return true
	}

;---- Remembered obstacles: where it got stuck (zone + distance to the goal) and which way round worked ----

;Which zone the wizard is in, from the game's own log ("ConnectComplete destination Zone=..."), e.g.
;"Karamelle/KM_Z03_GumdropForest". Looked at every few seconds, only when the log has grown
WalkZone(fresh := false)
	{
	static logPath := "", lastSize := -1, zone := "", checkedAt := 0, lastHead := ""
	if (A_TickCount - checkedAt < (fresh ? 250 : 3000))
		return zone
	checkedAt := A_TickCount
	WinGet, exePath, ProcessPath, ahk_class %GameClass% ahk_exe %GameExe%
	if (exePath != "")
		{
		SplitPath, exePath,, binDir
		logPath := binDir "\WizardClient.log"
		}
	if (logPath = "")
		return zone
	FileGetSize, logSize, %logPath%
	if (ErrorLevel || logSize = lastSize)
		return zone
	;The last part of the log normally has the latest zone change; the whole log if not known yet
	readFrom := (zone != "" && logSize > lastSize && lastSize > 300) ? lastSize - 300 : (zone != "" && logSize > 262144 ? logSize - 262144 : 0)
	if (logSize < lastSize)
		readFrom := 0
	lastSize := logSize
	logFile := FileOpen(logPath, "r", "CP0")
	if (!IsObject(logFile))
		return zone
	;The game starts a new log each time it starts, with a new time stamp on its first line: read
	;that one from the top, however long it has got
	logHead := logFile.Read(17)
	if (logHead != lastHead)
		{
		if (lastHead != "")
			readFrom := 0, zone := ""
		lastHead := logHead
		}
	logFile.Pos := readFrom
	chunk := logFile.Read(logSize - readFrom)
	logFile.Close()
	;(whole lines only: a line still being written could hold half a zone name). After each zone change
	;the game lists the zones of the quest's goals ("checking goal zone ...")
	foundAt := 1, goals := "", zoneBefore := zone
	while (foundAt := RegExMatch(chunk, "(ConnectComplete destination Zone=|checking goal zone )(\S+)\r?\n", zoneMatch, foundAt))
		{
		if (InStr(zoneMatch1, "ConnectComplete"))
			zone := zoneMatch2, goals := []
		else
			{
			if (!IsObject(goals))
				goals := []
			isNew := true
			for i, goalZone in goals
				if (goalZone = zoneMatch2)
					isNew := false
			if (isNew)
				goals.Push(zoneMatch2)
			}
		WalkZoneSeen(zoneMatch2)
		foundAt += StrLen(zoneMatch)
		}
	if (IsObject(goals) && goals.Length())
		WkGoalZones := goals
	;A zone transfer (a loading screen) started and not finished yet, or finished just now - only from
	;what was written since the last look (the first read of a log is history)
	if (zoneBefore != "" && readFrom > 0)
		{
		startAt := InStr(chunk, "MSG_ZoneTransferRequest", false, 0), doneAt := InStr(chunk, "ConnectComplete destination", false, 0)
		if (startAt > doneAt)
			WkLoading := 1
		else if (doneAt)
			WkLoading := 0, WkLoadedAt := A_TickCount
		}
	;(the zone just left, and when that was noticed: coming out of a dungeon puts you at its sigil)
	if (zoneBefore != "" && zone != zoneBefore)
		WkZoneFrom := zoneBefore, WkZoneAt := A_TickCount
	return zone
	}

;Every zone name seen in the game's log, kept in resources\known_zones.txt (a boat's "TO GOBBLERTON"
;is only understood once Karamelle/KM_Z10_Gobblerton has been seen)
WalkZonesLoad()
	{
	WkKnownZones := {}
	dir := AqDir()
	WkZonesFile := dir "\resources\known_zones.txt"
	Loop, Read, %WkZonesFile%
		if (Trim(A_LoopReadLine) != "")
			WkKnownZones[Trim(A_LoopReadLine)] := 1
	}

WalkZoneSeen(zoneName)
	{
	if (zoneName = "" || WkKnownZones.HasKey(zoneName))
		return
	WkKnownZones[zoneName] := 1
	FileAppend, %zoneName%`n, %WkZonesFile%
	}

WalkMemLoad()
	{
	WkMem := []
	if (WkMemFile = "")
		{
		dir := AqDir()
		WkMemFile := dir "\resources\walk_memory.txt"
		}
	Loop, Read, %WkMemFile%
		{
		line := Trim(A_LoopReadLine)
		if (line = "" || SubStr(line, 1, 1) = ";" || !RegExMatch(line, "^[^|]+(\|-?\d+){5}$"))
			continue
		part := StrSplit(line, "|")
		if (part.Length() >= 6)
			WkMem.Push({zone: part[1], dist: part[2] + 0, side: part[3] + 0, walkMs: part[4] + 0, wins: part[5] + 0, fails: part[6] + 0, preAt: 0})
		}
	}

WalkMemSave()
	{
	text := "; Walker.ahk's remembered obstacles, one per line (delete a line, or the file, to forget):`n"
		. "; zone|distance to the goal where it got stuck|side that got round it (1 right, -1 left)|ms walked along it|times it worked|times it didn't`n"
	for i, spot in WkMem
		text .= spot.zone "|" spot.dist "|" spot.side "|" spot.walkMs "|" spot.wins "|" spot.fails "`n"
	FileDelete, %WkMemFile%.tmp
	FileAppend, %text%, %WkMemFile%.tmp
	FileMove, %WkMemFile%.tmp, %WkMemFile%, 1
	}

;The remembered obstacle in that zone nearest that distance (within MemNear), if its way round has
;worked more often than not
WalkMemFind(zone, d, any := false)
	{
	best := ""
	for i, spot in WkMem
		if (spot.zone = zone && Abs(spot.dist - d) <= MemNear && (any || spot.wins > spot.fails)
			&& (!IsObject(best) || Abs(spot.dist - d) < Abs(best.dist - d)))
			best := spot
	return best
	}

;A remembered obstacle just ahead: same zone, the goal up to MemAhead further than where it was, its
;way round has worked at least twice (so most likely the same route), and not already steered round
;in the last 20 s
WalkMemAhead(zone, d)
	{
	if (zone = "")
		return ""
	for i, spot in WkMem
		if (spot.zone = zone && d >= spot.dist && d <= spot.dist + MemAhead && spot.wins >= 2 && spot.wins > spot.fails
			&& A_TickCount - spot.preAt > 20000)
			return spot
	return ""
	}

;Learns from a try at getting round an obstacle: worked (it got clearly closer afterwards) or not
WalkMemLearn(zone, d, side, walkMs, worked)
	{
	if (zone = "" || d = "")
		return
	;What's in the file now (the other script may have learned something meanwhile)
	WalkMemLoad()
	spot := WalkMemFind(zone, d, true)
	if (!IsObject(spot))
		{
		if (!worked)
			return
		spot := {zone: zone, dist: Round(d), side: side, walkMs: walkMs, wins: 0, fails: 0, preAt: 0}
		WkMem.Push(spot)
		}
	if (worked)
		{
		;The other way round worked this time: switch to it
		if (spot.side != side)
			spot.side := side, spot.wins := 0, spot.fails := 0
		spot.wins += 1, spot.walkMs := walkMs, spot.dist := Round((spot.dist * 3 + d) / 4)
		}
	else
		spot.fails += 1
	;Forget one that keeps failing
	if (spot.fails >= spot.wins + 2)
		{
		for i, other in WkMem
			if (other = spot)
				{
				WkMem.RemoveAt(i)
				break
				}
		WalkLog("forgot the obstacle at distance " spot.dist " in " zone " (its way round stopped working)")
		}
	WalkMemSave()
	}

;OnExit handler: never leave a movement key held down
WalkerQuit(reason, code)
	{
	ReleaseKeys()
	return 0
	}
