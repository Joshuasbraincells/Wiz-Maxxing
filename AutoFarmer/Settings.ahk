; Settings.ahk - the Settings window (the dashboard's Settings button, or the tray menu): the mouse and the bot's
; waits, and how it plays its cards. AHK v1.1, functions and labels only; #Included by Autofarmer.ahk.
;
; Every setting is a line in PlayerStats.txt (key:value) - the window only shows them. Save writes the ones you
; changed there, each in its own line with its comment kept (one the file doesn't have yet goes at its end),
; and the bot uses them from its next click or round on: no restart. Point at a setting to see what it does.
;
; Also here: the mouse put back where it was when the bot took it (MouseGrab / MouseLetGo, mousereturn).

;The window; its help line and its note by the buttons; each setting's control (key -> hwnd), the value it
;showed (key -> value) and the help for each label and control (hwnd -> text); the help on show
global CfgHwnd, CfgHelpText, CfgNote, CfgCtls, CfgShownVals, CfgHelps, CfgHelpShown
;Where the mouse was when the bot took it (MouseGrab), whether that's kept, and when it was taken
global MouseHomeX, MouseHomeY, MouseHomeSet, MouseHomeAt
;Cards of kinds switched off discarded this round (RoundStart clears it; at most discardmax)
global DiscardOffCount

;Every setting in the window, in order: {key, label, kind: "check" (on/off), "num" (lo to hi) or "pick" (picks:
;1, 2, ...), def: its default, help}. {key: "-"} is a heading, {key: "|"} starts the second column. LoadStats
;(KillCalc.ahk) takes the defaults from here too, for a PlayerStats.txt without the line
CfgList()
	{
	static list := ""
	if (IsObject(list))
		return list
	list := []
	list.Push({key: "-", label: "THE MOUSE AND WAITS"})
	list.Push({key: "handsoffon", label: "Wait for me while I play", kind: "check", def: 1
		, help: "While you use the keyboard or mouse yourself the bot waits: no battle rounds, no walking, no potions. (The dashboard's Wait for me button switches it too.)"})
	list.Push({key: "handsoff", label: "Wait for me: seconds after you stop", kind: "num", lo: 0, hi: 3600, def: 10
		, help: "How long after your last key press, click or mouse move the bot carries on. 0 = it never waits for you."})
	list.Push({key: "mousereturn", label: "Put the mouse back afterwards", kind: "check", def: 1
		, help: "When the bot takes the mouse - a battle round, a click out of battle - it goes back to where it was once the bot's done (not if you've used the mouse or keys meanwhile). Off: it's left in the middle of the game."})
	list.Push({key: "mousespeed", label: "Mouse speed (0 = jump there)", kind: "num", lo: 0, hi: 100, def: 1
		, help: "How the mouse moves to what it clicks: 0 jumps straight there, 1 is the fastest glide, higher numbers glide slower (100 is the slowest)."})
	list.Push({key: "clickwait", label: "Wait before each click (ms)", kind: "num", lo: 0, hi: 5000, def: 40
		, help: "Between the mouse getting there and the click. Raise it if the game misses clicks."})
	list.Push({key: "clickrandom", label: "...plus a random wait up to (ms)", kind: "num", lo: 0, hi: 5000, def: 0
		, help: "A random 0 to this many ms more before each click, so the clicks aren't evenly timed. 0 = none."})
	list.Push({key: "clickafter", label: "Wait after clicks (% of the usual)", kind: "num", lo: 0, hi: 1000, def: 50
		, help: "The wait after a card and after its target (300 ms at 100). Lower is faster - raise it if a target click gets missed after a card."})
	list.Push({key: "roundwait", label: "Wait before playing a round (ms)", kind: "num", lo: 0, hi: 30000, def: 0
		, help: "From a round showing up (its Pass button) to the bot's first look at the hand. 0 = at once."})
	list.Push({key: "discardafter", label: "Wait after each discard (ms)", kind: "num", lo: 250, hi: 5000, def: 400
		, help: "After each right-click that discards a card from the hand, while the rest slide together (250 at the least)."})
	list.Push({key: "discardlook", label: "Wait before looking at the hand again (ms)", kind: "num", lo: 0, hi: 5000, def: 700
		, help: "After discarding, while the hand slides together, before the cards are looked at again."})
	list.Push({key: "-", label: "HEALTH"})
	list.Push({key: "healat", label: "Heal under this % of health (0 = never)", kind: "num", lo: 0, hi: 100, def: 40
		, help: "In battle: a healing card (the heal1 / heal2 pictures) on yourself when your health is under this %. 0 = never."})
	list.Push({key: "potionat", label: "Drink a potion under this % (0 = never)", kind: "num", lo: 0, hi: 100, def: 40
		, help: "Out of battle: a potion (Ctrl+O) when your health is under this % - out of potions, the bot buys more with gold. 0 = never."})
	list.Push({key: "potionwalk", label: "Walk to the potion seller by the map", kind: "check", def: 1
		, help: "Out of potions: to Hilda Brewer in Wizard City's Commons by the zone's map - a Recall to your Mark (anywhere in the Commons) or End in Wizard City - X, Fill All, drink. No recording needed. Off: the recorded ways (tray menu Record potion buying)."})
	list.Push({key: "fleeon", label: "Flee when out of mana or cards", kind: "check", def: 1
		, help: "Out of mana (less than the cheapest hit costs, no wand) or out of cards, two rounds running: flee, drink a potion (or buy some), and try again."})
	list.Push({key: "-", label: "WALKING"})
	list.Push({key: "mobavoid", label: "Keep away from mobs (not the quest's)", kind: "check", def: 1
		, help: "Walking (quests, the potion seller): the route goes round the zone's mobs - read from the game's memory, read-only - so no battle starts on the way. Not the mobs the quest is about (named in its goal, or standing at it), and not while collecting. With no way round, it waits for the mob to move off (25 s at most). The dashboard's Map shows them: red dots."})
	list.Push({key: "mobradius", label: "...this far from them (game units)", kind: "num", lo: 100, hi: 1500, def: 300
		, help: "How far the route keeps from a mob all round - they come for you when you get near. More: safer, but narrow streets may leave no way round (then it waits)."})
	list.Push({key: "mobcone", label: "...and out of their sight cone (degrees wide)", kind: "num", lo: 0, hi: 180, def: 60
		, help: "A mob notices you in a cone in front of it, further than all round: the route keeps out of a cone this wide (degrees) in front of each mob, which way it faces read from the game. 0 = no cone. Players say 50 to 120."})
	list.Push({key: "mobsight", label: "...that cone's length (game units)", kind: "num", lo: 100, hi: 3000, def: 600
		, help: "How far in front of a mob its sight cone reaches. More: safer, but more streets look blocked (then it waits for the mob to turn or move)."})
	list.Push({key: "|"})
	list.Push({key: "-", label: "HOW IT PLAYS ITS CARDS"})
	list.Push({key: "cardlogic", label: "Card logic", kind: "pick", def: 1, picks: ["Boost first, then hit", "Hit first (fast)", "Boss: boost first - mobs: hit first"]
		, help: "Boost first: traps on the boss, blades, the bubble and aura, then the biggest hit it can cast. Hit first: the biggest hit it can cast as soon as it has one, boosting only in rounds it has none (quick on weak mobs). Boss/mobs: boost first once you've picked a boss (Alt+1), else hit first."})
	list.Push({key: "boostmax", label: "Boosts before each hit (0 = all it has)", kind: "num", lo: 0, hi: 20, def: 0
		, help: "Boosting first: at most this many boost cards (blades, traps, bubble, aura) go before a hit it can cast. 0 = every one it has."})
	list.Push({key: "healthocr", label: "Kill check: hit at once if that kills", kind: "check", def: 1
		, help: "Reads every enemy's health off the nameplates, and if a hit in hand already kills them all it's cast at once instead of more boosts. (Options > 2D Combat Display must be on.)"})
	list.Push({key: "killmargin", label: "Kill check margin (%)", kind: "num", lo: 0, hi: 200, def: 15
		, help: "A hit only counts as a kill when its least damage is this % more than the health left (covers shields and misreads)."})
	list.Push({key: "useblades", label: "Use blades (and Sharpen)", kind: "check", def: 1
		, help: "Off: blades and Sharpen aren't played (with Discard cards it never plays on, they're discarded)."})
	list.Push({key: "usetraps", label: "Use traps and Feint on the boss (and Potent)", kind: "check", def: 1
		, help: "Off: traps, Feint and Potent aren't played (with Discard cards it never plays on, they're discarded). Traps only ever go on a boss you picked (Alt+1)."})
	list.Push({key: "usebubble", label: "Use the bubble (global)", kind: "check", def: 1
		, help: "Off: your school's bubble isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "useaura", label: "Use the aura", kind: "check", def: 1
		, help: "Off: your school's aura isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "usewand", label: "Use the wand's hit", kind: "check", def: 1
		, help: "Off: the wand's own card (e.g. Minor Clash) isn't played - and isn't counted as a hit without mana when fleeing."})
	list.Push({key: "usetower", label: "Use Tower Shield", kind: "check", def: 1
		, help: "Off: Tower Shield isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "usereshuffle", label: "Use Reshuffle", kind: "check", def: 1
		, help: "Off: Reshuffle isn't played (with Discard cards it never plays on, it's discarded)."})
	list.Push({key: "reboost", label: "Boost again after each hit", kind: "check", def: 0
		, help: "After each hit its blades and traps may be cast again for the next one. Off: each is cast once a battle."})
	list.Push({key: "solotraps", label: "I fight bosses alone (count traps)", kind: "check", def: 0
		, help: "The kill check counts your traps and Feint on the boss. Leave it off when others fight with you: their hits use your traps up without the bot seeing it."})
	list.Push({key: "pipsave", label: "Save pips for a finishing hit (rounds)", kind: "num", lo: 0, hi: 20, def: 3
		, help: "Up to this many rounds, pips are saved for a hit in hand that ends the battle once it's affordable. 0 = never."})
	list.Push({key: "discardunused", label: "Discard cards it never plays", kind: "check", def: 1
		, help: "Every round, cards in hand the bot doesn't play (and kinds switched off above) are discarded with a right-click so it draws ones it can use. Treasure cards among them go too."})
	list.Push({key: "discardmax", label: "...at most this many a round", kind: "num", lo: 0, hi: 7, def: 3
		, help: "The most cards it never plays that are discarded in one round."})
	list.Push({key: "discardunaffordable", label: "Discard hits it can't cast yet", kind: "check", def: 0
		, help: "A hit you haven't the pips for is discarded instead of kept for a later round."})
	list.Push({key: "-", label: "ALERTS"})
	list.Push({key: "alertson", label: "Discord alerts when the wizard needs you", kind: "check", def: 1
		, help: "Stuck, out of potions or mana, logged out, a quest that needs you...: a message to your Discord channel - once its webhook is set (tray menu: Discord alerts...). The same alert at most once in 10 minutes."})
	return list
	}

;Opens the window - made afresh, with the values in use now - or brings it to the front if it's open
CfgShow()
	{
	static hooked := 0
	if (CfgHwnd && WinExist("ahk_id " CfgHwnd))
		{
		WinActivate, ahk_id %CfgHwnd%
		return
		}
	;(the help line follows the mouse: WM_MOUSEMOVE)
	if (!hooked)
		OnMessage(0x200, Func("CfgHover")), hooked := 1
	CfgCtls := {}, CfgShownVals := {}, CfgHelps := {}, CfgHelpShown := ""
	Gui, Cfg:New, +HwndCfgHwnd -MaximizeBox, % "Wizard101 bot " BotVersion() " - settings"
	Gui, Cfg:Color, 1B1D22, 111317
	Gui, Cfg:Margin, 12, 10
	cfgX := 12, cfgY := 12, cfgBottom := 12
	for each, cfgS in CfgList()
		{
		if (cfgS.key = "|")
			{
			cfgX := 444, cfgY := 12
			continue
			}
		if (cfgS.key = "-")
			{
			;(a gap above a heading that isn't the first)
			if (cfgY > 12)
				cfgY += 8
			Gui, Cfg:Font, s9 w600 c8AB4F8, Segoe UI
			Gui, Cfg:Add, Text, % "x" cfgX " y" cfgY " w410 h18", % cfgS.label
			cfgY += 26, cfgBottom := Max(cfgBottom, cfgY)
			continue
			}
		cfgV := Stats.HasKey(cfgS.key) ? Stats[cfgS.key] : cfgS.def
		;(a wizard's own value - storm.killmargin... - is used when it fights as that school; the window doesn't
		;change it, so the help says where it is)
		cfgHelp := cfgS.help
		for each, cfgSch in ["storm", "fire", "ice", "life", "death", "myth", "balance"]
			if (Stats.HasKey(cfgSch "." cfgS.key))
				cfgHelp .= "  Your " cfgSch " wizard has its own: " cfgSch "." cfgS.key ":" Stats[cfgSch "." cfgS.key] " in PlayerStats.txt (change it there)."
		;(a label the mouse can be over - SS_NOTIFY - and its control right of it)
		cfgW := (cfgS.kind = "pick") ? 90 : 300
		Gui, Cfg:Font, s9 w400 cDADADA, Segoe UI
		Gui, Cfg:Add, Text, % "x" cfgX " y" cfgY + 3 " w" cfgW " h18 +0x100 HwndcfgL", % cfgS.label
		cfgCx := cfgX + cfgW + 8
		if (cfgS.kind = "check")
			{
			cfgV := cfgV ? 1 : 0
			Gui, Cfg:Add, Checkbox, % "x" cfgCx " y" cfgY + 3 " w18 h18 HwndcfgC Checked" cfgV
			}
		else if (cfgS.kind = "pick")
			{
			cfgV := Max(1, Min(cfgS.picks.Length(), Round(cfgV)))
			cfgList := ""
			for each, cfgP in cfgS.picks
				cfgList .= (cfgList = "" ? "" : "|") cfgP
			Gui, Cfg:Add, DropDownList, % "x" cfgCx " y" cfgY " w312 AltSubmit HwndcfgC Choose" cfgV, %cfgList%
			}
		else
			{
			cfgV := Round(cfgV)
			Gui, Cfg:Add, Edit, % "x" cfgCx " y" cfgY " w70 h22 Number Right HwndcfgC", %cfgV%
			;(0x80: no thousands commas)
			Gui, Cfg:Add, UpDown, % "Range" cfgS.lo "-" cfgS.hi " 0x80 HwndcfgU", %cfgV%
			CfgHelps[cfgU + 0] := cfgHelp
			}
		CfgCtls[cfgS.key] := cfgC, CfgShownVals[cfgS.key] := cfgV
		CfgHelps[cfgL + 0] := cfgHelp, CfgHelps[cfgC + 0] := cfgHelp
		cfgY += 28, cfgBottom := Max(cfgBottom, cfgY)
		}
	cfgY := cfgBottom + 6
	Gui, Cfg:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, Cfg:Add, Text, x12 y%cfgY% w832 h36 vCfgHelpText, Point at a setting to see what it does. Each is a line in PlayerStats.txt: Save writes them there and the bot uses them at once - no restart.
	cfgY += 44
	Gui, Cfg:Font, s9 w400 c000000, Segoe UI
	Gui, Cfg:Add, Button, x12 y%cfgY% w90 h26 Default gCfgSave, Save
	Gui, Cfg:Add, Button, x+8 yp w90 h26 gCfgDefaults, Defaults
	Gui, Cfg:Add, Button, x+8 yp w150 h26 gCfgOpenFile, Open PlayerStats.txt
	Gui, Cfg:Add, Button, x+8 yp w90 h26 gCfgGuiClose, Close
	Gui, Cfg:Font, s9 w400 cB9E2B9, Segoe UI
	Gui, Cfg:Add, Text, x+14 yp+5 w370 h18 vCfgNote
	;(next to the dashboard when it's up, else in the middle of the screen)
	cfgPos := ""
	if (DashHwnd && DashShown)
		{
		;(not a minimised dashboard's place: -32000)
		WinGet, cfgMm, MinMax, ahk_id %DashHwnd%
		WinGetPos, cfgDx, cfgDy, , , ahk_id %DashHwnd%
		if (cfgDx != "" && cfgMm != -1)
			cfgPos := "x" cfgDx + 30 " y" cfgDy + 60 " "
		}
	Gui, Cfg:Show, % cfgPos "AutoSize", % "Wizard101 bot " BotVersion() " - settings"
	}

;The help for what the mouse is over: a label (SS_NOTIFY) or a control in the window
CfgHover(wParam, lParam, msg, hwnd)
	{
	if (A_Gui != "Cfg" || !IsObject(CfgHelps))
		return
	cfgT := CfgHelps.HasKey(hwnd + 0) ? CfgHelps[hwnd + 0] : ""
	if (cfgT = "" || cfgT == CfgHelpShown)
		return
	CfgHelpShown := cfgT
	GuiControl, Cfg:, CfgHelpText, %cfgT%
	}

;Writes the settings changed in the window to PlayerStats.txt and reads them all again (used from now on).
;A number outside its range is brought into it; one that isn't a number is left as it was
CfgSaveNow()
	{
	cfgPairs := [], cfgSaid := "", cfgFixed := ""
	for each, cfgS in CfgList()
		{
		if (!CfgCtls.HasKey(cfgS.key))
			continue
		cfgC := CfgCtls[cfgS.key]
		GuiControlGet, cfgV, Cfg:, %cfgC%
		if (cfgS.kind = "num")
			{
			cfgV := Trim(cfgV)
			if cfgV is not integer
				{
				cfgFixed .= ", " cfgS.key " (not a number - left as it was)"
				GuiControl, Cfg:, %cfgC%, % CfgShownVals[cfgS.key]
				continue
				}
			if (cfgV < cfgS.lo || cfgV > cfgS.hi)
				{
				cfgV := Max(cfgS.lo, Min(cfgS.hi, cfgV))
				cfgFixed .= ", " cfgS.key " (" cfgS.lo " to " cfgS.hi ": " cfgV ")"
				GuiControl, Cfg:, %cfgC%, %cfgV%
				}
			}
		cfgV += 0
		if (cfgV != CfgShownVals[cfgS.key])
			cfgPairs.Push([cfgS.key, cfgV]), cfgSaid .= ", " cfgS.key " " CfgShownVals[cfgS.key] " -> " cfgV
		}
	if (!cfgPairs.Length())
		{
		GuiControl, Cfg:, CfgNote, % "Nothing changed" (cfgFixed = "" ? "" : " - " SubStr(cfgFixed, 3))
		return
		}
	if (!CfgWrite(cfgPairs))
		{
		GuiControl, Cfg:, CfgNote, Couldn't write PlayerStats.txt - nothing was saved
		DebugLog("Settings: couldn't write PlayerStats.txt - nothing was saved")
		return
		}
	for each, cfgKv in cfgPairs
		CfgShownVals[cfgKv[1]] := cfgKv[2]
	;(the tray menu's tick and the dashboard's Wait for me button)
	HandsOffShow()
	DebugLog("Settings saved (used from now on): " SubStr(cfgSaid, 3) (cfgFixed = "" ? "" : " | " SubStr(cfgFixed, 3)))
	GuiControl, Cfg:, CfgNote, % "Saved " cfgPairs.Length() " change" (cfgPairs.Length() = 1 ? "" : "s") " - used from now on" (cfgFixed = "" ? "" : " (" SubStr(cfgFixed, 3) ")")
	}

;Every setting's default in the window (saved only with Save)
CfgFillDefaults()
	{
	for each, cfgS in CfgList()
		{
		if (!CfgCtls.HasKey(cfgS.key))
			continue
		cfgC := CfgCtls[cfgS.key]
		if (cfgS.kind = "pick")
			GuiControl, Cfg:Choose, %cfgC%, % cfgS.def
		else
			GuiControl, Cfg:, %cfgC%, % cfgS.def
		}
	GuiControl, Cfg:, CfgNote, Defaults filled in - Save to use them
	}

;Sets key:value lines in PlayerStats.txt - in their own lines (every one, if a key is in more than one), their
;comments kept; one the file doesn't have yet at its end, under a heading - and reads the settings again.
;False if the file couldn't be written
CfgWrite(pairs)
	{
	cfgWas := A_IsCritical
	Critical
	cfgPath := A_WorkingDir "\PlayerStats.txt"
	cfgText := ""
	if (FileExist(cfgPath))
		{
		FileRead, cfgText, %cfgPath%
		if (ErrorLevel)
			return CfgUncritical(cfgWas, false)
		}
	cfgLines := StrSplit(StrReplace(cfgText, "`r"), "`n")
	if (cfgLines.Length() && cfgLines[cfgLines.Length()] = "")
		cfgLines.Pop()
	cfgHead := "; ---- Set in the Settings window (the dashboard's Settings button) ----"
	for each, cfgKv in pairs
		{
		cfgFound := false
		for cfgI, cfgLn in cfgLines
			if (RegExMatch(cfgLn, "i)^(\s*\Q" cfgKv[1] "\E\s*:\s*)[^;\s]*(.*)$", cfgM))
				cfgLines[cfgI] := cfgM1 cfgKv[2] cfgM2, cfgFound := true
		if (cfgFound)
			continue
		cfgHas := false
		for cfgI, cfgLn in cfgLines
			if (cfgLn == cfgHead)
				cfgHas := true
		if (!cfgHas)
			cfgLines.Push(""), cfgLines.Push(cfgHead)
		cfgLines.Push(cfgKv[1] ":" cfgKv[2])
		}
	cfgOut := ""
	for cfgI, cfgLn in cfgLines
		cfgOut .= cfgLn "`r`n"
	FileDelete, %cfgPath%.tmp
	FileAppend, %cfgOut%, %cfgPath%.tmp
	if (ErrorLevel)
		return CfgUncritical(cfgWas, false)
	FileMove, %cfgPath%.tmp, %cfgPath%, 1
	if (ErrorLevel)
		return CfgUncritical(cfgWas, false)
	LoadStats(true)
	return CfgUncritical(cfgWas, true)
	}

;Critical off again unless it was on before (wasOn); returns result
CfgUncritical(wasOn, result)
	{
	if (!wasOn)
		Critical, Off
	return result
	}

;---- The mouse back where it was ----

;Remembers where the mouse is as the bot takes it (a battle round, a click out of battle) - unless that's
;remembered already: it goes back once, when the bot's done (MouseLetGo). True if it was taken now. Not with
;mousereturn:0 (the Settings window's "Put the mouse back afterwards")
MouseGrab()
	{
	;(one taken over 10 minutes ago and never given back is stale: taken afresh)
	if ((MouseHomeSet && A_TickCount - MouseHomeAt < 600000) || !Stat("mousereturn"))
		return false
	MouseGetPos, MouseHomeX, MouseHomeY
	MouseHomeSet := 1, MouseHomeAt := A_TickCount
	return true
	}

;Puts the mouse back where MouseGrab found it - not if you've used the keyboard or mouse since (you're there:
;it's yours) - and forgets it. 1 if it's back there, -1 if it was left to you, 0 if nothing was taken (or
;mousereturn:0)
MouseLetGo()
	{
	if (!MouseHomeSet)
		return 0
	MouseHomeSet := 0
	if (!Stat("mousereturn"))
		return 0
	if (A_TimeIdlePhysical < A_TickCount - MouseHomeAt)
		return -1
	MouseGetPos, mouseNowX, mouseNowY
	if (mouseNowX != MouseHomeX || mouseNowY != MouseHomeY)
		MouseMove, MouseHomeX, MouseHomeY, 0
	return 1
	}

;---- How it plays its cards ----

;Hit first this round, before any boost? (cardlogic: 2 = hit first, 3 = hit first unless a boss is picked)
CardHitFirst()
	{
	cardWay := Stat("cardlogic")
	return (cardWay = 2 || (cardWay = 3 && BossChoosen != 1))
	}

;May a boost card go this round? Not once boostmax of them have gone since the last hit while a hit can be
;cast (boostmax 0: no limit; nothing to hit with: boosting is all it can do)
CardBoostOk()
	{
	cardMax := Stat("boostmax")
	if (cardMax <= 0 || BoostRun < cardMax || !CardHitReady())
		return true
	DebugLog("  " BoostRun " boost" (BoostRun = 1 ? "" : "s") " since the last hit (boostmax " cardMax "): hitting now")
	return false
	}

;A hit in hand (hit4 only on a picked boss) you can pay for and aren't saving pips against (not the wand's)
CardHitReady()
	{
	return (hit4 == 1 && BossChoosen = 1 && CardHitCanGo("hit4")) || (hit3 == 1 && CardHitCanGo("hit3"))
		|| (hit2 == 1 && CardHitCanGo("hit2")) || (hit1 == 1 && CardHitCanGo("hit1"))
	}

;(pips unknown - your nameplate not found - isn't "can pay": boosting isn't held back for a hit that may not go)
CardHitCanGo(name)
	{
	return PipsNow >= 0 && Affordable(name) && (PipSaveFor = "" || PipSaveFor = name)
	}

;The biggest hit in hand it can cast (hit4 only on a picked boss) - not the wand's. True if one was cast
CastBestHit()
	{
	global
	if ((hit4 == 1) && (BossChoosen = 1) && UseHit("hit4", hit4, hitschool))
		|| ((hit3 == 1) && UseHit("hit3", hit3, hitschool))
		|| ((hit2 == 1) && UseHit("hit2", hit2, hitschool))
		|| ((hit1 == 1) && UseHit("hit1", hit1, hitschool))
		{
		BoostRun := 0
		return true
		}
	return false
	}

;Cards of a kind switched off in the Settings window (useblades, usetraps...) are never played: with
;discardunused on they're discarded like the others it never plays - at most discardmax a round, and not while
;you play. Returns how many were
DiscardSwitchedOff()
	{
	global
	local did := 0
	if (Stat("discardunused") != 1 || DiscardOffCount >= Stat("discardmax") || PlayerActing())
		return 0
	if (!Stat("useblades"))
		{
		if (blade == 1)
			did += DiscardOffOne("blade", hitschool)
		if (blade2 == 1 && bladetype != "")
			did += DiscardOffOne(bladetype, "resources")
		if (blade3 == 1)
			did += DiscardOffOne("blade3", "resources")
		if (blade4 == 1)
			did += DiscardOffOne("blade4", "resources")
		if (sharpen == 1)
			did += DiscardOffOne("sharpen", "resources")
		}
	if (!Stat("usetraps"))
		{
		if (trap == 1)
			did += DiscardOffOne("trap", hitschool)
		if (trap2 == 1 && traptype != "")
			did += DiscardOffOne(traptype, "resources")
		if (trap3 == 1)
			did += DiscardOffOne("trap3", "resources")
		if (feint == 1)
			did += DiscardOffOne("feint", "resources")
		if (potent == 1)
			did += DiscardOffOne("potent", "resources")
		}
	if (!Stat("usebubble") && bubble == 1)
		did += DiscardOffOne("bubble", hitschool)
	if (!Stat("useaura") && aura == 1)
		did += DiscardOffOne("aura", hitschool)
	if (!Stat("usetower") && tower == 1)
		did += DiscardOffOne("tower", "resources")
	if (!Stat("usereshuffle") && reshuffle == 1)
		did += DiscardOffOne("reshuffle", "resources")
	if (did)
		DebugLog("  (discarded " did " card" (did = 1 ? "" : "s") " of kinds switched off in the Settings window)")
	return did
	}

;One card of a kind switched off discarded, while the round's discardmax allows (DiscardOffCount)
DiscardOffOne(title, dir)
	{
	if (DiscardOffCount >= Stat("discardmax"))
		return 0
	n := DiscardCard(title, dir)
	DiscardOffCount += n
	return n
	}

CfgSave:
	;(not halfway through while the bot writes PlayerStats.txt itself: StatsSet is Critical too)
	Critical
	CfgSaveNow()
	return

CfgDefaults:
	CfgFillDefaults()
	return

CfgOpenFile:
	Run, notepad.exe "%A_WorkingDir%\PlayerStats.txt"
	return

CfgGuiClose:
CfgGuiEscape:
	Gui, Cfg:Destroy
	CfgHwnd := 0
	return
