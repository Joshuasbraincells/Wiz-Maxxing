; Dashboard.ahk - a window with the bot's statistics, what it sees right now, and a live log (every line
; of debug.log as it's written). AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Windows+2 or the tray menu shows / hides it; closing it only hides it. It opens on a monitor the game
; isn't on (if there is one) and remembers where you put it (dashboard.ini). It never takes the focus by
; itself - clicking into it does, and the walker waits while Wizard101 isn't the active window.
;
; The numbers come from the log lines (DashLog sees every DebugLog line) plus a few calls from the battle
; code: DashCast (a card was cast), DashSee (what the bot sees: the hand, enemies, your health...).
;
; Its Map button (or the tray menu) opens a second window: a top-down picture of the zone the wizard is in,
; drawn by the vision helper (/navmap) - see "The map" below.

global DashHwnd := 0, DashCon := 0, DashShown := 0, DashPaused := 0, DashHeld := "", DashStart := 0
;Counts (rounds, passes, ...) and casts per card; what it sees ({key: text}); card names off PlayerStats.txt
global DashN := "", DashCasts := "", DashSees := "", DashNames := ""
global DashHead, DashStatText, DashSeeText, DashConsole, DashPauseBtn, DashHandsBtn
;CPU and RAM in use, on the STATISTICS row (DashUsage)
global DashUsageText
;The Settings button (Settings.ahk), left of the Map button
global DashCfgBtn
;The Updates button, at the right end of the heading row (says whether a newer version is out: UpdState); Report a
;bug left of it (BugReport.ahk)
global DashUpdBtn, DashUpdBusy, DashBugBtn
;Where the tabs' inside starts in the window (GuiControl Move places a tab's controls from there: DashGuiSize)
global DashTabOX, DashTabOY, DashTabOW, DashTabOH
;The bottom row's other buttons (they share the window's width)
global DashClearBtn, DashLogBtn, DashWalkBtn, DashFolderBtn, DashBotBtn
;The Hand section: its heading, and a picture and a label for each of up to 7 cards
global DashLearnBtn, DashHandHead, DashCardPic1, DashCardPic2, DashCardPic3, DashCardPic4, DashCardPic5, DashCardPic6, DashCardPic7
global DashCardTxt1, DashCardTxt2, DashCardTxt3, DashCardTxt4, DashCardTxt5, DashCardTxt6, DashCardTxt7
;The map window: the button, the window, its picture and line; the request it's waiting for (kind: map / nav,
;sent at); when it last asked for a picture and at what size (screen pixels); the picture's file; what went
;wrong with the picture; /nav's last answer; when the picture shown was made
global DashMapBtn, DashMapHwnd, DashMapPic, DashMapPicH, DashMapText, DashMapShown, DashMapReq, DashMapKind, DashMapReqAt
global DashMapAt, DashMapW, DashMapH, DashMapFile, DashMapNote, DashMapNav, DashMapPicAt

