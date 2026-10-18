; Dashboard.ahk - a window with the bot's statistics, what it sees right now, and a live log (every line
; of debug.log as it's written). AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Windows+2 or the tray menu shows / hides it; closing it only hides it. It opens on a monitor the game
; isn't on (if there is one) and remembers where you put it (dashboard.ini). It never takes the focus by
; itself - clicking into it does, and the walker waits while Wizard101 isn't the active window.
;
; The numbers come from the log lines (DashLog sees every DebugLog line) plus a few calls from the battle
; code: DashCast (a card was cast), DashSee (what the bot sees: the hand, enemies, your health...).

global DashHwnd := 0, DashCon := 0, DashShown := 0, DashPaused := 0, DashHeld := "", DashStart := 0
;Counts (rounds, passes, ...) and casts per card; what it sees ({key: text}); card names off PlayerStats.txt
global DashN := "", DashCasts := "", DashSees := "", DashNames := ""
global DashHead, DashStatText, DashSeeText, DashConsole, DashPauseBtn, DashHandsBtn

;Makes the window (shown unless dashboard.ini says it was hidden). Called once at start
DashInit()
	{
	DashN := {}, DashCasts := {}, DashSees := {}, DashStart := A_TickCount
	Gui, Dash:New, +Resize +MinSize620x460 +HwndDashHwnd, Wizard101 bot
	Gui, Dash:Color, 1B1D22, 111317
	Gui, Dash:Margin, 12, 10
	Gui, Dash:Font, s11 w600 cF2F2F2, Segoe UI
	Gui, Dash:Add, Text, x12 y10 w760 h22 vDashHead, Wizard101 bot
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y40 w340 h16, STATISTICS
	Gui, Dash:Add, Text, x372 y40 w400 h16, WHAT IT SEES
	Gui, Dash:Font, s9 w400 cDADADA, Consolas
	Gui, Dash:Add, Text, x12 y60 w350 h190 vDashStatText
	Gui, Dash:Add, Text, x372 y60 w400 h190 vDashSeeText
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y258 w200 h16, LOG
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Edit, x12 y278 w760 h300 ReadOnly -Wrap +HScroll +VScroll vDashConsole HwndDashCon
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y588 w110 h26 gDashPauseLog vDashPauseBtn, Pause log
	Gui, Dash:Add, Button, x130 y588 w80 h26 gDashClearLog, Clear
	Gui, Dash:Add, Button, x218 y588 w120 h26 gDashOpenLog, Open debug.log
	Gui, Dash:Add, Button, x346 y588 w150 h26 gDashWalkToggle, Walking on/off (F8)
	Gui, Dash:Add, Button, x504 y588 w140 h26 gDashFolder, Open bot folder
	Gui, Dash:Add, Button, x652 y588 w124 h26 gDashHandsToggle vDashHandsBtn, Wait for me: on
	;(the log so far: the lines written before the window was made)
	FileRead, earlier, %A_ScriptDir%\debug.log
	if (earlier != "")
		DashAppend(earlier)
	IniRead, shown, %A_ScriptDir%\dashboard.ini, window, shown, 1
	if (shown)
		DashShow()
	SetTimer, DashRefresh, 1000
	OnExit("DashOnExit")
	}

;The "Wait while I play" button's label
DashHandsShow(waitOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashHandsBtn, % "Wait for me: " (waitOn ? "on" : "off")
	}

