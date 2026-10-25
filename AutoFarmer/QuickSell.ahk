; QuickSell.ahk - the backpack quick sold for gold when it's full (asked 2026-10-25: "when your backpack is full a circular
; alert icon with prospector zeke shows up on the right hand side of the screen ... we should have the bot look for that
; after a battle and if its there i'd like to to quick sell our entire inventory" - "of course this should be a setting
; to be turned on and off because dungeons would cause good gear to be sold"). AutoHotkey v1.1, functions only; #Included
; by Autofarmer.ahk. Needs the vision helper and the game's memory (vision\bagmem.py - /bag and /gui, READ-ONLY): without
; them it does nothing (no picture is ever trusted for this - Zeke's portrait also means "the gold bag is nearly full").
;
; Settings > THE BACKPACK: quicksell (off by default), quicksellpets (pets too - on), quicksellafterdungeon (off). Hidden
; (PlayerStats.txt): quicksellfree:N - sell with N slots or fewer left (0); quicksell:2 - a REHEARSAL: everything up to the
; confirmation window, read, logged and closed - nothing sold. Tray menu: "Quick sell the backpack now" and "Quick sell
; rehearsal (stops at the confirmation)".
;
; When: after a battle the bot played (the main loop's spellbook block - QsBattleEnd, QsTick), three looks at the game's
; memory (0, 3 and 8 s after it): the backpack's count against its size (calibrated by the game's own "N/M"), and Zeke's
; icon in the HUD's right-hand column. Full - or Zeke's icon with the gold bag not near full - is a look: B, the game's
; own N/M read; full by it: the sale. Never in a dungeon run, a dungeon being recorded or a zone entered through a sigil;
; after a dungeon the next full backpack is held (you're told) until you've sorted it, unless quicksellafterdungeon.
;
; The sale - every click target from the game's memory (name and ancestors, shown, its rect, its size against the .gui
; file's, its label), on an allow-list, turned into pixels: B (the backpack page), Quick Sell, each gear group (Hat,
; Robe, Shoes, Weapon, Athame, Amulet, Ring, Deck) and the Pet group (quicksellpets) with ALL - never the All group (it
; takes housing and jewels too) - and No to "Would you like to include Crowns Items in the selected items?" (the one
; Crown box it may ever click, only No, only when its game key in the log, its caption, its button's label and an OCR
; of "No" agree), SELL, the confirmation's numbers read (Crown rows, furniture, jewels, reagents, treasure cards 0; no
; pets unless quicksellpets; its total its rows'), SELL, Yes to the pets box only when its count is the confirmation's,
; then the backpack's count falling checked. A group an Equipment Set's item in the backpack is in is left out (the boss
; deck's deck), and every such item is checked to be there after - one gone turns quick sell off. Before each click:
; no key or mouse of yours since the run began, the bot on, Wizard101 in front, no battle, no "Crown" read round it.
; Anything else - a box it doesn't know, a timeout (60 s for the whole run) - backs out window by window (each close
; checked); a Crown box stops it with nothing clicked. You touching the mouse or keys stops it at once - no more input.
; debug.log: "Backpack: ..."; the dashboard counts the sales (Quick sells).

;Declared only (a top-level := never runs in an #Included file - numbers made with X := X ? X : 0)
;A run under way (Party.ahk's ready waits), when the bot's last battle ended and the looks after it, when a sale may be
;tried again, failures in a row, given up (3 in a row: till a restart or the setting toggled), when the last look that
;found it not full was, the last look found it full and not sold (QsStillFull - the mob loop), the setting as last seen,
;the character (its global id, hex - quicksell.ini's section)
global QsBusy, QsBattleEndAt, QsLooks, QsTryAt, QsFails, QsBlocked, QsLookAt, QsStill, QsSetWas, QsGid
;What's been said when ({key: tick}), the no-memory alert sent, windows a battle left open (closed at the next look) and
;the tries and when, the run's start (no input of yours after it), a run from the tray, the steps clicked
global QsSaidAt, QsMemSaid, QsLeftover, QsLeftoverTries, QsLeftoverAt, QsSince, QsManual, QsStep
;The game's log read by the run itself (where to, its first line, what it said since the run began: [{kind, key, msg}]);
;the backpack before the run ({items, gold, pouch, sets: {gid: set item}}), the last /bag read
global QsLogPos, QsLogHead, QsLogEvents, QsBefore, QsLastBag

;---- The settings ----

;quicksell: 0 off, 1 on, 2 the rehearsal (up to the confirmation, nothing sold)
QsMode()
	{
	qm := Stats.HasKey("quicksell") ? Round(Stats["quicksell"]) : 0
	return (qm = 1 || qm = 2) ? qm : 0
	}

;quicksellpets: pets sold too (on unless 0)
QsPets()
	{
	return !(Stats.HasKey("quicksellpets") && !Stats["quicksellpets"])
	}

;quicksellafterdungeon: a backpack holding a dungeon's drops sold like any other (off)
QsAfterDungeon()
	{
	return (Stats.HasKey("quicksellafterdungeon") && Stats["quicksellafterdungeon"]) ? 1 : 0
	}

;quicksellfree: sold with this many slots or fewer left (0: only when the game's own N/M reads full)
QsFree()
	{
	qf := Stats.HasKey("quicksellfree") ? Round(Stats["quicksellfree"]) : 0
	return qf > 0 ? Min(qf, 30) : 0
	}

QsLog(msg)
	{
	DebugLog("Backpack: " msg)
	}

;Said once in every ms (10 minutes) for its key; true when said now
QsSay(key, msg, every := 600000)
	{
	if (!IsObject(QsSaidAt))
		QsSaidAt := {}
	if (QsSaidAt.HasKey(key) && A_TickCount - QsSaidAt[key] < every)
		return false
	QsSaidAt[key] := A_TickCount
	QsLog(msg)
	return true
	}

;---- What's kept per character (quicksell.ini: [<the character's global id>] uncounted, cap, dungeon, markitems) ----

QsIniPath()
	{
	return A_ScriptDir "\quicksell.ini"
	}

QsIni(key, def := "")
	{
	qSec := QsGid != "" ? QsGid : "pending"
	IniRead, qv, % QsIniPath(), %qSec%, %key%, %A_Space%
	return (qv = "" || qv = "ERROR") ? def : qv
	}

QsIniSet(key, value)
	{
	qSec := QsGid != "" ? QsGid : "pending"
	if (value = "")
		IniDelete, % QsIniPath(), %qSec%, %key%
	else
		IniWrite, %value%, % QsIniPath(), %qSec%, %key%
	}

;What the count goes by: the backpack list's items the game's own N/M leaves out (emotes...), its size by that N/M, the
;slots left at which it's sold
QsState()
	{
	return {uncounted: QsIni("uncounted", 0) + 0, cap: QsIni("cap", 0) + 0, free: QsFree()}
	}

;A dungeon run started or stopped, a dungeon recorded, a zone entered through a sigil (Dungeons.ahk, Walker.ahk): this
;character's next full backpack is held - a dungeon's drops are the good gear (quicksellafterdungeon off) - until it's been
;sorted (10 items fewer than its most since), quicksellafterdungeon is ticked, or a quick sell is asked for from the tray
QsDungeonMark(zone := "")
	{
	qWas := QsIni("dungeon")
	QsIniSet("dungeon", A_Now)
	QsIniSet("markitems", "")
	if (qWas = "")
		QsLog("a dungeon (" (IsObject(DgRun) ? "the run '" DgRun.name "'" : DgRecording ? "being recorded" : "entered through its sigil" (zone != "" ? ": " zone : "")) ")"
			. (QsAfterDungeon() ? " - its drops sold like any others ('...even with a dungeon's drops in it' is ticked)" : " - the next full backpack is held (its drops are the good gear): you're told, nothing's sold"))
	}

QsMarkClear(why)
	{
	if (QsIni("dungeon") = "")
		return
	QsIniSet("dungeon", ""), QsIniSet("markitems", "")
	QsLog("the dungeon's hold dropped: " why)
	}

;The full backpack held for a dungeon's drops
QsHeld()
	{
	return QsIni("dungeon") != "" && !QsAfterDungeon()
	}

;A /bag read: the character, the game's own N/M when the backpack page shows it (whoever opened it), the dungeon mark's
;count
QsNoteBag(bag)
	{
	QsLastBag := bag
	if (bag.gid != "" && bag.gid != QsGid)
		{
		QsGid := bag.gid
		;(a mark made before the character was known: its own now)
		IniRead, qPend, % QsIniPath(), pending, dungeon, %A_Space%
		if (qPend != "")
			{
			QsIniSet("dungeon", qPend), QsIniSet("markitems", "")
			IniDelete, % QsIniPath(), pending
			}
		}
	if (IsObject(bag.space) && bag.space.m > 0)
		QsCalibrate(bag.items, bag.space.n, bag.space.m)
	if (QsIni("dungeon") = "")
		return
	if (QsAfterDungeon())
		{
		QsMarkClear("'...even with a dungeon's drops in it' is ticked")
		return
		}
	qMost := QsIni("markitems")
	if (bag.items = "")
		return
	if (qMost = "" || bag.items > qMost)
		QsIniSet("markitems", bag.items)
	else if (bag.items <= qMost - 10)
		QsMarkClear("the backpack went from " qMost " down to " bag.items " items (sorted)")
	}

;The game's own N/M against the backpack list's count: what the count leaves out (emotes...) and the backpack's size
QsCalibrate(items, n, m)
	{
	if (items = "" || n = "" || m = "" || m <= 0)
		return
	qUnc := items - n
	if (qUnc < 0 || qUnc > 300)
		return
	if (QsIni("uncounted") != qUnc || QsIni("cap") != m)
		{
		QsIniSet("uncounted", qUnc), QsIniSet("cap", m)
		QsLog("the game's own count " n "/" m " - " items " items in the backpack's list, " qUnc " of them not counted (emotes...)")
		}
	}

;---- When it's looked for (Autofarmer.ahk's spellbook block) ----

;A battle the bot played just ended (inbattle was 1)
QsBattleEnd()
	{
	QsBattleEndAt := A_TickCount, QsLooks := 0
	}

;Each pass of the spellbook block (after PotionCheck): a battle's windows left open closed; three looks after the bot's
;battle, 0, 3 and 8 s after it (the loot can come a moment after the spellbook shows). Nothing at all with quicksell off
QsTick()
	{
	static qDue := [0, 3000, 8000]
	qMode := QsMode()
	if (qMode != QsSetWas)
		{
		;(switched on: the gave-up and the waits forgotten)
		if (qMode && QsSetWas != "")
			QsBlocked := 0, QsFails := 0, QsTryAt := 0, QsLookAt := 0
		QsSetWas := qMode
		}
	if (!qMode)
		{
		QsStill := 0, QsLeftover := 0
		return
		}
	if (QsBusy)
		return
	if (QsLeftover)
		{
		QsLeftoverTick()
		return
		}
	QsLooks := QsLooks ? QsLooks : 0
	;(a blank time: "A_TickCount - blank < N" would be true)
	if (!QsBattleEndAt || A_TickCount - QsBattleEndAt >= 12000 || QsLooks >= 3)
		return
	if (A_TickCount < QsBattleEndAt + qDue[QsLooks + 1])
		return
	QsLooks += 1
	QsLook("look " QsLooks " of 3 after the battle")
	}

;Windows a battle (or a run that stopped) left open: closed - at most every 3 s, 3 tries
QsLeftoverTick()
	{
	QsLeftoverAt := QsLeftoverAt ? QsLeftoverAt : 0, QsLeftoverTries := QsLeftoverTries ? QsLeftoverTries : 0
	if (A_TickCount - QsLeftoverAt < 3000)
		return
	QsLeftoverAt := A_TickCount
	if (!QsMayRun(qWhy))
		return
	QsLeftoverTries += 1
	QsBusy := 1, QsSince := A_TickCount, QsManual := 0
	qDone := QsBackOut("a battle cut the quick sell short")
	QsBusy := 0
	if (qDone || QsLeftoverTries >= 3)
		QsLeftover := 0, QsLeftoverTries := 0
	}

;The last after-battle look found the backpack full and it wasn't sold (held, failed, waiting): the mob loop stops
QsStillFull()
	{
	return QsMode() && QsStill
	}

;A look: the backpack from the game's memory, and what to do about it
QsLook(why)
	{
	bag := NavBag()
	if (!IsObject(bag))
		{
		QsSay("nomem", "no look (" why ") - " NavBagWhy " (quick sell goes by the game's memory only)")
		if (!QsMemSaid && RegExMatch(NavBagWhy, "i)isn't running|navmem:0|dual mode"))
			{
			QsMemSaid := 1
			AlertSend("inventory", "quick sell can't look", "Quick sell needs the game's memory (the vision helper) - it's off (" NavBagWhy "). Nothing is sold.")
			}
		return
		}
	QsNoteBag(bag)
	d := QsDecide(bag, QsState())
	if (d.act = "none")
		{
		QsStill := 0
		return
		}
	if (d.act = "gold")
		{
		QsStill := 0
		if (QsSay("gold", d.why " - not looked at"))
			AlertSend("gold", "gold bag nearly full", "Prospector Zeke's alert: the gold bag is " Round(100 * bag.gold / bag.goldMax) "% full (" bag.gold " of " bag.goldMax ") - gold over it is lost.")
		return
		}
	;(full by the count - or Zeke's alert: a look)
	qDg := QsDungeonNow()
	if (qDg != "")
		{
		if (d.full)
			QsStill := 1
		if (QsSay("dungeon", d.why " in " qDg " - not sold (a dungeon's drops are the good gear)"))
			AlertSend("inventory", "backpack full", "The backpack is full in a dungeon - not sold (good gear). Drops go to the bank until it's full.")
		return
		}
	if (QsHeld())
		{
		if (d.full)
			QsStill := 1
		if (QsSay("held", d.why " - held: it holds a dungeon's drops (not quick sold - look through it, sell it yourself, or tick '...even with a dungeon's drops in it')"))
			AlertSend("inventory", "backpack full", "The backpack is full and holds a dungeon's drops - not quick sold. Look through it, then sell it yourself, or tick '...even with a dungeon's drops in it' (Settings: THE BACKPACK).")
		return
		}
	if (QsBlocked)
		{
		QsStill := d.full ? 1 : QsStill
		QsSay("blocked", d.why " - quick sell gave up after 3 failures in a row (switch it off and on, or restart the bot)")
		return
		}
	QsTryAt := QsTryAt ? QsTryAt : 0, QsLookAt := QsLookAt ? QsLookAt : 0
	if (QsTryAt && A_TickCount < QsTryAt)
		{
		QsStill := d.full ? 1 : QsStill
		QsSay("wait", d.why " - not tried again for " Ceil((QsTryAt - A_TickCount) / 60000) " more minutes")
		return
		}
	;(Zeke's alert with the count not full: one look in 10 minutes - it calibrates the count)
	if (!d.full && QsLookAt && A_TickCount - QsLookAt < 600000)
		return
	if (!QsMayRun(qWhy))
		{
		QsSay("skip " qWhy, d.why " - not now: " qWhy)
		return
		}
	QsRun(d, bag, false, QsMode() = 2)
	}

;What to do about a /bag reading (pure): {act: "look" (the backpack page opened and its own N/M read - the count says full,
;or Zeke's alert with the gold bag not near full), "gold" (Zeke's alert with the gold bag 95% full or more: the gold bag's
;alert - no look), "none"; full (by the count), zeke, gold, counted, cap, why}. s: QsState's {uncounted, cap, free}
QsDecide(bag, s)
	{
	qUnc := (s.uncounted > 0) ? s.uncounted : 0
	qCap := (s.cap > 0) ? s.cap : ((bag.allowed > 0) ? bag.allowed : 0)
	qFree := (s.free > 0) ? s.free : 0
	qCounted := (bag.items != "" && bag.items >= 0) ? bag.items - qUnc : ""
	qFull := (qCounted != "" && qCap > 0 && qCounted >= qCap - qFree) ? 1 : 0
	qZeke := QsZekeUp(bag.tips)
	qGold := (bag.goldMax > 0 && bag.gold != "" && bag.gold >= 0.95 * bag.goldMax) ? 1 : 0
	qNow := (qCounted = "" ? "?" : qCounted) "/" (qCap ? qCap : "?")
	qOut := {act: "none", full: qFull, zeke: qZeke, gold: qGold, counted: qCounted, cap: qCap, why: "the backpack is " qNow " by the count"}
	if (qFull)
		qOut.act := "look", qOut.why := "the count says full (" qNow (qUnc ? ", " qUnc " not counted" : "") ")" (qZeke ? " and Zeke's alert is up" : "")
	else if (qZeke && !qGold)
		qOut.act := "look", qOut.why := "Prospector Zeke's alert is up (the count says " qNow ")"
	else if (qZeke)
		qOut.act := "gold", qOut.why := "Zeke's alert is up and the gold bag is " Round(100 * bag.gold / bag.goldMax) "% full (" bag.gold "/" bag.goldMax ") - the gold bag's alert, the backpack is " qNow
	return qOut
	}

;Prospector Zeke's portrait on a shown icon of the HUD's right-hand column (the backpack full - or the gold bag nearly)
QsZekeUp(tips)
	{
	if (!IsObject(tips))
		return 0
	for qi, qt in tips
		if (qt.shown && (InStr(qt.image, "Portrait_Human_Zeke") || InStr(qt.button, "Portrait_Human_Zeke")))
			return 1
	return 0
	}

;In a dungeon: a dungeon run, one being recorded, a zone entered through a sigil - why, else ""
QsDungeonNow()
	{
	if (DgRecording)
		return "a dungeon being recorded"
	if (IsObject(DgRun))
		return "the dungeon run '" DgRun.name "'"
	qZone := WalkZone()
	if (qZone != "" && IsObject(WkSigilZones) && WkSigilZones.HasKey(qZone))
		return "a dungeon (" qZone " - entered through its sigil)"
	return ""
	}

;May a run start now: why not ("" it may). manual: asked for from the tray (the bot may be off, you've just used the mouse)
QsMayRun(ByRef why, manual := false)
	{
	why := ""
	qSecs := Stats.HasKey("handsoff") ? Stats["handsoff"] : 3
	if (!BotOn && !manual)
		why := "the bot is off"
	else if (afk)
		why := "holding (afk)"
	else if (dualmode)
		why := "dual mode"
	else if (LearnAll)
		why := "Learn every card is on"
	else if (PotionRecording)
		why := "potion buying being recorded"
	else if (PotionResting)
		why := "resting for health"
	else if (WkLoading)
		why := "a loading screen"
	else if (IsFunc("BattleLogInBattle") && Func("BattleLogInBattle").Call())
		why := "a battle"
	else if (WkNoteKind != "")
		why := "a ""needs you"" notice is up (" WkNoteKind ")"
	else if (!manual && UserIdle() < Max(3, qSecs) * 1000)
		why := "you're at the keyboard or mouse"
	else if (!GameActive() && !(IsFunc("GameToFront") && Func("GameToFront").Call("quick sell", !manual)))
		why := "Wizard101 isn't the window in front"
	return why = ""
	}

;---- The run ----

;The quick sell (a look, the tray): d - QsDecide's (why); bag - the /bag read before; manual - from the tray (sold
;whether the game says full or not; the bot may be off); rehearse - up to the confirmation, read, logged, closed. The
;result ({res: sold, notfull, rehearsed, nothing, stopped, failed, crowns; why...})
QsRun(d, bag, manual := false, rehearse := false)
	{
	if (QsBusy)
		return ""
	QsBusy := 1, QsSince := A_TickCount, QsManual := manual ? 1 : 0, QsLeftover := 0, QsStep := 0
	UpdateGameRect()
	qOwn := MouseGrab()
	SetStatus("Quick selling the backpack")
	ReleaseKeys()
	QsLogOpen()
	QsBefore := {items: bag.items, gold: bag.gold, pouch: bag.goldMax, sets: {}}
	for qi, qs in bag.setItems
		QsBefore.sets[qs.gid] := qs
	QsLog((rehearse ? "REHEARSAL (nothing is sold) - " : "") (manual ? "asked for from the tray" : d.why) " - opening the backpack")
	qRes := QsSteps(bag, manual, rehearse)
	qRes := QsFinish(qRes)
	QsBusy := 0, QsManual := 0
	SetStatus("")
	if (qOwn)
		MouseLetGo()
	WalkResume()
	QsAfter(qRes, manual)
	return qRes
	}

;The steps; the result as QsRun's - a step that fails returns its failure (QsFinish backs out)
QsSteps(bag, manual, rehearse)
	{
	;(0. the groups: the gear's and the pets' - less any an Equipment Set's item in the backpack is in; none at all when
	;the sets can't be read)
	qCats := QsCategories(bag, qWhyNot)
	if (!IsObject(qCats))
		return QsFail(qWhyNot)
	;(1. the backpack open, on its page)
	qr := QsOpenBook()
	if (IsObject(qr))
		return qr
	;(2. its own N/M)
	g := QsGui("InventorySpellbookPage/inventorySpace")
	qSp := IsObject(g) ? QsParseSpace(g.win["InventorySpellbookPage/inventorySpace"].text) : ""
	if (!IsObject(qSp))
		{
		qb := NavBag()
		qSp := IsObject(qb) ? qb.space : ""
		}
	if (!IsObject(qSp))
		return QsFail("the backpack's count (N/M) couldn't be read")
	QsCalibrate(bag.items, qSp.n, qSp.m)
	if (!manual && qSp.n < qSp.m - QsFree())
		{
		QsLog("the game's own count is " qSp.n "/" qSp.m " - not full: closing it, nothing sold")
		qr := QsCloseBook()
		return IsObject(qr) ? qr : {res: "notfull", why: qSp.n "/" qSp.m}
		}
	QsLog("the game's own count is " qSp.n "/" qSp.m (qSp.n >= qSp.m - QsFree() ? " - full" : "") ": quick selling (" (QsPets() ? "gear and pets" : "gear") ", for gold)")
	;(4. Quick Sell - on its BACKPACK tab)
	qr := QsOpenQuickSell()
	if (IsObject(qr))
		return qr
	;(5. each group with ALL)
	qPicked := 0
	for qi, qc in qCats.list
		{
		qr := QsSelectGroup(qc, qn)
		if (IsObject(qr))
			return qr
		qPicked += qn
		}
	if (!qPicked)
		{
		QsLog("nothing Quick Sell can sell in " (qCats.list.Length() ? "the groups" : "any group left") " - closing")
		return {res: "nothing", why: "nothing Quick Sell can sell in the gear" (QsPets() ? " and pet" : "") " groups", back: 1}
		}
	;(6. SELL: the confirmation)
	qr := QsClickWait("buyWindow/sellAction", "SELL", "QuickSellConfirmationWindow", 3000, "the confirmation window")
	if (IsObject(qr))
		return qr
	;(7. its numbers, from the game's memory)
	qr := QsConfirm(qCats, qNums)
	if (IsObject(qr))
		return qr
	if (rehearse)
		{
		QsSnap("the confirmation")
		QsLog("rehearsal - not sold: closing the confirmation and the windows")
		return {res: "rehearsed", why: "the rehearsal stops at the confirmation", nums: qNums, back: 1}
		}
	;(8. SELL in the confirmation)
	qr := QsConfirmSell(qNums)
	if (IsObject(qr))
		return qr
	;(9. the sale checked in the game's memory)
	return QsVerify(qNums)
	}

;A step's end: a failure backed out of (window by window); windows a battle left open closed at the next look
QsFinish(r)
	{
	if (!IsObject(r))
		return {res: "failed", why: "?"}
	if (r.res = "stopped" && r.kind = "cap")
		r.res := "failed"
	if (r.res = "failed")
		QsLog("quick sell failed: " r.why " - backing out")
	if ((r.res = "failed" || r.back) && !r.backed)
		{
		r.backed := 1
		QsBackOut(r.why)
		}
	if (r.res = "stopped")
		{
		QsLog("quick sell stopped: " r.why (r.kind = "user" ? "" : r.kind = "battle" ? " (its windows closed after the battle)" : ""))
		if (r.kind = "battle" || r.kind = "front")
			QsLeftover := 1, QsLeftoverTries := 0, QsLeftoverAt := 0
		}
	return r
	}

;The result into the waits: a sale at most every 10 minutes, 15 after a failure, 3 failures in a row given up; 60 when it
;freed under 5 slots and is still full, or there's nothing to sell
QsAfter(r, manual)
	{
	QsFails := QsFails ? QsFails : 0
	now := A_TickCount
	if (r.res = "sold")
		{
		QsFails := 0, QsTryAt := now + 600000
		qAfter := r.after, qd := IsObject(qAfter) ? QsDecide(qAfter, QsState()) : ""
		QsStill := IsObject(qd) && qd.full ? 1 : 0
		if (QsStill && QsBefore.items - qAfter.items < 5)
			{
			QsTryAt := now + 3600000
			QsLog("still full after the sale (it freed " QsBefore.items - qAfter.items " slots) - not tried again for 60 minutes")
			AlertSend("inventory", "backpack still full", "Quick sell freed only " QsBefore.items - qAfter.items " slots - the rest can't be quick sold (emotes, mounts, Crowns items, locked or set items). Drops go to the bank; tried again in 60 minutes.")
			}
		if (QsAfterDungeon())
			QsMarkClear("sold with '...even with a dungeon's drops in it' ticked")
		}
	else if (r.res = "notfull")
		QsLookAt := now, QsStill := 0
	else if (r.res = "rehearsed")
		QsTryAt := now + 600000, QsStill := 1
	else if (r.res = "nothing")
		{
		QsTryAt := now + 3600000, QsStill := 1
		AlertSend("inventory", "backpack full", "The backpack is full, but Quick Sell finds nothing it may sell in the gear" (QsPets() ? " and pet" : "") " groups. Drops go to the bank; tried again in 60 minutes.")
		}
	else if (r.res = "stopped")
		QsTryAt := now + 600000, QsStill := 1
	else if (r.res = "crowns")
		QsTryAt := now + 3600000, QsStill := 1
	else
		{
		QsFails += 1, QsTryAt := now + 900000, QsStill := 1
		if (QsFails >= 3 && !manual)
			{
			QsBlocked := 1
			QsLog("quick sell failed 3 times in a row - given up till it's switched off and on, or the bot restarts")
			AlertSend("inventory", "quick sell gave up", "The backpack is full and quick sell failed 3 times in a row (last: " r.why "). Drops go to the bank. Switch quick sell off and on (Settings: THE BACKPACK) to try again.")
			}
		else
			AlertSend("inventory", "backpack full", "Couldn't quick sell the full backpack: " r.why " - drops go to the bank; tried again in 15 minutes.")
		}
	}

;---- The steps ----

;The backpack open on its page: the book open on another page - its backpack tab; closed - B (it toggles: read first)
QsOpenBook()
	{
	g := QsGui("DeckConfiguration,InventorySpellbookPage,DeckConfiguration/Inventory")
	if (!IsObject(g))
		return QsFail("the game's windows can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message is up before the run (""" g.box.caption """)")
	if (g.win["DeckConfiguration"].shown && g.win["InventorySpellbookPage"].shown)
		return ""
	if (g.win["DeckConfiguration"].shown)
		return QsClickWait("DeckConfiguration/Inventory", "", "InventorySpellbookPage", 3000, "the backpack page")
	qr := QsKeyB("to open the backpack", 0)
	if (IsObject(qr))
		return qr
	return QsWaitFor("InventorySpellbookPage", "shown", 1, 3000, "the backpack page")
	}

;The book closed again after a look (B - it was opened with B), checked
QsCloseBook()
	{
	g := QsGui("DeckConfiguration")
	if (!IsObject(g) || !g.win["DeckConfiguration"].shown)
		return ""
	qr := QsKeyB("to close the backpack", 1)
	if (IsObject(qr))
		return qr
	return QsWaitFor("DeckConfiguration", "shown", 0, 1500, "the book to close")
	}

;Quick Sell opened from the backpack page, on its BACKPACK tab (never the bank's)
QsOpenQuickSell()
	{
	qr := QsClickWait("InventorySpellbookPage/QuickSell_Item", "", "buyWindow", 3000, "the Quick Sell window")
	if (IsObject(qr))
		return qr
	g := QsGui("shopGUI,shopGUI/sellTab,shopGUI/bankSellTab,buyWindow")
	if (!IsObject(g))
		return QsFail("the Quick Sell window can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message after Quick Sell: """ g.box.caption """")
	if (g.win["shopGUI/sellTab"].checked != 1 || g.win["shopGUI/bankSellTab"].checked = 1)
		return QsFail("Quick Sell isn't on its BACKPACK tab (never the bank's - BACKPACK " g.win["shopGUI/sellTab"].checked ", BANK " g.win["shopGUI/bankSellTab"].checked ")")
	return ""
	}

;The groups sold - the gear's eight and the pets' (quicksellpets), never the All group - less any group an Equipment
;Set's item in the backpack is in: {list: [{name, kind, path}], skipped, gearMax, petMax (the most each can hold - the
;backpack's items of those kinds, by the game's memory)}; "" and why when a set item's kind isn't known
QsCategories(bag, ByRef why)
	{
	why := ""
	;(the sets not all read: an item of one could be sold - nothing is)
	if (!bag.setsOk)
		{
		why := "the Equipment Sets couldn't all be read from the game's memory - nothing sold (a set's item could be)"
		return ""
		}
	qAll := [["Hat", "hat"], ["Robe", "robe"], ["Shoes", "shoes"], ["Weapon", "weapon"], ["Athame", "athame"], ["Amulet", "amulet"], ["Ring", "ring"], ["Deck", "deck"]]
	if (QsPets())
		qAll.Push(["Pet", "pet"])
	qGuard := {}
	for qi, qs in bag.setItems
		{
		qName := qs.name != "" ? qs.name : "id " qs.tid
		if (qs.kind = "" || qs.kind = "?")
			{
			why := "an Equipment Set's item in the backpack (" qName ", set " qs.set ") is of a kind the bot can't tell - lock or equip it, or Quick Sell could sell it"
			if (IsFunc("WalkNotify"))
				Func("WalkNotify").Call("quicksell", "lock or equip " qName, "It's in Equipment Set " qs.set " and in the backpack - quick sell could sell it, so it doesn't sell at all till it's locked or equipped.")
			return ""
			}
		qGuard[qs.kind] := (qGuard.HasKey(qs.kind) ? qGuard[qs.kind] ", " : "") qName " (set " qs.set ")"
		}
	qOut := {list: [], skipped: "", gearMax: 0, petMax: 0}
	for qi, qc in qAll
		{
		if (qGuard.HasKey(qc[2]))
			{
			qOut.skipped .= (qOut.skipped = "" ? "" : "; ") qc[1] " (" qGuard[qc[2]] ")"
			continue
			}
		qn := bag.cats.HasKey(qc[2]) ? Max(0, bag.cats[qc[2]].n - bag.cats[qc[2]].nosell) : 0
		;(memPlain: its items that are neither Crowns items nor unsellable, by the game's memory)
		qOut.list.Push({name: qc[1], kind: qc[2], path: "BackpackStuff/ShopCategory_" qc[1]
			, memPlain: bag.cats.HasKey(qc[2]) ? Max(0, bag.cats[qc[2]].n - bag.cats[qc[2]].crowns - bag.cats[qc[2]].nosell) : 0
			, memCrowns: bag.cats.HasKey(qc[2]) ? bag.cats[qc[2]].crowns : 0})
		if (qc[2] = "pet")
			qOut.petMax += qn
		else
			qOut.gearMax += qn
		}
	;(items whose kind wasn't read may be in any group)
	if (bag.cats.HasKey("?"))
		qOut.gearMax += bag.cats["?"].n, qOut.petMax += bag.cats["?"].n
	if (qOut.skipped != "")
		QsLog("left out - an Equipment Set's item is in the group: " qOut.skipped)
	return qOut
	}

;One group: its button, then ALL (the "include Crowns Items?" box answered No), the shown rows checked - every row
;selected but the Crowns items'. picked: its rows selected (0: none to sell)
QsSelectGroup(c, ByRef picked)
	{
	picked := 0
	;(its button clicked unless it's the group shown already - a second click could take it off)
	g := QsGui(c.path)
	if (!IsObject(g) || !IsObject(g.win[c.path]) || !(g.win[c.path].shown && g.win[c.path].checked = 1))
		{
		qr := QsClickWait(c.path, "", c.path, 3000, c.name "'s group", "checked")
		if (IsObject(qr))
			return qr
		}
	qRows := QsRows()
	if (!IsObject(qRows))
		return QsFail(c.name ": its rows can't be read (" NavGuiWhy ")")
	if (!qRows.shown)
		{
		QsLog(c.name ": none to sell")
		return ""
		}
	;(its first page only Crowns items: left alone - unless the game's memory has plain ones in it too, on a later page)
	if (!qRows.plain && c.memPlain <= 0)
		{
		QsLog(c.name ": only Crowns items (" qRows.shown ") - left alone")
		return ""
		}
	qr := QsAll(c)
	if (IsObject(qr))
		return qr
	qRows := QsRows()
	if (!IsObject(qRows))
		return QsFail(c.name ": its rows can't be read after ALL")
	;(ALL took nothing - it toggles? once more. Not when the page shows only Crowns items: none of them is to be selected)
	if (qRows.checked = 0 && qRows.plain)
		{
		QsLog(c.name ": ALL selected nothing - once more")
		qr := QsAll(c)
		if (IsObject(qr))
			return qr
		qRows := QsRows()
		if (!IsObject(qRows))
			return QsFail(c.name ": its rows can't be read after ALL")
		}
	if (qRows.crownsChecked)
		{
		AlertSend("crowns", "quick sell stopped", """Crowns"" items got selected in the Quick Sell window (" c.name ") - nothing sold, the windows closed (gold only).")
		return QsFail(c.name ": a Crowns item's row is selected - nothing sold")
		}
	if (qRows.plainChecked != qRows.plain)
		return QsFail(c.name ": " qRows.plainChecked " of its " qRows.plain " rows selected after ALL - not sure what it would sell")
	;(a first page of Crowns items only: the plain ones the memory counts, on later pages - the confirmation's numbers check it)
	picked := qRows.plain ? qRows.plainChecked : c.memPlain
	QsLog(c.name ": ALL - " picked " selected on its first page" (qRows.shown > picked ? " (" qRows.shown - picked " Crowns items left out)" : "") (qRows.names != "" ? ": " qRows.names : ""))
	return ""
	}

;The Quick Sell list's shown rows (its first page, 10): {shown, plain (not a Crowns item), checked, plainChecked,
;crownsChecked, names} - "" when they can't be read
QsRows()
	{
	qPaths := ""
	Loop, 10
		qPaths .= (qPaths = "" ? "" : ",") "buyWindow/shoplist" A_Index - 1 ",buyWindow/num" A_Index - 1 "/Selected,buyWindow/shoplist" A_Index - 1 "/CrownsIcon"
	g := QsGui(qPaths)
	if (!IsObject(g) || g.box.shown)
		return ""
	qOut := {shown: 0, plain: 0, checked: 0, plainChecked: 0, crownsChecked: 0, names: ""}
	Loop, 10
		{
		qRow := g.win["buyWindow/shoplist" A_Index - 1], qSel := g.win["buyWindow/num" A_Index - 1 "/Selected"], qCr := g.win["buyWindow/shoplist" A_Index - 1 "/CrownsIcon"]
		if (!qRow.shown)
			continue
		qOut.shown += 1
		qCrown := qCr.shown ? 1 : 0
		qOn := qSel.checked = 1 ? 1 : 0
		qOut.plain += !qCrown, qOut.checked += qOn
		qOut.plainChecked += (qOn && !qCrown), qOut.crownsChecked += (qOn && qCrown)
		if (qRow.text != "" && StrLen(qOut.names) < 300)
			qOut.names .= (qOut.names = "" ? "" : ", ") qRow.text (qCrown ? " (Crowns)" : "")
		}
	return qOut
	}

;ALL, and within 1.2 s the box it raises answered - only the "include Crowns Items?" box (No); no box and rows selected
;for 0.45 s in a group the game's memory has no Crowns item in: none coming
QsAll(c)
	{
	qMark := QsLogMark()
	qr := QsClickTarget("buyWindow/AllAction", "ALL")
	if (IsObject(qr))
		return qr
	qt := A_TickCount
	while (A_TickCount - qt < 1200)
		{
		Sleep, 150
		g := QsGui("buyWindow,buyWindow/num0/Selected,buyWindow/num1/Selected,buyWindow/num2/Selected")
		if (IsObject(g) && !g.box.shown && A_TickCount - qt >= 450 && !c.memCrowns
			&& (g.win["buyWindow/num0/Selected"].checked = 1 || g.win["buyWindow/num1/Selected"].checked = 1 || g.win["buyWindow/num2/Selected"].checked = 1))
			return ""
		if (IsObject(g) && g.box.shown)
			{
			qr := QsAnswerBox(g, "select", qMark, "", qSaid)
			if (IsObject(qr))
				return qr
			if (qSaid != "No")
				return QsFail("a game message after ALL was answered " qSaid)
			return ""
			}
		if (!QsOk(qWhy, qKind))
			return QsStop(qKind, qWhy)
		}
	return ""
	}

;The confirmation's numbers read from the game's memory and checked (QsConfirmOk), its SELL read on screen. nums: {name:
;{n, gold}} - Equipment, CrownEquipment, Furniture, CrownFurniture, Jewels, Reagents, TreasureCards, Pet, Total - and
;lost: the gold over the pouch (sold all the same: you said so)
QsConfirm(cats, ByRef nums)
	{
	nums := {}
	qPaths := "QuickSellConfirmationWindow/SellButton"
	for qi, qn in QsConfirmNames()
		qPaths .= ",QuickSellConfirmationWindow/" qn "Number,QuickSellConfirmationWindow/" qn "Gold"
	g := QsGui(qPaths)
	if (!IsObject(g))
		return QsFail("the confirmation can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message over the confirmation: """ g.box.caption """")
	;(AHK names aren't case-sensitive: the windows' variables named apart from the loop's qn)
	for qi, qn in QsConfirmNames()
		{
		qNumW := g.win["QuickSellConfirmationWindow/" qn "Number"], qGoldW := g.win["QuickSellConfirmationWindow/" qn "Gold"]
		nums[qn] := {n: qNumW.shown ? QsDigits(qNumW.text) : "", gold: qGoldW.shown ? QsDigits(qGoldW.text) : ""}
		}
	qOk := QsConfirmOk(nums, QsPets(), QsBefore.gold, QsBefore.pouch, cats.gearMax, cats.petMax, qWhy, qLost)
	nums.lost := qLost
	QsLog("confirmation - equipment " nums.Equipment.n " (" QsThousands(nums.Equipment.gold) " gold), pets " nums.Pet.n " (" QsThousands(nums.Pet.gold) "), Crown equipment " nums.CrownEquipment.n
		. ", Crown furniture " nums.CrownFurniture.n ", furniture " nums.Furniture.n ", jewels " nums.Jewels.n ", reagents " nums.Reagents.n ", treasure cards " nums.TreasureCards.n
		. " - total " nums.Total.n " for " QsThousands(nums.Total.gold) " gold" (qLost > 0 ? " (" QsThousands(qLost) " of it over the gold pouch's " QsThousands(QsBefore.pouch) " - lost, sold all the same)" : "")
		. " (the groups chosen hold up to " cats.gearMax " gear" (QsPets() ? " and " cats.petMax " pets" : "") " by the game's memory)")
	if (!qOk)
		{
		if (InStr(qWhy, "Crown"))
			AlertSend("crowns", "quick sell stopped", "The Quick Sell confirmation listed Crowns items - closed, nothing sold (gold only).")
		return QsFail("the confirmation: " qWhy)
		}
	w := g.win["QuickSellConfirmationWindow/SellButton"]
	if (!QsReadWord(w.l, w.t, w.r, w.b, g, "SELL"))
		return QsFail("the confirmation's SELL button doesn't read SELL on screen - not clicked")
	return ""
	}

QsConfirmNames()
	{
	static qNames := ["Equipment", "CrownEquipment", "Furniture", "CrownFurniture", "Jewels", "Reagents", "TreasureCards", "Pet", "Total"]
	return qNames
	}

;The confirmation's numbers fine to sell (pure): every one read; Crown Equipment and Crown Furniture 0; pets 0 unless
;pets; furniture, jewels, reagents, treasure cards 0; a total of 1 or more that is its rows' (count and gold); no more
;gear / pets than the groups chosen hold (gearMax, petMax - "" not known). why: what's wrong; lost: the gold over the pouch
QsConfirmOk(nums, pets, gold, pouch, gearMax, petMax, ByRef why, ByRef lost)
	{
	why := "", lost := 0
	for qi, qn in QsConfirmNames()
		if (!IsObject(nums[qn]) || nums[qn].n = "" || nums[qn].gold = "")
			{
			why := "its numbers couldn't all be read (" qn ")"
			return false
			}
	if (nums.CrownEquipment.n != 0 || nums.CrownFurniture.n != 0)
		{
		why := "Crown items in it (Crown Equipment " nums.CrownEquipment.n ", Crown Furniture " nums.CrownFurniture.n ")"
		return false
		}
	if (!pets && nums.Pet.n != 0)
		{
		why := nums.Pet.n " pets in it - quicksellpets is off"
		return false
		}
	for qi, qn in ["Furniture", "Jewels", "Reagents", "TreasureCards"]
		if (nums[qn].n != 0)
			{
			why := "not gear: " qn " " nums[qn].n
			return false
			}
	qSumN := 0, qSumG := 0
	for qi, qn in QsConfirmNames()
		if (qn != "Total")
			qSumN += nums[qn].n, qSumG += nums[qn].gold
	if (nums.Total.n < 1)
		{
		why := "nothing in it"
		return false
		}
	if (nums.Total.n != qSumN || nums.Total.gold != qSumG)
		{
		why := "its total (" nums.Total.n " for " nums.Total.gold ") isn't its rows' (" qSumN " for " qSumG ") - misread"
		return false
		}
	if (gearMax != "" && nums.Equipment.n > gearMax)
		{
		why := nums.Equipment.n " gear in it - more than the groups chosen hold (" gearMax ")"
		return false
		}
	if (petMax != "" && nums.Pet.n > petMax)
		{
		why := nums.Pet.n " pets in it - more than the backpack holds (" petMax ")"
		return false
		}
	if (pouch > 0 && gold != "")
		lost := Max(0, gold + nums.Total.gold - pouch)
	return true
	}

;SELL in the confirmation, and within 2 s: the waiting window or the sale in the game's log (the pets box first: Yes
;when its count is the confirmation's and quicksellpets is on, else No). A Crowns box: nothing clicked, stopped
QsConfirmSell(nums)
	{
	qMark := QsLogMark()
	g := QsGui("QuickSellConfirmationWindow/SellButton")
	w := IsObject(g) ? g.win["QuickSellConfirmationWindow/SellButton"] : ""
	;(the Crown check round it kept tight: the window's own "Crown Equipment" / "Crown Furniture" labels are above it -
	;the memory's numbers are its Crown check)
	qRad := IsObject(w) && w.found ? Round(Max(w.r - w.l, w.b - w.t) * GameW / g.rootW / 2) + 40 : ""
	qr := QsClickTarget("QuickSellConfirmationWindow/SellButton", "SELL", qRad)
	if (IsObject(qr))
		return qr
	qt := A_TickCount
	while (A_TickCount - qt < 2000)
		{
		Sleep, 150
		QsLogNew()
		if (QsLogHas("sold", qMark) || QsLogHas("gui", qMark, "QuickSellWaitingWindow"))
			return ""
		g := QsGui("QuickSellWaitingWindow,QuickSellConfirmationWindow")
		if (!IsObject(g))
			continue
		if (g.win["QuickSellWaitingWindow"].shown)
			return ""
		if (g.box.shown)
			{
			qr := QsAnswerBox(g, "sell", qMark, nums.Pet.n, qSaid)
			if (IsObject(qr))
				return qr
			if (qSaid != "Yes")
				return QsFail("the box after SELL was answered " qSaid " - not sold")
			qt := A_TickCount
			}
		}
	return QsFail("no sale after the confirmation's SELL (no waiting window, nothing in the game's log in 2 s)")
	}

;The sale checked: the backpack's count down by the total (one off allowed), the gold up by it (or at the pouch) - in
;15 s; the book closed; every Equipment Set item that was in the backpack still there (one gone: quick sell off)
QsVerify(nums)
	{
	qt := A_TickCount, qb := ""
	qWant := (QsBefore.pouch > 0) ? Min(QsBefore.pouch, QsBefore.gold + nums.Total.gold) : QsBefore.gold + nums.Total.gold
	while (A_TickCount - qt < 15000)
		{
		Sleep, 300
		qb := NavBag()
		if (IsObject(qb) && qb.items != "" && qb.items <= QsBefore.items - nums.Total.n + 1 && qb.gold != "" && qb.gold >= qWant - 1)
			break
		qb := ""
		}
	if (!IsObject(qb))
		return QsFail("the sale didn't go through - the backpack's count and gold didn't change in 15 s")
	QsNoteBag(qb)
	qr := QsCloseAfterSale()
	qHave := {}, qGone := ""
	for qi, qs in qb.setItems
		qHave[qs.gid] := 1
	for qg, qs in QsBefore.sets
		if (!qHave.HasKey(qg))
			qGone .= (qGone = "" ? "" : ", ") (qs.name != "" ? qs.name : "id " qs.tid) " (set " qs.set ")"
	QsLog("quick sold " nums.Total.n " items for " QsThousands(nums.Total.gold) " gold (bag " QsBefore.items " -> " qb.items " of " qb.allowed
		. ", gold " QsThousands(QsBefore.gold) " -> " QsThousands(qb.gold) ")" (nums.lost > 0 ? " - " QsThousands(nums.lost) " gold lost over the pouch" : ""))
	QsTray("Quick sold " nums.Total.n " items for " QsThousands(nums.Total.gold) " gold - the backpack was full.")
	if (qGone != "")
		{
		StatsSet([["quicksell", 0]], "quick sell turned itself off " A_YYYY "-" A_MM "-" A_DD ": an Equipment Set's item was sold (" qGone ")")
		QsLog("an Equipment Set's item is gone after the sale: " qGone " - quick sell turned OFF")
		WalkNotify("quicksell", "an Equipment Set lost an item", "Quick sell sold " qGone " - it has turned itself off (Settings: THE BACKPACK). Lock the items your Equipment Sets use, then switch it on again.")
		AlertSend("inventory", "Equipment Set item sold", "Quick sell sold " qGone " from an Equipment Set - it has turned itself off.")
		}
	return {res: "sold", why: "", n: nums.Total.n, gold: nums.Total.gold, lost: nums.lost, after: qb, gone: qGone}
	}

;After the sale the game closes the book itself; still open: its close button
QsCloseAfterSale()
	{
	qt := A_TickCount
	while (A_TickCount - qt < 1500)
		{
		g := QsGui("DeckConfiguration,QuickSellWaitingWindow")
		if (IsObject(g) && !g.win["DeckConfiguration"].shown && !g.win["QuickSellWaitingWindow"].shown && !g.box.shown)
			return ""
		Sleep, 300
		}
	return QsBackOut("the book left open after the sale") ? "" : {res: "failed", why: "the book stayed open"}
	}

;---- Backing out ----

;Closes the run's windows, the topmost first - a box (No; OK only on the safe list; any other left to you), the
;confirmation, Quick Sell, the book - each close checked within 1.5 s; 3 rounds. True when they're all closed. Your mouse or
;keys, a battle, the bot off stop it at once (the windows are yours / closed after the battle)
QsBackOut(why)
	{
	qPaths := "QuickSellConfirmationWindow,QuickSellConfirmationWindow/QuickSellConfirmationCloseButton,QuickSellWaitingWindow,shopGUI,buyWindow,buyWindow/exit,DeckConfiguration,DeckConfiguration/Close_Button"
	qClosed := ""
	Loop, 8
		{
		g := QsGui(qPaths)
		if (!IsObject(g))
			{
			QsLog("backing out (" why "): the game's windows can't be read (" NavGuiWhy ") - left as they are")
			return false
			}
		qWhat := g.box.shown ? "box" : g.win["QuickSellConfirmationWindow"].shown ? "confirmation" : g.win["QuickSellWaitingWindow"].shown ? "waiting"
			: g.win["buyWindow"].shown || g.win["shopGUI"].shown ? "quicksell" : g.win["DeckConfiguration"].shown ? "book" : ""
		if (qWhat = "")
			{
			if (qClosed != "")
				QsLog("quick sell stopped (" why ") - closed: " qClosed)
			return true
			}
		if (A_Index > 6)
			break
		if (qWhat = "waiting")
			{
			Sleep, 500
			continue
			}
		if (!QsOk(qWhy, qKind, true))
			{
			QsLog("backing out (" why ") stopped: " qWhy)
			if (qKind = "battle")
				QsLeftover := 1
			return false
			}
		if (qWhat = "box")
			{
			QsLogNew()
			qAns := QsBoxAnswer(g.box, QsLogBoxKey(""), g.btns, "backout", 0, "", QsLogBoxMsg(""))
			if (qAns.say != "No" && qAns.say != "OK")
				{
				QsLog("backing out (" why "): a game message I won't answer - """ g.box.caption """ (" qAns.why ") - left to you")
				if (qAns.crown)
					AlertSend("crowns", "quick sell stopped", "A Crowns box came up in the Quick Sell window - nothing clicked (gold only): """ g.box.caption """")
				WalkNotify("window", "a game message is up", g.box.caption " - quick sell left it to you.")
				return false
				}
			qr := QsClickBox(g, qAns.say, qAns.crownSel)
			qGone := "box"
			}
		else if (qWhat = "confirmation")
			qr := QsClickTarget("QuickSellConfirmationWindow/QuickSellConfirmationCloseButton", ""), qGone := "QuickSellConfirmationWindow"
		else if (qWhat = "quicksell")
			qr := QsClickTarget("buyWindow/exit", ""), qGone := "buyWindow"
		else if (g.win["DeckConfiguration/Close_Button"].found)
			qr := QsClickTarget("DeckConfiguration/Close_Button", ""), qGone := "DeckConfiguration"
		else
			qr := QsKeyB("to close the book (its close button not read)", 1), qGone := "DeckConfiguration"
		if (IsObject(qr))
			{
			QsLog("backing out (" why "): " qr.why)
			if (qr.res = "stopped" && qr.kind = "battle")
				QsLeftover := 1
			if (qr.res != "stopped")
				WalkNotify("window", "the Quick Sell window won't close", "Quick sell stopped (" why ") and couldn't close its windows: " qr.why)
			return false
			}
		qClosed .= (qClosed = "" ? "" : ", ") qWhat
		;(each close checked: gone within 1.5 s)
		qt := A_TickCount
		while (A_TickCount - qt < 1500)
			{
			Sleep, 150
			g2 := QsGui(qGone = "box" ? "buyWindow" : qGone)
			if (IsObject(g2) && (qGone = "box" ? !g2.box.shown : !g2.win[qGone].shown))
				break
			}
		}
	QsLog("backing out (" why "): still open after 3 rounds - left to you")
	WalkNotify("window", "the Quick Sell window won't close", "Quick sell stopped (" why ") and its windows are still open.")
	return false
	}

;---- Message boxes ----

;What to answer a game message box (pure): {say: "No" / "Yes" / "OK" / "" (none - back out), why, crown (a Crowns box:
;stopped, nothing clicked), crownSel (the "include Crowns Items?" box)}. box: {caption, title, captionKey}; logKey and
;logMsg: the game's log's DisplayMessageBox for it (key, message); btns: its shown buttons' {label}; stage: select (after
;ALL), sell (after the confirmation's SELL), backout; pets: quicksellpets; petCount: the confirmation's pets
QsBoxAnswer(box, logKey, btns, stage, pets, petCount, logMsg := "")
	{
	qCap := Trim(box.caption), qTitle := Trim(box.title)
	;(the one Crown box it may click: "include Crowns Items in the selected items?" - only No, only when the game's log's key,
	;the caption and the button's label agree; never Yes)
	if (logKey = "GUI2_00001001" && (box.captionKey = "" || box.captionKey = "GUI2_00001001")
		&& RegExMatch(qCap, "i)^Would you like to include Crowns Items in the selected items\?$"))
		{
		if (QsHasLabel(btns, "No") = 1)
			return {say: "No", crownSel: 1, why: "the ""include Crowns Items?"" box - No: they stay out"}
		return {say: "", crown: 1, why: "the ""include Crowns Items?"" box without one No button"}
		}
	if (RegExMatch(qCap " " qTitle " " logMsg, "i)cr[o0]wn"))
		return {say: "", crown: 1, why: "a Crowns box (" (logKey != "" ? logKey : "no key in the log") ")"}
	;(the pets box after the confirmation's SELL: Yes only with quicksellpets and the confirmation's own count)
	if (logKey = "GUI2_00000988" || logKey = "GUI2_00000989")
		{
		qN := ""
		for qi, qt in [qCap, logMsg]
			if (qN = "" && RegExMatch(qt, "i)^You are selling (a|\d+) Pets?\. Are you sure you want to sell (a|these) Pets?\?$", qm))
				qN := (qm1 = "a") ? 1 : qm1 + 0
		if (stage = "sell" && pets && qN != "" && petCount != "" && qN = petCount && QsHasLabel(btns, "Yes") = 1)
			return {say: "Yes", why: "the pets box (" qN ", as the confirmation counted) - Yes: quicksellpets is on"}
		if (QsHasLabel(btns, "No") = 1)
			return {say: "No", why: "the pets box (" (qN = "" ? "?" : qN) (petCount != "" ? ", the confirmation " petCount : "") (pets ? "" : ", quicksellpets off") ") - No"}
		return {say: "", why: "the pets box without one No button"}
		}
	;(an OK-only box that's safe to OK)
	qKey := box.captionKey != "" ? box.captionKey : logKey
	if (RegExMatch(qKey, "^(GUI_NoQuickSell|GUI_NoQuickSellWhileShopping|GUI_00001109|GUI2_00001002|Housing_18)$") && btns.Length() = 1 && QsHasLabel(btns, "OK") = 1)
		return {say: "OK", why: "a message to OK (" qKey ")"}
	return {say: "", why: "a game message it doesn't know (" (qKey != "" ? qKey : "no key") ")"}
	}

;How many of the buttons have the label (exactly, case aside)
QsHasLabel(btns, label)
	{
	qn := 0
	for qi, qb in btns
		if (Trim(qb.label) = label)
			qn += 1
	return qn
	}

;A box answered (QsBoxAnswer) and its button clicked; gone within 1.5 s. said: the answer clicked
QsAnswerBox(g, stage, mark, petCount, ByRef said)
	{
	said := ""
	QsLogNew()
	qKey := QsLogBoxKey(mark), qMsg := QsLogBoxMsg(mark)
	qAns := QsBoxAnswer(g.box, qKey, g.btns, stage, QsPets(), petCount, qMsg)
	QsLog("box: """ g.box.caption """ (" (qKey != "" ? qKey : "no key in the game's log") ") - " qAns.why)
	if (qAns.crown)
		return QsCrownBox(g.box, qAns.why)
	if (qAns.say = "")
		return QsFail("a game message: """ g.box.caption """ - " qAns.why)
	qr := QsClickBox(g, qAns.say, qAns.crownSel)
	if (IsObject(qr))
		return qr
	said := qAns.say
	qt := A_TickCount
	while (A_TickCount - qt < 1500)
		{
		Sleep, 150
		g2 := QsGui("buyWindow")
		if (IsObject(g2) && !g2.box.shown)
			return ""
		}
	return QsFail("the box didn't go after " said)
	}

;A box's button clicked by its label (never by its place): one button with it, its size, its word read off the screen,
;no "Crown" round it (but for the "include Crowns Items?" box's No - its own words say Crowns), then the click
QsClickBox(g, say, crownSel)
	{
	qb := "", qn := 0
	for qi, qx in g.btns
		if (Trim(qx.label) = say)
			qb := qx, qn += 1
	if (qn != 1)
		return {res: "failed", why: "the box has " qn " """ say """ buttons"}
	if (Abs(qb.r - qb.l - 128) > 2 || Abs(qb.b - qb.t - 32) > 2 || qb.greyed = 1)
		return {res: "failed", why: "the box's """ say """ button isn't as the game's file has it (" qb.r - qb.l "x" qb.b - qb.t (qb.greyed = 1 ? ", greyed" : "") ")"}
	if (qb.l < 0 || qb.t < 0 || qb.r > g.rootW || qb.b > g.rootH)
		return {res: "failed", why: "the box's """ say """ button is off the game"}
	QsPx(qb.l, qb.t, qb.r, qb.b, g.rootW, g.rootH, qx, qy)
	if (!QsPxOk(qx, qy, qWhyPx))
		return {res: "failed", why: "the box's """ say """ button: " qWhyPx}
	if (!QsReadWord(qb.l, qb.t, qb.r, qb.b, g, say))
		return {res: "failed", why: "the box's button doesn't read """ say """ on screen - not clicked"}
	;(the Crown check round it kept tight - the button and 40 px: the box's own words are checked in memory and the log
	;(QsBoxAnswer), and over the confirmation its "Crown Equipment" label shows just above the box)
	qRad := Round(Max(qb.r - qb.l, qb.b - qb.t) * GameW / g.rootW / 2) + 40
	if (!crownSel && !NoCrownsNear(qx, qy, qRad, "Backpack", "Quick sell", "by the Quick Sell window", "it only sells for gold", "quick sell stopped"))
		return {res: "failed", why: """Crown"" read by the box's button (or the screen couldn't be read) - not clicked"}
	Critical
	if (!QsOk(qWhy, qKind, true))
		{
		Critical, Off
		return QsStop(qKind, qWhy)
		}
	QsInputClick(qx, qy)
	Critical, Off
	QsStep += 1
	QsLog("step " QsStep ": the box's """ say """ at " qx - GameLeft "," qy - GameTop)
	return ""
	}

;A Crown box it may not click (any but "include Crowns Items?"'s No): stopped, nothing clicked - left to you, quick sell off
QsCrownBox(box, why)
	{
	QsLog("a Crowns box: """ box.caption """ - nothing clicked (gold only), quick sell turned OFF; the windows are left to you")
	StatsSet([["quicksell", 0]], "quick sell turned itself off " A_YYYY "-" A_MM "-" A_DD ": a Crowns box came up (" SubStr(box.caption, 1, 60) ")")
	AlertSend("crowns", "quick sell stopped", "A Crowns box came up in the Quick Sell window - nothing clicked (gold only), quick sell turned off: """ box.caption """")
	WalkNotify("window", "a Crowns box is up in Wizard101", """" box.caption """ - quick sell clicked nothing and turned itself off. Answer it yourself (No).")
	QsTray("Quick sell saw a Crowns box and stopped without clicking - it's turned itself off.", 2)
	return {res: "crowns", why: why}
	}

;---- Clicks, keys and checks ----

;Fine to give the game input now: the bot on (or a run from the tray), no key or mouse of yours since the run began,
;Wizard101 in front, no battle; the whole run 60 s at most (not while backing out). kind: off, user, front, battle, cap
QsOk(ByRef why, ByRef kind, backingOut := false)
	{
	why := "", kind := ""
	if (!(BotOn || QsManual))
		why := "the bot was turned off", kind := "off"
	else if (QsSince && A_TickCount - UserIdle() > QsSince)
		why := "you touched the mouse or keyboard - the windows are yours", kind := "user"
	else if (!GameActive())
		why := "Wizard101 isn't the window in front", kind := "front"
	else if (QsBattleNow())
		why := "a battle started", kind := "battle"
	else if (!backingOut && QsSince && A_TickCount - QsSince > 60000)
		why := "the whole run took over 60 s", kind := "cap"
	return why = ""
	}

;A battle on: by the game's log, or its round's Pass button on screen
QsBattleNow()
	{
	BattleLogRead()
	return BattleLogInBattle() || QsBattlePic()
	}

QsStop(kind, why)
	{
	return {res: "stopped", kind: kind, why: why}
	}

QsFail(why)
	{
	return {res: "failed", why: why}
	}

;/gui for paths ("" when it can't be read - NavGuiWhy)
QsGui(paths)
	{
	return NavGui(paths, 600)
	}

;Waits up to ms for the window at path to have prop (shown, checked) = want, polling the game's memory every 150 ms; a
;box coming up, your input, a battle stop it
QsWaitFor(path, prop, want, ms, what)
	{
	qt := A_TickCount
	Loop
		{
		g := QsGui(path)
		if (IsObject(g))
			{
			if (g.box.shown)
				return QsFail("a game message came up waiting for " what ": """ g.box.caption """")
			w := g.win[path], qv := 0
			if (IsObject(w))
				qv := (prop = "checked") ? ((w.shown && w.checked = 1) ? 1 : 0) : (w.shown ? 1 : 0)
			if (qv = want)
				return ""
			}
		if (A_TickCount - qt > ms)
			return QsFail("timed out waiting for " what " (" Round(ms / 1000, 1) " s)")
		if (!QsOk(qWhy, qKind))
			return QsStop(qKind, qWhy)
		Sleep, 150
		}
	}

;A click (QsClickTarget), then a wait for waitPath's prop
QsClickWait(path, label, waitPath, ms, what, prop := "shown")
	{
	qr := QsClickTarget(path, label)
	if (IsObject(qr))
		return qr
	return QsWaitFor(waitPath, prop, 1, ms, what)
	}

;A click on a window of the allow-list, by the game's memory: read now - shown once, inside its parent and the game, its
;size the .gui file's, not greyed, its label - turned into pixels (not the Crown shop's corner, the right-hand column or off
;the game), no "Crown" read round it (r: how far - 260 at UI 1.144 by default), the run still fine (QsOk) right before
QsClickTarget(path, label, r := "")
	{
	g := QsGui(path)
	if (!IsObject(g))
		return QsFail("the game's windows can't be read (" NavGuiWhy ")")
	if (g.box.shown)
		return QsFail("a game message is up (""" g.box.caption """)")
	w := g.win[path]
	if (!QsTargetOk(path, w, g.rootW, g.rootH, label, qWhy))
		return QsFail(path " not clicked: " qWhy)
	QsPx(w.l, w.t, w.r, w.b, g.rootW, g.rootH, qx, qy)
	QsJitter(w.l, w.t, w.r, w.b, g.rootW, g.rootH, qx, qy)
	if (!QsPxOk(qx, qy, qWhy))
		return QsFail(path " not clicked: " qWhy)
	if (!NoCrownsNear(qx, qy, r, "Backpack", "Quick sell", "by the Quick Sell window", "it only sells for gold", "quick sell stopped"))
		return QsFail(path " not clicked: ""Crown"" read round it (or the screen there couldn't be read)")
	Critical
	if (!QsOk(qWhy, qKind, path ~= "exit|Close"))
		{
		Critical, Off
		return QsStop(qKind, qWhy)
		}
	QsInputClick(qx, qy)
	Critical, Off
	QsStep += 1
	QsLog("step " QsStep ": " path " at " qx - GameLeft "," qy - GameTop)
	return ""
	}

;B (the game's backpack key - it toggles the book: open read first, by the caller): the run still fine right before
QsKeyB(what, open)
	{
	Critical
	if (!QsOk(qWhy, qKind, open = 1))
		{
		Critical, Off
		return QsStop(qKind, qWhy)
		}
	QsInputKeyB()
	Critical, Off
	QsStep += 1
	QsLog("step " QsStep ": B " what)
	return ""
	}

;The windows it may click (nothing else, ever) and their size in the game's .gui files (GUI units), or ""
QsTargetSize(path)
	{
	static qSizes := ""
	if (!IsObject(qSizes))
		{
		qSizes := {"InventorySpellbookPage/QuickSell_Item": [50, 50], "buyWindow/AllAction": [57, 32], "buyWindow/sellAction": [254, 32]
			, "buyWindow/exit": [47, 47], "QuickSellConfirmationWindow/SellButton": [177, 32]
			, "QuickSellConfirmationWindow/QuickSellConfirmationCloseButton": [47, 47], "DeckConfiguration/Close_Button": [40, 37]
			, "DeckConfiguration/Inventory": [40, 37]}
		for qi, qc in ["Hat", "Robe", "Shoes", "Weapon", "Athame", "Amulet", "Ring", "Deck", "Pet"]
			qSizes["BackpackStuff/ShopCategory_" qc] := [49, 49]
		}
	return qSizes.HasKey(path) ? qSizes[path] : ""
	}

;A window fine to click (pure): on the allow-list, found and shown once, inside its parent and the root, its .gui size
;(2 units either way), not greyed, its label (case aside; or its .gui key's) when one's given. why: what's wrong
QsTargetOk(path, w, rootW, rootH, label, ByRef why)
	{
	why := ""
	qSize := QsTargetSize(path)
	if (!IsObject(qSize))
		why := "not on the allow-list"
	else if (!IsObject(w) || !w.found)
		why := "not found in the game's windows"
	else if (!w.shown)
		why := "not shown"
	else if (w.dups != 1)
		why := "shown " w.dups " times - which one?"
	else if (w.l = "" || w.r = "" || w.t = "" || w.b = "" || w.r <= w.l || w.b <= w.t)
		why := "its rect is odd (" w.l "," w.t "," w.r "," w.b ")"
	else if (w.l < 0 || w.t < 0 || w.r > rootW || w.b > rootH)
		why := "off the game (" w.l "," w.t "," w.r "," w.b " in " rootW "x" rootH ")"
	else if (w.pl != "" && (w.l < w.pl - 1 || w.t < w.pt - 1 || w.r > w.pr + 1 || w.b > w.pb + 1))
		why := "outside its parent (" w.l "," w.t "," w.r "," w.b " in " w.pl "," w.pt "," w.pr "," w.pb ")"
	else if (Abs(w.r - w.l - qSize[1]) > 2 || Abs(w.b - w.t - qSize[2]) > 2)
		why := "its size " w.r - w.l "x" w.b - w.t " isn't the game file's " qSize[1] "x" qSize[2]
	else if (w.greyed = 1)
		why := "greyed out"
	else if (label != "" && w.text != label && !(label = "SELL" && w.key = "GUI_00006338") && !(label = "ALL" && w.key = "GUI_00006368"))
		why := "its label is """ w.text """, not " label
	return why = ""
	}

;The middle of a GUI rect (the root's units) in screen pixels (pure)
QsPx(l, t, r, b, rootW, rootH, ByRef x, ByRef y)
	{
	x := Round(GameLeft + (l + r) / 2 * GameW / rootW)
	y := Round(GameTop + (t + b) / 2 * GameH / rootH)
	}

;A random bit off the middle (clickrandom on): inside the rect's middle 40%
QsJitter(l, t, r, b, rootW, rootH, ByRef x, ByRef y)
	{
	if (Stat("clickrandom") <= 0)
		return
	qw := Floor((r - l) * GameW / rootW * 0.2), qh := Floor((b - t) * GameH / rootH * 0.2)
	Random, qdx, % -qw, % qw
	Random, qdy, % -qh, % qh
	x += qdx, y += qdy
	}

;A pixel fine to click (pure): on the game, not in the Crown shop's corner (TargetClick's), not in the right-hand column
;of tips (Zeke, the Crown Shop's offers...)
QsPxOk(x, y, ByRef why)
	{
	why := ""
	if (x < GameLeft || y < GameTop || x >= GameLeft + GameW || y >= GameTop + GameH)
		why := "off the game window (" x "," y ")"
	else if (x < GameLeft + Px(185) && y < GameTop + Px(110))
		why := "in the Crown shop's corner"
	else if (x > GameLeft + GameW - Round(130 * GameW / 2560))
		why := "in the right-hand column (the tips: never clicked)"
	return why = ""
	}

;A button's word read off the screen, 3 times bigger, plain, white or yellow ink (yellow-on-red reads badly at 1:1):
;No, Yes, OK, SELL (SEL, 5ELL)
QsReadWord(l, t, r, b, g, word)
	{
	static qRe := {No: "i)^n[o0]$", Yes: "i)^y[e3]s$", OK: "i)^[o0]k(ay)?$", SELL: "i)^(sell|sel|5ell|seli|seil|5el)$"}
	QsPx(l, t, l, t, g.rootW, g.rootH, qx1, qy1)
	QsPx(r, b, r, b, g.rootW, g.rootH, qx2, qy2)
	qPad := Round(3 * GameW / g.rootW)
	qRead := ""
	for qi, qMode in [0, 3, 4]
		{
		qText := QsOcr(qx1 - qPad, qy1 - qPad, qx2 - qx1 + 2 * qPad, qy2 - qy1 + 2 * qPad, 3, qMode)
		if (ErrorLevel)
			continue
		qText := RegExReplace(qText, "[\s.!]+")
		qRead .= (qRead = "" ? "" : " / ") qText
		if (RegExMatch(qText, qRe[word]))
			return true
		}
	QsLog("the button doesn't read """ word """ on screen (read: " (qRead = "" ? "nothing" : qRead) ")")
	return false
	}

;"150/150" -> {n, m}, else ""
QsParseSpace(text)
	{
	if (RegExMatch(text, "(\d{1,4})\s*/\s*(\d{1,4})", qm))
		return {n: qm1 + 0, m: qm2 + 0}
	return ""
	}

;The digits of a number as the game shows it ("12,345" -> 12345), "" none
QsDigits(text)
	{
	qd := RegExReplace(text, "\D")
	return qd = "" ? "" : qd + 0
	}

QsThousands(n)
	{
	if (n = "" || !RegExMatch(n, "^-?\d+$"))
		return n
	qs := "", qn := Abs(n)
	while (qn >= 1000)
		qs := "," SubStr("00" Mod(qn, 1000), -2) qs, qn := Floor(qn / 1000)
	return (n < 0 ? "-" : "") qn qs
	}

;---- The game's log, read by the run itself (its own place; short opens, 1 MB at most a read - never held open) ----

QsLogOpen()
	{
	QsLogEvents := [], QsLogPos := "", QsLogHead := ""
	if (RcLog = "" || !FileExist(RcLog))
		return
	qf := FileOpen(RcLog, "r", "CP0")
	if (!IsObject(qf))
		return
	QsLogHead := qf.Read(17), QsLogPos := qf.Length
	qf.Close()
	}

;What the game's log said since the last read: DisplayMessageBox (box: key, msg), Loaded GUI (gui: its name),
;MSG_QuickSellRequest (sold)
QsLogNew()
	{
	if (QsLogPos = "" || RcLog = "")
		return
	qf := FileOpen(RcLog, "r", "CP0")
	if (!IsObject(qf))
		return
	qSize := qf.Length, qTop := qf.Read(17)
	if (qTop != QsLogHead || qSize < QsLogPos)
		QsLogHead := qTop, QsLogPos := 0
	if (qSize - QsLogPos > 1048576)
		QsLogPos := qSize - 1048576
	if (qSize <= QsLogPos)
		{
		qf.Close()
		return
		}
	qf.Pos := QsLogPos
	qChunk := qf.Read(qSize - QsLogPos)
	qf.Close()
	qNl := InStr(qChunk, "`n", false, 0)
	if (!qNl)
		return
	qChunk := SubStr(qChunk, 1, qNl)
	QsLogPos += StrLen(qChunk)
	if (!IsObject(QsLogEvents))
		QsLogEvents := []
	Loop, Parse, qChunk, `n, `r
		{
		if (InStr(A_LoopField, "DisplayMessageBox("))
			{
			RegExMatch(A_LoopField, "msg = (.*?), title = (.*?), msg string key = (\w*)(?:, title string key = (\w*))?", qm)
			QsLogEvents.Push({kind: "box", key: qm3 != "" ? qm3 : qm4, msg: qm1, title: qm2})
			}
		else if (RegExMatch(A_LoopField, "Loaded GUI '(?:.*[\\/])?([\w]+)\.gui'", qm))
			QsLogEvents.Push({kind: "gui", key: qm1})
		else if (InStr(A_LoopField, "MSG_QuickSellRequest"))
			QsLogEvents.Push({kind: "sold", key: ""})
		}
	}

;Where the events are now (a step's own come after it)
QsLogMark()
	{
	QsLogNew()
	return IsObject(QsLogEvents) ? QsLogEvents.Length() : 0
	}

;The newest box event's key / message since mark ("" from the run's start)
QsLogBoxKey(mark)
	{
	qe := QsLogLastBox(mark)
	return IsObject(qe) ? qe.key : ""
	}

QsLogBoxMsg(mark)
	{
	qe := QsLogLastBox(mark)
	return IsObject(qe) ? qe.msg : ""
	}

QsLogLastBox(mark)
	{
	if (!IsObject(QsLogEvents))
		return ""
	qi := QsLogEvents.Length()
	while (qi > (mark = "" ? 0 : mark))
		{
		if (QsLogEvents[qi].kind = "box")
			return QsLogEvents[qi]
		qi -= 1
		}
	return ""
	}

;An event of kind (and key) since mark
QsLogHas(kind, mark, key := "")
	{
	if (!IsObject(QsLogEvents))
		return false
	for qi, qe in QsLogEvents
		if (qi > mark && qe.kind = kind && (key = "" || qe.key = key))
			return true
	return false
	}

;---- The tray menu ----

;"Quick sell the backpack now" / "Quick sell rehearsal (stops at the confirmation)": straight away, sold whether the game
;says full or not (never in a dungeon); the dungeon's hold dropped (a sale asked for)
QsMenuNow(rehearse := false)
	{
	if (QsBusy)
		{
		QsTray("A quick sell is already under way.")
		return
		}
	qDg := QsDungeonNow()
	if (qDg != "")
		{
		QsLog("asked for from the tray - not in " qDg " (a dungeon's drops are the good gear)")
		QsTray("No quick sell in a dungeon (" qDg ").")
		return
		}
	QsActivateGame()
	UpdateGameRect()
	bag := NavBag()
	if (!IsObject(bag))
		{
		QsLog("asked for from the tray - the game's memory can't be read: " NavBagWhy)
		QsTray("Quick sell needs the game's memory (the vision helper): " NavBagWhy, 2)
		return
		}
	QsNoteBag(bag)
	if (!QsMayRun(qWhy, true))
		{
		QsLog("asked for from the tray - not now: " qWhy)
		QsTray("Quick sell: not now - " qWhy ".", 2)
		return
		}
	if (!rehearse)
		QsMarkClear("a quick sell was asked for from the tray")
	QsRun({why: "asked for from the tray"}, bag, true, rehearse)
	}

;---- The only places this file gives the game input or looks at the screen (tests put recorders here) ----
;QS-INPUT-BEGIN
QsInputClick(x, y)
	{
	MouseMove, x, y, MouseSpeedNow()
	;(a moment on it first - the game takes a hovered click better: the potion run's rule)
	Sleep, % Max(150, Stats.HasKey("clickwait") ? Stats["clickwait"] : 40)
	Click
	}

QsInputKeyB()
	{
	Send, {Blind}b
	}

QsBattlePic()
	{
	ImageSearch, qbX, qbY, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, % PicOpt("resources\roundstart.png")
	return ErrorLevel = 0
	}

QsOcr(x, y, w, h, scale, mode)
	{
	return OcrRect(x, y, w, h, "en", scale, qoLines, mode)
	}

QsTray(text, icon := 1)
	{
	TrayTip, Wizard101 bot, %text%, 8, %icon%
	}

QsSnap(step)
	{
	if (IsFunc("LogMirrorSnap"))
		Func("LogMirrorSnap").Call(0, "quicksell")
	}

QsActivateGame()
	{
	WinActivate, ahk_class %GameClass% ahk_exe %GameExe%
	WinWaitActive, ahk_class %GameClass% ahk_exe %GameExe%, , 2
	Sleep, 800
	}
;QS-INPUT-END