;Makes the window (shown unless dashboard.ini says it was hidden). Called once at start
DashInit()
	{
	DashN := {}, DashCasts := {}, DashSees := {}, DashStart := A_TickCount
	Gui, Dash:New, +Resize +MinSize740x640 +HwndDashHwnd, % "Wizard101 bot " BotVersion()
	Gui, Dash:Color, 1B1D22, 111317
	Gui, Dash:Margin, 12, 10
	Gui, Dash:Font, s11 w600 cF2F2F2, Segoe UI
	Gui, Dash:Add, Text, x12 y10 w526 h22 vDashHead, % BotVersion()
	;(the Updates button: the heading row's right end - DashGuiSize keeps it there)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x544 y7 w88 h24 gDashBugButton vDashBugBtn, Report a bug
	Gui, Dash:Add, Button, x640 y7 w136 h24 gDashUpdButton vDashUpdBtn, Check for updates
	;(the button says "Checking..." a while after a click: DashUpdBusy)
	;Three tabs: Bot (statistics, what it sees, the hand, the log), Dungeons (Dungeons.ahk) and Spells (the cards
	;the bot learned by itself: Spells.ahk)
	Gui, Dash:Font, s9 w600 cF2F2F2, Segoe UI
	Gui, Dash:Add, Tab3, x6 y36 w772 h764 +Buttons -Theme vDashTabs, Bot|Dungeons|Spells
	Gui, Dash:Tab, 1
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w86 h16, STATISTICS
	Gui, Dash:Font, s8 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x100 y69 w270 h16 vDashUsageText, CPU / RAM ...
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x372 y68 w150 h16, WHAT IT SEES
	;(the Map button at the right end of that row; DashGuiSize keeps it there)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x618 y64 w76 h22 gDashSettingsButton vDashCfgBtn, Settings
	Gui, Dash:Add, Button, x700 y64 w76 h22 gDashMapButton vDashMapBtn, Map
	Gui, Dash:Font, s9 w400 cDADADA, Consolas
	Gui, Dash:Add, Text, x12 y88 w350 h190 vDashStatText
	Gui, Dash:Add, Text, x372 y88 w400 h190 vDashSeeText
	;The hand: each card as the bot saw it this round, and what it took it for (DashHandSeen)
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y286 w630 h16 vDashHandHead, HAND - nothing read yet (once a round in battle)
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x646 y280 w130 h24 gDashLearnAll vDashLearnBtn, Learn every card
	Gui, Dash:Font, s8 w400 cDADADA, Segoe UI
	Loop, 7
		{
		cx := 12 + (A_Index - 1) * 72
		Gui, Dash:Add, Picture, x%cx% y306 w58 h97 Hidden vDashCardPic%A_Index%
		Gui, Dash:Add, Text, x%cx% y405 w66 h28 Hidden vDashCardTxt%A_Index%
		}
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y438 w200 h16, LOG
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Edit, x12 y458 w760 h300 ReadOnly -Wrap +HScroll +VScroll vDashConsole HwndDashCon
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y768 w110 h26 gDashPauseLog vDashPauseBtn, Pause log
	Gui, Dash:Add, Button, x130 y768 w80 h26 gDashClearLog vDashClearBtn, Clear
	Gui, Dash:Add, Button, x218 y768 w120 h26 gDashOpenLog vDashLogBtn, Open debug.log
	Gui, Dash:Add, Button, x346 y768 w120 h26 gDashBotToggle vDashBotBtn, Bot: on (F6)
	Gui, Dash:Add, Button, x346 y768 w150 h26 gDashWalkToggle vDashWalkBtn, Walking on/off (F8)
	Gui, Dash:Add, Button, x504 y768 w140 h26 gDashFolder vDashFolderBtn, Open bot folder
	Gui, Dash:Add, Button, x652 y768 w124 h26 gDashHandsToggle vDashHandsBtn, Wait for me: on
	;The Dungeons tab: a run recorded once, walked again and again (Dungeons.ahk)
	Gui, Dash:Tab, 2
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w400 h16, DUNGEON FARMING
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x12 y88 w760 h48 vDgHelp, Record a run once: stand outside the dungeon by its sigil, click Record a run and play it - X at the sigil, to the boss (fighting on the way), back out to where you started - then press F9. Pick it and click Run: the bot walks the same way, presses X where you did, fights every battle (the bot on, F6) and starts over. F8 pauses it.
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y142 w120 h26 gDgRecordClick vDgRecBtn, Record a run
	Gui, Dash:Add, Button, x138 y142 w150 h26 gDgRecStopClick vDgRecStopBtn Disabled, Stop recording (F9)
	Gui, Dash:Add, Button, x300 y142 w90 h26 gDgRunClick vDgRunBtn, Run
	Gui, Dash:Add, Button, x396 y142 w90 h26 gDgStopClick vDgStopBtn Disabled, Stop run
	Gui, Dash:Add, Button, x498 y142 w90 h26 gDgDeleteClick vDgDelBtn, Delete
	Gui, Dash:Add, Button, x594 y142 w110 h26 gDgFolderClick vDgFolderBtn, Open folder
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x12 y182 w44 h18 vDgTimesLabel, Run it
	Gui, Dash:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, Dash:Add, Edit, x58 y179 w60 h22 Number Right vDgTimes, 0
	Gui, Dash:Add, UpDown, vDgTimesUD Range0-9999 0x80, 0
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x126 y182 w220 h18 vDgTimesNote, times (0 = until you stop it)
	Gui, Dash:Add, Checkbox, x360 y182 w300 h18 vDgAvoid, Keep away from mobs on the way
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y208 w760 h52 vDgStatus, Not running.
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y262 w760 h526 vDgList gDgListEvent AltSubmit -Multi Background111317 cDADADA, Run|Steps|Zones|X|Battles|Recorded|File
	LV_ModifyCol(1, 300), LV_ModifyCol(2, "60 Integer"), LV_ModifyCol(3, "60 Integer"), LV_ModifyCol(4, "50 Integer"), LV_ModifyCol(5, "70 Integer")
	LV_ModifyCol(6, 140), LV_ModifyCol(7, 0)
	;The Spells tab: the cards the bot learned by itself, and your corrections (Spells.ahk)
	Gui, Dash:Tab, 3
	Gui, Dash:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, Dash:Add, Text, x12 y68 w400 h16, LEARNED SPELLS
	Gui, Dash:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Dash:Add, Text, x12 y88 w760 h32 vSpHelp, Every card the bot learned by itself, and what it took it for. Pick one to see it. Change kind or Edit puts one right (applied out of battle; the learner never changes what you set). Forget: out of the list.
	Gui, Dash:Font, s9 w400 c000000, Segoe UI
	Gui, Dash:Add, Button, x12 y124 w100 h26 gSpKindClick vSpKindBtn, Change kind...
	Gui, Dash:Add, Button, x118 y124 w64 h26 gSpEditClick vSpEditBtn, Edit...
	Gui, Dash:Add, Button, x188 y124 w64 h26 gSpForgetClick vSpForgetBtn, Forget
	Gui, Dash:Add, Button, x258 y124 w96 h26 gSpHoldClick vSpHoldBtn, Never discard
	Gui, Dash:Add, Button, x360 y124 w92 h26 gSpPicClick vSpPicBtn, Show picture
	Gui, Dash:Add, Button, x458 y124 w86 h26 gSpFolderClick vSpFolderBtn, Open folder
	Gui, Dash:Add, Button, x550 y124 w100 h26 gSpMovedClick vSpMovedBtn, Moved away...
	Gui, Dash:Add, Button, x656 y124 w66 h26 gSpRefreshClick vSpRefreshBtn, Refresh
	Gui, Dash:Font, s9 w400 cB9E2B9, Consolas
	Gui, Dash:Add, Text, x12 y156 w760 h30 vSpStatus
	Gui, Dash:Font, s9 w400 cDADADA, Segoe UI
	Gui, Dash:Add, ListView, x12 y190 w612 h598 vSpList gSpListEvent AltSubmit Background111317 cDADADA, Name|Kind|School|Pips|Value|In use|Text read|TC|Learned|Set|Id
	LV_ModifyCol(1, 96), LV_ModifyCol(2, 84), LV_ModifyCol(3, 50), LV_ModifyCol(4, 34), LV_ModifyCol(5, 66), LV_ModifyCol(6, 112)
	LV_ModifyCol(7, 100), LV_ModifyCol(8, 26), LV_ModifyCol(9, 96), LV_ModifyCol(10, 50), LV_ModifyCol(11, 0)
	;(the spell picked: its picture, and what the bot took it for under it)
	Gui, Dash:Add, Picture, x632 y190 w140 h233 Hidden vSpPreview
	Gui, Dash:Font, s8 w400 cDADADA, Segoe UI
	Gui, Dash:Add, Text, x632 y428 w140 h360 vSpPreviewTxt, Pick a spell to see it.
	Gui, Dash:Tab
	;(the log so far: the lines written before the window was made)
	FileRead, earlier, %A_ScriptDir%\debug.log
	if (earlier != "")
		DashAppend(earlier)
	IniRead, shown, %A_ScriptDir%\dashboard.ini, window, shown, 1
	;(the Dungeons tab's list and status; the Spells tab's)
	DgListFill()
	DgShow()
	SpInit()
	if (shown)
		DashShow()
	SetTimer, DashRefresh, 1000
	OnExit("DashOnExit")
	;(the map: back if it was open when the bot stopped)
	IniRead, mapShown, %A_ScriptDir%\dashboard.ini, map, shown, 0
	if (mapShown = 1)
		DashMapShow()
	}

;The "Learn every card" button's label
DashLearnShow(learnOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashLearnBtn, % learnOn ? "Learning... (stop)" : "Learn every card"
	}

;The bot on/off button's label
DashBotShow(isOn)
	{
	if (DashHwnd)
		GuiControl, Dash:, DashBotBtn, % "Bot: " (isOn ? "on" : "off") " (F6)"
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
	IniRead, h, %A_ScriptDir%\dashboard.ini, window, h, %A_Space%
	IniRead, layout, %A_ScriptDir%\dashboard.ini, window, layout, 1
	;(the Hand section came in above the log, then the tabs: a window saved before that is that much taller now)
	h := (h = "") ? 804 : (layout < 2 ? h + 180 : layout < 3 ? h + 28 : h)
	;(w and h are at 100% display scaling; Windows' scaling makes the window that much bigger)
	dpi := A_ScreenDPI / 96
	if (x = "" || y = "" || !DashOnScreen(x + 40, y + 20))
		{
		;(the first monitor that doesn't hold the middle of the game window; else the bottom right)
		spare := DashSpareMonitor(mLeft, mTop, mRight, mBottom)
		;(no bigger than that monitor)
		w := Min(w, Floor((mRight - mLeft - 40) / dpi) - 16), h := Min(h, Floor((mBottom - mTop - 40) / dpi) - 40)
		x := spare ? mLeft + 20 : mRight - Round((w + 16) * dpi) - 20
		y := spare ? mTop + 20 : mBottom - Round((h + 40) * dpi) - 20
		}
	DashFitHeight(x, y, h)
	Gui, Dash:Show, x%x% y%y% w%w% h%h% NoActivate
	DashShown := 1
	DashRefresh()
	}

;The work area of the first monitor that doesn't hold the middle of the game window: true; else the main
;monitor's and false
DashSpareMonitor(ByRef mLeft, ByRef mTop, ByRef mRight, ByRef mBottom)
	{
	gx := GameLeft + GameW // 2, gy := GameTop + GameH // 2
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, MonitorWorkArea, %A_Index%
		if (!(gx >= mLeft && gx < mRight && gy >= mTop && gy < mBottom))
			return true
		}
	SysGet, m, MonitorWorkArea
	return false
	}

;The work area of the monitor that holds x, y (else the main monitor's)
DashMonitorAt(x, y, ByRef mLeft, ByRef mTop, ByRef mRight, ByRef mBottom)
	{
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, MonitorWorkArea, %A_Index%
		if (x >= mLeft && x < mRight && y >= mTop && y < mBottom)
			return
		}
	SysGet, m, MonitorWorkArea
	}

;h (a window's inside, at 100% display scaling) cut so a window at x, y fits on the monitor it's on
DashFitHeight(x, y, ByRef h)
	{
	dpi := A_ScreenDPI / 96
	SysGet, count, MonitorCount
	Loop, %count%
		{
		SysGet, m, MonitorWorkArea, %A_Index%
		if (x + 40 >= mLeft && x + 40 < mRight && y + 20 >= mTop && y + 20 < mBottom)
			h := Min(h, Floor((mBottom - y - 20) / dpi) - 40)
		}
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
	if (DashSaveWin(DashHwnd, "window"))
		IniWrite, 3, %A_ScriptDir%\dashboard.ini, window, layout
	}

;Saves where a window is in dashboard.ini [section]: x, y on the screen, and its inside's width and height at
;100% display scaling (as Gui Show takes them). Not while it's minimized or maximized (false)
DashSaveWin(hwnd, section)
	{
	WinGet, mm, MinMax, ahk_id %hwnd%
	if (mm != 0)
		return false
	VarSetCapacity(rc, 16, 0)
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rc)
	WinGetPos, x, y,,, ahk_id %hwnd%
	if (x = "")
		return false
	IniWrite, %x%, %A_ScriptDir%\dashboard.ini, %section%, x
	IniWrite, %y%, %A_ScriptDir%\dashboard.ini, %section%, y
	IniWrite, % Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), %A_ScriptDir%\dashboard.ini, %section%, w
	IniWrite, % Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI), %A_ScriptDir%\dashboard.ini, %section%, h
	return true
	}