;Shows the window where it was (else on a monitor the game isn't on), without taking the focus
DashShow()
	{
	IniRead, x, %A_ScriptDir%\dashboard.ini, window, x, %A_Space%
	IniRead, y, %A_ScriptDir%\dashboard.ini, window, y, %A_Space%
	IniRead, w, %A_ScriptDir%\dashboard.ini, window, w, 784
	IniRead, h, %A_ScriptDir%\dashboard.ini, window, h, 624
	;(w and h are at 100% display scaling; Windows' scaling makes the window that much bigger)
	dpi := A_ScreenDPI / 96
	if (x = "" || y = "" || !DashOnScreen(x + 40, y + 20))
		{
		;(the first monitor that doesn't hold the middle of the game window; else the bottom right)
		gx := GameLeft + GameW // 2, gy := GameTop + GameH // 2
		SysGet, count, MonitorCount
		x := "", y := ""
		Loop, %count%
			{
			SysGet, m, MonitorWorkArea, %A_Index%
			if (gx >= mLeft && gx < mRight && gy >= mTop && gy < mBottom)
				continue
			x := mLeft + 20, y := mTop + 20
			break
			}
		if (x = "")
			SysGet, m, MonitorWorkArea
		;(no bigger than that monitor)
		w := Min(w, Floor((mRight - mLeft - 40) / dpi) - 16), h := Min(h, Floor((mBottom - mTop - 40) / dpi) - 40)
		if (x = "")
			x := mRight - Round((w + 16) * dpi) - 20, y := mBottom - Round((h + 40) * dpi) - 20
		}
	Gui, Dash:Show, x%x% y%y% w%w% h%h% NoActivate
	DashShown := 1
	DashRefresh()
	}

DashOnScreen(x, y)
	{
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, Monitor, %A_Index%
		if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
			return true
		}
	return false
	}

;Windows+2 / tray menu
DashToggle()
	{
	if (!DashHwnd)
		return
	if (DashShown)
		{
		DashSavePlace()
		Gui, Dash:Hide
		DashShown := 0
		}
	else
		DashShow()
	IniWrite, %DashShown%, %A_ScriptDir%\dashboard.ini, window, shown
	}

DashSavePlace()
	{
	if (!DashShown || !DashHwnd)
		return
	WinGet, mm, MinMax, ahk_id %DashHwnd%
	if (mm != 0)
		return
	VarSetCapacity(rc, 16, 0)
	DllCall("GetClientRect", "Ptr", DashHwnd, "Ptr", &rc)
	WinGetPos, x, y,,, ahk_id %DashHwnd%
	if (x = "")
		return
	IniWrite, %x%, %A_ScriptDir%\dashboard.ini, window, x
	IniWrite, %y%, %A_ScriptDir%\dashboard.ini, window, y
	;(at 100% display scaling, as Gui Show takes them)
	IniWrite, % Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), %A_ScriptDir%\dashboard.ini, window, w
	IniWrite, % Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI), %A_ScriptDir%\dashboard.ini, window, h
	}

DashOnExit(reason, code)
	{
	DashSavePlace()
	}

;---- What goes in ----

;Every DebugLog line (with its time): onto the log, and into the counts
DashLog(line)
	{
	if (!DashHwnd)
		return
	DashParse(line)
	if (DashPaused)
		DashHeld .= line "`r`n"
	else
		DashAppend(line "`r`n")
	}

;Text onto the end of the log (the oldest half goes once it's long)
DashAppend(text)
	{
	text := StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "`r`n")
	len := DllCall("GetWindowTextLength", "Ptr", DashCon)
	if (len > 200000)
		{
		GuiControlGet, all, Dash:, DashConsole
		all := SubStr(all, len // 2)
		all := SubStr(all, InStr(all, "`n") + 1)
		GuiControl, Dash:, DashConsole, %all%
		len := DllCall("GetWindowTextLength", "Ptr", DashCon)
		}
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB1, "Ptr", len, "Ptr", len)      ; EM_SETSEL (the end)
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xC2, "Ptr", 0, "Str", text)      ; EM_REPLACESEL
	DllCall("SendMessage", "Ptr", DashCon, "UInt", 0xB7, "Ptr", 0, "Ptr", 0)         ; EM_SCROLLCARET
	}

