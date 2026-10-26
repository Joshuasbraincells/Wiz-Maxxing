; Kill calculator for AutoFarmer.ahk (AHK v1.1), #Included at the end of Autofarmer.ahk.
; Reads enemy health off the 2D Combat Display nameplates with Windows OCR (Ocr.ahk), predicts
; the minimum (no crit) damage of each hit in hand from PlayerStats.txt plus the boosts we've cast,
; and picks the cheapest hit that kills every enemy. Whenever something can't be trusted it claims
; no kill, so the normal battle code plays the round instead.
; Uses the super-globals declared at the top of #1:: in Autofarmer.ahk: Stats, EnemyHP, BossSlot,
; BossMax, HealthStatus, AppliedBlades, BossTraps (the traps on one enemy: TrapSlot, TrapFoe*), AuraRounds, EnchantedHits,
; PipsNow.

;Reads PlayerStats.txt (key:value lines, ; starts a comment) on top of built-in defaults. quiet: lines
;that can't be read go to debug.log instead of a message box (reloading while the bot runs)
LoadStats(quiet := false)
	{
	defaults := "damage:130,pierce:0,enemyresist:15,killmargin:15,solotraps:0,reboost:0,discardunaffordable:0,discardunused:1,discardmax:3,learnedhits:1,fleeon:1,healthocr:1,ocrscale:2,platestrip:110"
		. ",blade:35,elementalblade:35,spiritblade:35,blade3:25,blade4:20,sharpen:10"
		. ",trap:40,elementaltrap:30,spirittrap:30,trap3:30,trap4:0,feint:70,potent:10"
		. ",aura:25,enchant1:100,enchant2:225,enchant3:275,enchant4:300,enchant5:100,enchant6:125,enchant7:175,drawneed:100,drawround:3,drawmax:6,pipsave:3,pipsavehealth:50,handsoff:10,handsoffon:1,potionmark:1,potionfromhome:1,navmem:1"
		. ",storm.hit1:80,storm.hit2:520,storm.hit3:690,storm.hit4:805"
		. ",fire.hit1:305,fire.hit2:430,fire.hit3:540,fire.hit4:1265"
		. ",myth.hit1:275,myth.hit2:370,myth.hit3:700,myth.hit4:790"
		. ",storm.hit1pips:0,storm.hit2pips:5,storm.hit3pips:7,storm.hit4pips:9"
		. ",fire.hit1pips:4,fire.hit2pips:6,fire.hit3pips:7,fire.hit4pips:6"
		. ",myth.hit1pips:4,myth.hit2pips:6,myth.hit3pips:7,myth.hit4pips:5"
	Stats := {}
	Loop, Parse, defaults, `,
		{
		ParseStat(A_LoopField)
		}
	;(and the Settings window's: Settings.ahk CfgList)
	if (IsFunc("CfgList"))
		for each, cfgS in Func("CfgList").Call()
			if (cfgS.HasKey("def") && !Stats.HasKey(cfgS.key))
				Stats[cfgS.key] := cfgS.def
	bad := ""
	Loop, Read, %A_WorkingDir%\PlayerStats.txt
		{
		if (!ParseStat(A_LoopReadLine))
			{
			bad .= A_LoopReadLine . "`n"
			}
		}
	if (bad != "" && quiet)
		DebugLog("PlayerStats.txt lines that couldn't be read (built-in defaults used): " StrReplace(Trim(bad, "`n"), "`n", " | "))
	else if (bad != "")
		{
		MsgBox, 48, AutoFarmer, % "These PlayerStats.txt lines couldn't be read, so their built-in defaults are used:`n`n" . bad
		}
	}

;One key:value line (a trailing % is allowed). Returns false for a line that has something in it but doesn't parse
ParseStat(line)
	{
	line := RegExReplace(line, ";.*")
	if (RegExMatch(line, "^\s*([\w.]+)\s*:\s*(-?\d+(?:\.\d+)?)\s*\x25?\s*$", m))
		{
		StringLower, key, m1
		Stats[key] := m2 + 0
		return true
		}
	return (Trim(line) == "")
	}

Stat(key)
	{
	;The deck in use's own first (Decks.ahk - only the settings a deck may set)
	if (IsObject(DeckNow) && IsObject(DeckNow.vals) && DeckNow.vals.HasKey(key))
		return DeckNow.vals[key]
	;A value for one school's wizard first (e.g. myth.damage, myth.pierce for the Myth wizard - each
	;wizard has its own stats), when the battle is being fought as that school
	if (hitschool != "" && !InStr(key, ".") && Stats.HasKey(hitschool "." key))
		return Stats[hitschool "." key]
	return Stats.HasKey(key) ? Stats[key] : 0
	}

;A setting as Stat has it - the deck in use's, your school's, the plain one - else def (not in PlayerStats.txt at all)
StatOr(key, def)
	{
	if (IsObject(DeckNow) && IsObject(DeckNow.vals) && DeckNow.vals.HasKey(key))
		return DeckNow.vals[key]
	if (hitschool != "" && !InStr(key, ".") && Stats.HasKey(hitschool "." key))
		return Stats[hitschool "." key]
	return Stats.HasKey(key) ? Stats[key] : def
	}

;Outgoing damage % stat -> multiplier (PvE curve: linear to 150%, then limited towards +200%)
DamageMultiplier(D)
	{
	L := 2.0, k0 := 190, n0 := -40
	if (D <= k0 + n0)
		return 1 + D / 100
	k := Ln((100 * L) / (100 * L - k0)) / k0
	n := Ln(1 - (k0 + n0) / (100 * L)) + k * (k0 + n0)
	return 1 + L - L / Exp(k * D - n)
	}

;Remembers a blade/trap we cast, keyed by card so recasting the same card doesn't count twice: key is BoostKey's
;("storm/blade", "blade3", "elementalblade"...), src "tc" / "item" a treasure or item card's copy ("@tc", "@item" after it -
;the game stacks it with the deck's: a deck Stormblade and a pet's both count, the user 2026-10-24), "+" when it was
;sharpened / potent (bonus). Its % the game's (the card in hand, BoostPctMem) else PlayerStats.txt's (BoostPct)
AddBoost(list, key, bonus, src := "")
	{
	list[key (src != "" ? "@" src : "") (bonus ? "+" : "")] := BoostPctFor(key, src) + bonus
	}

BoostMult(list)
	{
	mult := 1
	for card, pct in list
		{
		mult *= 1 + pct / 100
		}
	return mult
	}

;---- Blades and traps by damage school (TODO.md goal 3, 2026-10-24) ----
;Each hit's damage schools head by head (HitHeads: Hydra's fire, ice and storm - the game's memory, vision\handmem.py,
;read-only), the boosts that fit the planned hit's schools found and cast (BoostSearch, BoostPick), the kill check by
;head (HitDamage: each head times the blades, traps and aura that fit it), the boosts a hit uses up by fit
;(ConsumeBoosts). Without the game's memory: PlayerStats.txt's <school>.hit<N><school> keys, else one head of your
;school - as before

;A boost card's key in AppliedBlades / BossTraps and the used flags (KeyFlags): its slot's name for one every school
;shares (resources\: blade3, blade4, elementalblade, spiritblade, trap3, elementaltrap, spirittrap, feint), "<school>/blade"
;/ "<school>/trap" for a school's own. Balance's own blade and trap are Balanceblade and Hex (balance\blade.png is
;resources\blade3.png): keyed as those, never counted twice
BoostKey(title, dir)
	{
	if (dir = "" || dir = "resources")
		return title
	if (dir = "balance" && (title = "blade" || title = "trap"))
		return (title = "blade") ? "blade3" : "trap3"
	return dir "/" title
	}

;A key without its copy ("@tc", "@item") and "+" (sharpened / potent): "storm/blade@item+" -> "storm/blade"
BoostBase(key)
	{
	return RegExReplace(key, "(@[a-z]+)?\+?$")
	}

;The kind of boost key: "blade" or "trap" ("" neither)
BoostKind(key)
	{
	bkB := BoostBase(key)
	;(trap3 and trap4 too - Hex is trap3: SubStr(bkB, -3) is its last four letters, "rap3")
	if (bkB = "feint" || RegExMatch(bkB, "trap[34]?$"))
		return "trap"
	return SubStr(bkB, -4) = "blade" || RegExMatch(bkB, "^blade[34]$") ? "blade" : ""
	}

;The schools boost card key fits: "all", or a comma list in a-z order, as the game has them (its memory, 2026-10-24:
;Balanceblade, Bladestorm, Hex and Feint boost every school - damage type All -, Elemental Blade / Trap fire, ice and
;storm, Spirit Blade / Trap death, life and myth, a school's blade and trap its own school; the aura: its card's as the
;game read it when cast - AuraSch -, else yours); "" not known (never multiplied, always used up)
BoostSchools(key)
	{
	global hitschool, AuraSch
	bsK := BoostBase(key)
	if (RegExMatch(bsK, "^([a-z]+)/(blade|trap)$", bsM))
		return bsM1
	if (bsK = "elementalblade" || bsK = "elementaltrap")
		return "fire,ice,storm"
	if (bsK = "spiritblade" || bsK = "spirittrap")
		return "death,life,myth"
	if (bsK = "blade3" || bsK = "blade4" || bsK = "trap3" || bsK = "trap4" || bsK = "feint")
		return "all"
	if (bsK = "aura")
		return AuraSch != "" ? AuraSch : hitschool
	;(an older key with no school: your school's)
	if (bsK = "blade" || bsK = "trap")
		return hitschool
	return ""
	}

;Whether boost card key boosts a head of school sch
BoostFits(key, sch)
	{
	bfS := BoostSchools(key)
	return bfS = "all" || (bfS != "" && sch != "" && InStr("," bfS ",", "," sch ","))
	}

;Whether boost card key fits any of the schools in list (a comma list)
BoostFitsAny(key, list)
	{
	Loop, Parse, list, `,
		if (A_LoopField != "" && BoostFits(key, A_LoopField))
			return true
	return false
	}

;The % boost card key adds as PlayerStats.txt has it: a school's own blade / trap - your school's at blade / trap as Stat
;has it (the deck's, your school's, the plain one), another school's at blade.<school> / trap.<school> (a pet's Stormblade
;on a Balance wizard: blade.storm - storm.blade is the Storm wizard's own blade, as Stat has it), else the plain blade /
;trap -, the others at their slot's (blade3, elementalblade, trap3...) as before
BoostPct(key)
	{
	global hitschool
	bpK := BoostBase(key)
	if (!RegExMatch(bpK, "^([a-z]+)/(blade|trap)$", bpM))
		return Stat(bpK)
	if (bpM1 = hitschool)
		return Stat(bpM2)
	return Stats.HasKey(bpM2 "." bpM1) ? Stats[bpM2 "." bpM1] : Stats.HasKey(bpM2) ? Stats[bpM2] : 0
	}

;The % boost key's copy src ("" the deck's, "tc", "item") adds: the least of its cards in the game's hand this look
;(BoostSearch - a pet's 40% Mythblade at 40), else PlayerStats.txt's (BoostPct)
BoostPctFor(key, src := "")
	{
	global BoostPctMem
	bpfK := BoostBase(key)
	if (IsObject(BoostPctMem))
		{
		if (BoostPctMem.HasKey(bpfK "@" (src = "" ? "deck" : src)))
			return BoostPctMem[bpfK "@" (src = "" ? "deck" : src)]
		if (BoostPctMem.HasKey(bpfK))
			return BoostPctMem[bpfK]
		}
	return BoostPct(bpfK)
	}

;The boosts in list that fit school sch, multiplied (BoostMult's, only those)
BoostMultFor(list, sch)
	{
	bmfMult := 1
	for bmfKey, bmfPct in list
		if (BoostFits(bmfKey, sch))
			bmfMult *= 1 + bmfPct / 100
	return bmfMult
	}

;"fire:230,ice:230,storm:230" (the helper's heads field; a learned card's flag heads= has + for ,) into out's heads
;({school: least damage}), total and sure (1). False - out untouched - when it isn't all known: "", "?", a school not one
;of the seven, nothing
HeadsParse(text, out)
	{
	if (text = "" || text = "?")
		return false
	hpHeads := {}, hpTotal := 0
	Loop, Parse, text, `,+
		{
		if (!RegExMatch(Trim(A_LoopField), "^([a-z]+):(\d+)$", hpM) || !BadgeNumber(hpM1))
			return false
		hpHeads[hpM1] := (hpHeads.HasKey(hpM1) ? hpHeads[hpM1] : 0) + hpM2, hpTotal += hpM2
		}
	if (hpTotal <= 0)
		return false
	out.heads := hpHeads, out.total := hpTotal, out.sure := 1
	return true
	}

;"ice:35,storm:35,fire:35" (the helper's boosts field) -> {sch: "fire,ice,storm" (a-z, as BoostSchools has them) or
;"all", pct: its least %}; "" when it isn't known ("", "?", a school that isn't one)
BoostsParse(text)
	{
	if (text = "" || text = "?")
		return ""
	bpaL := "", bpaPct := "", bpaAll := 0
	Loop, Parse, text, `,
		{
		if (!RegExMatch(Trim(A_LoopField), "^([a-z]+):(\d+)$", bpaM))
			return ""
		if (bpaM1 = "all")
			bpaAll := 1
		else if (!BadgeNumber(bpaM1))
			return ""
		else if (!InStr("`n" bpaL "`n", "`n" bpaM1 "`n"))
			bpaL .= (bpaL = "" ? "" : "`n") bpaM1
		if (bpaPct = "" || bpaM2 + 0 < bpaPct)
			bpaPct := bpaM2 + 0
		}
	if (bpaPct = "")
		return ""
	Sort, bpaL
	return {sch: bpaAll ? "all" : StrReplace(bpaL, "`n", ","), pct: bpaPct}
	}

;A boost card's % in the game's hand (VisionCards' card): its boosts' least, else its number ("" none)
BoostCardPct(c)
	{
	bcpB := BoostsParse(c.boosts)
	return IsObject(bcpB) ? bcpB.pct : c.num
	}

;Which copy a card in the game's hand is: "" the deck's, "tc" a treasure card, "item" an item card (a pet's, gear's) -
;copies of one boost from each stack in the game
BoostSrcOf(c)
	{
	return c.item ? "item" : c.tc ? "tc" : ""
	}

;The cards of the game's hand (VisionCards' cards) that are boost key's card, as their numbers in cards: its kind (blade /
;trap) and schools (BoostSchools) - those whose boosts weren't read only when no card read for sure is (they match any of
;their kind); one every school shares (blade3, blade4, trap3, feint) only those at its % (PlayerStats.txt's: Balanceblade's
;25, Bladestorm's 20) when any are. Tower Shield (key tower - resources\tower): TowerMatches'
BoostMatches(key, cards)
	{
	if (key = "tower")
		return TowerMatches(cards)
	bmOut := [], bmKind := BoostKind(key), bmSch := BoostSchools(key), bmUnsure := []
	if (bmKind = "" || bmSch = "" || !IsObject(cards))
		return bmOut
	for bmI, bmC in cards
		{
		if (bmC.kind != bmKind)
			continue
		bmB := BoostsParse(bmC.boosts)
		if (!IsObject(bmB))
			bmUnsure.Push(bmI)
		else if (bmB.sch = bmSch)
			bmOut.Push(bmI)
		}
	if (!bmOut.Length())
		bmOut := bmUnsure
	if (bmSch = "all" && bmOut.Length())
		{
		bmAt := [], bmWant := BoostPct(key)
		for bmI, bmN in bmOut
			if (BoostCardPct(cards[bmN]) = bmWant)
				bmAt.Push(bmN)
		if (bmAt.Length())
			return bmAt
		}
	return bmOut
	}

;The cards of the game's hand (VisionCards' cards) that are a Tower Shield (resources\tower - cast on yourself or an ally
;as Tower Shield), as their numbers in cards: a shield (kind ward) the game names Tower Shield - the deck's, a treasure or
;an item card's; none so named: a shield card (the game's type Ward) for one wizard against every school - its text as
;the helper writes it, "-50% to next spell" (no school named, not "(all of you)"; a school's shield - Fire Shield, Spirit
;Shield - only stops that school's hits, and a ramp's shield is another kind of card). [] none
TowerMatches(cards)
	{
	twmOut := [], twmAny := []
	if (!IsObject(cards))
		return twmOut
	for twmI, twmC in cards
		{
		if (twmC.kind != "ward")
			continue
		if (RegExMatch(twmC.display "|" twmC.name, "i)\btower\s*shield\b"))
			twmOut.Push(twmI)
		else if (twmC.type = "ward" && RegExMatch(Trim(twmC.text), "i)^-\d+%\s*to next spell$"))
			twmAny.Push(twmI)
		}
	return twmOut.Length() ? twmOut : twmAny
	}

