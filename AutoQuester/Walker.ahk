; Walker.ahk - walks the wizard towards the current quest goal by following the yellow quest arrow,
; one step per WalkStep() call. AHK v1.1, functions only. Shared by AutoQuester.ahk (walking only)
; and AutoFarmer\Autofarmer.ahk (battles and walking in one loop), so walking fixes go here.
;
; Needs, from the script that includes it: the super-globals GameLeft, GameTop, GameW, GameH (the
; game's client area, kept up to date by its UpdateGameRect()), GameExe and GameClass, and an
; #Include of ArrowReader.ahk. Call WalkerInit() once at start.
;
; In AutoFarmer the game's memory is a better source for the same decisions (NavRead in Vision.ahk: the
; vision helper reads where the wizard is and where the quest arrow points - READ-ONLY, navmem in
; PlayerStats.txt): its heading once it has agreed with the arrow's, its distance instead of the OCR'd
; number, steering on while scenery hides the arrow, and turns measured as they go. Whenever it can't be
; used the arrow on screen decides, as before. See "The game's memory" near the bottom.

global ArriveDist, TurnRate, AheadAngle, TurnInPlace, StuckTime, UnstickTries, UnreadLimit, MinMatch
global NearDist, TalkMax, TalkGap, PushTime, PushStraightDist, PushStraightTime, BackupTime, UnstickTurn, UnstickBias, BiasTime
global HiddenWalkTime, PushHiddenTime, LoadSpaceWait, LoadSpaceMax, GateDist, GateWait, SigilWait
global FastStuckTime, StillFrac, MemNear, MemAhead, TurnSettle, TransportWait, WkAcceptLook
;Cheat Engine's speedhack (AutoFarmer's speedhack setting): the game's speed now (1 = normal - the walker's timings are
;divided by it), when the bot last pressed one of its keys, normal speed held till (getting round an obstacle), and
;how near the goal it goes back to normal (the arrow's number / game units)
global SpeedNow, SpeedSentAt, WkSpeedHold, SpeedSlowDist, SpeedSlowUnits
;Why the speedhack's off for this run ("" on - the game was seen not sped up: Cheat Engine not attached, the key not
;taking), and how many turns in a row looked wrong (NavTurn)
global SpeedOff, SpeedMiss
;A quest offer's Accept: when a dialogue was last Spaced through (its offer may follow), the looks since, the clicks
;on this offer and when the first was
global WkDlgEndAt, WkAcceptLooks, WkAcceptClicks, WkAcceptAt
global WkGoalZones, WkKnownZones, WkZonesFile, WkPromptDest, WkTransUsed, WkTransSeen, WkTransStep, WkTransStepAt, WkWaitWhat
global WkPromptUsed, WkZoneFrom, WkZoneAt, WkPressAt, DialogQuiet, WkQuietUntil, WkQuietLogged
;A loading screen per the game's log: a zone transfer under way (WkLoading), when the last one finished
global WkLoading, WkLoadedAt, SkipGap, WkDlgLook
global CollectWait, RoamRadius, ChaseTime, CollectMax
;Telling you when it needs you (WalkNotify): settings; the notice up now ("" none: its kind, title, window,
;shown now, OK'd - not shown again till it's sorted); how long without an arrow / waiting at a goal; the
;last X of the bot's and its one Escape; the last distance read; on top of the goal / stuck by it
global NoArrowNotify, WaitNotify, CollectStall, OnTopDist
;Badly stuck: teleport to the Commons and start over (WalkCommonsReset) - settings; when it last did; the
;watch on getting closer to the goal (best distance, since when, the last step it looked)
global ResetTeleport, ResetEvery, StuckForever, WkResetAt, WkProgBest, WkProgAt, WkProgStep
global WkNoteKind, WkNoteTitle, WkNoteHwnd, WkNoteShown, WkNoteOff, WkNoArrowFrom, WkWaitFrom, WkLastX, WkEscTried
;(no arrow and the game's memory not standing in for it either: since when - the "No quest arrow" notice)
global WkNoGuideFrom
global WkLastDist, WkLastDistAt, WkOnTop, WkOnTopAt, WkOnTopBacked, WkOnTopDone, WkStuckNearDone, WkStuckTalk, WkTalkAt
global WkCollect, WkGoalReadAt, WkArr1At, WkFoesAt, WkChaseFrom, WkChaseSkipUntil, WkRoamLeg, WkRoamLegAt, WkRoamSide
global Walking, HeldW, KeysDown, Refocus, StatusText, StatusKind, StatusPrefix
global WkBestDist, WkBestTime, WkLastRead, WkSide, WkTries, WkNear, WkFar, WkArrived, WkTalk, WkPushUntil
global WkSeenAt, WkHidden, WkHiddenAt, WkBias, WkBiasUntil, WkPrevMovedH, WkLastBoxOff, WkLastMode, WkBackups, WkBackupsFrom
global WkDialog, WkPushes, WkPushStart, WkStraight, WkStraightAt
global WkTalkDist, WkArrDist, WkLoadAt, WkSpaceAt, WkGoneSpaces
global WkGateAt, WkGateClicks, WkGateX, WkGateLook, WkSigilUntil, WkFarAt, WkSigilSeen
global WkSnapPrev, WkSnapAt, WkTurnAt, WkWalkFrom, WkStill, WkMotion, WkMem, WkMemFile, WkEsc
;Turns made on the spot in a row with no walking between (a route point jumping behind the wizard): after 3 the next
;one's made walking on, so it never just spins
global WkSpins
;AutoFarmer's "a battle is on" flag (blank in AutoQuester on its own): never talk or push on during a battle
global inbattle
;The game's memory (AutoFarmer's NavRead, read-only; AutoQuester on its own has none): settings; this step's
;reading - usable, its heading in use, the heading (degrees, + = right, like ReadArrow's), the distance in the
;arrow's own units ("" until known), zone changes to go, the reading itself; its heading's sign (the game's
;world could be either way round) and whether it's trusted yet (readings that agree with the arrow / are its
;mirror image / match neither); the arrow's distance per game unit (the readings it's from; readings far off
;it in a row); on or off (logged when that changes); the
;last position (how fast it's moving); closed-loop turns so far, the last odd one logged; the file it's kept
;in, and the sign saved there; why the last NavRead got nothing (Vision.ahk)
global NavTurnTol, NavTurnCap, NavAgreeNeed
global WkNavOk, WkNavUse, WkNavH, WkNavD, WkNavHops, WkNavObj, WkNavSign, WkNavTrusted, WkNavAgree, WkNavMirror, WkNavOdd
global WkNavScale, WkNavScales, WkNavScaleBad, WkNavState, WkNavPrev, WkNavTurns, WkNavTurnLog, WkNavFile, WkNavSignSaved, NavWhy
;Its heading's sign checked (by the arrow agreeing, or a turn - kept in the file); the arrow's distance per game
;unit for each zone it's been worked out in, the zone the readings so far are from, and the middle of all the
;zones' (for a zone not worked out yet); the memory standing in for an arrow it can't see (since when)
global WkNavChecked, WkNavZScales, WkNavScaleZone, WkNavScaleAll, WkStandIn
;The route round walls over the zone's map (the vision helper plans it, vision\navroute.py): on or off (the
;setting); steering along it this step; how far is left along it (arrow units); the least left so far, for
;"is it getting anywhere" and for the badly-stuck watch; on or off (logged when that changes)
global NavRoute, WkNavRouted, WkNavLeft, WkRouteBest, WkRouteProg, WkRouteState
;(arrival and walking straight through a doorway by the game's memory, in game units: see the settings)
global ArriveUnits, PushUnits
;(X pressed at a prompt: what it opened looked at already; the quest's goal line as last read, and when)
global WkAfterXLooked, WkGoalLine, WkGoalLineAt
;(prompts walked past - not the quest's - logged, when: apart from WkPromptUsed, which says what X was pressed at;
;what was on screen just before X, for what X opened: WalkCloseAfterX)
global WkPromptSkip, WkPreXText
;A teleport on the game's path, right at it (the helper's route stops there): the seconds waited there ("" not
;at one), where it is ("x,y"); the one walked on into already; no way on but teleports that don't take the wizard
global WkNavJump, WkNavJumpAt, WkJumpKey, WkJumpStuck, WkJumpPushUntil
;A mob on the way that the helper's route can't go round (mobavoid): the seconds waited for it to move off ("" none),
;its name; the one last logged
global WkNavMob, WkNavMobName, WkMobLogged, WkNavMobAt
;(when the arrow itself was last on screen; whether it was right before X was pressed at a prompt)
global WkRealSeenAt, WkArrowAtX
;(an arrow read as the memory's mirror image, its sign checked: when that was last logged)
global WkNavMirrorSaid
;(pushing into the way out of the zone without an X first: if it doesn't load, X after all - a World Gate)
global WkNavDoor

;Settings and starting state. Returns false if the arrow shapes (resources\arrow_refs.txt) are missing
WalkerInit(prefix := "AutoQuester")
	{
	;---- Settings ----
	ArriveDist := 15     ;stop when the distance on the arrow is this or less (walks again when a new goal appears)
	ArriveUnits := 150   ;...by the game's memory (when it can be used): this many game units from the goal - the
	                     ;arrow's number means more or less in each zone (15 on it is 120-1500 units), this doesn't
	PushUnits := 250     ;...and the PushStraightDist below, by the game's memory
	TurnRate := 0.15     ;degrees the wizard turns per ms of holding A/D (measured: 22.5 degrees per 150 ms)
	TurnSettle := 500    ;ms the camera takes to catch up after a turn: don't steer on the arrow before then
	AheadAngle := 12     ;arrow within this many degrees of straight ahead: just walk
	TurnInPlace := 45    ;arrow (or the route) further off than this: stop, turn on the spot, then walk straight on -
	                     ;turning with W held swings the wizard round an arc about 100 units wide, into walls and round
	                     ;NPCs and the goal; under it (and over AheadAngle) the small turn is made walking on
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
	CollectStall := 180000 ;collecting: the count ("2 of 5") hasn't gone up for this long (battles left out):
	                      ;stop, wait there, and show you a notice (Keep trying / Stop walking)
	NoArrowNotify := 45000 ;no quest arrow this long out of battle (no loading screen): a notice for you
	WaitNotify := 180000  ;at a goal, waiting this long for the next one: a notice for you
	ResetTeleport := 1    ;badly stuck (gave up going round an obstacle, or no closer to the goal for StuckForever of
	                      ;walking): teleport to the world's Commons (End) and walk on from there; 0 = just stop
	ResetEvery := 600000  ;...at most once every this long (ms); stuck again sooner: it stops and tells you
	StuckForever := 180000 ;walking (battles, talks, collecting left out) this long without getting closer = badly stuck
	OnTopDist := 20       ;the arrow gone (or stuck) this close to the goal: it's on top of it / the thing itself
	                      ;is in the way - arrived (X), not backing up and turning, not going round it
	;The game's memory (AutoFarmer, navmem:1 in PlayerStats.txt - read-only):
	NavAgreeNeed := 3     ;its heading is steered by once this many readings agree with the arrow on screen
	NavTurnTol := 5       ;a turn holds A / D until the wizard's facing is within this many degrees...
	NavTurnCap := 2500    ;...for at most this long (ms)
	NavRoute := 1         ;steer along the route the vision helper plans round walls over the zone's map (its
	                      ;floor and obstacles); 0 = straight at where the quest arrow points, as before

	Walking := 0, HeldW := 0, KeysDown := 0, Refocus := 0, WkFarAt := 0, WkTurnAt := 0, WkWalkFrom := 0
	SpeedNow := 1, SpeedSentAt := 0, WkSpeedHold := 0, SpeedSlowDist := 40, SpeedSlowUnits := 600, SpeedOff := "", SpeedMiss := 0
	WkGoalZones := [], WkTransUsed := {}, WkTransSeen := "", WkTransStep := 0, WkTransStepAt := 0, WkWaitWhat := "sigil"
	WkPromptUsed := {}, WkZoneFrom := "", WkZoneAt := 0, WkPressAt := 0, WkQuietUntil := 0, WkQuietLogged := 0
	WkPromptSkip := {}, WkPreXText := ""
	WkNavJump := "", WkNavJumpAt := "", WkJumpKey := "", WkJumpStuck := 0, WkJumpPushUntil := 0
	WkNavMob := "", WkNavMobName := "", WkMobLogged := "", WkNavMobAt := 0
	WkLoading := 0, WkLoadedAt := 0, WkDlgLook := 0
	WkCollect := "", WkGoalReadAt := 0, WkAfterXLooked := 0, WkGoalLine := "", WkGoalLineAt := 0, WkRealSeenAt := 0, WkArrowAtX := 0
	WkNoteKind := "", WkNoteTitle := "", WkNoteHwnd := 0, WkNoteShown := 0, WkNoteOff := 0, WkWaitFrom := 0, WkLastX := 0
	WkResetAt := 0
	WkNavOk := 0, WkNavUse := 0, WkNavH := "", WkNavD := "", WkNavHops := "", WkNavObj := "", WkNavState := ""
	WkNavTrusted := 0, WkNavAgree := 0, WkNavMirror := 0, WkNavOdd := 0, WkNavScales := [], WkNavScaleBad := 0
	WkNavPrev := "", WkNavTurns := 0, WkNavTurnLog := 0, WkStandIn := 0
	WkNavRouted := 0, WkNavLeft := "", WkRouteBest := "", WkRouteProg := "", WkRouteState := "", WkNavMirrorSaid := 0
	WalkNavLoad()
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
	WkDialog := 0, WkPushes := 0, WkPushStart := 0, WkStraight := 0, WkStraightAt := 0, WkSpins := 0
	WkTalkDist := "", WkArrDist := "", WkLoadAt := 0, WkSpaceAt := 0, WkGoneSpaces := 0
	WkGateAt := 0, WkGateClicks := 0, WkGateX := 0, WkGateLook := 0, WkSigilUntil := 0, WkSigilSeen := 0
	WkBackups := 0, WkBackupsFrom := 0
	WkSeenAt := 0, WkHidden := 0, WkHiddenAt := 0, WkBias := 0, WkBiasUntil := 0, WkPrevMovedH := "", WkLastBoxOff := 0, WkLastMode := 0
	WkSnapPrev := "", WkSnapAt := 0, WkStill := 0, WkMotion := "", WkEsc := ""
	WkArr1At := 0, WkFoesAt := 0, WkChaseFrom := 0, WkChaseSkipUntil := 0, WkRoamLeg := 0, WkRoamLegAt := 0, WkRoamSide := 1
	WkNoArrowFrom := 0, WkNoGuideFrom := 0, WkEscTried := 0, WkLastDist := "", WkLastDistAt := 0
	WkOnTop := 0, WkOnTopAt := 0, WkOnTopBacked := 0, WkOnTopDone := 0, WkStuckNearDone := 0, WkStuckTalk := 0, WkTalkAt := 0
	WkProgBest := "", WkProgAt := A_TickCount, WkProgStep := A_TickCount
	WkNavDoor := 0, WkStandIn := 0, WkRouteBest := "", WkRouteProg := ""
	;(a new goal: its line is read again)
	WkGoalLineAt := 0
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
	;A notice for you: hidden in a battle (it mustn't cover what the battle reads), shown again after - also
	;while walking is off (the "stuck" one)
	if (inbattle && WkNoteShown)
		WalkNoteHide()
	else if (!inbattle && WkNoteKind != "" && !WkNoteShown && !WkNoteOff)
		WalkNoteShow()
	if (!Walking)
		return false
	if (!GameActive())
		{
		if (KeysDown)
			ReleaseKeys(), Refocus := 1
		SetStatus("paused - click into Wizard101 to carry on")
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkNoArrowFrom := 0, WkNoGuideFrom := 0, WkWaitFrom := 0
		Sleep, 300
		return true
		}
	if (Refocus)
		ReleaseKeys(), Refocus := 0
	if (inbattle && WkArrived >= 2)
		WalkReset()
	;At a World Gate: the Spiral Map covers the arrow, so no reading it
	if (WkArrived = 4)
		{
		WkNoArrowFrom := 0
		return GateStep()
		}
	;Entering a sigil (X pressed): stand still while it counts down and the dungeon loads, then carry
	;on like after a loading screen. Short steps, so AutoFarmer still notices a battle meanwhile
	if (WkArrived = 5)
		{
		WkNoArrowFrom := 0
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
	;The game's memory (AutoFarmer's vision helper, read-only), when it can be used: its heading instead of
	;the arrow's once the two have agreed, its distance instead of the OCR'd number (which misses lone digits)
	;once it's known how the two compare. Compared with the arrow only when it reads well (in its usual spot,
	;matching well) - the heading only once the camera has settled after the last turn. Anything wrong with
	;it: the arrow, as before
	fair := seen && !moved && score >= 0.8
	WalkNav(fair && A_TickCount - WkTurnAt > WalkSettle() + 150 ? h : "", fair ? dist : "")
	;The way on is only teleports that don't take the wizard (locked till a quest's done, or only the other way)
	;and the zone's paths have no other: walking off, and a notice - the arrow would lead back to one
	if (WkJumpStuck = 1)
		{
		WkJumpStuck := 2
		Walking := 0
		ReleaseKeys()
		WalkLog("stuck at a teleport: the quest's way on is a teleport that doesn't take the wizard (locked, or one way only), and the zone's paths have no other - walking off")
		SetStatus("stuck - the way on is a teleport that doesn't work here. Press F8 to walk again")
		WalkNotify("stuck", "Stuck at a teleport", "The quest's way on goes through a teleport here that doesn't take the wizard (locked till a quest's done, or it only goes the other way), and the zone's paths have no other way, so walking is off. Do what opens it (or move on to another quest) and press F8 to walk again.")
		return false
		}
	if (WkNavUse)
		h := WkNavH
	if (WkNavD != "")
		dist := WkNavD
	;No arrow on screen while the game's memory can be used: it stands in for the arrow - its heading and
	;distance, as if the arrow were seen (WalkNavStandIn: not in a battle or at a loading screen). A see-through
	;arrow on a floor its own colour (the gold carpet in Pigswick Academy) can't be picked out, and scenery hides
	;it. Dialogues and prompts are still looked for meanwhile (standIn, below), as when there's no arrow
	arrowSeen := seen
	if (arrowSeen)
		WkRealSeenAt := A_TickCount
	standIn := seen ? 0 : WalkNavStandIn()
	;(it turned to check the memory's heading: look again)
	if (standIn < 0)
		return Walking ? true : false
	if (standIn)
		{
		seen := 1, WkSeenAt := A_TickCount, WkLoadAt := 0, WkHidden := 0
		if (IsObject(WkTransSeen))
			WkTransSeen.seenAfter := 1
		if (!WkStandIn)
			{
			;(a dialogue that's just opened covers the arrow too: looked for now, below)
			WkStandIn := A_TickCount, WkDlgLook := 0
			WalkLog("no arrow on screen - the game's memory stands in for it (heading " Round(h) " degrees, distance " dist ")")
			}
		}
	else if (WkStandIn)
		{
		WalkLog((seen ? "arrow back" : "no arrow, and the game's memory can't stand in for it now") " - it stood in for " Round((A_TickCount - WkStandIn) / 1000, 1) " s")
		WkStandIn := 0
		}
	;The last distance read (on top of the goal, below) - the arrow's, or the memory's even while the arrow is
	;hidden. No arrow out of battle with no loading screen: how long - Escape once if an X of the bot's may have
	;opened something Space doesn't close (a shop), then a notice for you; it's closed once the arrow is back.
	;(The Escape goes by the arrow on screen even while the game's memory stands in for it - a window X opened
	;covers the arrow, not the memory; the notice only when nothing stands in for it either)
	if ((seen || WkNavD != "") && dist != "")
		WkLastDist := dist, WkLastDistAt := A_TickCount
	if (arrowSeen || inbattle || WkLoading || inbattle = "")
		{
		WkNoArrowFrom := 0, WkNoGuideFrom := 0
		if (arrowSeen)
			WkEscTried := 0, WalkNotifyClose("arrow")
		}
	else
		{
		if (!WkNoArrowFrom)
			WkNoArrowFrom := A_TickCount
		if (standIn)
			WkNoGuideFrom := 0, WalkNotifyClose("arrow")
		else if (!WkNoGuideFrom)
			WkNoGuideFrom := A_TickCount
		gone := A_TickCount - WkNoArrowFrom
		if (gone > 15000 && !WkEscTried && WkLastX && A_TickCount - WkLastX < 120000 && !WalkDialogOpen())
			{
			;(a quest offer: accepted, not closed)
			if (WalkAcceptQuest("no arrow since an X"))
				return Walking ? true : false
			WkEscTried := 1
			WalkEscape()
			return Walking ? true : false
			}
		if (WkNoGuideFrom && A_TickCount - WkNoGuideFrom > NoArrowNotify)
			WalkNotify("arrow", "No quest arrow", "No quest arrow for " Round((A_TickCount - WkNoGuideFrom) / 1000) " s, out of battle. Is a quest tracked? Is a window open over the game? It walks on by itself once the arrow is back.")
		}
	;Waiting at a goal for the next one for WaitNotify, out of battle: tell you (only while the arrow shows -
	;no arrow has its own notice)
	if (WkArrived = 1 && !inbattle)
		{
		if (!WkWaitFrom)
			WkWaitFrom := A_TickCount
		else if (seen && A_TickCount - WkWaitFrom > WaitNotify)
			WalkNotify("wait", "Waiting at the quest goal", "The wizard has been at the quest goal for " Round((A_TickCount - WkWaitFrom) / 60000) " minutes and the quest hasn't moved on - it may need something the bot can't do. It walks on by itself once there's a new goal.")
		}
	else if (WkArrived != 1)
		{
		WkWaitFrom := 0
		WalkNotifyClose("wait")
		}

	;A dialogue box (its NEXT / DONE / MORE / BACK button showing - it covers or pushes up the arrow):
	;Space through it as fast as the game takes it, whatever the walker was doing
	if ((!seen || moved || standIn) && !inbattle && A_TickCount > WkDlgLook)
		{
		WkDlgLook := A_TickCount + 400
		if (WalkDialogOpen())
			return WalkSkipDialog()
		}
	;A quest offer still up after a dialogue (it covers the arrow): its ACCEPT
	if ((!seen || standIn) && !inbattle && WkDlgEndAt && A_TickCount - WkDlgEndAt < 30000 && A_TickCount > WkAcceptLook)
		{
		WkAcceptLooks += 1
		WkAcceptLook := A_TickCount + (WkAcceptLooks > 2 ? 3000 : 1500)
		if (WalkAcceptQuest("the arrow's gone since the dialogue"))
			return Walking ? true : false
		}

	;The arrow led to a World Gate (the goal is in another world) or a sigil (a dungeon entrance):
	;close to it, its prompt pushes the arrow up or covers it. Only when the arrow was last this close,
	;so walking past a World Gate or a sigil on the way somewhere else doesn't count (the game's memory knows
	;the distance even while the prompt covers the arrow)
	if ((seen || WkNavD != "") && dist != "" && dist > GateDist)
		WkFarAt := A_TickCount
	near := (WkBestDist != "" && WkBestDist <= GateDist) || ((seen || WkNavD != "") && dist != "" && dist <= GateDist)
	;Standing on a sigil (or started there) its prompt covers the arrow and no distance reads at all.
	;If the arrow hasn't shown a far-off goal lately, the sigil is where it led - checked a few times
	;over a second or two first, so a passing frame without the arrow doesn't count
	hiddenHere := !seen && A_TickCount - WkFarAt > 10000
	if (!hiddenHere)
		WkSigilSeen := 0
	if ((WkArrived <= 1 || WkArrived = 3 || WkArrived = 7) && !inbattle && (!seen || moved || standIn) && A_TickCount > WkGateLook)
		{
		WkGateLook := A_TickCount + ((seen && !near && !standIn) ? 1500 : 700)
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
		;Any other "Press X ..." prompt (talk, collect, open...) the quest wants (WalkPromptWanted: its name in the
		;goal line, close to the goal, or collecting): press X - once a minute for the same one - then Space
		;through whatever it opens and walk on. Others - an NPC or a vendor walked past - are left alone
		if (prompt = "press" && WalkPromptFree(WkPromptDest, 60000))
			{
			if (WalkPromptWanted(WkPromptDest, dist))
				{
				StartPressX(WkPromptDest)
				return true
				}
			if (!WkPromptSkip.HasKey(WkPromptDest) || A_TickCount - WkPromptSkip[WkPromptDest] > 60000)
				WkPromptSkip[WkPromptDest] := A_TickCount, WalkLog("prompt '" SubStr(WkPromptDest, 1, 40) "' - not the quest's (not in the goal line, not near the goal): no X, walking on")
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
		;What X opened: an OK box or a window - a shop, a vendor's list - is closed first (WalkCloseAfterX: OK, or
		;Escape - nothing in it is ever clicked); looked at once, a moment after X
		if (!WkDialog && !WkAfterXLooked && A_TickCount - WkPressAt > 700 && !WalkDialogOpen())
			{
			WkAfterXLooked := 1
			if (WalkCloseAfterX())
				{
				WkArrived := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
				WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
				return true
				}
			}
		;(a dialogue covers the arrow on screen - not the game's memory standing in for it, which goes on
		;regardless: then it counts when the arrow itself was on screen right before X and has gone; with no
		;arrow to go by - Pigswick's carpet - only a dialogue box that's read)
		if (((standIn ? WkArrowAtX : !seen) || WalkDialogOpen()) && A_TickCount - WkPressAt < 60000)
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
	if ((WkArrived = 0 || WkArrived = 1) && !inbattle && seen && dist != "" && (dist <= RoamRadius || (IsObject(WkCollect) && WkCollect.gaveUp)) && CollectCheck(dist))
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
			;On top of the goal and X opened no dialogue (one would have been Spaced through above, setting
			;WkDialog): no Space (it jumps) - after 2.5 s step back once so the arrow shows again
			if (WkOnTop && !WkDialog)
				{
				if (!WkOnTopBacked && A_TickCount - WkOnTopAt > 2500)
					{
					WkOnTopBacked := A_TickCount
					WalkLog("talk: X on top of the goal opened nothing - stepping back so the arrow shows")
					BackUp(600)
					return Walking ? true : false
					}
				;(stepped back and still no arrow: something hides it after all - the usual search)
				if (WkOnTopBacked && A_TickCount - WkOnTopBacked > 2000)
					{
					WalkLog("talk: still no arrow after stepping back - looking for it (backing up, turning)")
					WkArrived := 0, WkOnTop := 0, WkSeenAt := A_TickCount - 1100, WkHidden := 0, WkHiddenAt := 0
					return true
					}
				SetStatus("at the goal - waiting for what X opened")
				Sleep, 300
				return true
				}
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
		;(the game's memory standing in for an arrow the Spiral Map covers: X at a World Gate all the same)
		if (standIn && WkTalk < 3 && IsObject(SpiralMapButton()))
			{
			WalkLog("talk: the Spiral Map opened - it's a World Gate")
			WkArrived := 4, WkGateAt := A_TickCount, WkGateClicks := 0, WkGateX := 1
			return true
			}
		;Arrow visible: give a slow dialogue two Space presses to show up first (not after X on top of the
		;goal opened nothing: it's been waited for)
		if (!WkDialog && WkTalk < 2 && !WkOnTop && !WkStuckTalk)
			{
			PressKey("Space")
			WkTalk += 1
			SetStatus("talking - Space (" WkTalk ")")
			Sleep, %TalkGap%
			return true
			}
		;X by the obstacle near the goal opened nothing: it wasn't the thing (a fence, a wall) - go round it
		;after all, as before (the next stuck tries Unstick; WkStuckNearDone keeps the X to once)
		if (WkStuckTalk && !WkDialog)
			{
			if (A_TickCount - WkTalkAt < 1500)
				{
				Sleep, 100
				return true
				}
			WalkLog("talk: X by the obstacle opened nothing - going round it after all")
			WkArrived := 0, WkStuckTalk := 0, WkBestTime := A_TickCount, WkLastRead := A_TickCount
			return true
			}
		if (WkDialog)
			WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
		StartPush(WkDialog ? "same goal after the dialogue" : "nobody to talk to (no dialogue opened)", dist)
		return true
		}

	;No arrow (and the game's memory not standing in for it, above)
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
		if (WkArrived = 0 && HeldW && !inbattle && A_TickCount - WkSeenAt < HiddenWalkTime / (SpeedNow ? SpeedNow : 1) && !(WkLastDist != "" && WkLastDist <= OnTopDist))
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
			WkArrived := 0, WkSeenAt := 0, WkPushes := 0, WkLastDist := ""
			WkLoadAt := A_TickCount, WkGoneSpaces := 0, WkSpaceAt := 0
			}
		;Right at the goal and the arrow went: on top of it (it isn't drawn there). Backing up and turning would
		;only walk away from the thing: it's arrived - X (talk / use / collect), once per goal
		;(not a loading screen, and in AutoFarmer not a battle starting - the arrow goes then too)
		else if (WkArrived = 0 && !inbattle && !WkOnTopDone && WkLastDist != "" && WkLastDist <= OnTopDist && A_TickCount - WkLastDistAt < 4000 && A_TickCount - WkSeenAt > 700
			&& !WkLoadAt && !WalkLoadingScreen() && (inbattle = "" || WalkSureNoBattle()))
			{
			WkOnTopDone := 1
			WalkLog("arrow gone right at the goal (last distance " WkLastDist ") - on top of it: arrived")
			StartTalk("?")
			if (WkArrived = 2)
				WkOnTop := 1, WkOnTopAt := A_TickCount, WkOnTopBacked := 0
			return true
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
		WkBestDist := "", WkRouteBest := "", WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
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
			;(walked into the way out without an X - the game's memory said so - and nothing loaded: X after
			;all, in case it's something to use, like a World Gate whose prompt didn't read)
			if (WkNavDoor)
				{
				WkNavDoor := 0
				WalkLog("push: the way out didn't load after " Round((A_TickCount - WkPushStart) / 1000, 1) " s - pressing X after all")
				StartTalk(dist = "" ? "?" : dist, false)
				return true
				}
			WkArrived := 1, WkFar := 0, WkArrDist := dist
			WalkLog("push: no loading screen after " Round((A_TickCount - WkPushStart) / 1000, 1) " s (distance " (dist = "" ? "?" : dist) ") - waiting for the next goal")
			SetStatus("arrived" (dist = "" ? "" : " (distance " dist ")") " - waiting for the next goal")
			return true
			}
		if (!WkStraight && ((dist != "" && WalkNear(dist, PushStraightDist, PushUnits)) || (dist = "" && (WkBestDist = "" || WkBestDist <= NearDist))))
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
		;(right after a turn the arrow doesn't show it yet: see TurnSettle. The game's memory does)
		if (!WkStraight && !WkNavUse && A_TickCount - WkTurnAt < WalkSettle())
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
		SetStatus("pushing on " (WkStraight ? "straight" : "- " (WkNavUse ? "heading " : "arrow ") Round(h) " degrees") ", distance " (dist = "" ? "?" : dist) (WkNavUse ? " (game's memory)" : ""))
		Sleep, 50
		return true
		}

	;A teleport on the game's path (the route stops at it - the zone's paths jump from there to far off: a
	;trolley, a hole down to the sewers): walk straight on into it for a second, once (X at its prompt if it
	;asks: WalkPromptWanted), then stand by it - not back and forth over it - while the helper waits for it to
	;take the wizard. One that doesn't in 15 s is given up and the route goes another way: walking on
	if (WkJumpKey != "" && WkNavJump = "" && WkNavRouted && IsObject(WkNavObj) && WkNavObj.ax != "")
		{
		jk := StrSplit(WkJumpKey, ",")
		if (Sqrt((WkNavObj.ax - jk[1]) ** 2 + (WkNavObj.ay - jk[2]) ** 2) > 400)
			WalkLog("teleport at " WkJumpKey ": the route goes another way now - walking on"), WkJumpKey := ""
		}
	;A mob on the way that the route can't go round (a corridor, a doorway - mobavoid): stand still till it
	;moves off - also through a reading missed meanwhile (not a step towards it). The helper gives up after 25 s
	;and routes on past it
	if ((WkNavMob != "" || (!WkNavOk && WkNavMobAt && A_TickCount - WkNavMobAt < 1500)) && WkNavJump = "")
		{
		if (WkMobLogged != WkNavMobName)
			WkMobLogged := WkNavMobName, WalkLog("a mob on the way (" WkNavMobName ") and no way round it - waiting for it to move off")
		if (KeysDown || HeldW)
			ReleaseKeys()
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
		SetStatus("waiting - a mob on the way (" WkNavMobName (WkNavMob != "" ? ", " WkNavMob " s" : "") ")")
		Sleep, 300
		return true
		}
	if (WkNavOk)
		WkMobLogged := "", WkNavMobAt := 0
	if (WkNavJump != "")
		{
		if (WkJumpKey != WkNavJumpAt)
			{
			WkJumpKey := WkNavJumpAt, WkJumpPushUntil := A_TickCount + 1000
			WalkLog("teleport on the game's path at " WkNavJumpAt " - walking on into it (given up if it doesn't take the wizard)")
			}
		if (A_TickCount < WkJumpPushUntil)
			{
			HoldW(1)
			SetStatus("walking on into a teleport on the game's path")
			Sleep, 50
			return true
			}
		if (KeysDown || HeldW)
			ReleaseKeys()
		WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0
		SetStatus("at a teleport - waiting for it to take the wizard (" WkNavJump " s)")
		Sleep, 300
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
			;(waiting on a collect goal it gave up on - it stopped wherever it was: only a new goal moves it on)
			gaveUpWait := IsObject(WkCollect) && WkCollect.gaveUp
			WkFar := (!gaveUpWait && (changed || dist > ArriveDist + (WkPushes >= 2 ? 60 : 5))) ? WkFar + 1 : 0
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
		;(by the game's memory, in game units, when it can be used: the arrow's number means more or less in
		;each zone)
		WkNear := WalkNear(dist, ArriveDist, ArriveUnits) ? WkNear + 1 : 0
		if (WkNear >= 2)
			{
			StartTalk(dist)
			return true
			}
		;Progress = closer than ever before, or a new goal further away
		if (WkBestDist = "" || dist < WkBestDist - 1 || dist > WkBestDist + 50)
			WkBestDist := dist, WkBestTime := A_TickCount, WkTries := 0
		;...or getting on along the route round walls: going round one gets no closer as the crow flies for a
		;while (and for the badly-stuck watch below)
		onRoute := WkNavUse && WkNavRouted && WkNavLeft != ""
		if (onRoute && (WkRouteBest = "" || WkNavLeft < WkRouteBest - 1 || WkNavLeft > WkRouteBest + 50))
			WkRouteBest := WkNavLeft, WkBestTime := A_TickCount, WkTries := 0
		if (onRoute && (WkRouteProg = "" || WkNavLeft < WkRouteProg - 30 || WkNavLeft > WkRouteProg + 300))
			WkRouteProg := WkNavLeft, WkProgAt := A_TickCount
		;Badly stuck: walking on and on without getting any closer to the goal for StuckForever (the clock only
		;runs while it walks here - a gap of over 5 s since it last looked, a battle or a talk, is left out):
		;the Commons, and start over from there
		if (A_TickCount - WkProgStep > 5000)
			WkProgAt += A_TickCount - WkProgStep
		WkProgStep := A_TickCount
		if (WkProgBest = "" || dist < WkProgBest - 30 || dist > WkProgBest + 300)
			WkProgBest := dist, WkProgAt := A_TickCount
		else if (A_TickCount - WkProgAt > StuckForever && WalkCommonsReset("no closer to the goal in " Round(StuckForever / 60000) " minutes of walking", dist))
			return true
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
		;(not on the route round walls: that knows the walls - the ones remembered were met without it)
		if (A_TickCount > WkBiasUntil && WkTries = 0 && !IsObject(WkEsc) && WkMem.Length() && !onRoute)
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
	;it, walking on (or standing) as before. (Steering by the game's memory: it knows the facing at once)
	if (!WkNavUse && A_TickCount - WkTurnAt < WalkSettle())
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
	;(a big turn: on the spot - walking on, it would swing round an arc into walls, round NPCs and the goal. Three in a
	;row with no walking between: this one walking on - WkSpins)
	WkSpins := WkSpins ? WkSpins : 0
	if (Abs(steer) > TurnInPlace && WkSpins < 3)
		{
		WkSpins += 1
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
	;(a small turn: walking on - W stays down while A/D turns the wizard; a big one after three on the spot too)
	HoldW(1)
	if (Abs(steer) > TurnInPlace)
		{
		SetStatus("walking - turning " (steer < 0 ? "left " : "right ") Round(Abs(steer)) " degrees on the move (" WkSpins " turns on the spot in a row)")
		Turn(steer)
		WkBestTime := A_TickCount
		}
	;(sped up, the shortest key press (30 ms) turns more than a small correction: smaller ones are left)
	else if (fine && Abs(steer) > Max(AheadAngle, TurnRate * 30 * (SpeedNow ? SpeedNow : 1)))
		Turn(steer)
	WkSpins := 0
	if (!Walking)
		return false
	SetStatus("walking - " (WkNavUse ? "heading " : "arrow ") Round(h) " degrees, distance " (dist = "" ? "?" : dist) (steer != h ? " (keeping clear of the obstacle)" : "") (fine ? "" : " (talk prompt showing)")
		. (standIn ? " (no arrow on screen - by the game's memory)" : WkNavUse && WkNavRouted ? " (on the route round walls)" : WkNavUse ? " (game's memory)" : ""))
	;Is the wizard actually moving? With W held, the picture moves along. Two looks in a row where it
	;has hardly changed = walking into something, so don't wait the full StuckTime
	still := WalkStill()
	if (still != "")
		WkStill := (still && dist != "") ? WkStill + 1 : 0
	slowStuck := A_TickCount - WkBestTime > StuckTime
	;(not moving: a quest offer's window up holds the wizard still - accepted, not counted as stuck)
	if ((slowStuck || (WkStill >= 2 && A_TickCount - WkBestTime > FastStuckTime)) && WalkAcceptQuest("the wizard isn't moving"))
		return Walking ? true : false
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
		;Stuck right by the goal: the thing itself is in the way (an item on a table, someone behind a
		;counter) - going round it only walks away. It's arrived: X, once per goal
		if (stuckAt != "" && stuckAt <= OnTopDist && !WkStuckNearDone)
			{
			WkStuckNearDone := 1
			WalkLog("stuck " stuckAt " from the goal - the goal itself in the way? Arrived: X")
			StartTalk(stuckAt, false)
			if (WkArrived = 2)
				WkStuckTalk := 1
			return true
			}
		if (WkTries >= UnstickTries)
			{
			;(what the game showed, to see what held it - AutoFarmer: Windows temp, "Wizard101 bot rounds")
			stuckPic := IsFunc("SaveRoundPicture") ? Func("SaveRoundPicture").Call() : ""
			WalkLog("stuck: gave up after " UnstickTries " tries" (stuckPic != "" ? " (the game's picture: " stuckPic ")" : ""))
			if (WalkCommonsReset("couldn't get round an obstacle in " UnstickTries " tries", stuckAt))
				return true
			Walking := 0
			ReleaseKeys()
			SetStatus("stuck - couldn't get around the obstacle. Move the wizard a bit and press F8")
			WalkNotify("stuck", "Stuck", "The wizard couldn't get round an obstacle (" (stuckAt = "" ? "?" : stuckAt) " from the goal) and the teleport to the Commons didn't help (used in the last " Round(ResetEvery / 60000) " minutes, or not possible here), so walking is off. Move it a bit and press F8 to walk again.")
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

;At the goal: stop, press X (talk / use), then WalkStep presses Space through the dialogue. door: at the
;way out of this zone (the game's memory says so) walk on into it instead (not when stuck by the goal)
StartTalk(d, door := true)
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
	;The game's memory says the goal is in another zone: this is the way out of this one (a door, a loading
	;point) - nobody to talk to, walk on into it straight away (no prompt showing: one asking for X gets X)
	if (door && prompt = "" && WkNavOk && WkNavHops > 0)
		{
		WalkLog("talk: at the goal (distance " d ") - the game's memory says it's the way out of this zone (" WkNavHops " zone change" (WkNavHops = 1 ? "" : "s") " to the goal): no X")
		StartPush("the way out of this zone (the game's memory)", d)
		WkNavDoor := WkArrived = 3
		return
		}
	WkArrived := 2, WkTalk := 0, WkFar := 0, WkNear := 0, WkDialog := 0, WkTalkDist := d, WkTalkAt := A_TickCount
	PressKey("x"), WkLastX := A_TickCount
	WalkLog("talk: at the goal (distance " d "), pressed X")
	SetStatus("talking - pressed X at the goal (distance " d ")")
	Sleep, 600
	}

;Walk on into the goal (doorway / loading point), at most twice for the same goal
StartPush(why, d)
	{
	WkNavDoor := 0
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
	WkArrived := 6, WkPressAt := A_TickCount, WkTalk := 0, WkDialog := 0, WkSpaceAt := 0, WkAfterXLooked := 0
	WkArrowAtX := (WkRealSeenAt && A_TickCount - WkRealSeenAt < 1500)
	;(what's on screen before X: what X opens is what's new - WalkCloseAfterX)
	WkPreXText := WalkAfterXText(preLines)
	PressKey("x"), WkLastX := A_TickCount
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
	presses := 0, acc := ""
	Loop, 80
		{
		PressKey("Space"), presses += 1
		Sleep, %SkipGap%
		if (!Walking)
			return false
		;(no NEXT / DONE any more: closed - or its last page is a quest offer, its button ACCEPT)
		if (Mod(A_Index, 4) = 0 && !WalkDialogOpen())
			{
			acc := WalkDialogAccept()
			break
			}
		}
	WalkLog("dialogue: skipped with " presses " Space presses" (IsObject(acc) ? " - its last page a quest offer" : ""))
	SetStatus("dialogue skipped (" presses " Space presses)")
	if (IsObject(acc) && Walking && GameActive())
		{
		WalkLog("quest offer: ACCEPT in the dialogue box - clicking it at " acc.x - GameLeft "," acc.y - GameTop)
		SetStatus("accepting the quest")
		WalkClick(acc.x, acc.y)
		Sleep, 700
		}
	;(a quest-giver's: the quest offer comes up after it - its ACCEPT clicked; looked for again a while: WalkStep)
	Sleep, 300
	if (Walking)
		WalkAcceptQuest("after the dialogue")
	;(a new offer may follow: its own clicks)
	WkDlgEndAt := A_TickCount, WkAcceptLooks := 0, WkAcceptClicks := 0
	WkDialog := 1, WkTalk += presses, WkSpaceAt := A_TickCount
	WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
	WkBestTime := A_TickCount, WkLastRead := A_TickCount
	return true
	}

;A quest offer's ACCEPT button (the window a quest-giver opens after the dialogue - Space doesn't take it, and the
;wizard can't walk while it's up), read by OCR over the middle of the game: {x, y} on the screen, or "" - never in a
;window that says anything about Crowns, or that's a friend / trade / teleport / group request or a duel
WalkAcceptButton()
	{
	;(the middle of the game, then its lower part bigger - a button's coloured letters read better larger)
	;(the second down to the bottom: a dialogue box's own ACCEPT is in its button row there)
	for pass, f in [[0.8, 0.07, 0.86], [0.6, 0.45, 0.55]]
		{
		readW := Round(GameW * f[1]), readH := Round(GameH * f[3])
		t := OcrRect(Round(GameLeft + (GameW - readW) / 2), Round(GameTop + GameH * f[2]), readW, readH, "en", Min(pass = 1 ? 2 : 3, 2500 / readW), acceptLines)
		;(anything about Crowns anywhere: never)
		if (ErrorLevel || !IsObject(acceptLines) || RegExMatch(t, "i)cr[o0]wn"))
			return ""
		;(a button: the word on a short line - ACCEPT and DECLINE side by side can read as one)
		btn := ""
		for each, line in acceptLines
			{
			if (!IsObject(line.words) || line.words.Length() > 3)
				continue
			for each, word in line.words
				if (btn = "" && RegExMatch(word.text, "i)^\W*ACC?E[PF]T\W*$"))
					btn := {x: Round(word.x + word.w / 2), y: Round(word.y + word.h / 2)}
			}
		if (btn = "")
			continue
		;(its window: the lines just above the button and on its row, hugging it - a quest offer says so (DECLINE beside
		;it, or quest / reward / experience / gold words); a friend, trade, teleport or group request never)
		;(in the dialogue box's button row at the bottom - a quest-giver's offer as the dialogue's last page - with no
		;request's words anywhere in what was read)
		offer := (btn.y > GameTop + GameH * 0.85) && !RegExMatch(t, "i)friend request|be your friend|would like to|wants? to (trade|duel|teleport|join)|invit(e|es|ed) you|teleport to|join (my|your|the|a|our) (group|team|party)|party invit")
		for each, line in acceptLines
			{
			cy := line.y + line.h / 2
			if (cy < btn.y - GameH * 0.35 || cy > btn.y + GameH * 0.05 || Abs(line.x + line.w / 2 - btn.x) > GameW * 0.2)
				continue
			if (RegExMatch(line.text, "i)friend request|be your friend|would like to|wants? to (trade|duel|teleport|join)|invit(e|es|ed) you|teleport to|join (my|your|the|a|our) (group|team|party)|party invit"))
				return ""
			if (RegExMatch(line.text, "i)\bDECLINE\b|\bquest\b|\breward|experience|\bXP\b|\bgold\b"))
				offer := true
			}
		if (offer)
			return btn
		;(not an offer it can tell: nothing - the next pass, or the next look)
		continue
		}
	return ""
	}

;The quest offer's ACCEPT clicked if it's up (why: for the log). True if it was
WalkAcceptQuest(why)
	{
	;(this offer clicked twice already in the last 20 s: no more - the stuck / Escape / notice ways carry on)
	if (WkAcceptClicks >= 2 && A_TickCount - WkAcceptAt < 20000)
		return false
	if (A_TickCount - WkAcceptAt >= 20000)
		WkAcceptClicks := 0
	btn := WalkAcceptButton()
	if (!IsObject(btn) || !Walking || !GameActive())
		return false
	if (KeysDown || HeldW)
		ReleaseKeys()
	if (!WkAcceptClicks)
		WkAcceptAt := A_TickCount
	WkAcceptClicks += 1
	WalkLog("quest offer: ACCEPT showing (" why ") - clicking it at " btn.x - GameLeft "," btn.y - GameTop (WkAcceptClicks > 1 ? " (again)" : ""))
	SetStatus("accepting the quest")
	WalkClick(btn.x, btn.y)
	Sleep, 700
	WkBestTime := A_TickCount, WkLastRead := A_TickCount, WkStill := 0
	return true
	}

;The dialogue box's own ACCEPT - a quest-giver's offer as the dialogue's last page (Space doesn't take it, and with no
;NEXT / DONE the box looks closed to WalkDialogOpen): {x, y} on the screen, or "" - never with "Crown" read in the box
;or the offer's window above it
WalkDialogAccept()
	{
	s := ArrowScale().scale
	t := OcrRect(Round(GameLeft + GameW / 2 - 480 * s), Round(GameTop + GameH - 170 * s), Round(960 * s), Round(168 * s), "en", 1, lines)
	;(nor a friend / trade / teleport / group request or a duel - as WalkAcceptButton)
	if (ErrorLevel || !IsObject(lines) || RegExMatch(t, "i)cr[o0]wn")
		|| RegExMatch(t, "i)friend request|be your friend|would like to|wants? to (trade|duel|teleport|join)|invit(e|es|ed) you|teleport to|join (my|your|the|a|our) (group|team|party)|party invit"))
		return ""
	btn := ""
	for i, line in lines
		for j, word in line.words
			if (btn = "" && RegExMatch(word.text, "i)^\W*ACC?E[PF]T\W*$"))
				btn := {x: Round(word.x + word.w / 2), y: Round(word.y + word.h / 2)}
	if (!IsObject(btn))
		return ""
	;(the offer's window above the box - the quest's name, what to do, its rewards: no Crowns there either)
	t := OcrRect(Round(GameLeft + GameW * 0.2), Round(GameTop + GameH * 0.3), Round(GameW * 0.6), Round(GameH * 0.6), "en", 1)
	return (ErrorLevel || RegExMatch(t, "i)cr[o0]wn")) ? "" : btn
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
	HoldFor(Round(1000 / (SpeedNow ? SpeedNow : 1)))
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

;Within the arrow's arrowMax of the goal - or, when the game's memory can be used this step, within units game
;units of it (the arrow's number means more or less in different zones; the memory's distance doesn't)
WalkNear(d, arrowMax, units)
	{
	if (WkNavOk && IsObject(WkNavObj) && WkNavObj.dist != "")
		return WkNavObj.dist <= units
	return d != "" && d <= arrowMax
	}

;Is this "Press X" prompt (key: its name's letters, WkPromptDest) one the quest wants? Its name in the quest's
;goal line ("Talk To Benedict Glendemming in ..." has BENEDICT GLENDEMMING), close to the goal (NearDist on the
;arrow), or collecting (a collect goal - it's how things are picked up). Prompts at others - an NPC or a vendor
;walked past - aren't: X there opens their chatter, an OK box or their shop
WalkPromptWanted(key, d)
	{
	;(and right at a teleport on the game's path: its prompt is the way on)
	if (WkArrived = 7 || WkNavJump != "" || (d != "" && d <= NearDist) || (WkBestDist != "" && WkBestDist <= NearDist))
		return true
	goal := WalkGoalLine()
	if (goal != "" && CollectGoal(goal))
		return true
	g := WalkLetters(goal)
	return (StrLen(key) >= 4 && g != "" && InStr(g, key))
	}

;The quest's goal line under the arrow, read at most every 3 s (the arrow not on screen: where it usually is)
WalkGoalLine()
	{
	if (WkGoalLineAt && A_TickCount - WkGoalLineAt < 3000)
		return WkGoalLine
	WkGoalLineAt := A_TickCount
	text := WalkGoalText()
	if (text = "")
		{
		s := ArrowScale().scale
		px := GameLeft + GameW / 2 - 0.7 * s, py := GameTop + GameH - 220 * s + 81.7 * s
		text := OcrRect(Round(px - 450 * s), Round(py + 28 * s), Round(900 * s), Round(60 * s))
		text := ErrorLevel ? "" : Trim(RegExReplace(text, "\s+", " "))
		}
	WkGoalLine := text
	return text
	}

;What X at a prompt opened, if it's not a dialogue - only what's new since just before X (WkPreXText), in the
;middle of the game where its windows open (not the chat, the prompt or the goal line): a window with a shop's
;words (Buy, Sell, Shop, Crowns...) - closed with Escape, nothing in it clicked (never anything that could
;spend); else a lone OK / Okay button on a line of its own - an OK box - clicked (never with Crowns on screen).
;Escape that opened the game's menu instead closes it again. True if it closed something
WalkCloseAfterX()
	{
	t := WalkAfterXText(lines)
	if (t = "" || !IsObject(lines))
		return false
	if (RegExMatch(t, "i)\b(buy|sell|shop|cr[o0]wns?|purchase|recipes|reagents|treasure cards)\b", m) && !RegExMatch(WkPreXText, "i)\b\Q" m "\E\b"))
		{
		WalkLog("pressed X: a window opened (""" m """ in it - a shop?) - Escape, nothing in it clicked")
		PressKey("Escape")
		Sleep, 800
		WalkCloseGameMenu()
		return true
		}
	;(an OK with Crowns anywhere in sight is never clicked)
	if (RegExMatch(t, "i)cr[o0]wn"))
		return false
	for i, line in lines
		if (IsObject(line.words) && line.words.Length() = 1 && RegExMatch(Trim(line.words[1].text), "i)^(ok|okay)[.!]?$")
			&& !RegExMatch(WkPreXText, "i)\b(ok|okay)\b"))
			{
			w := line.words[1]
			if (!Walking || !GameActive())
				return false
			WalkLog("pressed X: an OK box opened - OK")
			ReleaseKeys()
			;(the mouse back where it was afterwards, in AutoFarmer: mousereturn)
			ownGrab := IsFunc("MouseGrab") ? Func("MouseGrab").Call() : false
			MouseMove, % Round(w.x + w.w / 2), % Round(w.y + w.h / 2), 2
			Sleep, 60
			Click
			Sleep, 500
			if (ownGrab)
				Func("MouseLetGo").Call()
			return true
			}
	return false
	}

;The middle of the game - where a window X opens shows: not the chat (bottom left), the prompt or the goal line
;(bottom), the walker's notice (top right) - read by OCR. "" if it can't be read; its lines (with their words)
WalkAfterXText(ByRef lines)
	{
	lines := ""
	t := OcrRect(Round(GameLeft + GameW * 0.25), Round(GameTop + GameH * 0.12), Round(GameW * 0.5), Round(GameH * 0.58), "en", 1, lines)
	return ErrorLevel ? "" : t
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
	;(the mouse back where it was afterwards, in AutoFarmer: mousereturn)
	ownGrab := IsFunc("MouseGrab") ? Func("MouseGrab").Call() : false
	MouseMove, %x%, %y%, 1
	Sleep, 40
	if (Walking && GameActive())
		Click
	Sleep, 100
	if (ownGrab)
		Func("MouseLetGo").Call()
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
	WalkNotifyClose()
	Walking := !Walking
	if (Walking)
		{
		;(a collect goal given up on gets another go)
		if (IsObject(WkCollect) && WkCollect.gaveUp)
			WkCollect.gaveUp := 0, WkCollect.from := A_TickCount, WkCollect.progressAt := A_TickCount, WkCollect.stepAt := A_TickCount
		;(teleports the helper gave up get another go - you may have done what opens one: NavRead, AutoFarmer)
		WkJumpStuck := 0, WkJumpKey := "", NavUnblock := 1
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

;Holds A (goal to the left) or D (goal to the right) long enough to turn h degrees. Steering by the game's
;memory (its heading agreed with the arrow's): held until the wizard's own facing, re-read as it turns, has
;turned that far (NavTurn) - else for as long as TurnRate says
Turn(h)
	{
	;(a game sped up more than 5 times turns too far in the shortest key press: turns at normal speed)
	if (SpeedNow > 5)
		SpeedSet(0, "a turn")
	if (WkNavUse && NavTurn(h))
		return
	Critical
	if (!Walking || !GameActive())
		{
		Critical, Off
		return
		}
	key := h < 0 ? "a" : "d"
	ms := Round(Abs(h) / (TurnRate * SpeedNow))
	ms := ms < 30 ? 30 : ms > 800 ? 800 : ms
	;(the game's memory readable this step but its heading's sign not checked yet: the wizard's facing before
	;and after this turn checks it - see the end)
	yaw0 := (WkNavOk && !WkNavChecked && IsObject(WkNavObj) && IsFunc("NavRead")) ? WkNavObj.yaw : ""
	KeysDown := 1
	Send, {Blind}{%key% down}
	Critical, Off
	HoldFor(ms)
	Send, {Blind}{%key% up}
	WkTurnAt := A_TickCount
	if (yaw0 != "" && Walking)
		{
		Sleep, 120
		nav := Func("NavRead").Call(120)
		if (IsObject(nav) && nav.yaw != "")
			{
			turned := WkNavSign * ArrowWrap((nav.yaw - yaw0) * 57.29578)
			;(a fair way round: which way round its heading is, is settled - the keys turn the wizard)
			if (Abs(turned) >= 15 && turned * h < 0)
				{
				WkNavSign := -WkNavSign, turned := -turned
				WalkLog("turn: holding " key " turned the wizard " Round(Abs(turned)) " degrees the other way than the game's memory's heading said - turned its sign round")
				}
			if (Abs(turned) >= 15)
				WalkNavConfirm("holding " key " turned the wizard " Round(Abs(turned)) " degrees the way its heading said")
			}
		}
	}

;Back up, turn UnstickTurn degrees to one side and walk along the obstacle for walkMs
Unstick(side, walkMs)
	{
	;(at normal speed - backing up, turning and walking off as measured - and for a few seconds after)
	WkSpeedHold := A_TickCount + walkMs + 4000
	SpeedSet(0, "getting round an obstacle")
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
	HoldFor(Round(ms / SpeedNow))
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
	;(walking: Cheat Engine's speed for it, if that's on)
	if (on && HeldW)
		SpeedWalking()
	}

;{Blind} so an Alt/Ctrl/Shift the user is holding isn't let go. Stopping: the game back to normal speed (Cheat Engine)
ReleaseKeys()
	{
	Send, {Blind}{w up}{a up}{s up}{d up}
	HeldW := 0, KeysDown := 0
	SpeedSet(0, "stopped")
	}

;---- Cheat Engine's speedhack (AutoFarmer's Settings window: speedhack) ----
;Cheat Engine (yours - installed, attached to Wizard101 and its hotkeys set by you) speeds the game up; the bot only
;presses its hotkeys: speedkeyfast (the speed speedfactor) while walking, speedkeynormal (1x) for everything else -
;battles, talking, dialogues, shops, near the goal, getting round an obstacle, when you play, F6, and when it stops.
;F13-F24: no keyboard has them, nothing else uses them

;Whether the speedhack's on (AutoFarmer's speedhack setting; AutoQuester by itself: never)
SpeedOn()
	{
	return SpeedSetting() && SpeedFactor() > 1 && SpeedOff = ""
	}

;The speedhack setting switched on (AutoFarmer's Settings window)
SpeedSetting()
	{
	return IsFunc("Stat") && Func("Stat").Call("speedhack") = 1
	}

;The speed Cheat Engine's walking key sets (speedfactor, 1-50)
SpeedFactor()
	{
	f := IsFunc("Stat") ? Func("Stat").Call("speedfactor") : 1
	return (f + 0 >= 1) ? Min(f + 0, 50) : 1
	}

;Cheat Engine's key for walking (fast) or for 1x: speedkeyfast / speedkeynormal, F13-F24 (1 = F13)
SpeedKey(fast)
	{
	n := IsFunc("Stat") ? Func("Stat").Call(fast ? "speedkeyfast" : "speedkeynormal") : 0
	n := (n + 0 >= 1 && n + 0 <= 12) ? n + 0 : (fast ? 2 : 1)
	return "F" (12 + n)
	}

;The game to walking speed (fast true, the speedhack on) or normal: Cheat Engine's key pressed when that changes.
;force: the 1x key pressed even when it should be at 1x already (a battle round, F6 off, the bot stopping) - a press
;Cheat Engine missed, a speed set by hand - only with the speedhack set up (never a key you didn't give it). The key is
;held 250 ms - Cheat Engine looks at its hotkeys every 100 ms - and two presses are 400 ms apart at least (it takes no
;second press within 350 ms). The speed counts as changed before the key goes, so F6 / F8 / exit meanwhile set it back.
;why: for debug.log
SpeedSet(fast, why := "", force := false)
	{
	want := (fast && SpeedOn()) ? SpeedFactor() : 1
	SpeedNow := SpeedNow ? SpeedNow : 1
	if (want = SpeedNow && !(force && want = 1 && (SpeedSentAt || SpeedSetting())))
		return
	key := SpeedKey(want > 1)
	gap := SpeedSentAt ? 400 - (A_TickCount - SpeedSentAt) : 0
	SpeedNow := want, SpeedSentAt := A_TickCount
	Critical
	if (gap > 0)
		Sleep, %gap%
	Send, {Blind}{%key% down}
	Sleep, 250
	Send, {Blind}{%key% up}
	SpeedSentAt := A_TickCount
	Critical, Off
	WalkLog("speed: " want "x - " key (why != "" ? " (" why ")" : ""))
	}

;Walking: fast - or normal near the goal (no running past an NPC or a door), and for a while after getting round an
;obstacle
SpeedWalking()
	{
	if (!SpeedOn())
		return SpeedSet(0)
	if (A_TickCount < WkSpeedHold)
		return SpeedSet(0, "getting round an obstacle")
	;(a dungeon run, collecting round a spot, a teleport on the game's path walked into - its loading screen - or no
	;distance to the goal known: normal speed)
	if (IsObject(DgRun))
		return SpeedSet(0, "a dungeon run")
	if (WkArrived = 7)
		return SpeedSet(0, "collecting")
	if (WkNavJump != "")
		return SpeedSet(0, "a teleport ahead")
	if (WkLastDist = "" && !(WkNavOk && IsObject(WkNavObj) && WkNavObj.dist != ""))
		return SpeedSet(0, "the distance to the goal unknown")
	;(slowed within SpeedSlowDist / Units, fast again only half as far again past it - not on and off at the line)
	k := (SpeedNow > 1) ? 1 : 1.5
	if (WkLastDist != "" && WalkNear(WkLastDist, SpeedSlowDist * k, SpeedSlowUnits * k))
		return SpeedSet(0, "near the goal")
	SpeedSet(1, "walking")
	}

;How long the camera takes to catch up after a turn, at the game's speed now (TurnSettle at 1x)
WalkSettle()
	{
	return Round(TurnSettle / (SpeedNow ? SpeedNow : 1))
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
	;(the goal it gave up on has changed: the quest moved on - walk on)
	if (IsObject(WkCollect) && WkCollect.gaveUp && !CollectSameGoal(text, WkCollect.text))
		{
		WalkLog("collect: the goal is now '" text "' (was '" WkCollect.text "') - walking on")
		WkCollect := ""
		WalkNotifyClose("collect")
		if (WkArrived = 1)
			WkArrived := 0, WkFar := 0, WkArrDist := "", WkBestDist := "", WkBestTime := A_TickCount, WkTries := 0
		}
	;(a goal it gave up on - no progress for CollectStall, or CollectMax in all - without it changing: leave it be)
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
	WkCollect := {text: text, from: A_TickCount, sureAt: A_TickCount, last: text, gaveUp: 0, battles: 0
		, count: CollectCount(text), progressAt: A_TickCount, stepAt: A_TickCount}
	WalkNotifyClose("collect")
	StartCollect(text, "a goal to collect / defeat things")
	return true
	}

;Stops collecting a goal (no progress / too long): waits where it is (battles still get fought) and
;shows the collect notice. Only the goal line changing (CollectCheck), Keep trying or F8 off and on end it
CollectGiveUp(dist, why)
	{
	WkCollect.gaveUp := 1
	ReleaseKeys()
	WkArrived := 1, WkArrDist := dist, WkFar := 0
	mins := Round(CollectStall / 60000)
	WalkNotify("collect", "Collect quest needs you", "'" WkCollect.text "' - " why ". The bot waits here (battles still get fought) and walks on once the quest moves on.`n`nKeep trying: collect again (" mins " minutes without progress). Stop walking: walking off (F8 turns it back on).", true)
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
	;(time away from collecting - a battle, a prompt - doesn't count as no progress)
	if (A_TickCount - WkCollect.stepAt > 5000)
		WkCollect.progressAt += A_TickCount - WkCollect.stepAt, WkCollect.from += A_TickCount - WkCollect.stepAt
	WkCollect.stepAt := A_TickCount
	;Is it still the same goal? (every 4 s, when the arrow and so its line are showing)
	if (seen && A_TickCount - WkGoalReadAt > 4000)
		{
		WkGoalReadAt := A_TickCount
		text := WalkGoalText()
		if (text != "" && !CollectSameGoal(text, WkCollect.text))
			{
			WalkLog("collect: the goal is now '" text "' (was '" WkCollect.text "') - following the arrow again")
			WkCollect := ""
			WalkNotifyClose("collect")
			ReleaseKeys()
			WalkReset()
			return true
			}
		if (text != "")
			{
			WkCollect.sureAt := A_TickCount
			if (text != WkCollect.last)
				WkCollect.last := text, WalkLog("collect: " text)
			;(progress: the count going up)
			n := CollectCount(text)
			if (n != "" && n != WkCollect.count)
				{
				if (WkCollect.count != "")
					WalkLog("collect: the count is now " n " (was " WkCollect.count ")")
				WkCollect.count := n, WkCollect.progressAt := A_TickCount
				}
			}
		}
	if (A_TickCount - WkCollect.from > CollectMax)
		{
		WalkLog("collect: still '" WkCollect.text "' after " Round(CollectMax / 60000) " minutes - giving up, waiting here")
		CollectGiveUp(dist, Round(CollectMax / 60000) " minutes of collecting and it's still not done")
		return true
		}
	;No progress for CollectStall: an odd one (items it can't find, monsters elsewhere...) - stop, wait here
	;(battles still get fought) and tell you. It carries on once the goal changes, or on Keep trying
	if (seen && A_TickCount - WkCollect.progressAt > CollectStall)
		{
		WalkLog("collect: no progress on '" WkCollect.text "' in " Round(CollectStall / 60000) " minutes - stopping here, telling you")
		CollectGiveUp(dist, "no progress in " Round(CollectStall / 60000) " minutes of roaming and fighting")
		return true
		}
	;Right after a turn the picture is still swinging round: don't steer on it yet
	if (A_TickCount - WkTurnAt < WalkSettle())
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
			HoldW(1)
			if (Abs(ang) > 30)
				Turn(ang)
			else if (Abs(ang) > 6)
				Turn(ang * 0.7)
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
	;Roaming. Too far from the spot: back towards it (the arrow, or the game's memory while it's hidden), then
	;a new square
	if ((seen || WkNavUse) && dist != "" && dist > RoamRadius)
		{
		if (WkRoamLeg)
			WalkLog("collect: " dist " away from the spot - heading back"), WkRoamLeg := 0
		;(a big turn on the spot first, then walking - as on the way to a goal)
		if (Abs(h) > TurnInPlace)
			HoldW(0), Turn(h)
		HoldW(1)
		if (Abs(h) > AheadAngle && Abs(h) <= TurnInPlace)
			Turn(h)
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

;The count in a goal line ("(2 of 5)", "2/5"): the first number, "" if there's none
CollectCount(text)
	{
	;(a number above the total is a misread)
	return (RegExMatch(text, "i)(\d+)\s*(?:of|/)\s*(\d+)", cnt) && cnt1 + 0 <= cnt2 + 0) ? cnt1 + 0 : ""
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

;---- Badly stuck: the Commons, and start over ----

;Teleports to the world's Commons (End) and starts the walk over from there (the quest arrow leads on from
;wherever it lands). At most once every ResetEvery. False if it didn't: too soon, in a battle, or no
;loading screen came within 10 s (a dungeon, say) - or it's badly stuck where it was before (the same zone, the
;goal as far - within MemNear of distance at - and the same quest line, in the last 3 hours): the teleport only
;brings it back there (2026-10-21: Krokotopia's Throne Room, at a wall 35 from the goal, every 10 minutes for half
;an hour), so walking goes off and a notice says so
WalkCommonsReset(why, at := "")
	{
	static spots := []
	if (!ResetTeleport || (WkResetAt && A_TickCount - WkResetAt < ResetEvery) || inbattle || !Walking || !GameActive())
		return false
	zone := WalkZone(true), goal := SubStr(WalkLetters(WalkGoalLine()), 1, 24)
	for i, s in spots
		if (s.zone = zone && zone != "" && at != "" && s.dist != "" && Abs(at - s.dist) <= MemNear && A_TickCount - s.tick < 10800000
			&& (s.goal = "" || goal = "" || s.goal = goal))
			{
			Walking := 0
			ReleaseKeys()
			WalkLog("badly stuck (" why ") where it was at " s.time " too (" zone ", " at " from the goal) - the Commons only brings it back here: walking off")
			SetStatus("stuck at the same place again - walking is off. Walk it past, then press F8")
			WalkNotify("stuck", "Stuck at the same place again", "The wizard got badly stuck where it was at " s.time " too (" zone ", " at " from the goal). Teleporting to the Commons only brings it back here, so walking is off - the way on may be a door or something the bot can't open. Walk it past, then press F8.")
			return false
			}
	spots.Push({zone: zone, dist: at, goal: goal, tick: A_TickCount, time: A_Hour ":" A_Min})
	WkResetAt := A_TickCount
	ReleaseKeys()
	WalkLog("badly stuck (" why ") - teleporting to the Commons (End) to start over")
	SetStatus("badly stuck - teleporting to the Commons to start over")
	t0 := A_TickCount, started := false
	PressKey("End")
	while (A_TickCount - t0 < 40000)
		{
		Sleep, 250
		if (!Walking)
			return false
		WalkZone(true)
		if (WkLoading)
			started := true
		if (!WkLoading && WkLoadedAt > t0 + 500)
			{
			WalkLog("at the Commons (" WalkZone(true) ") - walking on from here")
			TrayTip, Wizard101 bot, % "The wizard was badly stuck (" why ") - it went to the Commons and walks on from there.", 10, 1
			WalkReset()
			WkLoadAt := A_TickCount
			return true
			}
		if (!started && A_TickCount - t0 > 10000)
			break
		}
	WalkLog("the teleport to the Commons didn't happen (no loading screen) - " why)
	return false
	}

;---- Telling you when it needs you ----

;Sure there's no battle on: AutoFarmer saw the spellbook (it only shows out of battle) a moment ago
;(BotNoBattle). AutoQuester can't tell
WalkSureNoBattle()
	{
	return IsFunc("BotNoBattle") ? Func("BotNoBattle").Call() : false
	}

;Wizard101's own menu (Escape opens it when nothing else is open) up: two of its page's labels read (GRAPHICS,
;RESOLUTION, FULLSCREEN, TEXTURE DETAIL, HARDWARE CURSOR, UI SIZE - often read clipped: ESOLUTION, ULLSCREEN...), or
;its buttons QUIT / IDLE / HELP / OK (WalkMenuButtons) - read enlarged, as yellow on red they aren't read at 1:1. Never
;with a disconnect box, a question or Crowns read. okBtn: the screen spot of its OK, if read (wantOk: the buttons
;read for it even with the labels read). seen: what was read (for debug.log)
WalkGameMenuOpen(ByRef okBtn := "", wantOk := false, ByRef seen := "")
	{
	okBtn := "", seen := ""
	;(the middle 70% of the game - the chat's corner mostly left out - enlarged up to twice, to 2500 px across at
	;most, Windows OCR's limit: small labels read better)
	readW := Min(Round(GameW * 0.7), 2500)
	t := OcrRect(Round(GameLeft + (GameW - readW) / 2), Round(GameTop + GameH * 0.1), readW, Round(GameH * 0.8), "en", Min(2, 2500 / readW), menuLines)
	if (ErrorLevel || !IsObject(menuLines))
		return false
	seen := RegExReplace(t, "\s+", " ")
	if (RegExMatch(t, "i)reconnect|disconnect|are you sure|cr[o0]wn"))
		return false
	;(labels: from short lines only - a word or two, not sentences - one label a line)
	labels := {}
	for i, line in menuLines
		{
		if (!IsObject(line.words) || line.words.Length() > 3)
			continue
		flat := RegExReplace(Format("{:L}", line.text), "[^a-z]")
		for k, re in {graphics: "graphic", resolution: "solutio|olution", fullscreen: "lscreen|fullscr", texture: "texture|t[ui]redet"
			, cursor: "cursor|recurs|hardwar", uisize: "uisiz"}
			if (RegExMatch(flat, re))
				{
				labels[k] := 1
				break
				}
		}
	;(its buttons are sometimes read at 1:1 too)
	menuUp := WalkMenuButtons(menuLines, okRead)
	menuUp := menuUp || labels.Count() >= 2
	if (menuUp && (!wantOk || IsObject(okRead)))
		{
		okBtn := okRead
		return true
		}
	;(the buttons: the lower middle of the game, enlarged to 2500 px across at most)
	bandW := Min(Round(GameW * 0.6), 1560)
	b := OcrRect(Round(GameLeft + (GameW - bandW) / 2), Round(GameTop + GameH * 0.5), bandW, Round(GameH * 0.45), "en", Min(2, 2500 / bandW), bandLines)
	if (!ErrorLevel && IsObject(bandLines) && !RegExMatch(b, "i)reconnect|disconnect|are you sure|cr[o0]wn"))
		{
		seen .= " | " RegExReplace(b, "\s+", " ")
		if (WalkMenuButtons(bandLines, bandOk))
			menuUp := true, okRead := IsObject(bandOk) ? bandOk : okRead
		}
	okBtn := menuUp ? okRead : ""
	return menuUp
	}

;The game menu's button row in an OCR read (lines as OcrRect gives them): three or four of QUIT, IDLE, HELP, OK
;(0K, 1DLE... too) side by side at one height - no other word between them - in that order left to right, far apart
;like buttons (a gap of more than a word's height between them): not words of a sentence. okAt: the OK's middle,
;if it's one of them
WalkMenuButtons(lines, ByRef okAt := "")
	{
	okAt := "", allWords := []
	for i, line in lines
		{
		if (!IsObject(line.words))
			continue
		for j, bw in line.words
			{
			word := RegExReplace(Format("{:L}", bw.text), "[^a-z0-9]")
			n := RegExMatch(word, "^[qo0]uit$") ? 1 : RegExMatch(word, "^[il1]dle$") ? 2 : word = "help" ? 3 : RegExMatch(word, "^[o0]k$") ? 4 : 0
			allWords.Push({n: n, x: bw.x, y: bw.y + bw.h / 2, w: bw.w, h: bw.h})
			}
		}
	for i, first in allWords
		{
		if (!first.n)
			continue
		;(every word at this one's height, left to right)
		row := []
		for j, bw in allWords
			if (Abs(bw.y - first.y) <= Max(first.h, 10) * 0.6)
				{
				at := row.Length() + 1
				for k, r in row
					if (bw.x < r.x)
						{
						at := k
						break
						}
				row.InsertAt(at, bw)
				}
		firstAt := 0, lastAt := 0
		for k, r in row
			if (r.n)
				lastAt := k, firstAt := firstAt ? firstAt : k
		runLen := lastAt - firstAt + 1
		if (runLen < 3 || runLen > 4)
			continue
		okRow := true, okSpot := ""
		Loop, % runLen
			{
			r := row[firstAt + A_Index - 1]
			if (!r.n)
				{
				okRow := false
				break
				}
			if (A_Index > 1)
				{
				prev := row[firstAt + A_Index - 2]
				if (r.n <= prev.n || r.x - (prev.x + prev.w) < Max(r.h, 8))
					{
					okRow := false
					break
					}
				}
			if (r.n = 4)
				okSpot := {x: Round(r.x + r.w / 2), y: Round(r.y)}
			}
		if (okRow)
			{
			okAt := okSpot
			return true
			}
		}
	return false
	}

;May the bot press a key or click for the game's menu: Wizard101 in front, walking on (needWalking - not for the
;potion run, which works with walking off) and, in AutoFarmer, its WalkHostOn: the bot on (F6) and no key or mouse
;of yours since from (A_TickCount)
WalkMenuMayAct(needWalking, from := 0)
	{
	if (!GameActive() || (needWalking && !Walking))
		return false
	return IsFunc("WalkHostOn") ? Func("WalkHostOn").Call(from) : true
	}

;Closes Wizard101's menu if it's up (WalkGameMenuOpen): Escape - twice at most - and if it's still there, its OK
;(never Quit), each only while the bot may act (WalkMenuMayAct, checked right before it, from since - or the start
;of this). -1: not looked at (the bot mayn't act), 0: no menu, 1: closed, 2: still up (left to you). seen: what the
;first look read (for debug.log)
WalkCloseGameMenu(needWalking := true, ByRef seen := "", since := 0)
	{
	seen := "", from := since ? since : A_TickCount
	if (!WalkMenuMayAct(needWalking, from))
		return -1
	if (!WalkGameMenuOpen("", false, seen))
		return 0
	Loop, 2
		{
		WalkLog("the game's menu is open (an Escape opened it?) - Escape to close it")
		Critical
		if (!WalkMenuMayAct(needWalking, from))
			{
			Critical, Off
			WalkLog("the game's menu left to you (the bot is off, Wizard101 isn't in front or you've taken over)")
			return 2
			}
		Send, {Blind}{Escape}
		Critical, Off
		Sleep, 800
		;(the second time, its OK looked for too - for a click if Escape won't do)
		if (!WalkGameMenuOpen(menuOk, A_Index = 2))
			return 1
		}
	if (!IsObject(menuOk))
		{
		WalkLog("the game's menu is still open and its OK wasn't read - left to you")
		return 2
		}
	WalkLog("the game's menu is still open - its OK")
	;(the mouse back where it was afterwards, in AutoFarmer: mousereturn)
	ownGrab := IsFunc("MouseGrab") ? Func("MouseGrab").Call() : false
	Critical
	clicked := WalkMenuMayAct(needWalking, from)
	if (clicked)
		Click, % menuOk.x " " menuOk.y
	Critical, Off
	Sleep, 100
	if (ownGrab)
		Func("MouseLetGo").Call()
	if (!clicked)
		{
		WalkLog("the game's menu left to you (the bot is off, Wizard101 isn't in front or you've taken over)")
		return 2
		}
	Sleep, 700
	return WalkGameMenuOpen() ? 2 : 1
	}

;Escape, once: for a window an X of the bot's opened that Space doesn't close (a shop, say). If that opened
;the game's own menu instead (nothing else was open), it's closed again (WalkCloseGameMenu)
WalkEscape()
	{
	if (KeysDown || HeldW)
		ReleaseKeys()
	WalkLog("no arrow for " Round((A_TickCount - WkNoArrowFrom) / 1000) " s since an X of the bot's - Escape, in case that opened a window Space doesn't close (a shop?)")
	PressKey("Escape")
	Sleep, 1200
	WalkCloseGameMenu()
	}

;A notice for you: a small window on top (it doesn't take the focus from the game) with a sound, plus a
;tray tip and a line in the log. One at a time; the same kind isn't shown twice till it's sorted
;(WalkNotifyClose). withKeep: Keep trying / Stop walking buttons too (a collect goal)
WalkNotify(kind, title, text, withKeep := false)
	{
	if (WkNoteKind = kind)
		return
	;(one at a time: one up for something as or more important stays - two causes can't take turns)
	if (WkNoteKind != "" && WalkNoteRank(WkNoteKind) >= WalkNoteRank(kind))
		return
	WalkNotifyClose()
	WkNoteKind := kind, WkNoteTitle := title, WkNoteShown := 0, WkNoteOff := 0
	WalkLog("NEEDS YOU - " title ": " text)
	;(and to Discord, if alerts are set up: AutoFarmer's Alerts.ahk)
	if (IsFunc("AlertSend"))
		Func("AlertSend").Call("walk-" kind, title, text)
	;(+E0x08000000: clicking it never takes the focus from the game)
	Gui, WkNote:New, +AlwaysOnTop +ToolWindow +E0x08000000 +HwndWkNoteHwnd, Wizard101 bot needs you
	Gui, WkNote:Margin, 14, 12
	Gui, WkNote:Font, s11 w700, Segoe UI
	Gui, WkNote:Add, Text, w400, %title%
	Gui, WkNote:Font, s9 w400, Segoe UI
	Gui, WkNote:Add, Text, w400 y+6, %text%
	if (withKeep)
		{
		Gui, WkNote:Add, Button, gWalkNoteKeep w120 y+12, Keep trying
		Gui, WkNote:Add, Button, gWalkNoteStop w120 x+8, Stop walking
		Gui, WkNote:Add, Button, gWalkNoteOk w80 x+8, OK
		}
	else
		Gui, WkNote:Add, Button, gWalkNoteOk w80 y+12, OK
	if (!inbattle)
		WalkNoteShow()
	SoundPlay, *48
	TrayTip, Wizard101 bot needs you, % title ": " SubStr(text, 1, 200), 10, 2
	}

;How important a notice is: stuck > collect > no arrow > waiting at a goal
WalkNoteRank(kind)
	{
	return (kind = "stuck" || kind = "shop") ? 4 : kind = "collect" ? 3 : kind = "arrow" ? 2 : 1
	}

;The notice's title-bar X: the same as OK
WkNoteGuiClose(args*)
	{
	WalkNoteOk()
	}

;Shows the notice (see WalkNotePlace), without taking the focus from the game
WalkNoteShow()
	{
	if (WkNoteKind = "" || WkNoteOff)
		return
	Gui, WkNote:Show, Hide AutoSize
	dhw := A_DetectHiddenWindows
	DetectHiddenWindows, On
	WinGetPos, , , noteW, noteH, ahk_id %WkNoteHwnd%
	DetectHiddenWindows, %dhw%
	at := WalkNotePlace(noteW, noteH)
	noteX := at[1], noteY := at[2]
	Gui, WkNote:Show, x%noteX% y%noteY% NoActivate
	WkNoteShown := 1
	}

;Where the notice goes: on a monitor the game isn't on; else beside the game window if there's room; else
;the top middle of the game (clear of the arrow, prompts, dialogues and globes - and it hides in a battle,
;whose name plates are up there)
WalkNotePlace(noteW, noteH)
	{
	gx := GameLeft + GameW // 2, gy := GameTop + GameH // 2
	SysGet, monCount, MonitorCount
	Loop, %monCount%
		{
		SysGet, wa, MonitorWorkArea, %A_Index%
		if (gx >= waLeft && gx < waRight && gy >= waTop && gy < waBottom)
			continue
		return [waRight - noteW - 20, waTop + 20]
		}
	Loop, %monCount%
		{
		SysGet, wa, MonitorWorkArea, %A_Index%
		if (gx >= waLeft && gx < waRight && gy >= waTop && gy < waBottom)
			break
		}
	if (waRight - (GameLeft + GameW) >= noteW + 16)
		return [GameLeft + GameW + 8, Max(waTop, GameTop)]
	if (GameLeft - waLeft >= noteW + 16)
		return [GameLeft - noteW - 8, Max(waTop, GameTop)]
	return [gx - noteW // 2, Max(waTop, GameTop) + 4]
	}

WalkNoteHide()
	{
	if (WkNoteShown)
		Gui, WkNote:Hide
	WkNoteShown := 0
	}

;The notice is sorted (kind: only that kind; "": whatever is up) - gone
WalkNotifyClose(kind := "")
	{
	if (WkNoteKind = "" || (kind != "" && WkNoteKind != kind))
		return
	WalkLog("notice '" WkNoteTitle "' closed")
	Gui, WkNote:Destroy
	WkNoteKind := "", WkNoteTitle := "", WkNoteShown := 0, WkNoteOff := 0
	}

;The notice's buttons. OK: put away (not shown again till it's sorted). Keep trying: collect again for
;CollectStall. Stop walking: walking off. Each gives the game the focus back
WalkNoteOk(args*)
	{
	Gui, WkNote:Hide
	WkNoteShown := 0, WkNoteOff := 1
	WalkGameFocus()
	}

WalkNoteKeep(args*)
	{
	if (IsObject(WkCollect))
		{
		WkCollect.gaveUp := 0, WkCollect.from := A_TickCount, WkCollect.progressAt := A_TickCount, WkCollect.stepAt := A_TickCount
		WalkNotifyClose()
		StartCollect(WkCollect.text, "you said keep trying")
		}
	else
		WalkNotifyClose()
	WalkGameFocus()
	}

WalkNoteStop(args*)
	{
	WalkNotifyClose()
	if (Walking)
		WalkToggle()
	WalkGameFocus()
	}

WalkGameFocus()
	{
	WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
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
		&& nowMs - WkSnapAt <= 1500 && WkSnapAt > WkTurnAt + WalkSettle() && WkSnapAt > WkWalkFrom + 200)
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

;---- The game's memory: a better source for the same decisions ----
;
;In AutoFarmer, NavRead (Vision.ahk) asks the vision helper where the wizard is (x, y and its facing, yaw)
;and where the quest arrow points (the node on the game's own path it points at, the distance along that
;path, the zone changes to go), read straight out of the game's memory - READ-ONLY: nothing in the game is
;written, no keys or clicks (navmem:0 in PlayerStats.txt switches it off). The walker uses it for the
;decisions it makes anyway:
;  - heading: from the wizard's facing to where the arrow points (+ = right, like ReadArrow's). Which way
;    round the game's world is isn't known for sure, so it's only used once it's been checked: NavAgreeNeed
;    fair readings agree with the arrow on screen (mirror images and its sign is turned round), or a turn
;    went the way it said - then kept (resources\nav_calibration.txt, checked:1) and used from the start
;  - distance: the memory's / how it compares with the number printed on the arrow (worked out from fair
;    readings for each zone - it differs - kept in resources\nav_calibration.txt) - instead of the OCR'd
;    number, which misses lone digits
;  - no arrow on screen (scenery hides it, or a see-through arrow on a floor its own colour can't be picked
;    out): the memory stands in for it (WalkNavStandIn), not back up and turn to find it, or wait
;  - turns: until the wizard's facing has turned that far (NavTurn), not TurnRate's guess
;  - the goal in another zone (hops > 0): this is the way out - walk on into it, no X (StartTalk)
;Anything wrong with it (no answer, an ERR, the quest helper off, a zone that isn't the one in the game's log,
;nothing to steer at): the arrow on screen, at once - logged when it comes and goes ("the game's memory ...")

;This step's reading of the game's memory (see above). Sets WkNavOk (usable), WkNavH, WkNavD ("" until it's
;known how its distance compares with the arrow's), WkNavHops and WkNavUse (its heading is steered by).
;hScr, dScr: the arrow's heading and distance off the screen this step, to check the memory's against - ""
;when they aren't fair to (the arrow hidden or pushed up, a poor match; the heading also right after a turn,
;the camera still swinging round)
WalkNav(hScr, dScr)
	{
	static navGoalKey := "", escSaid := ""
	WkNavOk := 0, WkNavUse := 0, WkNavH := "", WkNavD := "", WkNavHops := "", WkNavRouted := 0, WkNavLeft := ""
	WkNavJump := "", WkNavJumpAt := "", WkNavMob := ""
	;(AutoQuester on its own has no vision helper. In a battle there's nothing to steer, and the battle
	;shouldn't wait for it)
	if (!IsFunc("NavRead") || inbattle)
		return
	;(the route kept away from mobs - mobavoid, on unless it's 0 - but not while collecting: walking into them is
	;the point. A collect goal left over - finished in a battle - doesn't count once the goal line has moved on. The
	;quest's goal line goes along, read only if the ask is sent: the mobs it names aren't avoided)
	avoidMobs := NavRoute && !(IsObject(Stats) && Stats.HasKey("mobavoid") && !Stats["mobavoid"]) && WkArrived != 7
	if (avoidMobs && IsObject(WkCollect) && !WkCollect.gaveUp && CollectSameGoal(WalkGoalLine(), WkCollect.text))
		avoidMobs := false
	nav := Func("NavRead").Call(150, false, NavRoute, avoidMobs, Func("WalkGoalLine"))
	why := WalkNavProblem(nav)
	if (why = "")
		{
		WkNavOk := 1, WkNavObj := nav, WkNavHops := nav.hops
		;(a new goal - another zone, quest goal or zone changes to go: "getting on" along the route, and the
		;badly-stuck watch, start over from it)
		goalKey := nav.zone "|" nav.goalid "|" nav.hops
		if (goalKey != navGoalKey)
			navGoalKey := goalKey, WkRouteBest := "", WkRouteProg := "", WkProgBest := "", WkJumpKey := "", WkJumpStuck := 0
		WkNavH := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.tx, nav.ty)
		;(checked against the arrow on screen by where it points, not by the route)
		hTarget := WkNavH
		;The route round walls (the helper's plan over the zone's map): steer at its aim - a point ahead on it,
		;in sight - instead of straight at where the arrow points; how far is left along it
		if (NavRoute && nav.ax != "" && nav.ay != "")
			{
			hAim := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.ax, nav.ay)
			if (hAim != "")
				WkNavH := hAim, WkNavRouted := 1
			;(right at a teleport on the game's path: the route stops there - see the teleport step in WalkStep;
			;also when its aim is the wizard's own spot, the free spot by a teleport inside its object)
			if (nav.jump != "" && nav.jx != "")
				WkNavJump := nav.jump, WkNavJumpAt := Round(nav.jx) "," Round(nav.jy)
			;(a mob on the way it can't go round: see the mob step in WalkStep)
			if (nav.mob != "")
				WkNavMob := nav.mob, WkNavMobName := nav.mobname != "" ? nav.mobname : "a mob", WkNavMobAt := A_TickCount
			;(inside a mob's ring or sight: the aim leads out of it - said once each time)
			if (nav.escape != "" && nav.escape != escSaid)
				WalkLog("inside " nav.escape "'s reach or sight - getting out of it (the way out nearest the quest's way), not waiting there")
			escSaid := nav.escape
			}
		;How fast the wizard is moving (game units per ms): the number on screen and the memory's are read a
		;moment apart (up to ~150 ms with the OCR), so a pair only says how the two compare when that moment's
		;walking is small next to the distance. (Lone digits misread: 20 or more only)
		navSpeed := ""
		if (IsObject(WkNavPrev) && A_TickCount - WkNavPrev.at < 1500 && A_TickCount > WkNavPrev.at)
			navSpeed := Sqrt((nav.x - WkNavPrev.x) ** 2 + (nav.y - WkNavPrev.y) ** 2) / (A_TickCount - WkNavPrev.at)
		WkNavPrev := {x: nav.x, y: nav.y, at: A_TickCount}
		;(how the arrow's distance compares with the memory's differs from zone to zone - 41 in one, about 100
		;in Pigswick Academy: each zone's own once worked out there)
		if (nav.zone != WkNavScaleZone)
			WalkNavZoneScale(nav.zone)
		if (dScr != "" && dScr >= 20 && nav.dist > 0 && navSpeed != "" && navSpeed * 150 <= nav.dist * 0.04)
			WalkNavLearnScale(nav.dist / dScr, nav.hops)
		if (nav.dist != "" && WkNavScale > 0 && WkNavScaleBad < 2)
			WkNavD := Round(nav.dist / WkNavScale)
		if (WkNavRouted && nav.left != "" && WkNavScale > 0 && WkNavScaleBad < 2)
			WkNavLeft := nav.left / WkNavScale
		if (hScr != "" && hTarget != "")
			WalkNavVote(hScr, hTarget)
		WkNavUse := WkNavTrusted && WkNavH != ""
		}
	WalkNavSay(why, nav)
	WalkNavRouteSay(why = "" ? nav : "")
	;(no way on but teleports that don't take the wizard - the helper gave them up: WalkStep stops walking)
	if (why = "" && InStr(nav.routewhy, "teleport that doesn't take the wizard") && !WkJumpStuck)
		WkJumpStuck := 1
	}

;Logs the route round walls coming and going: once each way (a moment with none while it plans isn't a change)
WalkNavRouteSay(nav)
	{
	if (!NavRoute || !IsObject(nav))
		return
	if (WkNavRouted && WkRouteState != "on")
		WalkLog("the route round walls (the zone's map): steering along it" (WkNavLeft != "" ? " - " Round(WkNavLeft) " to go" : ""))
	else if (!WkNavRouted && WkRouteState = "on" && nav.routewhy != "planning")
		WalkLog("no route round walls (" (nav.routewhy = "" ? "?" : nav.routewhy) ") - steering at where the arrow points")
	else if (!WkNavRouted && WkRouteState = "" && nav.routewhy != "" && nav.routewhy != "planning")
		WalkLog("no route round walls (" nav.routewhy ") - steering at where the arrow points")
	if (WkNavRouted)
		WkRouteState := "on"
	else if (nav.routewhy != "planning")
		WkRouteState := "off"
	}

;Why this reading of the game's memory can't be used ("" it can)
WalkNavProblem(nav)
	{
	if (!IsObject(nav))
		return InStr(NavWhy, "navmem:0") ? "is switched off (" NavWhy ")" : "can't be read (" (NavWhy != "" ? NavWhy : "no answer") ")"
	if (nav.x = "" || nav.y = "" || nav.yaw = "")
		return "can't say where the wizard is (loading?)"
	if (nav.enabled = "")
		return "can't say if the game's quest helper is on"
	if (!nav.enabled)
		return "says the game's quest helper is off (no quest tracked?)"
	if (nav.tx = "" || nav.ty = "")
		return "can't say where the arrow points (the quest catching up after a zone change?)"
	if (nav.zone = "")
		return "can't say which zone it is"
	;(the game's log is looked at every few seconds: after a zone change, look again before calling it wrong)
	logZone := WalkZone()
	if (logZone != "" && !WalkSameZone(logZone, nav.zone))
		{
		logZone := WalkZone(true)
		if (logZone != "" && !WalkSameZone(logZone, nav.zone))
			return "says the zone is " nav.zone ", the game's log " logZone
		}
	return ""
	}

WalkSameZone(a, b)
	{
	return StrReplace(a, "\", "/") = StrReplace(b, "\", "/")
	}

;Degrees from where the wizard faces (yaw: forward = (-sin yaw, -cos yaw), z up) to (tx, ty), + = to the
;right like ReadArrow's - if the game's world is right-handed; WkNavSign turns it round when the arrow on
;screen says otherwise. "" if the target is right where the wizard is
WalkNavHeading(x, y, yaw, tx, ty)
	{
	dx := tx - x, dy := ty - y
	if (dx * dx + dy * dy < 4)
		return ""
	;(the yaw a wizard facing the target would have, less the one it has)
	return WkNavSign * ArrowWrap((ArrowAtan2(-dx, -dy) - yaw) * 57.29578)
	}

;Checks the memory's heading against the arrow's on screen. NavAgreeNeed readings that agree (the same side,
;within 35 degrees) and it's steered by; that many mirror images in a row (the other side) and its sign is
;turned round; five that match neither while it's trusted and it isn't till they agree again. Only clear
;readings count: 20-160 degrees off straight ahead both (near 0 or 180 a few degrees decide the side)
WalkNavVote(hScr, hMem)
	{
	if (Abs(hScr) < 20 || Abs(hScr) > 160 || Abs(hMem) < 20 || Abs(hMem) > 160)
		return
	if (hScr * hMem > 0 && Abs(ArrowWrap(hScr - hMem)) <= 35)
		{
		WkNavAgree += 1, WkNavMirror := 0, WkNavOdd := 0
		if ((!WkNavTrusted || !WkNavChecked) && WkNavAgree >= NavAgreeNeed)
			WalkNavConfirm("its heading agrees with the arrow's (" WkNavAgree " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees)")
		}
	else if (hScr * hMem < 0 && Abs(ArrowWrap(hScr + hMem)) <= 35)
		{
		WkNavMirror += 1, WkNavAgree := 0, WkNavOdd := 0
		;(its sign checked - the wizard's own facing turned with the keys the way it said, or the arrow agreed:
		;it's the game's, the same everywhere. An arrow that reads as its mirror image is misread there - a dais,
		;a carpet, the camera's angle - and isn't followed; turns go on checking the sign: NavTurn turns it round
		;if one ever goes the other way)
		if (WkNavMirror >= NavAgreeNeed && WkNavChecked)
			{
			WkNavMirror := 0
			if (A_TickCount - WkNavMirrorSaid > 60000)
				{
				WkNavMirrorSaid := A_TickCount
				WalkLog("the arrow reads as the game's memory's mirror image (" NavAgreeNeed " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees) - the arrow misread here? Keeping the memory's heading (checked by turning)")
				}
			}
		else if (WkNavMirror >= NavAgreeNeed)
			{
			WkNavSign := -WkNavSign, WkNavMirror := 0, WkNavTrusted := 0
			WalkLog("the game's memory: its heading is the arrow's mirror image (" NavAgreeNeed " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees) - turned it round, checking again")
			WalkNavUncheck()
			}
		}
	else
		{
		WkNavOdd += 1
		if (WkNavOdd >= 5 && WkNavTrusted)
			{
			WkNavTrusted := 0, WkNavAgree := 0
			WalkLog("the game's memory: its heading doesn't match the arrow's (" WkNavOdd " readings, the last: arrow " Round(hScr) ", memory " Round(hMem) " degrees) - following the arrow till they agree again")
			}
		}
	}

;One reading of how the memory's distance compares with the number on the arrow (game units per arrow unit).
;The last nine are kept; once five are within 12% of their middle one, that's it (kept in the file; the
;memory's distance is used from then on). Two in a row 25% off the one in use and it isn't used till it's
;worked out again
WalkNavLearnScale(ratio, hops)
	{
	WkNavScales.Push(ratio)
	if (WkNavScales.Length() > 9)
		WkNavScales.RemoveAt(1)
	if (WkNavScale > 0)
		{
		if (Abs(ratio / WkNavScale - 1) <= 0.25)
			WkNavScaleBad := 0
		;(only a guess borrowed from other zones: this zone's own readings so far, till it's worked out)
		else if (++WkNavScaleBad >= 2 && !WkNavZScales.HasKey(WkNavScaleZone))
			{
			WkNavScale := WalkMedian(WkNavScales), WkNavScaleBad := 0
			WalkLog("the game's memory: other zones' distance scale doesn't fit " WkNavScaleZone " - " Round(WkNavScale, 2) " from its readings so far, till it's worked out")
			}
		else if (WkNavScaleBad = 2)
			WalkLog("the game's memory: its distance doesn't match the arrow's any more (" Round(ratio, 2) " game units per arrow unit, not " Round(WkNavScale, 2) ") - the OCR'd number till it's worked out again")
		}
	if (WkNavScales.Length() < 5)
		return
	mid := WalkMedian(WkNavScales), close := 0
	for i, r in WkNavScales
		if (Abs(r / mid - 1) <= 0.12)
			close += 1
	own := WkNavZScales.HasKey(WkNavScaleZone)
	if (close < 5 || (own && Abs(mid / WkNavScale - 1) <= 0.03))
		return
	was := WkNavScale
	WkNavScale := mid, WkNavScaleBad := 0, WkNavZScales[WkNavScaleZone] := mid
	WkNavScaleAll := WalkNavMiddleScale()
	WalkLog("the game's memory: in " WkNavScaleZone " the arrow's distance is its distance / " Round(mid, 2) " (" close " readings agree" (hops = "" ? "" : ", " hops " zone changes to go") (was = "" ? "" : "; " (own ? "it was " : "other zones' ") Round(was, 2)) ") - its distance used from now on, not the OCR'd number")
	WalkNavSave()
	}

;The middle value of a list of numbers
WalkMedian(list)
	{
	sorted := []
	for i, v in list
		{
		at := 1
		while (at <= sorted.Length() && sorted[at] < v)
			at++
		sorted.InsertAt(at, v)
		}
	n := sorted.Length()
	return Mod(n, 2) ? sorted[(n + 1) // 2] : (sorted[n // 2] + sorted[n // 2 + 1]) / 2
	}

;Logs the game's memory coming and going: once each way, not every step
WalkNavSay(why, nav)
	{
	state := why = "" ? "on" : "off"
	if (state = WkNavState)
		return
	if (state = "on")
		WalkLog("the game's memory (read-only) can be used: " nav.zone (nav.hops = "" ? "" : nav.hops > 0 ? ", the goal " nav.hops " zone change" (nav.hops = 1 ? "" : "s") " away" : ", the goal in this zone")
			. " - " (WkNavTrusted ? "steering by it" : "steering by it once its heading agrees with the arrow's")
			. (WkNavScale > 0 ? "" : "; its distance once it's known how it compares with the arrow's"))
	else
		WalkLog("the game's memory " why " - following the on-screen arrow")
	WkNavState := state
	}

;Holds A (h < 0) or D until the wizard's facing, re-read from the game's memory as it turns, has turned h
;degrees (+ = right): within NavTurnTol - let go a little early for the bit it turns on after the key is up
;- at most NavTurnCap ms; it doesn't turn back if it went past. The memory lost on the way: the rest by TurnRate, like
;Turn. Turned the other way than the memory's heading said: its sign was wrong - turned round, and checked
;against the arrow again. Not turning at all (the keys not taken: a window open?): let go - twice in a row and
;its heading isn't trusted till it agrees with the arrow again. False if the facing can't be read to start
;with (Turn then turns by TurnRate)
NavTurn(h)
	{
	static stillTurns := 0
	if (!IsFunc("NavRead") || Abs(h) < 1)
		return false
	first := Func("NavRead").Call(120)
	if (!IsObject(first) || first.yaw = "")
		return false
	Critical
	if (!Walking || !GameActive())
		{
		Critical, Off
		return true
		}
	key := h < 0 ? "a" : "d"
	KeysDown := 1
	Send, {Blind}{%key% down}
	Critical, Off
	downAt := A_TickCount, lookAt := A_TickCount, prevYaw := first.yaw, turned := 0, looks := 0, ending := ""
	capMs := Round(Abs(h) / (TurnRate * SpeedNow) * 1.6) + 300
	capMs := capMs > NavTurnCap ? NavTurnCap : capMs
	loop
		{
		Sleep, 10
		if (!Walking)
			{
			ending := "walking off"
			break
			}
		if (!GameActive())
			{
			ReleaseKeys(), Refocus := 1, ending := "focus lost"
			break
			}
		lookMs := A_TickCount - lookAt, lookAt := A_TickCount
		nav := Func("NavRead").Call(120)
		took := A_TickCount - downAt
		if (!IsObject(nav) || nav.yaw = "")
			{
			;(the rest by TurnRate, as Turn would)
			rest := Round((Abs(h) - Abs(turned)) / (TurnRate * SpeedNow))
			if (rest > 0 && turned * h >= 0)
				HoldFor(rest > 800 ? 800 : rest)
			ending := "the memory lost"
			break
			}
		looks += 1
		turned += WkNavSign * ArrowWrap((nav.yaw - prevYaw) * 57.29578), prevYaw := nav.yaw
		left := h - turned
		;Let go now or after one more look, whichever lands nearer (within NavTurnTol): it turns on a little
		;after the key comes up, and this look is a moment old (coast: that much more, at the rate so far)
		rate := (took > 60 && Abs(turned) > 1) ? Abs(turned) / took : TurnRate * SpeedNow
		coast := rate * (lookMs / 2 + 16), shortNow := Abs(left) - coast
		if (left * h <= 0 || shortNow <= 0 || (shortNow <= NavTurnTol && shortNow <= Abs(shortNow - rate * lookMs)))
			break
		if (turned * h < 0 && Abs(turned) > 10)
			{
			ending := "wrong way"
			break
			}
		if (took > 500 && Abs(turned) < 2)
			{
			ending := "not turning"
			break
			}
		if (took > capMs)
			{
			ending := "time limit"
			break
			}
		}
	Send, {Blind}{%key% up}
	WkTurnAt := A_TickCount
	took := A_TickCount - downAt
	stillTurns := ending = "not turning" ? stillTurns + 1 : 0
	;(not turning: Wizard101's own menu may be up - keys don't reach the wizard then; closed, and tried again)
	if (ending = "not turning")
		HoldW(0), SpeedSet(0, "the game's menu up?")
	if (ending = "not turning" && WalkCloseGameMenu() = 1)
		stillTurns := 0
	;(the speed checked by how fast the wizard turned: Cheat Engine not attached (the game restarted), the key not taking
	;('Disable when released' ticked) - off for this run; sped up while it should be at 1x - its 1x key again)
	if (ending = "" && took > 150 && Abs(turned) > 20 && IsFunc("SpeedSet"))
		{
		ratio := (Abs(turned) / took) / TurnRate
		if (SpeedNow > 1 && ratio < SpeedNow * 0.55)
			{
			SpeedMiss += 1
			if (SpeedMiss >= 2 && SpeedOff = "")
				{
				SpeedOff := "the wizard turned at " Round(ratio, 1) "x, not " SpeedNow "x - is Cheat Engine attached to this Wizard101, its walking key set, 'Disable when released' unticked?"
				WalkLog("speed: off for this run - " SpeedOff)
				SpeedSet(0, "not sped up", true)
				}
			}
		else if (SpeedNow = 1 && ratio > 1.6 && SpeedSentAt && A_TickCount - SpeedSentAt > 10000)
			SpeedSet(0, "the wizard turned at " Round(ratio, 1) "x - the 1x key again", true)
		else
			SpeedMiss := 0
		}
	if (ending = "wrong way")
		{
		WkNavSign := -WkNavSign, WkNavTrusted := 0, WkNavAgree := 0, WkNavMirror := 0, WkNavOdd := 0
		WalkLog("memory turn: holding " key " turned the wizard " Round(Abs(turned)) " degrees the other way than the game's memory said - turned its sign round, checking it again")
		WalkNavUncheck()
		}
	else if (ending = "not turning" && stillTurns >= 2)
		{
		WkNavTrusted := 0, WkNavAgree := 0
		WalkLog("memory turn: the wizard's facing didn't change with " key " held, twice - not steering by the game's memory till it agrees with the arrow again")
		}
	else if (!WkNavTurns || (ending != "" && ending != "walking off" && ending != "focus lost" && A_TickCount - WkNavTurnLog > 60000))
		{
		if (ending != "")
			WkNavTurnLog := A_TickCount
		WalkLog("memory turn" (WkNavTurns ? "" : " (the first)") ": " Round(h) " degrees asked, " Round(turned) " turned in " took " ms, " looks " looks at the game's memory" (ending = "" ? "" : " - stopped: " ending))
		}
	;(turned a fair way, the way its heading said: which way round that is, is right)
	if (ending != "wrong way" && ending != "not turning" && turned * h > 0 && Abs(turned) >= 15 && !WkNavChecked)
		WalkNavConfirm("holding " key " turned the wizard " Round(Abs(turned)) " degrees the way its heading said")
	WkNavTurns += 1
	return true
	}

;The memory's heading is right way round (the arrow agreed, or a turn went the way it said): steered by from now
;on, and kept in resources\nav_calibration.txt (checked:1), so the next run steers by it from the start
WalkNavConfirm(how)
	{
	was := WkNavTrusted
	WkNavTrusted := 1, WkNavAgree := NavAgreeNeed, WkNavMirror := 0, WkNavOdd := 0
	if (!was)
		WalkLog("the game's memory: " how " - steering by it")
	if (!WkNavChecked || WkNavSign != WkNavSignSaved)
		WkNavChecked := 1, WalkNavSave()
	}

;Its sign was turned round: not checked any more (in the file too) till the arrow or a turn checks it again
WalkNavUncheck()
	{
	if (WkNavChecked)
		WkNavChecked := 0, WalkNavSave()
	}

;No arrow on screen: can the game's memory stand in for it? Its heading in use and its distance known, no
;battle (AutoFarmer saw the spellbook a moment ago), no loading screen (the game's log) and not the first
;moment after one. Its heading not checked yet (WkNavTrusted): a turn checks it - towards the goal when that's
;well off to one side, else 45 degrees right (walking turns back) - when the arrow's been gone a moment, no
;dialogue's open and it's walking (not at a goal), at most once every 10 s (straight away again after one that
;turned its sign round); NavTurn trusts it if the wizard turned the way it said. True if it stands in, -1 if it turned to check
WalkNavStandIn()
	{
	static checkAt := 0, checkSign := 0
	if (!WkNavOk || WkNavH = "" || WkNavD = "" || inbattle || !WalkSureNoBattle())
		return false
	WalkZone(true)
	if (WkLoading || (WkLoadedAt && A_TickCount - WkLoadedAt < 1500))
		return false
	if (WkNavTrusted)
		return WkNavUse
	;(its sign is checked - distrusted for not matching the arrow, or the keys not being taken: a turn can't
	;settle that - the arrow agreeing again, or the next zone)
	if (WkNavChecked)
		return false
	;(just turned round by the last check: the next one straight away, to confirm it)
	if (WkArrived != 0 || (WkSeenAt && A_TickCount - WkSeenAt < 1500) || A_TickCount - checkAt < (WkNavSign != checkSign ? 1500 : 10000) || WalkDialogOpen())
		return false
	checkAt := A_TickCount, checkSign := WkNavSign
	turnBy := Abs(WkNavH) >= 25 ? WkNavH : 45
	WalkLog("no arrow on screen, and the game's memory's heading isn't checked yet - turning " Round(turnBy) " degrees to check it (it's right if the wizard turns the way it says)")
	if (KeysDown || HeldW)
		ReleaseKeys()
	if (!NavTurn(turnBy))
		{
		WalkLog("the game's memory: the wizard's facing can't be read - no check")
		return false
		}
	return -1
	}

;The arrow's distance per game unit for this zone: its own once worked out there, else the middle of the same
;world's zones (it seems to go by world: Wysteria's about 100, Wizard City's about 41), else of all of them (or
;the one kept from before zones were told apart); readings start over
WalkNavZoneScale(zone)
	{
	WkNavScaleZone := zone, WkNavScales := [], WkNavScaleBad := 0
	WkNavScale := WkNavZScales.HasKey(zone) ? WkNavZScales[zone] : WalkNavMiddleScale(StrSplit(zone, "/")[1])
	;(nothing worked out anywhere yet - a new install: a first guess, Wizard City's; two fair readings that
	;disagree put this zone's own in its place, WalkNavLearnScale)
	if (WkNavScale = "")
		WkNavScale := 41
	;(a heading that's checked but was distrusted in the last zone - not matching the arrow, the keys not taken:
	;another go here, as a fresh run would)
	if (WkNavChecked && !WkNavTrusted)
		WkNavTrusted := 1, WkNavAgree := NavAgreeNeed, WkNavOdd := 0
	}

;The middle of the zones' distance per game unit: those in world (the zone's first part, e.g. "Wysteria") if
;any are known, else all of them; the one kept from before zones were told apart if none
WalkNavMiddleScale(world := "")
	{
	vals := [], inWorld := []
	for zoneName, sc in WkNavZScales
		{
		vals.Push(sc)
		if (world != "" && StrSplit(zoneName, "/")[1] = world)
			inWorld.Push(sc)
		}
	return inWorld.Length() ? WalkMedian(inWorld) : vals.Length() ? WalkMedian(vals) : WkNavScaleAll
	}

;What was learned about the game's memory, from resources\nav_calibration.txt: WkNavSign (which way round its
;heading is - a first guess till it's checked; once it has been, it's steered by from the start) and the arrow's
;distance per game unit, for each zone and all of them (WkNavScale is the one in use)
WalkNavLoad()
	{
	WkNavSign := 1, WkNavChecked := 0, WkNavZScales := {}, WkNavScaleAll := "", WkNavScaleZone := ""
	dir := AqDir()
	WkNavFile := dir "\resources\nav_calibration.txt"
	Loop, Read, %WkNavFile%
		{
		if (RegExMatch(A_LoopReadLine, "^\s*sign\s*:\s*(-?1)\s*(;.*)?$", m))
			WkNavSign := m1 + 0
		else if (RegExMatch(A_LoopReadLine, "^\s*checked\s*:\s*([01])\s*(;.*)?$", m))
			WkNavChecked := m1 + 0
		else if (RegExMatch(A_LoopReadLine, "^\s*scale\s*:\s*(\d+(?:\.\d+)?)\s*(;.*)?$", m) && m1 > 0)
			WkNavScaleAll := m1 + 0
		else if (RegExMatch(A_LoopReadLine, "^\s*zone\s*:\s*(.+?)\s*\|\s*(\d+(?:\.\d+)?)\s*$", m) && m2 > 0)
			WkNavZScales[m1] := m2 + 0
		}
	WkNavScale := WkNavScaleAll
	WkNavSignSaved := WkNavSign
	if (WkNavChecked)
		WkNavTrusted := 1, WkNavAgree := NavAgreeNeed
	}

WalkNavSave()
	{
	text := "; What Walker.ahk has learned about the game's memory (read-only). Delete this file to make it learn again.`n"
		. "; scale: the game's distance per unit of the distance printed on the quest arrow (the middle of the zones')`n"
		. "; sign: 1 or -1, which way round the memory's heading is compared with the arrow's`n"
		. "; checked: 1 once the sign has been checked (the arrow agreed, or a turn went the way it said)`n"
		. "; zone: a zone's own scale (zone|scale) - it differs from zone to zone`n"
		. (WkNavScaleAll > 0 ? "scale:" Round(WkNavScaleAll, 4) "`n" : "")
		. "sign:" WkNavSign "`n"
		. "checked:" (WkNavChecked ? 1 : 0) "`n"
	for zone, sc in WkNavZScales
		text .= "zone:" zone "|" Round(sc, 4) "`n"
	FileDelete, %WkNavFile%.tmp
	FileAppend, %text%, %WkNavFile%.tmp
	FileMove, %WkNavFile%.tmp, %WkNavFile%, 1
	WkNavSignSaved := WkNavSign
	}

;OnExit handler: never leave a movement key held down - nor the game sped up
WalkerQuit(reason, code)
	{
	ReleaseKeys()
	SpeedSet(0, "the bot stops", true)
	return 0
	}