;The counts and what it sees, from a log line ("HH:mm:ss text")
DashParse(line)
	{
	msg := SubStr(line, 10)
	if (InStr(msg, "Round start:") = 1)
		DashAdd("rounds"), DashSees.mode := "battle", DashSees.roundAt := A_TickCount, DashSees.plan := ""
	else if (msg = "Round done")
		DashSees.mode := "battle"
	else if (InStr(msg, "Out of battle") = 1)
		DashSees.mode := "out", DashSees.plan := ""
	else if (RegExMatch(msg, "^  saving pips for (\w+) \((\d+) pips, you have (\d+)\).*up to (\d+) round", m))
		DashAdd("pipsaves"), DashSees.plan := "saving pips for " DashShortName(m1) " (" m3 "/" m2 " pips)"
	else if (RegExMatch(msg, "^  (not saving pips|saved pips) .*", m))
		DashSees.plan := Trim(m)
	else if (RegExMatch(msg, "^  Click pass: found=1"))
		DashAdd("passes")
	else if (InStr(msg, "  Discarded ") = 1)
		DashAdd("discards")
	else if (RegExMatch(msg, "^  kill check: (.*) -> (.*)$", m))
		{
		DashSees.enemies := m1
		if (m2 != "no lethal hit")
			DashAdd("lethal")
		}
	else if (RegExMatch(msg, "^  pips=(-?\d+)", m))
		DashSees.pips := (m1 < 0 ? "?" : m1)
	else if (RegExMatch(msg, "^  own health: (\d+)/(\d+)", m))
		DashSees.hp := m1 "/" m2 " (" Round(100 * m1 / m2) "%, name plate)"
	else if (RegExMatch(msg, "school=(\w*) \| hitter=(\w*)", m))
		DashSees.school := m1, DashSees.hitter := m2
	else if (RegExMatch(msg, "^  learned a new card: (.*?)( \(picture:|$)", m))
		DashAdd("learned"), DashSees.lastLearned := m1
	else if (InStr(msg, "Potions: drank one") = 1)
		DashAdd("potions")
	else if (InStr(msg, "Potions: no potion left - going to buy some") = 1)
		DashAdd("potionRuns")
	else if (InStr(msg, "Reconnect: ") = 1)
		DashSees.reconnect := SubStr(msg, 12), DashSees.reconnectAt := A_TickCount
	else if (InStr(msg, "Pictures: ") = 1)
		DashSees.pictures := SubStr(msg, 11)
	else if (InStr(msg, "Stats: ") = 1)
		DashSees.stats := SubStr(msg, 8)
	else if (RegExMatch(msg, "^  (UseHeal|UseHit|UseBlade|UseTrap|UseOnSelf|UseOnHammer|UseConvert|Click) (\w+): found=1", m) && m2 != "pass")
		DashSees.lastTry := m2
	}

DashAdd(key, n := 1)
	{
	if (IsObject(DashN))
		DashN[key] := (DashN.HasKey(key) ? DashN[key] : 0) + n
	}

;A card went down (CastResult saw it cast)
DashCast(title)
	{
	if (!IsObject(DashCasts))
		return
	DashCasts[title] := (DashCasts.HasKey(title) ? DashCasts[title] : 0) + 1
	DashAdd("casts")
	DashSees.lastCast := DashCardName(title) " at " A_Hour ":" A_Min ":" A_Sec
	}

;What the bot sees (key: hand, you...)
DashSee(key, text)
	{
	if (IsObject(DashSees))
		DashSees[key] := text
	}

;The hand as the vision helper read it (/hand's answer, CardLearn.ahk): each card's name, ?<type> for one
;the bot doesn't know, * for a greyed-out one (not enough pips)
DashHandSeen(answer)
	{
	text := ""
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card")
			continue
		known := f[6]
		name := known = "" ? "?" (f[9] = "" ? "card" : f[9]) : InStr(known, "learned/") = 1 ? "learned" : DashShortName(SubStr(known, InStr(known, "/") + 1), SubStr(known, 1, InStr(known, "/") - 1))
		text .= (text = "" ? "" : ", ") name (f[8] = 1 ? "*" : "")
		}
	DashSee("hand", text)
	}

