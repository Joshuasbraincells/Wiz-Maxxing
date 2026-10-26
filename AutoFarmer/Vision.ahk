; Vision.ahk - asks the Python vision helper (vision\vision.py) which cards are in the hand and whose
; school badge is on a name plate. AHK v1.1, functions only; #Included by Autofarmer.ahk.
;
; The helper matches every card picture at every position with a distance (how far its colours are
; from the screen's), so the best match wins instead of ImageSearch's found / not found at a fixed
; tolerance. It's started with AutoFarmer (pythonw, no window), answers on 127.0.0.1:47128, and stops
; when AutoFarmer does. Whenever it can't be asked (Python missing, not started, an error three times
; in a row), Find / Tri / FindEnchant / BestBadge use ImageSearch as before. debug.log: "Vision: ...";
; the helper's own log: vision\vision.log.
;
; Needs from the including script: GameLeft/GameTop/GameW/GameH, ScreenX/ScreenY, UiScale, HandHalf,
; Px(), hitschool, DebugLog(), Stat() (KillCalc.ahk).
;
; NavRead (at the bottom) asks the helper where the wizard is and where the quest arrow points, read from the
; game's memory - for the walker (Walker.ahk). Only ever read: see "The game's memory" below.

global VisionOn := 0, VisionPid := 0, VisionFails := 0, VisionCards := "", VisionCardsAt := 0, VisionCardsKey := "", VisionMissing := ","
;The helper's folder ("" = vision\ next to the script) and port (tests use another one, so they don't stop
;the bot's own helper); why the last VisionGet got nothing
global VisionDir := "", VisionPort := 47128, VisionErr
;Why the last VisionPlate read nothing
global VisionPlateWhy
;Why the last VisionCards (the hand from the game's memory) got nothing; its last answer kept, its why and when
global VisionCardsWhy, VisionMemLast, VisionMemAt, VisionMemWhy
;How many fresh looks at the hand VisionFind has taken (CardLearn.ahk LearnBoostPicFix: one miss a look) - declared only:
;a top-level := never runs here
global VisionLookN

;Starts the helper (after stopping one left over from before) and waits up to 8 s for it to answer
VisionStart()
	{
	VisionOn := 0
	;(a global's starting value in an #Included file never runs: set here)
	if (!VisionPort)
		VisionPort := 47128
	if (VisionMissing = "")
		VisionMissing := ","
	VisionGet("/quit", 300)
	Sleep, 300
	py := VisionPython()
	if (py = "")
		{
		DebugLog("Vision: no Python found (pythonw.exe) - cards are found with ImageSearch")
		return false
		}
	dir := VisionDir != "" ? VisionDir : A_ScriptDir "\vision"
	if (!FileExist(dir "\vision.py"))
		{
		DebugLog("Vision: " dir "\vision.py isn't there - cards are found with ImageSearch")
		return false
		}
	Run, % """" py """ """ dir "\vision.py"" --parent " DllCall("GetCurrentProcessId") " --port " VisionPort, %dir%, Hide UseErrorLevel, VisionPid
	if (ErrorLevel)
		{
		DebugLog("Vision: couldn't start " py " - cards are found with ImageSearch")
		return false
		}
	startedAt := A_TickCount
	while (A_TickCount - startedAt < 8000)
		{
		Sleep, 400
		if (SubStr(VisionGet("/ping", 500), 1, 2) = "OK")
			{
			VisionOn := 1, VisionFails := 0
			DebugLog("Vision: helper running (" py ", pid " VisionPid ")")
			return true
			}
		;(it stopped: no point waiting)
		Process, Exist, %VisionPid%
		if (!ErrorLevel)
			break
		}
	DebugLog("Vision: the helper didn't answer - cards are found with ImageSearch (see vision\vision.log)")
	;(don't leave it running, holding the port)
	if (VisionPid)
		Process, Close, %VisionPid%
	VisionPid := 0
	return false
	}

;Stops the helper (on exit)
VisionStop()
	{
	if (VisionPid)
		VisionGet("/quit", 300)
	}

;pythonw.exe to run the helper with: the one next to python.exe on the PATH, else the usual install folders
VisionPython()
	{
	EnvGet, pathVar, PATH
	Loop, Parse, pathVar, `;
		{
		dir := Trim(A_LoopField)
		if (dir != "" && !InStr(dir, "WindowsApps") && FileExist(dir "\pythonw.exe"))
			return dir "\pythonw.exe"
		}
	Loop, Files, %A_AppData%\..\Local\Programs\Python\Python3*, D
		if (FileExist(A_LoopFileFullPath "\pythonw.exe"))
			return A_LoopFileFullPath "\pythonw.exe"
	return ""
	}

;One request to the helper. Returns its answer, "" if it couldn't be asked (3 of those in a row and
;the helper is left alone - ImageSearch from then on; VisionErr says why). noCount: an ERR or no answer
;doesn't count towards that (/nav: the game not running is no reason to stop asking about cards)
VisionGet(path, timeoutMs := 1500, noCount := false)
	{
	VisionErr := ""
	;(the helper's gone: no point asking - a closed port costs 2 s)
	if (VisionOn && VisionPid)
		{
		Process, Exist, %VisionPid%
		if (!ErrorLevel)
			{
			VisionOn := 0, VisionErr := "the helper has stopped"
			DebugLog("Vision: the helper has stopped - cards are found with ImageSearch from now on")
			return ""
			}
		}
	try
		{
		;(sent without waiting, then polled: a waiting Send ignores the time limit and freezes the bot 2-5 s)
		req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "http://127.0.0.1:" (VisionPort ? VisionPort : 47128) path, true)
		req.Send()
		sentAt := A_TickCount
		while (!req.WaitForResponse(0))
			{
			if (A_TickCount - sentAt > timeoutMs)
				{
				req.Abort()
				;(a timeout counts double: the second one turns the helper off)
				if (!noCount)
					VisionFails++
				throw "no answer in " timeoutMs " ms"
				}
			Sleep, 10
			}
		text := req.ResponseText
		if (req.Status != 200 || SubStr(text, 1, 3) = "ERR")
			throw text
		if (!noCount)
			VisionFails := 0
		return text = "" ? " " : text
		}
	catch e
		{
		VisionErr := Trim(IsObject(e) ? e.Message : e, " `t`r`n")
		if (VisionOn && !noCount && ++VisionFails >= 3)
			{
			VisionOn := 0
			DebugLog("Vision: the helper stopped answering (" (IsObject(e) ? e.Message : e) ") - cards are found with ImageSearch from now on")
			}
		return ""
		}
	}

;The card pictures the bot looks for, as "dir/name"
VisionPicList()
	{
	list := ""
	for each, name in ["hit1", "hit2", "hit3", "hit4", "blade", "trap", "aura", "bubble", "convert", "wand", "heal1", "heal2"]
		list .= hitschool "/" name ","
	;(and the other schools' blades and traps the planned hit wants this battle - KillCalc.ahk BoostSearch)
	Loop, Parse, BoostExtra, `,
		if (A_LoopField != "" && A_LoopField != hitschool && A_LoopField != "balance")
			list .= A_LoopField "/blade," A_LoopField "/trap,"
	for each, name in ["sharpen", "potent", "blade3", "blade4", "trap3", "trap4", "tower", "absorb", "reshuffle", "feint", "epic", "colossal", "gargantuan", "monstrous", "giant", "strong", "elementalblade", "elementaltrap", "spiritblade", "spirittrap"]
		list .= "resources/" name ","
	return list "life/enchant"
	}

;Where the card dir\title is in the hand: X, Y = the picture's top left (like ImageSearch). 1 found,
;0 not there, -1 the helper can't be asked (use ImageSearch). One look at the hand serves all the
;questions of the next 0.4 s (FindCards asks about every card in one go)
VisionFind(dir, title, ByRef X, ByRef Y)
	{
	if (!VisionOn || hitschool = "")
		return -1
	key := hitschool "|" BoostExtra "|" UiScale "|" ScreenX "|" ScreenY
	if (!IsObject(VisionCards) || A_TickCount - VisionCardsAt > 400 || key != VisionCardsKey)
		{
		answer := VisionGet("/cards?x1=" Round(ScreenX - HandHalf) "&y1=" Round(ScreenY - Px(75)) "&x2=" Round(ScreenX + HandHalf) "&y2=" Round(ScreenY + Px(150)) "&scale=" Round(UiScale, 3) "&pics=" VisionPicList())
		if (answer = "")
			return -1
		VisionCards := [], VisionCardsAt := A_TickCount, VisionCardsKey := key, VisionMissing := ",", VisionLookN := (VisionLookN ? VisionLookN : 0) + 1
		Loop, Parse, answer, `n, `r
			{
			p := StrSplit(A_LoopField, "|")
			if (p.Length() = 4)
				VisionCards.Push({pic: p[1], x: p[2] + 0, y: p[3] + 0, d: p[4] + 0})
			else if (p[1] = "missing")
				VisionMissing .= p[2] ","
			}
		}
	want := StrReplace(dir, "\", "/") "/" title
	;(a picture the helper wasn't asked about, or couldn't look for: ImageSearch's job)
	if (!InStr("," VisionPicList() ",", "," want ",") || InStr(VisionMissing, "," want ","))
		return -1
	for i, c in VisionCards
		if (c.pic = want)
			{
			X := c.x, Y := c.y
			return 1
			}
	return 0
	}

;Forget the last look at the hand (it's changed: a card was cast or discarded)
VisionForget()
	{
	VisionCardsAt := 0, VisionMemAt := 0
	}

;---- The cards in hand from the game's memory (vision\handmem.py) ----
;
;The helper's /cards without a rectangle reads the hand straight out of the game's memory, READ-ONLY as /nav (nothing in
;the game is written, injected or hooked; no key, click or window): each card's name, school, kind, pips (X pips),
;numbers, whether it's a treasure / item card and its enchantment, and your pips of each kind - only in a battle's
;planning phase, once the hand's settled (the cards on screen are exactly your hand). navmem:0 in PlayerStats.txt
;switches it off too (VisionCardsWhy, VisionMemLast... at the top)

;The hand from the game's memory, as an object - "" when there's none (VisionCardsWhy says why: navmem:0, the helper not
;running or an older one, not in a battle's planning phase, a card chosen, the hand still changing after waitMs...):
;  me     {health, max, generic, power, balance, death, fire, ice, life, myth, storm, shadow (your pips of each kind -
;         "" not read), school (yours, lower case; "" not known), ok (1: every pip count read)}
;  cards  left to right as on screen: [{slot (Card1-7, PetCard), name (the spell's own), display (the name on the card),
;         school (lower case), type (the game's: Damage, AOE, Charm, Ward, Jinx...), pips ("" unknown), xpip (1: X pips),
;         shadow, castable (1 / 0 - an estimate, the normal mode - "" unknown), tc, item, ench (its enchantment's name,
;         "" none), acc, value (as /cards writes it: "255-285", "45/pip", "35%", "+175", "" none), num (value's first
;         number, "" none), kind (vision\handmem.py KINDS - damage aoe heal ward absorb blade trap aura negaura bubble
;         weakness curse charm enchant sharpen potent enchantother mutate dot stun dispel prism clear polymorph shadow
;         minion pips manipulation keep), dot (damage over time besides, "" none), schoolpips ("fire:1"), enchfx, valueench, tid (the
;         template id), text (about as the card says it), heads (a damage card's damage by school, every head of it:
;         "fire:230,ice:230,storm:230" - KillCalc.ahk HeadsParse), boosts (what a blade, trap or aura boosts by school:
;         "ice:35,storm:35,fire:35", "all:25" - BoostsParse; either "?" not to be trusted, "" none or an older helper), nf
;         (the line's fields: 23 an older helper's, with no heads or boosts)}]
;  ms     how long the read took in the helper
;While the game says the hand is changing (dealing, laying the cards out) it's asked again every 100 ms, up to waitMs.
;maxAgeMs: the last answer (or its why) if it's no older than that - the hand doesn't change till a card's cast or
;discarded (VisionForget forgets it)
VisionCards(waitMs := 1500, maxAgeMs := 0)
	{
	;(when the last wait for a settled hand ran out: for 10 s after, asked once with no retries - the 1.5 s wait was paid
	;two to six times a round)
	static vcGaveUp := 0
	if (maxAgeMs > 0 && VisionMemAt && A_TickCount - VisionMemAt <= maxAgeMs)
		{
		VisionCardsWhy := VisionMemWhy
		return VisionMemLast
		}
	VisionCardsWhy := "", VisionMemLast := "", VisionMemAt := 0, VisionMemWhy := ""
	if (!Stat("navmem"))
		{
		VisionCardsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		VisionCardsWhy := "the vision helper isn't running"
		return ""
		}
	;(two clients - dual mode: the memory read is one client's, maybe not the one played)
	if (dualmode == 1)
		{
		VisionCardsWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (vcGaveUp && A_TickCount - vcGaveUp < 10000)
		waitMs := 0
	vcFrom := A_TickCount
	Loop
		{
		;(an older helper - /cards wants a rectangle there - answers ERR: never counted against the helper)
		vcAns := Trim(VisionGet("/cards", 800, true), " `t`r`n")
		if (vcAns = "")
			{
			VisionCardsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
			return VisionCardsKeep("")
			}
		if (SubStr(vcAns, 1, 5) != "none|")
			break
		VisionCardsWhy := SubStr(vcAns, 6)
		if (VisionCardsWhy != "hand changing" || A_TickCount - vcFrom >= waitMs)
			{
			if (VisionCardsWhy = "hand changing" && waitMs > 0)
				vcGaveUp := A_TickCount
			return VisionCardsKeep("")
			}
		Sleep, 100
		}
	vcOut := {me: "", cards: [], ms: ""}
	Loop, Parse, vcAns, `n, `r
		{
		vcF := StrSplit(A_LoopField, "|")
		if (vcF[1] = "me" && vcF.Length() >= 14)
			{
			vcMe := {health: NavNum(vcF[2]), max: NavNum(vcF[3]), school: Format("{:L}", Trim(vcF[14])), ok: 1}
			for vcI, vcKey in ["generic", "power", "balance", "death", "fire", "ice", "life", "myth", "storm", "shadow"]
				{
				vcMe[vcKey] := NavNum(vcF[vcI + 3])
				if (vcMe[vcKey] = "")
					vcMe.ok := 0
				}
			vcOut.me := vcMe
			}
		else if (vcF[1] = "card" && vcF.Length() >= 17)
			{
			vcCard := {slot: vcF[2], x: NavNum(vcF[3]), name: vcF[4], display: vcF[5], school: Format("{:L}", vcF[6]), type: vcF[7]
				, pips: NavNum(vcF[8]), xpip: vcF[9] = 1, shadow: NavNum(vcF[10]), castable: vcF[11], tc: vcF[12] = 1, item: vcF[13] = 1
				, ench: vcF[14], acc: NavNum(vcF[15]), value: vcF[16], kind: vcF[17], dot: NavNum(vcF[18]), schoolpips: vcF[19]
				, enchfx: vcF[20], valueench: vcF[21], tid: vcF[22], text: vcF[23], heads: vcF[24], boosts: vcF[25], nf: vcF.Length()}
			vcCard.num := RegExMatch(vcCard.value, "\d+", vcNum) ? vcNum + 0 : ""
			vcOut.cards.Push(vcCard)
			}
		else if (vcF[1] = "hand")
			vcOut.ms := vcF[3]
		}
	vcGaveUp := 0
	if (!IsObject(vcOut.me))
		{
		VisionCardsWhy := "an odd answer: " SubStr(RegExReplace(vcAns, "\s+", " "), 1, 60)
		return VisionCardsKeep("")
		}
	;(the wizard on screen another school than the game's memory's: another client's - not used)
	if (vcOut.me.school != "" && school != "" && IsFunc("BadgeNumber") && Func("BadgeNumber").Call(school) && Format("{:L}", school) != vcOut.me.school)
		{
		VisionCardsWhy := "another client's wizard (the game's memory: " vcOut.me.school ", the plate: " school ")"
		return VisionCardsKeep("")
		}
	return VisionCardsKeep(vcOut)
	}

;VisionCards' answer kept, with its why, for its maxAgeMs
VisionCardsKeep(vckOut)
	{
	VisionMemLast := vckOut, VisionMemWhy := VisionCardsWhy, VisionMemAt := A_TickCount
	return vckOut
	}

;Whose school badge is in the rectangle, by the helper: the school ("" none clearly), its top left in
;bx, by; -1 if the helper can't be asked or the best spot is unclear (two schools too close). With
;several plates (a team battle), the badge nearest nearX, nearY (0: the best match)
VisionBadge(x1, y1, x2, y2, ByRef bx, ByRef by, nearX := 0, nearY := 0)
	{
	if (!VisionOn)
		return -1
	answer := VisionGet("/badge?x1=" Round(x1) "&y1=" Round(y1) "&x2=" Round(x2) "&y2=" Round(y2) "&scale=" Round(UiScale, 3) "&schools=storm,fire,myth,balance,ice,life,death")
	if (answer = "" || InStr(answer, "unclear"))
		return -1
	sch := "", bestFar := ""
	Loop, Parse, answer, `n, `r
		{
		p := StrSplit(A_LoopField, "|")
		if (p.Length() != 4)
			continue
		far := (nearX || nearY) ? (p[2] - nearX) ** 2 + (p[3] - nearY) ** 2 : A_Index
		if (bestFar = "" || far < bestFar)
			sch := p[1], bx := p[2] + 0, by := p[3] + 0, bestFar := far
		}
	return sch
	}

;A name plate's red health numbers in the rectangle, read by the helper by their shape (its /plate - Windows' OCR
;misses them more often than not at 1440p): {cur, max, worst} (worst: the least like its cut picture of the glyphs,
;0-0.3), or "" - why in VisionPlateWhy
VisionPlate(x1, y1, x2, y2)
	{
	VisionPlateWhy := ""
	if (!VisionOn)
		{
		VisionPlateWhy := "the vision helper isn't running"
		return ""
		}
	answer := VisionGet("/plate?x1=" Round(x1) "&y1=" Round(y1) "&x2=" Round(x2) "&y2=" Round(y2), 1500)
	if (RegExMatch(answer, "^health\|(\d+)\|(\d+)\|([\d.]+)", m) && m2 > 0)
		return {cur: m1 + 0, max: m2 + 0, worst: m3 + 0}
	VisionPlateWhy := answer = "" ? (VisionErr = "" ? "no answer" : VisionErr) : RegExReplace(Trim(answer, " `r`n"), "^none\|")
	return ""
	}

;---- The game's memory: where the wizard is and where the quest arrow points (for Walker.ahk) ----
;
;The helper's /nav reads them straight out of the game's memory, READ-ONLY: the game is opened for reading
;only - nothing in it is ever written, nothing is injected or hooked, no keys are sent and its window isn't
;touched. navmem:0 in PlayerStats.txt switches it off (the walker then only reads the arrow off the screen).
;Why the last NavRead got nothing; when it may ask again, and how long it waited last time
global NavWhy, NavWaitUntil, NavWait
;Set by the walker's F8 (walking on): the next NavRead asks the helper to forget the teleports it gave up
global NavUnblock
;Why the last NavGoal got nothing; when it may ask again
global NavGoalWhy, NavGoalWaitUntil
;Why the last NavMobs / NavBattle got nothing; when each may ask again
global NavMobsWhy, NavMobsWaitUntil, NavBattleWhy, NavBattleWaitUntil
;Why the last NavBag / NavGui got nothing; when each may ask again (declared only: a top-level := never runs here)
global NavBagWhy, NavBagWaitUntil, NavGuiWhy, NavGuiWaitUntil
;Why the last NavItems got nothing; when it may ask again
global NavItemsWhy, NavItemsWaitUntil
;Why the last NavUiScale got nothing; when it may ask again; the GUI root's width it read (GUI units)
global NavUiWhy, NavUiWaitUntil, NavUiRootW

;The wizard and the quest goal from the game's memory, as an object:
;  ok        1
;  zone      the zone, e.g. WizardCity/WC_Ravenwood (as the game's log names it)
;  x, y, z   the wizard (z is up), yaw its facing in radians: forward = (-sin yaw, -cos yaw)
;  tx, ty, tz  where the quest arrow points (a node on the game's own path to the goal)
;  gx, gy, gz  the goal (hops 0), or the way out of this zone to take (hops = zone changes to go)
;  dist      the arrow's distance along the game's path (game units, not the number printed on the arrow)
;  enabled   1 while the game's quest helper is on; questid, goalid the quest and goal (as text)
;  path      (withPath only) the game's path, [{x, y, z}, ...] in order
;  ax, ay    (withRoute only) where to steer: a point ahead on the route the helper planned round the walls
;            over the zone's map (vision\navroute.py); "" when it has none yet - routewhy says why
;  left      (withRoute only) how far is left to walk along that route and the game's path on from it (game units)
;  jump, jx, jy  (withRoute only) right at a teleport on the game's path (the route stops at it): the seconds
;            waited there, and where it is; "" otherwise
;  goaltext, goaltype, goalstatus, goalcount, goaltotal, goalshown  the quest's goal line from the game's memory and its
;            kind, status, count, total, on screen (1/0) - as NavGoal's; "" when it can't be read (or an older helper)
;  noplace   1: the game shows no way to the goal - no arrow (its goal reads exactly 0, 0, 0 and the arrow's distance -1:
;            "Use Inactive Protector in District of the Stars (0 of 3)" - gx..dist are "" then and an arrow seen on the
;            screen is a phantom); 0: the goal has a place; "" not known (another zone, the quest helper off, a goal
;            change caught midway, an older helper). noplaceheld: seconds the 1 has held for this quest and goal (a
;            number - 3.000000: compare it as one), "" unless noplace is 1 - act on it once it has held (2 s, and the
;            same goalid two readings running: a goal change or a zone arrival can read 1 for a moment)
;A value that couldn't be read for sure is "". Returns "" when it can't be asked: navmem:0, the helper not
;running, an ERR (the game not running, at the login screen...) or no answer within timeoutMs - NavWhy says
;why, and after an ERR it isn't asked again for 1 s, doubling to 30 s while it keeps failing (no answer:
;1-4 s; the helper may be busy finding its way into a game it hasn't read yet)
;avoidMobs (with withRoute): the route kept out of what the zone's mobs see (mobshape, mobradius) - but not those named in
;goalLine, the quest's goal line (or a function giving it: called only if the ask is sent), nor one by the quest's
;goal (the helper decides)
NavRead(timeoutMs := 150, withPath := false, withRoute := false, avoidMobs := false, goalLine := "")
	{
	if (!Stat("navmem"))
		{
		NavWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavWhy := "the vision helper isn't running"
		return ""
		}
	if (A_TickCount < NavWaitUntil)
		return ""
	unblock := (withRoute && NavUnblock) ? "&unblock=1" : ""
	if (withRoute && avoidMobs)
		{
		goalNow := IsObject(goalLine) ? goalLine.Call() : goalLine
		unblock .= NavMobArgs() "&goal=" NavUri(SubStr(goalNow, 1, 160))
		}
	;(the wizard's turning circle: the helper looks round its arc to the aim - walls on it or not)
	arcAsk := (withRoute && IsFunc("WalkTurnRadius")) ? "&arcr=" Func("WalkTurnRadius").Call() : ""
	answer := VisionGet("/nav?path=" (withPath ? 1 : 0) "&route=" (withRoute ? 1 : 0) unblock arcAsk, timeoutMs, true)
	if (InStr(unblock, "&unblock=1") && answer != "")
		NavUnblock := 0
	if (answer = "")
		{
		NavWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavWait := NavWait >= 1000 ? Min(NavWait * 2, InStr(VisionErr, "no answer") ? 4000 : 30000) : 1000
		NavWaitUntil := A_TickCount + NavWait
		return ""
		}
	nav := {ok: "", zone: "", x: "", y: "", z: "", yaw: "", tx: "", ty: "", tz: "", gx: "", gy: "", gz: ""
		, hops: "", dist: "", enabled: "", questid: "", goalid: "", ax: "", ay: "", left: "", routewhy: "", jump: "", jx: "", jy: ""
		, mob: "", mx: "", my: "", mobname: "", escape: "", blindahead: "", blindback: "", blindin: "", arc: ""
		, goaltext: "", goaltype: "", goalstatus: "", goalcount: "", goaltotal: "", goalshown: "", noplace: "", noplaceheld: ""}
	Loop, Parse, answer, `n, `r
		{
		navLine := A_LoopField
		f := StrSplit(navLine, "|")
		if (f[1] = "ok")
			nav.ok := NavNum(f[2])
		else if (f[1] = "zone")
			nav.zone := Trim(SubStr(navLine, 6))
		else if (f[1] = "pos")
			nav.x := NavNum(f[2]), nav.y := NavNum(f[3]), nav.z := NavNum(f[4]), nav.yaw := NavNum(f[5])
		else if (f[1] = "target")
			nav.tx := NavNum(f[2]), nav.ty := NavNum(f[3]), nav.tz := NavNum(f[4])
		else if (f[1] = "goal")
			nav.gx := NavNum(f[2]), nav.gy := NavNum(f[3]), nav.gz := NavNum(f[4]), nav.hops := NavNum(f[5])
		else if (f[1] = "dist")
			nav.dist := NavNum(f[2])
		else if (f[1] = "quest")
			nav.enabled := NavNum(f[2]), nav.questid := Trim(f[3]), nav.goalid := Trim(f[4])
		else if (f[1] = "route" && withRoute)
			{
			nav.ax := NavNum(f[2]), nav.ay := NavNum(f[3]), nav.left := NavNum(f[4]), nav.jump := NavNum(f[5]), nav.jx := NavNum(f[6]), nav.jy := NavNum(f[7])
			;(8-11: a mob on the way the route can't go round - seconds waited for it, where it is, its name)
			nav.mob := NavNum(f[8]), nav.mx := NavNum(f[9]), nav.my := NavNum(f[10]), nav.mobname := Trim(f[11])
			;(12: inside a mob's ring or sight - its name: the aim leads out of it; 13: turning walking on round to the
			;aim - 1 its arc's clear of the walls, 0 not, "" not known)
			nav.escape := Trim(f[12]), nav.arc := f.Length() >= 13 ? Trim(f[13]) : ""
			}
		;(the mob whose ring or sight the arrow's straight way comes into, and backing up would - moves off the route)
		else if (f[1] = "blind" && withRoute)
			nav.blindahead := Trim(f[2]), nav.blindback := Trim(f[3]), nav.blindin := Trim(f[4])
		else if (f[1] = "routewhy" && withRoute)
			nav.routewhy := Trim(SubStr(navLine, 10))
		;(no place: the game shows no way to the goal - 1, a place 0, "" not known; how long the 1 has held, s - an older
		;helper sends no such line)
		else if (f[1] = "noplace")
			nav.noplace := NavNum(f[2]), nav.noplaceheld := NavNum(f[3])
		;(the quest's goal line from the game's memory - the helper's last line; an older one has none)
		else if (f[1] = "goalline")
			nav.goaltext := Trim(f[2]), nav.goaltype := Trim(f[3]), nav.goalstatus := Trim(f[4]), nav.goalcount := NavNum(f[5])
				, nav.goaltotal := NavNum(f[6]), nav.goalshown := NavNum(f[7])
		else if (f[1] = "path" && withPath)
			{
			nav.path := [], nodes := SubStr(navLine, 6)
			Loop, Parse, nodes, `;
				{
				xyz := StrSplit(A_LoopField, ",")
				if (xyz.Length() = 3 && NavNum(xyz[1]) != "" && NavNum(xyz[2]) != "" && NavNum(xyz[3]) != "")
					nav.path.Push({x: NavNum(xyz[1]), y: NavNum(xyz[2]), z: NavNum(xyz[3])})
				}
			}
		}
	if (nav.ok != 1)
		{
		NavWhy := "an odd answer: " SubStr(RegExReplace(answer, "\s+", " "), 1, 60)
		NavWait := 1000, NavWaitUntil := A_TickCount + NavWait
		return ""
		}
	NavWhy := "", NavWait := 0, NavWaitUntil := 0
	return nav
	}

;Text for a URL: its UTF-8 bytes, all but letters, digits and -._~ as %XX (the helper reads it as UTF-8)
NavUri(text)
	{
	VarSetCapacity(navUriBuf, StrPut(text, "UTF-8"), 0)
	navUriLen := StrPut(text, &navUriBuf, "UTF-8") - 1
	navUriOut := ""
	Loop, % navUriLen
		{
		navUriByte := NumGet(navUriBuf, A_Index - 1, "UChar")
		navUriOut .= ((navUriByte >= 48 && navUriByte <= 57) || (navUriByte >= 65 && navUriByte <= 90) || (navUriByte >= 97 && navUriByte <= 122)
			|| navUriByte = 45 || navUriByte = 46 || navUriByte = 95 || navUriByte = 126) ? Chr(navUriByte) : "%" Format("{:02X}", navUriByte)
		}
	return navUriOut
	}

;The quest's active goal from the game's memory (the helper's /goal - READ-ONLY, vision\questmem.py: the line exactly as
;the game draws it under the quest arrow, where the OCR of the screen slips letters - 2026-10-24 "Opiio (jn -rhe" for
;"Defeat Optio Agenor ..."), as an object:
;  text      the goal line ("Defeat Crustacean Waverunner and Collect Foul Tasting Algae in The Grotto (0 of 3)")
;  from      data (built from the quest's own data) / hud (the HUD's own text: the data's names not all read)
;  shown     1 on screen, 0 hidden (a battle), "" not known; hudtext the HUD's own line, distance the arrow's number
;  type      BOUNTY (defeat), BOUNTYCOLLECT (defeat and collect), USAGE (collect / open / use / read), WAYPOINT (go to),
;            PERSONA (talk to), SCAVENGE...; status INCOMPLETE / COMPLETE (the quest moving on); "" not read
;  count, total  "(count of total)"; "" none (talk and go-to goals)
;  mob, item, npc, place  what it names: the mob (or its kind: "Gobblers"), the item / object / one to go to, the NPC
;  quest, questid, goalid  the quest's title and ids; exact 1: the line and the fields are the goal's own data
;  itemkey, mobkey  the name-table keys of what it names (the TALLYTEXT "WizQst371C7_00000008" = Inactive Protector - the
;            display key NavItems' things carry; the TALLYTEXT2 "WizardMobs_00000883"); npcfirst, npclast a talk goal's
;            NPC's (FIRSTNAME, LASTNAME "WC-NPCs_00000014"); namekey the goal's own ("WizardQuestGoals_UseItem"); typenum
;            the game's number for its kind (USAGE 8 - for logs only: it may change between builds). "" none, the quest
;            moved on, or an older helper. A key is exact, but a goal's key may be another table's for the same words:
;            a match candidate, never the only test
;"" when it can't be read - navmem:0 in PlayerStats.txt, the helper not running or older (no /goal), no quest, the game
;not read yet - NavGoalWhy says why (the walker reads the line off the screen then). After no answer or an ERR it isn't
;asked again for 10 s (an older helper: 60 s)
NavGoal(timeoutMs := 800)
	{
	if (!Stat("navmem"))
		{
		NavGoalWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavGoalWhy := "the vision helper isn't running"
		return ""
		}
	if (NavGoalWaitUntil && A_TickCount < NavGoalWaitUntil)
		return ""
	answer := VisionGet("/goal", timeoutMs, true)
	if (answer = "")
		{
		NavGoalWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavGoalWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 10000)
		return ""
		}
	NavGoalWaitUntil := 0
	goal := {text: "", from: "", shown: "", hudtext: "", distance: "", type: "", status: "", count: "", total: "", mob: ""
		, item: "", npc: "", place: "", quest: "", questid: "", goalid: "", exact: "", typenum: "", itemkey: "", mobkey: ""
		, npcfirst: "", npclast: "", namekey: ""}
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "none")
			{
			NavGoalWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (f[1] = "text")
			goal.text := Trim(f[2]), goal.from := Trim(f[3])
		else if (f[1] = "shown")
			goal.shown := NavNum(f[2]), goal.hudtext := Trim(f[3]), goal.distance := Trim(f[4])
		;(kind's number: a kindnum line - or a 4th field here, as a helper may send it)
		else if (f[1] = "kind")
			goal.type := Trim(f[2]), goal.status := Trim(f[3]), goal.typenum := f.Length() >= 4 ? NavNum(f[4]) : goal.typenum
		else if (f[1] = "count")
			goal.count := NavNum(f[2]), goal.total := NavNum(f[3])
		else if (f[1] = "mob" || f[1] = "item" || f[1] = "npc" || f[1] = "place")
			goal[f[1]] := Trim(f[2])
		else if (f[1] = "quest")
			goal.quest := Trim(f[2]), goal.questid := Trim(f[3]), goal.goalid := Trim(f[4])
		else if (f[1] = "exact")
			goal.exact := NavNum(f[2])
		;(the goal's raw keys - an older helper sends none of these lines)
		else if (f[1] = "itemkey" || f[1] = "mobkey" || f[1] = "namekey")
			goal[f[1]] := Trim(f[2])
		else if (f[1] = "npckeys")
			goal.npcfirst := Trim(f[2]), goal.npclast := Trim(f[3])
		else if (f[1] = "kindnum")
			goal.typenum := NavNum(f[2])
		}
	if (goal.text = "")
		{
		NavGoalWhy := "an odd answer: " SubStr(RegExReplace(answer, "\s+", " "), 1, 60)
		return ""
		}
	NavGoalWhy := ""
	return goal
	}

;The zone's mobs from the game's memory (the helper's /mobs - READ-ONLY, vision\navmem.py and vision\bossmem.py: nothing
;in the game is written, injected or hooked; no key, click or window), nearest first, as an array of {name, x, y, z, dist
;(from the wizard), quest (1: the quest's - the helper's verdict by the game's memory's goal: its name, its kind, one by
;a fight goal's goal; goalLine, the line read off the screen, only when the memory's can't be read), off (degrees from
;where it faces to the wizard, "" not known), title (as the game names it: Boss, Elite, Normal, Easy, Minion), rank (the
;one the game shows: "Rank 9 Boss"), health (its starting - max - health), school (Ice...), boss (1: the game's own boss
;flag, 0 not), gid, named (1: the quest's by its name or its goal only - quest without a same-family match elsewhere in
;the zone, 0 not)} - title...named "" while not known (the helper's reader being made, a build it can't read, an older
;helper). [] when there are none (the helper's plain "none"); "" when they can't be read - navmem:0, the helper not
;running, dual mode (one client's memory), "none (<why>)" (not attached, a new zone being looked at...), an ERR or no
;answer: NavMobsWhy says why, and after an ERR or no answer it isn't asked again for 5 s
NavMobs(goalLine := "", timeoutMs := 400)
	{
	NavMobsWhy := ""
	if (!Stat("navmem"))
		{
		NavMobsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavMobsWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavMobsWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavMobsWaitUntil && A_TickCount < NavMobsWaitUntil)
		{
		NavMobsWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nmAns := VisionGet("/mobs" (goalLine != "" ? "?goal=" NavUri(SubStr(goalLine, 1, 160)) : ""), timeoutMs, true)
	if (nmAns = "")
		{
		NavMobsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavMobsWaitUntil := A_TickCount + 5000
		return ""
		}
	NavMobsWaitUntil := 0
	nmOut := []
	Loop, Parse, nmAns, `n, `r
		{
		nmF := StrSplit(A_LoopField, "|")
		;(none: no mobs in the zone - "none (<why>)": they can't be read now)
		if (Trim(A_LoopField) = "none")
			{
			NavMobsWhy := "no mobs in the zone"
			return []
			}
		if (SubStr(A_LoopField, 1, 5) = "none ")
			{
			NavMobsWhy := Trim(RegExReplace(Trim(A_LoopField), "^none\s*\(?|\)$"))
			return ""
			}
		if (nmF[1] != "mob" || nmF.Length() < 8)
			continue
		nmM := {name: Trim(nmF[2]), x: NavNum(nmF[3]), y: NavNum(nmF[4]), z: NavNum(nmF[5]), dist: NavNum(nmF[6]), quest: nmF[7] = 1 ? 1 : 0
			, off: NavNum(nmF[8]), title: "", rank: "", health: "", school: "", boss: "", gid: "", named: ""}
		;(9-14: what it is - an older helper's lines have none)
		if (nmF.Length() >= 14)
			nmM.title := Trim(nmF[9]), nmM.rank := NavNum(nmF[10]), nmM.health := NavNum(nmF[11]), nmM.school := Trim(nmF[12])
				, nmM.boss := (nmF[13] = "1" ? 1 : nmF[13] = "0" ? 0 : ""), nmM.gid := Trim(nmF[14])
		;(15: the quest's by its name or its goal - an older helper's lines stop at 14)
		if (nmF.Length() >= 15)
			nmM.named := (Trim(nmF[15]) = "1" ? 1 : Trim(nmF[15]) = "0" ? 0 : "")
		nmOut.Push(nmM)
		}
	return nmOut
	}

;The zone's things from the game's memory (the helper's /items - READ-ONLY, vision\navmem.py; with far the zone's own file
;too, vision\placements.py), nearest first, as an array of {name, x, y, z, dist (from the wizard), quest (1: the quest's
;goal is about it - the helper's verdict: the goal's own key (NavGoal's itemkey), else - an exact goal - its item, or a
;talk goal's NPC, as the thing's whole name, else the goal's line naming it; goalLine, the line read off the screen, only
;when the memory's can't be read), gid (a number in memory; a placement of the file's "f:<template>:<n>" - it turns into
;the live gid once in reach: remember used or skipped ones by template and place, not gid), key (its display key),
;template, src (mem: in the game's memory now; file: where the zone's file places it - far only), kind (item: lying about,
;picked up on contact; object: used, opened, read - Inactive Protector; npc; ambient: a mob's name on something that
;doesn't fight)}. An older helper's lines (8 fields): key and template "", src mem, kind item (all it listed). far: the
;zone file's things the memory doesn't hold too (it holds only those within ~6.7k; the file is read in a thread at each
;zone change - till then the live ones only; a used or picked-up one stays in the file). [] when there are none; "" when
;they can't be read - navmem:0, the helper not running, "none (<why>)" (not attached, a new zone being looked at, the
;zone's file being read...), an ERR or no answer: NavItemsWhy says why, and after an ERR or no answer it isn't asked
;again for 5 s
NavItems(goalLine := "", far := false, timeoutMs := 2500)
	{
	NavItemsWhy := ""
	if (!Stat("navmem"))
		{
		NavItemsWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavItemsWhy := "the vision helper isn't running"
		return ""
		}
	if (NavItemsWaitUntil && A_TickCount < NavItemsWaitUntil)
		{
		NavItemsWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	niAns := VisionGet("/items?goal=" NavUri(SubStr(goalLine, 1, 160)) (far ? "&far=1" : ""), timeoutMs, true)
	if (niAns = "")
		{
		NavItemsWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavItemsWaitUntil := A_TickCount + 5000
		return ""
		}
	NavItemsWaitUntil := 0
	niOut := []
	Loop, Parse, niAns, `n, `r
		{
		;(none: nothing in the zone - "none (<why>)": they can't be read now)
		if (Trim(A_LoopField) = "none")
			{
			NavItemsWhy := "nothing in the zone"
			return []
			}
		if (SubStr(A_LoopField, 1, 5) = "none ")
			{
			NavItemsWhy := Trim(RegExReplace(Trim(A_LoopField), "^none\s*\(?|\)$"))
			return ""
			}
		niF := StrSplit(A_LoopField, "|")
		if (niF[1] != "item" || niF.Length() < 8)
			continue
		niT := {name: Trim(niF[2]), x: NavNum(niF[3]), y: NavNum(niF[4]), z: NavNum(niF[5]), dist: NavNum(niF[6])
			, quest: niF[7] = 1 ? 1 : 0, gid: Trim(niF[8]), key: "", template: "", src: "mem", kind: "item"}
		;(9-12: its key, template, where it's from, its kind - an older helper's lines stop at 8)
		if (niF.Length() >= 11)
			niT.key := Trim(niF[9]), niT.template := Trim(niF[10]), niT.src := Trim(niF[11]), niT.kind := niF.Length() >= 12 ? Trim(niF[12]) : ""
		niOut.Push(niT)
		}
	return niOut
	}

;The battle's participants from the game's memory (the helper's /battle - READ-ONLY, vision\bossmem.py), in a battle's
;planning phase: {me: the wizard's own (or ""), foes: the other side's, parts: all} - each {me (1 the wizard's own), team,
;name (the mob's - "" a wizard), health, max, boss (1: the game's own boss flag), title, rank, school (its mob's - "" not
;known), player (1 a wizard), gid, x (the middle of its plate across the game's window, 0..1 - "" not read or an older
;helper)}. "" when it can't be read - navmem:0, the helper not running or older (no /battle), dual
;mode, not in a battle's planning phase, the readers being made: NavBattleWhy says why (after an ERR or no answer not
;asked again for 5 s; an older helper's "unknown request": 60 s)
NavBattle(timeoutMs := 700)
	{
	NavBattleWhy := ""
	if (!Stat("navmem"))
		{
		NavBattleWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavBattleWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavBattleWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavBattleWaitUntil && A_TickCount < NavBattleWaitUntil)
		{
		NavBattleWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nbAns := VisionGet("/battle", timeoutMs, true)
	if (nbAns = "")
		{
		NavBattleWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavBattleWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavBattleWaitUntil := 0
	nbOut := {me: "", foes: [], parts: []}
	Loop, Parse, nbAns, `n, `r
		{
		nbF := StrSplit(A_LoopField, "|")
		if (nbF[1] = "none")
			{
			NavBattleWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (nbF[1] != "part" || nbF.Length() < 12)
			continue
		nbP := {me: nbF[2] = 1 ? 1 : 0, team: NavNum(nbF[3]), name: Trim(nbF[4]), health: NavNum(nbF[5]), max: NavNum(nbF[6])
			, boss: (nbF[7] = "1" ? 1 : nbF[7] = "0" ? 0 : ""), title: Trim(nbF[8]), rank: NavNum(nbF[9]), school: Trim(nbF[10])
			, player: nbF[11] = 1 ? 1 : 0, gid: Trim(nbF[12]), x: nbF.Length() >= 13 ? NavNum(nbF[13]) : ""}
		nbOut.parts.Push(nbP)
		if (nbP.me && !IsObject(nbOut.me))
			nbOut.me := nbP
		}
	if (!IsObject(nbOut.me))
		{
		NavBattleWhy := "an odd answer (no line for the wizard): " SubStr(RegExReplace(nbAns, "\s+", " "), 1, 60)
		return ""
		}
	;(the other side: another team than the wizard's - a team not read: not a wizard of the game's)
	for nbI, nbP in nbOut.parts
		if (!nbP.me && (nbOut.me.team = "" || nbP.team = "" ? !nbP.player : nbP.team != nbOut.me.team))
			nbOut.foes.Push(nbP)
	return nbOut
	}

;The game's UI scale from its memory (the helper's /uiroot - READ-ONLY: the GUI root's size in GUI units, vision\navmem.py
;ui_root): a card's pitch is 67 GUI units at any size and 82 px at UI scale 1 (HalfPitch 41), so UiScale = GameW / the
;root's width x 67 / 82 - 2560 / 1827 x 67 / 82 = 1.145 at 1440p borderless, where the cut pictures say 1.144. NavUiRootW
;the width read. "" when it can't be read (navmem:0, the helper not running or older, dual mode, the game not in the world
;yet): NavUiWhy says why - not asked again for 60 s after a failure
NavUiScale(timeoutMs := 500)
	{
	NavUiWhy := ""
	if (!Stat("navmem") || !VisionOn || dualmode == 1)
		{
		NavUiWhy := !Stat("navmem") ? "navmem:0 in PlayerStats.txt" : !VisionOn ? "the vision helper isn't running" : "dual mode"
		return ""
		}
	if (NavUiWaitUntil && A_TickCount < NavUiWaitUntil)
		{
		NavUiWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nuAns := Trim(VisionGet("/uiroot", timeoutMs, true), " `t`r`n")
	nuF := StrSplit(nuAns, "|")
	if (nuF[1] != "root" || NavNum(nuF[2]) = "" || NavNum(nuF[2]) <= 0 || GameW <= 0)
		{
		NavUiWhy := nuAns = "" ? (VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")) : nuF[1] = "none" ? Trim(SubStr(nuAns, 6)) : "an odd answer: " SubStr(nuAns, 1, 40)
		NavUiWaitUntil := A_TickCount + 60000
		return ""
		}
	NavUiWaitUntil := 0, NavUiRootW := NavNum(nuF[2])
	return GameW / NavUiRootW * 67 / 82
	}

;A cross-check of the picture set in use (UiScale) against the game's memory's UI scale (NavUiScale) - nothing is switched
;on it yet: a disagreement over 0.8% is logged, once per window size and set (tonight's 1.130 against the memory's 1.145
;would have been). Asked at a round's start (the main loop), till the memory answers for that size and set
PicMemCheck()
	{
	static done := {}
	pmcKey := GameW "x" GameH "|" PicSet
	if (done.HasKey(pmcKey) || !IsObject(PicSets) || !IsObject(PicSets[PicSet]))
		return
	pmcSc := NavUiScale()
	if (pmcSc = "")
		return
	done[pmcKey] := 1
	if (Abs(pmcSc / UiScale - 1) > 0.008)
		DebugLog("UI size: the game's memory says UI scale " Round(pmcSc, 3) " (its GUI " NavUiRootW " units wide in a " GameW " px window) - the pictures in use are at " Round(UiScale, 3) " (" (PicSet = 1 ? "the main set" : SubStr(PicDir, StrLen(A_WorkingDir) + 2)) "): they disagree - nothing switched on it (only a cross-check for now)")
	}

;The backpack from the game's memory (the helper's /bag - READ-ONLY, vision\bagmem.py: nothing in the game is written,
;injected or hooked; no key, click or window), as an object: items (the backpack list's own count - emotes too), allowed
;(its size: 150), extra, gold, goldMax (the pouch), gid (the character's id, hex), walked (items read), emotes, setsOk (1:
;every Equipment Set and its items read, every item walked - QuickSell.ahk sells nothing without it), space
;({n, m, text}: the backpack page's own "N/M" - only while that page is shown - else ""), cats ({kind: {n, crowns,
;nosell, plain}} - deck, hat, robe, shoes, weapon, athame, amulet, ring, pet, mount, emote...; ? not read; crowns: a Crowns
;item or a Crown-shop template's, or one whose name wasn't read; plain: neither crowns nor unsellable), crownShop ([{kind,
;name}]: Crown-shop templates without the game's Crowns flag, and items whose name wasn't read), tips ([{i, shown, l,
;t, r, b, image, button, name}]: the HUD's right-hand icons - Prospector Zeke's portrait: the backpack full, or the gold
;bag nearly full), sets ([{n, equipped, ids, name}]), setItems ([{set, equipped, gid, tid, name, kind, crowns}]: the
;Equipment Sets' items in the backpack), rootW, rootH (the game's GUI in its own units). "" when it can't be read -
;navmem:0, the helper not running or older (no /bag), dual mode, "none|<why>" (not in the world, the reader being
;made): NavBagWhy says why (after an ERR or no answer not asked again for 5 s; an older helper's "unknown request": 60 s)
NavBag(timeoutMs := 600)
	{
	NavBagWhy := ""
	if (!Stat("navmem"))
		{
		NavBagWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavBagWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavBagWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavBagWaitUntil && A_TickCount < NavBagWaitUntil)
		{
		NavBagWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nbgAns := VisionGet("/bag", timeoutMs, true)
	if (nbgAns = "")
		{
		NavBagWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavBagWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavBagWaitUntil := 0
	nbgOut := {items: "", allowed: "", extra: "", gold: "", goldMax: "", gid: "", walked: "", emotes: "", setsOk: 0, space: "", cats: {}
		, tips: [], sets: [], setItems: [], crownShop: [], rootW: "", rootH: ""}
	Loop, Parse, nbgAns, `n, `r
		{
		nbgF := StrSplit(A_LoopField, "|")
		if (nbgF[1] = "none")
			{
			NavBagWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (nbgF[1] = "bag" && nbgF.Length() >= 7)
			nbgOut.items := NavNum(nbgF[2]), nbgOut.allowed := NavNum(nbgF[3]), nbgOut.extra := NavNum(nbgF[4]), nbgOut.gold := NavNum(nbgF[5])
				, nbgOut.goldMax := NavNum(nbgF[6]), nbgOut.gid := Trim(nbgF[7]), nbgOut.walked := NavNum(nbgF[8]), nbgOut.emotes := NavNum(nbgF[9])
				, nbgOut.setsOk := nbgF[10] = "1" ? 1 : 0
		else if (nbgF[1] = "space" && NavNum(nbgF[2]) != "" && NavNum(nbgF[3]) != "")
			nbgOut.space := {n: NavNum(nbgF[2]), m: NavNum(nbgF[3]), text: Trim(nbgF[4])}
		else if (nbgF[1] = "cat" && Trim(nbgF[2]) != "")
			nbgOut.cats[Trim(nbgF[2])] := {n: NavNum(nbgF[3]), crowns: NavNum(nbgF[4]), nosell: NavNum(nbgF[5]), plain: NavNum(nbgF[6])}
		else if (nbgF[1] = "crownshop" && Trim(nbgF[3]) != "")
			nbgOut.crownShop.Push({kind: Trim(nbgF[2]), name: Trim(nbgF[3])})
		else if (nbgF[1] = "tip")
			nbgOut.tips.Push({i: NavNum(nbgF[2]), shown: nbgF[3] = "1" ? 1 : 0, l: NavNum(nbgF[4]), t: NavNum(nbgF[5]), r: NavNum(nbgF[6])
				, b: NavNum(nbgF[7]), image: Trim(nbgF[8]), button: Trim(nbgF[9]), name: Trim(nbgF[10])})
		else if (nbgF[1] = "set")
			nbgOut.sets.Push({n: NavNum(nbgF[2]), equipped: nbgF[3] = "1" ? 1 : 0, ids: NavNum(nbgF[4]), name: Trim(nbgF[5])})
		else if (nbgF[1] = "setitem")
			nbgOut.setItems.Push({set: NavNum(nbgF[2]), equipped: nbgF[3] = "1" ? 1 : 0, gid: Trim(nbgF[4]), tid: NavNum(nbgF[5])
				, name: Trim(nbgF[6]), kind: Trim(nbgF[7]), crowns: nbgF[8] = "1" ? 1 : 0})
		else if (nbgF[1] = "root")
			nbgOut.rootW := NavNum(nbgF[2]), nbgOut.rootH := NavNum(nbgF[3])
		}
	if (nbgOut.items = "" || nbgOut.allowed = "")
		{
		NavBagWhy := "an odd answer (no backpack line): " SubStr(RegExReplace(nbgAns, "\s+", " "), 1, 60)
		return ""
		}
	return nbgOut
	}

;The game's windows from its memory (the helper's /gui - READ-ONLY, vision\bagmem.py), paths: "Anc/Name,..." (a window
;named Name with an ancestor named Anc - more ancestors allowed, in order; 40 at most). An object: rootW, rootH (the GUI
;in its own units - the game's client area), win ({path: {found, type, shown (VISIBLE on it and every ancestor), l, t, r,
;b (in the root's units), checked, greyed (1/0, "" not one), text (its words, the markup out), key (the .gui file's
;"<string;KEY>" when that's all its text), dups (its shown matches), pl, pt, pr, pb (its parent's), matches}}), box
;(the message box up: {shown, title, caption, titleKey, captionKey, count - how many are up}; shown 0 none), btns
;([{name, label, l, t, r, b, key, greyed}]: its shown buttons - centerButton, leftButton, rightButton). "" when it can't be
;read - as NavBag: NavGuiWhy
NavGui(paths, timeoutMs := 600)
	{
	NavGuiWhy := ""
	if (!Stat("navmem"))
		{
		NavGuiWhy := "navmem:0 in PlayerStats.txt"
		return ""
		}
	if (!VisionOn)
		{
		NavGuiWhy := "the vision helper isn't running"
		return ""
		}
	if (dualmode == 1)
		{
		NavGuiWhy := "dual mode: the game's memory is one client's"
		return ""
		}
	if (NavGuiWaitUntil && A_TickCount < NavGuiWaitUntil)
		{
		NavGuiWhy := "asked again in a moment (the last ask failed)"
		return ""
		}
	nguAns := VisionGet("/gui?w=" paths, timeoutMs, true)
	if (nguAns = "")
		{
		NavGuiWhy := VisionErr = "" ? "no answer" : RegExReplace(VisionErr, "^ERR\s*")
		NavGuiWaitUntil := A_TickCount + (InStr(VisionErr, "unknown request") ? 60000 : 5000)
		return ""
		}
	NavGuiWaitUntil := 0
	nguOut := {rootW: "", rootH: "", win: {}, box: {shown: 0, title: "", caption: "", titleKey: "", captionKey: ""}, btns: []}
	Loop, Parse, nguAns, `n, `r
		{
		nguF := StrSplit(A_LoopField, "|")
		if (nguF[1] = "none")
			{
			NavGuiWhy := Trim(SubStr(A_LoopField, 6))
			return ""
			}
		if (nguF[1] = "root")
			nguOut.rootW := NavNum(nguF[2]), nguOut.rootH := NavNum(nguF[3])
		else if (nguF[1] = "win" && nguF.Length() >= 18)
			nguOut.win[Trim(nguF[2])] := {found: Trim(nguF[3]) != "" ? 1 : 0, type: Trim(nguF[3]), shown: nguF[4] = "1" ? 1 : 0, l: NavNum(nguF[5]), t: NavNum(nguF[6])
				, r: NavNum(nguF[7]), b: NavNum(nguF[8]), checked: NavNum(nguF[9]), greyed: NavNum(nguF[10]), text: Trim(nguF[11]), key: Trim(nguF[12])
				, dups: NavNum(nguF[13]), pl: NavNum(nguF[14]), pt: NavNum(nguF[15]), pr: NavNum(nguF[16]), pb: NavNum(nguF[17]), matches: NavNum(nguF[18])}
		else if (nguF[1] = "box")
			nguOut.box := {shown: nguF[2] = "1" ? 1 : 0, title: Trim(nguF[3]), caption: Trim(nguF[4]), titleKey: Trim(nguF[5]), captionKey: Trim(nguF[6]), count: NavNum(nguF[7])}
		else if (nguF[1] = "btn" && nguF.Length() >= 9)
			nguOut.btns.Push({name: Trim(nguF[2]), label: Trim(nguF[3]), l: NavNum(nguF[4]), t: NavNum(nguF[5]), r: NavNum(nguF[6]), b: NavNum(nguF[7])
				, key: Trim(nguF[8]), greyed: NavNum(nguF[9])})
		}
	if (nguOut.rootW = "" || nguOut.rootW <= 0 || nguOut.rootH = "" || nguOut.rootH <= 0)
		{
		NavGuiWhy := "an odd answer (no root line): " SubStr(RegExReplace(nguAns, "\s+", " "), 1, 60)
		return ""
		}
	return nguOut
	}

;A battle's first round: the mob that started it, off the mobs the helper read lately (while walking with mob
;avoidance on) - how far away you were and how far off its facing when it noticed you, into debug.log, to measure the
;mobs' real sight against the mobshape / mobradius settings
CaughtLog()
	{
	if (!VisionOn)
		return
	a := VisionGet("/caught", 600, true)
	f := StrSplit(Trim(a, " `r`n"), "|")
	if (f[1] != "caught" || f.Length() < 6)
		return
	s := MobShape()
	if (s.wide >= 360)
		where := (f[3] <= s.range ? "inside" : "outside") " the circle set (" s.range " all round)"
	else if (f[4] = "")
		where := "its facing unknown"
	else
		where := ((f[4] <= s.wide / 2 && f[3] <= s.range) ? "inside" : "outside") " the " s.name " set (" s.wide " degrees wide, " s.range " long)"
	DebugLog("  Caught by " f[2] ": " (f[5] = 1 ? "it came for you from " f[3] " away" : "you walked into it (" f[3] " away)")
		. (f[4] != "" ? ", " f[4] " degrees off where it faced" : "") " (" f[6] " s before) - " where)
	MobGrow(f, s)
	}

;Caught by a mob the quest doesn't want (mobgrow, on unless 0): the reach the route keeps out of made bigger, so mobs
;are kept further off from now on - the shape's front (mobradius) when it caught the wizard in front of it (or all round:
;a circle, its facing unknown), its reach all round (mobbody) when from the side or behind - to where it caught him from
;and 25 more, 20 more at the least; 1500 at most (all round past the front: the front raised too). Left as it is when the battle was
;the quest's - collecting, a mob the helper took as the quest's (/caught's quest field: by the game's memory's goal), a mob
;named in the goal line, X pressed in the last 15 s (the goal's boss), a dungeon run that fights every battle - or you were
;playing. f: /caught's fields; s: MobShape()
MobGrow(f, s)
	{
	if (Stat("mobgrow") = 0 || (Stats.HasKey("mobavoid") && !Stats["mobavoid"]))
		return
	mgName := f[2], mgDist := Round(f[3]), mgOff := f[4]
	;(collecting: walking into mobs is the point - but not on the way to a quest item lying about: Collect.ahk)
	mgWhy := (WkArrived = 7 && CiGid = "") ? "collecting" : (WkLastX && A_TickCount - WkLastX < 15000) ? "X was just pressed - the goal's battle?"
		: (IsObject(DgRun) && !DgRun.avoid) ? "a dungeon run" : PlayerActive ? "you were playing" : ""
	;(the quest's mob by the helper's own verdict - the game's memory's goal: its name, its kind, or one by a fight goal -
	;left off the avoid list: /caught's 7th field; an older helper's has none)
	if (mgWhy = "" && f[7] = 1)
		mgWhy := "the quest's - the helper didn't keep it off"
	;(the quest's mob: its name in the goal line last read)
	if (mgWhy = "" && WkGoalLine != "" && IsFunc("WalkLetters"))
		{
		mgKey := Func("WalkLetters").Call(mgName)
		if (StrLen(mgKey) >= 4 && InStr(Func("WalkLetters").Call(WkGoalLine), mgKey))
			mgWhy := "the quest's - in its goal line"
		}
	if (mgWhy != "")
		{
		DebugLog("  (the mobs' reach left as it is: " mgWhy ")")
		return
		}
	;(caught: the 10 minutes before the reach is made smaller start again - MobShrinkTick)
	MobWalkMs := 0
	mgFront := s.wide >= 360 || mgOff = "" || mgOff <= s.wide / 2
	mgSet := mgFront ? "mobradius" : "mobbody"
	mgWas := mgFront ? s.range : s.body
	mgTo := Min(1500, Max(mgWas + 20, mgDist + 25))
	mgWhat := mgFront ? "how far they notice you" : "their reach all round"
	if (mgTo <= mgWas)
		{
		DebugLog("  not the quest's mob - " mgWhat " is at its most already (" mgWas ")")
		return
		}
	;(all round further than in front: the front that far too)
	mgPairs := [[mgSet, mgTo]]
	if (!mgFront && mgTo > s.range)
		mgPairs.Push(["mobradius", mgTo]), mgWhat .= " (and how far they notice you, " s.range " -> " mgTo ")"
	if (IsFunc("CfgWrite") && Func("CfgWrite").Call(mgPairs))
		DebugLog("  not the quest's mob - " mgWhat " raised " mgWas " -> " mgTo " (Settings: " mgSet ")")
	}

;Every 10 minutes of walking without a mob the quest doesn't want catching the wizard (mobshrink, on unless 0): the reach
;the route keeps out of made smaller - a tenth off how far they notice you (mobradius) and their reach all round
;(mobbody) - so routes aren't long ways round for nothing; a catch raises it again (MobGrow, which starts the 10 minutes
;again). Never below what you set yourself in the Settings window (mobradiusfloor, mobbodyfloor - written when you
;save them there; else 300 and 120). 2026-10-24: a fifth at a time down to 300 had the crabs of Survey Camp catching
;the wizard - you'd set 850. Counted while the bot's on and walking, out of battle, you not playing
MobShrinkTick()
	{
	static lastAt := 0
	now := A_TickCount
	if (lastAt && now - lastAt < 5000 && BotOn && Walking && inbattle != 1 && !PlayerActive)
		MobWalkMs := (MobWalkMs ? MobWalkMs : 0) + now - lastAt
	lastAt := now
	if (MobWalkMs < 600000)
		return
	MobWalkMs := 0
	if (Stat("mobshrink") = 0 || (Stats.HasKey("mobavoid") && !Stats["mobavoid"]))
		return
	s := MobShape()
	r := Max(Max(300, Stat("mobradiusfloor")), Round(s.range * 0.9)), b := Max(Max(120, Stat("mobbodyfloor")), Round(s.body * 0.9))
	if (r >= s.range && b >= s.body)
		return
	if (IsFunc("CfgWrite") && Func("CfgWrite").Call([["mobradius", r], ["mobbody", b]]))
		DebugLog("Walk: 10 minutes walking without a mob catching the wizard - mobs kept off less far: how far they notice you " s.range " -> " r ", their reach all round " s.body " -> " b " (Settings: mobshrink)")
	}

;What the mobs see, as PlayerStats.txt says: {shape (mobshape: 1 a circle all round, 2 a semi-circle in front - the
;default, 3 a cone in front), wide (degrees: 360, 180, mobcone - 60), range (mobradius: how far, 300), name}
MobShape()
	{
	shape := Stats.HasKey("mobshape") ? Round(Stats["mobshape"]) : 2
	shape := (shape >= 1 && shape <= 3) ? shape : 2
	cone := Stats.HasKey("mobcone") && Stats["mobcone"] >= 5 ? Min(180, Round(Stats["mobcone"])) : 60
	return {shape: shape, wide: shape = 1 ? 360 : shape = 2 ? 180 : cone, range: Stat("mobradius") > 0 ? Round(Stat("mobradius")) : 300
		, body: Stat("mobbody") > 0 ? Round(Stat("mobbody")) : 120, name: shape = 1 ? "circle" : shape = 2 ? "semi-circle" : "cone"}
	}

;The helper's arguments for keeping a route out of what mobs see: mobavoid (on unless 0) and MobShape - "" when it's off
NavMobArgs()
	{
	if (Stats.HasKey("mobavoid") && !Stats["mobavoid"])
		return ""
	s := MobShape()
	return "&avoid=1&mobr=" s.range "&shape=" s.shape (s.shape = 3 ? "&cone=" s.wide : "") (s.shape > 1 ? "&body=" s.body : "")
	}

;A number off /nav ("" if it isn't one: empty, nan, inf). Python may write a tiny one as 1.5e-08
NavNum(v)
	{
	v := Trim(v)
	if (RegExMatch(v, "i)^([-+]?\d+(?:\.\d*)?|[-+]?\.\d+)(?:e([-+]?\d+))?$", num))
		return num2 = "" ? num1 + 0 : (num1 + 0.0) * (10.0 ** num2)
	return ""
	}
