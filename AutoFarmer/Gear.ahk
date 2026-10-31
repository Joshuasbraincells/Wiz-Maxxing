; Gear.ahk - gear compared with what's worn (TODO goal 5, "gear dungeons until all gear is swapped", v0.9.0): the worn
; gear and the backpack's read from the game's memory (the vision helper's /gear - READ-ONLY, vision\gearmem.py: each
; piece's equip effects and requirements), the best piece a slot worked out for your battle role (vision\gearrank.py: your
; stats from PlayerStats.txt - the worn gear in them - with the worn piece's taken off and the candidate's added; the
; pieces' stats are NOT CONFIRMED in the game yet: ADVICE) and logged "Gear: ..." - before a full backpack is quick sold
; (QuickSell.ahk QsLook: a better piece in the backpack holds the sale - GearSellOk) and after each dungeon run (Dungeons.ahk
; DgBetweenRuns: the run's new pieces logged in learned\drops\<run>.txt, its "done" for "Until its gear is swapped" -
; GearRunMark / GearRunEnd).
; AutoHotkey v2, written for v2 (v1 never had this: nothing here is ported); #Included by Autofarmer.ahk only.
;
; Settings > THE BACKPACK: gearswap - 0 off (the default: nothing asked, quick sell and dungeon runs exactly as before),
; 1 REHEARSAL: the plan logged, NOTHING equipped - no key, no click, no window (2, the equip itself: NOT BUILT - GearPass's
; TODO; read as 1, said once). gearsets - 1: a slot whose worn piece is in an Equipment Set is planned like any other (you
; re-save the set yourself: the bot never saves one); 0 (the default): such a plan line is "held" and you're asked once to
; re-save the set after a swap (GearSetGuard) - Decks.ahk's Ctrl+N would put the old piece back. Hidden (PlayerStats.txt):
; gearmargin:N (2 - the % a piece must be better by), gearweight.off:1, gearweight.def:0.5, gearweight.pip:0.3,
; gearweight.heal:0, gearweight.cards:0.002, gearweight.eblock:200 (the score's weights, one number a line - KillCalc.ahk
; ParseStat reads only key:number; each left out: your party battle role's - Hitter, Blader, Healer), gearlevel:N (your
; level when the game's memory doesn't give it).
; Never anything that could spend Crowns: nothing is clicked at all (a Crown-shop piece may be planned - wearing one spends
; nothing). debug.log: "Gear: ..."; a better piece: a tray tip once; a held one: a Discord alert once.

;(v2-only globals - declared here with no value: a top-level := in an #Included file never runs - GearBlank sets them blank,
;the entry script calls it first thing) What's been said when ({key: tick}), the last /gear reading, the plans already shown
;in a tray tip / the worn pieces already alerted about ({key: 1}), the gearswap:2 notice said
global GearSaidAt, GearLast, GearTipped, GearSetSaid, GearTwoSaid

;---- The settings ----

;gearswap: 0 off, 1 the rehearsal (the plan logged, nothing equipped) - 2 and more: the equip, not built: a rehearsal too
GearMode()
	{
	global GearTwoSaid ; (v1 globals it sets)
	gmV := Stats.Has("gearswap") ? V1Round(Stats["gearswap"]) : 0
	if (gmV >= 2 && !GearTwoSaid)
		GearTwoSaid := 1, GearLog("gearswap:" gmV " - equipping isn't built yet (the backpack's item windows haven't been looked at in the game): a rehearsal, as gearswap:1")
	return gmV >= 1 ? 1 : 0
	}

;gearsets: a slot whose worn piece is in an Equipment Set planned like any other (you re-save the set)
GearSets()
	{
	return (Stats.Has("gearsets") && Stats["gearsets"] = 1) ? 1 : 0
	}

GearLog(msg)
	{
	DebugLog("Gear: " msg)
	}

;Said once in every ms (10 minutes) for its key; true when said now (QuickSell.ahk QsSay's way)
GearSay(key, msg, every := 600000)
	{
	global GearSaidAt ; (v1 globals it sets)
	if (!IsObject(GearSaidAt))
		GearSaidAt := V1Obj()
	if (GearSaidAt.Has(key) && A_TickCount - GearSaidAt[key] < every)
		return false
	GearSaidAt[key] := A_TickCount
	GearLog(msg)
	return true
	}

;---- Asking the helper ----

;A stat of your wizard's for school gsSch (PlayerStats.txt: <school>.key, else key) - "" none
GearStat(gsSch, gsKey)
	{
	if (gsSch != "" && Stats.Has(gsSch "." gsKey))
		return Stats[gsSch "." gsKey]
	return Stats.Has(gsKey) ? Stats[gsKey] : ""
	}

;Your battle role for the score: your party battle role (Settings: partybattle) while you're in a party, else a hitter
GearRole()
	{
	if (V1IsFunc("PartyRoleSet") && PartyRoleSet.Call() != "off" && V1IsFunc("PartyBattleSet"))
		return PartyBattleSet.Call()
	return "hitter"
	}

;/gear's arguments (no "?"): your school, role and level (gearlevel), your totals - damage, pierce, critical, block,
;accuracy, resist for your school (StatsReader's PlayerStats lines), health (maxhealth, else the globe's most), the margin,
;the weights, gearsets - then extra (a dungeon run's run=...)
GearQuery(extra := "")
	{
	gqSch := V1IsFunc("StatsSchoolOf") ? StatsSchoolOf.Call(StatsCharID.Call()) : ""
	gqQ := "school=" gqSch "&role=" GearRole()
	gqLv := Stats.Has("gearlevel") ? V1Round(Stats["gearlevel"]) : 0
	if (gqLv > 0)
		gqQ .= "&level=" gqLv
	for gqI, gqK in [["damage", "damage"], ["pierce", "pierce"], ["crit", "critical"], ["block", "block"], ["acc", "accuracy"], ["resist", "resist"]]
		{
		gqV := GearStat(gqSch, gqK[2])
		if (gqV != "" && gqV != 0)
			gqQ .= "&" gqK[1] "=" NavUri(gqV "")
		}
	gqHp := GearStat(gqSch, "maxhealth")
	if ((gqHp = "" || gqHp = 0) && OwnHpMax)
		gqHp := OwnHpMax
	if (gqHp != "" && gqHp != 0)
		gqQ .= "&hp=" NavUri(gqHp "")
	if (Stats.Has("gearmargin"))
		gqQ .= "&margin=" NavUri(Stats["gearmargin"] "")
	;(the score's weights: gearweight.off / .def / .pip / .heal / .cards / .eblock lines - one number each, as ParseStat reads
	;them - sent as weights=off:1,def:0.5 (vision\gearrank.py parse_weights); each left out keeps the role's)
	gqW := ""
	for gqI, gqK in ["off", "def", "pip", "heal", "cards", "eblock"]
		if (Stats.Has("gearweight." gqK))
			gqW .= (gqW = "" ? "" : ",") gqK ":" Stats["gearweight." gqK]
	if (gqW != "")
		gqQ .= "&weights=" NavUri(gqW)
	if (GearSets())
		gqQ .= "&sets=1"
	return gqQ extra
	}

;---- The pass ----

;The gear pass (gearswap on): /gear read and its plan logged as advice - nothing equipped (the rehearsal). why: what it's
;for (the log); extra: /gear's run=... (Dungeons.ahk); always: the plan logged even when it's the same as last time (a
;dungeon run's end - else once in 10 minutes). The reading (NavGear's: plan, items, better, unknown, run...) - "" off or
;not read (NavGearWhy)
GearPass(why, extra := "", always := false)
	{
	global GearLast ; (v1 globals it sets)
	if (!GearMode())
		return ""
	gpG := NavGear(GearQuery(extra))
	if (!IsObject(gpG))
		{
		GearSay("nomem", "no gear pass (" why ") - " NavGearWhy)
		return ""
		}
	GearLast := gpG
	GearReport(gpG, why, always)
	GearSetGuard(gpG)
	;TODO (needs the game - the backpack page's item windows nobody has looked at yet): equip each plan line that isn't
	;held, gearswap:2 - B (QuickSell.ahk QsOpenBook), the piece's window found by its gid (python vision\bagmem.py --tree
	;--under InventorySpellbookPage --out bag.txt while the backpack shows: how a window maps to its item, paging), hovered
	;and clicked with QsClickTarget's / QsClickAt's checks (no key or mouse of yours, the bot on, Wizard101 in front, no
	;battle, the mouse lock), the gid read back as worn from /gear (this reading's worn| lines), QsBackOut on anything it
	;doesn't know, the game's "Slow down!" limit as DeckEquip's (one a minute). Till then 1 and 2 only log the plan.
	return gpG
	}

;"hat: Fire Hat (+3.3%), robe: Storm Robe (+20 levels)" - a reading's plan, its first 3
GearPlanText(g)
	{
	gptOut := ""
	for gptI, gptP in g.plan
		{
		if (gptI > 3)
			{
			gptOut .= ", ..."
			break
			}
		gptOut .= (gptOut = "" ? "" : ", ") gptP.slot ": " (gptP.name != "" ? gptP.name : "?") " (" GearDeltaText(gptP) ")"
		}
	return gptOut
	}

;"+3.3%", "+20 levels", "nothing worn there"
GearDeltaText(p)
	{
	if (p.basis = "empty")
		return "nothing worn there"
	;(a delta not read - "" - isn't compared: v2 throws on text there)
	if (p.basis = "level")
		return "+" V1Round(p.delta) " level" (V1Round(p.delta) = 1 ? "" : "s") " - its stats' sizes not known"
	return p.delta != "" ? Format("{:+.1f}", p.delta) "%" : "?%"
	}

;The pieces not judged and why - their first 2
GearUnknownText(g)
	{
	gutOut := "", gutN := 0
	for gutI, gutT in g.items
		{
		if (gutT.verdict != "unknown")
			continue
		gutN += 1
		if (gutN > 2)
			{
			gutOut .= "; ..."
			break
			}
		;(one whose template couldn't be read has no name: its id)
		gutOut .= (gutOut = "" ? "" : "; ") (gutT.display != "" ? gutT.display : gutT.name != "" ? gutT.name : "item " gutT.gid) ": " gutT.why
		}
	return gutOut
	}

;A reading's plan into the log - each line's piece, the worn one, by how much and why; the helper's notes; the pieces not
;judged. The same plan again: said once in 10 minutes (always: said). A new better piece: a tray tip, once
GearReport(g, why, always := false)
	{
	global GearTipped ; (v1 globals it sets)
	grSig := ""
	for grI, grP in g.plan
		grSig .= grP.slot ":" grP.gid ","
	grHead := "REHEARSAL (nothing equipped) - " why ": " g.bagN " gear piece" (g.bagN = 1 ? "" : "s") " in the backpack - " g.better " better, "
		. (g.judged - g.better) " not, " g.unknown " not judged"
	if (!always && !GearSay("plan|" grSig "|" g.unknown, grHead))
		return
	if (always)
		GearLog(grHead)
	for grI, grP in g.plan
		GearLog("  " grP.slot ": " (grP.name != "" ? grP.name : "?") " instead of " (grP.wornName != "" ? grP.wornName : "nothing") " - "
			. GearDeltaText(grP) " (" grP.why ")" (grP.held ? " - HELD: re-save that Equipment Set after a swap" : "") " - advice: put it on yourself")
	for grI, grN in g.notes
		GearSay("note|" grN, "  note: " grN, always ? 0 : 600000)
	if (g.unknown)
		GearLog("  not judged: " GearUnknownText(g))
	if (!IsObject(GearTipped))
		GearTipped := V1Obj()
	if (g.plan.Length && !GearTipped.Has(grSig))
		{
		GearTipped[grSig] := 1
		TrayTip("A better piece is in your backpack: " GearPlanText(g) ". Advice only - put it on yourself (the gear pass is a rehearsal).", "Wizard101 bot", 1)
		}
	}

;The Equipment Set guard: a plan line whose worn piece is in an Equipment Set (held - gearsets off) - a swap would be undone
;by that set's Ctrl+N (Decks.ahk DeckEquip): you're asked, once a piece, to re-save the set in the game after you swap it.
;The bot never saves a set itself (its window's controls aren't known - and a set is yours). (A Discord alert, not a "needs
;you" notice: a notice holds the walking and the quick sell till it's answered.) Every piece new this pass in ONE alert, its
;kind named by those pieces: AlertSend sends one alert of a kind in 10 minutes - a second "gear" one in the same pass, or a
;new piece in the next pass, would be dropped and, already marked said, never sent
GearSetGuard(g)
	{
	global GearSetSaid ; (v1 globals it sets)
	if (!IsObject(GearSetSaid))
		GearSetSaid := V1Obj()
	gsgKind := "", gsgText := ""
	for gsgI, gsgP in g.plan
		{
		if (!gsgP.held || GearSetSaid.Has(gsgP.wornGid "|" gsgP.gid))
			continue
		GearSetSaid[gsgP.wornGid "|" gsgP.gid] := 1
		GearLog("the worn " gsgP.slot " (" gsgP.wornName ") is in an Equipment Set - after you put on " gsgP.name ", re-save that set in the game, else its Ctrl+N puts the old one back (gearsets:1 plans it without asking; the bot never saves a set)")
		gsgKind .= "|" gsgP.wornGid ":" gsgP.gid
		gsgText .= (gsgText = "" ? "" : " ") "A better " gsgP.slot " is in the backpack: " gsgP.name " (" GearDeltaText(gsgP) " - advice); your worn one, " gsgP.wornName ", is in an Equipment Set."
		}
	if (gsgKind != "")
		AlertSend("gear" gsgKind, "re-save an Equipment Set", gsgText " After you swap, re-save that set in the game, or its Ctrl+N puts the old piece back.")
	}

;---- Quick sell (QuickSell.ahk QsLook) ----

;gearswap on, a full backpack about to be quick sold: "" it may be sold (every gear piece in the backpack judged, none better
;than what's worn - a dungeon's hold dropped by QsLook then: the pass looked through its drops - unless a deck, a pet or an
;item of a kind not read is in it: never judged here, the hold stays), else why not: a better
;piece (put it on yourself - a rehearsal equips nothing), pieces not judged, the gear not read. The pass at most once a
;minute while the backpack's count is the same (QsLook looks three times after every battle)
GearSellOk(why)
	{
	static gsoAt := 0, gsoKey := "", gsoWhy := ""
	gsoNow := IsObject(QsLastBag) ? QsLastBag.items "" : ""
	if (gsoAt && A_TickCount - gsoAt < 60000 && gsoKey = gsoNow)
		return gsoWhy
	gsoG := GearPass("the backpack is full - before quick selling it (" why ")")
	gsoAt := A_TickCount, gsoKey := gsoNow
	if (!IsObject(gsoG))
		gsoWhy := "the gear couldn't be compared (" NavGearWhy ") - selling waits for the gear pass (Settings: gearswap)"
	else if (gsoG.better)
		gsoWhy := gsoG.better " piece" (gsoG.better = 1 ? "" : "s") " in the backpack better than what's worn (" GearPlanText(gsoG) ") - put them on yourself (the gear pass is a rehearsal: nothing is equipped), then it's sold"
	else if (gsoG.unknown)
		gsoWhy := gsoG.unknown " gear piece" (gsoG.unknown = 1 ? "" : "s") " couldn't be judged (" GearUnknownText(gsoG) ") - not sold till they are (or switch gearswap off)"
	else
		gsoWhy := ""
	return gsoWhy
	}

;---- Dungeon runs (Dungeons.ahk) ----

;A dungeon run started (gearswap on): the backpack's items noted - the next GearRunEnd's new pieces are its drops.
;r.gearMarked 1 when noted (GearRunEnd sets it too, its end's backpack noted for the next run). Not noted - the mark failed,
;or gearswap was off at the start and switched on midway: the first GearRunEnd says nomark=1 and its drops aren't counted -
;the drop log's .state still holds an older run's backpack (days old, maybe): all picked up since would count as its drops
GearRunMark(r)
	{
	r.gearMarked := 0
	if (!GearMode())
		return ""
	grmG := NavGear(GearQuery("&run=" NavUri(r.name) "&mark=1"))
	if (!IsObject(grmG) || !IsObject(grmG.run))
		{
		GearLog("the run '" r.name "' started - the backpack not noted (" (IsObject(grmG) ? "no run line" : NavGearWhy) "): its first run's drops won't be counted (the next run's are)")
		return ""
		}
	r.gearMarked := 1
	GearLog("the run '" r.name "' started - the backpack's " grmG.bagItems " items noted (its drops are the new ones)")
	return grmG
	}

;A dungeon run done, back at its start outside (Dungeons.ahk DgBetweenRuns; gearswap on): this run's new pieces logged
;(learned\drops\<run>.txt), the plan logged, the Equipment Set guard, whether its gear is all swapped (run.done, run.why -
;every slot it drops worn with its own drop, or stopafter runs with no upgrade). The reading - "" off or not read
GearRunEnd(r)
	{
	global GearLast ; (v1 globals it sets)
	if (!GearMode())
		return ""
	;(nomark=1: this run's start wasn't noted (GearRunMark) - the .state's backpack is an older run's, not taken for this one's)
	greQ := "&run=" NavUri(r.name) "&end=1" (r.slots != "" ? "&slots=" NavUri(r.slots) : "") (r.stopafter != "" ? "&stopafter=" r.stopafter : "")
		. (r.gearMarked ? "" : "&nomark=1")
	greG := NavGear(GearQuery(greQ))
	if (!IsObject(greG))
		{
		GearLog("after run " r.runs " of '" r.name "': its drops not looked at - " NavGearWhy)
		return ""
		}
	GearLast := greG
	if (IsObject(greG.run))
		{
		;(the backpack noted at this end: the next run's start)
		r.gearMarked := 1
		greD := ""
		;(a drop's count by brackets: .count is the Map's own Count - its number of keys, V1Compat.ahk)
		for greI, greP in greG.drops
			greD .= (greD = "" ? "" : ", ") (greP.display != "" ? greP.display : greP.name) " (" greP.slot (V1Gt(V1At(greP, "count"), 1) ? ", " V1At(greP, "count") " so far" : ", new") ")"
		GearLog("'" r.name "' run " greG.run.runs ": " (greG.run.new ? greG.run.new " new piece" (greG.run.new = 1 ? "" : "s") ": " greD : "no new gear")
			. (greG.run.marked ? "" : " (no backpack noted at its start: not counted this time)") " - " (greG.run.done ? "its gear is all swapped: " : "") greG.run.why)
		}
	GearReport(greG, "after run " r.runs " of '" r.name "'", true)
	GearSetGuard(greG)
	return greG
	}

;(v2 port, CONVENTIONS.md "Blank start": this file's globals start blank - the entry script calls this first thing)
GearBlank()
	{
	global GearSaidAt := "", GearLast := "", GearTipped := "", GearSetSaid := "", GearTwoSaid := ""
	}