;A slot's card name alone (e.g. "Scarab"), else the slot
DashShortName(title, dir := "")
	{
	full := DashCardName(title, dir)
	return InStr(full, " (") ? SubStr(full, 1, InStr(full, " (") - 1) : full
	}

;A card's name for a slot (e.g. hit1 -> "Scarab"), from its comment in PlayerStats.txt; else the slot
DashCardName(title, dir := "")
	{
	if (!IsObject(DashNames) || A_TickCount - DashNames._at > 60000)
		{
		DashNames := {_at: A_TickCount}
		prevKey := ""
		Loop, Read, %A_ScriptDir%\PlayerStats.txt
			{
			line := A_LoopReadLine
			if (RegExMatch(line, "^\s*([\w.]+)\s*:[^;]*;\s*(.*)$", m))
				key := m1, comment := m2
			else if (prevKey != "" && RegExMatch(line, "^\s*;\s*\^\s*(.*)$", m))
				key := prevKey, comment := m1
			else
				{
				prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", m) ? m1 : ""
				continue
				}
			prevKey := RegExMatch(line, "^\s*([\w.]+)\s*:", k) ? k1 : ""
			comment := RegExReplace(comment, "i)^learned \d+:\s*")
			if (RegExMatch(comment, "^([A-Z][A-Za-z']*(?: [A-Z][A-Za-z']*)*)", n) && !DashNames.HasKey(key))
				DashNames[key] := n1
			}
		}
	key := Format("{:L}", (dir != "" && dir != "resources" ? dir : hitschool) "." title)
	if (DashNames.HasKey(key))
		return DashNames[key] " (" title ")"
	key := Format("{:L}", title)
	return DashNames.HasKey(key) ? DashNames[key] " (" title ")" : title
	}

;---- Showing it ----