DashOnExit(reason, code)
	{
	DashSavePlace()
	if (DashMapShown && DashMapHwnd)
		DashSaveWin(DashMapHwnd, "map")
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
		DashAdd("rounds"), DashSees.mode := "battle", DashSees.roundAt := A_TickCount, DashSees.plan := "", DashSees.threat := ""
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
	else if (InStr(msg, "  fleeing: ") = 1)
		DashAdd("flees")
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
;the bot doesn't know, * for a greyed-out one (not enough pips). A box the helper says isn't a card (field 15 = 0:
;the deck's back, the round's timer, the floor) is left out
DashHandSeen(answer)
	{
	text := "", n := 0, box := 0, notCards := 0
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card")
			continue
		;(the helper saves every box's picture, generated\hand\hand<box>.png)
		box += 1
		if (f.Length() >= 15 && f[15] = "0")
			{
			notCards += 1
			continue
			}
		known := f[6]
		name := known = "" ? "?" (f[9] = "" ? "card" : f[9]) : InStr(known, "learned/") = 1 ? DashLearnedName(SubStr(known, 9)) : DashShortName(SubStr(known, InStr(known, "/") + 1), SubStr(known, 1, InStr(known, "/") - 1))
		text .= (text = "" ? "" : ", ") name (f[8] = 1 ? "*" : "")
		n += 1
		if (n <= 7)
			DashHandCard(n, name, known, f[8] = 1, f[11], box)
		}
	;(the slots past the hand: empty)
	Loop, % 7 - Min(n, 7)
		{
		slot := n + A_Index
		GuiControl, Dash:Hide, DashCardPic%slot%
		GuiControl, Dash:Hide, DashCardTxt%slot%
		}
	FormatTime, now, , HH:mm:ss
	GuiControl, Dash:, DashHandHead, % "HAND " now " (" n " card" (n = 1 ? "" : "s") (notCards ? ", " notCards " not a card" : "") ")   white known   yellow new to it   grey can't cast"
	DashSee("hand", text)
	}

;A learned card's name in the hand: the one you gave it on the Spells tab, else "learned"
DashLearnedName(id)
	{
	c := IsFunc("LearnCardOf") ? Func("LearnCardOf").Call(id) : ""
	return (IsObject(c) && c.name != "") ? c.name : "learned"
	}

;One card of the Hand section (n: its place there): its picture as the bot saw it (generated\hand\hand<box>.png,
;saved by the vision helper - box: the helper's count, non-cards too) and under it what it took it for and the pips it
;read - white known, yellow unknown, grey greyed out
DashHandCard(n, name, known, grey, pips, box := "")
	{
	if (!DashHwnd)
		return
	pic := A_ScriptDir "\generated\hand\hand" (box = "" ? n : box) ".png"
	if (FileExist(pic))
		{
		;(the picture control is sized for 100% display scaling; the picture is loaded at its real size)
		GuiControl, Dash:, DashCardPic%n%, % "*w" Round(58 * A_ScreenDPI / 96) " *h" Round(97 * A_ScreenDPI / 96) " " pic
		GuiControl, Dash:Show, DashCardPic%n%
		}
	else
		GuiControl, Dash:Hide, DashCardPic%n%
	colour := grey ? "8A8A8A" : known = "" ? "F2C14E" : "E8E8E8"
	GuiControl, Dash:+c%colour%, DashCardTxt%n%
	GuiControl, Dash:, DashCardTxt%n%, % SubStr(name, 1, 12) "`n" (pips = "" ? "? pips" : pips " pip" (pips = 1 ? "" : "s")) (grey ? " - grey" : "")
	GuiControl, Dash:Show, DashCardTxt%n%
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
	;(a dungeon run or recording: its line on the Dungeons tab)
	if (IsObject(DgRun) || DgRecording)
		DgShow()
	if (!DashShown || !DashHwnd)
		return
	;(the Spells tab's list: again when the catalog changed - LearnSave - or a correction was applied)
	if (SpDirty)
		SpListFill()
	up := (A_TickCount - DashStart) // 1000
	upText := Format("{:02}:{:02}:{:02}", up // 3600, Mod(up // 60, 60), Mod(up, 60))
	;What it's doing
	if (!BotOn)
		doing := BotEverOn ? "Off - F6 turns the bot on" : "Standby - press F6 to start the bot"
	else if (PotionRecording)
		doing := "Recording potion buying"
	else if (LearnAll)
		doing := "Learning every card (" (IsObject(LearnedCards) ? LearnedCards.Length() - LearnAllFrom : 0) " new so far)"
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
	;(the window's title says "Wizard101 bot")
	DashSet("DashHead", BotVersion() "  |  up " upText "  |  vision " (VisionOn ? "on" : "off") "  |  " SubStr(doing, 1, 70))
	;The version, and whether a newer one is out (the last look-up: UpdState) - on the Updates button too
	upd := UpdState()
	verNote := upd.newer ? upd.latest " is out" : upd.err != "" ? "can't check" : upd.latest != "" ? "up to date" : "not checked yet"
	;(why it can't check: in the log, once each time it changes)
	static updErrSaid := ""
	if (upd.err != updErrSaid)
		{
		updErrSaid := upd.err
		if (upd.err != "")
			DebugLog("Updates: can't check for a newer version - " upd.err)
		}
	if (DashUpdBusy && A_TickCount - DashUpdBusy > 10000)
		{
		DashUpdBusy := 0
		GuiControl, Dash:Enable, DashUpdBtn
		}
	DashSet("DashUpdBtn", DashUpdBusy ? "Checking..." : upd.newer ? "Update to " upd.latest : (upd.err = "" && upd.latest != "") ? "Up to date" : "Check for updates")
	;Statistics
	n := DashN
	casts := ""
	for title, count in DashCasts
		casts .= "`n   " SubStr(DashCardName(title) "                              ", 1, 25) Format("{:6}", count)
	;(the cards cast one by one last: what the box's height cuts off)
	s := "Version          " (BotVersion() = "" ? "?" : BotVersion()) " - " verNote "`n"
		. "Battles          " DashNum(battles) "`n"
		. "Rounds played    " DashNum(n.rounds) "`n"
		. "Passed           " DashNum(n.passes) "   (fled: " (n.flees = "" ? 0 : n.flees) ")`n"
		. "Discarded        " DashNum(n.discards) "`n"
		. "Kill-check hits  " DashNum(n.lethal) "`n"
		. "Rounds saving pips" SubStr(DashNum(n.pipsaves), 2) "`n"
		. "Potions drunk    " DashNum(n.potions) "   (buying runs: " (n.potionRuns = "" ? 0 : n.potionRuns) ")`n"
		. "Cards learned    " DashNum(n.learned) "`n"
		. "Cards cast       " DashNum(n.casts) casts
	DashSet("DashStatText", s)
	DashSet("DashUsageText", DashUsage())
	;What it sees
	see := DashSees
	zone := IsFunc("WalkZone") ? Func("WalkZone").Call() : ""
	t := "You          " (see.hp != "" ? see.hp : "?") (see.mana != "" ? ", mana " see.mana : "") ", pips " (see.pips != "" ? see.pips : "?") "`n"
		. "School       " (see.school != "" ? see.school : "?") "  (hitting with " (see.hitter != "" ? see.hitter : "?") ")`n"
		. "Hand         " DashCut(see.hand != "" ? see.hand : "-") "`n"
		. "Enemies      " DashCut(see.enemies != "" ? see.enemies : "-") "`n"
		. "Threat       " DashCut(see.threat != "" ? see.threat : "-") "`n"
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

;---- The map ----
;
;A window with a top-down picture of the zone the wizard is in, drawn by the vision helper (/navmap: the
;floor, what's in the way, the game's path, the wizard as an arrow, where the arrow points, the goal), and
;under it a line off /nav: the zone, where the wizard is, how far the goal is. Read from the game's memory by
;the helper (read-only). A new picture once a second while it's shown; closing it only hides it (and stops
;asking). Its requests don't wait for the answer - the next tick (every 250 ms) picks it up - so the bot never
;waits for the map. It never takes the focus by itself. Its place is kept in dashboard.ini [map].

;The Map button / tray menu: shows or hides it
DashMapToggle()
	{
	if (DashMapShown)
		DashMapHide()
	else
		DashMapShow()
	IniWrite, % DashMapShown ? 1 : 0, %A_ScriptDir%\dashboard.ini, map, shown
	}

;Makes the window (hidden), the first time it's shown
DashMapMake()
	{
	DashMapShown := 0, DashMapReq := "", DashMapKind := "", DashMapAt := 0, DashMapW := 0, DashMapH := 0
	DashMapNote := "", DashMapNav := "", DashMapPicAt := ""
	;(in the temp folder: it's rewritten every second, which OneDrive would keep uploading)
	DashMapFile := A_Temp "\Wizard101 bot map\navmap.png"
	FileCreateDir, %A_Temp%\Wizard101 bot map
	FileCreateDir, %A_ScriptDir%\generated
	Gui, Map:+Resize +MinSize320x240 +HwndDashMapHwnd
	Gui, Map:Color, 1B1D22, 111317
	Gui, Map:Margin, 8, 8
	Gui, Map:Add, Picture, x8 y8 w624 h460 vDashMapPic HwndDashMapPicH
	Gui, Map:Font, s9 w400 cDADADA, Consolas
	;(one line: cut with "..." when it's longer than the window is wide, not wrapped)
	Gui, Map:Add, Text, x8 y474 w624 h18 +0x400C vDashMapText, Asking the vision helper for the map...
	}

;Shows it where it was (else beside the dashboard), without taking the focus, and starts asking
DashMapShow()
	{
	if (!DashMapHwnd)
		DashMapMake()
	IniRead, x, %A_ScriptDir%\dashboard.ini, map, x, %A_Space%
	IniRead, y, %A_ScriptDir%\dashboard.ini, map, y, %A_Space%
	IniRead, w, %A_ScriptDir%\dashboard.ini, map, w, 640
	IniRead, h, %A_ScriptDir%\dashboard.ini, map, h, 500
	if (x = "" || y = "" || !DashOnScreen(x + 40, y + 20))
		DashMapPlace(x, y, w, h)
	DashFitHeight(x, y, h)
	Gui, Map:Show, x%x% y%y% w%w% h%h% NoActivate, % "Wizard101 bot " BotVersion() " - map"
	DashMapShown := 1, DashMapAt := 0
	SetTimer, DashMapTick, 250
	}

;Hides it (keeping its place) and stops asking
DashMapHide()
	{
	if (!DashMapHwnd)
		return
	if (DashMapShown)
		DashSaveWin(DashMapHwnd, "map")
	Gui, Map:Hide
	DashMapShown := 0
	SetTimer, DashMapTick, Off
	if (IsObject(DashMapReq))
		try DashMapReq.Abort()
	DashMapReq := ""
	}

;Where it goes the first time (w, h: its inside at 100% display scaling): beside the dashboard - right of it,
;below, left or above, whichever fits on the dashboard's monitor - else that monitor's bottom right (the
;spare monitor's, when the dashboard is hidden)
DashMapPlace(ByRef x, ByRef y, w, h)
	{
	dpi := A_ScreenDPI / 96
	ow := Round(w * dpi) + 16, oh := Round(h * dpi) + 40
	if (DashShown && DashHwnd)
		{
		WinGetPos, dx, dy, dw, dh, ahk_id %DashHwnd%
		DashMonitorAt(dx + dw // 2, dy + dh // 2, mLeft, mTop, mRight, mBottom)
		for each, p in [[dx + dw + 8, dy], [dx, dy + dh + 8], [dx - ow - 8, dy], [dx, dy - oh - 8]]
			if (p[1] >= mLeft && p[2] >= mTop && p[1] + ow <= mRight && p[2] + oh <= mBottom)
				{
				x := p[1], y := p[2]
				return
				}
		}
	else
		DashSpareMonitor(mLeft, mTop, mRight, mBottom)
	x := Max(mLeft, mRight - ow - 20), y := Max(mTop, mBottom - oh - 20)
	}

;Every 250 ms while it's shown: picks up the answer it's waiting for; else asks for a new picture once a
;second (at once when the window's size changed)
DashMapTick()
	{
	if (!DashMapShown)
		{
		SetTimer, DashMapTick, Off
		return
		}
	if (IsObject(DashMapReq))
		return DashMapCheck()
	;(minimized: nothing to draw)
	if (DllCall("IsIconic", "Ptr", DashMapHwnd))
		return
	;(the picture is asked for at the size it's shown at, in screen pixels: shown as it is, not stretched)
	VarSetCapacity(rc, 16, 0)
	DllCall("GetClientRect", "Ptr", DashMapPicH, "Ptr", &rc)
	pw := NumGet(rc, 8, "Int"), ph := NumGet(rc, 12, "Int")
	if (pw < 16 || ph < 16)
		{
		;(a picture that didn't load shrinks the control to nothing: back to the window's size)
		DashMapFit()
		return
		}
	if (A_TickCount - DashMapAt < 1000 && pw = DashMapW && ph = DashMapH)
		return
	DashMapAt := A_TickCount, DashMapW := pw, DashMapH := ph
	DashMapAsk("map", "/navmap?w=" pw "&h=" ph "&out=" DashMapUri(DashMapFile))
	}

;Sends a request to the vision helper without waiting for the answer (DashMapCheck picks it up). Not
;VisionGet: that waits, and its failures count towards turning the card vision off - the map's mustn't
DashMapAsk(kind, path)
	{
	DashMapReq := "", DashMapKind := kind, DashMapReqAt := A_TickCount
	try
		{
		req := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "http://127.0.0.1:" (VisionPort ? VisionPort : 47128) path, true)
		req.Send()
		DashMapReq := req
		}
	catch
		DashMapGot(kind, "", false)
	}

;The answer to the request sent, once it's there (after 4 s it's given up)
DashMapCheck()
	{
	req := DashMapReq, done := 0
	try
		done := req.WaitForResponse(0)
	catch
		{
		;(nothing answering on the port: the helper isn't running)
		DashMapReq := ""
		return DashMapGot(DashMapKind, "", false)
		}
	if (!done)
		{
		if (A_TickCount - DashMapReqAt > 4000)
			{
			try req.Abort()
			DashMapReq := ""
			DashMapGot(DashMapKind, "ERR the vision helper didn't answer in 4 s", false)
			}
		return
		}
	DashMapReq := "", text := "", status := 0
	try
		text := req.ResponseText, status := req.Status
	text := Trim(text, " `t`r`n")
	if (status != 200 && InStr(text, "ERR") != 1)
		text := "ERR the vision helper answered " status
	DashMapGot(DashMapKind, text, true)
	}

;An answer ("" = the helper couldn't be asked; answered: it did answer): the picture, then the line under it
DashMapGot(kind, text, answered)
	{
	if (kind = "map")
		{
		f := SubStr(text, 4)
		if (InStr(text, "ok|") != 1)
			DashMapNote := "Map: " DashMapWhy(text)
		else if (!FileExist(f) && !FileExist(f := DashMapFile))
			DashMapNote := "Map: the picture isn't there (" f ")"
		else
			{
			;(no *w *h: fitted to the control - the size it was asked for)
			GuiControl, Map:, DashMapPic, %f%
			DashMapPicAt := A_Hour ":" A_Min ":" A_Sec, DashMapNote := ""
			}
		if (DashMapNote != "" && DashMapPicAt != "")
			DashMapNote .= " (picture from " DashMapPicAt ")"
		;(then /nav for the line under it, if the helper is there to ask)
		if (answered)
			DashMapAsk("nav", "/nav")
		else
			DashMapNav := ""
		}
	else
		DashMapNav := text
	DashMapLine()
	}

;Why a request got no picture / no position ("ERR <why>", or "" when the helper couldn't be asked)
DashMapWhy(text)
	{
	if (text = "")
		return VisionOn ? "no answer from the vision helper (see vision\vision.log)" : "the vision helper isn't running (debug.log says why)"
	return InStr(text, "ERR") = 1 ? Trim(SubStr(text, 4)) : "an odd answer: " SubStr(text, 1, 60)
	}

;The line under the picture: what went wrong with the picture (if anything), then the zone, the place, the goal
DashMapLine()
	{
	static last := ""
	nav := DashMapNav
	if (InStr(nav, "ERR") = 1)
		{
		why := DashMapWhy(nav)
		;(the same reason as the picture's: once is enough)
		nav := InStr(DashMapNote, why) ? "" : "Can't read the game: " why
		}
	else
		nav := DashMapNavLine(nav)
	line := DashMapNote (DashMapNote != "" && nav != "" ? " | " : "") nav
	if (line == last)
		return
	last := line
	GuiControl, Map:, DashMapText, % line
	}

;/nav's answer as "zone | at x, y, z | goal in this zone | arrow 1520" (? for what it couldn't read; arrow = how
;far the on-screen arrow's point is, along the game's path)
DashMapNavLine(answer)
	{
	if (answer = "")
		return ""
	f := {}
	Loop, Parse, answer, `n, `r
		{
		p := StrSplit(A_LoopField, "|")
		f[p[1]] := p
		}
	if (!IsObject(f.ok))
		return "an odd /nav answer: " SubStr(answer, 1, 60)
	zone := IsObject(f.zone) && f.zone[2] != "" ? f.zone[2] : "zone ?"
	pos := IsObject(f.pos) ? "at " DashMapNum(f.pos[2]) ", " DashMapNum(f.pos[3]) ", " DashMapNum(f.pos[4]) : "at ?"
	hops := IsObject(f.goal) ? f.goal[5] : ""
	goal := hops = "" ? "goal ?" : hops = 0 ? "goal in this zone" : "goal " hops " zone" (hops = 1 ? "" : "s") " away"
	if (IsObject(f.quest) && f.quest[2] = "0")
		goal := "no quest goal (the quest helper is off)"
	arrow := IsObject(f.dist) && f.dist[2] != "" ? " | arrow " DashMapNum(f.dist[2]) : ""
	return zone " | " pos " | " goal arrow
	}

DashMapNum(v)
	{
	return v = "" ? "?" : Round(v)
	}

;Fits the picture and the line to the window (gw, gh: its inside at 100% display scaling, as GuiSize gives
;them; blank: the window's now)
DashMapFit(gw := "", gh := "")
	{
	if (gw = "")
		{
		VarSetCapacity(rc, 16, 0)
		DllCall("GetClientRect", "Ptr", DashMapHwnd, "Ptr", &rc)
		gw := Round(NumGet(rc, 8, "Int") * 96 / A_ScreenDPI), gh := Round(NumGet(rc, 12, "Int") * 96 / A_ScreenDPI)
		}
	GuiControl, Map:Move, DashMapPic, % "w" Max(16, gw - 16) " h" Max(16, gh - 40)
	GuiControl, Map:Move, DashMapText, % "y" gh - 26 " w" Max(16, gw - 16)
	}

;Text for a URL: UTF-8, everything but letters, digits and - . _ ~ %-escaped
DashMapUri(s)
	{
	VarSetCapacity(buf, StrPut(s, "UTF-8"), 0)
	n := StrPut(s, &buf, "UTF-8") - 1
	out := ""
	Loop, %n%
		{
		c := NumGet(buf, A_Index - 1, "UChar")
		out .= (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c = 45 || c = 46 || c = 95 || c = 126) ? Chr(c) : "%" Format("{:02X}", c)
		}
	return out
	}

DashMapButton:
	DashMapToggle()
	return

DashMapTick:
	DashMapTick()
	return

MapGuiClose:
	DashMapToggle()
	return

MapGuiSize:
	if (A_EventInfo != 1)
		DashMapFit(A_GuiWidth, A_GuiHeight)
	return

;---- The dashboard's buttons ----

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

;CPU and RAM in use, for the STATISTICS row: the bot (this script and its vision helper), the game, the whole PC.
;CPU from the time each has used since the last look (all cores = 100%), RAM its working set (what Task Manager
;shows, about). Read-only process queries - nothing is changed
DashUsage()
	{
	static last := {}, procs := {}
	EnvGet, cores, NUMBER_OF_PROCESSORS
	cores := cores > 0 ? cores : 1
	now := A_TickCount
	gamePid := 0
	WinGet, gamePid, PID, ahk_class %GameClass% ahk_exe %GameExe%
	who := {bot: [DllCall("GetCurrentProcessId"), VisionPid], game: [gamePid]}
	out := {}
	for name, pids in who
		{
		cpu := 0, ram := 0, seen := 0
		for each, pid in pids
			{
			if (!pid)
				continue
			if (!procs.HasKey(pid))
				procs[pid] := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
			h := procs[pid]
			if (!h)
				continue
			VarSetCapacity(ft, 32, 0)
			if (!DllCall("GetProcessTimes", "Ptr", h, "Ptr", &ft, "Ptr", &ft + 8, "Ptr", &ft + 16, "Ptr", &ft + 24))
				{
				DllCall("CloseHandle", "Ptr", h), procs.Delete(pid)
				continue
				}
			used := NumGet(ft, 16, "Int64") + NumGet(ft, 24, "Int64")
			if (last.HasKey(pid) && now > last[pid].at)
				cpu += (used - last[pid].used) / 10000 / (now - last[pid].at) / cores * 100
			last[pid] := {used: used, at: now}
			cb := 8 + 8 * A_PtrSize
			VarSetCapacity(pmc, cb, 0), NumPut(cb, pmc, 0, "UInt")
			if (DllCall("K32GetProcessMemoryInfo", "Ptr", h, "Ptr", &pmc, "UInt", cb))
				ram += NumGet(pmc, 8 + A_PtrSize, "UPtr")
			seen += 1
			}
		out[name] := seen ? DashUsageNum(cpu) "%" Chr(183) DashBytes(ram) : "-"
		}
	;the whole PC: busy share of all cores since the last look, and RAM in use
	VarSetCapacity(st, 24, 0)
	pcCpu := "?"
	if (DllCall("GetSystemTimes", "Ptr", &st, "Ptr", &st + 8, "Ptr", &st + 16))
		{
		idle := NumGet(st, 0, "Int64"), total := NumGet(st, 8, "Int64") + NumGet(st, 16, "Int64")
		if (last.HasKey("pc") && total > last.pc.total)
			pcCpu := DashUsageNum(100 * (1 - (idle - last.pc.idle) / (total - last.pc.total)))
		last.pc := {idle: idle, total: total}
		}
	VarSetCapacity(ms, 64, 0), NumPut(64, ms, 0, "UInt")
	pcRam := DllCall("GlobalMemoryStatusEx", "Ptr", &ms) ? NumGet(ms, 4, "UInt") "%" : "?"
	return "CPU" Chr(183) "RAM   bot " out.bot "   game " out.game "   PC " pcCpu "%" Chr(183) pcRam
	}

DashUsageNum(v)
	{
	return v < 0 ? 0 : v < 10 ? Round(v, 1) : Round(v)
	}

DashBytes(n)
	{
	return n >= 1073741824 ? Round(n / 1073741824, 1) "GB" : Round(n / 1048576) "MB"
	}

DashUpdButton:
	;The Updates button: the usual check - a newer version offered (its notes), installed if you say so, the bot then
	;started again as it is now - or "you're up to date" (UpdCheckNow, as the tray menu's Check for updates).
	;"Checking..." and not clickable for 10 s
	if (UpdCheckNow())
		{
		DashUpdBusy := A_TickCount
		GuiControl, Dash:Disable, DashUpdBtn
		DashRefresh()
		}
	return

;Report a bug (BugReport.ahk): what went wrong, posted as an issue on GitHub
DashBugButton:
	if (IsFunc("BugShow"))
		Func("BugShow").Call()
	return

;The Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
DashSettingsButton:
	if (IsFunc("CfgShow"))
		Func("CfgShow").Call()
	return

;"Learn every card" on/off (CardLearn.ahk)
DashLearnAll:
	if (IsFunc("LearnAllToggle"))
		Func("LearnAllToggle").Call()
	return

;The bot on/off (BotToggle in Autofarmer.ahk)
DashBotToggle:
	if (IsFunc("BotToggle"))
		Func("BotToggle").Call()
	return

;"Wait while I play" on/off (HandsOffToggle in Autofarmer.ahk)
DashHandsToggle:
	if (IsFunc("HandsOffToggle"))
		Func("HandsOffToggle").Call()
	return

;(the window's X stops the bot - minimise it, or Windows+2, to just put it away)
DashGuiClose:
	DebugLog("Dashboard closed - the bot stops")
	ExitApp
	return

DashGuiSize:
	if (A_EventInfo = 1)
		return
	;(GuiControl Move places a tab's controls from the tabs' inside, not the window's: where that starts, measured
	;once the window's up - a control moved to 0,0 there and where it lands read)
	if (DashTabOX = "")
		{
		GuiControl, Dash:Move, DashPauseBtn, x0 y0
		GuiControlGet, DashTabO, Dash:Pos, DashPauseBtn
		}
	GuiControl, Dash:Move, DashHead, % "w" A_GuiWidth - 258
	GuiControl, Dash:Move, DashBugBtn, % "x" A_GuiWidth - 240
	GuiControl, Dash:Move, DashUpdBtn, % "x" A_GuiWidth - 144
	GuiControl, Dash:Move, DashMapBtn, % "x" A_GuiWidth - 84 - DashTabOX
	GuiControl, Dash:Move, DashCfgBtn, % "x" A_GuiWidth - 166 - DashTabOX
	GuiControl, Dash:Move, DashSeeText, % "w" A_GuiWidth - 384
	;(the Learn button at the right end of the Hand row, its heading up to it)
	GuiControl, Dash:Move, DashLearnBtn, % "x" A_GuiWidth - 138 - DashTabOX
	GuiControl, Dash:Move, DashHandHead, % "w" A_GuiWidth - 154
	GuiControl, Dash:Move, DashConsole, % "w" A_GuiWidth - 24 " h" A_GuiHeight - 504
	;(the tabs fill the window under the heading; the Dungeons tab's list takes what's left)
	GuiControl, Dash:Move, DashTabs, % "w" A_GuiWidth - 12 " h" A_GuiHeight - 42
	GuiControl, Dash:Move, DgHelp, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DgStatus, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, DgList, % "w" A_GuiWidth - 24 " h" A_GuiHeight - 274
	;(the Spells tab: its list takes what's left of the picture on its right)
	GuiControl, Dash:Move, SpHelp, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, SpStatus, % "w" A_GuiWidth - 24
	GuiControl, Dash:Move, SpList, % "w" A_GuiWidth - 172 " h" A_GuiHeight - 202
	GuiControl, Dash:Move, SpPreview, % "x" A_GuiWidth - 152 - DashTabOX
	GuiControl, Dash:Move, SpPreviewTxt, % "x" A_GuiWidth - 152 - DashTabOX " h" Max(40, A_GuiHeight - 440)
	;(the bottom row shares the width, each button in proportion to the width it was made with, so all six
	;fit at any size - 620 at the least)
	;(a label runs in the global scope: Dash-named variables only)
	DashRowX := 12, DashRowRoom := A_GuiWidth - 24 - 6 * 6
	for DashRowI, DashRowB in [["DashPauseBtn", 100], ["DashClearBtn", 70], ["DashLogBtn", 110], ["DashBotBtn", 100], ["DashWalkBtn", 140], ["DashFolderBtn", 120], ["DashHandsBtn", 120]]
		{
		DashRowW := Floor(DashRowRoom * DashRowB[2] / 760)
		GuiControl, Dash:Move, % DashRowB[1], % "x" DashRowX - DashTabOX " y" A_GuiHeight - 36 - DashTabOY " w" DashRowW
		DashRowX += DashRowW + 6
		}
	return

;(Windows+2 is in Autofarmer.ahk: it shows the dev-mode info box in dev mode)
