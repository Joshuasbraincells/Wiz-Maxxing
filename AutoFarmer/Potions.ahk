; Potions.ahk - out of battle: drinks a potion when your health is low, and when there are none left goes
; to buy more with gold (never Crowns): Recall to your Mark at the potion seller and the buying you
; recorded there once. AHK v1.1, functions only; #Included by Autofarmer.ahk. Needs the vision helper
; (Vision.ahk) to read the globes.
;
; Health: the number on the red globe (vision.py /globes, digit pictures in ui1.144\globedigits), as a %
; of your most health (read off your name plate in battle - <school>.maxhealth in PlayerStats.txt - or
; the most the globe has shown). Under potionat % (PlayerStats.txt, default 40) it drinks (Ctrl+O, the
; game's Drink Potion key); health not going up after that means no potion was left.
;
; Out of potions (potionmark:1, the default): your Mark is at the potion seller - you leave it there
; (Page Down, right next to Hilda Brewer) and the bot never marks anywhere else:
;   1. Recall (Page Up) to the Mark - a recall keeps the Mark, so it's there for the next run too (none
;      when you're at the seller already)
;   2. the buying recorded there (routes\mark_<wizard>.txt - each wizard has its own Mark, so its own
;      recording: X to talk, the Fill All click, closing it), once the seller's "Press X" prompt with the
;      name read when recording (HILDA BREWER) shows - else it's the wrong place and nothing is clicked
;   3. drink, then carry on from there: walking follows the quest arrow from the seller (the walker
;      starts afresh). Mob-loop, lore and afk farming have no way back to their spot yet - it tells you
; Nothing recorded for this wizard yet: no recall (it would only pull you off your quest) - it tells you
; how to set it up. No Mark or too little mana (Page Up does nothing): it tells you and tries again 10
; minutes later. A Recall in the Mark's own zone may come without a loading screen: the seller's prompt
; showing, or mana going down (the Recall's cost), counts as arrived. The Mark somewhere else (another zone, or no seller's prompt there): no more
; recalls for this wizard till the bot restarts or you record the buying again. A run that ends without health going up (no gold, a missed click) waits 10 minutes
; too. Page Down / Page Up / Home / End are never recorded or replayed (Page Down while recording at the
; Mark: your Mark moved there, so the recording starts over from there).
;
; potionmark:0 - a refill run along a route (routes\<zone>.txt) instead, which moves your Mark:
;   1. Mark Location (Page Down) where you are
;   2. Go Home (the Home key) - you always land in the same spot there, and it's the same house from any
;      world, so one route does for all (potionfromhome:0 in PlayerStats.txt: the world's Commons (End)
;      instead - but you land somewhere different there each time); the game's log says which zone it is
;   3. the route recorded from there: your keys (walking, X to talk) and left clicks (Hilda
;      Brewer's "Fill All" etc.), replayed with the same timing; loading screens on the way are waited for
;   4. drink (now there are potions), then Recall (Page Up) back to the mark
; Before every click it reads the screen round it: any "Crown" there stops the run (it buys with gold
; only). A battle, you touching the mouse or keyboard, or a loading screen that doesn't come stops it too.
; No route from there: it recalls back and tells you to record one.
;
; By the zone's map (potionwalk:1, the default) - nothing recorded: the potion sellers' spots are in the game's
; own files (the vision helper reads them: Hilda Brewer in Wizard City's Commons, one in the Arcanum). Out of
; potions in a zone with one, the bot walks to her by the zone's map (the route planner, the game's memory -
; read-only), presses X at her prompt and clicks Fill All (found by the words on it, never with "Crown" round
; it), closes the window and drinks. Elsewhere: a Recall (Page Up) to your Mark - leave it anywhere in the
; Commons - or in Wizard City the Commons (End), then the same. A buying you recorded at your Mark is still used
; when there is one; anything that can't be done by the map falls back to the recorded ways below.
;
; Recording (tray menu "Record potion buying..."): the bot recalls you to your Mark (Page Up); press X to
; talk, click Fill All (and whatever closes the window), then press F9. You stay at the seller.
; potionmark:0: the bot marks your spot and takes you Home (or to the Commons); walk to the potion seller
; with the keyboard (W A S D / arrows - not the mouse, a camera turn isn't recorded), press X to talk,
; click Fill All (and whatever closes the window), then press F9. It saves the route for that start and
; recalls you back. Record on the same mount you'll farm with: a route is a timing.

global PotionNextCheck := 0, PotionMaxHp := 0, PotionFailUntil := 0, PotionRecording := 0
global PotionRec := "", PotionRecStop := 0, PotionRecT0 := 0, PotionRecDown := "", PotionHook := ""
;A refill run that stopped half way (a battle on the route): its mark is still the right one, so the next
;run doesn't mark again (that would move it to the middle of the route)
global PotionMarkZone := "", PotionMarkAt := 0
;The Mark way: per wizard, where its Mark turned out to be when that's not where the buying was recorded
;(no more recalls for it till a restart or a new recording); recording at the Mark, and a Page Down during
;it (start over)
;(PotionMarkOff: made by PotionOff - an initializer here never runs, as this file is #Included at the bottom)
global PotionMarkOff, PotionRecAtMark := 0, PotionRecRestart := 0

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
	;(by the zone's map - potionwalk:1: "" when it can't be done that way here, or didn't work and there's a recorded
	;way to try - then the recorded ways)
	if (PotionWalkOn())
		{
		walked := PotionRunWalk()
		if (walked != "")
			return walked
		}
	if (PotionByMark())
		return PotionRunMark()
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
	;2. Home (or this world's Commons)
	if (!PotionTeleport(PotionStartKey(), PotionStartName()))
		return false
	commons := WalkZone(true)
	route := PotionRouteFile(commons)
	if (!FileExist(route))
		{
		DebugLog("Potions: no potion route recorded from " commons " - going back (tray menu 'Record potion buying...')")
		TrayTip, Wizard101 bot, % "Out of potions, and there's no route to the potion seller from " commons ".`nRecord one: tray menu 'Record potion buying...'", 10, 2
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
	ok := PotionAfterBuy()
	PotionRecall()
	return ok
	}

;Whether your Mark is at the potion seller (potionmark:1, the default) - else potionmark:0, the route way
PotionByMark()
	{
	return !(Stats.HasKey("potionmark") && !Stats["potionmark"])
	}

;The Mark way: Recall to the seller, the buying recorded there, drink, carry on from there. True if it
;bought (it never presses Page Down: that would move your Mark off the seller)
PotionRunMark()
	{
	ReleaseKeys()
	;(nothing recorded for this wizard: a recall would only pull you off your quest to wherever its Mark is)
	who := PotionWho(), route := PotionMarkFile(who)
	if (route = "")
		{
		DebugLog("Potions: out of potions, but no buying recorded at this wizard's Mark yet - not recalling. Leave a Mark (Page Down) right next to the potion seller (Hilda Brewer), then tray menu 'Record potion buying...'")
		TrayTip, Wizard101 bot, % "Out of potions. To buy more: leave a Mark (Page Down) right next to the potion seller (Hilda Brewer, Wizard City's Commons), then tray menu 'Record potion buying...' (once for each wizard).", 10, 2
		return false
		}
	marksOff := PotionOff()
	if (marksOff.HasKey(who))
		{
		DebugLog("Potions: out of potions - not recalling: this wizard's Mark was in " marksOff[who] ", not at the potion seller (Mark next to her again, then restart the bot - Windows+1)")
		return false
		}
	rec := PotionMarkInfo(route)
	if (PotionAtSeller(rec))
		DebugLog("Potions: at the potion seller already (" rec.prompt "'s prompt is up) - no Recall")
	else
		{
		g := PotionGlobes()
		DebugLog("Potions: Recall (Page Up) to your Mark at the potion seller")
		if (!PotionTeleport("{PgUp}", "your Mark", Func("PotionArrived").Bind(rec, g.mana)))
			{
			low := (g.mana != "" && g.mana < 10)
			DebugLog("Potions: no Recall - " (low ? "mana is " g.mana ", and a Recall costs up to 10" : "no Mark, or too little mana for it? The Mark goes right next to the potion seller (Hilda Brewer)"))
			TrayTip, Wizard101 bot, % "Out of potions, and Page Up (Recall) went nowhere.`n" (low ? "Mana is " g.mana " - a Recall costs up to 10." : "No Mark, or too little mana for the Recall. The Mark goes right next to the potion seller (Hilda Brewer)."), 10, 2
			return false
			}
		}
	;(the right place: the zone the buying was recorded in, and the seller's prompt there if one was read)
	shop := WalkZone(true), there := (rec.zone = "" || shop = rec.zone)
	if (there && rec.prompt != "")
		{
		t0 := A_TickCount
		while (!(there := PotionAtSeller(rec)) && A_TickCount - t0 < 4000)
			Sleep, 500
		}
	if (!there)
		{
		marksOff[who] := shop
		DebugLog("Potions: this wizard's Mark is in " shop (shop = rec.zone ? " but not by " rec.prompt " (no prompt with that name)" : ", but the buying was recorded in " rec.zone) " - the Mark isn't at the potion seller. Nothing clicked; no more recalls till you Mark (Page Down) next to her again and restart the bot (Windows+1), or record the buying again")
		TrayTip, Wizard101 bot, % "This wizard's Mark isn't at the potion seller (it's in " shop ").`nMark (Page Down) right next to Hilda Brewer again, then restart the bot (Windows+1).", 10, 2
		PotionCarryOn(false)
		return false
		}
	if (!PotionReplay(route))
		{
		ReleaseKeys()
		PotionCarryOn(false)
		return false
		}
	ok := PotionAfterBuy()
	PotionCarryOn(ok)
	return ok
	}

;The per-wizard list of Marks found away from the seller (PotionMarkOff), made the first time it's needed
PotionOff()
	{
	if (!IsObject(PotionMarkOff))
		PotionMarkOff := {}
	return PotionMarkOff
	}

;Which wizard is logged in (its CharID off the game's log; "anyone" if that can't be read): each one has
;its own Mark, so its own recording
PotionWho()
	{
	id := IsFunc("StatsCharID") ? Func("StatsCharID").Call() : ""
	return id = "" ? "anyone" : id
	}

;routes\mark_<wizard>.txt, the buying recorded at that wizard's Mark (forSave: the name to save under;
;else "" if there's none). mark_anyone.txt (recorded while the game's log didn't say which wizard) is only
;used while it still doesn't - never for a wizard it can tell, whose Mark may be anywhere
PotionMarkFile(who, forSave := false)
	{
	file := A_WorkingDir "\routes\mark_" who ".txt"
	return (forSave || FileExist(file)) ? file : ""
	}

;{zone, prompt} off a Mark recording's start line (start|zone|scale|size|mark|prompt)
PotionMarkInfo(file)
	{
	FileReadLine, line, %file%, 2
	f := StrSplit(line, "|")
	return {zone: f[1] = "start" ? f[2] : "", prompt: f[1] = "start" ? f[6] : ""}
	}

;The name on the "Press X to ..." prompt showing now (the walker's reading of it, letters only), "" if none
PotionPrompt()
	{
	if (!IsFunc("InteractPrompt"))
		return ""
	return Func("InteractPrompt").Call() = "press" ? WkPromptDest : ""
	}

;The prompt's name read the same twice running ("" if not: a reading that changes each time - no title line,
;just OCR letters - can't be checked against later)
PotionPromptSteady()
	{
	a := PotionPrompt()
	Loop, 3
		{
		Sleep, 400
		b := PotionPrompt()
		if (a != "" && a = b)
			return a
		a := b
		}
	return ""
	}

;Arrived with no loading screen (a Recall in the same zone): the seller's prompt is up, or mana went down
;(read twice the same - the Recall's cost; nothing else costs mana out of battle)
PotionArrived(rec, manaBefore)
	{
	if (PotionAtSeller(rec))
		return true
	if (manaBefore = "")
		return false
	a := PotionGlobes().mana
	Sleep, 250
	b := PotionGlobes().mana
	return (a != "" && a = b && a < manaBefore)
	}

;Whether the prompt read when the buying was recorded is showing now (OCR: a letter or two may differ).
;False when none was read then
PotionAtSeller(rec)
	{
	if (rec.prompt = "")
		return false
	now := PotionPrompt()
	if (now = "")
		return false
	if (now = rec.prompt)
		return true
	return IsFunc("WalkEditDistance") && Func("WalkEditDistance").Call(now, rec.prompt) <= Max(1, StrLen(rec.prompt) // 5)
	}

;After buying: drinks if health is still under potionat %. False if that drink didn't work - nothing was
;bought (no gold, a click that missed), so PotionCheck waits 10 minutes before another run
PotionAfterBuy()
	{
	hp := PotionHealth(), most := PotionMost()
	limit := Stats.HasKey("potionat") ? Stats["potionat"] : 40
	if (hp = "")
		{
		DebugLog("Potions: can't read your health after buying - not drinking")
		return true
		}
	if (most && 100 * hp / most >= limit)
		return true
	if (PotionDrink(hp))
		return true
	DebugLog("Potions: still no potion after buying - nothing bought? (no gold, or a click missed - record the buying again)")
	return false
	}

;After the Mark way: the walker starts afresh from the seller (it's somewhere new); other farming can't get
;back to its spot yet, so you're told
PotionCarryOn(bought)
	{
	PotionWalkFresh()
	if (Walking && !afk && !loopmode && !loremode)
		{
		DebugLog("Potions: " (bought ? "bought" : "didn't buy") " - following the quest arrow on from your Mark")
		return
		}
	why := afk ? "afk farming" : loopmode ? "mob-loop farming" : loremode ? "lore farming" : ""
	DebugLog("Potions: " (bought ? "bought" : "didn't buy") " - staying at your Mark (" (why = "" ? "walking is off - F8" : why " has no way back to its spot yet") ")")
	if (bought)
		TrayTip, Wizard101 bot, % "Bought potions - you're at the potion seller. " (why = "" ? "Walking is off (F8), so the bot stays there." : "The bot can't get back to your " why " spot yet, so take it back yourself."), 10, 1
	}

;The walker starts afresh, and presses no X at a prompt for a while (DialogQuiet): it's standing by the
;seller, whose "Press X to talk" would reopen the shop
PotionWalkFresh()
	{
	if (!IsFunc("WalkReset"))
		return
	Func("WalkReset").Call()
	WkQuietUntil := A_TickCount + DialogQuiet, WkQuietLogged := 0
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

;Presses a teleport key and waits for the loading screen to come and go (up to 60 s). True if it did.
;Nothing loading after 15 s with the spellbook still on screen (no Mark, too little mana): it gives up then;
;a battle starting stops it too. arrived (a Func, optional): true once there with no loading screen (a
;Recall in the same zone), looked at every second from 3 s on
PotionTeleport(key, what, arrived := "")
	{
	before := WalkZone(true)
	Send, {Blind}%key%
	t0 := A_TickCount, started := false
	while (A_TickCount - t0 < 60000)
		{
		Sleep, 250
		WalkZone(true)
		if (WkLoading)
			started := true
		if (!WkLoading && WkLoadedAt > t0 + 500)
			{
			Sleep, 2500
			DebugLog("Potions: at " what " (" WalkZone(true) ")")
			return true
			}
		if (started || Mod(A_Index, 4))
			continue
		if (IsObject(arrived) && A_TickCount - t0 > 3000 && arrived.Call())
			{
			DebugLog("Potions: at " what " - no loading screen (" WalkZone(true) ")")
			return true
			}
		ImageSearch, bx, by, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, % PicOpt("resources\roundstart.png")
		if (ErrorLevel = 0)
			{
			DebugLog("Potions: a battle started instead of " key " for " what " - stopping")
			return false
			}
		if (A_TickCount - t0 > 15000)
			{
			ImageSearch, bx, by, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, % PicOpt("resources\roundfinish.png")
			if (ErrorLevel = 0)
				break
			}
		}
	DebugLog("Potions: no loading screen after " key " for " what " (still in " before ") - stopping")
	return false
	}

;Where routes start: Home (the Home key; potionfromhome:1, the default) or the world's Commons (End)
PotionStartKey()
	{
	return (Stats.HasKey("potionfromhome") && !Stats["potionfromhome"]) ? "{End}" : "{Home}"
	}

PotionStartName()
	{
	return PotionStartKey() = "{Home}" ? "your house (Home)" : "the Commons (End)"
	}

;routes\<zone>.txt for the zone a route starts in (potionmark:0)
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
			;(never Page Down / Page Up / Home / End: they'd move your Mark or teleport you off the route)
			if (RegExMatch(name, "i)^(Numpad)?(PgDn|PgUp|Home|End)$"))
				{
				if (f[4] = "down")
					DebugLog("Potions: " name " in the recording - skipped")
				continue
				}
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
			;(the mouse back where it was afterwards, unless that's done at the end of the run: mousereturn)
			ownGrab := MouseGrab()
			MouseMove, %x%, %y%, 3
			Sleep, 120
			Click
			if (ownGrab)
				MouseLetGo()
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
PotionOk(watchHands := true, since := 0)
	{
	if (!GameActive())
		{
		DebugLog("Potions: Wizard101 isn't the active window - stopping")
		return false
		}
	;(since: the run's start - any key or mouse of yours after it, not only in the last 400 ms)
	if (watchHands && (A_TimeIdlePhysical < 400 || (since && A_TickCount - A_TimeIdlePhysical > since)))
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
	;(the screen couldn't be read there: no click - it can't be sure there's no Crown)
	if (ErrorLevel)
		{
		DebugLog("Potions: the screen round the next click couldn't be read - not clicking, stopping (gold only)")
		return false
		}
	if (RegExMatch(text, "i)cr[o0]wn"))
		{
		DebugLog("Potions: ""Crown"" on screen by the next click - not clicking, stopping (gold only): " RegExReplace(text, "\s+", " "))
		TrayTip, Wizard101 bot, The potion run saw "Crowns" on screen and stopped (it only buys with gold)., 10, 2
		return false
		}
	return true
	}

;---- To the potion seller by the zone's map (potionwalk:1) ----

;potionwalk in PlayerStats.txt (the Settings window), on unless it's 0
PotionWalkOn()
	{
	return !(Stats.HasKey("potionwalk") && !Stats["potionwalk"])
	}

;The potion seller placed in zone ({name, x, y, z}), from the zone's own file (the vision helper's /seller), or ""
PotionSellerIn(zone)
	{
	static seen := {}
	if (zone = "")
		return ""
	if (seen.HasKey(zone))
		return seen[zone]
	answer := VisionGet("/seller?zone=" LearnUri(zone), 5000, true)
	;(no answer, or the zone's file not read: asked again next time)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	s := ""
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "seller" && f.Length() >= 5)
			{
			s := {name: f[2], x: f[3] + 0, y: f[4] + 0, z: f[5] + 0, zone: zone}
			break
			}
		}
	seen[zone] := s
	return s
	}

;Where the wizard is and the route to s (the vision helper's /navto: the game's memory, read-only, and its own
;route planner along the zone's map): {x, y, z, yaw, ax, ay, why} - ax/ay "" with no route - or ""
PotionNavTo(s)
	{
	answer := VisionGet("/navto?x=" Round(s.x, 1) "&y=" Round(s.y, 1) "&z=" Round(s.z, 1), 2500, true)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	nav := {x: "", y: "", z: "", yaw: "", ax: "", ay: "", left: "", why: "", zone: ""}
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "pos")
			nav.x := f[2], nav.y := f[3], nav.z := f[4], nav.yaw := f[5]
		else if (f[1] = "zone")
			nav.zone := f[2]
		else if (f[1] = "route")
			nav.ax := f[2], nav.ay := f[3], nav.left := f[4]
		else if (f[1] = "routewhy")
			nav.why := Trim(SubStr(A_LoopField, 10))
		}
	return (nav.x = "" || nav.yaw = "") ? "" : nav
	}

;W held down / let go (the walker's HoldW only works while walking is on)
PotionHoldW(on)
	{
	if (on && !HeldW && GameActive())
		{
		KeysDown := 1
		Send, {Blind}{w down}
		HeldW := 1
		}
	else if (!on && HeldW)
		{
		Send, {Blind}{w up}
		HeldW := 0
		}
	}

;A turn of h degrees (+ right): A or D held for as long as the walker's TurnRate says
PotionTurnBy(h)
	{
	if (!GameActive())
		return
	key := h < 0 ? "a" : "d"
	ms := Round(Abs(h) / (TurnRate > 0 ? TurnRate : 0.15))
	ms := ms < 30 ? 30 : ms > 800 ? 800 : ms
	KeysDown := 1
	Send, {Blind}{%key% down}
	Sleep, %ms%
	Send, {Blind}{%key% up}
	}

;Walks to the potion seller s by the zone's map: steering at the route's aim (a point ahead on it, round walls)
;by the game's memory. Stuck (no closer in 6 s): backs up and turns, 3 times at most. True once within 140 of
;her. Stops for a battle, your hands on the keys or mouse, the game's memory unreadable, or 2.5 minutes
PotionWalkTo(s, since := 0)
	{
	;(steering by the game's memory needs its heading's sign checked - the walker does that as it walks quests)
	if (!WkNavChecked && !WkNavTrusted)
		{
		DebugLog("Potions: can't walk to the potion seller by the map yet - the game's memory hasn't been checked against the quest arrow (it is after a minute of walking a quest)")
		return false
		}
	ReleaseKeys()
	DebugLog("Potions: walking to the potion seller (" s.name ") by the zone's map - " s.zone " at " Round(s.x) ", " Round(s.y))
	t0 := A_TickCount, best := "", bestLeft := "", bestAt := A_TickCount, unstuck := 0, said := "", misses := 0
	since := since ? since : t0
	Loop
		{
		if (!PotionOk(true, since))
			{
			ReleaseKeys()
			return false
			}
		nav := PotionNavTo(s)
		;(a moment with no answer - the helper busy - is asked again; three running: stop)
		if (!IsObject(nav))
			{
			misses += 1
			if (misses < 3)
				{
				Sleep, 300
				continue
				}
			ReleaseKeys()
			DebugLog("Potions: the game's memory can't be read (" VisionErr ") - not walking to the potion seller")
			return false
			}
		misses := 0
		;(walked through a gateway into another zone: not where she is)
		if (nav.zone != "" && nav.zone != s.zone)
			{
			ReleaseKeys()
			DebugLog("Potions: walked into " nav.zone " on the way to the potion seller - stopping")
			return false
			}
		if (nav.ax = "" && nav.why != said)
			said := nav.why, DebugLog("Potions: no route round walls (" nav.why ") - straight at her")
		d := Sqrt((nav.x - s.x) ** 2 + (nav.y - s.y) ** 2)
		if (d <= 140)
			{
			ReleaseKeys()
			DebugLog("Potions: at the potion seller (" Round(d) " away, " Round((A_TickCount - t0) / 1000) " s)")
			return true
			}
		if (A_TickCount - t0 > 150000)
			{
			ReleaseKeys()
			DebugLog("Potions: not at the potion seller after 2.5 minutes (" Round(d) " away) - stopping")
			return false
			}
		;(getting on: closer as the crow flies, or along the route round walls - a detour isn't being stuck)
		if (best = "" || d < best - 40)
			best := d, bestAt := A_TickCount, unstuck := 0
		if (nav.left != "" && (bestLeft = "" || nav.left < bestLeft - 40 || nav.left > bestLeft + 300))
			bestLeft := nav.left, bestAt := A_TickCount, unstuck := 0
		if (A_TickCount - bestAt > 6000)
			{
			unstuck += 1
			if (unstuck > 3)
				{
				ReleaseKeys()
				DebugLog("Potions: stuck " Round(d) " from the potion seller (no closer after backing up 3 times) - stopping")
				return false
				}
			DebugLog("Potions: no closer in 6 s (" Round(d) " away) - backing up and turning")
			PotionHoldW(0)
			Send, {Blind}{s down}
			Sleep, 700
			Send, {Blind}{s up}
			PotionTurnBy(Mod(unstuck, 2) ? 90 : -90)
			if (!PotionOk(true, since))
				{
				ReleaseKeys()
				return false
				}
			PotionHoldW(1)
			Sleep, 900
			bestAt := A_TickCount
			continue
			}
		h := WalkNavHeading(nav.x, nav.y, nav.yaw, nav.ax != "" ? nav.ax : s.x, nav.ay != "" ? nav.ay : s.y)
		h := (h = "") ? 0 : h
		if (Abs(h) > 60)
			{
			PotionHoldW(0)
			PotionTurnBy(h)
			}
		else
			{
			if (Abs(h) > 12)
				PotionTurnBy(h)
			PotionHoldW(1)
			}
		Sleep, 60
		}
	}

;The words firstRe (and nextRe right after it, if given) in the middle of the game window, by OCR: {x, y} (screen)
;of their middle, or "". text: what was read there
PotionFindWords(firstRe, nextRe := "", ByRef text := "", lone := false)
	{
	text := OcrRect(Round(GameLeft + GameW * 0.12), Round(GameTop + GameH * 0.08), Round(GameW * 0.76), Round(GameH * 0.84), "en", 1, lines)
	if (ErrorLevel || !IsObject(lines))
		return ""
	for i, line in lines
		{
		ws := line.words
		if (!IsObject(ws))
			continue
		for j, w in ws
			{
			if (!RegExMatch(Trim(w.text), firstRe) || (lone && ws.Length() != 1))
				continue
			if (nextRe = "")
				return {x: Round(w.x + w.w / 2), y: Round(w.y + w.h / 2)}
			if (j < ws.Length() && RegExMatch(Trim(ws[j + 1].text), nextRe))
				{
				v := ws[j + 1]
				return {x: Round((w.x + v.x + v.w) / 2), y: Round(w.y + w.h / 2)}
				}
			}
		}
	return ""
	}

;Closes the potion shop's window (Escape) - and the game's menu, if Escape opened that instead
PotionCloseShop()
	{
	Send, {Blind}{Escape}
	Sleep, 800
	;(a box on top of it closed instead: the shop's still up - Escape once more)
	if (IsObject(PotionFindWords("i)^fill$", "i)^all[.!]?$")))
		{
		Send, {Blind}{Escape}
		Sleep, 800
		}
	menuText := OcrRect(Round(GameLeft + GameW * 0.3), Round(GameTop + GameH * 0.15), Round(GameW * 0.4), Round(GameH * 0.7))
	if (!ErrorLevel && RegExMatch(menuText, "i)\b(quit|log\s*out|settings|options|resume|return to game)\b"))
		{
		DebugLog("Potions: Escape opened the game's menu - Escape again")
		Send, {Blind}{Escape}
		Sleep, 600
		}
	}

;At the potion seller: X at her prompt, Fill All in her window (never with "Crown" round it), a box asking to
;pay with gold OK'd (same rule), the window closed. True if Fill All was clicked
PotionBuyHere(s, since := 0)
	{
	ReleaseKeys()
	t0 := A_TickCount
	while ((name := PotionPrompt()) = "" && A_TickCount - t0 < 2500)
		Sleep, 300
	;(no prompt yet: a step closer - she may stand behind her stall)
	if (name = "")
		{
		nav := PotionNavTo(s)
		h := IsObject(nav) ? WalkNavHeading(nav.x, nav.y, nav.yaw, s.x, s.y) : ""
		if (h != "")
			{
			PotionTurnBy(h)
			PotionHoldW(1)
			Sleep, 500
			PotionHoldW(0)
			t0 := A_TickCount
			while ((name := PotionPrompt()) = "" && A_TickCount - t0 < 2000)
				Sleep, 300
			}
		}
	if (name = "")
		{
		DebugLog("Potions: by the potion seller, but no 'Press X' prompt shows - not buying")
		return false
		}
	if (!PotionOk(true, since))
		return false
	DebugLog("Potions: " name "'s prompt - X")
	Send, {Blind}x
	Sleep, 1800
	w := PotionFindWords("i)^fill$", "i)^all[.!]?$", seen)
	;(Crowns anywhere in the window: nothing clicked)
	if (IsObject(w) && RegExMatch(seen, "i)cr[o0]wn"))
		{
		DebugLog("Potions: ""Crown"" in the shop's window - not clicking, stopping (gold only): " SubStr(RegExReplace(seen, "\s+", " "), 1, 160))
		TrayTip, Wizard101 bot, The potion run saw "Crowns" on screen and stopped (it only buys with gold)., 10, 2
		PotionCloseShop()
		return false
		}
	if (!IsObject(w))
		{
		DebugLog("Potions: no Fill All on screen after X (read: " SubStr(RegExReplace(seen, "\s+", " "), 1, 160) ") - closing, not buying")
		PotionCloseShop()
		return false
		}
	if (!PotionNoCrowns(w.x, w.y) || !PotionOk(true, since))
		{
		PotionCloseShop()
		return false
		}
	DebugLog("Potions: Fill All at " w.x - GameLeft "," w.y - GameTop " - clicking")
	ClickAt(w.x, w.y, 300)
	Sleep, 1200
	;(a box asking to pay with gold: its OK / Yes - only with "gold" in it and no Crown round it)
	c := PotionFindWords("i)^(ok|okay|yes)[.!]?$", "", seen, true)
	if (IsObject(c) && RegExMatch(seen, "i)gold") && !RegExMatch(seen, "i)cr[o0]wn") && PotionOk(true, since) && PotionNoCrowns(c.x, c.y))
		{
		DebugLog("Potions: a box asking to pay with gold - OK")
		ClickAt(c.x, c.y, 300)
		Sleep, 1000
		}
	PotionCloseShop()
	return true
	}

;Out of potions, by the zone's map: the potion seller in this zone - else, in Wizard City, the Commons (End), or
;a Recall (Page Up) to your Mark - walked to, Fill All, drink, then on with the quest from there. True / false
;(bought or not); "" when the recorded ways are for here: a buying recorded at your Mark, potionmark:0's route,
;farming (afk, mob-loop, lore) away from her, the map walk impossible (the game's memory off, unchecked or
;unreadable) - checked before any teleport - or this way failed with a recorded one to try
PotionRunWalk()
	{
	ReleaseKeys()
	since := A_TickCount
	who := PotionWho()
	;(potionmark:0's route way is always there to try - it says so itself when there's no route)
	recorded := PotionByMark() ? PotionMarkFile(who) != "" : true
	;(the map walk needs the game's memory - on, its heading checked by the walker, readable now)
	if ((Stats.HasKey("navmem") && !Stats["navmem"]) || (!WkNavChecked && !WkNavTrusted))
		{
		DebugLog("Potions: no walking to the potion seller by the map (the game's memory " ((Stats.HasKey("navmem") && !Stats["navmem"]) ? "is off: navmem:0" : "hasn't been checked against the quest arrow yet - it is after a minute of walking a quest") ") - the recorded ways")
		return ""
		}
	zone := WalkZone(true)
	s := PotionSellerIn(zone)
	if (!IsObject(s))
		{
		;(the ways you set up - a buying recorded at your Mark, potionmark:0's routes - and farming, which has
		;no way back from the Commons: as before)
		if (recorded || !PotionByMark() || afk || loopmode || loremode)
			return ""
		if (!IsObject(PotionNavTo({x: 0, y: 0, z: 0})))
			{
			DebugLog("Potions: the game's memory can't be read (" VisionErr ") - no walking to the potion seller by the map")
			return ""
			}
		marksOff := PotionOff()
		;In Wizard City: the Commons (End) - she's there
		if (InStr(zone, "WizardCity/") = 1)
			{
			DebugLog("Potions: no potion seller in " zone " - to the Commons (End)")
			if (PotionTeleport("{End}", "the Commons"))
				zone := WalkZone(true), s := PotionSellerIn(zone)
			}
		;Elsewhere: a Recall to your Mark (anywhere in the Commons) - once: a Mark that led to no seller isn't
		;tried again till you record at it or restart the bot
		else if (!marksOff.HasKey(who))
			{
			g := PotionGlobes()
			DebugLog("Potions: no potion seller in " zone " - Recall (Page Up) to your Mark")
			if (PotionTeleport("{PgUp}", "your Mark", Func("PotionArrivedMana").Bind(g.mana)))
				{
				zone := WalkZone(true), s := PotionSellerIn(zone)
				if (!IsObject(s))
					marksOff[who] := zone
				}
			}
		if (!IsObject(s))
			{
			DebugLog("Potions: out of potions, and no potion seller here (" zone ") - leave your Mark (Page Down) anywhere in Wizard City's Commons: the bot recalls there and walks to Hilda Brewer by the map")
			TrayTip, Wizard101 bot, % "Out of potions, and no potion seller here.`nLeave your Mark (Page Down) anywhere in Wizard City's Commons - the bot recalls there and walks to Hilda Brewer.", 10, 2
			PotionCarryOn(false)
			return false
			}
		}
	if (!PotionWalkTo(s, since) || !PotionBuyHere(s, since))
		{
		ReleaseKeys()
		;(a recorded way to try, and nothing's said stop - a battle, your hands): that one
		if (recorded && WalkZone(true) = s.zone && PotionOk(true, since))
			{
			DebugLog("Potions: the walk to the potion seller didn't work - the recorded way instead")
			return ""
			}
		PotionCarryOn(false)
		return false
		}
	ok := PotionAfterBuy()
	PotionCarryOn(ok)
	return ok
	}

;A Recall with no loading screen (the Mark in this zone): mana went down - read twice the same (its cost)
PotionArrivedMana(manaBefore)
	{
	if (manaBefore = "")
		return false
	a := PotionGlobes().mana
	Sleep, 250
	b := PotionGlobes().mana
	return (a != "" && a = b && a < manaBefore)
	}

;---- Recording a route (tray menu) ----

PotionRecordStart()
	{
	if (PotionRecording)
		return
	if (!VisionOn)
		{
		MsgBox, 48, Record potion buying, % "The vision helper isn't running, so the bot can't follow loading screens. Restart the bot (Windows+1) and try again."
		return
		}
	atMark := PotionByMark()
	if (atMark)
		MsgBox, 65, Record potion buying, % "First leave a Mark (Page Down) right next to the potion seller (Hilda Brewer, Wizard City's Commons) - the bot recalls you there every time you're out of potions. Each wizard has its own Mark: do this once for each.`n`nThe bot now recalls you to your Mark (Page Up). Once its ""Recording"" message shows, press X to talk, click Fill All with GOLD (and close the window), and press F9. (Not right by her? Walk there and press Page Down - the recording starts over from there.)`n`nYou stay at the seller afterwards."
	else
		MsgBox, 65, Record potion buying, % "The bot will mark your spot (Page Down) and take you to " PotionStartName() ".`n`nThen walk to the potion seller (Hilda Brewer) with the KEYBOARD only, press X to talk, click Fill All with GOLD (and close the window), and press F9.`n`nUse the mount you'll farm with. The bot recalls you back afterwards."
	IfMsgBox, Cancel
		return
	WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
	Sleep, 500
	PotionRecording := 1
	ReleaseKeys()
	if (atMark)
		{
		;(never Page Down here: your Mark stays at the seller)
		g := PotionGlobes()
		if (!PotionTeleport("{PgUp}", "your Mark", Func("PotionArrived").Bind({prompt: ""}, g.mana)))
			{
			;(a Recall in the Mark's own zone may not show a loading screen)
			MsgBox, 36, Record potion buying, % "Page Up (Recall) showed no loading screen - in the Mark's own zone it may not.`n`nAre you standing at your Mark, right next to the potion seller?`n`nYes: record here. No: stop (leave a Mark there first, with some mana for the Recall)."
			IfMsgBox, No
				{
				PotionRecording := 0
				return
				}
			WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
			Sleep, 500
			}
		}
	else
		{
		startZone := WalkZone(true)
		Send, {Blind}{PgDn}
		PotionMarkZone := startZone, PotionMarkAt := A_TickCount
		Sleep, 1500
		if (!PotionTeleport(PotionStartKey(), PotionStartName()))
			{
			PotionRecording := 0
			MsgBox, 48, Record potion buying, % "The teleport to " PotionStartName() " didn't happen (no loading screen) - nothing recorded."
			return
			}
		}
	;(PotionRec: the events only - the start line is made when saving, with the prompt read meanwhile)
	commons := WalkZone(true), prompt := ""
	PotionRec := "", PotionRecStop := 0, PotionRecDown := {}
	PotionRecAtMark := atMark, PotionRecRestart := 0
	PotionHook := InputHook("V L0")
	PotionHook.KeyOpt("{All}", "N")
	PotionHook.OnKeyDown := Func("PotionRecKey").Bind(1)
	PotionHook.OnKeyUp := Func("PotionRecKey").Bind(0)
	Hotkey, ~*LButton, PotionRecClick, On
	Hotkey, F9, PotionRecF9, On
	PotionRecT0 := A_TickCount
	PotionHook.Start()
	TrayTip, Wizard101 bot, % "Recording " (atMark ? "at your Mark in " commons ": X to talk" : "from " commons ": walk to the potion seller") ", buy Fill All, then press F9.", 10, 1
	DebugLog("Potions: recording " (atMark ? "the buying at your Mark in " : "a route from ") commons)
	;(the seller's prompt, read while the recording already runs - an X meanwhile is kept)
	if (atMark)
		prompt := PotionPromptSteady()
	lastZone := commons, t0 := A_TickCount
	;(a loading screen on the way: noted when it's done, as replaying waits for that and goes on from there)
	while (!PotionRecStop && A_TickCount - t0 < 15 * 60000)
		{
		Sleep, 50
		z := WalkZone(true)
		if (z != lastZone && !WkLoading)
			PotionRec .= (A_TickCount - PotionRecT0) "|zone|" z "`r`n", lastZone := z
		;(Page Down at the Mark way: your Mark is here now, so the recording starts here)
		;(PotionRecKey already started the events over, at the Page Down itself)
		if (PotionRecRestart)
			{
			PotionRecRestart := 0, commons := lastZone
			DebugLog("Potions: Page Down - your Mark is here now (" commons "): recording again from here")
			TrayTip, Wizard101 bot, Your Mark is here now - the recording starts again from here. X to talk`, Fill All`, then F9., 10, 1
			prompt := PotionPromptSteady()
			}
		}
	PotionHook.Stop()
	Hotkey, ~*LButton, Off
	Hotkey, F9, Off
	PotionRecording := 0, PotionRecAtMark := 0
	if (atMark)
		{
		;(no prompt read at the start - the shop may have been open: her prompt is back now it's closed)
		if (prompt = "")
			prompt := PotionPromptSteady()
		DebugLog("Potions: the prompt here: " (prompt = "" ? "none read (no check that a run is at the seller)" : prompt))
		;(the buying needs the X that opens her shop and the Fill All click)
		missing := (RegExMatch(PotionRec, "im)^\d+\|key\|x\|down") ? "" : "no X press (to talk to her)") (InStr(PotionRec, "|click|") ? "" : (RegExMatch(PotionRec, "im)^\d+\|key\|x\|down") ? "" : " and ") "no click (Fill All)")
		if (missing != "")
			{
			MsgBox, 308, Record potion buying, % "The recording has " missing ".`n`nThe bot couldn't buy with it. Save it anyway?`n`n(No: nothing saved - record again, and press X once the ""Recording"" message shows.)"
			IfMsgBox, No
				{
				DebugLog("Potions: buying not saved (" missing ")")
				WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
				PotionWalkFresh()
				return
				}
			}
		}
	FileCreateDir, % A_WorkingDir "\routes"
	who := PotionWho()
	file := atMark ? PotionMarkFile(who, true) : PotionRouteFile(commons)
	head := "start|" commons "|" Round(UiScale, 3) "|" GameW "x" GameH (atMark ? "|mark|" prompt : "")
	FileDelete, %file%
	FileAppend, % "; Potion " (atMark ? "buying at your Mark in " : "route from ") commons ", recorded " A_YYYY "-" A_MM "-" A_DD " " A_Hour ":" A_Min " (Potions.ahk): ms|key|name|down/up, ms|click|x|y (UI px from the window's middle), ms|zone|<zone after a loading screen>`r`n" head "`r`n" PotionRec, %file%
	DebugLog("Potions: " (atMark ? "buying" : "route") " saved: " file)
	if (atMark)
		{
		PotionOff().Delete(who), PotionOff().Delete("anyone")
		MsgBox, 64, Record potion buying, % "Saved the buying at this wizard's Mark in " commons (prompt = "" ? "" : " (by " prompt ")") ".`n`nOut of potions, the bot recalls here, buys, and walks on from here. Keep the Mark here (don't Page Down anywhere else)." (prompt = "" ? "`n`n(No ""Press X"" prompt was read here, so a run can't check it's at the seller - better to record standing where her prompt shows.)" : "")
		WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
		PotionWalkFresh()
		return
		}
	MsgBox, 64, Record potion buying, % "Saved the route from " commons ".`n`nThe bot now recalls you to where you were (Page Up)."
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
	;(teleport keys aren't part of a route; Page Down at the Mark way moves the Mark here: start over)
	if (RegExMatch(name, "i)^(Numpad)?(PgDn|PgUp|Home|End)$"))
		{
		if (isDown && PotionRecAtMark && RegExMatch(name, "i)PgDn$"))
			PotionRec := "", PotionRecDown := {}, PotionRecT0 := A_TickCount, PotionRecRestart := 1
		return
		}
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