DashRefresh()
	{
	if (!DashShown || !DashHwnd)
		return
	up := (A_TickCount - DashStart) // 1000
	upText := Format("{:02}:{:02}:{:02}", up // 3600, Mod(up // 60, 60), Mod(up, 60))
	;What it's doing
	if (PotionRecording)
		doing := "Recording potion buying"
	else if (WkNoteKind != "")
		doing := "Needs you: " WkNoteTitle
	else if (PlayerActive)
		doing := "You're playing - the bot waits"
	else if (DashSees.mode = "battle" && A_TickCount - DashSees.roundAt < 120000)
		doing := "In battle (round " DashN.rounds ")"
	else if (!Walking)
		doing := "Walking off (F8)"
	else if (StatusText != "")
		doing := StatusText
	else
		doing := "Watching"
	DashSet("DashHead", "Wizard101 bot  |  " SubStr(doing, 1, 70) "  |  up " upText "  |  vision " (VisionOn ? "on" : "off"))
	;Statistics
	n := DashN
	casts := ""
	for title, count in DashCasts
		casts .= "`n   " SubStr(DashCardName(title) "                              ", 1, 25) Format("{:6}", count)
	s := "Battles          " DashNum(battles) "`n"
		. "Rounds played    " DashNum(n.rounds) "`n"
		. "Cards cast       " DashNum(n.casts) casts "`n"
		. "Passed           " DashNum(n.passes) "`n"
		. "Discarded        " DashNum(n.discards) "`n"
		. "Kill-check hits  " DashNum(n.lethal) "`n"
		. "Rounds saving pips" SubStr(DashNum(n.pipsaves), 2) "`n"
		. "Potions drunk    " DashNum(n.potions) "   (buying runs: " (n.potionRuns = "" ? 0 : n.potionRuns) ")`n"
		. "Cards learned    " DashNum(n.learned)
	DashSet("DashStatText", s)
	;What it sees
	see := DashSees
	zone := IsFunc("WalkZone") ? Func("WalkZone").Call() : ""
	t := "You          " (see.hp != "" ? see.hp : "?") (see.mana != "" ? ", mana " see.mana : "") ", pips " (see.pips != "" ? see.pips : "?") "`n"
		. "School       " (see.school != "" ? see.school : "?") "  (hitting with " (see.hitter != "" ? see.hitter : "?") ")`n"
		. "Hand         " DashCut(see.hand != "" ? see.hand : "-") "`n"
		. "Enemies      " DashCut(see.enemies != "" ? see.enemies : "-") "`n"
		. "Plan         " DashCut(see.plan != "" ? see.plan : "-") "`n"
		. "Last cast    " (see.lastCast != "" ? see.lastCast : "-") "`n"
		. "Zone         " DashCut(zone != "" ? zone : "?") "`n"
		. "Walker       " DashCut(StatusText != "" ? StatusText : "-") "`n"
		. "Pictures     " DashCut(see.pictures != "" ? RegExReplace(see.pictures, " - card area.*") : "?") "`n"
		. "Last learned " DashCut(see.lastLearned != "" ? see.lastLearned : "-")
		. (see.reconnect != "" && A_TickCount - see.reconnectAt < 600000 ? "`nReconnect    " DashCut(see.reconnect) : "")
	DashSet("DashSeeText", t)
	}

;A value cut to what fits the "What it sees" column (its width, past the 13-letter label; Consolas 9 is
;about 7 px a letter - the width is in 100%-scaling pixels too)
DashCut(text)
	{
	GuiControlGet, pos, Dash:Pos, DashSeeText
	fit := Max(20, Floor(posW / 7) - 14)
	return StrLen(text) > fit ? SubStr(text, 1, fit - 1) "~" : text
	}

;A count, right-aligned (blank = 0)
DashNum(v)
	{
	return Format("{:6}", v = "" ? 0 : v)
	}

;Sets a control's text only when it changed (no flicker)
DashSet(control, text)
	{
	static last := {}
	if (last[control] == text)
		return
	last[control] := text
	GuiControl, Dash:, %control%, %text%
	}

DashRefresh:
	DashRefresh()
	return

DashPauseLog:
	DashPaused := !DashPaused
	GuiControl, Dash:, DashPauseBtn, % DashPaused ? "Resume log" : "Pause log"
	if (!DashPaused && DashHeld != "")
		DashAppend(DashHeld), DashHeld := ""
	return

DashClearLog:
	GuiControl, Dash:, DashConsole,
	return

DashOpenLog:
	Run, notepad.exe "%A_ScriptDir%\debug.log"
	return

DashWalkToggle:
	if (IsFunc("WalkToggle"))
		Func("WalkToggle").Call()
	return

DashFolder:
	Run, %A_ScriptDir%
	return

;"Wait while I play" on/off (HandsOffToggle in Autofarmer.ahk)
DashHandsToggle:
	if (IsFunc("HandsOffToggle"))
		Func("HandsOffToggle").Call()
	return

DashGuiClose:
	DashToggle()
	return

DashGuiSize:
	if (A_EventInfo = 1)
		return
	GuiControl, Dash:Move, DashHead, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DashSeeText, % "w" A_GuiWidth - 384
	GuiControl, Dash:Move, DashConsole, % "w" A_GuiWidth - 24 " h" A_GuiHeight - 324
	for each, b in [["Pause log", 12], ["Clear", 130], ["Open debug.log", 218], ["Walking on/off (F8)", 346], ["Open bot folder", 504]]
		GuiControl, Dash:Move, % b[1], % "y" A_GuiHeight - 36
	GuiControl, Dash:Move, DashPauseBtn, % "y" A_GuiHeight - 36
	GuiControl, Dash:Move, DashHandsBtn, % "y" A_GuiHeight - 36
	return

;(Windows+2 is in Autofarmer.ahk: it shows the dev-mode info box in dev mode)