;The slot a boost of kind ("blade" / "trap") boosting schools sch (BoostsParse's - "fire,ice,storm", "all") at pct % is
;cast from: "<school>\blade", "resources\elementalblade", "resources\blade3" (every school: by its % - Balanceblade's,
;Bladestorm's, Hex's, Feint's as PlayerStats.txt has them)... "" none (Balance alone - its own are blade3, trap3 -, two
;schools, another %). For school wsch's wizard (its numbers)
BoostSlotFor(kind, sch, pct, wsch := "")
	{
	if (sch = "fire,ice,storm")
		return "resources\elemental" kind
	if (sch = "death,life,myth")
		return "resources\spirit" kind
	if (sch = "all")
		{
		for bsfI, bsfK in (kind = "blade" ? ["blade3", "blade4"] : ["trap3", "feint"])
			if (pct != "" && pct + 0 = BoostStatOf(wsch, bsfK))
				return "resources\" bsfK
		return ""
		}
	return (BadgeNumber(sch) && sch != "balance") ? sch "\" kind : ""
	}

;PlayerStats.txt's key for school sch's wizard (<sch>.key), else the plain key ("" none)
BoostStatOf(sch, key)
	{
	if (sch != "" && Stats.HasKey(sch "." key))
		return Stats[sch "." key]
	return Stats.HasKey(key) ? Stats[key] : ""
	}

;The used flags of boost key (used<n>: UseBlade's / UseTrap's Use1 - sharpened / potent - and Use2 - plain - for its
;deck copy, cast once each a battle): [n1, n2], "" none. Every school's own blade and trap its pair (balance: blade3,
;trap3); 0, 3, 4, 11, 12 and 20 aren't used any more (19: Party.ahk PartyShield's)
KeyFlags(key)
	{
	static kfT := ""
	if (!IsObject(kfT))
		kfT := {feint: [1, 2], elementaltrap: [5, 6], trap3: [7, 8], trap4: [9, 10], elementalblade: [13, 14], blade3: [15, 16]
			, blade4: [17, 18], spiritblade: [49, 50], spirittrap: [51, 52]}
	kfB := BoostBase(key)
	if (kfT.HasKey(kfB))
		return kfT[kfB]
	if (RegExMatch(kfB, "^([a-z]+)/(blade|trap)$", kfM) && kfM1 != "balance" && (kfN := BadgeNumber(kfM1)))
		return (kfM2 = "blade") ? [21 + 4 * (kfN - 1), 22 + 4 * (kfN - 1)] : [23 + 4 * (kfN - 1), 24 + 4 * (kfN - 1)]
	return ""
	}

