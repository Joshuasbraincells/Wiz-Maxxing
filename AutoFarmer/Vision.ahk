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
; Px(), hitschool, DebugLog().

global VisionOn := 0, VisionPid := 0, VisionFails := 0, VisionCards := "", VisionCardsAt := 0, VisionCardsKey := "", VisionMissing := ","
;The helper's folder ("" = vision\ next to the script) and port (tests use another one, so they don't stop
;the bot's own helper)
global VisionDir := "", VisionPort := 47128

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
;the helper is left alone - ImageSearch from then on)
VisionGet(path, timeoutMs := 1500)
	{
	;(the helper's gone: no point asking - a closed port costs 2 s)
	if (VisionOn && VisionPid)
		{
		Process, Exist, %VisionPid%
		if (!ErrorLevel)
			{
			VisionOn := 0
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
				VisionFails++
				throw "no answer in " timeoutMs " ms"
				}
			Sleep, 10
			}
		text := req.ResponseText
		if (req.Status != 200 || SubStr(text, 1, 3) = "ERR")
			throw text
		VisionFails := 0
		return text = "" ? " " : text
		}
	catch e
		{
		if (VisionOn && ++VisionFails >= 3)
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
	for each, name in ["sharpen", "potent", "blade3", "blade4", "trap3", "trap4", "tower", "reshuffle", "feint", "epic", "colossal", "gargantuan", "elementalblade", "elementaltrap", "spiritblade", "spirittrap"]
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
