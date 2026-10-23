; Flee.ahk - out of mana or out of cards in a battle: flee, then try again. AHK v1.1, functions only;
; #Included by Autofarmer.ahk.
;
; Once a round, before casting (FleeCheck): the cards in hand (the vision helper's read of the hand) and your
; mana (the blue globe, Potions.ahk PotionGlobes). Two rounds in a row with no cards in hand - the deck used up -
; or no hit in a hand of fewer than 7 cards (a full hand's 7: the deck's used up, and heals and blades can't end
; the battle), or with less mana than the cheapest hit costs (every spell costs a mana a pip; a wand costs none,
; so not while one's in hand) and the bot can only pass for the rest of the battle: it clicks Flee (the word FLEE found by OCR
; under the hand, where Pass is on the left) and the battle's over. Out of battle again (FleeAfter): fled for
; mana, it drinks a potion (Ctrl+O) - none left, it goes and buys some (Potions.ahk PotionRun) and drinks one -
; then farms / walks on as usual, so the next battle starts with a full deck and mana. Not while you play, while
; learning every card, or on a manual round.
; PlayerStats.txt: fleeon:0 switches it off. debug.log: "fleeing: ...", "after fleeing: ...".

;Rounds in a row with no cards / too little mana / no hits left; why the last flee was ("mana" / "cards"; "" when
;dealt with). (this file is #Included at the bottom: an initializer here never runs - they start blank, made numbers
;in FleeCheck)
global FleeNoCards, FleeNoMana, FleeNoHits, FleeWhy
;The battle round (roundnumber) the no-hits count last looked at - "" a new battle (ResetVariables)
global FleeHitsRound

;True if it fled (the round's over: EndRound)
FleeCheck()
	{
	global
	local cards, g, mana, cheapest, why, w, fx, fy, fled
	if (!Stat("fleeon") || LearnAll || Manual == 1)
		return false
	;(blank till now: made numbers - in an expression "" + 1 is "" in AHK v1, and so is a blank "+= 0" chained with a
	;comma: a count that started blank never reached 2, so no flee when the first rounds after a start were out of
	;mana or cards)
	FleeNoCards := FleeNoCards ? FleeNoCards : 0, FleeNoMana := FleeNoMana ? FleeNoMana : 0, FleeNoHits := FleeNoHits ? FleeNoHits : 0
	cards := FleeHandCount()
	if (cards >= 0)
		FleeNoCards := (cards = 0) ? FleeNoCards + 1 : 0
	;(no hit in a hand of fewer than 7 cards - a full hand's 7, so the deck's used up: what's left can't end the
	;battle - 2026-10-21: a wizard passed 6 rounds holding 2 heals and a blade, and died. Once a battle round, on its
	;first look - a round left to you and looked at again holds what's left after its discards - and not in dual
	;mode, where two wizards' rounds take turns and the other one still hits)
	if (cards > 0 && !RoundAgain && dualmode != 1 && FleeHitsRound != roundnumber)
		FleeHitsRound := roundnumber, FleeNoHits := (cards < 7 && FleeHandHasHit() = 0) ? FleeNoHits + 1 : 0
	;(a wand in hand costs no mana: it can still hit - unless it's switched off, usewand)
	cheapest := FleeCheapestHit()
	if ((wand == 1 && Stat("usewand")) || cheapest = "")
		FleeNoMana := 0
	else
		{
		g := PotionGlobes(), mana := g.mana
		if (mana != "")
			FleeNoMana := (mana + 0 < cheapest) ? FleeNoMana + 1 : 0
		}
	;(no hits left: not a party battle's blader or healer - it's there for its boosts, the hitter hits)
	why := FleeNoCards >= 2 ? "no cards left (the deck's used up)" : (FleeNoHits >= 2 && !PartySupport()) ? "no hits left (the deck's used up: " cards " card(s) in hand, none a hit)" : FleeNoMana >= 2 ? "out of mana (" mana ", the cheapest hit costs " cheapest ")" : ""
	if (why = "")
		return false
	w := FleeWord()
	if (!IsObject(w))
		{
		DebugLog("  " why " - it would flee, but the Flee button can't be read")
		return false
		}
	DebugLog("  fleeing: " why " - Flee at " Round(w.x + w.w / 2) - GameLeft "," Round(w.y + w.h / 2) - GameTop " - to try again")
	ClickAt(Round(w.x + w.w / 2), Round(w.y + w.h / 2), 300)
	;(did it take? The round's Pass button goes with it. Not: once more, the mouse brought up from below the buttons -
	;on its way across, a card in hand zooms up under the mouse and can cover the button. Still not: the round goes on,
	;and the next tries again - the counts kept)
	if (!CastWentOut())
		{
		fx := Round(w.x + w.w / 2), fy := Round(w.y + w.h / 2)
		MouseMove, %fx%, % fy + Px(70), MouseSpeedNow()
		Sleep, 150
		MouseMove, %fx%, %fy%, MouseSpeedNow()
		Sleep, 80
		Click
		fled := CastWentOut()
		DebugLog("  the Flee click didn't take - clicked it again from below: " (fled ? "fled" : "still in the battle - the round goes on"))
		if (!fled)
			{
			CenterMouse()
			return false
			}
		}
	;(out of mana as well: a potion after it, whatever else it fled for)
	FleeWhy := (InStr(why, "mana") || FleeNoMana >= 2) ? "mana" : "cards", FleeNoCards := 0, FleeNoMana := 0, FleeNoHits := 0
	TrayTip, Wizard101 bot, % "Fled the battle: " why ". " (FleeWhy = "mana" ? "Drinking a potion (or buying some), then trying again." : "Trying again with a full deck."), 8, 1
	return true
	}

;How many cards are in hand, by the vision helper's read of it this round - only boxes it calls cards (-1: not read
;this round, or there were boxes where the hand should be and none was a card - the hand looked for in the wrong
;place: can't tell; 0 only when the helper saw none at all, hand|0)
FleeHandCount()
	{
	if (LastHandAnswer = "")
		return -1
	n := 0, boxes := 0, none := 0
	Loop, Parse, LastHandAnswer, `n, `r
		{
		if (InStr(A_LoopField, "card|") = 1)
			{
			boxes += 1
			f := StrSplit(A_LoopField, "|")
			if (f.Length() < 15 || f[15] != "0")
				n += 1
			}
		else if (A_LoopField = "hand|0")
			none := 1
		}
	if (!boxes)
		return none ? 0 : -1
	return n ? n : -1
	}

;Whether the hand holds a hit the bot can cast, or a card that may become one: 1 yes, 0 none, -1 can't tell (the
;hand not read). A hit: one the battle's own look found (hit1-3, hit4 in a boss fight - it's kept for the boss, a
;wand when wands are used), a card the vision helper knows by one of those pictures (greyed out: not enough pips
;yet), or a greyed-out card it doesn't know (learned - maybe into a hit's place - once it's in colour). A Reshuffle
;in hand (when used) counts too: it puts the used cards back in the deck. Not hits: a learned card in no slot (the
;bot never casts one) and a card in colour it doesn't know (it would have been learned). Not-cards (the deck's back,
;the floor) don't count
FleeHandHasHit()
	{
	global
	local n, f, k
	if (hit1 == 1 || hit2 == 1 || hit3 == 1 || (hit4 == 1 && BossChoosen == 1) || (wand == 1 && Stat("usewand")) || (reshuffle == 1 && Stat("usereshuffle")))
		return 1
	if (LastHandAnswer = "")
		return -1
	n := 0
	Loop, Parse, LastHandAnswer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] != "card" || f.Length() < 12 || (f.Length() >= 15 && f[15] = "0"))
			continue
		n += 1, k := f[6]
		if ((k = "" && f[8] = 1) || RegExMatch(k, "i)/hit[123]$") || (RegExMatch(k, "i)/hit4$") && BossChoosen == 1)
			|| (RegExMatch(k, "i)/wand$") && Stat("usewand")) || (RegExMatch(k, "i)^resources/reshuffle$") && Stat("usereshuffle")))
			return 1
		;(a learned hit in no slot: cast when nothing else can go - CastLearnedHit)
		if (InStr(k, "learned/") = 1 && Stat("learnedhits") && LearnIsHit(LearnCardOf(SubStr(k, 9))))
			return 1
		}
	return n ? 0 : -1
	}

