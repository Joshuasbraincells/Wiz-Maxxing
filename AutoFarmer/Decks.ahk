; Decks.ahk - decks (v0.47.0, TODO goal 3, asked 2026-10-23/24): a "small" deck for weak collect mobs, a "large" one for
; bosses, and as many more as you like. Each is a set of settings that override yours while it's the deck in use - how
; it plays (card logic, blades, traps, healing, pips, discards, which hits and heals it plays) - with what it's used for
; (anything else, collect goals, bosses, dungeon runs, farming), the school it's for, and the game's Equipment Set
; (Ctrl+1..9) that puts its in-game deck on. The bot picks one before each fight from what's ahead (DeckPick) and presses
; that set's key out of battle (DeckEquip). No decks - or decks that set nothing - and it plays exactly as without.
; One file per deck: decks\<id>.txt - yours (updates keep them). The dashboard's Cards tab shows and edits them
; (Dashboard.ahk). AutoHotkey v1.1, #Included by Autofarmer.ahk.

;The decks ([{id, file, name, school, eqset, when: {default, collect, boss, dungeon, farm}, priority, vals: {key: value}}]),
;the one in use ("" none - your Settings as they are) and why, read again soon (an edit on the tab), when an Equipment Set
;was last pressed, the battle it was picked for, the Cards tab's view (0 the hand, else a deck's number in DeckList)
global DeckList, DeckNow, DeckWhy, DeckDirty, DeckEqAt, DeckDuel, DeckView
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

;The deck to use now and why ({deck: d or "", why}): only decks for this wizard's school (or any) - the one fought as in
;a battle, else the one this character fought as before. First match wins: the dungeon run's deck, the one pinned on the
;Cards tab, in a battle the boss's (your Alt+1 pick), a collect goal's, farming's (loop or lore mode), a dungeon run's,
;anything else's - none: your Settings as they are. Of several for the same, the highest priority
DeckPick(inBattle)
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
	for i, use in [["boss", inBattle && BossChoosen, "a boss (your Alt+1 pick)"]
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
		if (IsObject(best))
			return {deck: best, why: use[3]}
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

;Out of battle, every 2 s (the main loop): the decks read again after an edit, the deck for what's ahead picked, and its
;Equipment Set put on
DeckTick()
	{
	static lookAt := 0
	if (lookAt && A_TickCount - lookAt < 2000)
		return
	lookAt := A_TickCount
	if (!IsObject(DeckList) || DeckDirty)
		DeckDirty := 0, DeckLoadAll()
	p := DeckPick(false)
	DeckSet(p.deck, p.why)
	if (IsObject(p.deck))
		DeckEquip(p.deck)
	}

;A battle round (once the school's known): a new battle - its deck picked; your Alt+1 boss pick - the boss's, if there's
;one (the in-game deck can't change in a battle: its settings only)
DeckRound()
	{
	if (!IsObject(DeckList))
		DeckLoadAll()
	if (BlDuel != "" && BlDuel = DeckDuel && !(BossChoosen && !(IsObject(DeckNow) && DeckNow.when.boss)))
		return
	DeckDuel := BlDuel
	p := DeckPick(true)
	DeckSet(p.deck, p.why)
	}

;The deck's in-game deck put on - its Equipment Set's key (Ctrl+1..9 - the game's own; also its gear, pet and mount, as
;you set the set up), out of battle only, with nothing loading, Wizard101 in front and you away from the keys and mouse
;(as long as "Wait while I play" waits - handsoff, 3 s at least; Play for me: never waited for), once a minute at most (the
;game says "Slow down!" past 10 changes in 2 minutes); the set put on last kept by character (dashboard.ini [decks]
;eqset<CharID>) and pressed again after 15 minutes (a press the game didn't take - a dialog up, a battle starting)
DeckEquip(d)
	{
	static at := {}
	secs := Stats.HasKey("handsoff") ? Stats["handsoff"] : 3
	if (!d.eqset || !BotOn || inbattle = 1 || WkLoading || (IsFunc("BattleLogInBattle") && Func("BattleLogInBattle").Call())
		|| !GameActive() || UserIdle() < Max(3, secs) * 1000 || (DeckEqAt && A_TickCount - DeckEqAt < 60000))
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
	;for balance)
	boost := 1, names := ""
	grp := IsFunc("SchoolGroup") ? Func("SchoolGroup").Call(sch) : ""
	b2 := grp = "elemental" ? "elementalblade" : grp = "spirit" ? "spiritblade" : ""
	t2 := grp = "elemental" ? "elementaltrap" : grp = "spirit" ? "spirittrap" : ""
	for i, b in [["useblades", ["blade", b2, "blade3", "blade4"]], ["usetraps", ["trap", t2, "trap3", "trap4", "feint"]], ["useaura", ["aura"]], ["usebubble", ["bubble"]]]
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
