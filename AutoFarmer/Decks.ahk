; Decks.ahk - decks (v0.47.0, TODO goal 3, asked 2026-10-23/24): a "small" deck for weak collect mobs, a "large" one for
; bosses, and as many more as you like. Each is a set of settings that override yours while it's the deck in use - how
; it plays (card logic, blades, traps, healing, pips, discards, which hits and heals it plays) - with what it's used for
; (anything else, collect goals, bosses, dungeon runs, farming), the school it's for, and the game's Equipment Set
; (Ctrl+1..9) that puts its in-game deck on. The bot picks one before each fight from what's ahead (DeckPick) and presses
; that set's key out of battle (DeckEquip). No decks - or decks that set nothing - and it plays exactly as without.
; A boss is known before the fight from the game's memory (2026-10-25, "it doesn't change decks for the bosses" - Alt+1 only
; names it inside the battle, too late for the in-game deck): the zone's mobs' titles, ranks and health (the helper's
; /mobs, READ-ONLY - vision\bossmem.py) - a boss the quest's goal names, the walker goes to or the dungeon run's way leads
; to is "a boss ahead" (DeckBossLook), and the boss deck goes on before the fight (an Elite only when it takes 3 or more
; of your best hits); in the battle its enemies from the memory (/battle) - the boss deck's settings without Alt+1 (a
; boss ahead held: while its in-game deck is the one on). One only passed by isn't: the walker routes round it, and one
; walked into is found in the battle.
; One file per deck: decks\<id>.txt - yours (updates keep them). The dashboard's Cards tab shows and edits them
; (Dashboard.ahk). AutoHotkey v1.1, #Included by Autofarmer.ahk.

;The decks ([{id, file, name, school, eqset, when: {default, collect, boss, dungeon, farm}, priority, vals: {key: value}}]),
;the one in use ("" none - your Settings as they are) and why, read again soon (an edit on the tab), when an Equipment Set
;was last pressed, the battle it was picked for, the Cards tab's view (0 the hand, else a deck's number in DeckList)
global DeckList, DeckNow, DeckWhy, DeckDirty, DeckEqAt, DeckDuel, DeckView
;A boss ahead, out of battle, from the game's memory (DeckBossLook): {key (its gid, else its name), name, gid, title,
;rank, health, school, kind (boss, elite), text ("Governor Nereus, rank 9 boss"), why (the quest's goal names it, ...),
;order, dist, since, seenAt (last found ahead - or the end of a battle it wasn't in), battlesAt (the battle count then),
;battled (a battle seen while it was on), inBattle (1 the boss was in that battle by the game's memory, 0 not, "" not
;known), over (that battle over: let go at the next look unless it's still ahead), misses (the zone's mobs not read, in
;a row)} - "" none. A battle's boss ({name, kind, text, max, gid, from: memory - the
;battle's enemies read, walk - the boss ahead}, "" none), the rounds it's been looked for, 1 once the memory answered.
;Declared only (a top-level := never runs in an #Included file)
global DeckBoss, DeckFoe, DeckFoeTries, DeckFoeKnown
;The deck being edited on the Cards tab (a copy - saved to its file by Save), the hand's pictures wanted (Dashboard.ahk
;DashCardShow), and the tab's controls (a control's variable has to be global)
global DeckEdit, DashCardWant
global DeckView0, DeckView1, DeckView2, DeckView3, DeckView4, DeckView5, DeckView6, DeckAddBtn
global DeckFNameT, DeckFName, DeckFSchoolT, DeckFSchool, DeckFSetT, DeckFSet, DeckFSetN, DeckFWhenT, DeckFWDefault, DeckFWCollect
global DeckFWBoss, DeckFWDungeon, DeckFWFarm, DeckFPriT, DeckFPri, DeckFPin, DeckFSave, DeckFCopy, DeckFDel, DeckFDmg, DeckFList
global DeckFValT, DeckFVal, DeckFValSet, DeckFValClear, DeckFNote

;Where the decks are kept
DeckDir()
	{
	return A_ScriptDir "\decks"
	}

;What a deck may set: these Settings (Settings.ahk CfgList - how it plays) and which slots it plays
DeckKeys()
	{
	static keys := ""
	if (!IsObject(keys))
		{
		keys := []
		for i, k in ["cardlogic", "boostmax", "useblades", "usetraps", "usebubble", "useaura", "usewand", "usetower"
			, "usereshuffle", "reboost", "solotraps", "healthocr", "killmargin", "drawenchant", "pipsave", "discardunused"
			, "discardmax", "discardunaffordable", "healat", "defendat", "fleeon", "usehit1", "usehit2", "usehit3", "usehit4", "useheal"]
			keys.Push(k)
		}
	return keys
	}

;A deck setting's {label, kind, lo, hi, def, picks} - from the Settings window's list, or the deck's own (which slots)
DeckKeyInfo(key)
	{
	static own := ""
	if (!IsObject(own))
		own := {usehit1: "Plays hit1", usehit2: "Plays hit2", usehit3: "Plays hit3", usehit4: "Plays hit4", useheal: "Plays its heals (heal1, heal2)"}
	if (own.HasKey(key))
		return {key: key, label: own[key], kind: "check", def: 1}
	if (IsFunc("CfgList"))
		for i, s in Func("CfgList").Call()
			if (s.key = key)
				return s
	return {key: key, label: key, kind: "num", def: 0}
	}