;The boost key used flag n belongs to ("" none: 19 is the tower's)
FlagKey(n)
	{
	for fkI, fkK in ["feint", "elementaltrap", "trap3", "trap4", "elementalblade", "blade3", "blade4", "spiritblade", "spirittrap"
		, "storm/blade", "storm/trap", "fire/blade", "fire/trap", "myth/blade", "myth/trap", "ice/blade", "ice/trap"
		, "life/blade", "life/trap", "death/blade", "death/trap"]
		{
		fkF := KeyFlags(fkK)
		if (IsObject(fkF) && (fkF[1] = n || fkF[2] = n))
			return fkK
		}
	return ""
	}

;The battle code's used flag n (used<n>, a global: here so a function's own doesn't take its place)
UsedFlag(n)
	{
	global
	return used%n%
	}

UsedFlagSet(n, v)
	{
	global
	used%n% := v
	}

;A hit's damage by school - its heads (Hydra: fire, ice and storm, 230 each): {heads: {school: least damage}, total, sure
;(1: its schools are known - the game's or yours; 0: taken as your school's, as always), xpip (its numbers a pip's), src
;(for the log), one (1 one enemy, 0 all, "" not known), item (1 an item card - never enchanted)}. Looked at once a look at
;the hand (HeadsMemo, emptied at FindCards) - HitHeadsFind
HitHeads(hitName)
	{
	global hitschool, HeadsMemo
	if (!IsObject(HeadsMemo))
		HeadsMemo := {}
	if (!HeadsMemo.HasKey(hitName "|" hitschool))
		HeadsMemo[hitName "|" hitschool] := HitHeadsFind(hitName)
	return HeadsMemo[hitName "|" hitschool]
	}

;HitHeads' look, in this order: the game's memory - the card on the slot's picture (SlotGame: its name in the game, from
;CardLearn.ahk LearnCards' look at the hand; else the slot's learned card's flag game=), the card itself in the game's hand
;(VisionCards: its heads field); the slot's learned card's heads as the game had them (flag heads=); PlayerStats.txt's
;<school>.<hit><head's school> keys (balance.hit3fire:230, balance.hit3ice:230, balance.hit3storm:230) while they add up
;to <school>.<hit> (or it isn't set); else one head of your school, <school>.<hit> (sure 0). A learned card with a number
;you set on the Spells tab (flag user): the game's schools, your number (HeadsToYours)
HitHeadsFind(hitName)
	{
	global hitschool, SlotGame, BoostSaid
	hhOut := {heads: {}, total: 0, sure: 0, xpip: 0, src: "", one: "", item: (hitName = "wand") ? 1 : 0}
	if (hitschool = "")
		return hhOut
	hhName := IsObject(SlotGame) ? SlotGame[hitschool "/" hitName] : ""
	hhLc := IsFunc("LearnCardInSlot") ? Func("LearnCardInSlot").Call(hitschool "\" hitName) : ""
	if (hhName = "" && IsObject(hhLc))
		hhName := Func("LearnFlag").Call(hhLc, "game")
	if (hhName != "" && IsFunc("VisionCards"))
		{
		;(the hand read this look - no new read)
		hhHand := Func("VisionCards").Call(300, 5000)
		if (IsObject(hhHand))
			for hhI, hhM in hhHand.cards
				if ((IsFunc("LearnMemGame") ? Func("LearnMemGame").Call(hhM) : hhM.name) = hhName && (hhM.kind = "damage" || hhM.kind = "aoe") && HeadsParse(hhM.heads, hhOut))
					{
					hhOut.xpip := (hhM.xpip && hitName != "wand") ? 1 : 0, hhOut.src := "the game", hhOut.one := (hhM.kind = "damage") ? 1 : 0
					hhOut.item := (hhM.item || hitName = "wand") ? 1 : 0
					;(the slot's learned card - this card, by its game name - with a number you set on the Spells tab: yours)
					if (IsObject(hhLc) && Func("LearnHasFlag").Call(hhLc, "user") && IsFunc("LearnHitBase")
						&& (Func("LearnFlag").Call(hhLc, "game") = "" || Func("LearnFlag").Call(hhLc, "game") = hhName))
						HeadsToYours(hhOut, Func("LearnHitBase").Call(hhLc))
					return hhOut
					}
		}
	if (IsObject(hhLc) && HeadsParse(Func("LearnFlag").Call(hhLc, "heads"), hhOut))
		{
		hhOut.xpip := (Func("LearnHasFlag").Call(hhLc, "xpip") && hitName != "wand") ? 1 : 0, hhOut.src := "the game (learned card)"
		hhOut.item := (Func("LearnHasFlag").Call(hhLc, "item") || hitName = "wand") ? 1 : 0
		if (Func("LearnHasFlag").Call(hhLc, "user") && IsFunc("LearnHitBase"))
			HeadsToYours(hhOut, Func("LearnHitBase").Call(hhLc))
		return hhOut
		}
	hhOut.xpip := (hitName != "wand" && Stat(hitschool "." hitName "pips") = 0) ? 1 : 0
	;(PlayerStats.txt's heads only while they add up to <school>.<hit>, or it isn't set - the learner writes both, CardLearn.ahk
	;LearnStats: a number put there since - the Settings window, another card in the slot, the picture cut again - is the
	;slot's card now, not the old heads)
	hhSum := 0, hhPer := {}
	for hhI, hhS in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
		if ((hhV := Stat(hitschool "." hitName hhS)) > 0)
			hhPer[hhS] := hhV, hhSum += hhV
	hhV := Stat(hitschool "." hitName)
	if (hhSum > 0 && (hhV <= 0 || hhV = hhSum))
		{
		hhOut.heads := hhPer, hhOut.total := hhSum, hhOut.sure := 1, hhOut.src := "PlayerStats.txt"
		return hhOut
		}
	if (hhSum > 0 && IsObject(BoostSaid) && !BoostSaid.HasKey("heads|" hitschool "." hitName))
		BoostSaid["heads|" hitschool "." hitName] := 1, DebugLog("  PlayerStats.txt: the heads of " hitschool "." hitName " (" HeadsText({heads: hhPer})
			. ") add up to " hhSum ", not its " hitschool "." hitName ":" hhV " - left out, one head of your school counted")
	if (hhV > 0)
		hhOut.heads[hitschool] := hhV, hhOut.total := hhV, hhOut.src := "your school's"
	return hhOut
	}

;A hit's heads (HitHeads') brought to number uv you set for its learned card on the Spells tab (flag user - never what you
;set, as CardLearn.ahk LearnHitBase): each head its share of uv, floored, what that leaves on the biggest - the game's
;schools, your number. Not when uv isn't a number above 0 or is their total already
HeadsToYours(hh, uv)
	{
	if (uv = "" || !(uv > 0) || hh.total <= 0 || uv = hh.total)
		return
	htyOut := {}, htySum := 0, htyBig := ""
	for htyS, htyB in hh.heads
		{
		htyOut[htyS] := Floor(htyB * uv / hh.total), htySum += htyOut[htyS]
		if (htyBig = "" || htyB > hh.heads[htyBig])
			htyBig := htyS
		}
	htyOut[htyBig] += uv - htySum
	hh.heads := htyOut, hh.total := uv + 0, hh.src := "your value (the game's schools)"
	}

;A learned hit's heads (LearnedHitDamage, ConsumeBoosts after one): as the game had them (flag heads=) - a number you set
;on the Spells tab (flag user) kept: the game's schools, your number (HeadsToYours) -, else one head of its own school
;(flag school=, the Spells tab - one of the seven) or yours, its least damage (LearnHitBase)
LearnHitHeads(c)
	{
	global hitschool
	lhOut := {heads: {}, total: 0, sure: 0, xpip: 0, src: "", one: "", item: 0}
	if (!IsObject(c))
		return lhOut
	lhOut.xpip := (IsFunc("LearnHasFlag") && Func("LearnHasFlag").Call(c, "xpip")) ? 1 : 0
	lhOut.item := (IsFunc("LearnHasFlag") && Func("LearnHasFlag").Call(c, "item")) ? 1 : 0
	if (IsFunc("LearnFlag") && HeadsParse(Func("LearnFlag").Call(c, "heads"), lhOut))
		{
		lhOut.src := "the game (learned card)"
		if (IsFunc("LearnHasFlag") && Func("LearnHasFlag").Call(c, "user") && IsFunc("LearnHitBase"))
			HeadsToYours(lhOut, Func("LearnHitBase").Call(c))
		return lhOut
		}
	lhBase := IsFunc("LearnHitBase") ? Func("LearnHitBase").Call(c) : ""
	if (lhBase = "" || lhBase <= 0)
		return lhOut
	lhS := IsFunc("LearnFlag") ? Func("LearnFlag").Call(c, "school") : ""
	lhS := BadgeNumber(lhS) ? lhS : hitschool
	lhOut.heads[lhS] := lhBase, lhOut.total := lhBase, lhOut.src := "its school's"
	return lhOut
	}

;Least damage of a hit with heads hh (HitHeads'): each head times per (an X-pip hit's pips) with the boosts that fit its
;school (HitDamageFrom), floored and added; the enchant's add (once - it's one card) on the head where it adds the least
HeadsDamage(hh, per, add, toBoss)
	{
	hdD := {}, hdSum := 0
	for hdS, hdB in hh.heads
		hdD[hdS] := HitDamageFrom(hdB * per, toBoss, hdS), hdSum += hdD[hdS]
	if (add <= 0)
		return hdSum
	hdBest := ""
	for hdS, hdB in hh.heads
		{
		hdT := hdSum - hdD[hdS] + HitDamageFrom(hdB * per + add, toBoss, hdS)
		if (hdBest = "" || hdT < hdBest)
			hdBest := hdT
		}
	return hdBest = "" ? 0 : hdBest
	}

;"fire 230 + ice 230 + storm 230 (the game)" - a hit's heads for the log
HeadsText(hh)
	{
	htOut := ""
	for htS, htB in hh.heads
		htOut .= (htOut = "" ? "" : " + ") htS " " htB
	return htOut (hh.src != "" ? " (" hh.src ")" : "")
	}

;The heads' schools, your school first, then as BadgeNumber orders them: [school...]
HeadsOrder(heads)
	{
	global hitschool
	hoOut := []
	if (IsObject(heads) && heads.HasKey(hitschool))
		hoOut.Push(hitschool)
	for hoI, hoS in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		if (hoS != hitschool && IsObject(heads) && heads.HasKey(hoS))
			hoOut.Push(hoS)
	return hoOut
	}

;The blade and trap groups of schools list: "elemental" (fire, ice, storm), "spirit" (myth, life, death), each once, in
;list's order - Balance has none
PlanGroups(list)
	{
	pgOut := [], pgSeen := ","
	for pgI, pgS in list
		{
		pgG := SchoolGroup(pgS)
		if ((pgG = "elemental" || pgG = "spirit") && !InStr(pgSeen, "," pgG ","))
			pgOut.Push(pgG), pgSeen .= pgG ","
		}
	return pgOut
	}

;Whether a copy of boost key (its src: "" the deck's, "tc", "item") can still be cast: the deck's sharpened (sharp: a
;Sharpen / Potent in hand; never an item card's) while use1 isn't set, plain while use2 isn't; a treasure or item card's
;once a battle (BoostSrcUsed) - it stacks with the deck's
BoostCopyCanGo(key, src, item, sharp, use1, use2)
	{
	global BoostSrcUsed
	if (src = "")
		return (sharp && !item && use1 != 1) || use2 != 1
	return !(IsObject(BoostSrcUsed) && BoostSrcUsed.HasKey(BoostBase(key) "@" src))
	}

;Whether boost key can still go this round: a copy of it in the game's hand that can (BoostHand, BoostCopyCanGo); without
;it, as ever - its sharpened cast (a Sharpen / Potent in hand) or its plain one not used this battle
BoostCanGo(key)
	{
	global
	local bcgF, bcgI, bcgC, bcgSharp
	bcgF := KeyFlags(key)
	if (!IsObject(bcgF))
		return false
	if (BoostKind(key) = "trap")
		{
		if (TrapOn != 1)
			return false
		bcgSharp := (potent == 1)
		}
	else
		bcgSharp := (sharpen == 1)
	if (IsObject(BoostHand) && BoostHand.HasKey(key))
		{
		for bcgI, bcgC in BoostHand[key]
			if (BoostCopyCanGo(key, bcgC.src, bcgC.item, bcgSharp, UsedFlag(bcgF[1]), UsedFlag(bcgF[2])))
				return true
		return false
		}
	return (bcgSharp && UsedFlag(bcgF[1]) != 1) || UsedFlag(bcgF[2]) != 1
	}

;The card boxes of a fresh look at the hand (CardLearn.ahk LearnHandRead), each with the game's card on it - VisionCards',
;left to right, only when they're as many: [{l, t, w, h, known, grey (1: greyed out), m, n (its number in the game's
;hand)}]; "" they aren't, or either isn't there. bbWait: how long the game's hand may still be changing (VisionCards)
BoostBoxes(bbWait := 300)
	{
	bbHand := IsFunc("VisionCards") ? Func("VisionCards").Call(bbWait, 5000) : ""
	if (!IsObject(bbHand) || !IsFunc("LearnHandRead"))
		return ""
	bbAns := Func("LearnHandRead").Call()
	bbOut := []
	Loop, Parse, bbAns, `n, `r
		{
		bbF := StrSplit(A_LoopField, "|")
		if (bbF.Length() < 12 || bbF[1] != "card" || (bbF.Length() >= 15 && bbF[15] = "0"))
			continue
		bbOut.Push({l: bbF[2] + 0, t: bbF[3] + 0, w: bbF[4] + 0, h: bbF[5] + 0, known: bbF[6], grey: bbF[8] = 1 ? 1 : 0})
		}
	if (!bbOut.Length() || bbOut.Length() != bbHand.cards.Length())
		return ""
	for bbI, bbB in bbOut
		bbB.m := bbHand.cards[bbI], bbB.n := bbI
	return {boxes: bbOut, hand: bbHand}
	}

;---- A boost no picture finds, cast where the game's memory has it (2026-10-24) ----
;The game's hand (read-only) names a blade or trap no picture found - the slot's picture missing, an 8x8 placeholder, or one
;the helper can't match on every copy (debug.log: "in hand (the game): Balanceblade ... no picture found it"): BoostSearch
;notes it (BoostMemOnly) when this look's search is for it, BoostPick plans with it as with any found, and UseBlade / UseTrap
;cast it at its card box (BoostMemBox) - only while the boxes and the game's cards line up for sure

;The key of the boost cast from slot ("resources\blade3" -> "blade3", "storm\blade" -> "storm/blade" - BoostKey's); "" none
BoostMemKey(slot)
	{
	if (slot = "")
		return ""
	SplitPath, slot, bmkName, bmkDir
	return BoostKey(bmkName, bmkDir)
	}

;Whether this look's boost search (BoostSearch) is for boost key, the schools wanted being want: a school's own blade or
;trap of a school in it (not Balance's - its own are blade3, trap3), a group's (elemental, spirit) of a group of them, every
;school's (blade3, blade4, trap3, feint) always - as FindCards and BoostSearch look for them by their pictures
BoostMemWanted(key, want)
	{
	if (RegExMatch(key, "^([a-z]+)/(blade|trap)$", bmwM))
		{
		for bmwI, bmwS in want
			if (bmwS = bmwM1 && bmwS != "balance")
				return true
		return false
		}
	if (RegExMatch(key, "^(elemental|spirit)(blade|trap)$", bmwM))
		{
		for bmwI, bmwG in PlanGroups(want)
			if (bmwG = bmwM1)
				return true
		return false
		}
	return (key = "blade3" || key = "blade4" || key = "trap3" || key = "feint")
	}

;What kind of card a hand box the helper knows by picture known holds (/hand's known: "balance/hit3", "resources/blade3",
;"learned/<id>") - BoostMemBox's check that the boxes and the game's cards line up: "hit", "boost" (a blade, trap or aura),
;"heal", "ward", "enchant"; "" not known for sure (no picture, a kind it doesn't tell, a learned card whose kind was only
;read off it - flag mem: the game's)
BoostBoxSays(known)
	{
	if (known = "")
		return ""
	if (InStr(known, "learned/") = 1)
		{
		bxsC := IsFunc("LearnCardOf") ? Func("LearnCardOf").Call(SubStr(known, 9)) : ""
		if (!IsObject(bxsC) || !IsFunc("LearnHasFlag") || !Func("LearnHasFlag").Call(bxsC, "mem"))
			return ""
		return BoostKindSays(bxsC.type)
		}
	bxsN := SubStr(known, InStr(known, "/", false, 0) + 1)
	if (RegExMatch(bxsN, "^(hit[1-4]|wand)$"))
		return "hit"
	if (bxsN = "feint" || bxsN = "aura" || RegExMatch(bxsN, "(blade|trap)[34]?$"))
		return "boost"
	if (RegExMatch(bxsN, "^heal[12]$"))
		return "heal"
	if (bxsN = "tower")
		return "ward"
	if (RegExMatch(bxsN, "^(sharpen|potent|enchant|strong|giant|monstrous|gargantuan|colossal|epic)$"))
		return "enchant"
	return ""
	}

;The same for a kind (the game's - VisionCards' kind - or a learned card's): "hit" damage / aoe, "boost" blade / trap /
;aura, "heal", "ward", "enchant"; "" any other (damage over time, keep - the game's effects cut short -...)
BoostKindSays(kind)
	{
	if (kind = "damage" || kind = "aoe")
		return "hit"
	if (kind = "blade" || kind = "trap" || kind = "aura")
		return "boost"
	return (kind = "heal" || kind = "ward" || kind = "enchant") ? kind : ""
	}

;Where boost key's card is in hand when no picture found it (UseBlade, UseTrap): a fresh look at the hand's card boxes laid
;on the game's cards (BoostBoxes: the game's hand settled, as many boxes as cards, left to right), the first box holding a
;copy of it (BoostMatches) that can go now (BoostCopyCanGo - sharp: a Sharpen / Potent in hand; use1, use2: its deck copy's
;used flags), not greyed out nor one the game says can't be cast - and only while the pairing is sure: no box the bot knows
;by a picture holds a card of another kind than the picture says (BoostBoxSays: a hit's picture on a blade - the boxes don't
;line up), and this box's own picture, if it has one, is this card's (BoostMemBoxOk). ench 1: only a copy with an
;enchantment on it (the one just sharpened - BoostSettleMem); wait: how long the game's hand may still be changing.
;{x, y (the box's middle - ClickAt goes there from above the hand: MoveToCard), n, of (the box's number, how many), src (""
;the deck's, "tc", "item"), item, name (the game's), ench (1: it carries an enchantment already)}; {x: "", why} none
BoostMemBox(key, sharp, use1, use2, ench := 0, wait := 300)
	{
	global VisionCardsWhy
	;(no card zoomed up under the mouse when the hand's boxes are read - CardLearn.ahk; the round's CenterMouse is off it)
	if (IsFunc("LearnMouseClear"))
		Func("LearnMouseClear").Call()
	bmbAll := BoostBoxes(wait)
	if (!IsObject(bmbAll))
		return {x: "", why: "the hand's card boxes and the game's cards don't line up (" (VisionCardsWhy != "" ? VisionCardsWhy : "not as many, or the hand not read") ")"}
	;(the boxes known by a picture: each one's card the kind its picture says)
	for bmbI, bmbB in bmbAll.boxes
		{
		bmbSays := BoostBoxSays(bmbB.known), bmbKind := BoostKindSays(bmbB.m.kind)
		if (bmbSays != "" && bmbKind != "" && bmbSays != bmbKind)
			return {x: "", why: "box " bmbI " is known as " bmbB.known ", the game has " BoostMemName(bmbB.m) " (" bmbB.m.kind ") there - the boxes and the game's cards may not line up"}
		}
	bmbIdx := {}
	for bmbI, bmbN in BoostMatches(key, bmbAll.hand.cards)
		bmbIdx[bmbN] := 1
	bmbWhy := "no copy of it among the game's cards now", bmbEnc := ""
	for bmbI, bmbB in bmbAll.boxes
		{
		if (!bmbIdx.HasKey(bmbB.n))
			continue
		bmbM := bmbB.m, bmbNm := BoostMemName(bmbM)
		if (ench && bmbM.ench = "")
			{
			bmbWhy := "no copy of it with an enchantment on it"
			continue
			}
		if (!BoostMemBoxOk(key, bmbB.known, bmbNm))
			{
			bmbWhy := "its box (" bmbI ") is known as " bmbB.known " - another card's picture"
			continue
			}
		if (bmbB.grey || bmbM.castable = "0")
			{
			bmbWhy := "it's greyed out (not enough pips)"
			continue
			}
		bmbSrc := BoostSrcOf(bmbM), bmbItem := bmbM.item ? 1 : 0
		;(a copy already enchanted goes on its plain or its sharpened flag, whichever is free - as UseBlade / UseTrap cast it)
		if (!ench && !BoostCopyCanGo(key, bmbSrc, bmbItem, (bmbM.ench != "") ? 1 : sharp, use1, use2))
			{
			bmbWhy := "each copy's casts used this battle"
			continue
			}
		;(ench 0: a plain copy first - one that carries an enchantment already can't take a Sharpen / Potent: it's cast as it
		;is only when no plain copy can go - ench 1 in the answer, UseBlade / UseTrap)
		bmbAt := {x: Round(bmbB.l + bmbB.w / 2), y: Round(bmbB.t + bmbB.h / 2), n: bmbI, of: bmbAll.boxes.Length(), src: bmbSrc, item: bmbItem, name: bmbNm, ench: (bmbM.ench != "") ? 1 : 0}
		if (ench || !bmbAt.ench)
			return bmbAt
		if (!IsObject(bmbEnc))
			bmbEnc := bmbAt
		}
	return IsObject(bmbEnc) ? bmbEnc : {x: "", why: bmbWhy}
	}

;Whether a hand box known as picture known can hold boost key's card the game names name (BoostMemBox): no picture; a
;learned card's the game named so (flag game=) or never named; a slot's - a learned card there the game named so, else the
;slot's own key is key (resources/blade3 for Balanceblade)
BoostMemBoxOk(key, known, name)
	{
	if (known = "")
		return true
	bmoC := ""
	if (InStr(known, "learned/") = 1)
		bmoC := IsFunc("LearnCardOf") ? Func("LearnCardOf").Call(SubStr(known, 9)) : ""
	else if (IsFunc("LearnCardInSlot"))
		bmoC := Func("LearnCardInSlot").Call(StrReplace(known, "/", "\"))
	bmoG := (IsObject(bmoC) && IsFunc("LearnFlag")) ? Func("LearnFlag").Call(bmoC, "game") : ""
	if (bmoG != "")
		return bmoG = name
	if (InStr(known, "learned/") = 1)
		return true
	return BoostMemKey(StrReplace(known, "/", "\")) = key
	}

;A card of the game's hand by its name, for the log (the name on it - CardLearn.ahk LearnMemGame -, else its own)
BoostMemName(m)
	{
	return IsFunc("LearnMemGame") ? Func("LearnMemGame").Call(m) : m.name
	}

;Which copy of boost card key in hand the card at x, y is - UseBlade, UseTrap, with the game's hand read (BoostHand):
;{src ("" the deck's, "tc", "item"), item (1: an item card - never sharpened or made potent), moved (1: that copy can't go
;- its casts used this battle - so x, y are now another copy's that can, plain: one moved to is never sharpened)}; "" none
;that's in hand can go. Its copies all one kind (the same src, item card or not), or the boxes and the game's cards not
;lining up: the first kind of its copies that can go, the deck's first - never sharpened if any is an item card
BoostCopyPick(key, ByRef x, ByRef y, sharp, use1, use2)
	{
	;(every copy in hand one kind - as most often, one copy: a fresh look at the hand can't change which goes, so none is
	;asked for - each is a /hand read for the helper, about 0.1 s)
	bcpF := "", bcpOne := 1
	for bcpI, bcpC in BoostHand[key]
		bcpT := bcpC.src "|" (bcpC.item ? 1 : 0), bcpOne := bcpOne && (bcpF = "" || bcpT = bcpF), bcpF := bcpT
	;(and only while the game's hand holds no other blade or trap - a click found on another boost's box is then moved onto
	;the real card by the look; this look's cached hand: no read)
	bcpHand := bcpOne && IsFunc("VisionCards") ? Func("VisionCards").Call(300, 5000) : "", bcpN := 0
	if (IsObject(bcpHand))
		for bcpI, bcpC in bcpHand.cards
			bcpN += (bcpC.kind = "blade" || bcpC.kind = "trap") ? 1 : 0
	bcpOne := bcpOne && IsObject(bcpHand) && bcpN = BoostHand[key].Length()
	bcpAll := bcpOne ? "" : BoostBoxes()
	if (IsObject(bcpAll))
		{
		bcpIs := {}
		for bcpI, bcpN in BoostMatches(key, bcpAll.hand.cards)
			bcpIs[bcpN] := 1
		bcpAt := "", bcpGo := ""
		for bcpI, bcpB in bcpAll.boxes
			{
			if (!bcpIs.HasKey(bcpB.n))
				continue
			bcpSrc := BoostSrcOf(bcpB.m), bcpItem := bcpB.m.item ? 1 : 0
			if (x >= bcpB.l - 5 && x <= bcpB.l + bcpB.w + 5)
				bcpAt := {src: bcpSrc, item: bcpItem, can: BoostCopyCanGo(key, bcpSrc, bcpItem, sharp, use1, use2), moved: 0}
			;(another copy's box: only one that can go plain - UseBlade / UseTrap never sharpen or make potent a copy moved to)
			else if (!IsObject(bcpGo) && BoostCopyCanGo(key, bcpSrc, bcpItem, 0, use1, use2))
				bcpGo := {src: bcpSrc, item: bcpItem, can: 1, moved: 1, x: Round(bcpB.l + bcpB.w / 2), y: Round(bcpB.t + bcpB.h * 0.45)}
			}
		if (IsObject(bcpAt) && bcpAt.can)
			return bcpAt
		if (IsObject(bcpGo))
			{
			x := bcpGo.x, y := bcpGo.y
			DebugLog("  " key ": the copy found can't go again this battle - its " (bcpGo.src = "" ? "deck" : bcpGo.src) " copy instead, at " x - GameLeft "," y - GameTop)
			return bcpGo
			}
		if (IsObject(bcpAt))
			return ""
		}
	;(one kind, or the boxes and the cards don't line up: by the copies BoostSearch saw - each kind of them in turn, the
	;deck's, then an item card's, then a treasure card's: the first that can go, as BoostCanGo has it)
	bcpSrcs := {}, bcpAny := 0
	for bcpI, bcpC in BoostHand[key]
		bcpSrcs[bcpC.src = "" ? "deck" : bcpC.src] := 1, bcpAny := bcpAny || bcpC.item
	for bcpS in bcpSrcs
		{
		bcpSrc := (bcpS = "deck") ? "" : bcpS
		if (BoostCopyCanGo(key, bcpSrc, bcpAny, sharp, use1, use2))
			return {src: bcpSrc, item: bcpAny, can: 1, moved: 0}
		}
	return ""
	}

;The schools of the aura card just cast, as the game's hand has it (AuraSch: "all", "fire,ice" - one aura card in hand
;read for sure), else "" (yours)
BoostAuraSchools()
	{
	basHand := IsFunc("VisionCards") ? Func("VisionCards").Call(300, 5000) : ""
	basOut := "", basN := 0
	if (IsObject(basHand))
		for basI, basC in basHand.cards
			if (basC.kind = "aura")
				basN += 1, basB := BoostsParse(basC.boosts), basOut := IsObject(basB) ? basB.sch : ""
	return basN = 1 ? basOut : ""
	}

;FindCards, once the pips are read (and before the hand's read for learning: the helper's /hand must know these pictures,
;or a pictured Storm Blade is learned again): the blades and traps of every school this round's hits need, by their
;pictures - SbFound {"<school>/blade" / "<school>/trap": {x, y}}, GbFound {"elementalblade"...: 1} - and blade, trap,
;blade2, trap2 for the log and the discards (BoostPick picks this round's). The schools: a party battle's blader's or
;healer's - and Alt+2's pick of another school's wizard - the hitter's: its planned hit's (HammerPlan, Party.ahk), else its
;school; else yours, every head of the hits in hand (HitHeads: a Balance Hydra's fire, ice and storm) and of every hit in
;the game's hand. Balance's own blade and trap are Balanceblade and Hex (resources\blade3, trap3): its folder isn't
;searched. With the game's hand read (VisionCards), a picture found for a card that isn't in it is a false match - not
;used -, each boost found counts at the % of its card in hand (BoostPctMem) and its copies are noted (BoostHand: a
;treasure or item card's stacks with the deck's). A blade or trap in the game's hand no picture found, that this search is
;for, is found all the same - by the game's hand (BoostMemOnly): UseBlade / UseTrap cast it at its card box (BoostMemBox)
BoostSearch()
	{
	global
	local bsHand, bsWant, bsSeen, bsI, bsS, bsH, bsHh, bsC, bsF, bsX, bsY, bsG, bsK, bsKeys, bsM, bsJ, bsN, bsP, bsSrc, bsLog, bsTr, bsHas, bsB, bsSlot, bsNm
	local bsMem, bsGo, bsMk
	SbFound := {}, GbFound := {}, BoostPctMem := {}, BoostHand := {}, BoostMemOk := 0, BoostMemOnly := {}
	blade := 0, trap := 0, blade2 := 0, trap2 := 0, BladeDir := "", TrapDir := "", bladetype := "", traptype := ""
	if (!IsObject(BoostSrcUsed))
		BoostSrcUsed := {}
	if (!IsObject(BoostSaid))
		BoostSaid := {}
	if (hitschool = "")
		return
	;(the game's hand as the helper read it this look - an older helper's, with no heads or boosts, isn't used here: the
	;cards are played as before)
	bsHand := VisionCards(300, 5000)
	BoostMemOk := (IsObject(bsHand) && (!bsHand.cards.Length() || bsHand.cards[1].nf >= 25)) ? 1 : 0
	if (!BoostMemOk)
		bsHand := ""
	bsWant := [], bsSeen := ","
	if (PartySupport() || (Manual = 1 && HammerSchool != hitschool))
		{
		bsH := HammerPlan != "" ? HammerPlan : HammerSchool
		Loop, Parse, bsH, `,
			if (BadgeNumber(A_LoopField) && !InStr(bsSeen, "," A_LoopField ","))
				bsWant.Push(A_LoopField), bsSeen .= A_LoopField ","
		}
	else
		{
		bsWant.Push(hitschool), bsSeen .= hitschool ","
		;(hit4 only on a picked boss - it's cast on bosses only)
		for bsI, bsH in ["hit4", "hit3", "hit2", "hit1"]
			if (%bsH% == 1 && (bsH != "hit4" || BossChoosen == 1))
				for bsS in HitHeads(bsH).heads
					if (!InStr(bsSeen, "," bsS ","))
						bsWant.Push(bsS), bsSeen .= bsS ","
		if (BoostMemOk)
			for bsI, bsC in bsHand.cards
				{
				bsHh := {}
				if ((bsC.kind = "damage" || bsC.kind = "aoe") && HeadsParse(bsC.heads, bsHh))
					for bsS in bsHh.heads
						if (!InStr(bsSeen, "," bsS ","))
							bsWant.Push(bsS), bsSeen .= bsS ","
				}
		}
	;(the wand's heads too, looked at now - the kill check asks)
	if (wand == 1)
		HitHeads("wand")
	;(the other schools' pictures the helper is asked about from now on this battle - Vision.ahk VisionPicList)
	for bsI, bsS in bsWant
		if (bsS != hitschool && bsS != "balance" && !InStr("," BoostExtra ",", "," bsS ","))
			BoostExtra .= (BoostExtra = "" ? "" : ",") bsS
	for bsI, bsS in bsWant
		{
		if (bsS = "balance")
			continue
		bsF := 0, bsX := "", bsY := ""
		Find("blade", bsF, bsX, bsY, bsS)
		if (bsF == 1)
			SbFound[bsS "/blade"] := {x: bsX, y: bsY}
		bsF := 0, bsX := "", bsY := ""
		Find("trap", bsF, bsX, bsY, bsS)
		if (bsF == 1)
			SbFound[bsS "/trap"] := {x: bsX, y: bsY}
		}
	for bsI, bsG in PlanGroups(bsWant)
		{
		if (Tri(bsG, "blade"))
			GbFound[bsG "blade"] := 1
		if (Tri(bsG, "trap"))
			GbFound[bsG "trap"] := 1
		}
	;(the game's hand read: a picture found for a card it doesn't have is a false match; each one's cards - their % and copies)
	if (BoostMemOk)
		{
		bsKeys := [], bsHas := {}
		for bsK in SbFound
			bsKeys.Push(bsK)
		for bsK in GbFound
			bsKeys.Push(bsK)
		for bsI, bsK in ["blade3", "blade4", "trap3", "feint"]
			if (%bsK% == 1)
				bsKeys.Push(bsK)
		for bsI, bsK in bsKeys
			{
			bsM := BoostMatches(bsK, bsHand.cards)
			if (!bsM.Length())
				{
				if (SbFound.HasKey(bsK))
					SbFound.Delete(bsK)
				else if (GbFound.HasKey(bsK))
					GbFound.Delete(bsK)
				else
					%bsK% := 0
				if (!BoostSaid.HasKey("false|" bsK))
					BoostSaid["false|" bsK] := 1, DebugLog("  the " bsK " picture matched, but the game has no such card in hand - a false match, not used")
				continue
				}
			BoostHand[bsK] := []
			for bsJ, bsN in bsM
				{
				bsC := bsHand.cards[bsN], bsP := BoostCardPct(bsC), bsSrc := BoostSrcOf(bsC), bsHas[bsN] := 1
				BoostHand[bsK].Push({src: bsSrc, item: bsC.item ? 1 : 0, pct: bsP})
				if (bsP != "")
					{
					if (!BoostPctMem.HasKey(bsK) || bsP < BoostPctMem[bsK])
						BoostPctMem[bsK] := bsP
					bsS := bsK "@" (bsSrc = "" ? "deck" : bsSrc)
					if (!BoostPctMem.HasKey(bsS) || bsP < BoostPctMem[bsS])
						BoostPctMem[bsS] := bsP
					}
				}
			}
		;(the game's blades and traps in hand no picture found: found by the game's hand when this search is for them - their
		;slot's key by their schools and % (BoostSlotFor), not one the game says can't be cast now; cast at their card box -
		;UseBlade / UseTrap, BoostMemBox; said once a battle)
		bsMem := {}
		for bsI, bsC in bsHand.cards
			{
			if ((bsC.kind != "blade" && bsC.kind != "trap") || bsHas.HasKey(bsI))
				continue
			bsB := BoostsParse(bsC.boosts), bsNm := BoostMemName(bsC)
			if (!IsObject(bsB))
				continue
			bsSlot := BoostSlotFor(bsC.kind, bsB.sch, bsB.pct, hitschool), bsMk := BoostMemKey(bsSlot)
			bsGo := (bsMk != "" && bsC.castable != "0" && BoostMemWanted(bsMk, bsWant))
			if (bsGo)
				{
				if (!BoostHand.HasKey(bsMk))
					BoostHand[bsMk] := []
				bsP := BoostCardPct(bsC), bsSrc := BoostSrcOf(bsC), bsMem[bsMk] := 1
				BoostHand[bsMk].Push({src: bsSrc, item: bsC.item ? 1 : 0, pct: bsP, ench: (bsC.ench != "") ? 1 : 0})
				if (bsP != "")
					{
					if (!BoostPctMem.HasKey(bsMk) || bsP < BoostPctMem[bsMk])
						BoostPctMem[bsMk] := bsP
					bsS := bsMk "@" (bsSrc = "" ? "deck" : bsSrc)
					if (!BoostPctMem.HasKey(bsS) || bsP < BoostPctMem[bsS])
						BoostPctMem[bsS] := bsP
					}
				}
			if (BoostSaid.HasKey("miss|" bsNm))
				continue
			BoostSaid["miss|" bsNm] := 1
			DebugLog("  in hand (the game): " bsNm " (" bsC.kind " " bsB.sch " " bsB.pct "%) - no picture found it" (bsSlot = "" ? " (no slot is for it - not cast)"
				: " (" bsSlot ")" (bsGo ? ": cast at its card box when the hand's boxes and the game's cards line up" : bsC.castable = "0" ? ": greyed out now" : ": not for this round's hits")))
			}
		;(each found so: its school's (SbFound - no picture spot), its group's (GbFound), every school's (blade3...: its flag)
		for bsK in bsMem
			{
			BoostMemOnly[bsK] := 1
			if (InStr(bsK, "/"))
				SbFound[bsK] := {x: "", y: "", mem: 1}
			else if (RegExMatch(bsK, "^(elemental|spirit)(blade|trap)$"))
				GbFound[bsK] := 1
			else
				%bsK% := 1, %bsK%X := "", %bsK%Y := ""
			}
		;(and Tower Shield the same way - TowerMem)
		TowerMem(bsHand)
		}
	;(this look's: the first school blade and trap in the schools' order, the first group's)
	for bsI, bsS in bsWant
		{
		if (!blade && SbFound.HasKey(bsS "/blade"))
			blade := 1, BladeDir := bsS, BladeX := SbFound[bsS "/blade"].x, BladeY := SbFound[bsS "/blade"].y
		if (!trap && SbFound.HasKey(bsS "/trap"))
			trap := 1, TrapDir := bsS, trapX := SbFound[bsS "/trap"].x, trapY := SbFound[bsS "/trap"].y
		}
	for bsI, bsG in PlanGroups(bsWant)
		{
		if (!blade2 && GbFound.HasKey(bsG "blade"))
			blade2 := 1, bladetype := bsG "blade"
		if (!trap2 && GbFound.HasKey(bsG "trap"))
			trap2 := 1, traptype := bsG "trap"
		}
	;(said when it's more than your own school's - a plain one-school battle's log as before)
	if (bsWant.Length() != 1 || bsWant[1] != hitschool || BoostMemOk)
		{
		;(one found by the game's hand alone - no picture: "(no picture)")
		bsLog := "", bsTr := ""
		for bsK in SbFound
			if (InStr(bsK, "/blade"))
				bsLog .= (bsLog = "" ? "" : ", ") bsK (BoostMemOnly.HasKey(bsK) ? " (no picture)" : "")
			else
				bsTr .= (bsTr = "" ? "" : ", ") bsK (BoostMemOnly.HasKey(bsK) ? " (no picture)" : "")
		for bsK in GbFound
			if (InStr(bsK, "blade"))
				bsLog .= (bsLog = "" ? "" : ", ") bsK (BoostMemOnly.HasKey(bsK) ? " (no picture)" : "")
			else
				bsTr .= (bsTr = "" ? "" : ", ") bsK (BoostMemOnly.HasKey(bsK) ? " (no picture)" : "")
		for bsI, bsK in ["blade3", "blade4"]
			if (%bsK% == 1)
				bsLog .= (bsLog = "" ? "" : ", ") bsK (BoostMemOnly.HasKey(bsK) ? " (no picture)" : "")
		for bsI, bsK in ["trap3", "feint"]
			if (%bsK% == 1)
				bsTr .= (bsTr = "" ? "" : ", ") bsK (BoostMemOnly.HasKey(bsK) ? " (no picture)" : "")
		bsS := ""
		for bsI, bsH in bsWant
			bsS .= (bsS = "" ? "" : ",") bsH
		DebugLog("  boosts searched for " (bsS = "" ? "no school (the hitter's isn't known: only every school's)" : bsS) ": " (bsLog = "" ? "no blade" : bsLog) "; traps: " (bsTr = "" ? "none" : bsTr) (BoostMemOk ? " (the game's hand)" : ""))
		}
	}

;---- Tower Shield by the game's hand (2026-10-25) ----
;Live 18:53 (1440p, UI 1.144): the game's hand held two Tower Shields while every round's "cards:" line said tower=0 -
;ui1.144\resources\tower.png is another card's picture (a Spirit Shield's, learned before Tower Shields were), so no picture
;found them, and the shield went out neither to defend you (EnemySpells.ahk EnemyDefend), on an ally or the hitter
;(Party.ahk PartyShield), nor as the filler when nothing else could go. BoostSearch, the game's hand read for sure (hand):
;the tower picture found with no shield in the game's hand at all is a false match - not used; a Tower Shield the game has
;(TowerMatches) that no picture found is found all the same when one can be cast now - tower 1, no picture spot,
;BoostMemOnly["tower"]: UseOnSelf / UseOnHammer cast it at its card box (Autofarmer.ahk UseMemAt - BoostMemBox, only while
;the hand's boxes and the game's cards line up for sure). Said once a battle. The slot's picture is put right by the
;learner meanwhile (CardLearn.ahk LearnBoostPicFix)
TowerMem(hand)
	{
	global tower, towerX, towerY, BoostMemOnly, BoostSaid
	twmWard := 0
	for twmI, twmC in hand.cards
		twmWard += (twmC.kind = "ward") ? 1 : 0
	twmM := TowerMatches(hand.cards)
	if (tower == 1)
		{
		if (!twmWard)
			{
			tower := 0
			if (!BoostSaid.HasKey("false|tower"))
				BoostSaid["false|tower"] := 1, DebugLog("  the tower picture matched, but the game has no shield in hand - a false match, not used")
			}
		;(a Tower Shield in hand and another shield too - a school's or a team's, which the picture may be on: as shipped at
		;UI 1.144 resources\tower is a Spirit Shield's - the Tower Shield at its card box when the boxes line up for sure,
		;else the picture's spot as before - Autofarmer.ahk UseMemAt, 2026-10-25)
		else if (twmM.Length() && twmM.Length() < twmWard)
			BoostMemOnly["tower"] := 1
		return
		}
	if (!twmM.Length())
		return
	twmGo := ""
	for twmI, twmN in twmM
		if (twmGo = "" && hand.cards[twmN].castable != "0")
			twmGo := twmN
	twmC := hand.cards[twmGo != "" ? twmGo : twmM[1]], twmNm := BoostMemName(twmC)
	if (twmGo != "")
		tower := 1, towerX := "", towerY := "", BoostMemOnly["tower"] := 1
	if (!BoostSaid.HasKey("miss|" twmNm))
		BoostSaid["miss|" twmNm] := 1, DebugLog("  in hand (the game): " twmNm " (" twmC.kind " " twmC.value ") - no picture found it (resources\tower)"
			. (twmGo != "" ? ": cast at its card box when the hand's boxes and the game's cards line up" : ": greyed out now"))
	}

;The planned hit's share of damage boost key fits (1: every school's boost)
BoostShare(key)
	{
	global PlanHeads
	if (BoostSchools(key) = "all")
		return 1
	if (!IsObject(PlanHeads) || PlanHeads.total <= 0)
		return 0
	bshN := 0
	for bshS, bshV in PlanHeads.heads
		if (BoostFits(key, bshS))
			bshN += bshV
	return bshN / PlanHeads.total
	}

;Of the boosts in list (SbFound / GbFound) of kind ("blade" / "trap"), the one that adds the most to the planned hit and
;can still go (BoostCanGo): its % (BoostPctFor) x the share of the hit's damage it fits (BoostShare) - ties: your school's,
;then as BadgeNumber orders them. "" none fits
BoostBest(list, kind)
	{
	global hitschool
	bbBest := "", bbGain := 0, bbRank := 99
	for bbK in list
		{
		if (BoostKind(bbK) != kind)
			continue
		bbG := BoostPctFor(bbK) * BoostShare(bbK)
		if (bbG <= 0 || !BoostCanGo(bbK))
			continue
		bbS := InStr(bbK, "/") ? SubStr(bbK, 1, InStr(bbK, "/") - 1) : ""
		bbR := (bbS != "" && bbS = hitschool) ? 0 : (bbS != "") ? BadgeNumber(bbS) : InStr(bbK, "elemental") ? 8 : 9
		if (bbG > bbGain || (bbG = bbGain && bbR < bbRank))
			bbBest := bbK, bbGain := bbG, bbRank := bbR
		}
	return bbBest
	}

;The hit planned, for the log: "Hydra (hit3)", "hit3", "the hitter's", "learned hit <id>"
PlanName()
	{
	global PlanHit, hitschool, PlanWait
	if (PlanHit = "hitter")
		return "the hitter's hit"
	if (InStr(PlanHit, "learned/") = 1)
		return "learned hit " SubStr(PlanHit, 9)
	pnN := (IsFunc("DashShortName") && RegExMatch(PlanHit, "^hit\d$")) ? Func("DashShortName").Call(PlanHit, hitschool) : ""
	if (PlanHit = "" && PlanWait != "")
		return PlanWait ", waiting for its pips"
	return (pnN != "" && pnN != PlanHit) ? pnN " (" PlanHit ")" : PlanHit != "" ? PlanHit : "no hit"
	}

;The damage hit hitN would deal this round against the enemies left (PlanChoose: the planned hit deals the most) -
;HitDamage with the blades and traps on and those in hand that can still go (each once, at its %: SbFound, GbFound,
;blade3, blade4, trap3 - traps on the enemy this round's go on, TrapPick, else the one they're on: TrapSlot - the boss's,
;the one with the most health; counted with solotraps:1 only), an enchant in hand on it: an all-enemies hit on each enemy
;left (its health the most it can take), a one-enemy hit on the one it does the most to; their health not read: an
;all-enemies hit times the plates found
PlanProject(hitN)
	{
	global
	local ppKeepB, ppKeepT, ppB, ppT, ppK, ppL, ppI, ppJ, ppE, ppD, ppSum, ppBest, ppOne, ppUe, ppHh, ppKeys, ppTs
	ppKeepB := AppliedBlades, ppKeepT := BossTraps
	ppB := AppliedBlades.Clone(), ppT := BossTraps.Clone(), ppKeys := []
	for ppI, ppL in [SbFound, GbFound]
		for ppK in ppL
			ppKeys.Push(ppK)
	for ppI, ppK in ["blade3", "blade4", "trap3"]
		if (%ppK% == 1)
			ppKeys.Push(ppK)
	for ppI, ppK in ppKeys
		if (BoostCanGo(ppK) && !ppB.HasKey(ppK) && !ppT.HasKey(ppK))
			{
			if (BoostKind(ppK) = "trap")
				ppT[ppK] := BoostPctFor(ppK)
			else
				ppB[ppK] := BoostPctFor(ppK)
			}
	AppliedBlades := ppB, BossTraps := ppT
	ppHh := HitHeads(hitN), ppUe := (enchant >= 1 && !ppHh.item)
	ppOne := (ppHh.one != "") ? ppHh.one : (Stat(hitschool "." hitN "target") = 1)
	if (IsObject(EnemyHP) && EnemyHP.Length())
		{
		ppSum := 0, ppBest := 0, ppTs := (BossChoosen != 1 && TrapPick) ? TrapPick : TrapSlot
		for ppI, ppE in EnemyHP
			{
			ppD := Min(HitDamage(hitN, ppUe, ppI == ppTs), ppE.cur)
			ppSum += ppD, ppBest := Max(ppBest, ppD)
			}
		ppD := ppOne ? ppBest : ppSum
		}
	else
		ppD := HitDamage(hitN, ppUe, BossChoosen == 1) * ((ppOne || EnemyPlates.Length() < 1) ? 1 : EnemyPlates.Length())
	AppliedBlades := ppKeepB, BossTraps := ppKeepT
	return ppD
	}

;The hit this round's boosts are for (BoostPick) - the one CastBestHit casts first: the kill check's own pick when it can
;kill now; with the game's hand read this look (the user, 2026-10-24), the one dealing the most (PlanProject) of hit4 (a
;picked boss only), hit3, hit2, hit1 in hand you can pay for now (pips saved for one: that one), else of those in hand;
;without it as ever: the first of them you can pay for and aren't saving pips against, else the one pips are saved for,
;else the first in hand. None in hand: the strongest learned hit in no slot ("learned/<id>"); none: ""
PlanChoose()
	{
	global
	local pcL, pcI, pcH, pcBest, pcBestV, pcV, pcLh, pcPass
	if (RegExMatch(KillHit, "^hit[1-4]$"))
		if (%KillHit% == 1)
			return KillHit
	pcL := (BossChoosen == 1) ? ["hit4", "hit3", "hit2", "hit1"] : ["hit3", "hit2", "hit1"]
	if (BoostMemOk)
		{
		pcBest := "", pcBestV := -1
		Loop, 2
			{
			pcPass := A_Index
			for pcI, pcH in pcL
				if (%pcH% == 1 && (pcPass = 2 || (PipSaveFor != "" ? PipSaveFor = pcH : Affordable(pcH))))
					{
					pcV := PlanProject(pcH)
					if (pcV > pcBestV)
						pcBest := pcH, pcBestV := pcV
					}
			if (pcBest != "")
				return pcBest
			}
		}
	else
		{
		for pcI, pcH in pcL
			if (%pcH% == 1 && Affordable(pcH) && (PipSaveFor = "" || PipSaveFor = pcH))
				return pcH
		if (RegExMatch(PipSaveFor, "^hit[1-4]$"))
			if (%PipSaveFor% == 1)
				return PipSaveFor
		for pcI, pcH in pcL
			if (%pcH% == 1)
				return pcH
		}
	if (IsFunc("LearnHitCards") && LastHandAnswer != "")
		{
		pcLh := Func("LearnHitCards").Call(LastHandAnswer)
		if (pcLh.Length())
			return "learned/" pcLh[1].id
		}
	return ""
	}

;Right before the round's cards are played (after the kill check - it can name the hit, and PipSaveFor is this round's):
;the planned hit (PlanHit, PlanHeads, PlanList: its schools - a party's supports boost for them, Party.ahk) - a blader's or
;healer's, Alt+2's pick's: the hitter's -, and of the blades and traps found (BoostSearch) the ones the chain casts: the
;school blade and trap that add the most to it (blade, BladeDir and its flags BladeU1/2; trap, TrapDir, TrapU1/2), the
;group's (blade2, bladetype, Blade2U1/2; trap2, traptype, Trap2U1/2); every school's (blade3, blade4, trap3, feint) as
;found. A hit of two or more schools (Hydra): only the blade and the trap that add the most go this round - Elemental Blade
;(all three heads) before Balanceblade, before a Storm Blade (one head)
BoostPick()
	{
	global
	local bpL, bpS, bpK, bpF, bpN, bpBest, bpG, bpC, bpI, bpFit, bpNot, bpLog, bpLc, bpCand, bpMax, bpWho, bpHand, bpBestV, bpHh
	PlanHit := "", PlanHeads := "", PlanList := "", BoostOneOfOff := {}, PlanWait := ""
	if (hitschool = "")
		return
	if (PartySupport() || (Manual = 1 && HammerSchool != hitschool))
		{
		PlanHit := "hitter", PlanHeads := {heads: {}, total: 0, sure: 0, src: "the hitter's"}
		bpL := HammerPlan != "" ? HammerPlan : (BadgeNumber(HammerSchool) ? HammerSchool : "")
		Loop, Parse, bpL, `,
			if (BadgeNumber(A_LoopField) && !PlanHeads.heads.HasKey(A_LoopField))
				PlanHeads.heads[A_LoopField] := 1, PlanHeads.total += 1
		}
	else
		{
		PlanHit := PlanChoose()
		if (InStr(PlanHit, "learned/") = 1)
			PlanHeads := LearnHitHeads(IsFunc("LearnCardOf") ? Func("LearnCardOf").Call(SubStr(PlanHit, 9)) : "")
		else if (PlanHit != "")
			PlanHeads := HitHeads(PlanHit)
		;(no hit the pictures place or the pips pay for - a greyed Hydra waiting for its pips: the game's hand names it,
		;and the boosts go on for that one while the pips come - 2026-10-25: Elemental Blade and Trap held back two
		;rounds with Hydra greyed in hand. The strongest of the hand's hits; nothing's cast for it till it can be)
		if (PlanHit = "" && BoostMemOk && IsFunc("VisionCards"))
			{
			bpHand := Func("VisionCards").Call(0, 5000), bpBestV := -1
			if (IsObject(bpHand) && IsObject(bpHand.cards))
				for bpI, bpC in bpHand.cards
					if ((bpC.kind = "damage" || bpC.kind = "aoe") && bpC.num != "" && bpC.num + 0 > bpBestV)
						{
						bpHh := {}
						if (HeadsParse(bpC.heads, bpHh))
							bpBestV := bpC.num + 0, PlanHeads := bpHh, PlanHeads.src := "the game's hand", PlanWait := (bpC.display != "" ? bpC.display : bpC.name)
						}
			}
		if (!IsObject(PlanHeads) || PlanHeads.total <= 0)
			{
			PlanHeads := {heads: {}, total: 1, sure: 0, src: "your school's"}
			PlanHeads.heads[hitschool] := 1
			}
		;(its schools for the party's supports only when they're known - the game's, PlayerStats.txt's heads: one taken as
		;your school's goes out blank, so a support never throws a blade away for a guess - BoostMisfitDiscard)
		if (PlanHeads.sure)
			for bpI, bpS in HeadsOrder(PlanHeads.heads)
				PlanList .= (PlanList = "" ? "" : ",") bpS
		}
	;(the school blade and trap, the group's)
	blade := 0, BladeDir := "", BladeU1 := "", BladeU2 := ""
	bpK := BoostBest(SbFound, "blade")
	if (bpK != "")
		bpF := KeyFlags(bpK), blade := 1, BladeDir := SubStr(bpK, 1, InStr(bpK, "/") - 1), BladeU1 := bpF[1], BladeU2 := bpF[2]
	trap := 0, TrapDir := "", TrapU1 := "", TrapU2 := ""
	bpK := BoostBest(SbFound, "trap")
	if (bpK != "")
		bpF := KeyFlags(bpK), trap := 1, TrapDir := SubStr(bpK, 1, InStr(bpK, "/") - 1), TrapU1 := bpF[1], TrapU2 := bpF[2]
	blade2 := 0, Blade2U1 := "", Blade2U2 := ""
	bpK := BoostBest(GbFound, "blade")
	if (bpK != "")
		bpF := KeyFlags(bpK), blade2 := 1, bladetype := bpK, Blade2U1 := bpF[1], Blade2U2 := bpF[2]
	trap2 := 0, Trap2U1 := "", Trap2U2 := ""
	bpK := BoostBest(GbFound, "trap")
	if (bpK != "")
		bpF := KeyFlags(bpK), trap2 := 1, traptype := bpK, Trap2U1 := bpF[1], Trap2U2 := bpF[2]
	bpN := 0
	for bpS in PlanHeads.heads
		bpN += 1
	;(what fits the plan, for the log - said when it's more than one school, the game's hand was read, or for the hitter)
	bpWho := (bpN >= 2 || BoostMemOk || PlanHit = "hitter")
	if (bpWho)
		{
		bpFit := "", bpNot := ""
		for bpI, bpLc in [SbFound, GbFound]
			for bpK in bpLc
				{
				bpG := BoostShare(bpK)
				if (bpG > 0)
					bpFit .= (bpFit = "" ? "" : ", ") bpK " " BoostPctFor(bpK) "%" (bpG < 1 ? " (" BoostHeadsText(bpK) ")" : "")
				else
					bpNot .= (bpNot = "" ? "" : ", ") bpK
				}
		for bpI, bpK in ["blade3", "blade4", "trap3", "feint"]
			if (%bpK% == 1)
				bpFit .= (bpFit = "" ? "" : ", ") bpK " " BoostPctFor(bpK) "%"
		}
	;(a hit of two or more schools: the one blade and the one trap that add the most this round)
	if (bpN >= 2)
		{
		BoostOneOf([["blade", BladeDir "/blade"], ["blade2", bladetype], ["blade3", "blade3"], ["blade4", "blade4"]], "blade")
		BoostOneOf([["trap", TrapDir "/trap"], ["trap2", traptype], ["trap3", "trap3"]], "trap")
		}
	if (bpWho)
		{
		bpLog := ""
		for bpI, bpC in [["feint", "feint"], ["trap", TrapDir "/trap"], ["trap2", traptype], ["trap3", "trap3"], ["blade", BladeDir "/blade"], ["blade2", bladetype], ["blade3", "blade3"], ["blade4", "blade4"]]
			{
			bpS := bpC[1]
			if (%bpS% == 1 && (BoostKind(bpC[2]) = "blade" || TrapOn == 1) && BoostCanGo(bpC[2]))
				bpLog .= (bpLog = "" ? "" : ", ") bpC[2]
			}
		DebugLog("  plan: " PlanName() (PlanHeads.total > 0 && PlanHit != "hitter" ? ": " HeadsText(PlanHeads) : PlanList != "" ? " (" PlanList ")" : "")
			. (PlanHit = "hitter" ? " - its schools: " (HammerPlan != "" ? HammerPlan " (its planned hit)" : HammerSchool != "" ? HammerSchool : "not known") : "")
			. " - fits: " (bpFit = "" ? "nothing in hand" : bpFit) (bpNot != "" ? " - not for it: " bpNot : "") "; this round: " (bpLog = "" ? "none" : bpLog))
		}
	}

;"1 of 3 heads" - how many of the planned hit's heads boost key fits (BoostPick's log)
BoostHeadsText(key)
	{
	global PlanHeads
	bhtN := 0, bhtF := 0
	for bhtS in PlanHeads.heads
		bhtN += 1, bhtF += BoostFits(key, bhtS) ? 1 : 0
	return bhtF " of " bhtN " heads"
	}

;Of the battle code's flags in list ([its variable's name, its boost key]) of kind ("blade" / "trap") set (1) whose boost
;can go, only the one adding the most to the planned hit stays set this round (ties: list's order - the chain's); the
;others 0 - noted (BoostOneOfOff[kind]) and set again if the one kept can't be cast after all (BoostOneOfBack)
BoostOneOf(list, kind)
	{
	global
	local booI, booP, booV, booK, booG, booBest, booBestG, booOff
	booBest := "", booBestG := -1, booOff := []
	for booI, booP in list
		{
		booV := booP[1], booK := booP[2]
		if (%booV% != 1)
			continue
		if (!BoostCanGo(booK))
			{
			%booV% := 0
			continue
			}
		booG := BoostPctFor(booK) * BoostShare(booK)
		if (booG > booBestG)
			booBest := booV, booBestG := booG
		}
	for booI, booP in list
		{
		booV := booP[1]
		if (booV != booBest)
			{
			if (%booV% == 1)
				booOff.Push(booV)
			%booV% := 0
			}
		}
	if (!IsObject(BoostOneOfOff))
		BoostOneOfOff := {}
	BoostOneOfOff[kind] := booOff
	}

;The flags of kind ("blade" / "trap") BoostOneOf took off this round set again: the one it kept can't be cast after all
;(no copy of it in hand can go now - BoostCopyPick: UseBlade, UseTrap), so the chain goes on to the next that can
BoostOneOfBack(kind)
	{
	global
	local boobI, boobV, boobL
	if (!IsObject(BoostOneOfOff) || !IsObject(BoostOneOfOff[kind]) || !BoostOneOfOff[kind].Length())
		return
	boobL := ""
	for boobI, boobV in BoostOneOfOff[kind]
		%boobV% := 1, boobL .= (boobL = "" ? "" : ", ") boobV
	BoostOneOfOff[kind] := []
	DebugLog("  the " kind "s held back this round can go instead: " boobL)
	}

;The wand's card isn't cast while it would use up a blade or trap on you meant for the planned hit - both their heads the
;game's (or PlayerStats.txt's): a boost on that fits a head of each. Else (not known) it's cast, as before
WandWastes()
	{
	global
	local wwW, wwI, wwL, wwK, wwV, wwS, wwT
	if (!IsObject(PlanHeads) || !PlanHeads.sure || !RegExMatch(PlanHit, "^hit[1-4]$"))
		return false
	wwW := HitHeads("wand")
	if (!wwW.sure)
		return false
	for wwI, wwL in [AppliedBlades, BossTraps]
		for wwK, wwV in wwL
			for wwS in wwW.heads
				if (BoostFits(wwK, wwS))
					for wwT in PlanHeads.heads
						if (BoostFits(wwK, wwT))
							{
							DebugLog("  wand not cast: it would use up " BoostBase(wwK) " (" wwV "%) meant for " PlanName())
							return true
							}
	return false
	}

;A party battle's blader or healer (the user, 2026-10-24): a blade in hand - the game's - that boosts neither the hitter's
;planned hit (its schools as the hitter knows them for sure: HammerPlan, Party.ahk - not heard yet, round 1 before its
;first plan, a plan it isn't sure of, an older bot: nothing goes, a discard can't be undone) nor this wizard's own school
;is right-clicked away, by its box (a fresh look at the hand laid on the game's cards - BoostBoxes); never a treasure
;card, never one you said never to discard (Spells tab), nothing while you play; once a round, at most discardmax.
;Returns how many
BoostMisfitDiscard()
	{
	global
	local bmdAll, bmdWant, bmdI, bmdB, bmdP, bmdC, bmdLc, bmdDid, bmdMost, bmdS, bmdFits, bmdK, bmdO, bmdX, bmdY
	if (BoostMisfitDone || !BoostMemOk || !Stat("discardunused") || LearnAll)
		return 0
	BoostMisfitDone := 1
	;(the hitter's plan only - never its school taken for it)
	bmdWant := HammerPlan
	if (bmdWant = "" || hitschool = "" || (IsFunc("PlayerActing") && Func("PlayerActing").Call()))
		return 0
	bmdAll := BoostBoxes()
	if (!IsObject(bmdAll))
		return 0
	bmdDid := 0, bmdMost := StatOr("discardmax", 3) + 0, bmdI := 1
	while (bmdI <= bmdAll.boxes.Length() && bmdDid < bmdMost)
		{
		bmdB := bmdAll.boxes[bmdI], bmdC := bmdB.m, bmdP := BoostsParse(bmdC.boosts), bmdLc := ""
		if (InStr(bmdB.known, "learned/") = 1 && IsFunc("LearnCardOf"))
			bmdLc := Func("LearnCardOf").Call(SubStr(bmdB.known, 9))
		else if (bmdB.known != "" && IsFunc("LearnCardInSlot"))
			bmdLc := Func("LearnCardInSlot").Call(StrReplace(bmdB.known, "/", "\"))
		bmdFits := !IsObject(bmdP) || bmdP.sch = "all"
		if (!bmdFits)
			Loop, Parse, % bmdP.sch, `,
				if (A_LoopField = hitschool || InStr("," bmdWant ",", "," A_LoopField ","))
					bmdFits := true
		if (bmdC.kind != "blade" || bmdFits || bmdC.tc || (IsObject(bmdLc) && (Func("LearnHasFlag").Call(bmdLc, "hold") || Func("LearnHasFlag").Call(bmdLc, "tc"))))
			{
			bmdI += 1
			continue
			}
		bmdX := Round(bmdB.l + bmdB.w / 2), bmdY := Round(bmdB.t + bmdB.h * 0.6)
		MoveToCard(bmdX, bmdY)
		s(Stats.HasKey("clickwait") ? Stats["clickwait"] : 40)
		Click, right
		bmdDid += 1
		DebugLog("  Discarded " (IsFunc("LearnMemGame") ? Func("LearnMemGame").Call(bmdC) : bmdC.name) " - it boosts " bmdP.sch ", not the hitter's " bmdWant " nor your " hitschool " (right-click at " bmdX - GameLeft "," bmdY - GameTop ")")
		bmdAll.boxes.RemoveAt(bmdI)
		for bmdK, bmdO in bmdAll.boxes
			bmdO.l += (bmdK < bmdI ? HalfPitch : -HalfPitch)
		s(Stat("discardafter"))
		}
	if (bmdDid)
		CenterMouse(), VisionForget()
	return bmdDid
	}

;Blades only count toward our hits when they went on our own wizard: the hammer is our school icon
;(Bladestorm buffs the whole team). An ally hammer, a manual Alt+2 hammer or no player found -> not counted
BladeOnUs(card)
	{
	if (card = "blade4")
		return true
	return (school != "") && (school = hitschool) && (Abs(hammerX - schoolX) < Px(10)) && (Abs(hammerY - schoolY) < Px(10))
	}

;A hit uses up the hammer's blades and the boss's traps. With reboost:1 the battle code may also cast
;its blades/traps again for the next hit (normally each is cast once per battle). The hits counted, and the round of the
;last (the game's log): a party's bladers and healers see them - their blades on this wizard are spent (Party.ahk); a
;blader's or healer's own blades went on the hitter: cast again after the hitter's hit, not its own.
;hh: the hit's heads (HitHeads, LearnHitHeads). Known (the game's, or PlayerStats.txt's): only the blades and traps that
;fit one of its schools go - a Power Nova leaves an Elemental Blade on, a Hydra takes it; one whose schools aren't known
;goes - and the party's told its schools (PartyLastSch: a support's blades that fit none stay on); with reboost:1 only
;those are cast again, and the blades cast on you that weren't seen there (BoostUnrec: UseBlade) that fit it. Not known:
;all of them, as before
ConsumeBoosts(hh := "")
	{
	cbSure := IsObject(hh) && hh.sure && hh.total > 0
	cbGone := []
	if (cbSure)
		{
		cbStill := ""
		for cbI, cbList in [AppliedBlades, BossTraps]
			{
			cbOut := []
			for cbKey in cbList
				{
				cbFit := (BoostSchools(cbKey) = "")
				for cbS in hh.heads
					if (BoostFits(cbKey, cbS))
						cbFit := true
				if (cbFit)
					cbOut.Push(cbKey)
				else
					cbStill .= (cbStill = "" ? "" : ", ") cbKey
				}
			for cbJ, cbKey in cbOut
				cbList.Delete(cbKey), cbGone.Push(cbKey)
			}
		PartyLastSch := ""
		for cbS in hh.heads
			PartyLastSch .= (PartyLastSch = "" ? "" : ",") cbS
		if (cbStill != "")
			{
			cbText := ""
			for cbJ, cbKey in cbGone
				cbText .= (cbText = "" ? "" : ", ") cbKey
			DebugLog("  used up by " HeadsText(hh) ": " (cbText = "" ? "nothing" : cbText) "; still on: " cbStill)
			}
		}
	else
		{
		AppliedBlades := {}
		BossTraps := {}
		PartyLastSch := ""
		}
	PartyHits := (PartyHits ? PartyHits : 0) + 1, PartyHitR := (BlRound ? BlRound : 0) + 1
	if (Stat("reboost") == 1 && !PartySupport())
		{
		if (!cbSure)
			ResetUsed()
		else
			{
			;(and each blade cast on you that wasn't seen there - your plate or badge not read that round: BoostUnrec - that
			;fits one of its schools, or whose schools aren't known: used up with it as well)
			cbReset := cbGone.Clone(), cbLeft := []
			for cbJ, cbKey in (IsObject(BoostUnrec) ? BoostUnrec : [])
				{
				cbFit := (BoostSchools(cbKey) = "")
				for cbS in hh.heads
					if (BoostFits(cbKey, cbS))
						cbFit := true
				if (cbFit)
					cbReset.Push(cbKey)
				else
					cbLeft.Push(cbKey)
				}
			BoostUnrec := cbLeft
			for cbJ, cbKey in cbReset
				{
				;(a treasure or item card's copy: its own once-a-battle; the deck's: its sharpened or plain flag)
				if (RegExMatch(cbKey, "@([a-z]+)\+?$", cbM))
					{
					if (IsObject(BoostSrcUsed))
						BoostSrcUsed.Delete(BoostBase(cbKey) "@" cbM1)
					}
				else if (IsObject(cbF := KeyFlags(cbKey)))
					UsedFlagSet(SubStr(cbKey, 0) = "+" ? cbF[1] : cbF[2], 0)
				}
			}
		}
	}

;Returns [{cur, max}, ...] for every "current/max" in the OCR text, or "" if anything health-like couldn't be read
ParseHealth(text)
	{
	static pair := "(?<![\d,.])(\d{1,3}(?:,\d{3})+|\d+)/(\d{1,3}(?:,\d{3})+|\d+)(?![\d,])"
	text := RegExReplace(text, "(\d)\s*([,./])\s*(?=\d)", "$1$2")
	text := RegExReplace(text, "(\d)\.(?=\d{3}(?!\d))", "$1,")
	list := []
	pos := 1
	while (pos := RegExMatch(text, pair, m, pos))
		{
		cur := StrReplace(m1, ",") + 0
		mx := StrReplace(m2, ",") + 0
		if (mx <= 0) || (cur < 1) || (cur > mx)
			return ""
		list.Push({cur: cur, max: mx})
		pos += StrLen(m)
		}
	;Anything but a space touching a pair, or a digit (or l/I/| standing in for a 1) near it, means part of a number was misread
	rest := RegExReplace(text, pair, "#")
	if (list.Length() < 1 || list.Length() > 4 || RegExMatch(rest, "\d{3,}|\d/|/\d|[^\s#]#|#[^\s#]|\d[ \t]*#|#[ \t]*\d|[lI|][ \t]*#"))
		return ""
	;A health line holds exactly one pair and nothing else
	Loop, Parse, rest, `n, `r
		{
		if (InStr(A_LoopField, "#")) && (RegExMatch(A_LoopField, "#.*#") || RegExMatch(A_LoopField, "[A-Za-z]"))
			return ""
		}
	return list
	}

;An OCR line of an enemy nameplate along the top: a name on the plates' row - its top ~27 and ~15 tall at UI scale 1,
;the same at 1440p (UI 1.144: top 31, 17 tall) and 1920x1200 (UI 1.265: top 34, 19 tall) - or a plate's health line
;under it (top ~47; OCR doesn't always read it). Not by where the plates sit across: their spacing differs with the
;window (511 at 1440p, 331 at 1920x1200, at UI scale 1). A mob's floating name over its head can reach up into the
;strip, but it's taller (~22) or lower; its RANK line never counts. rects: unused (the strip's lines)
OnPlateRow(r, rects := "")
	{
	if (RegExMatch(r.text, "i)^\W*RANK\b"))
		return false
	top := (r.y - GameTop) / UiScale, tall := r.h / UiScale
	if (IsHealthLine(r.text))
		return Abs(top - 47) <= 7 && tall <= 20
	return Abs(top - 27) <= 5 && Abs(tall - 15) <= 3
	}

;OCR line kinds: a plate's name line (letters, no digits) or its health line ("current/max")
IsNameLine(t)
	{
	return RegExMatch(t, "[A-Za-z]{2,}") && !RegExMatch(t, "\d")
	}

IsHealthLine(t)
	{
	return RegExMatch(t, "\d\s*/\s*\d|\d{3,}")
	}

;Two OCR line boxes overlap side to side (and, with sameRow, top to bottom too)
BoxesOverlap(a, b, sameRow)
	{
	if (a.x > b.x + b.w) || (b.x > a.x + a.w)
		return false
	return !sameRow || !((a.y > b.y + b.h) || (b.y > a.y + a.h))
	}

SameHealth(a, b)
	{
	if (!IsObject(a) || !IsObject(b) || a.Length() != b.Length())
		return false
	for i, e in a
		{
		if (e.cur != b[i].cur) || (e.max != b[i].max)
			return false
		}
	return true
	}

;Reads every enemy's health off the nameplate strip. Windows OCR sometimes drops a line from a wide
;image, so: find the plates from every name and health line seen at two sizes, then read each plate's
;health on its own at both sizes. Anything that doesn't add up -> false (health unknown)
ReadEnemyHealth()
	{
	EnemyHP := "", EnemyPlates := [], EnemyPlatesAt := A_TickCount
	BossSlot := 0, TrapSlot := 0
	;platestrip is in pixels at UI scale 1: the plates grow with the UI
	stripH := Round(Stat("platestrip") * UiScale)
	if (stripH > GameH)
		stripH := GameH
	;OCR images can't be wider than 10000px, keep the two scales clearly different within that
	maxScale := 9900 / GameW
	scale1 := Stat("ocrscale")
	if (scale1 <= 0)
		scale1 := 1
	scale2 := scale1 + 1
	if (scale2 > maxScale)
		scale2 := maxScale
	if (scale1 > scale2 - 0.5)
		scale1 := scale2 - 0.5
	if (scale1 <= 0.5)
		{
		HealthStatus := "The game window is too wide to read health at two different sizes"
		return false
		}
	MouseMove, GameRight - 20, ScreenY, 0

	;1) Plates: name lines (deduped across both reads), each with the health line under it if one was seen
	names := [], healths := [], seen := "", offRow := ""
	Loop, 2
		{
		stripRead := A_Index
		seen := OcrRect(GameLeft, GameTop, GameW, stripH, "en", (A_Index == 1) ? scale1 : scale2, rects)
		if (ErrorLevel)
			{
			HealthStatus := ErrorLevel
			return false
			}
		for i, r in rects
			{
			;(not the Shop button in the top left corner - its "SHOP" reads like an enemy's name)
			if (r.x + r.w / 2 < GameLeft + Px(85) || RegExMatch(r.text, "i)^\W*(SHOP|EARN\W*CROWNS|UPGRADE\W*NOW)\W*$"))
				continue
			;(only the plates' own row - not a mob's floating name over its head, which can reach into the strip)
			if (!OnPlateRow(r, rects))
				{
				if (stripRead = 1 && IsNameLine(r.text))
					offRow .= (offRow = "" ? "" : ", ") r.text " at " r.x - GameLeft "," r.y - GameTop
				continue
				}
			if (IsHealthLine(r.text))
				healths.Push(r)
			else if (IsNameLine(r.text))
				names.Push(r)
			}
		}
	plates := []
	for i, n in names
		{
		dupe := false
		for j, p in plates
			{
			if (BoxesOverlap(p.name, n, true))
				dupe := true
			}
		if (!dupe)
			plates.Push({name: n, health: ""})
		}
	for i, hl in healths
		{
		owner := ""
		for j, p in plates
			{
			if (IsObject(p.name) && BoxesOverlap(p.name, hl, false) && hl.y > p.name.y && hl.y < p.name.y + p.name.h * 4)
				owner := p
			else if (IsObject(p.health) && BoxesOverlap(p.health, hl, true))
				owner := p
			}
		if (!IsObject(owner))
			plates.Push(owner := {name: "", health: hl, votes: []})
		else if (!IsObject(owner.health))
			owner.health := hl
		;(the strip's own read of the line only finds the plate - no vote: read plain, the red numbers on the
		;parchment come back empty or wrong; each plate's are read below with only their red)
		if (!IsObject(owner.votes))
			owner.votes := []
		}
	;Left to right, like the slots on screen
	Loop, % plates.Length() - 1
		{
		Loop, % plates.Length() - A_Index
			{
			a := plates[A_Index], b := plates[A_Index + 1]
			if ((IsObject(a.name) ? a.name.x : a.health.x) > (IsObject(b.name) ? b.name.x : b.health.x))
				plates[A_Index] := b, plates[A_Index + 1] := a
			}
		}
	if (offRow != "")
		DebugLog("  nameplates: not on the plates' row, left out: " SubStr(offRow, 1, 160))
	if (plates.Length() < 1 || plates.Length() > 4)
		{
		HealthStatus := "Couldn't find the enemy nameplates (" . plates.Length() . " found): " . SubStr(RegExReplace(seen, "\s+", " "), 1, 60)
		;(none read: there's always a first plate - its box is where a single-target hit is clicked; not with the Crown
		;shop's buttons read up there - its Earn Crowns / Upgrade Now)
		if (plates.Length() < 1 && !RegExMatch(seen, "i)cr[o0]wn|upgrade|earn"))
			EnemyPlates.Push({x: GameLeft + Px(205), y: GameTop + Px(36)})
		return false
		}
	;Where each plate is (its name, else its health line), left to right: a single-target hit clicks one
	;(kept even if the health can't be read below)
	for i, p in plates
		{
		b := IsObject(p.name) ? p.name : p.health
		EnemyPlates.Push({x: b.x + b.w // 2, y: b.y + b.h // 2})
		}

	;2) Each plate's health also read on its own at both sizes. Every read is a vote: at least two must
	;agree and none may disagree (a misread digit that still looks like health won't repeat exactly)
	list := []
	for i, p in plates
		{
		if (!IsObject(p.votes))
			p.votes := []
		if (IsObject(p.health))
			{
			b := p.health
			cx := b.x - b.h, cy := b.y - b.h // 2, cw := b.w + b.h * 2, ch := b.h * 2
			}
		else
			{
			b := p.name
			cx := b.x - b.h * 2, cy := b.y + b.h, cw := (b.w > b.h * 10 ? b.w : b.h * 10) + b.h * 4, ch := b.h * 3
			}
		;(only the red pixels read - the numbers; just round their glyphs when they're found, not the whole box, which
		;can hold a bit of the plate's icon; their 3s and 5s told by their shape: HealthDigits)
		;(looked for a good way either side: the strip's read of the line can start or end a digit or two short)
		;(by the helper first, by the digits' shape - VisionPlate: two votes; else OCR)
		vp := VisionPlate(cx - b.h * 3, cy, cx + cw + b.h * 3, cy + ch)
		if (IsObject(vp))
			p.votes.Push([{cur: vp.cur, max: vp.max}]), p.votes.Push([{cur: vp.cur, max: vp.max}])
		gl := IsObject(vp) ? "" : HealthGlyphs(cx - b.h * 3, cy, cw + b.h * 6, ch)
		;(the plate's own box kept as it is - the boss click's matched against it below)
		gx := cx, gy := cy, gw := cw, gh := ch
		if (IsObject(gl) && gl.Length() >= 3)
			GlyphsBox(gl, (gl[1].y2 - gl[1].y1) // 2 + 2, gx, gy, gw, gh)
		if (!IsObject(vp))
			{
			p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", scale1, redLines, 1), gl)))
			p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", scale2, redLines, 1), gl)))
			}
		;(the two don't make two agreeing reads - one came out short: a third, at a size between)
		got := 0
		for j, v in p.votes
			got += IsObject(v) ? 1 : 0
		if (got < 2)
			p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", (scale1 + scale2) / 2, redLines, 1), gl)))
		agreed := "", count := 0
		for j, v in p.votes
			{
			if (!IsObject(v))
				continue
			if (v.Length() != 1 || (IsObject(agreed) && !SameHealth(agreed, v)))
				{
				HealthStatus := "Conflicting health reads on nameplate " . i . " of " . plates.Length()
				return false
				}
			agreed := v, count++
			}
		if (count < 2)
			{
			HealthStatus := "Couldn't read the health on nameplate " . i . " of " . plates.Length()
			return false
			}
		list.Push(agreed[1])
		;Whole plate, for matching the Alt+1 boss click: the diamond sits left of the text, pips above it
		top := IsObject(p.name) ? p.name : b
		p.box := {x1: (top.x < cx ? top.x : cx) - top.h * 5, y1: top.y - top.h * 2, x2: cx + cw + top.h, y2: cy + ch + top.h}
		}
	EnemyHP := list
	HealthStatus := ""
	;Boss clicked on its nameplate (Alt+1): the plate under the click is the boss, so traps only count against it
	if (BossChoosen == 1)
		{
		for i, p in plates
			{
			if (BossX >= p.box.x1 && BossX <= p.box.x2 && BossY >= p.box.y1 && BossY <= p.box.y2)
				BossSlot := BossSlot ? -1 : i
			}
		if (BossSlot < 0)
			BossSlot := 0
		;The boss keeps its max health, so a plate with a different max isn't it
		if (BossSlot)
			{
			if (!BossMax)
				BossMax := list[BossSlot].max
			else if (list[BossSlot].max != BossMax)
				BossSlot := 0
			}
		if (BossMax)
			{
			alive := 0
			for i, e in list
				{
				if (e.max == BossMax)
					alive++
				}
			if (alive == 0)
				{
				;Boss is gone, any traps we put on it went with it
				BossTraps := {}
				BossSlot := 0
				}
			else if (alive > 1)
				BossSlot := 0
			}
		}
	;The enemy our traps are on (the kill check counts them on it only): the boss's plate; else the plate of the one with the
	;most health they went on - TrapFoeSlot
	TrapSlot := (BossChoosen == 1) ? BossSlot : TrapFoeSlot(list, plates)
	return true
	}

;---- Traps on the enemy with the most health (the user, 2026-10-24: "Can we have the wizard trap the enemy with the
;highest health always?") ----
;No boss picked with Alt+1 and not a party's blader or healer: every battle's traps (Hex, Feint, Elemental and school
;traps - those that fit the planned hit's schools: BoostPick) go on the enemy with the most health (TrapTarget); BossTraps
;holds the traps on that one enemy (TrapPut), found again each round by its plate and its most health (TrapFoeSlot), and
;the kill check counts them on it only - with solotraps:1 (you fight alone: another's hit uses them up unseen)

;Where this round's traps go (the battle code, right before BoostPick): TrapOn, TrapAtX / TrapAtY, TrapMine (noted for
;the kill check: TrapPut), TrapAtMax, TrapPick, TrapWhy. The boss picked with Alt+1: on it, as ever; a party battle's
;blader or healer: the enemy the hitter goes for (Party.ahk PartyTrapTarget - not noted, as ever); else - with traps on
;(usetraps) and one in hand - the enemy with the most health (TrapTarget). None found: no traps this round
TrapWhere()
	{
	global
	TrapOn := (BossChoosen == 1), TrapAtX := bossX, TrapAtY := bossY, TrapMine := TrapOn, TrapAtMax := "", TrapPick := 0, TrapWhy := ""
	if (TrapOn)
		return
	if (PartySupport())
		{
		if (PartyTrapTarget(TrapAtX, TrapAtY))
			TrapOn := 1
		return
		}
	if (Stat("usetraps") && TrapsInHand() && TrapTarget(TrapAtX, TrapAtY, TrapAtMax))
		TrapOn := 1, TrapMine := 1
	}

;A trap in hand the chain could cast: a Feint, Hex (trap3), trap4, a school's or a group's trap found (SbFound, GbFound -
;BoostSearch: by its picture or the game's hand)
TrapsInHand()
	{
	global
	local tihI, tihL, tihK
	if (feint == 1 || trap3 == 1 || trap4 == 1)
		return true
	for tihI, tihL in [SbFound, GbFound]
		if (IsObject(tihL))
			for tihK in tihL
				if (BoostKind(tihK) = "trap")
					return true
	return false
	}

;Where a trap goes with no boss picked (TrapWhere): the enemy with the most health - the plates read as the kill check
;reads them (ReadEnemyHealth: the helper's digits, else OCR; read again when the last read is over 8 s old); a tie, or
;health not read: the planned hit's target among them (TrapHitPick). x, y: its plate; most: its most health ("" not read);
;TrapPick its slot, TrapWhy which it is (the log). False: no plate found - nowhere sure to put it
TrapTarget(ByRef x, ByRef y, ByRef most)
	{
	global
	local ttI, ttE, ttTop, ttTied, ttN, ttOne
	most := "", TrapPick := 0, TrapWhy := ""
	if (A_TickCount - EnemyPlatesAt > 8000)
		ReadEnemyHealth()
	if (!IsObject(EnemyPlates) || !EnemyPlates.Length())
		return false
	if (IsObject(EnemyHP) && EnemyHP.Length() && EnemyHP.Length() = EnemyPlates.Length())
		{
		ttTop := "", ttTied := {}, ttN := 0, ttOne := ""
		for ttI, ttE in EnemyHP
			if (ttTop = "" || ttE.cur > ttTop)
				ttTop := ttE.cur
		for ttI, ttE in EnemyHP
			if (ttE.cur = ttTop)
				{
				ttTied[ttI] := 1, ttN += 1
				if (ttOne = "")
					ttOne := ttI
				}
		TrapPick := (ttN > 1) ? TrapHitPick(ttTied) : ttOne
		most := EnemyHP[TrapPick].max
		TrapWhy := "enemy " TrapPick " of " EnemyPlates.Length() " (" EnemyHP[TrapPick].cur "/" most " health - "
			. (ttN > 1 ? ttN " have the most: the planned hit's target" : "the most") ")"
		}
	else
		{
		TrapPick := TrapHitPick("")
		TrapWhy := "enemy " TrapPick " of " EnemyPlates.Length() " (health not read" (HealthStatus != "" ? ": " HealthStatus : "") " - the planned hit's target)"
		}
	x := EnemyPlates[TrapPick].x, y := EnemyPlates[TrapPick].y
	return true
	}

;The planned hit's target among the enemies among ({slot: 1}; "" all) - TrapTarget's in a tie or with health not read:
;where the hit the round plans (PlanChoose) would be clicked - a hit on one enemy (<school>.<hit>target:1, a learned hit's
;card) the one HitTarget picks (Autofarmer.ahk HitPick: the one it does the most to); an all-enemies hit, the weakest of
;them. Among equal health, the leftmost; health not read, the leftmost plate
TrapHitPick(among)
	{
	global
	local thpP, thpD, thpC
	thpP := PlanChoose(), thpD := ""
	if (RegExMatch(thpP, "^hit[1-4]$") && Stats[hitschool "." thpP "target"] = 1)
		thpD := HitDamage(thpP, false, false)
	else if (InStr(thpP, "learned/") = 1 && IsFunc("LearnCardOf"))
		{
		thpC := Func("LearnCardOf").Call(SubStr(thpP, 9))
		if (IsObject(thpC) && thpC.type = "damage" && thpC.target != 0)
			thpD := LearnedHitDamage(thpC, false)
		}
	return HitPick(thpD, among)
	}

;A trap cast this round noted for the kill check (UseTrap: the boss's, or TrapTarget's pick - TrapMine): BossTraps holds
;the traps on one enemy - the boss (BossSlot), else the one TrapFoeX / TrapFoeY (its plate) and TrapFoeMax (its most
;health) say, found again each round (TrapFoeSlot). One on another enemy starts them afresh: those on the last one aren't
;counted any more (still on it - left out is the safe side)
TrapPut(key, bonus, src)
	{
	global
	if (!IsObject(BossTraps))
		BossTraps := {}
	if (BossChoosen != 1)
		{
		if (TrapFoeX = "" || Abs(TrapAtX - TrapFoeX) > Px(40) || Abs(TrapAtY - TrapFoeY) > Px(40))
			{
			if (BossTraps.Count())
				DebugLog("  a trap on another enemy than the last ones - those aren't counted any more")
			BossTraps := {}, TrapFoeX := TrapAtX, TrapFoeY := TrapAtY, TrapFoeMax := TrapAtMax
			TrapFoeN := IsObject(EnemyPlates) ? EnemyPlates.Length() : 0, TrapSlot := TrapPick
			}
		else if (TrapFoeMax = "" && TrapAtMax != "")
			TrapFoeMax := TrapAtMax
		DebugLog("  " key " on " (TrapWhy != "" ? TrapWhy : "the enemy with the most health") (Stat("solotraps") == 1 ? " - the kill check counts it there" : " - not counted (solotraps:0)"))
		}
	AddBoost(BossTraps, key, bonus, src)
	}

;The slot of the enemy the traps went on in this health read (ReadEnemyHealth: list its health, plates their boxes), no
;boss picked: the plate round where it was (TrapFoeX / TrapFoeY) with its most health (TrapFoeMax - an enemy keeps it;
;taken from this read if it wasn't read then). Its most health on no plate: it's gone, its traps with it. 0: none on, or
;not sure which - two with that most health and a plate fewer than then (they may have moved along)
TrapFoeSlot(list, plates)
	{
	global
	local tfsI, tfsP, tfsE, tfsAt, tfsSame
	if (TrapFoeX = "" || !IsObject(BossTraps) || !BossTraps.Count())
		return 0
	tfsAt := 0
	for tfsI, tfsP in plates
		if (IsObject(tfsP.box) && TrapFoeX >= tfsP.box.x1 && TrapFoeX <= tfsP.box.x2 && TrapFoeY >= tfsP.box.y1 && TrapFoeY <= tfsP.box.y2)
			tfsAt := tfsAt ? -1 : tfsI
	;(its most health not read when they went on: this read's of the plate where it was)
	if (TrapFoeMax = "" && tfsAt > 0)
		TrapFoeMax := list[tfsAt].max
	if (TrapFoeMax = "")
		return 0
	tfsSame := 0
	for tfsI, tfsE in list
		tfsSame += (tfsE.max = TrapFoeMax) ? 1 : 0
	if (!tfsSame)
		{
		DebugLog("  the enemy your traps went on is gone - they went with it")
		BossTraps := {}, TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0
		return 0
		}
	if (tfsAt <= 0 || list[tfsAt].max != TrapFoeMax)
		return 0
	if (tfsSame > 1 && plates.Length() != TrapFoeN)
		return 0
	return tfsAt
	}

;---- The health numbers' 3s, 5s and 8s ----
;
;In the plates' font a 3 has a flat top like a 5, and Windows' OCR reads 395 as 595 (or 39S) - and an 8 as a 3 now and
;then. The numbers are pure red: their glyphs are found at 1:1, left to right (not a plate's school icon - not that
;red), a run wider than it is tall split at its thinnest column (a digit touching the "/"), only the digits' height
;kept (not a speck, nor the taller icon) with a comma joining those either side, and of them only the longest row close
;together (not a bit of the icon a gap away). A 5 and an 8 have ink down the left side under the top (a 3 at most a
;quarter, against over half), and only an 8 over the bottom too (all of it, against at most about half)

;The pure red numbers' glyphs in the screen box, left to right: [{x1, x2, y1, y2, band, low}] (screen) - how much of the
;glyph's left side is inked (0-1) under its top (band) and over its bottom (low). "" if it can't be captured
HealthGlyphs(x, y, w, h)
	{
	px := CaptureRGB(x, y, w, h)
	if (!IsObject(px))
		return ""
	inkAt := [], colInk := []
	Loop, % w
		colInk[A_Index] := 0
	Loop, % w * h
		{
		c := px[A_Index]
		r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
		;(the numbers' red - not the orange-red of a school icon: its green well above its blue)
		if (r > 110 && g < 45 && b < 45 && r - g > 80 && g - b < 18)
			inkAt[A_Index] := 1, colInk[Mod(A_Index - 1, w) + 1] += 1
		}
	;Runs of inked columns, and the usual width of one
	runs := [], start := 0, widths := ""
	Loop, % w + 1
		{
		has := (A_Index <= w && colInk[A_Index])
		if (has && !start)
			start := A_Index
		else if (!has && start)
			runs.Push([start, A_Index - 1]), widths .= (widths = "" ? "" : ",") A_Index - start, start := 0
		}
	if (!runs.Length())
		return []
	Sort, widths, N D`,
	ws := StrSplit(widths, ",")
	med := ws[(ws.Length() + 1) // 2]
	parts := []
	for i, run in runs
		{
		a := run[1], z := run[2], wide := z - a + 1
		;(its height: the rows with ink in its columns)
		top := 0, bottom := 0
		Loop, % h
			{
			j := A_Index, row := (j - 1) * w
			Loop, % wide
				if (inkAt[row + a + A_Index - 1])
					{
					top := top ? top : j, bottom := j
					break
					}
			}
		;(two glyphs touching - a digit and the "/": wider than it is tall - a digit alone is about 0.7 of its height:
		;split at the thinnest column of its middle half)
		if (wide > (bottom - top + 1) && wide >= 6)
			{
			cut := a + wide // 4
			Loop, % (z - wide // 4) - (a + wide // 4) + 1
				{
				k := a + wide // 4 + A_Index - 1
				if (colInk[k] < colInk[cut])
					cut := k
				}
			parts.Push([a, cut]), parts.Push([cut + 1, z])
			}
		else
			parts.Push([a, z])
		}
	;Each glyph's top and bottom, and the usual height
	gl := [], heights := ""
	for i, q in parts
		{
		top := 0, bottom := 0
		Loop, % h
			{
			j := A_Index, row := (j - 1) * w
			Loop, % q[2] - q[1] + 1
				{
				if (inkAt[row + q[1] + A_Index - 1])
					{
					if (!top)
						top := j
					bottom := j
					break
					}
				}
			}
		if (top)
			gl.Push({x1: q[1], x2: q[2], y1: top, y2: bottom}), heights .= (heights = "" ? "" : ",") bottom - top + 1
		}
	if (!gl.Length())
		return []
	Sort, heights, N D`,
	hs := StrSplit(heights, ",")
	tall := hs[(hs.Length() + 1) // 2]
	;(the digits' own height - not a speck, nor the taller icon or a mob's name - and a comma (short, low: it joins the
	;digits either side); then the longest row of them close together: the numbers, not a bit of the icon or anything
	;else a gap away)
	kept := [], gaps := "", bottoms := ""
	for i, g in gl
		{
		gh := g.y2 - g.y1 + 1
		if (gh >= 0.7 * tall && gh <= 1.35 * tall)
			gaps .= (gaps = "" ? "" : ",") g.x2 - g.x1 + 1, bottoms .= (bottoms = "" ? "" : ",") g.y2
		}
	if (gaps = "")
		return []
	Sort, gaps, N D`,
	Sort, bottoms, N D`,
	gs := StrSplit(gaps, ","), bs := StrSplit(bottoms, ",")
	near := Max(2, 0.6 * gs[(gs.Length() + 1) // 2]), base := bs[(bs.Length() + 1) // 2]
	for i, g in gl
		{
		gh := g.y2 - g.y1 + 1
		if (gh >= 0.7 * tall && gh <= 1.35 * tall)
			g.digit := 1, kept.Push(g)
		else if (gh < 0.6 * tall && g.y1 >= base - tall * 0.5 && g.y2 <= base + tall * 0.5)
			g.digit := 0, kept.Push(g)
		}
	best := 1, bestN := 0, from := 1, n := 0
	for i, g in kept
		{
		if (i > 1 && g.x1 - kept[i - 1].x2 - 1 > near)
			from := i, n := 0
		n += g.digit
		if (n > bestN)
			best := from, bestN := n, last := i
		}
	;(too-tall red ink beside the row or in it - a red thing under the first digits joins their columns, and they'd be
	;left out, the number read short: none of it trusted)
	for i, g in gl
		if (g.y2 - g.y1 + 1 > 1.35 * tall && g.x2 >= kept[best].x1 - tall && g.x1 <= kept[last].x2 + tall)
			return []
	digits := []
	Loop, % last - best + 1
		if (kept[best + A_Index - 1].digit)
			digits.Push(kept[best + A_Index - 1])
	out := []
	lowRow := Round(base - tall * 0.4)
	for i, g in digits
		{
		;(a comma touching the digit: its columns, inked only low down, trimmed off its ends - else the left side measured
		;is the comma's)
		Loop, 2
			{
			trim := 0, side := A_Index
			Loop, % g.x2 - g.x1 - 5
				{
				edge := side = 1 ? g.x1 + A_Index - 1 : g.x2 - A_Index + 1, high := 0
				Loop, % lowRow - g.y1
					{
					if (inkAt[(g.y1 + A_Index - 2) * w + edge])
						{
						high := 1
						break
						}
					}
				if (high)
					break
				trim := A_Index
				}
			if (trim >= 2 && side = 1)
				g.x1 += trim
			else if (trim >= 2)
				g.x2 -= trim
			}
		Loop, % h - g.y1 + 1
			{
			j := g.y1 + A_Index - 1, row := (j - 1) * w
			Loop, % g.x2 - g.x1 + 1
				{
				if (inkAt[row + g.x1 + A_Index - 1])
					{
					g.y2 := j
					break
					}
				}
			}
		gh := g.y2 - g.y1 + 1, gw := g.x2 - g.x1 + 1
		;(the left 30 %: from a quarter of the way down to under half way - band - and from just over half way to
		;three quarters - low)
		bw := Max(1, Round(gw * 0.3)), band := low := 0
		for k, rows in [[0.25, 0.45], [0.58, 0.75]]
			{
			y0 := g.y1 + Round(gh * rows[1]), y1 := g.y1 + Round(gh * rows[2]), inked := 0
			Loop, % y1 - y0 + 1
				{
				row := (y0 + A_Index - 2) * w
				Loop, % bw
					inked += inkAt[row + g.x1 + A_Index - 1] ? 1 : 0
				}
			if (k = 1)
				band := inked / (bw * (y1 - y0 + 1))
			else
				low := inked / (bw * (y1 - y0 + 1))
			}
		out.Push({x1: x + g.x1 - 1, x2: x + g.x2 - 1, y1: y + g.y1 - 1, y2: y + g.y2 - 1, band: band, low: low})
		}
	return out
	}

;The screen box round glyphs (HealthGlyphs), pad pixels out
GlyphsBox(gl, pad, ByRef bx, ByRef by, ByRef bw, ByRef bh)
	{
	x1 := gl[1].x1, x2 := gl[gl.Length()].x2, y1 := gl[1].y1, y2 := gl[1].y2
	for i, g in gl
		y1 := Min(y1, g.y1), y2 := Max(y2, g.y2)
	bx := x1 - pad, by := y1 - pad, bw := x2 - x1 + 1 + pad * 2, bh := y2 - y1 + 1 + pad * 2
	}

;An OCR'd health line (read with only its red) put right by its glyphs (HealthGlyphs): S read for 5, O for 0 and B for 8,
;then each 3, 5 or 8 by its shape. "" when the glyphs were found and don't line up with the characters (one each), or
;there's a 3, 5 or 8 to tell and they weren't - such a read isn't to be trusted
HealthDigits(text, gl)
	{
	;(only a thousands mark between digits and spaces round the "/" taken out - anything else left in for ParseHealth to
	;turn down, and to be counted against the glyphs)
	;(and an "r" for a comma - 1440p, 2026-10-23: 2r848/3r153)
	t := RegExReplace(text, "(?<=[\dSsOoB])\s*[,.']\s*(?=[\dSsOoB])|(?<=[\dSsOoB])r(?=[\dSsOoB]{3}(?![\dSsOoB]))|\s+(?=/)|(?<=/)\s+")
	t := RegExReplace(RegExReplace(RegExReplace(t, "[Ss]", "5"), "[Oo]", "0"), "B", "8")
	;(every read counted against the glyphs when they were found - a digit cut off or added shows)
	if (IsObject(gl) && gl.Length() != StrLen(t))
		return ""
	if (!RegExMatch(t, "[358]"))
		return t
	if (!IsObject(gl))
		return ""
	out := ""
	Loop, Parse, t
		out .= InStr("358", A_LoopField) ? (gl[A_Index].band < 0.4 ? "3" : gl[A_Index].low >= 0.75 ? "8" : "5") : A_LoopField
	return out
	}

;Minimum non-crit damage of a hit to one enemy, counting only boosts we know are applied.
;Bubbles aren't counted: anyone's global (enemies' too) replaces ours and we can't see it.
HitDamage(hitName, useEnchant, toBoss)
	{
	global hitschool, enchant
	;(head by head - HitHeads: Hydra's fire, ice and storm each with the blades and traps that fit it; one head of your
	;school - its PlayerStats.txt number - when they aren't known, as before)
	hdHh := HitHeads(hitName)
	if (hdHh.total <= 0)
		return 0
	;X-pip spells (pip cost 0) are stored as damage per pip: they spend all your pips (not the wand's card:
	;it costs nothing)
	hdPer := (hdHh.xpip && hitName != "wand") ? (PipsNow > 0 ? PipsNow : 1) : 1
	hdAdd := 0
	if (EnchantedHits[hitName])
		hdAdd := Stat("enchant" . EnchantedHits[hitName])
	;(never on an item card - a pet's, the wand's: it can't be enchanted)
	else if (useEnchant && enchant >= 1 && !hdHh.item)
		hdAdd := Stat("enchant" . enchant)
	return HeadsDamage(hdHh, hdPer, hdAdd, toBoss)
	}

;A hit's least damage from its base (its card's, an enchant added): your damage %, the blades and aura on, the traps on
;the enemy they went on (solotraps:1 - toBoss: this is that enemy - the boss, or the one with the most health they went
;on: TrapSlot), the enemies' resist less your pierce - HitDamage's, and a learned hit's in no slot (HitTarget).
;sch: the head's school - only the blades, aura and traps that fit it count; "*" every one, as before
HitDamageFrom(base, toBoss := false, sch := "*")
	{
	if (base <= 0)
		return 0
	dmg := base * DamageMultiplier(Stat("damage")) * (sch = "*" ? BoostMult(AppliedBlades) : BoostMultFor(AppliedBlades, sch))
	if (AuraRounds > 0 && (sch = "*" || BoostFits("aura", sch)))
		dmg *= 1 + Stat("aura") / 100
	;Another player's hit on the enemy uses up our traps without us seeing it: counted only with solotraps:1 (you fight
	;alone), and only on the enemy they went on
	if (toBoss && Stat("solotraps") == 1)
		dmg *= (sch = "*" ? BoostMult(BossTraps) : BoostMultFor(BossTraps, sch))
	resist := Stat("enemyresist") - Stat("pierce")
	if (resist > 0)
		dmg *= 1 - resist / 100
	return Floor(dmg)
	}

;A learned hit's least damage in no slot (for its target: HitTarget) - every head of it (CardLearn.ahk LearnHitBase: a
;Hydra's three), the enchant put on it added (enchanted), then as HitDamage; "" its damage not known
LearnedHitDamage(c, enchanted)
	{
	global enchant, BossChoosen
	;(head by head: LearnHitHeads - the game's heads, else one of its school)
	lhdHh := LearnHitHeads(c)
	if (lhdHh.total <= 0)
		return ""
	;(an X-pip hit: its number is a pip's - all your pips go)
	return HeadsDamage(lhdHh, lhdHh.xpip ? Max(PipsNow, 1) : 1, (enchanted && enchant >= 1) ? Stat("enchant" . enchant) : 0, BossChoosen == 1)
	}

IsLethal(hitName, useEnchant)
	{
	if (!IsObject(EnemyHP))
		return false
	;Boss fight: the boss's plate must be among the ones read, or a missed plate could hide it
	if (BossChoosen == 1) && (BossSlot < 1)
		return false
	;A hit on one enemy (<school>.<hit>target:1, e.g. Scarab) only ends the battle when one enemy is left
	if (Stat(hitschool "." hitName "target") = 1 && EnemyHP.Length() > 1)
		return false
	margin := 1 + Stat("killmargin") / 100
	;(the traps counted on the enemy they went on only - TrapSlot: the boss's slot, or the one with the most health they
	;went on; 0 none / its plate not found)
	for i, e in EnemyHP
		{
		if (HitDamage(hitName, useEnchant, i == TrapSlot) < e.cur * margin)
			return false
		}
	return true
	}

;Enemy health as text, or why it couldn't be read
HealthText()
	{
	if (!IsObject(EnemyHP))
		return HealthStatus
	text := ""
	for i, e in EnemyHP
		{
		text .= (text = "" ? "" : ", ") . e.cur . "/" . e.max . (i == BossSlot ? " (boss)" : (i == TrapSlot) ? " (your traps)" : "")
		}
	return text
	}

;Statistic mode (Alt+S): tooltip with the health read and what each hit in hand would do
ShowKillInfo()
	{
	global KillHit, KillEnchant
	if (statsmode != 1)
		return
	info := "Pips: " . PipsNow . "`nEnemy health: " . HealthText()
	if (IsObject(EnemyHP))
		{
		inHand := [hit1, hit2, hit3, hit4]
		Loop, 4
			{
			if (inHand[A_Index] == 1)
				{
				info .= "`nhit" . A_Index . ": " . HitDamage("hit" . A_Index, 0, 0)
				if (TrapSlot)
					info .= " (" (TrapSlot == BossSlot ? "boss" : "trapped enemy") " " . HitDamage("hit" . A_Index, 0, 1) . ")"
				}
			}
		if (KillHit != "")
			info .= "`nCasting " . KillHit . (KillEnchant ? " with enchant" : "") . ", it kills everything"
		else if (BossChoosen == 1) && (BossSlot < 1)
			info .= "`nBoss nameplate not found, kill check off"
		else
			info .= "`nNo hit kills everything yet, boosting"
		}
	;The box must never sit over the game: ImageSearch would see it instead of the cards, and it would
	;catch the boss/hammer clicks. Put it beside the window, or don't show it (Win+2 still has the info)
	SysGet, vLeft, 76
	SysGet, vWidth, 78
	if (GameRight + 420 <= vLeft + vWidth)
		ToolTip, %info%, % GameRight + 10, % GameTop, 20
	else if (GameLeft - 420 >= vLeft)
		ToolTip, %info%, % GameLeft - 410, % GameTop, 20
	else
		{
		ToolTip,,,, 20
		return
		}
	;ToolTip moves itself back on screen when it doesn't fit, so check where it really ended up
	tip := WinExist("ahk_class tooltips_class32 ahk_pid " . DllCall("GetCurrentProcessId"))
	if (tip)
		{
		WinGetPos, tx, ty, tw, th, ahk_id %tip%
		if (tx < GameRight) && (tx + tw > GameLeft) && (ty < GameBottom) && (ty + th > GameTop)
			ToolTip,,,, 20
		}
	}

;Can you pay for this hit right now? (the game doesn't grey out cards you can't afford)
;Unknown pips (nameplate not found) counts as yes; the cast check in Autofarmer catches it
Affordable(hitName)
	{
	global hitschool
	if (PipsNow < 0)
		return true
	;(the wand's card costs no pips at all - not an X-pip spell)
	if (hitName = "wand")
		return true
	cost := Stat(hitschool . "." . hitName . "pips")
	return (cost = 0) ? (PipsNow >= 1) : (PipsNow >= cost)
	}

;Your pips this round (PipsNow): the game's own count from its memory when the hand's read there this round (Vision.ahk
;VisionCards - /cards' me line, read-only), else off the orbs under your name (PipValue). The game counts pips for a spell
;of your own school - the cards the bot plays - as:
;  generic pip                                  1
;  power pip                                    2
;  school pip of your own school                2   (a power pip in your school's colours: it pays as one)
;  school pip of another school                 1   (it pays as a power pip only for that school's spells)
;  shadow pip                                   0   (it pays only a spell's shadow pips)
;so PipsNow = generic + 2 x (power + your school's pips) + the other schools' pips. Your school: the game's, else the
;badge by your name (school). The orbs are read anyway, for the slots filled (PipOrbs, for saving pips: the game's pips
;counted one an orb when it read them) and for the log - pipsnote says "(from the game; the pip row read M)" when the
;two differ. -1 when neither can be read
PipsRead()
	{
	global school
	prRow := PipValue(), PipsNote := ""
	prHand := VisionCards(1500)
	if (!IsObject(prHand) || !IsObject(prHand.me) || !prHand.me.ok)
		return prRow
	prOwn := prHand.me.school != "" ? prHand.me.school : Format("{:L}", school)
	prNum := prHand.me.generic + 2 * prHand.me.power, prOrbs := prHand.me.generic + prHand.me.power
	for prI, prSch in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
		prNum += prHand.me[prSch] * (prSch = prOwn ? 2 : 1), prOrbs += prHand.me[prSch]
	PipOrbs := Min(7, prOrbs)
	if (prNum != prRow)
		PipsNote := " (from the game; the pip row read " prRow ")"
	return prNum
	}

;Your pips, from the orbs under your name on your nameplate: white = 1, gold power pip = 2,
;gold with your school's symbol (school pip) = 2. Orbs fill from the left, 20 px apart at UI scale
;1 (11 px orbs). Returns -1 if your nameplate (resources\player.png) wasn't found this round
PipValue()
	{
	global playerX, playerY
	if (playerX = "" || playerY = "" || (playerX = 0 && playerY = 0))
		return -1
	;(and how many of the 7 orb slots are filled, for saving pips: PipOrbs)
	PipOrbs := 0
	orb := Px(11), w := Round(20 * UiScale * 6) + orb, h := orb
	px := CaptureRGB(playerX - Px(6), playerY + Px(50), w, h)
	if (!IsObject(px))
		return -1
	;The colour counts below are areas, so they grow with the square of the UI scale
	area := UiScale * UiScale
	total := 0
	Loop, 7
		{
		slot := A_Index - 1, purple := 0, blue := 0, yellow := 0, white := 0, vivid := 0, dull := 0, grey := 0
		Loop, %h%
			{
			row := (A_Index - 1) * w + Round(20 * UiScale * slot)
			Loop, %orb%
				{
				c := px[row + A_Index], r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
				if (b > 150 && r > 110 && g < 120)
					purple++
				;(a Myth school pip: gold with a big blue triangle, so not much gold shows)
				else if (b > 140 && r < 110 && g < 150)
					blue++
				else if (r > 200 && g > 170 && b < 120)
					yellow++
				else if (r > 215 && g > 205 && b > 180)
					white++
				;(each school's own pip - a gold rim round its school's sign, 2026-10-24 at 1440p: Fire's orange flame,
				;Ice's snowflake, Life's leaf, Balance's red-orange, Myth's triangle, the power pip's gold: strongly
				;coloured, 86+ px a slot where an empty one has 42 at most; Death's skull is dark grey in a grey glow -
				;dark scenery under an empty slot has the dark but not the glow)
				mx := Max(r, g, b), mn := Min(r, g, b)
				if (mx - mn > 90 && mx > 120)
					vivid++
				else if (mx < 110 && mx - mn < 25)
					dull++
				else if (mn > 140 && mx - mn < 30 && mx < 225)
					grey++
				}
			}
		if (purple + blue + yellow >= 30 * area || vivid >= 60 * area || (dull >= 70 * area && grey >= 8 * area))
			total += 2
		else if (white >= 50 * area)
			total += 1
		else
			break
		PipOrbs := A_Index
		}
	return total
	}

;Screen rectangle -> array of 0xRRGGBB colours, row by row (1-based)
CaptureRGB(x, y, w, h)
	{
	hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
	VarSetCapacity(bi, 40, 0)
	NumPut(40, bi, 0, "UInt"), NumPut(w, bi, 4, "Int"), NumPut(-h, bi, 8, "Int")
	NumPut(1, bi, 12, "UShort"), NumPut(32, bi, 14, "UShort")
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", &bi, "UInt", 0, "Ptr*", bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (!hbm)
		{
		DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
		return ""
		}
	obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
	DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
	DllCall("GdiFlush")
	out := []
	Loop, % w * h
		out.Push(NumGet(bits + (A_Index - 1) * 4, "UInt") & 0xFFFFFF)
	DllCall("SelectObject", "Ptr", mdc, "Ptr", obm), DllCall("DeleteObject", "Ptr", hbm)
	DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
	return out
	}

;Cheapest hit in hand that kills every enemy, trying without the enchant first: the wand's card first (it
;costs nothing; never enchanted), then hit1-4
;The damage the kill check counts on from each hit in hand (HitDamage: the least it does - no crit - with the blades
;and traps known to be on, your damage %, the enemies' resist), for debug.log: "Sandstorm (hit1) 255 all enemies, 355
;with the enchant; wand 80 one enemy" ("" none in hand)
KillHitsText()
	{
	global enchant, wand, hit1, hit2, hit3, hit4, hitschool
	inHand := [hit1, hit2, hit3, hit4], out := ""
	for each, kh in ["wand", "hit1", "hit2", "hit3", "hit4"]
		{
		if (kh = "wand" ? !(wand == 1 && Stat("usewand")) : inHand[each - 1] != 1)
			continue
		khDmg := HitDamage(kh, false, false)
		if (khDmg <= 0)
			continue
		khName := IsFunc("DashShortName") && kh != "wand" ? Func("DashShortName").Call(kh, hitschool) : ""
		;(a wand's hit is always one enemy's)
		khOne := kh = "wand" || Stat(hitschool "." kh "target") = 1
		khBoost := (kh != "wand" && enchant >= 1) ? HitDamage(kh, true, false) : 0
		;(its heads, when they're known - the game's: [fire 230 + ice 230 + storm 230 (the game)])
		khHh := HitHeads(kh)
		out .= (out = "" ? "" : "; ") (khName != "" && khName != kh ? khName " (" kh ")" : kh) " " khDmg (khOne ? " one enemy" : " all enemies")
			. (khBoost > khDmg ? ", " khBoost " with the enchant" : "") (khHh.sure ? " [" HeadsText(khHh) "]" : "")
		}
	return out
	}

FindLethalHit(ByRef hitName, ByRef withEnchant)
	{
	global enchant, wand
	inHand := [hit1, hit2, hit3, hit4]
	hitName := "", withEnchant := 0
	if (wand == 1 && Stat("usewand") && IsLethal("wand", 0))
		{
		hitName := "wand"
		return true
		}
	Loop, % (enchant >= 1) ? 2 : 1
		{
		useEnchant := A_Index - 1
		Loop, 4
			{
			;The strongest hit is saved for boss fights, same as the normal battle code
			if (inHand[A_Index] == 1) && (A_Index < 4 || BossChoosen == 1) && Affordable("hit" . A_Index) && IsLethal("hit" . A_Index, useEnchant)
				{
				hitName := "hit" . A_Index
				withEnchant := useEnchant
				return true
				}
			}
		}
	return false
	}

;---- Saving pips for a hit that ends the battle ----
;
;Called by the kill check when nothing in hand ends the battle this round. A hit in hand that would end it
;- an AoE that kills every enemy, a single-target hit that kills the last one - but costs more pips than
;you have, is worth saving for: pips come at 1 or more a round, so it's castable in (cost - pips) rounds
;at most. Within pipsave rounds (PlayerStats.txt, default 3; 0 = never save), PipSaveFor names it and
;UseHit casts no other hit meanwhile (the wand's free hit, boosts, healing and Pass still go). Not while
;your health is under pipsavehealth % (default 50), and given up for the battle if the pips don't come.
;The round it's affordable the kill check casts it.
PlanPips()
	{
	global hit1, hit2, hit3, hit4, BossChoosen, enchant, roundnumber, OwnHpPct, OwnHpRound, player
	PipSaveFor := "", PipSaveBare := 0
	maxWait := Stat("pipsave")
	if (maxWait <= 0 || PipSaveGaveUp || PipsNow < 0 || !IsObject(EnemyHP) || !EnemyHP.Length())
		return
	inHand := [hit1, hit2, hit3, hit4]
	;(the most pips you can still reach: 7 orb slots, each new one worth at least 1)
	reach := PipsNow + Max(0, 7 - PipOrbs)
	best := "", bestWait := 99, bestCost := 0
	Loop, 4
		{
		name := "hit" A_Index
		;(hit4 is only cast on bosses, as in the battle code)
		if (inHand[A_Index] != 1 || (A_Index = 4 && BossChoosen != 1))
			continue
		cost := Stat(hitschool "." name "pips")
		;(an X-pip spell, one you can pay for now, or one too far off: nothing to save for)
		if (cost <= 0 || cost <= PipsNow || cost - PipsNow > maxWait || cost > reach)
			continue
		;(lethal as it'll be when it's castable: the aura may have run out by then)
		wait := cost - PipsNow
		if (!PipLethalLater(name, wait))
			continue
		if (wait < bestWait)
			best := name, bestWait := wait, bestCost := cost
		}
	if (best = "")
		{
		PipSaveRounds := 0, PipSaveTarget := "", PipSaveStall := 0
		return
		}
	;Your health, off your name plate, read this round: no saving when it's low - or can't be read
	if (OwnHpRound != roundnumber && player == 1 && IsFunc("OwnHealthLow"))
		Func("OwnHealthLow").Call()
	if (OwnHpRound != roundnumber)
		{
		DebugLog("  not saving pips for " best ": your health couldn't be read")
		return
		}
	if (OwnHpPct < Stat("pipsavehealth"))
		{
		DebugLog("  not saving pips for " best ": your health is " OwnHpPct "% (under pipsavehealth " Stat("pipsavehealth") "%)")
		return
		}
	;Rounds saved for this hit: a new game round shows as more pips (the bot can look at one round twice);
	;the same pips three looks running means they've stopped coming
	if (best != PipSaveTarget)
		PipSaveTarget := best, PipSaveRounds := 0, PipSaveStall := 0, PipSaveLastPips := -1
	if (PipsNow != PipSaveLastPips)
		PipSaveRounds++, PipSaveStall := 0, PipSaveLastPips := PipsNow
	else
		PipSaveStall++
	if (PipSaveRounds > maxWait + 1 || PipSaveStall >= 3)
		{
		PipSaveGaveUp := 1
		DebugLog("  saved pips for " best " " PipSaveRounds " round(s) and still can't cast it - spending them again this battle")
		return
		}
	PipSaveFor := best
	;(the wand's free hit meanwhile only if the saved hit kills without the blades, traps, aura and enchant
	;it would use up - and never with the enchant)
	PipSaveBare := PipLethalBare(best)
	DebugLog("  saving pips for " best " (" bestCost " pips, you have " PipsNow "): it ends the battle - no other hit spends pips for up to " bestWait " round" (bestWait = 1 ? "" : "s") (PipSaveBare ? "" : "; no wand hit meanwhile (it would use up the boosts the kill needs)"))
	}

;Whether hit name is lethal once castable in wait rounds: the aura counted only if it lasts that long;
;the enchant in hand may be used on it
PipLethalLater(name, wait)
	{
	global enchant
	keep := AuraRounds
	AuraRounds := Max(0, AuraRounds - wait)
	lethal := IsLethal(name, 0) || (enchant >= 1 && IsLethal(name, 1))
	AuraRounds := keep
	return lethal
	}

;Whether hit name is lethal with none of the boosts a wand hit would use up (blades, traps, aura, enchant)
PipLethalBare(name)
	{
	keepBlades := AppliedBlades, keepTraps := BossTraps, keepAura := AuraRounds
	AppliedBlades := {}, BossTraps := {}, AuraRounds := 0
	lethal := IsLethal(name, 0)
	AppliedBlades := keepBlades, BossTraps := keepTraps, AuraRounds := keepAura
	return lethal
	}

