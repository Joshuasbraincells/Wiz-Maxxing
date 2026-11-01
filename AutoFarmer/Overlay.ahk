#Warn Unreachable, Off
; Overlay.ahk - the overlay over the game: the zone map round your wizard and the newest debug.log lines drawn
; see-through over Wizard101 (borderless or windowed - exclusive full screen never shows it) while it's the window in
; front and not minimised. AutoHotkey v2, written for v2 (v1 never had this: nothing here is ported); #Included by
; Autofarmer.ahk only. Settings (PlayerStats.txt, the Settings window's THE OVERLAY): overlay - off unless 1; where each
; part goes, the map's size, the log's lines, width and text size, the dark box, how solid (overlaymapat ...
; overlayopacity - read from Stats each tick); dashboard.ini [overlay]: mapdx, mapdy, logdx, logdy (pixel nudges),
; mapspan (game units across) - read each time the windows are made. The tray menu and its key switch it
; (OverlayToggle).
;
; The windows: two (the map, the log), each layered (WS_EX_LAYERED - drawn by UpdateLayeredWindow from a premultiplied
; 32-bit DIB), click-through (WS_EX_TRANSPARENT: WindowFromPoint passes them by - RcOnGame, LogMirrorGameShown), never
; activated (WS_EX_NOACTIVATE; shown only by ShowWindow SW_SHOWNA and SetWindowPos SWP_NOACTIVATE), tool windows (not in
; Alt+Tab), topmost (re-asserted every 2 s), and kept out of every screen capture with SetWindowDisplayAffinity
; WDA_EXCLUDEFROMCAPTURE 0x11 (Windows 10 version 2004, 10.0.19041, or newer - older: it stays off), so ImageSearch,
; PixelSearch, OCR, ArrowReader and the helper's grab_screen read the game alone. Never WDA_MONITOR (1): that blacks the
; windows out in the bot's own screen reading. The affinity is read back (0x11) before every show - anything else stops
; the overlay. Never Gui.Show, WinSet Transparent, WinSet TransColor or SetLayeredWindow Attributes on these windows:
; UpdateLayeredWindow fails on a window that has had SetLayeredWindow Attributes (the names written apart here: the
; helper's test_overlay.py checks that none of them is in this file).
;
; The capture check (OvProbeStep): each time the windows are made, before any real picture, an 8 x 8 opaque magenta
; square is shown for about 150-200 ms at a corner of the game's inside and the screen there is read with the bot's own
; two readers (CaptureRGB's BitBlt, PixelSearch). Pink seen (Windows shows it to screen captures) or black twice
; (Windows blacks it out): the overlay stays off. A spot that's black or pink already is tried again 3 s later at the
; next of 4 places.
;
; The pictures, both drawn by the vision helper (vision\overlay.py): GET http://127.0.0.1:<VisionPort>/ovmap?<layout>
; and POST /ovlog?<layout> - its body one RRGGBB<TAB><the line BrecEsc'd><LF> a line, oldest first, RRGGBB the line's
; dashboard colour (DashLogColors, DashLogKind). The layout: gw=&gh=&mapat=&msize=&logat=&lines=&lw=&text=&back=&mdx=
; &mdy=&ldx=&ldy=&span= (OvQuery), then &seq=&force=&out=. The answer: "ok|<file>" (written), "same|<file>" (unchanged,
; nothing written - never with force=1), "ERR <why>". The file (.wzov, A_Temp\Wizard101 bot map\): a 32-byte header,
; little-endian - "WZOV" (0x564F5A57), version 1, w, h, stride (w*4), seq (UInts), x, y (Ints: the part's top left in
; the game's inside) - then h rows top-down of w premultiplied B,G,R,A pixels. One request in flight at a time, never
; waited for (WinHttp asynchronous, as Dashboard.ahk DashMapAsk asks /navmap), picked up by a later tick; the map asked
; every second while shown, the log at most every 400 ms and only when something changed. A picture that can't be
; loaded only hides its part till the next one.
;
; Its hook: OvLogNote, from DebugLog (V1IsFunc + .Call) - a single push of the line onto a 60-line array, nothing drawn
; there. Everything else runs on one timer (OvTick: 200 ms while on, 1 s while off) under try: an error is logged once
; and the overlay stays off (OvFail, OvStop) - the bot runs on as ever. Nothing here clicks, types, activates a window,
; writes the game's memory or waits.

;(v2-only globals - the port tools don't know them: declared here with no value - a top-level := in an #Included file
;never runs - every one set in OverlayBlank, called first thing by Autofarmer.ahk)
;The two windows (Map "map"/"log" of window objects, "" none); on as last applied; stopped till switched off and on;
;OverlayInit done; the game's inside on screen; the request in flight (a WinHttp object, "" none), its part, when it
;went, its seq; the last seq used
global OvWin, OvWasOn, OvBroken, OvInit, OvGx, OvGy, OvGw, OvGh, OvReq, OvReqPart, OvReqAt, OvReqSeq, OvSeq
;The newest log lines (OvLogNote) and their count; the count and the colours (the object) last sent; the capture
;check: its state ("", "shown", "ok"), when (or not before), the spot's look before, the spot [x, y], tries, black seen
global OvLogBuf, OvLogSeq, OvLogSentSeq, OvLogSentCols, OvProbe, OvProbeAt, OvProbePre, OvProbeXY, OvProbeTries, OvProbeBlack
;dashboard.ini [overlay]: [mapdx, mapdy, logdx, logdy] and mapspan; the frame files (Map "map"/"log"); the last topmost
global OvNudge, OvSpan, OvFile, OvTopAt

;Every global blank at the start (Autofarmer.ahk's first lines). Handles are numbers (0), never blank
OverlayBlank()
	{
	global OvWin := "", OvWasOn := 0, OvBroken := 0, OvInit := 0, OvGx := 0, OvGy := 0, OvGw := 0, OvGh := 0
	global OvReq := "", OvReqPart := "", OvReqAt := 0, OvReqSeq := 0, OvSeq := 0, OvLogBuf := [], OvLogSeq := 0
	global OvLogSentSeq := -1, OvLogSentCols := "", OvProbe := "", OvProbeAt := 0, OvProbePre := "", OvProbeXY := ""
	global OvProbeTries := 0, OvProbeBlack := 0, OvNudge := [0, 0, 0, 0], OvSpan := 4000, OvFile := "", OvTopAt := 0
	}

;StartBot, after LoadStats, the Game* block, DashInit and VisionStart: the frame files (the helper makes their folder)
;and the timer - nothing shown till the timer finds the setting on
OverlayInit()
	{
	global OvFile, OvInit
	OvFile := Map("map", A_Temp "\Wizard101 bot map\overlay-map.wzov", "log", A_Temp "\Wizard101 bot map\overlay-log.wzov")
	OvInit := 1
	OverlayTrayTick()
	SetTimer(OvTick, 1000)
	}

;The DebugLog hook ("HH:mm:ss msg"): kept for the log's next picture. Any thread, Critical callers too: only pushes,
;trims and counts - no Critical, waiting, file, window, HTTP or DashLogKind here
OvLogNote(line)
	{
	global OvLogBuf, OvLogSeq
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	try
		{
		if (!IsObject(OvLogBuf))
			return
		for each, ovPart in StrSplit(line, "`n", "`r")
			if (ovPart != "")
				OvLogBuf.Push(SubStr(ovPart, 1, 400))
		while (OvLogBuf.Length > 60)
			OvLogBuf.RemoveAt(1)
		OvLogSeq += 1
		}
	}

;A setting as a whole number (def when it isn't a number) - Stats itself, never Stat / StatOr: a deck's or a school's
;value can't change the overlay
OvStat(key, def)
	{
	v := ""
	try
		{
		if (IsObject(Stats) && Stats.Has(key))
			v := Stats[key]
		}
	return V1IsNum(v) ? Integer(Round(v)) : def
	}

;The tray menu / its key (MenuOverlay): overlay on / off, kept in PlayerStats.txt. The timer applies it - nothing
;window-related here
OverlayToggle()
	{
	ovNow := OvStat("overlay", 0) ? 0 : 1
	if (!StatsSet([["overlay", ovNow]]))
		try Stats["overlay"] := ovNow
	OverlayTrayTick()
	TrayTip("Overlay over the game: " (ovNow ? "ON - the map and the log over Wizard101 while it's the window in front." : "OFF"), "Wizard101 bot", 1)
	if (OvInit)
		SetTimer(OvTick, 50)
	}

;The tray menu's tick
OverlayTrayTick()
	{
	try
		{
		if (OvStat("overlay", 0))
			Tray.Check(HkMenu("overlay"))
		else
			Tray.Uncheck(HkMenu("overlay"))
		}
	}

;The timer: one step at a time, an error stops the overlay (no AutoHotkey error box to take the focus from the game)
OvTick()
	{
	static busy := 0
	local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)
	if (busy)
		return
	busy := 1
	try
		{
		OvStep()
		}
	catch Any as e
		OvFail(e)
	busy := 0
	}

;Each tick: the setting applied; an answer picked up (even while hidden); hidden unless Wizard101 is in front; the
;windows made and checked once; the next picture asked for; the parts shown where the helper put them
OvStep()
	{
	global OvWasOn, OvBroken, OvGx, OvGy, OvGw, OvGh
	if (!IsObject(OvFile))
		return
	ovOn := OvStat("overlay", 0) ? 1 : 0
	if (ovOn != OvWasOn)
		{
		OvWasOn := ovOn
		OverlayTrayTick()
		if (ovOn)
			{
			OvBroken := 0
			k := HkText("overlay")
			OvSay("on", "Overlay: on (" (k = "(none)" ? "" : k " or ") "the tray menu switches it off)")
			}
		else
			{
			OvFree()
			OvSay("on", "Overlay: off")
			}
		}
	;(every tick, not only on a change: OverlayToggle's 50 ms put back even when two toggles came before this tick)
	SetTimer(OvTick, ovOn ? 200 : 1000)
	if (!ovOn)
		return
	if (IsObject(OvReq))
		OvCheck()
	if (OvBroken)
		return
	mapAt := OvStat("overlaymapat", 2), logAt := OvStat("overlaylogat", 2)
	if (mapAt <= 1 && logAt <= 1)
		{
		OvHideAll()
		OvProbeReset()
		return
		}
	cx := 0, cy := 0, cw := 0, ch := 0
	if (!OvGameFront(&cx, &cy, &cw, &ch))
		{
		OvHideAll()
		OvProbeReset()
		return
		}
	OvGx := cx, OvGy := cy, OvGw := cw, OvGh := ch
	if (!IsObject(OvWin) && !OvMake())
		return
	if (OvProbe != "ok")
		return OvProbeStep()
	if (!IsObject(OvReq))
		OvAskNext(mapAt, logAt)
	OvShowParts(mapAt, logAt)
	}

;Wizard101 in front and not minimised: its window (0 not), its inside on screen in &cx, &cy, &cw, &ch. Never reads or
;sets GameLeft and the other Game* globals
OvGameFront(&cx, &cy, &cw, &ch)
	{
	static lastFg := 0, lastExe := ""
	cls := GameClass != "" ? GameClass : "Wizard Graphical Client"
	exe := GameExe != "" ? GameExe : "WizardGraphicalClient.exe"
	fg := DllCall("GetForegroundWindow", "Ptr")
	if (!fg)
		return 0
	g := 0
	try g := WinActive("ahk_class " cls " ahk_exe " exe)
	if (!g)
		{
		;(the game's own other window in front - its D3DProxyWindow while loading - counts as the game, as in
		;UpdateGameRect; the front window's program looked up once per window)
		if (fg != lastFg)
			{
			lastFg := fg, lastExe := ""
			try lastExe := WinGetProcessName("ahk_id " fg)
			}
		if (lastExe = exe)
			try g := WinGetID("ahk_class " cls " ahk_exe " exe)
		}
	if (!g || DllCall("IsIconic", "Ptr", g, "Int"))
		return 0
	rc := Buffer(16, 0), pt := Buffer(8, 0)
	if (!DllCall("GetClientRect", "Ptr", g, "Ptr", rc, "Int") || !DllCall("ClientToScreen", "Ptr", g, "Ptr", pt, "Int"))
		return 0
	cw := NumGet(rc, 8, "Int"), ch := NumGet(rc, 12, "Int"), cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")
	return (cw >= 200 && ch >= 150) ? g : 0
	}

;The two windows made (hidden), the capture check to run again, dashboard.ini read. False: the overlay stopped
OvMake()
	{
	global OvWin, OvProbe, OvProbeTries, OvProbeBlack, OvLogSentSeq, OvNudge, OvSpan
	if (VerCompare(A_OSVersion, "10.0.19041") < 0)
		{
		OvStop("can't be shown - it needs Windows 10 version 2004 or newer (this PC: " A_OSVersion "), an older Windows would black it out in the bot's screen reading")
		return false
		}
	why := ""
	m := OvWinMake("map", &why)
	if (!IsObject(m))
		{
		OvStop("can't be shown - " why)
		return false
		}
	l := OvWinMake("log", &why)
	if (!IsObject(l))
		{
		OvWinFree(m)
		OvStop("can't be shown - " why)
		return false
		}
	OvWin := Map("map", m, "log", l), OvProbe := "", OvProbeTries := 0, OvProbeBlack := 0, OvLogSentSeq := -1
	OvReadIni()
	return true
	}

;dashboard.ini [overlay] (hand-edited): mapdx, mapdy, logdx, logdy -4000..4000 (0), mapspan 500-100000 (4000)
OvReadIni()
	{
	global OvNudge, OvSpan
	ovN := [0, 0, 0, 0]
	for i, key in ["mapdx", "mapdy", "logdx", "logdy"]
		{
		v := 0
		try v := IniRead(A_ScriptDir "\dashboard.ini", "overlay", key, 0)
		ovN[i] := IsInteger(v) ? Max(-4000, Min(4000, Integer(v))) : 0
		}
	OvNudge := ovN
	v := 4000
	try v := IniRead(A_ScriptDir "\dashboard.ini", "overlay", "mapspan", 4000)
	OvSpan := IsInteger(v) ? Max(500, Min(100000, Integer(v))) : 4000
	}

;One window, hidden: layered, click-through, never activated (0x08080020 = WS_EX_NOACTIVATE | WS_EX_LAYERED |
;WS_EX_TRANSPARENT), a tool window, topmost; its title doesn't start with "Wizard101" (the bot's window searches).
;Never shown by its Gui object. "" when it couldn't be made (why says why)
OvWinMake(part, &why)
	{
	local ovG := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x08080020", "Wiz-Maxxing overlay (" part ")")
	hwnd := ovG.Hwnd
	;(not trusted here - OvAff reads 0x11 back before any show; 1, WDA_MONITOR, is never passed anywhere)
	DllCall("SetWindowDisplayAffinity", "Ptr", hwnd, "UInt", 0x11, "Int")
	hdc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
	if (!hdc)
		{
		why := "CreateCompatibleDC failed"
		try ovG.Destroy()
		return ""
		}
	return {part: part, gui: ovG, hwnd: hwnd, hdc: hdc, hbm: 0, old: 0, bits: 0, w: 0, h: 0, ox: 0, oy: 0, sx: -99999, sy: -99999, alpha: -1, shown: 0, have: 0, bad: 0, dirty: 0, err: 0, askAt: 0, gotAt: 0, sentQ: ""}
	}

;"" when the window is kept out of screen captures (WDA_EXCLUDEFROMCAPTURE read back), else why not
OvAff(win)
	{
	aff := 0
	DllCall("GetWindowDisplayAffinity", "Ptr", win.hwnd, "UInt*", &aff, "Int")
	if (aff = 0x11)
		return ""
	ok := DllCall("SetWindowDisplayAffinity", "Ptr", win.hwnd, "UInt", 0x11, "Int"), err := A_LastError
	aff := 0
	DllCall("GetWindowDisplayAffinity", "Ptr", win.hwnd, "UInt*", &aff, "Int")
	return aff = 0x11 ? "" : "Windows wouldn't keep it out of screen captures (SetWindowDisplayAffinity: " (ok ? "affinity " aff : "error " err) ")"
	}

;A picture (w x h premultiplied BGRA at src, rows top-down) into the window's DIB - made again when the size changed.
;The only code that touches the DIB. False: no DIB (CreateDIBSection failed)
OvPixels(win, w, h, src)
	{
	if (!win.hbm || w != win.w || h != win.h)
		{
		bi := Buffer(40, 0)
		NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
		NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
		bits := 0
		hbm := DllCall("gdi32\CreateDIBSection", "Ptr", win.hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
		if (!hbm || !bits)
			{
			if (hbm)
				DllCall("gdi32\DeleteObject", "Ptr", hbm)
			return false
			}
		was := DllCall("gdi32\SelectObject", "Ptr", win.hdc, "Ptr", hbm, "Ptr")
		if (win.hbm)
			DllCall("gdi32\DeleteObject", "Ptr", win.hbm)
		else
			win.old := was
		win.hbm := hbm, win.bits := bits, win.w := w, win.h := h
		}
	DllCall("gdi32\GdiFlush")
	DllCall("RtlMoveMemory", "Ptr", win.bits, "Ptr", src, "Ptr", w * h * 4)
	win.dirty := 1
	return true
	}

;The DIB onto the window, at the game's inside + the part's place, op (0-255) how solid as a whole. False: failed
;(win.err the error)
OvPut(win, op)
	{
	x := OvGx + win.ox, y := OvGy + win.oy
	pt := Buffer(8, 0), NumPut("Int", x, pt, 0), NumPut("Int", y, pt, 4)
	sz := Buffer(8, 0), NumPut("Int", win.w, sz, 0), NumPut("Int", win.h, sz, 4)
	src := Buffer(8, 0)
	;(BLENDFUNCTION, passed by pointer: AC_SRC_OVER, 0, the alpha, AC_SRC_ALPHA)
	bf := Buffer(4, 0), NumPut("UChar", 0, bf, 0), NumPut("UChar", 0, bf, 1), NumPut("UChar", op, bf, 2), NumPut("UChar", 1, bf, 3)
	;(2 = ULW_ALPHA)
	ok := DllCall("UpdateLayeredWindow", "Ptr", win.hwnd, "Ptr", 0, "Ptr", pt, "Ptr", sz, "Ptr", win.hdc, "Ptr", src, "UInt", 0, "Ptr", bf, "UInt", 2, "Int")
	if (!ok)
		{
		win.err := A_LastError
		return false
		}
	win.sx := x, win.sy := y, win.alpha := op
	return true
	}

;Shows the window without activating it, topmost - only once the affinity is read back as 0x11 (else the overlay
;stops). False: stopped
OvShow(win)
	{
	why := OvAff(win)
	if (why != "")
		{
		OvStop("stopped - " why)
		return false
		}
	;(8 = SW_SHOWNA: shown, not activated)
	DllCall("ShowWindow", "Ptr", win.hwnd, "Int", 8)
	;(HWND_TOPMOST; 0x213 = SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER)
	DllCall("SetWindowPos", "Ptr", win.hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x213, "Int")
	win.shown := 1
	return true
	}

;Hides the window (SW_HIDE)
OvHide(win)
	{
	if (win.shown)
		{
		try DllCall("ShowWindow", "Ptr", win.hwnd, "Int", 0)
		win.shown := 0
		}
	}

;Both hidden
OvHideAll()
	{
	if (IsObject(OvWin))
		for each, w in OvWin
			OvHide(w)
	}

;One window let go: hidden, its DIB and DC deleted, the window destroyed
OvWinFree(win)
	{
	OvHide(win)
	if (win.old && win.hdc)
		try DllCall("gdi32\SelectObject", "Ptr", win.hdc, "Ptr", win.old, "Ptr")
	if (win.hbm)
		try DllCall("gdi32\DeleteObject", "Ptr", win.hbm)
	if (win.hdc)
		try DllCall("gdi32\DeleteDC", "Ptr", win.hdc)
	win.hbm := 0, win.hdc := 0, win.old := 0, win.bits := 0
	try win.gui.Destroy()
	}

;Everything let go: the request in flight dropped, both windows freed (made again - and checked again - when needed)
OvFree()
	{
	global OvWin, OvReq, OvProbe
	if (IsObject(OvReq))
		try OvReq.Abort()
	OvReq := ""
	if (IsObject(OvWin))
		for each, w in OvWin
			OvWinFree(w)
	OvWin := "", OvProbe := ""
	}

;The overlay off for this run, till it's switched off and on again: why logged and said in a tray tip
OvStop(why)
	{
	global OvBroken
	OvBroken := 1
	try OvFree()
	try DebugLog("Overlay: " why " - it stays off (switch it off and on to try again)")
	try TrayTip("Overlay: " why, "Wizard101 bot", 2)
	}

;An error in the timer: the overlay stopped, the error said
OvFail(e)
	{
	try
		{
		msg := (e is Error) ? (e.Message (e.What != "" ? " in " e.What : "") " (line " e.Line ")") : String(e)
		OvStop("stopped - " msg)
		}
	}

;The 8 x 8 screen square at x, y (screen) read by the bot's own two readers: {pink: pink pixels, black: all 64 black,
;found: PixelSearch found magenta}, "" when it couldn't be read. KillCalc.ahk CaptureRGB - GDI BitBlt SRCCOPY, as
;Ocr.ahk, ArrowReader and vision.py grab_screen read the screen - gives 0xRRGGBB a pixel; PixelSearch is AutoHotkey's
;ImageSearch capture path
OvSee(x, y)
	{
	arr := ""
	try arr := CaptureRGB(x, y, 8, 8)
	if (!IsObject(arr) || arr.Length != 64)
		return ""
	pink := 0, black := 0
	for each, c in arr
		{
		r := (c >> 16) & 0xFF, gg := (c >> 8) & 0xFF, b := c & 0xFF
		if (r >= 0xE0 && gg <= 0x30 && b >= 0xE0)
			pink += 1
		if (c = 0)
			black += 1
		}
	found := 0, fx := 0, fy := 0
	try
		{
		CoordMode("Pixel", "Screen")
		found := PixelSearch(&fx, &fy, x, y, x + 7, y + 7, 0xFF00FF, 24)
		}
	catch
		return ""
	return {pink: pink, black: black = 64, found: found}
	}

;The capture check, once each time the windows are made - real pictures are shown only after it passes. It uses the
;map's window (made even when the map is Off): an opaque magenta square shown, the screen read under it 150 ms later
OvProbeStep()
	{
	global OvProbe, OvProbeAt, OvProbePre, OvProbeXY, OvProbeTries, OvProbeBlack
	win := OvWin["map"]
	if (OvProbe = "")
		{
		if (A_TickCount < OvProbeAt)
			return
		;(the spot cycles through 4 places: top left, top right, left and right halfway down)
		i := Mod(OvProbeTries, 4)
		x := OvGx + ((i = 1 || i = 3) ? OvGw - 32 : 24)
		y := OvGy + (i >= 2 ? OvGh // 2 : 24)
		pre := OvSee(x, y)
		if (!IsObject(pre) || pre.pink || pre.found || pre.black)
			{
			;(the check can't be made there now)
			OvProbeTries += 1, OvProbeAt := A_TickCount + 3000
			OvSay("probe", "Overlay: waiting to check it - the game there is black or pink (a loading screen?)")
			return
			}
		;(opaque magenta: premultiplied BGRA FF 00 FF FF)
		ovPx := Buffer(256, 0)
		Loop 64
			NumPut("UInt", 0xFFFF00FF, ovPx, (A_Index - 1) * 4)
		if (!OvPixels(win, 8, 8, ovPx.Ptr))
			return OvStop("can't be shown - CreateDIBSection failed")
		win.have := 0, win.ox := x - OvGx, win.oy := y - OvGy
		if (!OvPut(win, 255))
			return OvStop("can't be shown - UpdateLayeredWindow failed (error " win.err ")")
		;(OvShow has stopped the overlay already when the affinity isn't 0x11)
		if (!OvShow(win))
			return
		OvProbe := "shown", OvProbeAt := A_TickCount, OvProbePre := pre, OvProbeXY := [x, y]
		}
	else if (OvProbe = "shown")
		{
		if (A_TickCount - OvProbeAt < 150)
			return
		if (OvGx + win.ox != OvProbeXY[1] || OvGy + win.oy != OvProbeXY[2])
			{
			;(the game moved: again)
			OvHide(win)
			OvProbe := ""
			return
			}
		post := OvSee(OvProbeXY[1], OvProbeXY[2])
		OvHide(win)
		if (!IsObject(post))
			return OvProbeFail("the screen couldn't be read to check it")
		if (post.pink >= 16 || post.found)
			return OvProbeFail("Windows shows it in screen captures - the bot's screen reading would see it")
		if (post.black)
			{
			OvProbeBlack += 1
			if (OvProbeBlack >= 2)
				return OvProbeFail("Windows blacks it out in screen captures")
			OvProbe := "", OvProbeAt := A_TickCount + 2000
			return
			}
		OvProbe := "ok"
		OvSay("probe", "Overlay: checked - the bot's screen reading doesn't see it (Windows " A_OSVersion ")")
		}
	}

;The capture check failed: the overlay stays off
OvProbeFail(why)
	{
	OvStop("can't be shown - " why " (Windows " A_OSVersion ")")
	}

;The check's square hidden and the check started again (the game not in front)
OvProbeReset()
	{
	global OvProbe
	if (OvProbe = "shown" && IsObject(OvWin))
		{
		OvHide(OvWin["map"])
		OvProbe := ""
		}
	}

;The layout query, the same for both parts (the helper's keys, in this order)
OvQuery()
	{
	return "gw=" OvGw "&gh=" OvGh "&mapat=" OvStat("overlaymapat", 2) "&msize=" OvStat("overlaymapsize", 28)
		. "&logat=" OvStat("overlaylogat", 2) "&lines=" OvStat("overlaylines", 10) "&lw=" OvStat("overlaylogwidth", 38)
		. "&text=" OvStat("overlaytext", 100) "&back=" OvStat("overlayback", 35) "&mdx=" OvNudge[1] "&mdy=" OvNudge[2]
		. "&ldx=" OvNudge[3] "&ldy=" OvNudge[4] "&span=" OvSpan
	}

;The vision helper's port
OvPort()
	{
	p := 0
	try p := VisionPort
	return (V1IsNum(p) && p > 0) ? p : 47128
	}

;The next picture asked for, if one is due: the map every second while shown (3 s after a failure), at once when the
;query changed; the log at most every 400 ms (3 s after a failure), only when a line came, the query or the colours
;changed. Nothing asked while hidden: OvStep returns before this
OvAskNext(mapAt, logAt)
	{
	q := OvQuery(), now := A_TickCount, m := OvWin["map"], l := OvWin["log"]
	cols := DashLogColors()
	colsNew := !IsObject(OvLogSentCols) || ObjPtr(cols) != ObjPtr(OvLogSentCols)
	;(no picture yet: at once - unless the last ask failed, then 3 s on, as with a picture)
	mDue := mapAt > 1 && now - m.askAt >= 200 && (q != m.sentQ || (!m.have && !m.bad) || now - m.askAt >= (m.bad ? 3000 : 1000))
	lDue := logAt > 1 && now - l.askAt >= (l.bad ? 3000 : 400) && (q != l.sentQ || !l.have || OvLogSeq != OvLogSentSeq || colsNew)
	if (mDue && (!lDue || m.askAt <= l.askAt))
		OvAsk("map", q)
	else if (lDue)
		OvAsk("log", q)
	}

;Asks the helper for a part's picture without waiting (OvCheck picks the answer up). force=1 while there's no picture
;of it, and after a failed ask (one given up after 4 s may still have been written - a picture never loaded here), so
;the helper doesn't answer "same" to a picture this window hasn't got
OvAsk(part, q)
	{
	global OvReq, OvReqPart, OvReqAt, OvReqSeq, OvSeq
	win := OvWin[part], OvSeq := OvSeq >= 0x7FFFFFFF ? 1 : OvSeq + 1
	url := "http://127.0.0.1:" OvPort() "/ov" part "?" q "&seq=" OvSeq "&force=" (win.have && !win.bad ? 0 : 1) "&out=" DashMapUri(OvFile[part])
	body := part = "log" ? OvLogBody() : ""
	win.askAt := A_TickCount, win.sentQ := q
	try
		{
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.SetTimeouts(1000, 1000, 4000, 4000)
		req.Open(part = "log" ? "POST" : "GET", url, true)
		if (part = "log")
			{
			req.SetRequestHeader("Content-Type", "text/plain; charset=us-ascii")
			req.Send(body)
			}
		else
			req.Send()
		OvReq := req, OvReqPart := part, OvReqAt := A_TickCount, OvReqSeq := OvSeq
		}
	catch
		OvGot(part, "")
	}

;/ovlog's body (the timer's thread only): the newest lines (overlaylines), oldest first, each RRGGBB<TAB><line
;BrecEsc'd, 300 characters at most><LF> in its dashboard colour. Keeps the colours object sent: its ObjPtr stays unique
OvLogBody()
	{
	global OvLogSentSeq, OvLogSentCols
	n := Max(3, Min(30, OvStat("overlaylines", 10))), cols := DashLogColors(), seqNow := OvLogSeq, ovL := OvLogBuf.Clone(), body := ""
	start := Max(1, ovL.Length - n + 1)
	Loop ovL.Length - start + 1
		{
		ln := ovL[start + A_Index - 1], kind := DashLogKind(ln)
		body .= (cols.Has(kind) ? cols[kind] : "DADADA") "`t" BrecEsc(SubStr(ln, 1, 300)) "`n"
		}
	OvLogSentSeq := seqNow, OvLogSentCols := cols
	return body
	}

;The answer to the request in flight, once it's there (after 4 s it's given up) - as Dashboard.ahk DashMapCheck
OvCheck()
	{
	global OvReq
	req := OvReq, done := 0
	try
		done := req.WaitForResponse(0)
	catch
		{
		;(nothing answering on the port: the helper isn't running)
		OvReq := ""
		return OvGot(OvReqPart, "")
		}
	if (!done)
		{
		if (A_TickCount - OvReqAt > 4000)
			{
			try req.Abort()
			OvReq := ""
			OvGot(OvReqPart, "ERR the vision helper didn't answer in 4 s")
			}
		return
		}
	OvReq := "", text := "", status := 0
	try
		text := req.ResponseText, status := req.Status
	text := Trim(text, " `t`r`n")
	if (status != 200 && InStr(text, "ERR") != 1)
		text := "ERR the vision helper answered " status
	OvGot(OvReqPart, text)
	}

;An answer ("" = the helper couldn't be asked): the picture loaded, or kept ("same"), or why not - said once. A
;picture that can't be loaded is never fatal: its part hidden, the next ask force=1
OvGot(part, text)
	{
	global OvLogSentSeq
	if (!IsObject(OvWin))
		return
	win := OvWin[part], name := part = "map" ? "map" : "log"
	if (InStr(text, "ok|") = 1)
		{
		why := OvLoad(win, SubStr(text, 4), OvReqSeq)
		if (why = "")
			win.have := 1, win.bad := 0, win.gotAt := A_TickCount
		else
			{
			win.have := 0, win.bad := 1
			OvSay(part, "Overlay: " name " not shown - " why)
			}
		}
	else if (InStr(text, "same|") = 1)
		{
		if (win.have)
			win.bad := 0, win.gotAt := A_TickCount
		else
			win.sentQ := ""
		}
	else
		{
		win.bad := 1
		OvSay(part, "Overlay: " name " not shown - " DashMapWhy(text))
		if (part = "log")
			OvLogSentSeq := -1
		}
	}

;A frame file (.wzov) into the window's DIB, its place kept: "" done, else why not
OvLoad(win, path, seq)
	{
	buf := ""
	try buf := FileRead(path, "RAW")
	if (!IsObject(buf))
		try buf := FileRead(OvFile[win.part], "RAW")
	if (!IsObject(buf))
		return "the picture couldn't be read (" path ")"
	n := buf.Size
	if (n < 32 || NumGet(buf, 0, "UInt") != 0x564F5A57 || NumGet(buf, 4, "UInt") != 1)
		return "the picture isn't one the overlay reads"
	w := NumGet(buf, 8, "UInt"), h := NumGet(buf, 12, "UInt")
	if (w < 1 || h < 1 || w > 4000 || h > 4000 || NumGet(buf, 16, "UInt") != w * 4 || n != 32 + w * h * 4)
		return "the picture's size is wrong"
	if (NumGet(buf, 20, "UInt") != seq)
		return "an older picture came back"
	if (!OvPixels(win, w, h, buf.Ptr + 32))
		return "no memory for the picture (CreateDIBSection failed)"
	win.ox := NumGet(buf, 24, "Int"), win.oy := NumGet(buf, 28, "Int")
	return ""
	}

;Each part shown with its picture where the helper put it (UpdateLayeredWindow before the window's first show, so the
;picture is in place as it shows), or hidden (Off, no picture, failing 3 s); topmost again every 2 s
OvShowParts(mapAt, logAt)
	{
	global OvTopAt
	op := Round(255 * Max(20, Min(100, OvStat("overlayopacity", 90))) / 100)
	for each, part in ["map", "log"]
		{
		win := OvWin[part]
		want := (part = "map" ? mapAt : logAt) > 1 && win.have && (!win.bad || A_TickCount - win.gotAt < 3000)
		if (!want)
			{
			OvHide(win)
			continue
			}
		if (!win.shown || win.dirty || win.alpha != op || win.sx != OvGx + win.ox || win.sy != OvGy + win.oy)
			{
			if (!OvPut(win, op))
				return OvStop("stopped - UpdateLayeredWindow failed (error " win.err ")")
			win.dirty := 0
			}
		if (!win.shown && !OvShow(win))
			return
		}
	if (A_TickCount - OvTopAt >= 2000)
		{
		OvTopAt := A_TickCount
		for each, part in ["map", "log"]
			if (OvWin[part].shown)
				DllCall("SetWindowPos", "Ptr", OvWin[part].hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x213, "Int")
		}
	}

;A debug.log line, not repeated: the same text under the same key at most every 10 minutes
OvSay(key, text)
	{
	static said := Map(), at := Map()
	if (said.Has(key) && said[key] == text && A_TickCount - at[key] < 600000)
		return
	said[key] := text, at[key] := A_TickCount
	DebugLog(text)
	}
