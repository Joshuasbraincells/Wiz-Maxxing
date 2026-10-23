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
	for each, name in ["sharpen", "potent", "blade3", "blade4", "trap3", "trap4", "tower", "reshuffle", "feint", "epic", "colossal", "gargantuan", "monstrous", "giant", "strong", "elementalblade", "elementaltrap", "spiritblade", "spirittrap"]
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
	key := hitschool "|" UiScale "|" ScreenX "|" ScreenY
	if (!IsObject(VisionCards) || A_TickCount - VisionCardsAt > 400 || key != VisionCardsKey)
		{
		answer := VisionGet("/cards?x1=" Round(ScreenX - HandHalf) "&y1=" Round(ScreenY - Px(75)) "&x2=" Round(ScreenX + HandHalf) "&y2=" Round(ScreenY + Px(150)) "&scale=" Round(UiScale, 3) "&pics=" VisionPicList())
		if (answer = "")
			return -1
		VisionCards := [], VisionCardsAt := A_TickCount, VisionCardsKey := key, VisionMissing := ","
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
	VisionCardsAt := 0
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

;---- The game's memory: where the wizard is and where the quest arrow points (for Walker.ahk) ----
;
;The helper's /nav reads them straight out of the game's memory, READ-ONLY: the game is opened for reading
;only - nothing in it is ever written, nothing is injected or hooked, no keys are sent and its window isn't
;touched. navmem:0 in PlayerStats.txt switches it off (the walker then only reads the arrow off the screen).
;Why the last NavRead got nothing; when it may ask again, and how long it waited last time
global NavWhy, NavWaitUntil, NavWait
;Set by the walker's F8 (walking on): the next NavRead asks the helper to forget the teleports it gave up
global NavUnblock

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
	answer := VisionGet("/nav?path=" (withPath ? 1 : 0) "&route=" (withRoute ? 1 : 0) unblock, timeoutMs, true)
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
		, mob: "", mx: "", my: "", mobname: "", escape: "", blindahead: "", blindback: "", blindin: ""}
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
			;(12: inside a mob's ring or sight - its name: the aim leads out of it)
			nav.escape := Trim(f[12])
			}
		;(the mob whose ring or sight the arrow's straight way comes into, and backing up would - moves off the route)
		else if (f[1] = "blind" && withRoute)
			nav.blindahead := Trim(f[2]), nav.blindback := Trim(f[3]), nav.blindin := Trim(f[4])
		else if (f[1] = "routewhy" && withRoute)
			nav.routewhy := Trim(SubStr(navLine, 10))
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
	}

;What the mobs see, as PlayerStats.txt says: {shape (mobshape: 1 a circle all round, 2 a semi-circle in front - the
;default, 3 a cone in front), wide (degrees: 360, 180, mobcone - 60), range (mobradius: how far, 300), name}
MobShape()
	{
	shape := Stats.HasKey("mobshape") ? Round(Stats["mobshape"]) : 2
	shape := (shape >= 1 && shape <= 3) ? shape : 2
	cone := Stats.HasKey("mobcone") && Stats["mobcone"] >= 5 ? Min(180, Round(Stats["mobcone"])) : 60
	return {shape: shape, wide: shape = 1 ? 360 : shape = 2 ? 180 : cone, range: Stat("mobradius") > 0 ? Round(Stat("mobradius")) : 300
		, name: shape = 1 ? "circle" : shape = 2 ? "semi-circle" : "cone"}
	}

;The helper's arguments for keeping a route out of what mobs see: mobavoid (on unless 0) and MobShape - "" when it's off
NavMobArgs()
	{
	if (Stats.HasKey("mobavoid") && !Stats["mobavoid"])
		return ""
	s := MobShape()
	return "&avoid=1&mobr=" s.range "&shape=" s.shape (s.shape = 3 ? "&cone=" s.wide : "")
	}

;A number off /nav ("" if it isn't one: empty, nan, inf). Python may write a tiny one as 1.5e-08
NavNum(v)
	{
	v := Trim(v)
	if (RegExMatch(v, "i)^([-+]?\d+(?:\.\d*)?|[-+]?\.\d+)(?:e([-+]?\d+))?$", num))
		return num2 = "" ? num1 + 0 : (num1 + 0.0) * (10.0 ** num2)
	return ""
	}