;The fewest pips (= mana) a hit of this school's costs (hit1-3; PlayerStats.txt <school>.hitNpips), "" if none
;is known
FleeCheapestHit()
	{
	least := ""
	Loop, 3
		{
		k := hitschool ".hit" A_Index "pips"
		if (hitschool != "" && Stats.HasKey(k) && Stats[k] > 0 && (least = "" || Stats[k] < least))
			least := Stats[k]
		}
	return least
	}

;The Flee button's word under the hand ({x, y, w, h} on the screen), by OCR where DetectUiScale finds Pass and
;Flee; "" if it can't be read
FleeWord()
	{
	OcrRect(GameLeft + GameW // 8, GameTop + Round(GameH * 0.4), GameW * 3 // 4, Round(GameH * 0.45), "en", GameH < 1000 ? 2 : 1, lines)
	if (ErrorLevel || !IsObject(lines))
		return ""
	for i, line in lines
		for j, word in line.words
			{
			t := RegExReplace(word.text, "[^A-Za-z0-9|]")
			;(right of the middle, where Flee is - Pass is left of it)
			if (RcLooksLike(t, "FLEE") && word.x > ScreenX)
				return word
			}
	return ""
	}

;Out of battle after fleeing (the main loop, spellbook visible): fled for mana - drink a potion, or buy some and
;drink one; fled for cards - nothing to do (the next battle deals a full deck)
FleeAfter()
	{
	if (FleeWhy = "")
		return
	why := FleeWhy, FleeWhy := ""
	if (why != "mana")
		{
		DebugLog("after fleeing: out of cards - the next battle starts with a full deck")
		return
		}
	;(no mana and none to be had: it would only flee every battle - it stops, kept from timing out, as with an
	;empty mana globe: checkmana)
	if (!FleeRefillMana("after fleeing"))
		{
		Respond("Error, It Seems I Have No Mana. Preventing Timeout.")
		TrayTip, Wizard101 bot, Out of mana and couldn't get potions - the bot has stopped (kept from timing out)., 10, 2
		AlertSend("mana", "out of mana", "Fled out of mana, and no potion to be had (none left, and buying didn't work) - the bot is holding (kept from timing out) and carries on by itself once there's mana again.")
		afk("mana")
		}
	}

;Mana back: a potion (Ctrl+O), and if that doesn't raise it - none left - a run to buy some, then one (unless
;the run already drank one: PotionAfterBuy). A run that failed isn't tried again for 10 minutes (PotionFailUntil,
;as PotionCheck). True if mana went up
FleeRefillMana(why)
	{
	before := PotionGlobes().mana
	if (FleeDrinkForMana(before))
		{
		DebugLog(why ": drank a potion for mana (" (before = "" ? "?" : before) " -> " PotionGlobes().mana ")")
		AfkRetries := 0
		return true
		}
	if (A_TickCount < PotionFailUntil)
		{
		DebugLog(why ": no potion left, and the last run to buy some failed - not trying again yet")
		return false
		}
	DebugLog(why ": no potion left - going to buy some")
	if (PotionRun())
		{
		now := PotionGlobes().mana
		if ((before != "" && now != "" && now > before) || FleeDrinkForMana(now))
			{
			DebugLog(why ": bought potions and drank one for mana")
			AfkRetries := 0
			return true
			}
		}
	else
		PotionFailUntil := A_TickCount + 10 * 60000
	DebugLog(why ": couldn't get mana back (no potions, and the run to buy some didn't work)")
	return false
	}

;Ctrl+O; true if mana (or health, when mana can't be read) went up
FleeDrinkForMana(before)
	{
	ReleaseKeys()
	hpBefore := PotionGlobes().hp
	Send, {Blind}^o
	Sleep, 2500
	g := PotionGlobes()
	if (before != "" && g.mana != "")
		return g.mana > before
	return (hpBefore != "" && g.hp != "" && g.hp > hpBefore)
	}