;The decks read from the folder (DeckList) - the two to start with made if there are none
DeckLoadAll()
	{
	FileCreateDir, % DeckDir()
	list := []
	Loop, Files, % DeckDir() "\*.txt"
		{
		d := DeckLoad(A_LoopFileFullPath)
		if (IsObject(d))
			list.Push(d)
		}
	if (!list.Length())
		{
		for i, s in [["small", "Small deck", "default,collect"], ["large", "Large deck", "boss"]]
			{
			d := {id: s[1], file: DeckDir() "\" s[1] ".txt", name: s[2], school: "any", eqset: 0, when: DeckWhenOf(s[3]), priority: 0, vals: {}}
			DeckSave(d)
			list.Push(d)
			}
		DebugLog("Decks: made Small deck (used for collect goals and anything else) and Large deck (bosses) - they set nothing yet: set them on the Cards tab")
		}
	;(in a set order: Small, Large, then the others as they were made - a new deck's id is when; the files come
	;alphabetically, which put a new deck1 before both)
	order := []
	for i, id in ["small", "large"]
		for j, d in list
			if (d.id = id)
				order.Push(d)
	for j, d in list
		if (d.id != "small" && d.id != "large")
			{
			at := order.Length() + 1
			Loop, % order.Length()
				if (order[A_Index].id != "small" && order[A_Index].id != "large" && d.id < order[A_Index].id)
					{
					at := A_Index
					break
					}
			order.InsertAt(at, d)
			}
	DeckList := order
	;(the Cards tab's buttons named after them; the Dungeons tab's Deck box)
	if (DashHwnd)
		DeckButtonsShow()
	if (DashHwnd && IsFunc("DgDeckShow"))
		Func("DgDeckShow").Call()
	;(the one in use, read afresh - or none if it's gone; not in a battle: the round goes on as it was planned, the edit
	;from the next battle - DeckTick picks afresh out of battle)
	if (IsObject(DeckNow) && inbattle != 1)
		{
		d := DeckById(DeckNow.id)
		DeckNow := IsObject(d) ? d : ""
		}
	return order
	}

;Deck id's place in DeckList (0 not there)
DeckIndexOf(id)
	{
	for i, d in IsObject(DeckList) ? DeckList : []
		if (d.id = id)
			return i
	return 0
	}

;{default: 1, collect: 1, ...} of a comma list
DeckWhenOf(text)
	{
	w := {}
	Loop, Parse, text, `,, %A_Space%
		if (RegExMatch(A_LoopField, "^(default|collect|boss|dungeon|farm)$"))
			w[A_LoopField] := 1
	return w
	}

;One deck's file read ("" if it isn't one): field|value lines, then key:value settings - only those a deck may set
DeckLoad(file)
	{
	SplitPath, file, , , , id
	d := {id: id, file: file, name: id, school: "any", eqset: 0, when: {}, priority: 0, vals: {}}
	allowed := {}
	for i, k in DeckKeys()
		allowed[k] := 1
	dropped := ""
	Loop, Read, %file%
		{
		line := Trim(RegExReplace(A_LoopReadLine, "\s;.*$"))
		if (line = "" || SubStr(line, 1, 1) = ";")
			continue
		if (RegExMatch(line, "^(\w+)\|(.*)$", m))
			{
			if (m1 = "name")
				d.name := Trim(SubStr(RegExReplace(m2, "[^\x20-\x7E]|\|", ""), 1, 30))
			else if (m1 = "school")
				d.school := RegExMatch(Trim(m2), "i)^(storm|fire|myth|balance|ice|life|death)$") ? Format("{:L}", Trim(m2)) : "any"
			else if (m1 = "eqset")
				d.eqset := RegExMatch(Trim(m2), "^[0-9]$") ? Trim(m2) + 0 : 0
			else if (m1 = "when")
				d.when := DeckWhenOf(m2)
			else if (m1 = "priority")
				d.priority := RegExMatch(Trim(m2), "^-?\d{1,3}$") ? Trim(m2) + 0 : 0
			continue
			}
		if (RegExMatch(line, "^([\w.]+)\s*:\s*(-?\d+(?:\.\d+)?)\s*\x25?$", m))
			{
			StringLower, k, m1
			if (allowed.HasKey(k))
				d.vals[k] := m2 + 0
			else
				dropped .= (dropped = "" ? "" : ", ") k
			}
		}
	if (dropped != "")
		DebugLog("Decks: " d.name " (" file "): not a deck's setting, left out - " dropped)
	if (d.name = "")
		d.name := id
	return d
	}

;One deck written back to its file
DeckSave(d)
	{
	w := ""
	for k, v in d.when
		w .= (w = "" ? "" : ",") k
	text := "; Wiz-Maxxing deck (the dashboard's Cards tab). A setting not here: your Settings' (your school's, then the plain one)`r`n"
		. "name|" d.name "`r`nschool|" d.school "`r`neqset|" d.eqset "`r`nwhen|" w "`r`npriority|" d.priority "`r`n"
	for i, k in DeckKeys()
		if (d.vals.HasKey(k))
			text .= k ":" d.vals[k] "`r`n"
	FileCreateDir, % DeckDir()
	f := FileOpen(d.file ".tmp", "w", "UTF-8-RAW")
	if (!IsObject(f))
		return false
	f.Write(text)
	f.Close()
	FileMove, % d.file ".tmp", % d.file, 1
	return !ErrorLevel
	}

DeckById(id)
	{
	if (id = "" || !IsObject(DeckList))
		return ""
	for i, d in DeckList
		if (d.id = id)
			return d
	return ""
	}

;The deck to use now and why ({deck: d or "", why, boss: 1 when it's for a boss - DeckEquip puts it on sooner}): only
;decks for this wizard's school (or any) - the one fought as in a battle, else the one this character fought as before.
;First match wins: the dungeon run's deck, the one pinned on the Cards tab, the boss's (in a battle: your Alt+1 pick, or
;a boss among its enemies by the game's memory - or, that not read, the boss ahead it was walked into - or a boss ahead
;still held, its deck's Equipment Set the one on in the game: a fight on the way to it plays the cards that are in hand;
;out of battle, the bot on: a boss ahead - DeckBossLook), a collect goal's, farming's (loop or lore mode), a dungeon
;run's, anything else's - none: your Settings as they are. Of several for the same, the highest priority. noBoss: as if
;there were no boss (the deck an Elite is measured against - DeckBestHit)
DeckPick(inBattle, noBoss := false)
	{
	if (!IsObject(DeckList) || !DeckList.Length())
		return {deck: "", why: "no decks"}
	sch := inBattle && hitschool != "" ? hitschool : IsFunc("StatsSchoolOf") ? Func("StatsSchoolOf").Call(Func("StatsCharID").Call()) : ""
	if (IsObject(DgRun) && DgRun.deck != "")
		{
		d := DeckById(DgRun.deck)
		if (IsObject(d))
			return {deck: d, why: "the dungeon run " DgRun.name "'s"}
		}
	IniRead, pin, %A_ScriptDir%\dashboard.ini, decks, pin, %A_Space%
	if (pin != "")
		{
		d := DeckById(pin)
		if (IsObject(d) && DeckFits(d, sch))
			return {deck: d, why: "pinned on the Cards tab"}
		}
	;(the boss's: your Alt+1 pick; in a battle a boss among its enemies - DeckFoe, DeckRound - or the boss ahead held,
	;while its deck is the one on in the game; out of battle a boss ahead)
	bossWhy := "", bossHeld := 0
	if (!noBoss && inBattle && BossChoosen)
		bossWhy := "a boss (your " HkText("boss") " pick)"
	else if (!noBoss && inBattle && IsObject(DeckFoe))
		bossWhy := (DeckFoe.from = "memory" ? "a boss in this battle: " : "a boss ahead: ") DeckFoe.text
	else if (!noBoss && inBattle && BotOn && IsObject(DeckBoss))
		bossWhy := "a boss ahead: " DeckBoss.text " (its deck is on)", bossHeld := 1
	else if (!noBoss && !inBattle && BotOn && IsObject(DeckBoss))
		bossWhy := "a boss ahead: " DeckBoss.text
	for i, use in [["boss", bossWhy != "", bossWhy]
		, ["collect", IsObject(WkCollect) && !WkCollect.gaveUp, "a collect goal"]
		, ["farm", loopmode || loremode, "farming"]
		, ["dungeon", IsObject(DgRun), "a dungeon run"]
		, ["default", 1, "anything else"]]
		{
		if (!use[2])
			continue
		best := ""
		for j, d in DeckList
			if (d.when[use[1]] && DeckFits(d, sch) && (!IsObject(best) || d.priority > best.priority))
				best := d
		;(a boss ahead held in a battle it isn't in: its deck's settings only while its in-game deck is on - the set put
		;on last, DeckEquip's; another set on: the deck for what this battle is)
		if (use[1] = "boss" && bossHeld && IsObject(best))
			{
			;(no Equipment Set: it puts no cards on - the deck for what this battle is)
			if (!best.eqset)
				continue
			IniRead, onSet, %A_ScriptDir%\dashboard.ini, decks, % "eqset" (IsFunc("StatsCharID") ? Func("StatsCharID").Call() : ""), %A_Space%
			if (onSet != "" && onSet != best.eqset)
				continue
			}
		if (IsObject(best))
			return {deck: best, why: use[3], boss: use[1] = "boss" ? 1 : 0}
		}
	return {deck: "", why: "no deck for this"}
	}

;A deck is for this wizard: its school, or any (school not known: only an 'any' one)
DeckFits(d, sch)
	{
	return d.school = "any" || (sch != "" && d.school = sch)
	}

;The deck in use set (said in the log and on the dashboard when it changes)
DeckSet(d, why)
	{
	if ((IsObject(d) ? d.id : "") = (IsObject(DeckNow) ? DeckNow.id : ""))
		{
		;(the same deck for another reason - a boss ahead now in the battle: the dashboard's line says so, not the log)
		if (why != DeckWhy && IsObject(DashSees))
			DashSees.deck := IsObject(d) ? d.name " (" why ")" : "-"
		DeckNow := d, DeckWhy := why
		return false
		}
	DeckNow := d, DeckWhy := why
	n := 0
	if (IsObject(d))
		for k, v in d.vals
			n += 1
	DebugLog("Deck: " (IsObject(d) ? d.name " (" why ")" (n ? " - " n " setting" (n = 1 ? "" : "s") " of its own" : " - it sets nothing: your Settings") : "none - your Settings as they are (" why ")"))
	if (IsObject(DashSees))
		DashSees.deck := IsObject(d) ? d.name " (" why ")" : "-"
	return true
	}

;Out of battle, every 2 s (the main loop): the decks read again after an edit, a boss ahead looked for (the game's
;memory - DeckBossLook), the deck for what's ahead picked, and its Equipment Set put on (a boss's sooner)
DeckTick()
	{
	static lookAt := 0
	if (lookAt && A_TickCount - lookAt < 2000)
		return
	lookAt := A_TickCount
	if (!IsObject(DeckList) || DeckDirty)
		DeckDirty := 0, DeckLoadAll()
	DeckBossLook()
	p := DeckPick(false)
	DeckSet(p.deck, p.why)
	if (IsObject(p.deck))
		DeckEquip(p.deck, p.boss)
	}

;A battle round (once the school's known): a new battle - its deck picked; your Alt+1 boss pick - the boss's, if there's
;one; the battle's enemies from the game's memory (the helper's /battle - DeckFoeLook: a boss among them, the boss deck's
;settings without Alt+1; looked for in its first 3 rounds till the memory answers - not read: the boss ahead it was
;walked into). The in-game deck can't change in a battle: its settings only. A battle is told by its duel in the game's
;log (BlDuel), else by the battle count (constant within a battle) - not every round a new one
DeckRound()
	{
	if (!IsObject(DeckList))
		DeckLoadAll()
	drKey := BlDuel != "" ? BlDuel : "#" battles
	drNew := drKey != DeckDuel
	if (drNew)
		DeckFoe := "", DeckFoeTries := 0, DeckFoeKnown := 0
	;(an Equipment Set pressed just before this battle - maybe in its start, which the game doesn't take: not kept as
	;the one on, so it's pressed again after the fight rather than skipped for 15 minutes. The spellbook - it only shows
	;out of battle - not seen half a second or more after the set was pressed (the main loop looks for it right after
	;DeckTick): pressed at the battle's start or under a dialog, maybe not taken)
	if (drNew && DeckEqAt && BookSeenAt < DeckEqAt + 500)
		{
		drWho := IsFunc("StatsCharID") ? Func("StatsCharID").Call() : ""
		IniDelete, %A_ScriptDir%\dashboard.ini, decks, eqset%drWho%
		}
	drFoe := 0
	if (!DeckFoeKnown && DeckFoeTries < 3 && DeckBossWanted())
		{
		DeckFoeTries += 1
		drWas := IsObject(DeckFoe) ? DeckFoe.from "|" DeckFoe.name : ""
		DeckFoeLook()
		drFoe := drWas != (IsObject(DeckFoe) ? DeckFoe.from "|" DeckFoe.name : "")
		}
	if (!drNew && !drFoe && !(BossChoosen && !(IsObject(DeckNow) && DeckNow.when.boss)))
		return
	DeckDuel := drKey
	p := DeckPick(true)
	DeckSet(p.deck, p.why)
	}

;The deck's in-game deck put on - its Equipment Set's key (Ctrl+1..9 - the game's own; also its gear, pet and mount, as
;you set the set up), out of battle only, with nothing loading, Wizard101 in front and you away from the keys and mouse
;(as long as "Wait while I play" waits - handsoff, 3 s at least; Play for me: never waited for), once a minute at most (the
;game says "Slow down!" past 10 changes in 2 minutes) - soon (a boss ahead: its fight is coming) 10 s after the last; the
;set put on last kept by character (dashboard.ini [decks] eqset<CharID>) and pressed again after 15 minutes (a press the
;game didn't take - a dialog up, a battle starting)
DeckEquip(d, soon := false)
	{
	static at := {}
	secs := Stats.HasKey("handsoff") ? Stats["handsoff"] : 3
	if (!d.eqset || !BotOn || inbattle = 1 || WkLoading || (IsFunc("BattleLogInBattle") && Func("BattleLogInBattle").Call())
		|| !GameActive() || UserIdle() < Max(3, secs) * 1000 || (DeckEqAt && A_TickCount - DeckEqAt < (soon ? 10000 : 60000)))
		return false
	who := IsFunc("StatsCharID") ? Func("StatsCharID").Call() : ""
	IniRead, was, %A_ScriptDir%\dashboard.ini, decks, eqset%who%, %A_Space%
	if (was = d.eqset && at.HasKey(who) && A_TickCount - at[who] < 900000)
		return false
	at[who] := A_TickCount
	DeckEqAt := A_TickCount
	if (KeysDown || HeldW)
		ReleaseKeys()
	Sleep, 150
	key := d.eqset
	Send, {Blind}^%key%
	IniWrite, % d.eqset, %A_ScriptDir%\dashboard.ini, decks, eqset%who%
	DebugLog("Deck: " d.name "'s in-game deck put on - Equipment Set " d.eqset " (Ctrl+" d.eqset ")" (was = d.eqset ? " again" : ""))
	Sleep, 400
	return true
	}

;The hit, heal and wand slots the deck in use doesn't play, taken out of this round's hand (after the slots were looked for)
DeckFilterHand()
	{
	if (!IsObject(DeckNow))
		return
	v := DeckNow.vals
	if (v.HasKey("usehit1") && !v.usehit1)
		hit1 := 0
	if (v.HasKey("usehit2") && !v.usehit2)
		hit2 := 0
	if (v.HasKey("usehit3") && !v.usehit3)
		hit3 := 0
	if (v.HasKey("usehit4") && !v.usehit4)
		hit4 := 0
	if (v.HasKey("useheal") && !v.useheal)
		heal1 := 0, heal2 := 0
	if (v.HasKey("usewand") && !v.usewand)
		wand := 0
	}

;A setting as deck d has it for school sch: its own, else your school's, else the plain one (0 none)
DeckStatFor(d, sch, key)
	{
	if (IsObject(d) && d.vals.HasKey(key))
		return d.vals[key]
	if (sch != "" && Stats.HasKey(sch "." key))
		return Stats[sch "." key]
	return Stats.HasKey(key) ? Stats[key] : 0
	}

;What a hit of deck d can deal, as a range (you asked 2026-10-24): {lo, hi, hiNoCrit, loName, hiName, boosts, guess, none,
;crit, damage}. lo: its weakest hit at the low end of its range with nothing on it and no critical; hi: its strongest at
;the top of its range with every blade, trap, aura and bubble the deck plays on it (each once) and a critical (x2 - its
;most, against no block: CritMult). Both with the wizard's own damage % for that school (StatsReader: <school>.damage,
;else damage - the game's curve: DamageMultiplier) - not the enemies' resist, your pierce or an enchant (a boss's: the
;fight's own numbers). The hits: hit1-4 of its school that it plays (their least damage in your Settings; the top of
;the range from the card learned into that slot, else its least: guess) and the learned hits in no slot (learnedhits).
;none: no hit known for it
DeckDamage(d)
	{
	sch := (IsObject(d) && d.school != "any") ? d.school : IsFunc("StatsSchoolOf") ? Func("StatsSchoolOf").Call(Func("StatsCharID").Call()) : ""
	out := {lo: "", hi: "", loName: "", hiName: "", boosts: "", guess: false, none: true, school: sch}
	if (sch = "")
		return out
	hits := []
	;(the slots' hits it plays)
	for i, slot in ["hit1", "hit2", "hit3", "hit4"]
		{
		if (!DeckStatFor(d, sch, "use" slot) && (IsObject(d) && d.vals.HasKey("use" slot)))
			continue
		lo := Stats.HasKey(sch "." slot) ? Stats[sch "." slot] : 0
		;(none: its heads typed one line a head - balance.hit3fire, .hit3ice, .hit3storm for a Hydra - added up, as the kill
		;check counts them: KillCalc.ahk HitHeadsFind)
		if (lo <= 0)
			for ddI, ddS in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
				lo += Stats.HasKey(sch "." slot ddS) ? Stats[sch "." slot ddS] : 0
		if (lo <= 0)
			continue
		hi := DeckSlotHigh(sch, slot)
		name := IsFunc("DashShortName") ? Func("DashShortName").Call(slot, sch) : slot
		;(an X-pip hit - its pips 0: its number a pip's - 1 pip at the least, 14 at the most: 7 power pips)
		if (Stats.HasKey(sch "." slot "pips") && Stats[sch "." slot "pips"] = 0 && slot != "wand")
			hits.Push({lo: lo, hi: (hi != "" ? hi : lo) * 14, guess: hi = "", name: name " (X pips)"})
		else
			hits.Push({lo: lo, hi: hi != "" ? hi : lo, guess: hi = "", name: name})
		}
	;(learned hits in no slot, when it casts them: learnedhits)
	if (DeckStatFor(d, sch, "learnedhits") != 0 && IsObject(LearnedCards))
		for i, c in LearnedCards
			if ((c.type = "damage" || c.type = "aoe") && c.sch = sch && c.slot = "" && !LearnHasFlag(c, "skip"))
				{
				lo := IsFunc("LearnHitBase") ? Func("LearnHitBase").Call(c) : c.value
				if (lo = "" || lo <= 0)
					continue
				hi := DeckRangeTop(c.text)
				hi := hi != "" && hi >= lo ? hi : lo
				xp := LearnHasFlag(c, "xpip")
				hits.Push({lo: lo, hi: xp ? hi * 14 : hi, guess: hi = lo, name: (c.name != "" ? c.name : "a learned hit") (xp ? " (X pips)" : "")})
				}
	if (!hits.Length())
		return out
	dmgPct := Stats.HasKey(sch ".damage") ? Stats[sch ".damage"] : Stats.HasKey("damage") ? Stats.damage : 0
	critR := Stats.HasKey(sch ".critical") ? Stats[sch ".critical"] : Stats.HasKey("critical") ? Stats.critical : 0
	mult := IsFunc("DamageMultiplier") ? Func("DamageMultiplier").Call(dmgPct) : 1
	weak := "", strong := ""
	for i, h in hits
		{
		if (!IsObject(weak) || h.lo < weak.lo)
			weak := h
		if (!IsObject(strong) || h.hi > strong.hi)
			strong := h
		}
	;(every boost it plays, once each)
	;(the second blade and trap the school's: Elemental for fire, ice and storm, Spirit for life, death and myth - none
	;for balance. Balance's own blade and trap are Balanceblade and Hex - blade3, trap3: counted once, as the kill check
	;does - KillCalc.ahk BoostKey)
	boost := 1, names := ""
	grp := IsFunc("SchoolGroup") ? Func("SchoolGroup").Call(sch) : ""
	b2 := grp = "elemental" ? "elementalblade" : grp = "spirit" ? "spiritblade" : ""
	t2 := grp = "elemental" ? "elementaltrap" : grp = "spirit" ? "spirittrap" : ""
	ddB := (sch = "balance") ? [b2, "blade3", "blade4"] : ["blade", b2, "blade3", "blade4"]
	ddT := (sch = "balance") ? [t2, "trap3", "trap4", "feint"] : ["trap", t2, "trap3", "trap4", "feint"]
	for i, b in [["useblades", ddB], ["usetraps", ddT], ["useaura", ["aura"]], ["usebubble", ["bubble"]]]
		{
		if (!DeckStatFor(d, sch, b[1]))
			continue
		for j, k in b[2]
			{
			pct := k != "" ? DeckStatFor(d, sch, k) : 0
			if (pct > 0)
				boost *= 1 + pct / 100, names .= (names = "" ? "" : ", ") k " " pct "%"
			}
		}
	out.lo := Floor(weak.lo * mult), out.hiNoCrit := Floor(strong.hi * mult * boost)
	out.hi := Floor(out.hiNoCrit * (critR > 0 ? CritMult(critR, 0) : 1))
	out.loName := weak.name, out.hiName := strong.name, out.boosts := names, out.guess := strong.guess, out.none := false
	out.crit := critR, out.damage := dmgPct
	return out
	}

;A critical's damage multiplier for your critical rating crit against an enemy's block rating block (PvE): 2 - 3B / (C +
;3B) - x2 against no block, x1.7 for 630 against 90. The community's model (multicalculators.com, Oct 2026 - KingsIsle
;doesn't publish it; checked against its worked example)
CritMult(crit, block)
	{
	if (crit <= 0)
		return 1
	return 2 - 3 * block / (crit + 3 * block)
	}

;The chance (0-1) your hit is a critical against block rating block (PvE): 3 L C / (3 C + B), L your level / 100 (at most
;1) - the same model as CritMult
CritChance(crit, block, level := 100)
	{
	if (crit <= 0)
		return 0
	lf := level > 0 ? Min(1, level / 100) : 1
	return Min(1, 3 * lf * crit / (3 * crit + block))
	}

;The top of a slot's hit's damage range: from the card learned into that slot (learned\cards.txt) - "" not known
DeckSlotHigh(sch, slot)
	{
	if (!IsObject(LearnedCards))
		return ""
	for i, c in LearnedCards
		if (c.slot = sch "\" slot)
			return DeckRangeTop(c.text)
	return ""
	}

;The top of every head's damage range on a card's text, added up ("295-335" -> 335; a Hydra's three heads summed), up to
;its "over N rounds" part; "" none
DeckRangeTop(text)
	{
	at := RegExMatch(text, "i)over\s*\d|r[o0]unds?\b")
	head := at ? SubStr(text, 1, at - 1) : text
	sum := 0, n := 0, p := 1
	while (p := RegExMatch(head, "O)(\d+)\s*-\s*(\d+)", m, p))
		{
		if (m.Value(2) + 0 >= m.Value(1) + 0)
			sum += m.Value(2) + 0, n += 1
		p += StrLen(m.Value(0))
		}
	return n ? sum : ""
	}

;The range in words, for the Cards tab
DeckDamageText(d)
	{
	r := DeckDamage(d)
	if (r.school = "")
		return "Damage: not known yet - the bot hasn't seen which school this wizard fights as"
	if (r.none)
		return "Damage: no " r.school " hit known for this deck - it would only boost and pass"
	return "Damage a hit (" r.school ", your damage " r.damage "%, critical " r.crit "): " r.lo " (" r.loName ", nothing on it, no critical) to " r.hi
		. (r.guess ? "+" : "") " (" r.hiName " at its best" (r.boosts != "" ? ", with " r.boosts : "") (r.crit > 0 ? ", a critical x2 - " r.hiNoCrit " without" : "") ")"
		. (r.guess ? " - its range's top isn't known: its least used" : "")
	}

;---- A boss ahead: the boss deck before the fight (the game's memory - read-only) ----
;
;Alt+1 names the boss inside the battle - too late for the in-game deck. The helper's /mobs (NavMobs in Vision.ahk, READ-
;ONLY: nothing in the game is written, injected or hooked) gives each of the zone's mobs its title as the game has it
;(Boss, Elite, Normal...), rank, max health and the game's own boss flag (vision\bossmem.py). A boss (or an Elite that
;takes 3 or more of your best hits) is "ahead" when the quest's goal names it, the walker goes to it (the helper's quest
;mob by its name or its goal - not one of the same family elsewhere in the zone) or the dungeon run's way leads to it -
;then the deck for bosses is picked and its Equipment Set pressed before the fight. One only passed by isn't (the walker
;routes round it; one walked into is found in the battle - DeckFoeLook). Kept till that battle's over, or 30 s after
;it's gone or far off - counted from the end of a battle it wasn't in (no switching back and forth); a missed reading
;changes nothing, but 60 in a row (2 minutes), the bot off or another zone let it go. Needs the bot on, out of battle,
;nothing loading, a deck for bosses, navmem on and the vision helper (no memory: your Alt+1 pick in the battle, as before)

;There's a deck for bosses (else there's nothing to look for)
DeckBossWanted()
	{
	for dbwI, dbwD in IsObject(DeckList) ? DeckList : []
		if (dbwD.when.boss)
			return true
	return false
	}

;Out of battle (DeckTick, every 2 s): the zone's mobs read (NavMobs) and a boss ahead looked for - DeckBoss set, kept or
;let go (see above)
DeckBossLook()
	{
	;(the zone from the game's log now: WkZoneAt and WkLoading up to date before the mobs are read)
	if (IsFunc("WalkZone"))
		Func("WalkZone").Call(true)
	;(the bot off, or another zone since it was last found ahead: let go - not kept for a fight it won't be in)
	if (IsObject(DeckBoss) && (!BotOn || (WkZoneAt && WkZoneAt > DeckBoss.seenAt)))
		{
		DebugLog("Deck: no boss ahead now - " DeckBoss.name (!BotOn ? " (the bot's off)" : " (another zone)"))
		DeckBoss := ""
		}
	if (!DeckBossWanted() || !BotOn || inbattle = 1 || WkLoading || !IsFunc("NavMobs"))
		return
	if (IsFunc("BattleLogInBattle") && Func("BattleLogInBattle").Call())
		return
	dblNow := A_TickCount
	;(a battle over while it was on - the boss's, or one the game's memory couldn't name: let go now unless it's still
	;ahead; one the memory says it wasn't in: kept, its 30 s from now - nothing was looked at in the battle)
	if (IsObject(DeckBoss) && (DeckBoss.battled || battles != DeckBoss.battlesAt))
		{
		if (DeckBoss.inBattle != 0)
			DeckBoss.over := 1
		DeckBoss.battled := 0, DeckBoss.battlesAt := battles, DeckBoss.inBattle := "", DeckBoss.seenAt := dblNow
		}
	dblGoal := (WkGoalLineAt && dblNow - WkGoalLineAt < 30000) ? WkGoalLine : ""
	dblMobs := Func("NavMobs").Call(dblGoal)
	;(not read - the helper busy, an ERR, navmem off: as it is - no switching on a missed reading; 60 in a row, about 2
	;minutes - the helper stopped for good: let go)
	if (!IsObject(dblMobs))
		{
		if (IsObject(DeckBoss))
			{
			DeckBoss.misses := (DeckBoss.misses ? DeckBoss.misses : 0) + 1
			if (DeckBoss.misses >= 60)
				{
				DebugLog("Deck: no boss ahead now - " DeckBoss.name " (the zone's mobs not read for 2 minutes: " NavMobsWhy ")")
				DeckBoss := ""
				}
			}
		return
		}
	if (IsObject(DeckBoss))
		DeckBoss.misses := 0
	dblHit := DeckBossFind(dblMobs, IsObject(DeckBoss) ? DeckBoss.key : "")
	if (IsObject(dblHit))
		{
		if (IsObject(DeckBoss) && DeckBoss.key = dblHit.key)
			{
			DeckBoss.seenAt := dblNow, DeckBoss.over := 0, DeckBoss.dist := dblHit.dist, DeckBoss.misses := 0
			if (DeckBoss.why != dblHit.why)
				DeckBoss.why := dblHit.why, DeckBoss.order := dblHit.order
			return
			}
		dblHit.since := dblNow, dblHit.seenAt := dblNow, dblHit.battlesAt := battles, dblHit.battled := 0, dblHit.inBattle := "", dblHit.over := 0, dblHit.misses := 0
		if (IsObject(DeckBoss))
			DebugLog("Deck: no boss ahead now - " DeckBoss.name " (another one is: " dblHit.name ")")
		DeckBoss := dblHit
		DebugLog("Deck: a boss ahead - " dblHit.text " (" (dblHit.health != "" ? dblHit.health " health" : "health not known") (dblHit.school != "" ? ", " dblHit.school : "")
			. (dblHit.dist != "" ? ", " Round(dblHit.dist) " away" : "") "): " dblHit.why " (the game's memory)")
		return
		}
	if (!IsObject(DeckBoss))
		return
	;(not ahead now: let go once that battle's over, else 30 s on - gone, or behind and far off)
	dblIn := DeckBossIn(dblMobs, DeckBoss)
	if (DeckBoss.over || dblNow - DeckBoss.seenAt >= 30000)
		{
		DebugLog("Deck: no boss ahead now - " DeckBoss.name (DeckBoss.over ? (dblIn ? " (its battle's over)" : " is gone (its battle's over)")
			: dblIn ? " is behind or far off (30 s)" : " is gone (30 s)"))
		DeckBoss := ""
		}
	}

;The boss ahead among the zone's mobs (NavMobs'), or "": a boss or a counted Elite (DeckMobKind) the quest's goal names
;(the walker's goal line - the game's memory's, else the screen's - read in the last 30 s), the helper's quest mob by
;its name or its goal (the walker goes to it - named: not 0; an older helper's, no named field: its quest flag alone),
;or one a dungeon run's way leads to (DeckDgAhead). Of several, the first of those reasons, a boss before an Elite, the
;one held already (holdKey: no swapping between two), then the nearest
DeckBossFind(dbfMobs, holdKey := "")
	{
	dbfGoal := (WkGoalLine != "" && WkGoalLineAt && A_TickCount - WkGoalLineAt < 30000) ? DeckLetters(WkGoalLine) : ""
	dbfBest := ""
	for dbfI, dbfM in dbfMobs
		{
		dbfNote := ""
		dbfKind := DeckMobKind(dbfM.boss, dbfM.title, dbfM.health, dbfNote)
		if (dbfKind = "")
			continue
		dbfKey := DeckLetters(dbfM.name)
		dbfWhy := "", dbfOrder := 0
		if (dbfGoal != "" && StrLen(dbfKey) >= 4 && InStr(dbfGoal, dbfKey))
			dbfWhy := "the quest's goal names it", dbfOrder := 4
		;(the helper's quest flag takes a same-family mob anywhere in the zone too - "Gobbler King" for "Defeat Gobblers":
		;named 0 is that, not the walker's)
		else if (dbfM.quest && dbfM.named != 0)
			dbfWhy := "the quest's mob (the walker goes to it)", dbfOrder := 3
		else if (IsObject(DgRun) && DeckDgAhead(dbfM))
			dbfWhy := "the dungeon run's way leads to it", dbfOrder := 2
		if (!dbfOrder)
			continue
		dbfId := dbfM.gid != "" ? dbfM.gid : dbfM.name
		dbfScore := dbfOrder * 10 + (dbfKind = "boss" ? 2 : 0) + (holdKey != "" && dbfId = holdKey ? 1 : 0)
		if (IsObject(dbfBest) && (dbfScore < dbfBest.score || (dbfScore = dbfBest.score && (dbfM.dist = "" || (dbfBest.dist != "" && dbfM.dist >= dbfBest.dist)))))
			continue
		dbfBest := {key: dbfId, name: dbfM.name, gid: dbfM.gid, title: dbfM.title, rank: dbfM.rank, health: dbfM.health, school: dbfM.school
			, kind: dbfKind, why: dbfWhy, order: dbfOrder, score: dbfScore, dist: dbfM.dist, x: dbfM.x, y: dbfM.y, text: DeckBossText(dbfM.name, dbfM.rank, dbfKind, dbfNote)}
		}
	return dbfBest
	}

;The boss b still among the zone's mobs (by its gid, else its name)
DeckBossIn(dbiMobs, dbiB)
	{
	for dbiI, dbiM in dbiMobs
		if ((dbiB.gid != "" && dbiM.gid = dbiB.gid) || (dbiB.gid = "" && dbiM.name = dbiB.name))
			return true
	return false
	}

;What a mob is for the decks: "boss" (the game's own boss flag, or its title Boss), "elite" (its title Elite and its max
;health takes 3 or more of your best hits - DeckBestHit: note says how many), else "" (an Elite under 3 hits, or your best
;hit not known: not counted)
DeckMobKind(dmkBoss, dmkTitle, dmkHealth, ByRef dmkNote := "")
	{
	dmkNote := ""
	if (dmkBoss = 1 || dmkTitle = "Boss")
		return "boss"
	if (dmkTitle != "Elite" || dmkHealth = "" || dmkHealth <= 0)
		return ""
	dmkBest := DeckBestHit()
	if (dmkBest = "" || dmkBest <= 0)
		return ""
	dmkHits := Ceil(dmkHealth / dmkBest)
	if (dmkHits < 3)
		return ""
	dmkNote := " (" dmkHealth " health - " dmkHits " of your best hits, " dmkBest ")"
	return "elite"
	}

;Your best hit, as the deck you'd fight it with deals it - the deck picked as if there were no boss (DeckPick noBoss):
;its strongest hit at its best with the boosts it plays, no critical (DeckDamage hiNoCrit) - "" not known. Kept 30 s
DeckBestHit()
	{
	static dbhAt := 0, dbhKeep := ""
	if (dbhAt && A_TickCount - dbhAt < 30000)
		return dbhKeep
	dbhAt := A_TickCount
	dbhP := DeckPick(inbattle = 1, true)
	dbhR := DeckDamage(dbhP.deck)
	dbhKeep := (dbhR.none || dbhR.hiNoCrit = "") ? "" : dbhR.hiNoCrit
	return dbhKeep
	}

;"Governor Nereus, rank 9 boss" (note: an Elite's hits)
DeckBossText(dbtName, dbtRank, dbtKind, dbtNote := "")
	{
	return (dbtName != "" ? dbtName : "an enemy") (dbtRank != "" ? ", rank " dbtRank : "") " " dbtKind dbtNote
	}

;Just the letters of a name, in capitals (the walker's WalkLetters when it's there - OCR's digit slips put right)
DeckLetters(dlText)
	{
	if (IsFunc("WalkLetters"))
		return Func("WalkLetters").Call(dlText)
	StringUpper, dlText, dlText
	return RegExReplace(dlText, "[^A-Z]")
	}

;The dungeon run's way leads to mob m: a step still to walk in the zone of the one walked to (the steps in a row there)
;within 1000 of it
DeckDgAhead(ddaM)
	{
	if (!IsObject(DgRun) || !IsObject(DgRun.steps) || ddaM.x = "" || ddaM.y = "")
		return false
	ddaI := DgRun.i >= 1 ? DgRun.i : 1
	if (ddaI > DgRun.steps.Length())
		return false
	ddaZone := DgRun.steps[ddaI].zone
	while (ddaI <= DgRun.steps.Length() && DgRun.steps[ddaI].zone = ddaZone)
		{
		ddaS := DgRun.steps[ddaI]
		if ((ddaS.x - ddaM.x) ** 2 + (ddaS.y - ddaM.y) ** 2 <= 1000000)
			return true
		ddaI += 1
		}
	return false
	}

;A battle round (DeckRound): the battle's enemies from the game's memory (NavBattle) - DeckFoe the boss among them (a boss
;first, then the Elite with the most health that counts - DeckMobKind), "" none; the boss ahead's place in it noted
;(DeckBoss.inBattle). Not read: the boss ahead it was walked into (DeckBoss), if any - DeckFoeKnown stays 0 (looked for
;again next round)
DeckFoeLook()
	{
	dflB := IsFunc("NavBattle") ? Func("NavBattle").Call() : ""
	if (!IsObject(dflB))
		{
		if (IsObject(DeckBoss))
			{
			DeckFoe := {name: DeckBoss.name, kind: DeckBoss.kind, text: DeckBoss.text, max: DeckBoss.health, gid: DeckBoss.gid, from: "walk"}
			DeckBoss.battled := 1
			}
		return false
		}
	dflBest := "", dflSaid := "", dflAll := 1
	for dflI, dflF in dflB.foes
		{
		;(a foe whose title isn't known yet - its mob not joined: an Elite can't be told - looked at again next round)
		if (dflF.title = "" && dflF.boss != 1)
			dflAll := 0
		dflSaid .= (dflSaid = "" ? "" : ", ") (dflF.name != "" ? dflF.name : "?") " (" (dflF.title != "" ? dflF.title : dflF.boss = 1 ? "boss" : "?")
			. (dflF.rank != "" ? " rank " dflF.rank : "") ", " dflF.health "/" dflF.max ")"
		dflNote := ""
		dflKind := DeckMobKind(dflF.boss, dflF.title, dflF.max, dflNote)
		if (dflKind = "")
			continue
		if (IsObject(dflBest) && (dflKind != dflBest.kind ? dflKind != "boss" : (dflF.max = "" || (dflBest.max != "" && dflF.max <= dflBest.max))))
			continue
		dflBest := {name: dflF.name, kind: dflKind, max: dflF.max, gid: dflF.gid, from: "memory", text: DeckBossText(dflF.name, dflF.rank, dflKind, dflNote)}
		}
	DeckFoe := dflBest
	;(known: a boss among them, or every one's title read - else looked at again next round, its first 3 at most)
	DeckFoeKnown := (IsObject(dflBest) && dflBest.kind = "boss") || (dflAll && dflB.foes.Length()) ? 1 : 0
	DebugLog("  Deck: the battle's enemies (the game's memory): " (dflSaid != "" ? dflSaid : "none read") (IsObject(dflBest) ? " - a " dflBest.kind ": " dflBest.name : "")
		. (DeckFoeKnown ? "" : " (not all known yet - looked at again next round)"))
	if (IsObject(DeckBoss))
		{
		dflIn := 0
		for dflI, dflF in dflB.foes
			if ((DeckBoss.gid != "" && dflF.gid = DeckBoss.gid) || (DeckBoss.gid = "" && dflF.name != "" && dflF.name = DeckBoss.name))
				dflIn := 1
		DeckBoss.inBattle := dflIn, DeckBoss.battled := 1
		}
	return true
	}

;---- The Cards tab's deck views (Dashboard.ahk makes the controls) ----

;The row's buttons named after the decks (at most 6 - "+ Deck" hidden then)
DeckButtonsShow()
	{
	if (!DashHwnd || !IsObject(DeckList))
		return
	Loop, 6
		{
		if (A_Index <= DeckList.Length())
			{
			GuiControl, Dash:Text, DeckView%A_Index%, % SubStr(DeckList[A_Index].name, 1, 14)
			GuiControl, Dash:Show, DeckView%A_Index%
			}
		else
			GuiControl, Dash:Hide, DeckView%A_Index%
		}
	GuiControl, % "Dash:" (DeckList.Length() >= 6 ? "Hide" : "Show"), DeckAddBtn
	}

DeckHandCtrls()
	{
	return ["DashHandHead", "DashLearnBtn", "DashFoeHead", "DashFoeList"]
	}

DeckFormCtrls()
	{
	return ["DeckFNameT", "DeckFName", "DeckFSchoolT", "DeckFSchool", "DeckFSetT", "DeckFSet", "DeckFSetN", "DeckFWhenT", "DeckFWDefault"
		, "DeckFWCollect", "DeckFWBoss", "DeckFWDungeon", "DeckFWFarm", "DeckFPriT", "DeckFPri", "DeckFPin", "DeckFSave", "DeckFCopy", "DeckFDel"
		, "DeckFDmg", "DeckFList", "DeckFValT", "DeckFVal", "DeckFValSet", "DeckFValClear", "DeckFNote"]
	}

;One of the Cards tab's views up: 0 the hand and the enemies, n the n-th deck (its form filled from a copy of it)
DeckViewShow(n)
	{
	if (!DashHwnd)
		return
	if (!IsObject(DeckList))
		DeckLoadAll()
	if (n > DeckList.Length())
		n := 0
	DeckView := n
	GuiControl, Dash:, DeckView%n%, 1
	for i, c in DeckHandCtrls()
		GuiControl, % "Dash:" (n ? "Hide" : "Show"), %c%
	Loop, 7
		{
		p := IsObject(DashCardWant) && DashCardWant["p" A_Index], t := IsObject(DashCardWant) && DashCardWant["t" A_Index]
		GuiControl, % "Dash:" (!n && p ? "Show" : "Hide"), DashCardPic%A_Index%
		GuiControl, % "Dash:" (!n && t ? "Show" : "Hide"), DashCardTxt%A_Index%
		}
	for i, c in DeckFormCtrls()
		GuiControl, % "Dash:" (n ? "Show" : "Hide"), %c%
	if (n)
		DeckFormFill(DeckCopy(DeckList[n]))
	}

;A deck's copy - edits go to it, not to the deck in use, till Save
DeckCopy(d)
	{
	c := d.Clone()
	c.when := d.when.Clone(), c.vals := d.vals.Clone()
	return c
	}

;The deck view's fields and settings list from deck d (the copy being edited)
DeckFormFill(d)
	{
	DeckEdit := d
	GuiControl, Dash:, DeckFName, % d.name
	GuiControl, Dash:ChooseString, DeckFSchool, % d.school
	GuiControl, Dash:, DeckFSet, % d.eqset
	GuiControl, Dash:, DeckFPri, % d.priority
	for k, c in {default: "DeckFWDefault", collect: "DeckFWCollect", boss: "DeckFWBoss", dungeon: "DeckFWDungeon", farm: "DeckFWFarm"}
		GuiControl, Dash:, %c%, % d.when[k] ? 1 : 0
	IniRead, pin, %A_ScriptDir%\dashboard.ini, decks, pin, %A_Space%
	GuiControl, Dash:, DeckFPin, % pin = d.id ? 1 : 0
	GuiControl, Dash:, DeckFDmg, % DeckDamageText(d)
	DeckListFill(d)
	GuiControl, Dash:, DeckFNote, % IsObject(DeckNow) && DeckNow.id = d.id ? "In use now (" DeckWhy ")" : ""
	}

;A setting's value in words: on/off, a pick's name, a number
DeckValText(s, v)
	{
	if (v = "")
		return ""
	if (s.kind = "check")
		return v ? "on" : "off"
	if (s.kind = "pick" && IsObject(s.picks) && s.picks.HasKey(v))
		return v " - " s.picks[v]
	return v
	}

;The settings list: every setting a deck may have - this deck's ("" not its own), and everywhere else's (your school's or
;the plain one)
DeckListFill(d)
	{
	Gui, Dash:Default
	prevLV := A_DefaultListView
	Gui, Dash:ListView, DeckFList
	GuiControl, Dash:-Redraw, DeckFList
	LV_Delete()
	sch := d.school != "any" ? d.school : IsFunc("StatsSchoolOf") ? Func("StatsSchoolOf").Call(Func("StatsCharID").Call()) : ""
	for i, k in DeckKeys()
		{
		s := DeckKeyInfo(k)
		mine := d.vals.HasKey(k) ? DeckValText(s, d.vals[k]) : ""
		other := (sch != "" && Stats.HasKey(sch "." k)) ? Stats[sch "." k] : Stats.HasKey(k) ? Stats[k] : s.def
		LV_Add("", s.label, mine, DeckValText(s, other), k)
		}
	GuiControl, Dash:+Redraw, DeckFList
	if (prevLV != "" && prevLV != "DeckFList")
		Gui, Dash:ListView, %prevLV%
	}

;The key of the setting picked in the list ("" none)
DeckListKey(ByRef row := 0)
	{
	Gui, Dash:Default
	prevLV := A_DefaultListView
	Gui, Dash:ListView, DeckFList
	row := LV_GetNext(0), key := ""
	if (row)
		LV_GetText(key, row, 4)
	if (prevLV != "" && prevLV != "DeckFList")
		Gui, Dash:ListView, %prevLV%
	return key
	}

;The deck view's fields into the copy being edited
DeckFormRead()
	{
	d := DeckEdit
	if (!IsObject(d))
		return ""
	GuiControlGet, v, Dash:, DeckFName
	d.name := Trim(SubStr(RegExReplace(v, "[^\x20-\x7E]|\|", ""), 1, 30))
	d.name := d.name != "" ? d.name : d.id
	GuiControlGet, v, Dash:, DeckFSchool
	d.school := v != "" ? v : "any"
	GuiControlGet, v, Dash:, DeckFSet
	d.eqset := RegExMatch(v, "^[0-9]$") ? v + 0 : 0
	GuiControlGet, v, Dash:, DeckFPri
	d.priority := RegExMatch(v, "^-?\d{1,3}$") ? v + 0 : 0
	d.when := {}
	for k, c in {default: "DeckFWDefault", collect: "DeckFWCollect", boss: "DeckFWBoss", dungeon: "DeckFWDungeon", farm: "DeckFWFarm"}
		{
		GuiControlGet, v, Dash:, %c%
		if (v)
			d.when[k] := 1
		}
	return d
	}

DeckSay(text)
	{
	GuiControl, Dash:, DeckFNote, %text%
	}

;A new deck's id (its file's name): when it was made - never a deleted deck's (a dungeon run naming that one would take
;the new one for it), and in the order made
DeckNewId()
	{
	id := "deck" A_Now
	Loop, 99
		{
		if (!FileExist(DeckDir() "\" id ".txt"))
			return id
		id := "deck" A_Now "_" A_Index
		}
	return "deck" A_Now A_TickCount
	}

DeckViewClick:
	DeckViewShow(SubStr(A_GuiControl, 9) + 0)
	return

;(a setting picked: its value for this deck in the box)
DeckListEvent:
	if (A_GuiEvent = "I" && InStr(ErrorLevel, "S") && IsObject(DeckEdit))
		{
		DeckKey := DeckListKey()
		GuiControl, Dash:, DeckFVal, % DeckKey != "" && DeckEdit.vals.HasKey(DeckKey) ? DeckEdit.vals[DeckKey] : ""
		}
	return

DeckValSet:
DeckValClear:
	DeckKey := DeckListKey()
	if (DeckKey = "" || !IsObject(DeckEdit))
		{
		DeckSay("Pick a setting in the list first")
		return
		}
	if (A_ThisLabel = "DeckValClear")
		DeckEdit.vals.Delete(DeckKey), DeckSay(DeckKey ": not set by this deck - Save to keep it")
	else
		{
		GuiControlGet, DeckV, Dash:, DeckFVal
		DeckS := DeckKeyInfo(DeckKey)
		DeckV := Trim(DeckV)
		DeckLo := DeckS.kind = "check" ? 0 : DeckS.kind = "pick" ? 1 : DeckS.lo, DeckHi := DeckS.kind = "check" ? 1 : DeckS.kind = "pick" ? DeckS.picks.Length() : DeckS.hi
		if (!RegExMatch(DeckV, "^-?\d+(\.\d+)?$") || (DeckLo != "" && DeckV < DeckLo) || (DeckHi != "" && DeckV > DeckHi))
			{
			DeckSay(DeckS.label ": " (DeckS.kind = "check" ? "1 (on) or 0 (off)" : DeckLo " to " DeckHi))
			return
			}
		DeckEdit.vals[DeckKey] := DeckV + 0, DeckSay(DeckKey " " DeckV + 0 " for this deck - Save to keep it")
		}
	DeckListFill(DeckEdit)
	GuiControl, Dash:, DeckFDmg, % DeckDamageText(DeckEdit)
	return

DeckSaveClick:
	DeckD := DeckFormRead()
	if (!IsObject(DeckD))
		return
	GuiControlGet, DeckPinOn, Dash:, DeckFPin
	IniRead, DeckPinWas, %A_ScriptDir%\dashboard.ini, decks, pin, %A_Space%
	if (DeckPinOn)
		IniWrite, % DeckD.id, %A_ScriptDir%\dashboard.ini, decks, pin
	else if (DeckPinWas = DeckD.id)
		IniDelete, %A_ScriptDir%\dashboard.ini, decks, pin
	if (DeckSave(DeckD))
		{
		;(read again from the files at once - the deck in use too - and the pick made afresh out of battle: DeckTick)
		DeckLoadAll(), DeckDirty := 0
		DeckButtonsShow()
		n := DeckIndexOf(DeckD.id)
		if (n)
			DeckFormFill(DeckCopy(DeckList[n]))
		DeckSay("Saved - " (inbattle = 1 ? "used from the next battle" : "used from now on"))
		DebugLog("Decks: " DeckD.name " saved (" DeckD.file ")")
		}
	else
		DeckSay("Couldn't write " DeckD.file)
	return

DeckCopyClick:
DeckAddClick:
	if (!IsObject(DeckList))
		DeckLoadAll()
	if (DeckList.Length() >= 6)
		{
		DeckSay("Six decks at most on the tab - delete one first")
		return
		}
	DeckId := DeckNewId()
	if (A_ThisLabel = "DeckCopyClick" && IsObject(DeckEdit))
		DeckD := DeckCopy(DeckFormRead()), DeckD.name := SubStr(DeckD.name " copy", 1, 30)
	else
		DeckD := {name: "New deck", school: "any", eqset: 0, when: {}, priority: 0, vals: {}}
	DeckD.id := DeckId, DeckD.file := DeckDir() "\" DeckId ".txt"
	DeckSave(DeckD), DeckLoadAll(), DeckButtonsShow()
	DeckViewShow(DeckIndexOf(DeckId))
	DeckSay("Made - set what it's for and its settings, then Save")
	return

DeckDelClick:
	if (!IsObject(DeckEdit))
		return
	MsgBox, 262180, Decks, % "Delete the deck '" DeckEdit.name "'? Its file goes (" DeckEdit.file "); your Settings aren't touched."
	IfMsgBox, No
		return
	FileDelete, % DeckEdit.file
	IniRead, DeckPinWas, %A_ScriptDir%\dashboard.ini, decks, pin, %A_Space%
	if (DeckPinWas = DeckEdit.id)
		IniDelete, %A_ScriptDir%\dashboard.ini, decks, pin
	DebugLog("Decks: " DeckEdit.name " deleted")
	DeckEdit := "", DeckLoadAll(), DeckButtonsShow()
	DeckViewShow(0)
	return
