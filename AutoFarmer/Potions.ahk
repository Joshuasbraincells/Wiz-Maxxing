; Potions.ahk - out of battle: drinks a potion when your health is low, and when there are none left goes
; to buy more with gold (never Crowns) along a route you recorded once. AHK v1.1, functions only;
; #Included by Autofarmer.ahk. Needs the vision helper (Vision.ahk) to read the globes.
;
; Health: the number on the red globe (vision.py /globes, digit pictures in ui1.144\globedigits), as a %
; of your most health (read off your name plate in battle - <school>.maxhealth in PlayerStats.txt - or
; the most the globe has shown). Under potionat % (PlayerStats.txt, default 40) it drinks (Ctrl+O, the
; game's Drink Potion key); health not going up after that means no potion was left.
;
; Out of potions: a refill run along a route (routes\<zone>.txt):
;   1. Mark Location (Page Down) where you are
;   2. Go to the Commons (End) of this world - the game's log says which Commons it is
;   3. the route recorded from that Commons: your keys (walking, X to talk) and left clicks (Hilda
;      Brewer's "Fill All" etc.), replayed with the same timing; loading screens on the way are waited for
;   4. drink (now there are potions), then Recall (Page Up) back to the mark
; Before every click it reads the screen round it: any "Crown" there stops the run (it buys with gold
; only). A battle, you touching the mouse or keyboard, or a loading screen that doesn't come stops it too.
; No route from that Commons: it recalls back and tells you to record one.
;
; Recording (tray menu "Record potion route..."): the bot marks your spot and takes you to the Commons;
; walk to the potion seller with the keyboard (W A S D / arrows - not the mouse, a camera turn isn't
; recorded), press X to talk, click Fill All (and whatever closes the window), then press F9. It saves
; the route for that Commons and recalls you back. Record on the same mount you'll farm with: a route is
; a timing.

global PotionNextCheck := 0, PotionMaxHp := 0, PotionFailUntil := 0, PotionRecording := 0
global PotionRec := "", PotionRecStop := 0, PotionRecT0 := 0, PotionRecDown := "", PotionHook := ""
;A refill run that stopped half way (a battle on the route): its mark is still the right one, so the next
;run doesn't mark again (that would move it to the middle of the route)
global PotionMarkZone := "", PotionMarkAt := 0

;Called out of battle from the main loop (every few seconds at most): low health -> drink, none -> run
PotionCheck()
	{
	if (A_TickCount < PotionNextCheck || PotionRecording || !VisionOn || !GameActive())
		return
	PotionNextCheck := A_TickCount + 4000
	hp := PotionHealth()
	if (hp = "")
		return
	most := PotionMost()
	if (hp > most)
		PotionNoteMax(hp, false), most := hp
	limit := Stats.HasKey("potionat") ? Stats["potionat"] : 40
	if (!most || 100 * hp / most >= limit)
		return
	DebugLog("Potions: health " hp "/" most " (" Round(100 * hp / most) "%) - under " limit "%: drinking a potion")
	if (PotionDrink(hp))
		return
	if (A_TickCount < PotionFailUntil)
		return
	DebugLog("Potions: no potion left - going to buy some")
	if (!PotionRun())
		PotionFailUntil := A_TickCount + 10 * 60000
	}

;Health off the globe, read twice the same ("" if not)
PotionHealth()
	{
	a := PotionGlobes()
	Sleep, 250
	b := PotionGlobes()
	return (a.hp != "" && a.hp = b.hp) ? a.hp + 0 : ""
	}

;{hp, mana} off the globes ("" each that can't be read)
PotionGlobes()
	{
	answer := VisionGet("/globes?left=" GameLeft "&bottom=" GameTop + GameH "&scale=" Round(UiScale, 3), 1500)
	RegExMatch(answer, "health\|(\d*)", h), RegExMatch(answer, "mana\|(\d*)", m)
	;(for the dashboard)
	if (h1 != "")
		DashSee("hp", h1 (PotionMost() ? "/" PotionMost() " (" Round(100 * h1 / PotionMost()) "%)" : ""))
	if (m1 != "")
		DashSee("mana", m1)
	return {hp: h1, mana: m1}
	}

;Your most health: the name plate's max (battle) for this school's wizard, else the most the globe showed
PotionMost()
	{
	if (school != "" && Stats.HasKey(school ".maxhealth"))
		return Max(Stats[school ".maxhealth"], PotionMaxHp)
	return PotionMaxHp
	}

;A most-health reading: exact (off the name plate in battle) is kept in PlayerStats.txt per school
PotionNoteMax(n, exact := true)
	{
	if (!exact)
		{
		PotionMaxHp := Max(PotionMaxHp, n)
		return
		}
	PotionMaxHp := n
	if (school != "" && Stats[school ".maxhealth"] != n)
		StatsSet([[school ".maxhealth", n]], "your " school " wizard's most health (off its name plate in battle; Potions.ahk)")
	}

;Drinks a potion (Ctrl+O). True if health went up
PotionDrink(before)
	{
	ReleaseKeys()
	Send, {Blind}^o
	Sleep, 2500
	after := PotionHealth()
	if (after != "" && after > before + Max(5, PotionMost() // 50))
		{
		DebugLog("Potions: drank one - health " before " -> " after)
		return true
		}
	DebugLog("Potions: health didn't go up (" before " -> " (after = "" ? "?" : after) ") - no potion left")
	return false
	}

;The refill run (see the top of this file). True if it came back with potions
PotionRun()
	{
	ReleaseKeys()
	startZone := WalkZone(true)
	;1. Mark here (unless a run that stopped half way already did)
	if (!(PotionMarkZone != "" && A_TickCount - PotionMarkAt < 15 * 60000))
		{
		Send, {Blind}{PgDn}
		PotionMarkZone := startZone, PotionMarkAt := A_TickCount
		DebugLog("Potions: marked this spot (Page Down) in " startZone)
		Sleep, 1500
		}
	;2. To this world's Commons
	if (!PotionTeleport("{End}", "the Commons"))
		return false
	commons := WalkZone(true)
	route := PotionRouteFile(commons)
	if (!FileExist(route))
		{
		DebugLog("Potions: no potion route recorded from " commons " - going back (tray menu 'Record potion route...')")
		TrayTip, Wizard101 bot, % "Out of potions, and there's no route to the potion seller from " commons ".`nRecord one: tray menu 'Record potion route...'", 10, 2
		PotionRecall()
		return false
		}
	;3. The route
	if (!PotionReplay(route))
		{
		ReleaseKeys()
		return false
		}
	;4. Drink, back to the mark
	hp := PotionHealth()
	if (hp != "")
		PotionDrink(hp)
	PotionRecall()
	return true
	}

;Recall (Page Up) to the mark, if this run made one
PotionRecall()
	{
	if (PotionMarkZone = "")
		return
	DebugLog("Potions: back to the mark (Page Up)")
	if (PotionTeleport("{PgUp}", "the mark") && WalkZone(true) != PotionMarkZone)
		DebugLog("Potions: the recall went to " WalkZone(true) ", not " PotionMarkZone " where the mark was made - carrying on from here")
	PotionMarkZone := "", PotionMarkAt := 0
	}

;Presses a teleport key and waits for the loading screen to come and go (up to 60 s). True if it did
PotionTeleport(key, what)
	{
	before := WalkZone(true)
	Send, {Blind}%key%
	t0 := A_TickCount
	while (A_TickCount - t0 < 60000)
		{
		Sleep, 250
		WalkZone(true)
		if (!WkLoading && WkLoadedAt > t0 + 500)
			{
			Sleep, 2500
			DebugLog("Potions: at " what " (" WalkZone(true) ")")
			return true
			}
		}
	DebugLog("Potions: no loading screen after " key " for " what " (still in " before ") - stopping")
	return false
	}

;routes\<zone>.txt for a Commons zone
PotionRouteFile(zone)
	{
	return A_WorkingDir "\routes\" RegExReplace(zone, "[^\w-]", "_") ".txt"
	}

;Replays a recorded route. False if it was stopped (a battle, your hands, a Crown, a load that didn't come)
PotionReplay(route)
	{
	FileRead, text, %route%
	t0 := A_TickCount, ok := true, down := {}
	DebugLog("Potions: replaying " route)
	Loop, Parse, text, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 3 || f[1] = "start" || SubStr(A_LoopField, 1, 1) = ";")
			continue
		;(wait for the event's time, watching for trouble)
		while (A_TickCount - t0 < f[1])
			{
			if (!PotionOk())
				{
				ok := false
				break
				}
			Sleep, 10
			}
		if (!ok)
			break
		if (f[2] = "key")
			{
			name := f[3]
			Send, % "{Blind}{" name (f[4] = "down" ? " down" : " up") "}"
			down[name] := (f[4] = "down")
			}
		else if (f[2] = "click")
			{
			x := Round(GameLeft + GameW / 2 + f[3] * UiScale), y := Round(GameTop + GameH / 2 + f[4] * UiScale)
			if (!PotionNoCrowns(x, y))
				{
				ok := false
				break
				}
			MouseMove, %x%, %y%, 3
			Sleep, 120
			Click
			}
		else if (f[2] = "zone")
			{
			;a loading screen on the route: wait till it's done (the same zone as when recorded), then the
			;times go on from there (a key held through it stays held, as it was when recorded)
			w0 := A_TickCount
			while (WalkZone(true) != f[3] || WkLoading)
				{
				if (A_TickCount - w0 > 60000 || !PotionOk(false))
					{
					DebugLog("Potions: the route's loading screen to " f[3] " didn't come (in " WalkZone(true) ") - stopping")
					ok := false
					break
					}
				Sleep, 50
				}
			if (!ok)
				break
			t0 := A_TickCount - f[1]
			}
		}
	for name, isDown in down
		if (isDown)
			Send, % "{Blind}{" name " up}"
	ReleaseKeys()
	DebugLog("Potions: route " (ok ? "done" : "stopped"))
	return ok
	}

;Fine to carry on with a run: Wizard101 in front, your hands off, no battle
PotionOk(watchHands := true)
	{
	if (!GameActive())
		{
		DebugLog("Potions: Wizard101 isn't the active window - stopping")
		return false
		}
	if (watchHands && A_TimeIdlePhysical < 400)
		{
		DebugLog("Potions: you touched the mouse or keyboard - stopping (the bot leaves it to you)")
		return false
		}
	ImageSearch, bx, by, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, % PicOpt("resources\roundstart.png")
	if (ErrorLevel = 0)
		{
		DebugLog("Potions: a battle started - stopping the run (the next one won't mark again)")
		return false
		}
	return true
	}

;No "Crown" anywhere round a click (it only ever buys with gold). False (and stops) if there is
PotionNoCrowns(x, y)
	{
	r := Round(260 * UiScale)
	text := OcrRect(Max(GameLeft, x - r), Max(GameTop, y - r), 2 * r, 2 * r, "en", 1)
	if (RegExMatch(text, "i)cr[o0]wn"))
		{
		DebugLog("Potions: ""Crown"" on screen by the next click - not clicking, stopping (gold only): " RegExReplace(text, "\s+", " "))
		TrayTip, Wizard101 bot, The potion run saw "Crowns" on screen and stopped (it only buys with gold)., 10, 2
		return false
		}
	return true
	}

;---- Recording a route (tray menu) ----

PotionRecordStart()
	{
	if (PotionRecording)
		return
	if (!VisionOn)
		{
		MsgBox, 48, Record potion route, % "The vision helper isn't running, so the bot can't follow loading screens. Restart the bot (Windows+1) and try again."
		return
		}
	MsgBox, 65, Record potion route, % "The bot will mark your spot (Page Down) and take you to this world's Commons (End).`n`nThen walk to the potion seller (Hilda Brewer) with the KEYBOARD only, press X to talk, click Fill All with GOLD (and close the window), and press F9.`n`nUse the mount you'll farm with. The bot recalls you back afterwards."
	IfMsgBox, Cancel
		return
	WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
	Sleep, 500
	PotionRecording := 1
	ReleaseKeys()
	startZone := WalkZone(true)
	Send, {Blind}{PgDn}
	PotionMarkZone := startZone, PotionMarkAt := A_TickCount
	Sleep, 1500
	if (!PotionTeleport("{End}", "the Commons"))
		{
		PotionRecording := 0
		MsgBox, 48, Record potion route, The teleport to the Commons didn't happen (no loading screen) - nothing recorded.
		return
		}
	commons := WalkZone(true)
	PotionRec := "start|" commons "|" Round(UiScale, 3) "|" GameW "x" GameH "`r`n", PotionRecStop := 0, PotionRecDown := {}
	PotionHook := InputHook("V L0")
	PotionHook.KeyOpt("{All}", "N")
	PotionHook.OnKeyDown := Func("PotionRecKey").Bind(1)
	PotionHook.OnKeyUp := Func("PotionRecKey").Bind(0)
	Hotkey, ~*LButton, PotionRecClick, On
	Hotkey, F9, PotionRecF9, On
	PotionRecT0 := A_TickCount
	PotionHook.Start()
	TrayTip, Wizard101 bot, % "Recording from " commons ": walk to the potion seller, buy Fill All, then press F9.", 10, 1
	DebugLog("Potions: recording a route from " commons)
	lastZone := commons, t0 := A_TickCount
	;(a loading screen on the way: noted when it's done, as replaying waits for that and goes on from there)
	while (!PotionRecStop && A_TickCount - t0 < 15 * 60000)
		{
		Sleep, 50
		z := WalkZone(true)
		if (z != lastZone && !WkLoading)
			PotionRec .= (A_TickCount - PotionRecT0) "|zone|" z "`r`n", lastZone := z
		}
	PotionHook.Stop()
	Hotkey, ~*LButton, Off
	Hotkey, F9, Off
	PotionRecording := 0
	FileCreateDir, % A_WorkingDir "\routes"
	file := PotionRouteFile(commons)
	FileDelete, %file%
	FileAppend, % "; Potion route from " commons ", recorded " A_YYYY "-" A_MM "-" A_DD " " A_Hour ":" A_Min " (Potions.ahk): ms|key|name|down/up, ms|click|x|y (UI px from the window's middle), ms|zone|<zone after a loading screen>`r`n" PotionRec, %file%
	DebugLog("Potions: route saved: " file)
	MsgBox, 64, Record potion route, % "Saved the route from " commons ".`n`nThe bot now recalls you to where you were (Page Up)."
	WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
	Sleep, 500
	PotionRecall()
	}

;A key going down or up while recording (repeats of a held key and keys with Ctrl/Alt/Win aren't kept;
;F9 ends the recording)
PotionRecKey(isDown, hook, vk, sc)
	{
	name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
	if (name = "F9" || InStr(name, "Control") || InStr(name, "Alt") || InStr(name, "Win") || InStr(name, "Shift"))
		return
	if (isDown && (GetKeyState("Ctrl") || GetKeyState("Alt") || GetKeyState("LWin") || GetKeyState("RWin")))
		return
	if (isDown && PotionRecDown[name])
		return
	if (!isDown && !PotionRecDown[name])
		return
	PotionRecDown[name] := isDown
	PotionRec .= (A_TickCount - PotionRecT0) "|key|" name "|" (isDown ? "down" : "up") "`r`n"
	}

PotionRecClick:
	CoordMode, Mouse, Screen
	MouseGetPos, mx, my
	if (GameActive())
		PotionRec .= (A_TickCount - PotionRecT0) "|click|" Round((mx - GameLeft - GameW / 2) / UiScale, 1) "|" Round((my - GameTop - GameH / 2) / UiScale, 1) "`r`n"
	return

PotionRecF9:
	PotionRecStop := 1
	return
