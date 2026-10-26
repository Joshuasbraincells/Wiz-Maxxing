; CardLearn.ahk - learns the cards in hand the bot has no picture for yet, as they show up. AHK v1.1,
; functions only; #Included by Autofarmer.ahk. Needs the vision helper (Vision.ahk): without it nothing
; is learned.
;
; Once a round, after the hand's been looked at, the helper reads the hand card by card (vision.py /hand):
; where each card is, whether it's one the bot knows, whether it's greyed out (not enough pips), its type
; from the icon at the bottom right of its picture (cardicons\: damage = one enemy, aoe = all enemies,
; heal, ward = a shield, charm, manip), its pip cost from the yellow digit (carddigits\, vision\digits\), whether
; the box is a card at all (real: the deck's back, the floor, the round timer or a popup where a card should be
; isn't - it's never learned, discarded or counted) and whether it's a treasure card. For a card it doesn't know
; (in colour - a greyed-out card's colours are gone) it:
;   - saves it in <the cut picture set for this UI size>\learned\<id>: .png (its picture, cut like the
;     hand-cut ones), .card.png (the whole card, for you to see), .icon.png, .pips.png
;   - reads its text with OCR three times and takes what two reads agree on (LearnKindOf): the kind and its
;     number ("65-105" -> hits for 65, "-50% to next" with a shield icon -> a shield, "Stun all enemies" -> a
;     stun, "525 over 3 rounds" -> damage over time...)
;   - puts it to use in a free slot - a slot whose picture isn't cut yet:
;       damage / aoe with pips -> <school>\hit1-3 (kept weakest to strongest; hit4 - cast on bosses only - only
;                                 for a one-enemy hit stronger than all of them)
;       damage / aoe, no pips  -> <school>\wand
;       heal                   -> <school>\heal1, heal2
;       ward                   -> resources\tower (cast on yourself)
;       blade                  -> resources\blade3 for Balanceblade ("+25% to next spell"), <school>\blade for one
;       trap, aura                naming your school, resources\trap3 for a trap on the next spell, <school>\aura -
;                                 only at the % PlayerStats.txt counts for that slot (blade3:, blade:, trap3:, aura:),
;                                 so the kill check never counts a boost that isn't there
;     copying its picture there and writing its numbers into PlayerStats.txt (<school>.hitN, hitNpips,
;     hitNtarget, ...), so the battle code uses it like any other card
;   - a hit stronger than one in hit1-3 when they're all taken: after the battle, room is made for it
;     (LearnArrange - learnupgrade:0 switches it off): the weakest leaves and hit1-3 are kept weakest to
;     strongest, everything that was there kept in backups\hits <school> <when> (<id>)\ and put back when you
;     forget the card or change its kind on the Spells tab
;   - otherwise (no free slot, or a kind the bot doesn't play: damage over time, stun, dispel, prism...) it's
;     only kept, and recognised from then on (it's tried for a slot again whenever it's in hand)
; A pip cost that couldn't be read is guessed as the pips you have (the card's in colour), and brought down
; whenever the card shows up in colour with fewer; a digit read is the card's own and is kept.
; The game's memory (Vision.ahk VisionCards - vision\handmem.py, read-only: nothing in the game is written, no key or
; click): when it has the hand settled and as many cards as the helper has card boxes, card i of it (left to right) is box
; i, and nothing above is guessed or OCR'd - a new card is learned with the game's name, kind, school (flag school=), pips
; (X: flag xpip), numbers and treasure / item card (flags tc, item), flag mem (read from the game: Sure 100%) and game=<its
; name in the game>; its picture is still cut as before (/cut). A card the bot knows by its picture gets what the game
; says filled in - never what you set (flag user, a name you typed): only the learner's own guesses and OCR'd numbers.
; An enchanted card the bot doesn't know by its picture isn't learned (its picture is the enchanted one's): it is when it
; shows up plain. LearnMemHand, LearnMemRead, LearnApplyMem. A learned card you named on the Spells tab, of any wizard, is
; put right whenever the game's hand has a card of that name (LearnMemNamed). A blade, trap or Tower Shield the game names
; whose slot's picture the battle's look doesn't find on it twice running gets the card's own picture there (the old one
; in backups\ - LearnBoostPicFix); meanwhile the battle casts it at its card box by the game's hand (KillCalc.ahk
; BoostMemBox, TowerMem).
; Out of battle, once a run (LearnOutOfBattle): learned "cards" that aren't cards are moved to backups\learned
; junk\, and a learned card's picture left in a slot that isn't its own is taken out (backups\learned strays\).
; Everything learned is listed in learned\cards.txt (and on the dashboard's Spells tab); debug.log: "learned a
; new card ...".

global LearnedThisRound := 0
;The catalog (learned\cards.txt): [{id, sch, type, pips, guess, value, target, slot, scale, dir, when, text, name,
;flags}] - flags a comma list (LearnFlag): ok, icon=<t>, tc, notc, item, two, dot=<n>, xpip, mem, game=<name>, school=<s>,
;user, hold, out=<id>, snap=<folder>
;(learned cards whose first pairing with the game's memory disagreed with them: the game's name seen, waiting to be seen
;again - LearnSeenAgain)
global LearnMemWait
global LearnedCards := ""
;Whether each slot is free (LearnFree), asked once a round
global LearnFreeCache := ""
;The hand as the helper read it this round (/hand's answer; "" till it's read - RoundStart clears it), and
;"Learn every card" (LearnAllToggle): on, the learned count when it started, rounds, rounds with nothing
;new, rounds with an empty hand
global LastHandAnswer, LearnAll, LearnAllFrom, LearnAllRounds, LearnAllIdle, LearnAllEmpty, LearnAllSeen
;Cards the bot never plays discarded this round already (DiscardUnused: once a round - RoundStart clears it)
global DiscardedUnused := 0
;What waits for the battle's end - room made in hit1-3 for a learned card ("p|<id>"), an arrangement put back
;("u|<id>|<why>"): pictures in hit1-3 never move during a battle (its records are by slot); the once-a-run jobs
;done (LearnOutOfBattle); cards' texts it may still read again this round (LearnSeenAgain). (This file is
;#Included at the bottom: an initializer here never runs - they start blank)
global LearnArrangeQueue, LearnRunDone, LearnRereadsLeft

;---- Discarding what the bot never plays (normal battles) ----
;Once a round, after the hand's been read and learned (LastHandAnswer): every card in it the bot knows for sure
;it never plays - a learned card in no slot: a charm, a global, a minion... it has no use for, a kind it doesn't
;play (a stun, damage over time...), one taken out of its slot by a stronger card, or one more card of a kind whose
;slots are all taken - is right-clicked away, so the next round draws cards it can use. Not: its own cards (hits,
;heals, blades, traps... - spare blades and Sharpen have their own rule, DiscardSpare), cards it doesn't know
;(greyed out - they may be its own; in colour they're learned first, and go next round if they get no slot), a
;treasure card (discarding one uses it up), one you said never to discard (Spells tab), a box that isn't a card,
;and nothing while you're playing. At most discardmax a round (PlayerStats.txt; discardunused:0 switches it off).
;From the left, following the hand as it re-centres (a card gone: those left of it slide right half a card, those
;right of it slide left). Returns how many
DiscardUnused()
	{
	global
	local cards, f, c, i, k, o, did, most, pid, why, lc, own, ox
	if (DiscardedUnused || LastHandAnswer = "" || !Stat("discardunused") || LearnAll)
		return 0
	DiscardedUnused := 1
	if (IsFunc("PlayerActing") && Func("PlayerActing").Call())
		return 0
	most := StatOr("discardmax", 3) + 0
	cards := []
	Loop, Parse, LastHandAnswer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		;(not a card - the deck's back, the timer, a popup where a card should be: never clicked)
		if (f.Length() < 12 || f[1] != "card" || (f.Length() >= 15 && f[15] = "0"))
			continue
		cards.Push({x: f[2] + f[4] / 2, y: f[3] + f[5] * 0.6, known: f[6], grey: f[8] + 0, l: f[2] + 0, w: f[4] + 0, tc: f.Length() >= 16 ? f[16] + 0 : 0})
		}
	;(where the battle's own search found its cards this round - one of them learned again at another UI size, under
	;its own name, is still that slot's card)
	own := []
	for k, o in [[hit1, hit1X], [hit2, hit2X], [hit3, hit3X], [hit4, hit4X], [wand, wandX], [heal1, heal1X], [heal2, heal2X]
		, [blade, BladeX], [blade3, Blade3X], [blade4, Blade4X], [sharpen, SharpX], [potent, PotentX], [trap, trapX]
		, [trap3, trap3X], [aura, auraX], [tower, towerX], [reshuffle, reshuffleX], [feint, feintX], [bubble, bubbleX], [convert, convertX]]
		if (o[1] == 1 && o[2] != "")
			own.Push(o[2])
	did := 0, i := 1
	while (i <= cards.Length() && did < most)
		{
		c := cards[i]
		if (InStr(c.known, "learned/") != 1)
			{
			i += 1
			continue
			}
		pid := SubStr(c.known, 9)
		;(put in a slot this round - the hand was read before it got one: the bot plays it now - a blade, trap or
		;aura with a slot free for it: not thrown away for a moment's failed look at the slot - one you said never to
		;discard, or a treasure card: discarding one uses it up)
		lc := LearnCardOf(pid)
		;(nor one of a kind it doesn't know: some aren't cards at all, and some are real cards learned again at a new
		;UI size before their kind could be read - nor one the battle's search found as its own)
		ox := ""
		for k, o in own
			if (o >= c.l - 5 && o <= c.l + c.w)
				ox := o
		;(an enchant - a treasure card's Monstrous, say - is never thrown away: it goes on a hit, slot or no slot
		;(CastLearnedHit); nor a card the hand's look says is a treasure card)
		;(nor a Reshuffle: never thrown away - the way back to a full deck, 2026-10-25)
		if (LearnSlotOf(pid) != "" || ox != "" || !IsObject(lc) || lc.type = "" || LearnHasFlag(lc, "hold") || LearnHasFlag(lc, "tc") || LearnIsReshuffle(lc)
			|| lc.type = "enchant" || c.tc = 1
			;(nor a blade or trap at all: the bot can't yet tell the school it boosts - a pet's Storm Blade on a Balance
			;support boosts the Storm hitter, an Elemental Blade a Balance wizard's Hydra - so it was thrown away as having
			;no slot, 2026-10-23; an aura only with a slot)
			|| lc.type = "blade" || lc.type = "trap" || (lc.type = "aura" && LearnSlotFor(lc) != "")
			;(nor a Tower Shield - the game's name for it, or yours - while the game's hand is read: the bot casts one no
			;picture finds at its box - KillCalc.ahk TowerMem, Autofarmer.ahk UseMemAt; another shield - a school's, a
			;team's - in no slot is never cast: thrown away as before)
			|| (lc.type = "ward" && Stat("usetower") && BoostMemOk && RegExMatch(LearnFlag(lc, "game") "|" lc.name, "i)\btower\s*shield\b"))
			;(a hit of the school while no hit1-3 in hand can go: cast this round instead - LearnHitCards)
			|| (LearnIsHit(lc) && Stat("learnedhits") && !((hit1 == 1 && Affordable("hit1")) || (hit2 == 1 && Affordable("hit2")) || (hit3 == 1 && Affordable("hit3")))))
			{
			i += 1
			continue
			}
		why := LearnWhyUnused(pid)
		MoveToCard(Round(c.x), Round(c.y))
		s(Stats.HasKey("clickwait") ? Stats["clickwait"] : 40)
		Click, right
		did += 1
		DebugLog("  Discarded learned card " pid " - " why " (right-click at " Round(c.x) - GameLeft "," Round(c.y) - GameTop ")")
		cards.RemoveAt(i)
		for k, o in cards
			o.x += (k < i ? HalfPitch : -HalfPitch)
		s(Stat("discardafter"))
		}
	;(the hand has changed: a fresh look next time - Vision.ahk keeps its picture of it for 400 ms)
	if (did)
		CenterMouse(), VisionForget()
	return did
	}

;The slot learned card id is used as ("" none, or not a learned card)
LearnSlotOf(id)
	{
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			if (c.id = id)
				return c.slot
	return ""
	}

;Learned card id's catalog entry ("" if it isn't one)
;A learned card the battle can cast as a hit when it's in no slot (LearnHitCards): one enemy or all, of the school
;the bot hits with
LearnIsHit(c)
	{
	return IsObject(c) && (c.type = "damage" || c.type = "aoe") && c.sch = hitschool && hitschool != ""
	}

;The learned hits in no slot in hand answer (a /hand read) that can go now - in colour, a card, of the school, pips
;you have (pips unread: tried - the cast's check tells), not one that didn't go this battle with as many pips as now
;(LearnHitFails: an off-school card's power pips count 1 in the game, 2 here), strongest first (LearnHitRank): [{x,
;y (where to click it), id, c (its catalog entry)}]
LearnHitCards(answer)
	{
	list := []
	if (answer = "" || !IsObject(LearnedCards) || !Stat("learnedhits"))
		return list
	if (!IsObject(LearnHitFails))
		LearnHitFails := {}
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card" || f[8] = 1 || (f.Length() >= 15 && f[15] = "0") || InStr(f[6], "learned/") != 1)
			continue
		c := LearnCardOf(SubStr(f[6], 9))
		if (!LearnIsHit(c))
			continue
		;(the cost: its pips read - 0 on a hit is X-pip, all you have, at least one)
		if (PipsNow >= 0 && c.pips != "" && !c.guess && PipsNow < Max(c.pips, 1))
			continue
		if (LearnHitFails.HasKey(c.id) && PipsNow <= LearnHitFails[c.id])
			continue
		e := {x: f[2] + f[4] / 2, y: f[3] + f[5] * 0.45, id: c.id, c: c, rank: LearnHitRank(c)}
		at := 1
		while (at <= list.Length() && list[at].rank >= e.rank)
			at++
		list.InsertAt(at, e)
		}
	return list
	}

;How strong a learned hit is, to cast the strongest first: its damage when it's sure (two reads agreed), else its pips
;when read (a guess says nothing), else 0 - one key for all, so the order holds
LearnHitRank(c)
	{
	v := LearnValueKnown(c)
	;(an X-pip hit: its damage a pip times the pips you have)
	if (v != "" && LearnHasFlag(c, "xpip"))
		v *= Max(PipsNow, 1)
	if (v != "")
		return 100000 + v
	return (c.pips != "" && !c.guess) ? c.pips + 0 : 0
	}

;A learned hit in no slot in this round's hand read (LastHandAnswer) that can go now - for "is there a hit to cast"
;(CardHitReady). Not once the round's discarded something: that read's out of date
;Learned hits in no slot that didn't go this battle: id -> the pips there were then (ResetVariables empties it)
global LearnHitFails

LearnHitReady()
	{
	global Discards
	return !Discards && LearnHitCards(LastHandAnswer).Length() > 0
	}

;A fresh look at the hand, as LearnCards' (learned cards known by their pictures) but writing no thumbnails and
;cutting nothing new - the hand may have re-centred since the round's read. "" if the helper didn't answer
LearnHandRead()
	{
	if (!VisionOn || hitschool = "" || !IsObject(LearnedCards))
		return ""
	learnedList := "", learnedPics := ""
	for i, c in LearnedCards
		if (c.sch = hitschool || InStr(c.slot, "resources\") = 1)
			{
			learnedList .= c.id ":" c.dir ":" c.slot ","
			if (c.slot = "")
				learnedPics .= ",learned/" c.id
			}
	return VisionGet("/hand?x1=" Round(ScreenX - HandHalf) "&y1=" Round(ScreenY - Px(75)) "&x2=" Round(ScreenX + HandHalf) "&y2=" Round(ScreenY + Px(150)) "&scale=" Round(UiScale, 3) "&pics=" VisionPicList() learnedPics "&learned=" LearnUri(learnedList), 3000)
	}

LearnCardOf(id)
	{
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			if (c.id = id)
				return c
	return ""
	}

;The learned card in slot rel (e.g. "balance\hit2") - "" none (your own picture, or nothing)
LearnCardInSlot(rel)
	{
	if (IsObject(LearnedCards) && rel != "")
		for i, c in LearnedCards
			if (c.slot = rel)
				return c
	return ""
	}

;A card's name, for you: the one typed on the Spells tab, else the first words of its text, else "?"
LearnName(c)
	{
	if (!IsObject(c))
		return "?"
	if (c.name != "")
		return c.name
	if (c.text != "")
		{
		w := StrSplit(c.text, " ")
		return "(" w[1] (w.Length() > 1 ? " " w[2] : "") (w.Length() > 2 ? " " w[3] : "") ")"
		}
	return "?"
	}

;How sure the learner is of what it took card c for, 0-100 ({pct, why}): its kind (40 - read alike twice or its icon
;the same; 25 read once), its number (35 - read alike twice; 15 once; a kind with no number: all 35) and its pips
;(25 read off the card or an X; 10 guessed). Set by you (Spells tab): what's there counts as read alike twice - what's
;blank still not known. Read from the game's memory (flag mem: its kind, number and pips the game's): 100%
LearnSure(c)
	{
	if (!IsObject(c))
		return {pct: 0, why: "-"}
	if (LearnHasFlag(c, "mem"))
		return {pct: 100, why: "read from the game"}
	user := LearnHasFlag(c, "user")
	two := user || LearnHasFlag(c, "two"), icon := LearnFlag(c, "icon")
	if (c.type = "")
		k := 0, kw := "kind not known"
	else if (two || (icon != "" && icon = c.type))
		k := 40, kw := "kind read " (two ? "alike twice" : "and its icon agree")
	else
		k := 25, kw := "kind read once"
	if (!InStr(",damage,aoe,heal,ward,blade,trap,aura,dot,enchant,", "," c.type ","))
		v := c.type = "" ? 0 : 35, vw := c.type = "" ? "" : "no number needed"
	else if (c.value = "")
		v := 0, vw := "number not read"
	else if (two)
		v := 35, vw := "number read alike twice"
	else
		v := 15, vw := "number read once"
	if (LearnHasFlag(c, "xpip"))
		p := 25, pw := "X pips"
	else if (c.pips = "")
		p := 0, pw := "pips not known"
	else if (c.guess)
		p := 10, pw := "pips guessed"
	else
		p := 25, pw := "pips read"
	if (user)
		return {pct: k + v + p, why: "set by you" (c.type = "" ? ", kind not known" : "") (v = 0 && c.type != "" ? ", number not known" : "") (p < 25 ? ", " pw : "")}
	return {pct: k + v + p, why: kw (vw != "" ? ", " vw : "") ", " pw}
	}

;A card whose icon wasn't one the helper knows (a blade's is a charm's), whose text says it's a blade: "+25% to next
;spell" - the + often read as something else, or lost. Not a "-25%" (a weakness, a shield), nor a Sharpen (it's put
;on a blade - its text says so). Now only for cards an older version learned (LearnLoad): new ones need the charm icon.
;Never one with a shield's icon (icon=ward - a shield's or a trap's): its - or + lost ("?50% to next" - a Tower Shield,
;a Thermic Shield, learned 2026-10-24 by OCR) made it a blade at every load, 2026-10-25
LearnLooksBlade(c)
	{
	return (c.type = "" || c.type = "blade") && LearnIconOf(c) != "ward" && RegExMatch(c.text, "i)\d{1,3}\s*%\s*to\s*next") && !RegExMatch(c.text, "-\s*\d{1,3}\s*%") && !RegExMatch(c.text, "i)blade")
	}

;Why learned card id isn't one the bot plays (for the log)
LearnWhyUnused(id)
	{
	c := LearnCardOf(id)
	if (!IsObject(c))
		return "the bot has no use for it"
	return LearnDescribe(c) ": " LearnWhyNot(c)
	}

;Why learned card c is in no slot - from what's known already (never asks the helper: the Spells tab uses it)
LearnWhyNot(c)
	{
	out := LearnFlag(c, "out")
	if (out != "")
		{
		o := LearnCardOf(out)
		return "taken out by " (IsObject(o) ? LearnName(o) : out) ", a stronger hit"
		}
	if (c.type = "keep")
		return (LearnHasFlag(c, "mem") && !LearnHasFlag(c, "user")) ? "a kind the bot doesn't play (the game's: " c.text ")" : "you chose not to use it"
	if (c.type = "")
		return "a kind the bot doesn't know"
	if (!LearnPlayed(c.type))
		return "a kind the bot doesn't play: " LearnKindLabel(c.type)
	if (IsObject(LearnArrangeQueue))
		for i, job in LearnArrangeQueue
			if (job = "p|" c.id)
				return "no free slot - room is made for it after this battle if it's strong enough"
	if ((c.type = "damage" || c.type = "aoe") && LearnValueKnown(c) = "")
		return "no free slot for it (its numbers weren't read for sure)"
	if ((c.type = "blade" || c.type = "trap") && LearnFlag(c, "boost") != "")
		return "no free slot for a " c.type " that boosts " (LearnFlag(c, "boost") = "all" ? "every school" : StrReplace(LearnFlag(c, "boost"), "+", ", ")) (c.value != "" ? " at " c.value "%" : "")
	if (c.type = "blade" || c.type = "trap" || c.type = "aura")
		return "no free slot for it at its % (PlayerStats.txt counts its slot at another)"
	return "no free slot for it"
	}

;What learned card c is used as, for the Spells tab's In use column: its slot, else "kept: <why>"
LearnInUse(c)
	{
	if (c.slot != "")
		return c.slot
	return "kept: " LearnWhyNot(c) (LearnHasFlag(c, "hold") ? " - never discarded" : LearnHasFlag(c, "tc") ? " - a treasure card, never discarded" : "")
	}

;---- Learn every card (dashboard button / tray menu) ----
;For a deck made to be learned (one of every card): in a battle, every round it learns what's in hand (in
;colour) as usual, then right-clicks away every card it knows - so the next round draws new ones - keeping
;greyed-out ones it doesn't know (their colours can't be read) till there are pips to show them in colour.
;It casts nothing but a heal when your health is low, and passes. It stops by itself once the deck is used
;up (two rounds with an empty hand) or nothing new has come for three rounds.

;On / off
;The mouse on the hand - where a card under it is drawn zoomed up (2026-10-24 at 1440p, UI 1.144: a card 655-781 high
;grows to 620-815 hovered, over its neighbours): cut or read like that, it's learned wrong
LearnMouseOnHand()
	{
	MouseGetPos, mx, my
	return (Abs(mx - ScreenX) <= HandHalf && my >= ScreenY - Px(95) && my <= ScreenY + Px(85))
	}

;Before the hand's read for learning: the mouse off it (above the hand, on the scene - not Pass or Draw) and a moment
;for a zoomed card to go back down, the hand looked at afresh. Already off it (the round's CenterMouse): nothing
LearnMouseClear()
	{
	if (!LearnMouseOnHand())
		return
	MouseMove, ScreenX, Min(GameTop + Round(GameH * 0.4), ScreenY - Px(150)), MouseSpeedNow()
	Sleep, 250
	VisionForget()
	}

LearnAllToggle()
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	LearnAll := !LearnAll
	if (LearnAll)
		{
		LearnAllFrom := LearnedCards.Length(), LearnAllSeen := LearnAllFrom, LearnAllRounds := 0, LearnAllIdle := 0, LearnAllEmpty := 0
		DebugLog("Learn every card: on - in a battle it casts nothing (a heal when low), learns the hand, discards what it knows and passes, till the deck is used up")
		TrayTip, Wizard101 bot, Learn every card: ON. Start a battle (an easy one) with the deck - it casts nothing`, learns each hand`, discards what it knows to draw new cards`, and passes., 10, 1
		}
	else
		LearnAllDone("switched off")
	if (IsFunc("DashLearnShow"))
		Func("DashLearnShow").Call(LearnAll)
	}

;The mode ends: says how many it learned
LearnAllDone(why)
	{
	LearnAll := 0
	got := (IsObject(LearnedCards) ? LearnedCards.Length() : 0) - LearnAllFrom
	DebugLog("Learn every card: off (" why ") - " got " new card" (got = 1 ? "" : "s") " learned in " LearnAllRounds " round" (LearnAllRounds = 1 ? "" : "s"))
	if (why != "switched off")
		{
		SoundPlay, *64
		TrayTip, Wizard101 bot, % "Learn every card: done (" why ") - " got " new card" (got = 1 ? "" : "s") " learned. The bot plays normally again; with the deck used up, finish or flee this battle yourself.", 15, 1
		}
	if (IsFunc("DashLearnShow"))
		Func("DashLearnShow").Call(0)
	}

;One round of it, after the hand's been read and learned (LastHandAnswer): right-clicks every card it knows
;(in colour - learned by now if it could be - or greyed out but known) from the left, following the hand as
;it re-centres (a card gone: those left of it slide right half a card, those right of it slide left). Never a
;box that isn't a card
LearnAllRound()
	{
	global
	local cards, f, c, i, k, o, did, kept, before, lc
	LearnAllRounds += 1
	if (LastHandAnswer = "")
		{
		DebugLog("  learn every card: the hand wasn't read this round (vision helper?) - just passing")
		return
		}
	cards := []
	Loop, Parse, LastHandAnswer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card" || (f.Length() >= 15 && f[15] = "0"))
			continue
		cards.Push({x: f[2] + f[4] / 2, y: f[3] + f[5] * 0.6, known: f[6], grey: f[8] + 0, tc: (f.Length() >= 16 && f[16] = 1)})
		}
	if (!cards.Length())
		{
		LearnAllEmpty += 1
		DebugLog("  learn every card: no cards in hand (" LearnAllEmpty " round" (LearnAllEmpty = 1 ? "" : "s") ")")
		if (LearnAllEmpty >= 2)
			LearnAllDone("the deck is used up")
		return
		}
	LearnAllEmpty := 0, did := 0, kept := 0, i := 1
	while (i <= cards.Length())
		{
		c := cards[i]
		;(nor a treasure card - discarding one uses it up - nor one you said never to discard)
		lc := (InStr(c.known, "learned/") = 1) ? LearnCardOf(SubStr(c.known, 9)) : ""
		if ((c.grey && c.known = "") || c.tc || (IsObject(lc) && (LearnHasFlag(lc, "tc") || LearnHasFlag(lc, "hold"))))
			{
			kept += 1, i += 1
			continue
			}
		MoveToCard(Round(c.x), Round(c.y))
		s(Stats.HasKey("clickwait") ? Stats["clickwait"] : 40)
		Click, right
		did += 1
		cards.RemoveAt(i)
		for k, o in cards
			o.x += (k < i ? HalfPitch : -HalfPitch)
		s(Stat("discardafter"))
		}
	CenterMouse()
	;(nothing learned or discarded: the greyed-out ones it keeps aren't coming into colour)
	before := LearnAllIdle
	LearnAllIdle := (did = 0 && LearnedCards.Length() = LearnAllSeen) ? LearnAllIdle + 1 : 0
	LearnAllSeen := LearnedCards.Length()
	DebugLog("  learn every card: discarded " did ", kept " kept " greyed-out unknown" (kept = 1 ? "" : "s") " - " LearnedCards.Length() - LearnAllFrom " new so far")
	if (LearnAllIdle >= 3)
		LearnAllDone("nothing new for 3 rounds")
	}

;---- Reading the hand ----

;Called once a round after the hand's been looked at (FindCards). True if a card went into a slot (or a
;slot's learned picture was just made to fit a copy that differs a little): look at the hand again, so
;it's used this round. picFix 0: no boost slot picture counted as missed (LearnBoostPicFix) - Draw.ahk's call after a
;treasure card's drawn, against a look at the hand taken before the draw
LearnCards(picFix := 1)
	{
	if (!VisionOn || hitschool = "")
		return false
	if (!IsObject(LearnedCards))
		LearnLoad()
	;(this school's learned cards - and shields, which go in a slot of every school's - also by
	;themselves: copies of a card differ a little, so a picture cut from one copy is compared leaving out
	;the pixels that differ most, and those go see-through in it; vision.py. The ones in no slot are
	;looked for too, but only here - the battle's own search never asks about them)
	learnedList := "", learnedPics := "", LearnFreeCache := {}, LearnRereadsLeft := 2
	for i, c in LearnedCards
		if (c.sch = hitschool || InStr(c.slot, "resources\") = 1)
			{
			learnedList .= c.id ":" c.dir ":" c.slot ","
			if (c.slot = "")
				learnedPics .= ",learned/" c.id
			}
	here := LearnSetDir(false)
	hereRel := SubStr(here, StrLen(A_WorkingDir) + 2)
	;(no card zoomed up by the mouse when it's read)
	LearnMouseClear()
	answer := VisionGet("/hand?x1=" Round(ScreenX - HandHalf) "&y1=" Round(ScreenY - Px(75)) "&x2=" Round(ScreenX + HandHalf) "&y2=" Round(ScreenY + Px(150)) "&scale=" Round(UiScale, 3) "&pics=" VisionPicList() learnedPics "&learned=" LearnUri(learnedList) "&here=" LearnUri(hereRel) "&thumbs=" LearnUri(A_ScriptDir "\generated\hand"), 3000)
	if (answer = "")
		return false
	LastHandAnswer := answer
	;(what's in hand, for the dashboard)
	DashHandSeen(answer)
	;(a card learned at another UI size was cut into a new folder for this size: a picture set from now on)
	if (InStr(FileExist(here), "D"))
		LearnSetDir(true)
	;(the cards as the game's memory has them - read, not guessed - laid on the boxes: LearnMemHand)
	mem := LearnMemHand(answer)
	placed := 0, fresh := 0, greyNew := 0, relook := 0, setsBefore := PicSets.Length(), boxes := 0, notCards := 0, noPips := 0, onHand := 0, enchNew := 0
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card")
			continue
		boxes += 1
		;(not a card where one should be - the deck's back, the floor, the timer, a popup: never learned, and not
		;looked at again; vision.py)
		if (f.Length() >= 15 && f[15] = "0")
			{
			notCards += 1
			continue
			}
		card := {left: f[2] + 0, top: f[3] + 0, known: f[6], grey: f[8] + 0, type: f[9], pips: f[11], same: f[13] + 0
			, isCard: (f.Length() >= 16 && f[15] = 1), tc: (f.Length() >= 16 && f[16] = 1), mem: (IsObject(mem) && mem.HasKey(boxes)) ? mem[boxes] : ""}
		;(the game's name of the card on a hit slot's picture - your own cut one too: its heads are read off the game's hand
		;by it - KillCalc.ahk HitHeads; the newest wins)
		if (IsObject(card.mem) && RegExMatch(card.known, "^(\w+)/(hit[1-4]|wand)$", lcSg) && lcSg1 = hitschool)
			{
			if (!IsObject(SlotGame))
				SlotGame := {}
			if (SlotGame[card.known] != LearnMemGame(card.mem))
				SlotGame[card.known] := LearnMemGame(card.mem), HeadsMemo := {}
			}
		;(a slot's learned picture was just written - made see-through where this copy differs, or cut at
		;this UI size - so the battle's own search finds the card if the hand's looked at again)
		if (f[14] = 1)
			relook := 1
		if (card.known != "")
			placed += LearnSeenAgain(card)
		else if (card.grey)
			greyNew++
		;(another copy of a new card further left: learned with that one)
		else if (card.same)
			continue
		;(learned only where the helper says it's a card, and with your pips read - unread, the hand may not be
		;where it's looked for; the game's memory has its pips itself)
		else if (!card.isCard)
			continue
		;(an enchanted card the bot doesn't know by its picture: its picture is the enchanted one's, not the card's -
		;learned when it shows up plain)
		else if (IsObject(card.mem) && card.mem.ench != "")
			enchNew++
		else if (PipsNow < 0 && !(IsObject(card.mem) && card.mem.pips != ""))
			noPips++
		;(the mouse moved onto the hand since - yours: the card under it zoomed up - none learned now, next round)
		else if (onHand || LearnMouseOnHand())
			onHand += 1
		;(two new cards a round at most: each takes about half a second - four from the game's memory: no OCR)
		else if (fresh < 2 || (IsObject(card.mem) && fresh < 4))
			{
			fresh++
			placed += LearnNew(card)
			}
		;(a blade, trap or Tower Shield the game names here whose slot's picture never finds it: the card's own put there -
		;LearnBoostPicFix)
		if (picFix && IsObject(card.mem))
			placed += LearnBoostPicFix(card, f)
		}
	;(the learned cards you named that the game has in hand - any wizard's, never named by the game: put right -
	;LearnMemNamed)
	placed += IsFunc("LearnMemNamed") ? Func("LearnMemNamed").Call() : 0
	if (enchNew)
		DebugLog("  " enchNew " enchanted card(s) in hand the bot doesn't know by their picture - learned when they show up plain")
	if (boxes && notCards = boxes)
		DebugLog("  none of the " boxes " box(es) where the hand should be looks like a card - the hand may not be where it's looked for (vision\vision.log): nothing learned")
	if (greyNew)
		DebugLog("  " greyNew " card(s) in hand the bot doesn't know are greyed out (not enough pips) - learned once they're in colour")
	if (noPips)
		DebugLog("  " noPips " new card(s) in hand not learned: your pips couldn't be read this round")
	if (onHand)
		DebugLog("  " onHand " new card(s) in hand not learned this round: the mouse is on the hand (a card under it is drawn zoomed up)")
	;(new pictures in a slot, or a new picture set: the helper and PicPath look again)
	if (placed || PicSets.Length() != setsBefore)
		{
		PicMade := {}
		VisionGet("/forget", 3000)
		}
	VisionForget()
	return (placed > 0 || relook)
	}

;A card the bot doesn't know: saved, read and put to use. 1 if it went into a slot
LearnNew(card)
	{
	setDir := LearnSetDir()
	FormatTime, stamp,, yyMMddHHmmss
	id := "c" stamp "_" Mod(Round(card.left), 10000)
	cut := Trim(VisionGet("/cut?left=" card.left "&top=" card.top "&scale=" Round(UiScale, 3) "&out=" LearnUri(setDir "\learned\" id), 3000), " `t`r`n")
	;(only "OK" is a card saved: NOTCARD - the helper looked again and it isn't one - saves nothing)
	if (cut != "OK")
		{
		if (InStr(cut, "NOTCARD") = 1)
			DebugLog("  not a card - not learned (" Trim(SubStr(cut, 8)) ")")
		else
			DebugLog("  a new card in hand couldn't be saved (vision\vision.log)")
		return 0
		}
	;(the game's memory read it - its name, kind, numbers, pips, school, treasure / item card as they are: no OCR, nothing
	;guessed; else its text read with OCR)
	fromGame := IsObject(card.mem)
	r := fromGame ? LearnMemRead(card.mem) : LearnReadCard(card, card.type, hitschool)
	;(the game had no kind for it - its effects cut short: its kind and numbers read off the card as before; its name,
	;school and pips still the game's)
	if (fromGame && !r.sure)
		{
		ro := LearnReadCard(card, card.type, hitschool)
		r.kind := ro.kind, r.value := ro.value, r.extra := ro.extra, r.two := ro.two
		}
	if (!fromGame && !r.two && r.text != "")
		DebugLog("  the new card's text couldn't be read alike twice (""" r.text """) - " (r.kind = "" ? "its kind isn't known" : "its numbers count as unknown"))
	c := {id: id, sch: hitschool, type: r.kind, pips: fromGame ? r.pips : card.pips, guess: 0, value: r.value, target: (r.kind = "damage") ? 1 : 0, slot: ""
		, scale: Round(UiScale, 3), dir: SubStr(setDir, StrLen(A_WorkingDir) + 2), when: A_Now, text: r.text, name: fromGame ? r.name : "", flags: "ok"}
	if (card.type != "")
		LearnSetFlag(c, "icon", card.type)
	if (fromGame)
		{
		LearnSetFlag(c, "game", r.game)
		if (r.sure)
			LearnSetFlag(c, "mem")
		if (r.school != "" && r.school != hitschool)
			LearnSetFlag(c, "school", r.school)
		if (r.tc)
			LearnSetFlag(c, "tc")
		if (r.item)
			LearnSetFlag(c, "item")
		;(what it does by school, as the game has it: a hit's heads - Hydra's fire, ice and storm, KillCalc.ahk HitHeads -, a
		;blade's or trap's schools - the slot it goes in, LearnBoostSlot)
		if (r.sure && (r.kind = "damage" || r.kind = "aoe") && r.heads != "")
			LearnSetFlag(c, "heads", r.heads)
		if (r.sure && (r.kind = "blade" || r.kind = "trap" || r.kind = "aura") && r.boost != "")
			LearnSetFlag(c, "boost", r.boost)
		}
	else if (card.tc)
		LearnSetFlag(c, "tc")
	if (r.two && !fromGame)
		LearnSetFlag(c, "two")
	LearnSetExtra(c, r.extra)
	;(no pip digit read: it's in colour, so it costs no more than the pips you have - a guess. A digit read is the
	;card's own, kept even when it's more than you have: the game doesn't grey out every card you can't afford)
	;(an X-pip spell - its text says per pip: its cost is X, all your pips (0 here), not a guess - an X isn't a digit)
	;(a 0 read off any other deck hit is no pip count - the digit misread: guessed instead - but not the game's own 0)
	if (LearnHasFlag(c, "xpip"))
		c.pips := 0, c.guess := 0
	else if (!fromGame && c.pips = 0 && (c.type = "damage" || c.type = "aoe") && !card.tc)
		c.pips := ""
	if (c.pips = "")
		c.pips := PipsNow, c.guess := 1
	else if (!fromGame && c.pips > PipsNow)
		DebugLog("  its pip digit reads " c.pips " - more than the " PipsNow " you have (kept: it's the card's own)")
	LearnedCards.Push(c)
	got := LearnPlace(c)
	LearnSave()
	where := c.slot != "" ? "using it as " c.slot : "kept, not used (" LearnWhyNot(c) ")"
	DebugLog("  learned a new card" (fromGame ? " (read from the game)" : "") ": " LearnDescribe(c) " - " where " (picture: " c.dir "\learned\" id ".card.png)")
	TrayTip, Wizard101 bot, % "New card learned: " LearnDescribe(c) "`n" (c.slot != "" ? "Using it as " c.slot "." : "Kept, not used yet."), 5, 1
	return got
	}

;A card's kind and numbers, from its text: read with OCR at three sizes (LearnKindOf each), what two reads agree on
;(OCR misreads now and then - Scorpion's 160-200 once came out 260-200): {kind, value, extra, two (two reads agreed),
;text}. None agree: a kind the bot doesn't play that one read found (never cast anyway), else its icon's kind with its
;numbers unknown. Any read with damage over time's mark ("over 3 rounds", "(3)") and only one number: never a plain hit
LearnReadCard(card, icon, sch := "")
	{
	k := UiScale, votes := {}, reads := [], agreed := ""
	for each, zoom in [3, 2, 4]
		{
		;(two agree on a plain hit: the third read anyway, for a damage over time mark the two missed)
		if (IsObject(agreed) && !((agreed.kind = "damage" || agreed.kind = "aoe") && agreed.extra = ""))
			break
		t := OcrRect(card.left + Round(2.6 * k), card.top + Round(74.3 * k), Round(65.6 * k), Round(29.7 * k), "en", zoom)
		t := LearnClean(Trim(RegExReplace(t, "[|\r\n]+", " ")))
		r := LearnKindOf(t, icon, sch)
		r.text := t, r.mark := LearnDotMark(t)
		reads.Push(r)
		if (r.kind = "" || IsObject(agreed))
			continue
		key := r.kind "|" r.value
		votes[key] := (votes.HasKey(key) ? votes[key] : 0) + 1
		if (votes[key] >= 2)
			agreed := r
		}
	if (IsObject(agreed))
		res := {kind: agreed.kind, value: agreed.value, extra: agreed.extra, two: 1, text: agreed.text}
	else
		{
		res := {kind: "", value: "", extra: "", two: 0, text: ""}
		for i, r in reads
			if (res.text = "" && r.text != "")
				res.text := r.text
		for i, r in reads
			if (r.kind != "" && !LearnPlayed(r.kind))
				{
				res.kind := r.kind, res.extra := r.extra, res.text := r.text
				break
				}
		if (res.kind = "" && (icon = "damage" || icon = "aoe" || icon = "heal"))
			res.kind := icon
		}
	if ((res.kind = "damage" || res.kind = "aoe") && !InStr(res.extra, "dot="))
		for i, r in reads
			{
			if (!r.mark)
				continue
			if (r.kind = "dot")
				{
				res.kind := "dot", res.value := "", res.extra := r.extra, res.two := 0, res.text := r.text
				break
				}
			if (InStr(r.extra, "dot=") && (res.value = "" || r.value = res.value))
				res.extra := r.extra
			}
	return res
	}

;Whether text has damage over time's mark: "over 3" (OCR: "onr 3", "owr 3"), "(3)" / "($3)", "Rounds", "rds"
LearnDotMark(text)
	{
	return RegExMatch(text, "i)over\s*\d|(?<![a-z])o\S{0,2}r\s*\d|\(\s*\S{0,2}\s*\d\s*\)|r[o0]unds?\b|\brds\b") > 0
	}

;A card's kind from the text read off it and its icon (cardicons\: damage, aoe, heal, ward, charm, manip; "" none) -
;{kind, value, extra}: extra "dot=<n>" (damage over time besides the hit), "xpip". sch: the card's school (an aura
;names it, or "all spells"). In this order: a stun ("Stun all enemies"), a dispel, a prism ("Convert next..."),
;"N times Clear"; a hit (damage / aoe icon, or none with a range - "all enemies" an aoe): its range's lowest, the
;up-front number when there's damage over time too ("540 + 435 (3)"), damage over time alone ("525 over 3 rounds",
;"950 (3)"), an X-pip spell ("85 per pip"); a heal; a % - a shield icon's "-50%" a shield, its "+25%" a trap, a charm's
;"+25% to next" a blade (its "-%" a weakness), "+15% to all spells" an aura; else unknown (kind ""). Numbers of two
;digits or more only (OCR makes single ones out of nothing)
LearnKindOf(text, icon, sch := "")
	{
	t := Trim(RegExReplace(RegExReplace(text, "[|/]", " "), "\s+", " "))
	StringLower, low, t
	none := {kind: "", value: "", extra: ""}
	hasPct := RegExMatch(t, "O)([-+])?\s*(?<!\d)(\d{1,2}|100)\s*%", pm)
	sign := hasPct ? pm.Value(1) : ""
	if (RegExMatch(low, "\bs[tl1]un\b") && icon != "damage" && icon != "aoe")
		return {kind: "stun", value: "", extra: ""}
	if (RegExMatch(low, "d[il1]spe[l1i]"))
		return {kind: "dispel", value: "", extra: ""}
	if (RegExMatch(low, "c[o0]nv[e3]rt"))
		return {kind: "prism", value: "", extra: ""}
	if (RegExMatch(low, "\bc[l1]ear\b"))
		return {kind: "clear", value: "", extra: ""}
	;(a damage enchant - Strong, Giant, Monstrous, Gargantuan, Colossal, Epic: "+175 [fist] to 1 spell" - a number that
	;isn't a % (OCR: "0175", "t175"), "spell" with no "next" / "all" / "enemies" / range / "per pip": the damage it adds,
	;when it's one PlayerStats.txt knows (enchantN) - Epic's accuracy % besides is allowed)
	if (icon != "heal" && icon != "ward" && RegExMatch(low, "\bsp\S{0,2}ll\b") && !RegExMatch(low, "n[eo]?xt|a[l1][l1]\s*(sp|en)|en[e3]m|\d\s*-\s*\d|per\s*p")
		&& RegExMatch(t, "(?<![\d%])0?(\d{2,3})(?!\s*%|\d)", em) && LearnEnchantLevel(sch, em1 + 0))
		return {kind: "enchant", value: em1 + 0, extra: ""}
	if ((icon = "damage" || icon = "aoe" || icon = "") && !hasPct)
		{
		at := RegExMatch(t, "i)over\s*\d|(?<![a-z])o\S{0,2}r\s*\d|\(\s*\S{0,2}\s*\d\s*\)|r[o0]unds?\b|\brds\b")
		head := at ? SubStr(t, 1, at - 1) : t
		nums := [], p := 1
		while (p := RegExMatch(head, "\d{2,}", nm, p))
			nums.Push(nm + 0), p += StrLen(nm)
		;(an X-pip hit - "85 per pip", its cost an X: all your pips - a hit, one enemy or all, played as one: 2026-10-24)
		if (RegExMatch(low, "per\s*p[il1]p"))
			return {kind: (icon != "") ? icon : RegExMatch(low, "a[l1][l1]\s*enem") ? "aoe" : "damage", value: nums.Length() ? nums[1] : "", extra: "xpip"}
		if (RegExMatch(head, "O)(\d+)\s*-\s*(\d+)", rm))
			{
			kd := (icon != "") ? icon : RegExMatch(low, "a[l1][l1]\s*enem") ? "aoe" : ""
			return (kd = "") ? none : {kind: kd, value: LearnRangeFix(rm.Value(1), rm.Value(2)), extra: ""}
			}
		if (at && nums.Length() = 1)
			return {kind: "dot", value: "", extra: "dot=" nums[1]}
		if (at && nums.Length() >= 2 && icon != "")
			return {kind: icon, value: nums[1], extra: "dot=" nums[2]}
		if (!at && nums.Length() && icon != "")
			return {kind: icon, value: nums[1], extra: ""}
		}
	if (icon = "heal")
		return {kind: "heal", value: RegExMatch(t, "\d{2,}", nm) ? nm + 0 : "", extra: ""}
	if (hasPct)
		{
		v := pm.Value(2) + 0
		nxt := RegExMatch(low, "n[eo]?xt")
		if (icon = "ward")
			return (sign = "-") ? {kind: "ward", value: v, extra: ""} : (sign = "+") ? {kind: "trap", value: v, extra: ""} : none
		if (icon = "charm" && nxt && !InStr(low, "blade"))
			return {kind: (sign = "-") ? "weakness" : "blade", value: v, extra: ""}
		if (!nxt && sign != "-" && (RegExMatch(low, "a[l1][l1]\s*sp") || (sch != "" && InStr(low, sch))))
			return {kind: "aura", value: v, extra: ""}
		}
	return none
	}

;A damage range's lowest ("65-105" -> 65), its digits mended where OCR mixes 3 with 8 and 5 with 6 when the range
;can't be right as read: Wizard101's tops are 1.1-1.7 times the bottoms, 30-120 more in tens ("805-345" -> 305,
;"245-805" -> 245). The fewest digits changed wins - "" when more than one way fits, or none does
LearnRangeFix(lo, hi)
	{
	a := lo + 0, b := hi + 0
	if (a > 0 && a <= b && b <= 2 * a)
		return a
	best := "", bestK := 99, many := 0
	for i, x in LearnSwaps(lo)
		for j, y in LearnSwaps(hi)
			{
			if (x.n <= 0)
				continue
			d := y.n - x.n
			if (y.n / x.n < 1.1 || y.n / x.n > 1.7 || d < 30 || d > 120 || Mod(d, 10))
				continue
			kk := x.k + y.k
			if (kk < bestK)
				bestK := kk, best := x.n, many := 0
			else if (kk = bestK && x.n != best)
				many := 1
			}
	return (best = "" || many) ? "" : best
	}

;Every way of reading digits ds with 3/8 and 5/6 swapped: [{n, k: how many swapped}]
LearnSwaps(ds)
	{
	;(the digit at each place in "3856" goes with the one at the same place in "8365" - an object's keys "3" etc.
	;would be numbers, never equal to a parsed character)
	at := []
	Loop, Parse, ds
		if (InStr("3856", A_LoopField))
			at.Push(A_Index)
	out := []
	Loop, % 1 << at.Length()
		{
		mask := A_Index - 1, s := ds, kk := 0
		for i, pos in at
			if (mask & (1 << (i - 1)))
				s := SubStr(s, 1, pos - 1) SubStr("8365", InStr("3856", SubStr(ds, pos, 1)), 1) SubStr(s, pos + 1), kk += 1
		out.Push({n: s + 0, k: kk})
		}
	return out
	}

;The number on a card's text that matters: a damage range's lowest (mended: LearnRangeFix), else the first number of
;two digits or more ("400 for Self", "-50% to next" -> 50). "" none
LearnValue(text, type := "")
	{
	if (RegExMatch(text, "O)(\d+)\s*-\s*(\d+)", m))
		return LearnRangeFix(m.Value(1), m.Value(2))
	if (RegExMatch(text, "\d{2,}", m))
		return m + 0
	return ""
	}

;Flags besides a kind (LearnKindOf's extra) onto learned card c: "dot=<n>", "xpip"
LearnSetExtra(c, extra)
	{
	if (RegExMatch(extra, "dot=(\d+)", m))
		LearnSetFlag(c, "dot", m1)
	if (InStr(extra, "xpip"))
		LearnSetFlag(c, "xpip")
	}

;Learned card c's icon: as read (flag icon=), else its kind where that came from the icon (the older versions'
;types), else ""
LearnIconOf(c)
	{
	ic := LearnFlag(c, "icon")
	if (ic != "")
		return ic
	return (c.type = "damage" || c.type = "aoe" || c.type = "heal" || c.type = "ward") ? c.type : ""
	}

;What a fresh read of learned card c's text (LearnReadCard), or its text classified again (LearnRecheckTexts), says -
;taken when two reads agreed, it found damage over time, or c's kind wasn't known (or its numbers, the same kind):
;never for a card you set on the Spells tab (flag user). A card whose kind changes leaves its slot; a hit whose numbers
;now put it out of order too. how: for the log. 1 if anything changed
LearnApplyRead(c, r, how)
	{
	;(nor for one read from the game's memory: its kind and numbers are the game's - only its text, when it has none)
	if (LearnHasFlag(c, "user") || LearnHasFlag(c, "mem") || r.kind = "")
		{
		if (c.text != "" || r.text = "")
			return 0
		c.text := r.text
		return 1
		}
	oldKind := c.type, oldValue := c.value, oldFlags := c.flags, oldText := c.text
	if (r.kind = c.type && (r.value = c.value || (!r.two && c.value != "")))
		{
		;(the same: what it tells besides - damage over time with the hit, X pips - and two reads agreeing now)
		if (r.value = c.value)
			{
			LearnSetExtra(c, r.extra)
			if (r.two)
				LearnSetFlag(c, "two")
			}
		}
	else if (r.two || r.kind = "dot" || c.type = "" || (r.kind = c.type && c.value = ""))
		{
		c.type := r.kind, c.value := r.value, c.target := (r.kind = "damage") ? 1 : 0
		if (r.two)
			LearnSetFlag(c, "two")
		else
			LearnDropFlag(c, "two")
		LearnDropFlag(c, "dot"), LearnDropFlag(c, "xpip"), LearnSetExtra(c, r.extra)
		if (LearnHasFlag(c, "xpip"))
			c.pips := 0, c.guess := 0
		}
	if (r.text != "" && (c.text = "" || r.two))
		c.text := r.text
	if (c.type == oldKind && c.value == oldValue && c.flags == oldFlags && c.text == oldText)
		return 0
	;(out of order first, its numbers after: one put in by an arrangement is put back with the numbers as they were)
	if (c.slot != "" && c.type != oldKind)
		LearnUnplace(c, "it's " LearnKindLabel(c.type) " now (" how ")")
	else if (c.slot != "" && c.value != oldValue)
		{
		if (RegExMatch(c.slot, "\\hit([1-4])$", hn) && !LearnHitFits(c, hn1))
			LearnUnplace(c, "its numbers now put it out of order with the other hits")
		else
			LearnStats(c)
		}
	return 1
	}

;A card the bot knows, seen again in colour: a learned one that isn't in a slot gets one if it can now;
;a guessed pip cost comes down to the pips you have. 1 if it went into a slot
LearnSeenAgain(card)
	{
	;(learned cards whose text was read again this run, at each UI size: id|scale)
	static reread := {}
	if (card.grey)
		return 0
	for i, c in LearnedCards
		{
		if (c.sch != hitschool && InStr(c.slot, "resources\") != 1)
			continue
		mine := (c.slot != "" && StrReplace(c.slot, "\", "/") = card.known) || ("learned/" c.id = card.known)
		if (!mine)
			continue
		changed := 0, got := 0
		;(known by its own name though it has a slot: the slot's picture isn't this card's any more - you
		;put another there - so it's out of that slot. Not while the slot's picture is still its own: its
		;.raw.png - never made see-through - is the same; nor in this UI size's set, where LearnBoostPicFix writes a slot's
		;new picture - a card learned at another size, the Tower Shield at 0.917 given resources\tower at 1.144)
		slotDir := A_WorkingDir (c.dir = "" ? "" : "\" c.dir), hereDir := LearnSetDir(false)
		if (c.slot != "" && "learned/" c.id = card.known && !LearnSameCard(slotDir "\" c.slot, slotDir "\learned\" c.id)
			&& !LearnSameCard(hereDir "\" c.slot, hereDir "\learned\" c.id))
			{
			DebugLog("  learned card " c.id " (" LearnDescribe(c) "): " c.slot " has another picture now - not using it there any more")
			c.slot := "", changed := 1
			}
		if (card.type != "" && LearnFlag(c, "icon") = "")
			LearnSetFlag(c, "icon", card.type), changed := 1
		;(the game's memory read it: what it says filled in - its name, kind, numbers, pips, school; never what you set -
		;and nothing below guessed or read off the card)
		;(a card never paired with the game before whose own kind or read pips the game's disagree with: the same game card
		;in that box a second time first - one wrong pairing would rewrite a good card. One you set is yours to differ: only
		;its blanks are filled in)
		memR := IsObject(card.mem) ? LearnMemRead(card.mem) : ""
		;(an object first: LearnMemWait is #Included blank, and a key set on a blank variable makes no object in AHK v1.1 -
		;the second sighting was never seen, 2026-10-24: Hex learned as a blade stayed one, never in resources\trap3)
		if (!IsObject(LearnMemWait))
			LearnMemWait := {}
		if (IsObject(memR) && LearnFlag(c, "game") = "" && memR.sure && !LearnHasFlag(c, "user")
			&& ((c.type != "" && c.type != memR.kind) || (!c.guess && c.pips != "" && memR.pips != "" && c.pips != memR.pips)))
			{
			if (LearnMemWait[c.id] != memR.game)
				{
				LearnMemWait[c.id] := memR.game
				DebugLog("  learned card " c.id " (" LearnDescribe(c) "): the game says " memR.game " (" LearnKindLabel(memR.kind) ") - put in when it's seen so again")
				memR := ""
				}
			else
				LearnMemWait.Delete(c.id)
			}
		if (IsObject(memR))
			{
			memWas := LearnDescribe(c)
			memGot := LearnApplyMem(c, memR)
			if (memGot)
				{
				changed := 1, got := (memGot = 2) ? 1 : got
				if (memWas != LearnDescribe(c))
					DebugLog("  learned card " c.id " read from the game: " memWas " -> " LearnDescribe(c))
				}
			}
		if (card.tc && !IsObject(card.mem) && !LearnHasFlag(c, "tc") && !LearnHasFlag(c, "notc"))
			LearnSetFlag(c, "tc"), changed := 1
		;(its pip digit read this time where the pips were only guessed: the card's own - a hit's never 0, that's X-pip)
		if (c.guess && !IsObject(card.mem) && RegExMatch(card.pips, "^\d+$") && card.pips != c.pips && !(card.pips = 0 && (InStr(c.slot, "\hit") || ((c.type = "damage" || c.type = "aoe") && !LearnHasFlag(c, "tc")))))
			{
			DebugLog("  learned card " c.id " (" LearnDescribe(c) "): its pip digit reads " card.pips " (was guessed)")
			c.pips := card.pips + 0, c.guess := 0, changed := 1
			if (c.slot != "")
				LearnStats(c)
			}
		else if (c.guess && !IsObject(card.mem) && RegExMatch(card.pips, "^\d+$") && card.pips = c.pips)
			c.guess := 0, changed := 1
		if (c.pips = "" && PipsNow >= 0)
			{
			c.pips := PipsNow, c.guess := 1, changed := 1
			if (c.slot != "")
				LearnStats(c)
			}
		;(its kind or numbers weren't read for sure when it was learned - e.g. in a small window: read again, once a
		;run at each UI size, two cards a round at most - never one you set on the Spells tab)
		rk := c.id "|" Round(UiScale, 2)
		if (!LearnHasFlag(c, "user") && !LearnHasFlag(c, "mem") && !IsObject(card.mem) && LearnRereadsLeft > 0 && !reread.HasKey(rk)
			&& (c.type = "" || c.text = "" || ((c.type = "damage" || c.type = "aoe" || c.type = "heal" || c.type = "enchant") && (c.value = "" || !LearnHasFlag(c, "two")))))
			{
			reread[rk] := 1, LearnRereadsLeft -= 1
			r := LearnReadCard(card, card.type != "" ? card.type : LearnIconOf(c), c.sch)
			was := LearnDescribe(c)
			if (LearnApplyRead(c, r, "read again"))
				{
				DebugLog("  learned card " c.id " read again (""" r.text """): " was " -> " LearnDescribe(c))
				changed := 1, got := 1
				}
			}
		;(a hit's pips never go to 0 that way: 0 means an X-pip spell there)
		low := (InStr(c.slot, "\hit") || ((c.type = "damage" || c.type = "aoe") && !LearnHasFlag(c, "tc"))) ? 1 : 0
		if (c.guess && !IsObject(card.mem) && PipsNow >= 0 && c.pips != "" && PipsNow < c.pips && PipsNow >= low)
			{
			DebugLog("  " (c.slot != "" ? c.slot : "learned card " c.id) " is in colour with " PipsNow " pips: it costs no more than that (was guessed " c.pips ")")
			c.pips := PipsNow, changed := 1
			if (c.slot != "")
				LearnStats(c)
			}
		;(a hit in a slot whose numbers changed: still in order with the other hits? Else out of it, and put
		;where it fits - 1 either way: the pictures changed)
		if (changed && RegExMatch(c.slot, "\\hit([1-4])$", hn) && !LearnHitFits(c, hn1))
			{
			LearnUnplace(c, "its numbers now put it out of order with the other hits")
			got := 1
			}
		if (c.slot = "" && LearnPlace(c))
			{
			got := 1
			DebugLog("  learned card " c.id " (" LearnDescribe(c) ") now in use as " c.slot)
			}
		if (changed || got)
			LearnSave()
		return got
		}
	return 0
	}

;---- The hand from the game's memory ----

;The cards as the game's memory has them (Vision.ahk VisionCards - read-only: names, kinds, numbers, pips; nothing
;guessed) laid on the helper's /hand answer: {n: the game's card} for its n-th card line - or "" when they can't be: no
;memory read this round (the game not read, not settled within 1.5 s: debug.log says why), not as many cards as the
;boxes that look like cards (left to right, card i is box i only when they're as many), or a box the bot knows as a
;learned card that the game named otherwise before (flag game=: the boxes and the cards don't line up)
LearnMemHand(answer)
	{
	static saidOff := {}
	;(this pass's answer if it's 3 s old at most - PipsRead's: FindCards' VisionForget clears it when the hand changed)
	lmhHand := VisionCards(1500, 3000)
	if (!IsObject(lmhHand))
		{
		if (VisionCardsWhy != "" && !InStr(VisionCardsWhy, "navmem:0"))
			DebugLog("  the hand from the game's memory: none (" VisionCardsWhy ")")
		return ""
		}
	lmhBoxes := [], lmhN := 0
	Loop, Parse, answer, `n, `r
		{
		lmhF := StrSplit(A_LoopField, "|")
		if (lmhF.Length() < 12 || lmhF[1] != "card")
			continue
		lmhN += 1
		if (lmhF.Length() >= 15 && lmhF[15] = "0")
			continue
		lmhBoxes.Push({n: lmhN, known: lmhF[6]})
		}
	if (lmhBoxes.Length() != lmhHand.cards.Length())
		{
		DebugLog("  the hand from the game's memory: " lmhHand.cards.Length() " card(s), the helper sees " lmhBoxes.Length() " card box(es) - not used this round")
		return ""
		}
	lmhOut := {}, lmhNames := ""
	for lmhI, lmhB in lmhBoxes
		{
		lmhM := lmhHand.cards[lmhI]
		lmhC := (InStr(lmhB.known, "learned/") = 1) ? LearnCardOf(SubStr(lmhB.known, 9)) : LearnCardInSlot(StrReplace(lmhB.known, "/", "\"))
		lmhWas := IsObject(lmhC) ? LearnFlag(lmhC, "game") : ""
		;(a box the learned card in it isn't the game's card for: that box left out - one wrong pairing before mustn't stop
		;the rest of the hand; said once a card)
		if (lmhWas != "" && lmhWas != LearnMemGame(lmhM))
			{
			if (!saidOff.HasKey(lmhC.id))
				saidOff[lmhC.id] := 1, DebugLog("  the hand from the game's memory: box " lmhI " is learned card " lmhC.id " (" lmhWas " in the game), the game has " LearnMemGame(lmhM) " there - that box left out (said once)")
			continue
			}
		lmhOut[lmhB.n] := lmhM, lmhB.m := lmhM
		lmhNames .= (lmhNames = "" ? "" : ", ") LearnMemGame(lmhM) (lmhM.ench != "" ? " (" lmhM.ench ")" : "")
		}
	;(two or more boxes found as one learned card, the game holding them differently - a pet's or treasure copy with its
	;own numbers: the memory only on the plain copy, else on none - the card isn't flipped from one to the other)
	lmhBy := {}
	for lmhI, lmhB in lmhBoxes
		if (lmhB.known != "" && IsObject(lmhB.m))
			{
			if (!lmhBy.HasKey(lmhB.known))
				lmhBy[lmhB.known] := []
			lmhBy[lmhB.known].Push(lmhB)
			}
	for lmhK, lmhL in lmhBy
		{
		if (lmhL.Length() < 2)
			continue
		lmhDiff := 0, lmhA := lmhL[1].m
		for lmhJ, lmhB in lmhL
			if (lmhB.m.num != lmhA.num || lmhB.m.kind != lmhA.kind || lmhB.m.pips != lmhA.pips || lmhB.m.tc != lmhA.tc || lmhB.m.item != lmhA.item)
				lmhDiff := 1
		if (!lmhDiff)
			continue
		lmhPlain := ""
		for lmhJ, lmhB in lmhL
			if (lmhPlain = "" && !lmhB.m.item && !lmhB.m.tc && lmhB.m.ench = "")
				lmhPlain := lmhB.n
		for lmhJ, lmhB in lmhL
			if (lmhB.n != lmhPlain)
				lmhOut.Delete(lmhB.n)
		}
	DebugLog("  the hand from the game's memory: " (lmhNames = "" ? "no cards" : lmhNames))
	return lmhOut
	}

;---- A learned card you named, put right by the game's hand on any wizard (2026-10-25) ----
;LearnSeenAgain puts right only the learned card a box of the hand is known as - and the helper is asked only about this
;school's learned cards and those in a slot every school shares (LearnCards' learned list): a card learned on another
;wizard, in no slot, is never seen here, so the game's memory never reaches it. c261024120831_1004 - a Tower Shield learned
;on the Fire wizard by OCR before v0.49.0, its - lost ("?50% to next") and so made a blade at load (LearnLooksBlade) - stayed
;a blade while the Balance wizard held two Tower Shields. So each card of the game's hand (VisionCards: the hand settled; no
;box pairing needed - the name is the card) puts right every learned card, of any school, you named so on the Spells tab
;that the game never named (no flag game=): LearnApplyMem - its kind, number, pips and words the game's, game=<its name>.
;Not one you set (flag user: left alone), nor from a treasure or item copy onto a card that isn't one (its own numbers -
;and it'd be flagged tc / item). Returns how many it took out of a slot (their kind changed: the slots' pictures did)
LearnMemNamed()
	{
	lmnHand := VisionCards(1500, 3000)
	if (!IsObject(lmnHand) || !lmnHand.cards.Length() || !IsObject(LearnedCards))
		return 0
	lmnReads := []
	for lmnI, lmnM in lmnHand.cards
		if (lmnM.kind != "")
			lmnReads.Push({m: lmnM, r: LearnMemRead(lmnM)})
	lmnOut := 0, lmnAny := 0
	for lmnI, lmnC in LearnedCards
		{
		lmnNm := Trim(lmnC.name)
		if (lmnNm = "" || LearnFlag(lmnC, "game") != "" || LearnHasFlag(lmnC, "user"))
			continue
		for lmnJ, lmnE in lmnReads
			{
			if (lmnNm != lmnE.r.name && lmnNm != lmnE.r.game)
				continue
			if ((lmnE.m.tc && !LearnHasFlag(lmnC, "tc")) || (lmnE.m.item && !LearnHasFlag(lmnC, "item")))
				continue
			lmnWas := LearnDescribe(lmnC)
			lmnGot := LearnApplyMem(lmnC, lmnE.r)
			if (lmnGot)
				{
				lmnAny := 1, lmnOut += (lmnGot = 2) ? 1 : 0
				DebugLog("  learned card " lmnC.id " (learned for " lmnC.sch "), named " lmnNm " on the Spells tab: the game's " lmnE.r.game " in hand - " lmnWas " -> " LearnDescribe(lmnC))
				}
			break
			}
		}
	if (lmnAny)
		LearnSave()
	return lmnOut
	}

;A card's name in the game, as flag game= keeps it: the name on the card (else the spell's own), printable, no , | $ \
LearnMemGame(m)
	{
	return RegExReplace(LearnClean(m.display != "" ? m.display : m.name), "[,|$\\]")
	}

;A card as the game's memory has it (VisionCards' card m) in the learner's words: {kind (LearnTypes' - one it doesn't
;have: keep), value (the number the learner keeps: a hit's least damage, every head added - an X-pip hit's a pip -, a
;heal's, the % of a shield, blade, trap, aura or weakness, an enchant's damage; "" none), extra (dot=<n>, xpip - as
;LearnKindOf's), text (about as the card says it), name (the name on the card), game (LearnMemGame), school (lower
;case, "" not one of LearnSchools), pips (0 for X; "" not read), xpip, tc, item, two: 0, heads (a hit's damage by school as
;flag heads= keeps it: "fire:230+ice:230+storm:230"; "" not known), boost (what a blade, trap or aura boosts, as flag boost=
;keeps it: "fire+ice+storm", "all"; "" not known)}
LearnMemRead(m)
	{
	;(no kind from the game - its effects cut short: unknown, not "keep"; sure 0: its kind and numbers aren't the game's)
	lmrKind := (m.kind = "") ? "" : "keep"
	for lmrI, lmrT in LearnTypes()
		if (lmrT.kind = m.kind && m.kind != "xpip")
			lmrKind := m.kind
	lmrValue := InStr(",damage,aoe,heal,ward,blade,trap,aura,weakness,enchant,", "," lmrKind ",") ? m.num : ""
	lmrExtra := ((lmrKind = "damage" || lmrKind = "aoe" || lmrKind = "dot") && m.dot != "") ? "dot=" m.dot : ""
	if (m.xpip)
		lmrExtra .= (lmrExtra = "" ? "" : ",") "xpip"
	lmrSch := ""
	for lmrI, lmrS in LearnSchools()
		if (lmrS = m.school)
			lmrSch := lmrS
	return {kind: lmrKind, value: lmrValue, extra: lmrExtra, two: 0, text: LearnClean(m.text), name: LearnClean(m.display != "" ? m.display : m.name)
		, game: LearnMemGame(m), school: lmrSch, pips: m.xpip ? 0 : m.pips, xpip: m.xpip ? 1 : 0, tc: m.tc ? 1 : 0, item: m.item ? 1 : 0
		, sure: (m.kind != "") ? 1 : 0, heads: RegExMatch(m.heads, "^[a-z]+:\d+(,[a-z]+:\d+)*$") ? StrReplace(m.heads, ",", "+") : ""
		, boost: IsFunc("LearnBoostSchools") ? Func("LearnBoostSchools").Call(m.boosts) : ""}
	}

;What a blade, trap or aura boosts (the game's: /cards' boosts - "ice:35,storm:35,fire:35") as flag boost= keeps it: its
;schools a-z, each once, joined with + ("fire+ice+storm"), "all" if it boosts every school; "" not known ("", "?")
LearnBoostSchools(lbsText)
	{
	;(lbsText, not "boosts": that's the battle code's boost count, a super-global)
	lbsOut := ""
	if (lbsText = "" || lbsText = "?")
		return ""
	Loop, Parse, lbsText, `,
		{
		if (!RegExMatch(Trim(A_LoopField), "^([a-z]+):\d+$", lbsM))
			return ""
		lbsOut .= (lbsOut = "" ? "" : "`n") lbsM1
		}
	Sort, lbsOut, U
	return InStr("`n" lbsOut "`n", "`nall`n") ? "all" : StrReplace(lbsOut, "`n", "+")
	}

;What the game's memory says of learned card c (r: LearnMemRead) put into it - never what you set: a card you set on the
;Spells tab (flag user) keeps its kind, number and pips (only pips the learner guessed are put right), a name you typed
;stays (only a card with none gets the game's), a school, treasure card or not-a-treasure-card you set stays. Its text
;becomes the game's words. Flag mem while what it holds is the game's (the same kind, number and pips: LearnSure 100%),
;game=<its name in the game>. A card whose kind changed leaves its slot; one whose numbers or pips changed gets them in
;PlayerStats.txt - out of its hit slot when they no longer keep the hits in order. Returns 0 nothing changed, 1 changed,
;2 out of its slot
LearnApplyMem(c, r)
	{
	;(an item or treasure card copy - a pet's, its own numbers - never over what the card's plain copy put in)
	if ((r.item || r.tc) && LearnHasFlag(c, "mem") && !LearnHasFlag(c, "item") && !LearnHasFlag(c, "tc"))
		return 0
	lamWas := LearnLine(c), lamKind := c.type, lamValue := c.value, lamPips := c.pips
	lamUser := LearnHasFlag(c, "user")
	if (c.name = "" && r.name != "")
		c.name := r.name
	;(no kind from the game: its kind, numbers and pips stay as they are)
	if (!lamUser && r.sure)
		{
		c.type := r.kind, c.value := r.value, c.target := (r.kind = "damage") ? 1 : 0
		LearnDropFlag(c, "dot"), LearnDropFlag(c, "xpip"), LearnSetExtra(c, r.extra)
		if (r.pips != "")
			c.pips := r.pips, c.guess := 0
		}
	else if (c.guess && r.pips != "" && !r.xpip && !LearnHasFlag(c, "xpip"))
		c.pips := r.pips, c.guess := 0
	;(a card you set with no number, the game's kind the one you set: the game's number in the blank - nothing you typed
	;changed. 2026-10-24: Bladestorm, set as a blade with no %, never got resources\blade4 - LearnBoostSlot wants its %)
	if (lamUser && r.sure && c.type = r.kind && c.value = "" && r.value != "")
		c.value := r.value
	if (r.school != "" && r.school != c.sch && LearnFlag(c, "school") = "")
		LearnSetFlag(c, "school", r.school)
	if (r.tc && !LearnHasFlag(c, "tc") && !LearnHasFlag(c, "notc"))
		LearnSetFlag(c, "tc")
	if (r.item && !LearnHasFlag(c, "item"))
		LearnSetFlag(c, "item")
	if (r.text != "")
		c.text := r.text
	if (r.game != "")
		LearnSetFlag(c, "game", r.game)
	;(what it does by school, as the game has it - flags heads=, boost=: its kind the game's)
	if (r.sure)
		{
		if ((r.kind = "damage" || r.kind = "aoe") && r.heads != "")
			LearnSetFlag(c, "heads", r.heads)
		else
			LearnDropFlag(c, "heads")
		if ((r.kind = "blade" || r.kind = "trap" || r.kind = "aura") && r.boost != "")
			LearnSetFlag(c, "boost", r.boost)
		else
			LearnDropFlag(c, "boost")
		}
	lamSame := r.sure && (c.type = r.kind && c.value = r.value && (r.pips = "" || c.pips = r.pips) && (LearnHasFlag(c, "xpip") ? 1 : 0) = r.xpip)
	if (lamSame)
		LearnSetFlag(c, "mem")
	else
		LearnDropFlag(c, "mem")
	if (LearnLine(c) == lamWas)
		return 0
	;(a blade or trap in a slot its schools aren't for - an Ice wizard's Elemental Blade, "+35% to next Ice, Storm, Fire
	;spell", went in ice\blade: out of it, and put where they say - LearnSeenAgain, LearnBoostSlot)
	if (!lamUser && c.slot != "" && LearnFlag(c, "boost") != "" && IsFunc("LearnBoostSlotOf") && Func("LearnBoostSlotIs").Call(c.slot)
		&& Func("LearnBoostSlotOf").Call(c) != c.slot)
		return LearnUnplace(c, "the game says it boosts " LearnFlag(c, "boost")) ? 2 : 1
	if (c.slot != "" && c.type != lamKind)
		return LearnUnplace(c, "the game says it's " LearnKindLabel(c.type)) ? 2 : 1
	if (c.slot != "" && (c.value != lamValue || c.pips != lamPips))
		{
		if (RegExMatch(c.slot, "\\hit([1-4])$", lamHn) && !LearnHitFits(c, lamHn1))
			return LearnUnplace(c, "its numbers from the game put it out of order with the other hits") ? 2 : 1
		LearnStats(c)
		}
	return 1
	}

;---- Slots ----

;Puts learned card c in a free slot (picture copied there, numbers into PlayerStats.txt). A hit with no free slot
;for it: room is made in hit1-3 (LearnArrange - after the battle). 1 if it's in a slot now
LearnPlace(c)
	{
	slot := LearnSlotFor(c)
	if (slot = "")
		return (c.type = "damage" || c.type = "aoe") ? LearnArrange(c) : 0
	setDir := A_WorkingDir (c.dir = "" ? "" : "\" c.dir)
	src := setDir "\learned\" c.id
	dest := setDir "\" slot
	;(FileCopy says nothing when the file it's to copy isn't there: looked at first, and checked after)
	if (!FileExist(src ".png"))
		{
		DebugLog("  learned card " c.id ": its picture " src ".png is missing - not put in " slot)
		return 0
		}
	SplitPath, dest,, destDir
	FileCreateDir, %destDir%
	FileCreateDir, % A_WorkingDir "\backups"
	;(what was there - only an old placeholder, or the slot would have counted as taken - is kept in backups\)
	if (FileExist(dest ".png"))
		FileCopy, %dest%.png, % A_WorkingDir "\backups\" StrReplace(slot, "\", "_") " (" (c.dir = "" ? "main" : c.dir) ", before learned card " c.id ").png", 1
	FileCopy, %src%.png, %dest%.png, 1
	if (ErrorLevel || !LearnSameFile(src ".png", dest ".png"))
		{
		DebugLog("  couldn't copy learned card " c.id " to " dest ".png")
		return 0
		}
	FileCopy, %src%.raw.png, %dest%.raw.png, 1
	;(and in the other picture sets it's been cut in - at another UI size: the slot's picture there too, as the
	;helper does for a card learned in a slot already; the slot is free in every set, or it wouldn't be here)
	Loop, Files, % A_WorkingDir "\ui*", D
		{
		if (A_LoopFileFullPath = setDir || !LearnIsSet(A_LoopFileName) || !FileExist(A_LoopFileFullPath "\learned\" c.id ".png"))
			continue
		other := A_LoopFileFullPath "\" slot
		;(a real picture there - cut at that size: an enchant's slot is handed out while one's cut at another size -
		;stays; the card's own there is used by the helper as its learned picture anyway)
		if (LearnRealPic(other ".png"))
			continue
		SplitPath, other,, otherDir
		FileCreateDir, %otherDir%
		if (FileExist(other ".png"))
			FileCopy, %other%.png, % A_WorkingDir "\backups\" StrReplace(slot, "\", "_") " (" A_LoopFileName ", before learned card " c.id ").png", 1
		FileCopy, % A_LoopFileFullPath "\learned\" c.id ".png", %other%.png, 1
		FileCopy, % A_LoopFileFullPath "\learned\" c.id ".raw.png", %other%.raw.png, 1
		}
	;(pictures made from what was there before)
	Loop, Files, % A_WorkingDir "\generated\ui*", D
		FileDelete, % A_LoopFileFullPath "\" slot ".bmp"
	LearnFreeCache := {}
	;(numbers you had for the slot are kept too - put back when it's taken out)
	LearnStatsKeep(c.sch, slot, c.id)
	c.slot := slot
	;(the slot's card is this one now: the game's name seen for it before is another's)
	if (IsObject(SlotGame))
		SlotGame.Delete(StrReplace(slot, "\", "/")), HeadsMemo := {}
	LearnStats(c)
	return 1
	}

;The free slot for learned card c ("" none): see the top of this file
;A Reshuffle - the card that puts your deck back together when the battle goes wrong: by the game's name for it (or yours)
LearnIsReshuffle(c)
	{
	return IsObject(c) && RegExMatch(LearnFlag(c, "game") "|" c.name, "i)\breshuffle\b")
	}

LearnSlotFor(c)
	{
	;(Reshuffle: its own slot - cast when nothing else can go (Use Reshuffle) - whatever the game calls its kind)
	if (LearnIsReshuffle(c))
		return LearnFree("resources\reshuffle") ? "resources\reshuffle" : ""
	sch := c.sch, kd := c.type
	if (kd = "damage" || kd = "aoe")
		{
		if (c.pips = "")
			return ""
		;(the wand's hit - free, no pips - only a treasure (item) card whose 0 was read off it: a deck spell's 0 is a
		;misread or a guess, and as the wand it'd be cast with no pips and keep the bot from fleeing out of mana. An item
		;card the game's memory says is one: flag item)
		if (c.pips = 0)
			return (!c.guess && (LearnHasFlag(c, "tc") || LearnHasFlag(c, "item")) && !LearnHasFlag(c, "xpip") && LearnFree(sch "\wand")) ? sch "\wand" : ""
		;(only where it keeps hit1-3 weakest to strongest - the battle casts hit3 first, then hit2, hit1 -
		;else it's kept out of use rather than cast before a stronger hit; LearnHitFits)
		Loop, 3
			if (LearnFree(sch "\hit" A_Index) && LearnHitFits(c, A_Index))
				return sch "\hit" A_Index
		;(hit4 - cast on bosses only - for a one-enemy hit stronger than all of them: one for all enemies kept
		;for bosses is wasted on the mobs)
		if (kd = "damage" && LearnFree(sch "\hit4") && LearnHitFits(c, 4))
			return sch "\hit4"
		return ""
		}
	if (kd = "heal")
		{
		if (c.pips = "")
			return ""
		Loop, 2
			if (LearnFree(sch "\heal" A_Index))
				return sch "\heal" A_Index
		return ""
		}
	if (kd = "ward")
		return LearnFree("resources\tower") ? "resources\tower" : ""
	;(a blade or trap whose schools the game's memory read - flag boost=: the slot they say, LearnBoostSlot - an Elemental
	;Blade in resources\elementalblade, a pet's Stormblade in storm\blade; not by its text, which put an Ice wizard's
	;Elemental Blade - "+35% to next Ice, Storm, Fire spell" - in ice\blade)
	if ((kd = "blade" || kd = "trap") && LearnFlag(c, "boost") != "")
		return LearnBoostSlot(c)
	;(cast on yourself before a hit, as a cut one would be: Balanceblade - "+25% to next spell", no school named - as
	;blade3, one naming your school as your school's blade; only at the % PlayerStats.txt counts for that slot - the
	;kill check adds it - else none: kept, not used. The card's school's own % first)
	if (kd = "blade")
		{
		if (RegExMatch(c.text, "i)to[\s/]*next[\s/]*sp"))
			slot := "resources\blade3", want := LearnStatOf(sch, "blade3")
		else if (sch != "" && RegExMatch(c.text, "i)to[\s/]*next[\s/]*" sch))
			slot := sch "\blade", want := LearnStatOf(sch, "blade")
		else
			return ""
		return (c.value != "" && c.value = want && LearnFree(slot)) ? slot : ""
		}
	;(a trap on the next spell - Hex - cast on the boss: at trap3's %; an aura - all spells, or your school's - at aura's)
	if (kd = "trap")
		return (c.value != "" && RegExMatch(c.text, "i)to[\s/]*next[\s/]*sp") && c.value = LearnStatOf(sch, "trap3") && LearnFree("resources\trap3")) ? "resources\trap3" : ""
	if (kd = "aura")
		return (c.value != "" && sch != "" && c.value = LearnStatOf(sch, "aura") && LearnFree(sch "\aura")) ? sch "\aura" : ""
	;(an enchant: the slot whose enchantN is its number - the kill check adds that - with no picture of its own in the
	;card's picture set: one cut at another size doesn't count, it didn't know this card or the card wouldn't be learned)
	if (kd = "enchant")
		{
		v := LearnValueKnown(c), lv := (v != "") ? LearnEnchantLevel(sch, v) : 0
		if (!lv)
			return ""
		for i, e in EnchantList()
			if (e[1] = lv)
				slot := e[2] "\" e[3]
		return (LearnFree(slot) || !LearnRealPic(A_WorkingDir (c.dir = "" ? "" : "\" c.dir) "\" slot ".png")) ? slot : ""
		}
	return ""
	}

;The slot learned blade or trap c goes in by its schools as the game read them (flag boost=), free or not: one school's
;"<school>\blade" / "\trap" (not Balance's: its own are Balanceblade and Hex), fire+ice+storm resources\elemental<kind>,
;death+life+myth resources\spirit<kind>, every school's by its %: resources\blade3 (Balanceblade's), blade4 (Bladestorm's),
;trap3 (Hex's), feint (Feint's) as PlayerStats.txt has them; "" none (balance alone, two schools, another %)
LearnBoostSlotOf(c)
	{
	lbsoS := LearnFlag(c, "boost")
	if (lbsoS = "" || (c.type != "blade" && c.type != "trap"))
		return ""
	lbsoS := (lbsoS = "all") ? "all" : StrReplace(lbsoS, "+", ",")
	return BoostSlotFor(c.type, lbsoS, c.value, c.sch)
	}

;The free slot for learned blade or trap c with flag boost= (LearnSlotFor): LearnBoostSlotOf's, when it's free and the
;card's % is at least what PlayerStats.txt counts for that slot (a stronger card is counted at the slot's when the game's
;memory isn't read - never more than it does; with it, at its own: KillCalc.ahk BoostPctMem); "" none
LearnBoostSlot(c)
	{
	lbsSlot := LearnBoostSlotOf(c)
	if (lbsSlot = "" || !LearnFree(lbsSlot))
		return ""
	lbsV := LearnValueKnown(c)
	if (lbsV = "")
		return ""
	return LearnBoostPctOk(lbsSlot, lbsV, c.sch) ? lbsSlot : ""
	}

;Whether a blade or trap of pct % may be cast from boost slot rel (LearnBoostSlot, LearnBoostPicFix) for school sch's wizard:
;at least the % PlayerStats.txt counts for that slot - one every school shares, or your school's own: your wizard's
;<school>.<key>, else the plain one; another school's - blade.storm for a pet's Stormblade on your Balance wizard,
;storm.blade being the Storm wizard's own -, else the plain one (KillCalc.ahk BoostPct); none set: any
LearnBoostPctOk(rel, pct, sch)
	{
	SplitPath, rel, lbpName, lbpDir
	if (lbpDir = "resources" || lbpDir = sch)
		lbpWant := LearnStatOf(sch, lbpName)
	else
		lbpWant := Stats.HasKey(lbpName "." lbpDir) ? Stats[lbpName "." lbpDir] : LearnStatOf("", lbpName)
	return (lbpWant = "" || pct + 0 >= lbpWant + 0)
	}

;Whether slot rel is a blade's or trap's: <school>\blade, \trap, resources\blade3, blade4, trap3, feint, elementalblade...
LearnBoostSlotIs(rel)
	{
	return RegExMatch(rel, "i)^(resources\\(blade3|blade4|trap3|feint|elementalblade|elementaltrap|spiritblade|spirittrap)|[a-z]+\\(blade|trap))$")
	}

;---- A boost slot's picture that never finds the game's card (2026-10-24) ----
;A blade or trap the game's memory names in a box (LearnMemHand's pairing - card.mem: the hand settled, as many boxes as
;cards, the box not another learned card's), a plain copy (not greyed out, enchanted, a treasure or item card - those look
;otherwise), whose slot by its schools and % (KillCalc.ahk BoostSlotFor - at least the % the slot counts: LearnBoostPctOk)
;the battle's own look at the hand asked about and didn't find on that box twice running (a card zoomed up under the mouse
;for one look isn't a picture that never finds it):
;  - the slot's picture at this UI size isn't the card's own (an old cut, another card's), or there's none here and one cut
;    at another size is resized for it: the card's own put there - the learned card's picture (a new card is learned by the
;    box first: LearnNew), what was there kept in backups\ as LearnPlace keeps it (LearnUnplace puts it back), the slot the
;    card's (another learned card that had it: out of it). The battle's pictures find it from then on, memory or not. Nothing
;    usable for the slot anywhere (an 8x8 placeholder): LearnPlace's own job, by its rules
;  - it IS the card's own: the helper isn't using it - another set's picture comes first in the helper's order
;    (LearnShadowSet - vision.py Library.masters; since 2026-10-24 this size's own cut comes first, so that's rare), or the
;    card looks otherwise now and then: said once a run; the card's cast at its box by the game's hand meanwhile
;    (KillCalc.ahk BoostMemBox)
;And Tower Shield's slot the same way (2026-10-25): a shield the game names Tower Shield (KillCalc.ahk TowerMatches) whose
;resources\tower picture never finds it - live at UI 1.144 that picture was a Spirit Shield's, the first shield learned
;(LearnSlotFor gives any shield resources\tower), so the Tower Shields learned since got no slot: the shield learned card
;the box is gets resources\tower, its picture there (the Spirit Shield's in backups\, the Spirit Shield out of the slot)
;f: the box's /hand line, split. 1 if the slot's picture was written (the hand's looked at again)
LearnBoostPicFix(card, f)
	{
	static misses := {}, said := {}, lookOf := {}
	m := card.mem
	if (!IsObject(m) || (m.kind != "blade" && m.kind != "trap" && m.kind != "ward") || card.grey || !card.isCard || card.tc || m.ench != "" || m.tc || m.item)
		return 0
	if (m.kind = "ward")
		{
		if (!TowerMatches([m]).Length())
			return 0
		slot := "resources\tower"
		}
	else
		{
		b := BoostsParse(m.boosts)
		if (!IsObject(b))
			return 0
		slot := BoostSlotFor(m.kind, b.sch, b.pct, hitschool)
		if (slot = "" || !LearnBoostPctOk(slot, b.pct, hitschool))
			return 0
		}
	pic := StrReplace(slot, "\", "/"), name := LearnMemGame(m), key := slot "|" name
	;(the battle's own look asked about it - and found it on this box: its picture works)
	if (!InStr("," VisionPicList() ",", "," pic ",") || InStr(VisionMissing, "," pic ","))
		return 0
	l := f[2] + 0, w := f[4] + 0
	if (IsObject(VisionCards))
		for i, vc in VisionCards
			if (vc.pic = pic && vc.x >= l - Px(10) && vc.x <= l + w + Px(10))
				{
				misses.Delete(key)
				return 0
				}
	;(one miss a look at the hand - VisionFind's count: the same look asked about again isn't a second - and so the look's
	;first copy of it only: a second copy known as another learned card - two Tower Shields learned apart - would start
	;the count again every look, 2026-10-25)
	if (VisionLookN = "" || lookOf[key] = VisionLookN)
		return 0
	;(twice running for one box identity - the same picture or learned card known there: two misses on two different boxes
	;or cards, a pairing that shifted, aren't twice)
	if (!misses.HasKey(key) || misses[key].known != card.known)
		misses[key] := {n: 0, known: card.known}
	lookOf[key] := VisionLookN
	misses[key].n += 1
	if (misses[key].n < 2)
		return 0
	here := LearnSetDir(false), dest := here "\" slot
	setName := (here = A_WorkingDir) ? "main" : SubStr(here, StrLen(A_WorkingDir) + 2)
	;(the box's card as a learned card: known by its own picture - only one the game named so, and not one the learner is
	;still waiting to see so again: LearnMemWait -, else the slot's card the game names so)
	lc := ""
	if (InStr(card.known, "learned/") = 1)
		{
		lc := LearnCardOf(SubStr(card.known, 9))
		if (!IsObject(lc) || LearnFlag(lc, "game") != name || (IsObject(LearnMemWait) && LearnMemWait.HasKey(lc.id)))
			lc := ""
		}
	else
		{
		lc := LearnCardInSlot(slot)
		if (!IsObject(lc) || LearnFlag(lc, "game") != name)
			lc := ""
		}
	own := IsObject(lc) && FileExist(here "\learned\" lc.id ".png")
	if (LearnRealPic(dest ".png"))
		{
		;(never over the slot's own learned card's picture - the game names it so too)
		sow := LearnCardInSlot(slot)
		sow := (IsObject(sow) && LearnFlag(sow, "game") = name && FileExist(here "\learned\" sow.id ".png") && LearnSameCard(dest, here "\learned\" sow.id)) ? sow : ""
		if ((own && LearnSameCard(dest, here "\learned\" lc.id)) || IsObject(sow))
			{
			if (!said.HasKey(slot))
				{
				said[slot] := 1, sh := LearnShadowSet(slot)
				DebugLog("  " slot ": its picture (" setName ") is the game's " name "'s own, yet the battle's look didn't find it twice running"
					. (sh != "" ? " - the vision helper matches " sh "'s picture of it instead (it comes first in vision.py Library.masters' order)" : " (the card looks otherwise now and then?)")
					. "; it's cast at its box by the game's hand")
				}
			return 0
			}
		}
	else if (LearnFree(slot))
		return 0
	;(not learned yet - LearnNew learns a new card this round: its own picture next time; one in another slot: the game's
	;boost= takes it out of that first - LearnApplyMem)
	if (!own || (lc.slot != "" && lc.slot != slot))
		return 0
	src := here "\learned\" lc.id
	back := A_WorkingDir "\backups\" StrReplace(slot, "\", "_") " (" setName ", before learned card " lc.id ")"
	SplitPath, dest,, destDir
	FileCreateDir, %destDir%
	FileCreateDir, % A_WorkingDir "\backups"
	hadOld := FileExist(dest ".png") ? 1 : 0
	if (hadOld)
		FileCopy, %dest%.png, %back%.png, 1
	if (FileExist(dest ".raw.png"))
		FileCopy, %dest%.raw.png, %back%.raw.png, 1
	FileCopy, %src%.png, %dest%.png, 1
	if (ErrorLevel || !LearnSameFile(src ".png", dest ".png"))
		{
		DebugLog("  couldn't copy learned card " lc.id " to " dest ".png")
		return 0
		}
	if (FileExist(src ".raw.png"))
		FileCopy, %src%.raw.png, %dest%.raw.png, 1
	;(pictures made from what was there before)
	Loop, Files, % A_WorkingDir "\generated\ui*", D
		FileDelete, % A_LoopFileFullPath "\" slot ".bmp"
	old := LearnCardInSlot(slot)
	if (IsObject(old) && old.id != lc.id)
		{
		old.slot := ""
		DebugLog("  learned card " old.id " (" LearnDescribe(old) "): " slot " has the game's " name " now - not using it there any more")
		}
	if (lc.slot = "")
		{
		LearnStatsKeep(lc.sch, slot, lc.id), lc.slot := slot
		if (IsObject(SlotGame))
			SlotGame.Delete(pic)
		LearnStats(lc)
		}
	LearnFreeCache := {}, misses.Delete(key)
	LearnSave()
	DebugLog("  " slot " (" setName "): its picture didn't find the game's " name " in hand twice running - the card's own put there (learned card " lc.id ")"
		. (hadOld ? ", the old one kept in backups\" StrReplace(slot, "\", "_") " (" setName ", before learned card " lc.id ").png" : ""))
	return 1
	}

;The picture set the vision helper takes slot rel's picture from at this UI size instead of this size's own (LearnSetDir),
;by vision.py Library.masters' order among the sets with a real picture for it: one cut within 1% of the size (the nearest),
;then the ones truly at or above it (the smallest), then the smaller ones (the biggest) - its folder's name ("ui1.121"), ""
;this size's own or none. (Till 2026-10-24 a set down to 3% smaller came first: ui1.121's Balanceblade at 1.144)
LearnShadowSet(rel)
	{
	lssBest := "", lssKey := ""
	for lssI, lssSt in LearnSets()
		{
		if (!LearnRealPic(lssSt.path "\" rel ".png"))
			continue
		lssV := (lssSt.name = "main") ? 1 : SubStr(lssSt.name, 3) + 0
		lssK := (Abs(lssV / UiScale - 1) < 0.01) ? Abs(lssV - UiScale) : (lssV >= UiScale) ? 10 + lssV : 100 - lssV
		if (lssKey = "" || lssK < lssKey)
			lssBest := lssSt, lssKey := lssK
		}
	return (IsObject(lssBest) && lssBest.path != LearnSetDir(false)) ? lssBest.name : ""
	}

;Learned enchant c in the slot for its number (EnchantList's picture for its level)
LearnEnchantSlotOk(c)
	{
	lv := LearnEnchantLevel(c.sch, c.value)
	for i, e in EnchantList()
		if (e[1] = lv)
			return c.slot = e[2] "\" e[3]
	return false
	}

;The enchant level (PlayerStats.txt enchantN, EnchantList) whose damage is v for school sch's wizard - the new ones
;(Strong, Giant, Monstrous: 5-7) before the old life\enchant placeholder (1); 0 none
LearnEnchantLevel(sch, v)
	{
	if (v = "" || v + 0 < 10)
		return 0
	for i, lv in [4, 3, 2, 7, 6, 5, 1]
		if (LearnStatOf(sch, "enchant" lv) = v + 0)
			return lv
	return 0
	}

;PlayerStats.txt's key for school sch's wizard (<sch>.key), else the plain key - not the school fought as now; "" none
LearnStatOf(sch, key)
	{
	if (sch != "" && Stats.HasKey(sch "." key))
		return Stats[sch "." key]
	return Stats.HasKey(key) ? Stats[key] : ""
	}

;Learned card c's number when it's sure: two reads agreed on it, you typed it (Spells tab) or it's the game's (flag mem)
;- else ""
LearnValueKnown(c)
	{
	return (c.value != "" && (LearnHasFlag(c, "two") || LearnHasFlag(c, "user") || LearnHasFlag(c, "mem"))) ? c.value : ""
	}

;A learned hit's least damage, every head of it - the low end of each damage range on the card before any "over N
;rounds" (Hydra: its storm, fire and ice heads; LearnKindOf keeps the first range only) when its value is known, else
;"" (a value you set on the Spells tab is taken as it is, and the game's - every head added already)
LearnHitBase(c)
	{
	known := LearnValueKnown(c)
	if (known = "" || LearnHasFlag(c, "user") || LearnHasFlag(c, "mem"))
		return known
	lhbAt := RegExMatch(c.text, "i)over\s*\d|(?<![a-z])o\S{0,2}r\s*\d|\(\s*\S{0,2}\s*\d\s*\)|r[o0]unds?\b|\brds\b")
	lhbHead := lhbAt ? SubStr(c.text, 1, lhbAt - 1) : c.text
	lhbSum := 0, lhbN := 0, p := 1
	while (p := RegExMatch(lhbHead, "O)(\d+)\s*-\s*(\d+)", lhbM, p))
		{
		lhbLo := LearnRangeFix(lhbM.Value(1), lhbM.Value(2))
		if (lhbLo != "")
			lhbSum += lhbLo, lhbN += 1
		p += StrLen(lhbM.Value(0))
		}
	return lhbN > 1 ? lhbSum : known
	}

;Which of two hits is stronger: > 0 the first, < 0 the second, 0 can't tell (or the same). By their damage where
;both are known (a hit's damage not read is 0 in PlayerStats.txt), else by their pips
LearnStronger(val1, pips1, val2, pips2)
	{
	if (val1 > 0 && val2 > 0)
		return val1 - val2
	;(pips "" when they were guessed, not read: no use for this)
	if (pips1 > 0 && pips2 > 0 && pips1 != pips2)
		return pips1 - pips2
	;(the second's damage known, the first's not and no pips to tell by: the first counts as 0 - as ever)
	if (val2 > 0 && !(pips1 > 0 && pips2 > 0))
		return 0 - val2
	return ""
	}

;Whether learned/known hit c in slot hitN (n 1-4) keeps the hits in order against the other slots taken: hit1-3
;weakest to strongest, hit4 stronger than all (LearnStronger; can't tell - its damage unsure and the same pips, or
;no pips read - doesn't fit)
LearnHitFits(c, n)
	{
	sch := c.sch, val := LearnValueKnown(c), pips := c.guess ? "" : c.pips
	val := (val != "") ? val + 0 : 0
	Loop, 4
		{
		m := A_Index
		if (m = n || LearnFree(sch "\hit" m))
			continue
		cmp := LearnStronger(Stat(sch ".hit" m), LearnSlotPips(sch, m), val, pips)
		if (cmp = "")
			return false
		if (n = 4 && cmp >= 0)
			return false
		if ((m < n && cmp > 0) || (m > n && cmp < 0))
			return false
		}
	return true
	}

;Slot <sch>\hitN's pip cost as read ("" not known: a learned card's guessed one, or none in PlayerStats.txt)
LearnSlotPips(sch, n)
	{
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			if (c.sch = sch && c.slot = sch "\hit" n)
				return c.guess ? "" : c.pips
	p := Stat(sch ".hit" n "pips")
	return (p > 0) ? p : ""
	}

;Takes learned card c out of its slot (why: for the log): the slot's pictures that are its removed - what was there
;before put back (backups\) - so the slot's free again, and its numbers out of PlayerStats.txt once no picture's left
;there (yours put back if it had some). One put there by making room in hit1-3 (flag snap=): that whole arrangement
;is put back (LearnUndoLayout) - after the battle, if it's on. 1 if it's out of the slot now
LearnUnplace(c, why)
	{
	slot := c.slot
	if (slot = "")
		return 1
	;(in a battle not out of a hit slot - the round's records go by slot (an enchant on hitN, pips saved for it): after
	;the battle, and put back where it fits then)
	if (inbattle = 1 && (LearnHasFlag(c, "snap") || RegExMatch(slot, "\\hit[1-4]$")))
		{
		if (LearnQueue("u|" c.id "|" why))
			DebugLog("  learned card " c.id " (" LearnDescribe(c) "): out of " slot " after this battle - " why)
		LearnQueue("p|" c.id)
		return 0
		}
	if (LearnHasFlag(c, "snap") && LearnUndoLayout(c, why))
		return 1
	DebugLog("  learned card " c.id " (" LearnDescribe(c) "): out of " slot " - " why)
	for i, st in LearnSets()
		{
		pic := st.path "\" slot
		if (!LearnSameCard(pic, st.path "\learned\" c.id))
			continue
		FileDelete, %pic%.png
		FileDelete, %pic%.raw.png
		back := A_WorkingDir "\backups\" StrReplace(slot, "\", "_") " (" st.name ", before learned card " c.id ").png"
		if (FileExist(back))
			FileCopy, %back%, %pic%.png, 1
		}
	Loop, Files, % A_WorkingDir "\generated\ui*", D
		FileDelete, % A_LoopFileFullPath "\" slot ".bmp"
	LearnFreeCache := {}
	c.slot := ""
	if (!LearnSlotHasPic(slot))
		LearnStatsBack(c.sch, slot, c.id)
	return 1
	}

;Whether folder name (e.g. "ui1.144") is a cut picture set's: ui and its UI scale
LearnIsSet(name)
	{
	sc := SubStr(name, 3)
	if sc is not number
		return false
	return (SubStr(name, 1, 2) = "ui" && sc >= 0.3 && sc <= 4)
	}

;The picture sets: [{path, name}] - the main one ("main", the AutoFarmer folder) and every cut ui<scale> folder;
;first: a set's name to put first (e.g. a card's own)
LearnSets(first := "")
	{
	out := [{path: A_WorkingDir, name: "main"}]
	Loop, Files, % A_WorkingDir "\ui*", D
		if (LearnIsSet(A_LoopFileName))
			out.Push({path: A_LoopFileFullPath, name: A_LoopFileName})
	if (first != "")
		for i, st in out
			if (st.name = first)
				{
				out.RemoveAt(i), out.InsertAt(1, st)
				break
				}
	return out
	}

;Whether files a and b are the same, byte for byte
LearnSameFile(a, b)
	{
	FileGetSize, sa, %a%
	if (ErrorLevel || sa = "" || sa = 0)
		return false
	FileGetSize, sb, %b%
	if (ErrorLevel || sb != sa)
		return false
	FileRead, da, *c %a%
	FileRead, db, *c %b%
	return DllCall("msvcrt\memcmp", "Ptr", &da, "Ptr", &db, "UPtr", sa, "CDecl Int") = 0
	}

;Whether picture a (a path without .png) is a copy of b: the same .raw.png (never made see-through, unlike the .png -
;the helper makes the pixels that differ between copies see-through in both), or the same .png
LearnSameCard(a, b)
	{
	return LearnSameFile(a ".raw.png", b ".raw.png") || LearnSameFile(a ".png", b ".png")
	}

;Whether a picture file is big enough to use (12x12 or more - the 8x8 placeholders of 2018 aren't), by its PNG header
LearnRealPic(file)
	{
	fh := FileOpen(file, "r")
	if (!IsObject(fh))
		return false
	VarSetCapacity(hdr, 24, 0)
	got := fh.RawRead(hdr, 24)
	fh.Close()
	if (got < 24 || NumGet(hdr, 0, "UInt") != 0x474E5089)
		return false
	w := (NumGet(hdr, 16, "UChar") << 24) | (NumGet(hdr, 17, "UChar") << 16) | (NumGet(hdr, 18, "UChar") << 8) | NumGet(hdr, 19, "UChar")
	h := (NumGet(hdr, 20, "UChar") << 24) | (NumGet(hdr, 21, "UChar") << 16) | (NumGet(hdr, 22, "UChar") << 8) | NumGet(hdr, 23, "UChar")
	return (w >= 12 && h >= 12)
	}

;Whether slot rel has a picture big enough to use in any set (as the helper's /usable, from the files)
LearnSlotHasPic(rel)
	{
	for i, st in LearnSets()
		if (LearnRealPic(st.path "\" rel ".png"))
			return true
	return false
	}

;Whether slot rel (e.g. "balance\hit2") is free: no cut picture big enough to use for it in any set (the
;helper knows; the 8x8 placeholders of 2018 don't count)
LearnFree(rel)
	{
	;(asked once a round per slot - LearnCards empties the answers, as does a card put in a slot)
	if (!IsObject(LearnFreeCache))
		LearnFreeCache := {}
	if (!LearnFreeCache.HasKey(rel))
		LearnFreeCache[rel] := (Trim(VisionGet("/usable?rel=" LearnUri(rel ".png"), 3000)) = "0")
	return LearnFreeCache[rel]
	}

;Learned card c's numbers into PlayerStats.txt (a number not sure - LearnValueKnown - is 0: the kill check never
;counts on it, never the number of the card the slot was meant for). A hit's heads by school too (flag heads=, the
;game's - Hydra's fire, ice and storm: <school>.<hit>fire... lines adding up to its number, the kill check's without the
;game's memory - KillCalc.ahk HitHeadsFind); one head of its own school, or a number not sure: none - those the slot's
;card before had taken out
LearnStats(c)
	{
	slot := c.slot
	SplitPath, slot, name
	key := c.sch "." name, pairs := []
	if (InStr(name, "hit") = 1 || name = "wand")
		{
		v := LearnValueKnown(c)
		pairs.Push([key, v != "" ? v : 0])
		if (name != "wand" && c.pips != "")
			pairs.Push([key "pips", c.pips])
		pairs.Push([key "target", c.target])
		lstHh := (v != "" && IsFunc("LearnHitHeads")) ? Func("LearnHitHeads").Call(c) : ""
		lstMany := IsObject(lstHh) && lstHh.sure && lstHh.total = v && !(lstHh.heads.Count() = 1 && lstHh.heads.HasKey(c.sch))
		for lstI, lstS in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
			pairs.Push([key lstS, (lstMany && lstHh.heads.HasKey(lstS)) ? lstHh.heads[lstS] : ""])
		}
	else if (InStr(name, "heal") = 1 && c.pips != "")
		{
		pairs.Push([key "pips", c.pips])
		;(whether it heals an ally - a party battle's healer finds out: Autofarmer.ahk UseHeal)
		pairs.Push([key "target", ""])
		}
	if (pairs.Length())
		StatsSet(pairs, LearnStatsNote(c))
	}

;The comment that goes with learned card c's numbers in PlayerStats.txt (its id in it)
LearnStatsNote(c)
	{
	return "learned " SubStr(c.when, 1, 8) ": " LearnClean(c.text) (c.guess ? " (pips guessed: brought down as it shows up in colour with fewer)" : "") " - picture " c.dir "\learned\" c.id ".card.png"
	}

;PlayerStats.txt's keys for slot rel of school sch: hitN's damage, pips and target, the wand's, their heads by school
;(<school>.<hit><head's school>: LearnStats), a heal's pips ([] none)
LearnSlotKeys(sch, rel)
	{
	SplitPath, rel, nm
	if (RegExMatch(nm, "^hit\d$") || nm = "wand")
		{
		lskOut := (nm = "wand") ? [sch ".wand", sch ".wandtarget"] : [sch "." nm, sch "." nm "pips", sch "." nm "target"]
		for lskI, lskS in ["balance", "death", "fire", "ice", "life", "myth", "storm"]
			lskOut.Push(sch "." nm lskS)
		return lskOut
		}
	if (RegExMatch(nm, "^heal\d$"))
		return [sch "." nm "pips"]
	return []
	}

;Your numbers for slot rel (PlayerStats.txt lines there before learned card id went in), kept in backups\<slot>
;(before learned card <id>).stats.txt - once
LearnStatsKeep(sch, rel, id)
	{
	keys := LearnSlotKeys(sch, rel)
	if (!keys.Length())
		return
	file := A_WorkingDir "\backups\" StrReplace(rel, "\", "_") " (before learned card " id ").stats.txt"
	if (FileExist(file))
		return
	lines := LearnStatLines(keys), any := 0
	for i, kk in keys
		any += (lines[kk] != "-")
	if (any)
		LearnWriteLines(file, keys, lines)
	}

;Slot rel's numbers once learned card id is out of it: yours put back (LearnStatsKeep's backup), else its lines taken
;out of PlayerStats.txt (no picture's left there)
LearnStatsBack(sch, rel, id)
	{
	keys := LearnSlotKeys(sch, rel)
	if (!keys.Length())
		return
	file := A_WorkingDir "\backups\" StrReplace(rel, "\", "_") " (before learned card " id ").stats.txt"
	old := FileExist(file) ? LearnReadLines(file) : ""
	edits := []
	for i, kk in keys
		edits.Push([kk, IsObject(old) && old.HasKey(kk) && old[kk] != "-" ? old[kk] : ""])
	LearnStatsWrite(edits)
	}

;---- Out of battle ----

;The main loop calls this between battles (the spellbook up, inbattle 0). Once a run: a learned card's picture left in
;a slot that isn't its own taken out (LearnReconcile), the texts it holds classified again (LearnRecheckTexts), and -
;with the vision helper up - the catalog checked for things that aren't cards (LearnCheckCatalog). Every time: what
;waited for the battle's end (room made in hit1-3, an arrangement put back). Returns how many cards went into or
;out of a slot
LearnOutOfBattle()
	{
	if (inbattle = 1)
		return 0
	if (!IsObject(LearnRunDone))
		LearnRunDone := {}
	if (!LearnRunDone.HasKey("load"))
		{
		LearnRunDone.load := 1
		if (!IsObject(LearnedCards))
			LearnLoad()
		LearnReconcile()
		LearnRecheckTexts()
		}
	if (VisionOn && !LearnRunDone.HasKey("check"))
		{
		LearnRunDone.check := 1
		if (LearnCheckCatalog())
			LearnRecheckTexts()
		}
	return LearnArrangePending()
	}

;Every learned card not checked yet (flag ok) looked at again by the vision helper as a card in hand is (/cardcheck on
;its .card.png): one that isn't a card - the deck's back, an empty spot, the timer, a popup over a card, learned while
;the hand was looked for in the wrong place - is moved to backups\learned junk\ (LearnJunk; never deleted). One that is
;gets the flag ok, its icon (icon=), tc for a treasure card, and the pip digit read off it now (more digits are known).
;Not one in use in a slot (Forget it on the Spells tab if it's wrong), and nothing at all when none of them passes (the
;check is what's wrong then). 1 if anything changed
LearnCheckCatalog()
	{
	if (!VisionOn)
		return 0
	if (!IsObject(LearnedCards))
		LearnLoad()
	todo := [], junk := [], changed := 0, unanswered := 0, looked := 0
	for i, c in LearnedCards
		if (!LearnHasFlag(c, "ok"))
			todo.Push(c)
	for i, c in todo
		{
		pic := LearnCardPicture(c)
		if (pic = "")
			{
			DebugLog("  learned card " c.id ": no " c.id ".card.png in any picture set - not checked")
			continue
			}
		ans := Trim(VisionGet("/cardcheck?file=" LearnUri(pic) "&scale=" (c.scale != "" ? c.scale : Round(UiScale, 3)), 3000, true), " `t`r`n")
		;(no answer - an older helper: tried again next run)
		if (ans = "")
			{
			if (++unanswered >= 3)
				break
			continue
			}
		unanswered := 0
		if (InStr(ans, "fail") = 1)
			{
			DebugLog("  learned card " c.id ": couldn't be checked (" ans ")")
			continue
			}
		v := StrSplit(ans, "|")
		if (v.Length() < 9 || (v[1] != "0" && v[1] != "1"))
			continue
		looked += 1
		if (v[1] = "0")
			{
			junk.Push({c: c, why: "not a card (eTxt=" v[3] " pipYel=" v[4] " white=" v[5] " iconD=" v[6] ")"})
			continue
			}
		LearnSetFlag(c, "ok"), changed := 1
		if (v[7] != "")
			LearnSetFlag(c, "icon", v[7])
		if (v[2] = 1 && !LearnHasFlag(c, "notc"))
			LearnSetFlag(c, "tc")
		;(not pips you typed on the Spells tab - guessed ones are, even on a spell whose name or number you set - nor the
		;game's own: flag mem)
		pd := v[8]
		if (RegExMatch(pd, "^\d+$") && (c.guess || c.pips != pd) && (!LearnHasFlag(c, "user") || c.guess) && !LearnHasFlag(c, "xpip") && !LearnHasFlag(c, "mem"))
			{
			if (pd = 0 && RegExMatch(c.slot, "\\hit\d$"))
				DebugLog("  learned card " c.id " (" LearnDescribe(c) "): its pip digit reads 0 - not taken for a hit in " c.slot)
			else
				{
				DebugLog("  learned card " c.id " (" LearnDescribe(c) "): its pip digit reads " pd)
				c.pips := pd + 0, c.guess := 0
				if (c.slot != "")
					LearnStats(c)
				}
			}
		}
	if (junk.Length() && junk.Length() = looked && looked >= 4)
		{
		DebugLog("  learned cards checked: none of the " looked " looked like a card - that's the check failing, not the cards: nothing moved")
		junk := []
		}
	moved := 0
	for i, j in junk
		{
		if (j.c.slot != "")
			{
			DebugLog("  learned card " j.c.id " (" LearnDescribe(j.c) ") doesn't look like a card (" j.why ") but it's in use as " j.c.slot " - kept (Forget it on the Spells tab if it's wrong)")
			continue
			}
		LearnJunk(j.c, j.why, false)
		moved += 1, changed := 1
		}
	if (changed)
		LearnSave()
	if (moved)
		{
		PicMade := {}, LearnFreeCache := {}
		VisionGet("/forget", 3000, true)
		VisionForget()
		DebugLog("  learned cards checked: " moved " that aren't cards moved to backups\learned junk (their files and catalog lines)")
		}
	return changed
	}

;Learned card c's .card.png (the whole card): in its own picture set first, then any - "" none
LearnCardPicture(c)
	{
	for i, st in LearnSets(c.dir = "" ? "main" : c.dir)
		if (FileExist(st.path "\learned\" c.id ".card.png"))
			return st.path "\learned\" c.id ".card.png"
	return ""
	}

;Learned "card" c isn't one (why: for the log): out of the catalog, its files moved to backups\learned junk\<set>\
;(never deleted) and its line added to backups\learned junk\cards.txt. save: the catalog written and the helper told
LearnJunk(c, why, save := true)
	{
	if (c.slot != "")
		LearnUnplace(c, why)
	n := LearnMoveFiles(c, "learned junk")
	LearnDrop(c)
	DebugLog("  learned card " c.id " (" (c.text = "" ? "no text" : """" c.text """") "): " why " - its " n " file(s) moved to backups\learned junk")
	if (save)
		{
		LearnSave()
		PicMade := {}, LearnFreeCache := {}
		if (VisionOn)
			VisionGet("/forget", 3000, true), VisionForget()
		}
	}

;Forgets learned card c (why: for the log): out of its slot (an arrangement it was put in by put back), out of the
;catalog, its files moved to backups\learned forgotten\<set>\. A real card is learned again when it's next in hand.
;1 if done (not during a battle for one put in hit1-3 by an arrangement)
LearnForget(c, why)
	{
	if (c.slot != "" && !LearnUnplace(c, why))
		return 0
	n := LearnMoveFiles(c, "learned forgotten")
	LearnDrop(c)
	;(cards it took the place of are free to be arranged again)
	for i, o in LearnedCards
		if (LearnFlag(o, "out") = c.id)
			LearnDropFlag(o, "out")
	if (LearnAll)
		LearnAllFrom := LearnAllFrom > 0 ? LearnAllFrom - 1 : 0, LearnAllSeen := LearnAllSeen > 0 ? LearnAllSeen - 1 : 0
	LearnSave()
	PicMade := {}, LearnFreeCache := {}
	if (VisionOn)
		VisionGet("/forget", 3000, true), VisionForget()
	DebugLog("  learned card " c.id " (" LearnDescribe(c) ") forgotten - " why " (its " n " file(s): backups\learned forgotten)")
	return 1
	}

;Moves every <set>\learned\<id>.* of learned card c (the main set and every ui* set) into backups\<folder>\<set>\ (a
;file there already: the new one gets the time in front) and adds its catalog line to backups\<folder>\cards.txt.
;Returns how many files moved
LearnMoveFiles(c, folder)
	{
	into := A_WorkingDir "\backups\" folder
	FileCreateDir, %into%
	n := 0
	for i, st in LearnSets()
		{
		found := []
		Loop, Files, % st.path "\learned\" c.id ".*"
			found.Push(A_LoopFileFullPath)
		if (!found.Length())
			continue
		FileCreateDir, % into "\" st.name
		for j, fp in found
			{
			SplitPath, fp, fn
			to := into "\" st.name "\" fn
			if (FileExist(to))
				to := into "\" st.name "\" A_Now " " fn
			FileMove, %fp%, %to%
			if (ErrorLevel || !FileExist(to) || FileExist(fp))
				DebugLog("  couldn't move " fp " to " to)
			else
				n += 1
			}
		}
	FileAppend, % LearnLine(c) "`r`n", % into "\cards.txt"
	return n
	}

;Learned card c out of the catalog (LearnedCards; not saved)
LearnDrop(c)
	{
	for i, o in LearnedCards
		if (o.id = c.id)
			{
			LearnedCards.RemoveAt(i)
			return
			}
	}

;Every learned card's text classified again (LearnKindOf, no OCR) with what's known now - its icon read since, the
;newer rules (Choke a stun, Backfire "Clear"...). Never one you set on the Spells tab, nor one read from the game's memory
;(flag mem - its text is the game's words, not OCR); a number found this way isn't sure (one read) till two fresh reads
;agree. Returns how many changed
LearnRecheckTexts()
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	n := 0
	for i, c in LearnedCards.Clone()
		{
		if (c.text = "" || LearnHasFlag(c, "user") || LearnHasFlag(c, "mem"))
			continue
		r := LearnKindOf(c.text, LearnIconOf(c), c.sch)
		r.two := 0, r.text := ""
		was := LearnDescribe(c)
		if (LearnApplyRead(c, r, "its text classified again"))
			n += 1, DebugLog("  learned card " c.id " (""" c.text """): " was " -> " LearnDescribe(c))
		}
	if (n)
		LearnSave()
	return n
	}

;A learned card's picture in a slot that isn't the card's (an older version's mix-up: Locust Swarm in both balance\hit3
;and hit4 while the catalog had it in none): out of that slot - moved to backups\learned strays\<set>\, what was there
;before put back (backups\) - and that slot's numbers out of PlayerStats.txt once no picture's left there. Copies are
;told by their .raw.png (never made see-through). Never the card's own slot, nor another learned card's. Returns how
;many pictures were taken out
LearnReconcile()
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	sets := LearnSets(), moved := 0, strays := {}
	for i, c in LearnedCards
		{
		if (c.sch = "")
			continue
		for j, rel in LearnSlotNames(c.sch)
			{
			if (rel = c.slot)
				continue
			o := LearnCardInSlot(rel)
			if (IsObject(o) && o.id != c.id)
				continue
			for k, st in sets
				{
				own := st.path "\learned\" c.id ".raw.png", pic := st.path "\" rel
				if (!FileExist(own) || !LearnSameFile(pic ".raw.png", own))
					continue
				to := A_WorkingDir "\backups\learned strays\" st.name
				FileCreateDir, %to%
				fn := StrReplace(rel, "\", "_") " (" c.id ")"
				if (FileExist(to "\" fn ".png") || FileExist(to "\" fn ".raw.png"))
					fn := fn " " A_Now
				FileMove, %pic%.png, %to%\%fn%.png
				FileMove, %pic%.raw.png, %to%\%fn%.raw.png
				if (FileExist(pic ".raw.png"))
					{
					DebugLog("  learned card " c.id ": couldn't move its stray picture " pic ".raw.png")
					continue
					}
				back := A_WorkingDir "\backups\" StrReplace(rel, "\", "_") " (" st.name ", before learned card " c.id ").png"
				if (FileExist(back))
					FileCopy, %back%, %pic%.png, 1
				strays[rel] := c, moved += 1
				DebugLog("  learned card " c.id " (" LearnDescribe(c) "): its picture was also " rel " in " st.name " (its slot: " (c.slot = "" ? "none" : c.slot) ") - moved to backups\learned strays\" st.name)
				}
			}
		}
	for rel, c in strays
		{
		Loop, Files, % A_WorkingDir "\generated\ui*", D
			FileDelete, % A_LoopFileFullPath "\" rel ".bmp"
		if (!LearnSlotHasPic(rel))
			LearnStatsBack(c.sch, rel, c.id)
		}
	if (moved)
		{
		LearnFreeCache := {}, PicMade := {}
		if (VisionOn)
			VisionGet("/forget", 3000, true), VisionForget()
		}
	return moved
	}

;The slots a learned card of school sch can be in
LearnSlotNames(sch)
	{
	lsnOut := [sch "\hit1", sch "\hit2", sch "\hit3", sch "\hit4", sch "\wand", sch "\heal1", sch "\heal2", sch "\blade", sch "\trap", sch "\aura", "resources\blade3", "resources\trap3", "resources\tower"
		, "resources\strong", "resources\giant", "resources\monstrous", "resources\gargantuan", "resources\colossal", "resources\epic"
		, "resources\blade4", "resources\feint", "resources\elementalblade", "resources\elementaltrap", "resources\spiritblade", "resources\spirittrap"]
	;(and every other school's blade and trap: a pet's Stormblade on a Balance wizard goes in storm\blade - LearnBoostSlot)
	for lsnI, lsnS in ["storm", "fire", "ice", "myth", "life", "death"]
		if (lsnS != sch)
			lsnOut.Push(lsnS "\blade"), lsnOut.Push(lsnS "\trap")
	return lsnOut
	}

;---- Making room in hit1-3 for a stronger learned hit ----
;The battle casts by slot (hit3, then hit2, hit1; the kill check tries hit1 first), so hit1-3 are kept weakest to
;strongest by moving pictures and their numbers. Only after a battle; learnupgrade:0 (or <school>.learnupgrade:0)
;switches it off. Your order is kept where it can't be known: a slot is only moved when PlayerStats.txt has its
;damage and pips (hitN, hitNpips - written in the file, not the built-in guesses), it isn't X-pip (pips 0) nor kept
;with <school>.hitNkeep:1 - the others stay where they are. hit4 is never touched

;Whether learnupgrade is on for school sch (<sch>.learnupgrade first, then learnupgrade; on unless set to 0)
LearnUpgradeOn(sch)
	{
	v := LearnStatOf(sch, "learnupgrade")
	return (v = "" || v != 0)
	}

;Whether learned card c may have room made for it: a hit (one enemy or all), its damage sure (two reads agreed, or
;yours) and 20 or more, its pips read off it (not guessed) and 1 or more, not X-pip, not taken out by another card
LearnArrangeOk(c)
	{
	if ((c.type != "damage" && c.type != "aoe") || !LearnUpgradeOn(c.sch))
		return false
	v := LearnValueKnown(c)
	if (v = "" || v < 20 || c.guess || c.pips = "" || c.pips < 1)
		return false
	return !LearnHasFlag(c, "xpip") && !LearnHasFlag(c, "out")
	}

;Room in hit1-3 for learned hit c that has no free slot it fits: out of battle at once (LearnArrangeNow), during one
;it waits for the end (LearnArrangePending). 1 if it's in a slot now
LearnArrange(c)
	{
	if (!LearnArrangeOk(c))
		return 0
	if (inbattle = 1)
		{
		if (LearnQueue("p|" c.id))
			DebugLog("  learned card " c.id " (" LearnDescribe(c) "): no free slot - after this battle room is made for it in " c.sch "\hit1-3 if it's strong enough")
		return 0
		}
	return LearnArrangeNow(c)
	}

;job waits for the battle's end (LearnArrangeQueue) - 1 if it wasn't waiting already
LearnQueue(job)
	{
	if (!IsObject(LearnArrangeQueue))
		LearnArrangeQueue := []
	for i, j in LearnArrangeQueue
		if (j = job)
			return 0
	LearnArrangeQueue.Push(job)
	return 1
	}

;What waited for the battle's end: room made in hit1-3 ("p|<id>": a free slot first, things may have changed), an
;arrangement put back ("u|<id>|<why>"). Out of battle only. Returns how many cards went into or out of a slot
LearnArrangePending()
	{
	if (inbattle = 1 || !IsObject(LearnArrangeQueue) || !LearnArrangeQueue.Length())
		return 0
	if (!IsObject(LearnedCards))
		LearnLoad()
	todo := LearnArrangeQueue, LearnArrangeQueue := [], got := 0, LearnFreeCache := {}
	for i, job in todo
		{
		j := StrSplit(job, "|",, 3)
		c := LearnCardOf(j[2])
		if (!IsObject(c))
			continue
		if (j[1] = "u")
			{
			if (c.slot != "" && LearnUnplace(c, j[3]))
				got += 1
			}
		else if (c.slot = "" && LearnPlace(c))
			got += 1
		}
	if (got)
		{
		LearnSave()
		PicMade := {}, LearnFreeCache := {}
		if (VisionOn)
			VisionGet("/forget", 3000, true), VisionForget()
		}
	return got
	}

;Makes room in hit1-3 of its school for learned hit c (LearnArrangeOk). The slots that may move (see above), the
;others pinned; a free slot among hit1-3: c goes in with the others, weakest to strongest. None free: one leaves -
;the weakest, but never the cheapest (fewest pips) when c costs more, never the only all-enemies hit when c hits one
;enemy, and never a deck spell for a treasure card (it's used up) - and only when c is 15% stronger. Then those slots
;are rewritten weakest to strongest (LearnLayout). 1 if c is in a slot now
LearnArrangeNow(c)
	{
	static said := {}
	sch := c.sch, have := LearnFileStats(), slots := [], free := ""
	Loop, 3
		{
		n := A_Index, rel := sch "\hit" n, kk := sch ".hit" n
		if (!LearnSlotHasPic(rel))
			{
			if (free = "")
				free := n
			continue
			}
		if (!have.HasKey(kk) || !have.HasKey(kk "pips") || Stats[kk "pips"] <= 0 || Stats[kk] <= 0 || (Stats.HasKey(kk "keep") && Stats[kk "keep"] = 1))
			continue
		o := LearnCardInSlot(rel)
		slots.Push({n: n, from: n, value: Stats[kk] + 0, pips: Stats[kk "pips"] + 0, target: Stats.HasKey(kk "target") ? Stats[kk "target"] + 0 : 0
			, hasTarget: have.HasKey(kk "target"), card: o, tc: IsObject(o) && LearnHasFlag(o, "tc")})
		}
	nv := LearnValueKnown(c) + 0, np := c.pips + 0, nt := (c.type = "damage") ? 1 : 0
	victim := "", why := ""
	if (free = "")
		{
		if (!slots.Length())
			why := "hit1-3 are all taken and none may move (X-pip, kept with hitNkeep:1, or their damage and pips aren't in PlayerStats.txt)"
		else
			{
			cheap := "", aoes := 0
			for i, st in slots
				{
				if (!IsObject(cheap) || st.pips < cheap.pips)
					cheap := st
				aoes += (st.target = 0)
				}
			for i, st in slots
				{
				if ((np > cheap.pips && st.n = cheap.n) || (nt = 1 && st.target = 0 && aoes = 1) || (LearnHasFlag(c, "tc") && !st.tc))
					continue
				if (!IsObject(victim) || st.value < victim.value)
					victim := st
				}
			if (!IsObject(victim))
				why := "the hits it could take the place of are kept (the cheapest, your only all-enemies hit" (LearnHasFlag(c, "tc") ? ", or a deck spell - it's a treasure card" : "") ")"
			else if (nv < 1.15 * victim.value)
				why := "not 15% stronger than " sch "\hit" victim.n " (" victim.value ")", victim := ""
			}
		if (why != "")
			{
			if (!said.HasKey(c.id "|" why))
				said[c.id "|" why] := 1, DebugLog("  learned card " c.id " (" LearnDescribe(c) "): no room made for it - " why)
			return 0
			}
		}
	;(who's in those slots after: the others and c, weakest first - equal: the one that was there first)
	list := []
	for i, st in slots
		if (!IsObject(victim) || st.n != victim.n)
			list.Push(st)
	list.Push({n: 0, from: 0, value: nv, pips: np, target: nt, hasTarget: 1, card: c, tc: LearnHasFlag(c, "tc")})
	LearnSortByValue(list)
	nums := []
	for i, st in slots
		nums.Push(st.n)
	if (!IsObject(victim))
		nums.Push(free)
	LearnSortNums(nums)
	place := {}, moved := 0
	for i, occ in list
		{
		if (occ.from = nums[i])
			continue
		place[nums[i]] := occ
		moved += (occ.from > 0)
		}
	;(nothing would move, nothing leave: it'd only go in a free slot out of order with your pinned ones - LearnSlotFor
	;said no to that)
	if (!moved && !IsObject(victim))
		return 0
	return LearnLayout(c, place, victim)
	}

;Sorts list (of {value}) weakest first, keeping the order of equals
LearnSortByValue(list)
	{
	Loop, % list.Length()
		{
		i := A_Index
		while (i > 1 && list[i].value < list[i - 1].value)
			t := list[i], list[i] := list[i - 1], list[i - 1] := t, i -= 1
		}
	}

;Sorts an array of numbers, smallest first
LearnSortNums(nums)
	{
	Loop, % nums.Length()
		{
		i := A_Index
		while (i > 1 && nums[i] < nums[i - 1])
			t := nums[i], nums[i] := nums[i - 1], nums[i - 1] := t, i -= 1
		}
	}

;Rewrites hit1-3 of learned card c's school (LearnArrangeNow): place[n] is who goes in hitN - {from: the slot it was in,
;0 for c; value, pips, target, hasTarget, card: the catalog entry, "" for your own picture}; victim: who leaves ("").
;First everything that's there is kept in backups\hits <school> <when> (<id>)\ - every picture set's hit1-3 pictures,
;their PlayerStats.txt lines (stats.txt), the whole file, layout.txt - then the new pictures are written under other
;names, checked, and only then put in place; the numbers after that, and the catalog. Any failure: all put back as it
;was, the numbers untouched. A card that leaves is only in the snapshot (a learned one stays in the catalog, its flag
;out=<c's id>). 1 if done
LearnLayout(c, place, victim)
	{
	sch := c.sch
	FormatTime, stamp,, yyyyMMdd-HHmmss
	snapName := "hits " sch " " stamp " (" c.id ")"
	snap := A_WorkingDir "\backups\" snapName
	sets := LearnSets(), names := ""
	FileCreateDir, %snap%
	if (ErrorLevel || !InStr(FileExist(snap), "D"))
		{
		DebugLog("  learned card " c.id ": couldn't make " snap " - nothing moved")
		return 0
		}
	;(1. the snapshot, checked file by file)
	for i, st in sets
		{
		names .= (names = "" ? "" : ",") st.name
		Loop, 3
			{
			n := A_Index
			for j, ext in [".png", ".raw.png"]
				{
				from := st.path "\" sch "\hit" n ext
				if (!FileExist(from))
					continue
				FileCreateDir, % snap "\" st.name
				FileCopy, %from%, % snap "\" st.name "\hit" n ext, 1
				if (ErrorLevel || !LearnSameFile(from, snap "\" st.name "\hit" n ext))
					{
					DebugLog("  learned card " c.id ": couldn't keep " from " in " snap " - nothing moved")
					return 0
					}
				}
			}
		}
	keys := LearnHitKeys(sch)
	before := LearnStatLines(keys)
	LearnWriteLines(snap "\stats.txt", keys, before)
	FileCopy, % A_WorkingDir "\PlayerStats.txt", % snap "\PlayerStats.txt", 1
	;(2. what goes where, set by set: a card that moves from the snapshot - a 3-way move never loses a file - c from
	;its learned picture; where a set has no picture of who goes in, that slot's picture there goes - it'd be another
	;card's - unless it's a placeholder)
	plan := []
	for i, st in sets
		for n, occ in place
			{
			to := st.path "\" sch "\hit" n
			from := occ.from ? snap "\" st.name "\hit" occ.from : st.path "\learned\" c.id
			if (LearnRealPic(from ".png"))
				plan.Push({to: to, from: from, raw: FileExist(from ".raw.png") != ""})
			else if (LearnRealPic(to ".png") || FileExist(to ".raw.png"))
				plan.Push({to: to, from: "", keepPng: !LearnRealPic(to ".png")})
			}
	if (!LearnRealPic(A_WorkingDir (c.dir = "" ? "" : "\" c.dir) "\learned\" c.id ".png"))
		{
		DebugLog("  learned card " c.id ": its picture is missing - nothing moved")
		return 0
		}
	;(3. under other names first, each checked)
	ok := true
	for i, p in plan
		{
		if (p.from = "")
			continue
		toPng := p.to ".png"
		SplitPath, toPng,, toDir
		FileCreateDir, %toDir%
		FileCopy, % p.from ".png", % p.to ".png.arr", 1
		ok := ok && !ErrorLevel && LearnSameFile(p.from ".png", p.to ".png.arr")
		if (p.raw)
			{
			FileCopy, % p.from ".raw.png", % p.to ".raw.png.arr", 1
			ok := ok && !ErrorLevel && LearnSameFile(p.from ".raw.png", p.to ".raw.png.arr")
			}
		}
	if (!ok)
		{
		for i, p in plan
			FileDelete, % p.to ".png.arr"
		for i, p in plan
			FileDelete, % p.to ".raw.png.arr"
		DebugLog("  learned card " c.id ": couldn't write the new pictures - nothing moved")
		return 0
		}
	;(4. into place, then checked again; any failure: the snapshot put back)
	for i, p in plan
		{
		if (p.from = "")
			{
			;(a placeholder stays - it never counts)
			if (!p.keepPng)
				FileDelete, % p.to ".png"
			FileDelete, % p.to ".raw.png"
			ok := ok && (p.keepPng || !FileExist(p.to ".png")) && !FileExist(p.to ".raw.png")
			continue
			}
		FileMove, % p.to ".png.arr", % p.to ".png", 1
		ok := ok && !ErrorLevel
		if (p.raw)
			{
			FileMove, % p.to ".raw.png.arr", % p.to ".raw.png", 1
			ok := ok && !ErrorLevel
			}
		else
			{
			FileDelete, % p.to ".raw.png"
			ok := ok && !FileExist(p.to ".raw.png")
			}
		}
	for i, p in plan
		if (p.from != "")
			ok := ok && LearnSameFile(p.from ".png", p.to ".png") && (!p.raw || LearnSameFile(p.from ".raw.png", p.to ".raw.png"))
	if (!ok)
		{
		LearnSnapPut(snap, sch, StrSplit(names, ","))
		for i, p in plan
			FileDelete, % p.to ".png.arr"
		for i, p in plan
			FileDelete, % p.to ".raw.png.arr"
		DebugLog("  learned card " c.id ": the new pictures didn't go in right - all put back as it was (" snap ")")
		return 0
		}
	;(5. the numbers - the card's id in every comment)
	edits := []
	for n, occ in place
		{
		kk := sch ".hit" n
		if (occ.from = 0)
			note := LearnStatsNote(c)
		else if (IsObject(occ.card))
			note := "moved from hit" occ.from " - learned card " occ.card.id
		else
			note := "your picture, moved from hit" occ.from (RegExMatch(before[sch ".hit" occ.from], ";\s*(.*)$", cm) ? ": " cm1 : "")
		edits.Push([kk, kk ":" occ.value "   `; " note])
		edits.Push([kk "pips", kk "pips:" occ.pips])
		edits.Push([kk "target", occ.hasTarget ? kk "target:" occ.target : ""])
		}
	if (!LearnStatsWrite(edits))
		{
		LearnSnapPut(snap, sch, StrSplit(names, ","))
		DebugLog("  learned card " c.id ": PlayerStats.txt couldn't be written - the pictures put back as they were (" snap ")")
		return 0
		}
	;(6. what it's like now - for putting it back: LearnUndoLayout)
	for i, st in sets
		Loop, 3
			{
			n := A_Index
			for j, ext in [".png", ".raw.png"]
				if (FileExist(st.path "\" sch "\hit" n ext))
					{
					FileCreateDir, % snap "\after\" st.name
					FileCopy, % st.path "\" sch "\hit" n ext, % snap "\after\" st.name "\hit" n ext, 1
					}
			}
	LearnWriteLines(snap "\after_stats.txt", keys, LearnStatLines(keys))
	;(7. the catalog)
	lay := "; What was done to " sch "\hit1-3 for learned card " c.id " (" LearnDescribe(c) ") - put back by forgetting it or changing its kind on the Spells tab`r`n"
		. "; before: " LearnLayoutText(sch, before) "`r`nschool|" sch "`r`ncard|" c.id "`r`nsets|" names "`r`n"
	for n, occ in place
		{
		if (IsObject(occ.card))
			occ.card.slot := sch "\hit" n
		lay .= "move|" (IsObject(occ.card) ? occ.card.id : "yours") "|" occ.from "|" n "`r`n"
		}
	if (IsObject(victim))
		{
		if (IsObject(victim.card))
			victim.card.slot := "", LearnSetFlag(victim.card, "out", c.id)
		lay .= "out|" (IsObject(victim.card) ? victim.card.id : "yours") "|" victim.n "`r`n"
		}
	LearnSetFlag(c, "snap", snapName)
	written := ""
	;(and the ones it took away - an update would bring back the release's picture of the card that was there)
	for i, p in plan
		if (p.from != "")
			written .= SubStr(p.to, StrLen(A_WorkingDir) + 2) ".png`r`n" (p.raw ? SubStr(p.to, StrLen(A_WorkingDir) + 2) ".raw.png`r`n" : "")
		else
			written .= SubStr(p.to, StrLen(A_WorkingDir) + 2) ".png`r`n" SubStr(p.to, StrLen(A_WorkingDir) + 2) ".raw.png`r`n"
	FileAppend, %lay%, %snap%\layout.txt
	FileAppend, %written%, %snap%\written.txt
	LearnWritten(written, true)
	;(8. pictures made from what was there, the helper and PicPath look again)
	for n, occ in place
		Loop, Files, % A_WorkingDir "\generated\ui*", D
			FileDelete, % A_LoopFileFullPath "\" sch "\hit" n ".bmp"
	LearnFreeCache := {}, PicMade := {}
	LearnSave()
	if (VisionOn)
		VisionGet("/forget", 3000, true), VisionForget()
	said := ""
	for n, occ in place
		said .= (said = "" ? "" : "; ") (occ.from = 0 ? LearnName(c) " now hit" n : (IsObject(occ.card) ? LearnName(occ.card) : "your hit" occ.from " picture") " moved to hit" n)
	if (IsObject(victim))
		said .= "; " (IsObject(victim.card) ? LearnName(victim.card) : "your hit" victim.n " picture") " out"
	DebugLog("  made room in " sch "\hit1-3 for learned card " c.id " (" LearnDescribe(c) "): " said " - as it was: backups\" snapName)
	TrayTip, Wizard101 bot, % "Stronger learned hit in use (" sch "): " said ". The old pictures and numbers: backups\" snapName " - forget it or change its kind on the Spells tab to put them back.", 10, 1
	return 1
	}

;What's in hit1-3 by their PlayerStats.txt lines (lines: LearnStatLines), for layout.txt
LearnLayoutText(sch, lines)
	{
	out := ""
	Loop, 3
		{
		kk := sch ".hit" A_Index
		o := LearnCardInSlot(sch "\hit" A_Index)
		out .= (A_Index > 1 ? ", " : "") "hit" A_Index " " (lines[kk] = "-" ? "-" : RegExReplace(lines[kk], "^[^:]*:\s*([^\s;]*).*", "$1")) (IsObject(o) ? " (" o.id ")" : "")
		}
	return out
	}

;Puts every picture set's hit1-3 of school sch back as snapshot folder snap has them (setNames: the sets it was made
;of; a picture that wasn't there then is taken away). 1 if all went back
LearnSnapPut(snap, sch, setNames)
	{
	ok := 1
	for i, nm in setNames
		{
		path := (nm = "main") ? A_WorkingDir : A_WorkingDir "\" nm
		Loop, 3
			{
			n := A_Index
			for j, ext in [".png", ".raw.png"]
				{
				from := snap "\" nm "\hit" n ext, to := path "\" sch "\hit" n ext
				if (FileExist(from))
					{
					FileCopy, %from%, %to%, 1
					if (ErrorLevel || !LearnSameFile(from, to))
						ok := 0
					}
				else if (FileExist(to))
					{
					FileDelete, %to%
					if (FileExist(to))
						ok := 0
					}
				}
			}
		}
	return ok
	}

;Puts back the arrangement learned card c was put in hit1-3 by (its flag snap=): when no picture in hit1-3 has changed
;since - by .raw.png, never made see-through, else the .png - every set's hit1-3 come back from the snapshot, with the
;cards that were moved or taken out, and their numbers too unless you changed those lines since (then they're left as
;you set them). Else only c comes out of its slot (the rest stays; the snapshot is named in debug.log). 1 if put back
LearnUndoLayout(c, why)
	{
	snapName := LearnFlag(c, "snap"), snap := A_WorkingDir "\backups\" snapName
	LearnDropFlag(c, "snap")
	for i, o in LearnedCards
		if (LearnFlag(o, "out") = c.id)
			LearnDropFlag(o, "out")
	FileRead, lay, %snap%\layout.txt
	if (ErrorLevel || snapName = "")
		{
		DebugLog("  learned card " c.id ": " snap "\layout.txt can't be read - only it comes out of its slot")
		return 0
		}
	sch := "", setNames := [], moves := [], outs := []
	Loop, Parse, lay, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "school")
			sch := f[2]
		else if (f[1] = "sets")
			setNames := StrSplit(f[2], ",")
		else if (f[1] = "move")
			moves.Push(f)
		else if (f[1] = "out")
			outs.Push(f)
		}
	same := (sch != "")
	for i, st in LearnSets()
		Loop, 3
			if (!LearnSameState(snap "\after\" st.name "\hit" A_Index, st.path "\" sch "\hit" A_Index))
				same := false
	if (!same)
		{
		DebugLog("  learned card " c.id ": pictures in " sch "\hit1-3 changed since room was made for it - only it comes out of its slot; what was there before: backups\" snapName)
		return 0
		}
	;(their numbers changed since - not just a comment: then the pictures stay too, or pictures and numbers wouldn't
	;match; only this card comes out of its slot)
	keys := LearnHitKeys(sch), now := LearnStatLines(keys), aft := LearnReadLines(snap "\after_stats.txt"), old := LearnReadLines(snap "\stats.txt")
	for i, kk in keys
		if (!aft.HasKey(kk) || LearnStatValue(now[kk]) != LearnStatValue(aft[kk]))
			{
			DebugLog("  learned card " c.id ": " sch "\hit1-3's numbers in PlayerStats.txt were changed since room was made for it - only it comes out of its slot; what was there before: backups\" snapName)
			return 0
			}
	if (!LearnSnapPut(snap, sch, setNames))
		DebugLog("  learned card " c.id ": not every picture could be put back from backups\" snapName)
	edits := []
	for i, kk in keys
		edits.Push([kk, (!old.HasKey(kk) || old[kk] = "-") ? "" : old[kk]])
	LearnStatsWrite(edits)
	for i, m in moves
		if (m[2] != "yours" && m[2] != c.id && IsObject(o := LearnCardOf(m[2])))
			o.slot := sch "\hit" m[3]
	for i, m in outs
		if (m[2] != "yours" && IsObject(o := LearnCardOf(m[2])))
			o.slot := sch "\hit" m[3], LearnDropFlag(o, "out")
	c.slot := ""
	Loop, Files, % A_WorkingDir "\generated\ui*", D
		Loop, 3
			FileDelete, % A_LoopFileFullPath "\" sch "\hit" A_Index ".bmp"
	FileRead, written, %snap%\written.txt
	LearnWritten(written, false)
	FileAppend, % "undone|" A_Now "|" why "`r`n", %snap%\layout.txt
	LearnFreeCache := {}, PicMade := {}
	DebugLog("  learned card " c.id " (" LearnDescribe(c) "): " why " - " sch "\hit1-3 put back as they were before it (backups\" snapName ")")
	return 1
	}

;A PlayerStats.txt line's number alone - no comment, no spaces ("-" for none stays "-")
LearnStatValue(line)
	{
	return Trim(RegExReplace(line, "\s*;.*$"))
	}

;Whether picture cur (a path without .png) is as after (the snapshot's after\ copy): the same .raw.png where it had
;one, else the same .png (and no .raw.png); after has none: cur has none big enough to use
LearnSameState(after, cur)
	{
	if (FileExist(after ".raw.png"))
		return LearnSameFile(after ".raw.png", cur ".raw.png")
	if (FileExist(after ".png"))
		return LearnSameFile(after ".png", cur ".png") && !FileExist(cur ".raw.png")
	return !LearnRealPic(cur ".png")
	}

;PlayerStats.txt's keys for school sch's hit1-3 (damage, pips, target, keep)
LearnHitKeys(sch)
	{
	out := []
	Loop, 3
		{
		n := A_Index
		for i, sfx in ["", "pips", "target", "keep"]
			out.Push(sch ".hit" n sfx)
		}
	return out
	}

;Slot pictures an arrangement wrote (rel paths in the AutoFarmer folder, one a line), kept in learned\slots_written.txt
;so an update never puts the release's picture over them (Updater.ahk UpIsMine). add false: taken off it (put back)
LearnWritten(paths, add)
	{
	file := A_WorkingDir "\learned\slots_written.txt"
	FileRead, have, %file%
	list := {}, order := []
	Loop, Parse, have, `n, `r
		if (A_LoopField != "" && !list.HasKey(A_LoopField))
			list[A_LoopField] := 1, order.Push(A_LoopField)
	Loop, Parse, paths, `n, `r
		{
		if (A_LoopField = "")
			continue
		if (add && !list.HasKey(A_LoopField))
			list[A_LoopField] := 1, order.Push(A_LoopField)
		else if (!add)
			list.Delete(A_LoopField)
		}
	out := ""
	for i, p in order
		if (list.HasKey(p))
			out .= p "`r`n"
	FileCreateDir, % A_WorkingDir "\learned"
	FileDelete, %file%.tmp
	FileAppend, %out%, %file%.tmp
	FileMove, %file%.tmp, %file%, 1
	}

;---- The Spells tab's (Spells.ahk) - call on the main thread, out of battle ----

;The kinds a learned card can be: [{kind, label, played (the bot casts it), menu (offered on the Spells tab)}]
LearnTypes()
	{
	static types := ""
	if (!IsObject(types))
		types := [{kind: "damage", label: "Hits one enemy", played: 1, menu: 1}
			, {kind: "aoe", label: "Hits all enemies", played: 1, menu: 1}
			, {kind: "heal", label: "Heals you", played: 1, menu: 1}
			, {kind: "ward", label: "Shield (cast on you)", played: 1, menu: 1}
			, {kind: "blade", label: "Blade", played: 1, menu: 1}
			, {kind: "trap", label: "Trap", played: 1, menu: 1}
			, {kind: "aura", label: "Aura", played: 1, menu: 1}
			, {kind: "enchant", label: "Enchant (+N damage on a hit)", played: 1, menu: 1}
			, {kind: "dot", label: "Damage over time", played: 0, menu: 1}
			, {kind: "stun", label: "Stun", played: 0, menu: 1}
			, {kind: "dispel", label: "Dispel", played: 0, menu: 1}
			, {kind: "prism", label: "Prism (converts the school)", played: 0, menu: 1}
			, {kind: "clear", label: "Removes shields or charms (N times Clear)", played: 0, menu: 1}
			, {kind: "polymorph", label: "Polymorph / shift (Moon)", played: 0, menu: 1}
			, {kind: "weakness", label: "Weakness", played: 0, menu: 0}
			, {kind: "xpip", label: "X-pip spell", played: 0, menu: 0}
			, {kind: "keep", label: "Not used (stays in the list)", played: 0, menu: 1}]
	return types
	}

;A kind's label, for you ("" unknown)
LearnKindLabel(kind)
	{
	for i, t in LearnTypes()
		if (t.kind = kind)
			return t.label
	return "unknown"
	}

;Whether the bot plays kind (dot, stun, dispel, prism, clear, weakness, xpip, keep and "" it doesn't: no slot)
LearnPlayed(kind)
	{
	for i, t in LearnTypes()
		if (t.kind = kind)
			return t.played
	return 0
	}

;Learned card id's kind set to kind (LearnTypes; flag user: never changed by itself again): out of its slot first (an
;arrangement it was put in put back), then a slot for it if it has one now. Returns what happened, for the log
LearnSetKind(id, kind)
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	c := LearnCardOf(id)
	if (!IsObject(c))
		return "no learned card " id
	if (c.slot != "" && !LearnUnplace(c, "its kind was changed on the Spells tab"))
		return "not now: it's taken out of " c.slot " after this battle"
	c.type := kind, c.target := (kind = "damage") ? 1 : 0
	;(yours now, not the game's - flag mem again only while what you set is what the game says: LearnApplyMem)
	LearnSetFlag(c, "user"), LearnDropFlag(c, "out"), LearnDropFlag(c, "mem")
	got := VisionOn ? LearnPlace(c) : 0
	LearnSave()
	PicMade := {}, LearnFreeCache := {}
	if (VisionOn)
		VisionGet("/forget", 3000, true), VisionForget()
	DebugLog("  Spells: learned card " c.id " is " LearnDescribe(c) " now - " (c.slot != "" ? "in use as " c.slot : "kept (" LearnWhyNot(c) ")"))
	return LearnDescribe(c) " - " (c.slot != "" ? "in use as " c.slot : "kept (" LearnWhyNot(c) ")")
	}

;Learned card id's name, number and pips set as you typed them ("" for unknown; flag user, pips not guessed): its
;numbers in PlayerStats.txt again when it's in a slot - out of it (and into one it fits) when they no longer fit it.
;Returns what happened, for the log
LearnEdit(id, name, value, pips, keepGuess := 0, nameOnly := 0)
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	c := LearnCardOf(id)
	if (!IsObject(c))
		return "no learned card " id
	value := Trim(value), pips := Trim(pips)
	;(X: an X-pip spell - all your pips; the number then its damage a pip)
	xp := RegExMatch(pips, "^[xX]$")
	if ((value != "" && !RegExMatch(value, "^\d+$")) || (pips != "" && !xp && !RegExMatch(pips, "^\d+$")))
		return "the number has to be a whole number, the pips a whole number or X (or blank)"
	;(the pips typed - not a name or number alone: X or not, as typed)
	if (!keepGuess && !nameOnly)
		{
		if (xp)
			LearnSetFlag(c, "xpip")
		else
			LearnDropFlag(c, "xpip")
		}
	pips := xp ? 0 : pips
	;(keepGuess: only its name or number edited - the Spells list's cells: guessed pips stay guessed, still corrected
	;from the card's pip digit)
	c.name := LearnClean(name), c.value := value, c.pips := pips, c.guess := keepGuess && pips != "" ? c.guess : 0
	;(nameOnly: only its name - the learner never changes a name, so not marked yours: its number and pips still read.
	;Else yours, not the game's - flag mem again only while what you set is what the game says: LearnApplyMem)
	if (!nameOnly)
		LearnSetFlag(c, "user"), LearnDropFlag(c, "mem")
	;(no longer fitting its slot: out first - one put in by an arrangement is put back with the numbers as they were -
	;then where it fits; else its new numbers there)
	if (c.slot != "")
		{
		fits := true
		if (RegExMatch(c.slot, "\\hit([1-4])$", hn))
			fits := LearnHitFits(c, hn1)
		else if ((c.type = "blade" || c.type = "trap" || c.type = "aura") && c.value = "")
			fits := false
		;(an enchant's slot goes by its number - the kill check adds that slot's enchantN)
		else if (c.type = "enchant")
			fits := LearnEnchantSlotOk(c)
		if (fits)
			LearnStats(c)
		else if (LearnUnplace(c, "its numbers were changed on the Spells tab") && VisionOn)
			LearnPlace(c)
		}
	else if (VisionOn)
		LearnPlace(c)
	LearnSave()
	PicMade := {}, LearnFreeCache := {}
	if (VisionOn)
		VisionGet("/forget", 3000, true), VisionForget()
	DebugLog("  Spells: learned card " c.id " edited - " LearnDescribe(c) (c.slot != "" ? " - in use as " c.slot : ""))
	return LearnDescribe(c) (c.slot != "" ? " - in use as " c.slot : " - kept (" LearnWhyNot(c) ")")
	}

;Forgets learned card id (LearnForget). Returns what happened, for the log
LearnForgetById(id)
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	c := LearnCardOf(id)
	if (!IsObject(c))
		return "no learned card " id
	return LearnForget(c, "forgotten on the Spells tab") ? "forgotten (its files: backups\learned forgotten)" : "not now: it's taken out of its slot after this battle"
	}

;Learned card id never discarded (flag hold) - or again as before. Returns 1 now held, 0 not, "" no such card
;The schools a spell can be of: the seven, and the astral ones (Sun: enchants, Star: auras, Moon: polymorphs) and Shadow
LearnSchools()
	{
	return ["fire", "ice", "storm", "myth", "life", "death", "balance", "sun", "star", "moon", "shadow"]
	}

;Learned card id's own school set (the Spells tab): flag school=<it> - the school the card is of, which can be another than
;the wizard's it was learned for (sch: whose deck and slots it's in - not changed); "" or the wizard's: the flag dropped
LearnSetSchool(id, s)
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	c := LearnCardOf(id)
	if (!IsObject(c))
		return "no learned card " id
	StringLower, s, s
	ok := false
	for i, k in LearnSchools()
		if (k = s)
			ok := true
	if (s != "" && !ok)
		return "not a school: " s
	if (s = "" || s = c.sch)
		LearnDropFlag(c, "school")
	else
		LearnSetFlag(c, "school", s)
	LearnSave()
	return "its school " (s = "" ? c.sch : s) (s != "" && s != c.sch ? " (learned for your " c.sch " wizard - still in that deck)" : "")
	}

;Learned card id a treasure card or not (the Spells tab): flag tc - never discarded, the wand's slot - and notc when you
;said it isn't (the learner then doesn't make it one again from the hand's look). Out of its slot and into the one it
;fits now
LearnSetTc(id, on)
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	c := LearnCardOf(id)
	if (!IsObject(c))
		return "no learned card " id
	if ((LearnHasFlag(c, "tc") ? 1 : 0) = (on ? 1 : 0))
		return on ? "a treasure card already" : "not a treasure card already"
	if (c.slot != "" && !LearnUnplace(c, "set " (on ? "" : "not ") "a treasure card on the Spells tab"))
		return "not now: it's taken out of " c.slot " after this battle"
	if (on)
		LearnSetFlag(c, "tc"), LearnDropFlag(c, "notc")
	else
		LearnDropFlag(c, "tc"), LearnSetFlag(c, "notc")
	got := VisionOn ? LearnPlace(c) : 0
	LearnSave()
	PicMade := {}, LearnFreeCache := {}
	if (VisionOn)
		VisionGet("/forget", 3000, true), VisionForget()
	return (on ? "a treasure card" : "not a treasure card") " - " (c.slot != "" ? "in use as " c.slot : "kept (" LearnWhyNot(c) ")")
	}

LearnToggleHold(id)
	{
	if (!IsObject(LearnedCards))
		LearnLoad()
	c := LearnCardOf(id)
	if (!IsObject(c))
		return ""
	if (LearnHasFlag(c, "hold"))
		LearnDropFlag(c, "hold")
	else
		LearnSetFlag(c, "hold")
	LearnSave()
	return LearnHasFlag(c, "hold") ? 1 : 0
	}

;---- The catalog's file ----

;What learned card c is, for you
LearnDescribe(c)
	{
	pips := LearnHasFlag(c, "xpip") ? "X pips (all you have)" : (c.pips = "") ? "pips unknown" : c.pips " pip" (c.pips = 1 ? "" : "s") (c.guess ? " (guessed)" : "")
	v := (c.value = "") ? "?" : c.value, dt := LearnFlag(c, "dot"), kd := c.type
	ot := (dt != "") ? " (+" dt " over time)" : ""
	if (kd = "damage")
		d := "hits one enemy for " v ot
	else if (kd = "aoe")
		d := "hits all enemies for " v ot
	else if (kd = "heal")
		d := "heals " v
	else if (kd = "ward")
		d := "a shield (" (c.value != "" ? "-" c.value "%" : c.text) ")"
	else if (kd = "blade")
		d := "a blade (" (c.value != "" ? "+" c.value "%" : c.text) ")"
	else if (kd = "trap")
		d := "a trap (" (c.value != "" ? "+" c.value "%" : c.text) ")"
	else if (kd = "aura")
		d := "an aura (+" v "% for 4 rounds)"
	else if (kd = "enchant")
		d := "an enchant (+" v " damage on a hit)"
	else if (kd = "dot")
		d := "damage over time" (dt != "" ? " (" dt ")" : "")
	else if (kd = "stun")
		d := "a stun"
	else if (kd = "dispel")
		d := "a dispel"
	else if (kd = "prism")
		d := "a prism (converts the enemies' school)"
	else if (kd = "clear")
		d := "removes shields or charms (N times Clear)"
	else if (kd = "weakness")
		d := "a weakness (-" v "%)"
	else if (kd = "xpip")
		d := "an X-pip spell (" v " a pip)"
	else if (kd = "keep")
		d := (LearnHasFlag(c, "mem") && !LearnHasFlag(c, "user")) ? "a kind the bot doesn't play (" c.text ")" : "not used (your choice)"
	else
		d := "type unknown (""" c.text """)"
	return (c.name != "" ? c.name ": " : "") d ", " pips
	}

;The cut picture set for this UI size (a new ui<scale> folder if there's none within 1%): learned cards go
;in there, since they're cut at this size. create false: only its name (the helper makes the folder when
;it cuts a card into it; then this is called again to add it to the picture sets)
LearnSetDir(create := true)
	{
	if (!PicSets[PicSet].gen)
		return PicDir
	for i, set in PicSets
		if (!set.gen && Abs(set.scale / UiScale - 1) < 0.01)
			return set.dir
	dir := A_WorkingDir "\ui" Round(UiScale, 3)
	if (!create)
		return dir
	FileCreateDir, %dir%
	PicSets.Push({dir: dir, scale: Round(UiScale, 3) + 0, gen: 0})
	PicMade := {}
	DebugLog("  new picture set " dir " for the cards learned at this UI size")
	return dir
	}

;learned\cards.txt -> LearnedCards (lines of 12 fields from older versions too)
LearnLoad()
	{
	LearnedCards := []
	FileRead, text, % A_WorkingDir "\learned\cards.txt"
	Loop, Parse, text, `n, `r
		{
		if (A_LoopField = "" || SubStr(A_LoopField, 1, 1) = ";")
			continue
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12)
			continue
		c := {id: f[1], sch: f[2], type: f[3], pips: f[4], guess: f[5] + 0, value: f[6], target: f[7] + 0, slot: f[8], scale: f[9], dir: f[10], when: f[11], text: f[12]
			, name: f.Length() >= 13 ? f[13] : "", flags: f.Length() >= 14 ? f[14] : ""}
		;(a line from before v0.31: a number it holds was one two reads agreed on - the rule then)
		if (f.Length() < 14 && c.value != "")
			LearnSetFlag(c, "two")
		;(a blade learned before blades were known by their text: one now - it gets the blade slot when next in hand)
		if (c.type = "" && LearnLooksBlade(c))
			c.type := "blade"
		LearnedCards.Push(c)
		}
	;(one whose picture is still in a slot is that slot's card - its record of it can have been lost)
	back := 0
	for i, c in LearnedCards
		if (c.slot = "" && (slot := LearnSlotWithPicture(c)) != "")
			{
			c.slot := slot, back += 1
			DebugLog("  learned card " c.id " (" LearnDescribe(c) "): its picture is " slot "'s - in use there again")
			}
	if (back)
		LearnSave()
	}

;The slot whose picture is learned card c's own (a copy of it - its .raw.png, never made see-through, the same - in the
;picture set it was learned in) - "" none. Its school's hits, wand, heals, blade, trap and aura, and the blades, trap
;and shield every school shares. Not another learned card's slot
LearnSlotWithPicture(c)
	{
	setDir := A_WorkingDir (c.dir = "" ? "" : "\" c.dir)
	own := setDir "\learned\" c.id
	if (!FileExist(own ".png") || c.sch = "")
		return ""
	for i, slot in LearnSlotNames(c.sch)
		if (!IsObject(LearnCardInSlot(slot)) && LearnSameCard(setDir "\" slot, own))
			return slot
	return ""
	}

;LearnedCards -> learned\cards.txt
LearnSave()
	{
	out := "; Cards AutoFarmer learned by itself (CardLearn.ahk), one per line:`r`n"
		. "; id|school it was learned for|kind (damage = one enemy, aoe = all, heal, ward = a shield, blade, trap, aura; not played: dot = damage over time, stun, dispel, prism, clear, weakness, xpip, keep; blank = unknown)|pips|pips guessed (1)|number on the card|single target (1)|slot it's used as|UI scale|picture set|when|text read off it|name|flags`r`n"
		. "; flags: ok = checked, it's a card; icon=<its type icon>; tc = a treasure card; item = an item card (the game's); two = two reads agreed; dot=<damage over time>; xpip; mem = read from the game's memory (kind, number, pips); game=<its name in the game>; school=<its own school>; user = set on the Spells tab (never changed by itself); hold = never discarded; out=<id> = taken out of its slot by that card; snap=<backups folder of the hits it was put in by>`r`n"
		. "; Pictures: <picture set>\learned\<id>.card.png (whole card) and .png (the picture cut from it). Older versions read the first 12 fields only.`r`n"
	for i, c in LearnedCards
		{
		c.text := LearnClean(c.text), c.name := LearnClean(c.name)
		out .= LearnLine(c) "`r`n"
		}
	FileCreateDir, % A_WorkingDir "\learned"
	path := A_WorkingDir "\learned\cards.txt"
	FileDelete, %path%.tmp
	FileAppend, %out%, %path%.tmp
	FileMove, %path%.tmp, %path%, 1
	;(the Spells tab fills its list again - DashRefresh; never a GUI call from here)
	SpDirty := 1
	}

;Learned card c's cards.txt line (14 fields)
LearnLine(c)
	{
	return c.id "|" c.sch "|" c.type "|" c.pips "|" c.guess "|" c.value "|" c.target "|" c.slot "|" c.scale "|" c.dir "|" c.when "|" LearnClean(c.text) "|" LearnClean(c.name) "|" c.flags
	}

;Text made safe for the catalog and PlayerStats.txt (written in the system's code page): printable ASCII only - others
;"?", | (the field separator) "/"
LearnClean(s)
	{
	out := ""
	Loop, Parse, s
		{
		o := Ord(A_LoopField)
		out .= (A_LoopField = "|") ? "/" : (o >= 32 && o <= 126) ? A_LoopField : (o < 32) ? " " : "?"
		}
	return Trim(RegExReplace(out, " {2,}", " "))
	}

;Whether learned card c has flag key (its flags: a comma list of key or key=value)
LearnHasFlag(c, key)
	{
	return RegExMatch("," c.flags ",", "i),\Q" key "\E(=[^,]*)?,") > 0
	}

;Learned card c's flag key's value ("" none, or a flag without one)
LearnFlag(c, key)
	{
	return RegExMatch("," c.flags ",", "i),\Q" key "\E=([^,]*),", m) ? m1 : ""
	}

;Sets flag key (val: its value, "" none) on learned card c - where it is when it's there already
LearnSetFlag(c, key, val := "")
	{
	item := key (val = "" ? "" : "=" RegExReplace(val, "[,|$\\]"))
	if (LearnHasFlag(c, key))
		c.flags := Trim(RegExReplace("," c.flags ",", "i),\Q" key "\E(=[^,]*)?(?=,)", "," item,, 1), ",")
	else
		c.flags := (c.flags = "" ? "" : c.flags ",") item
	}

;Takes flag key off learned card c
LearnDropFlag(c, key)
	{
	c.flags := Trim(RegExReplace("," c.flags ",", "i),\Q" key "\E(=[^,]*)?(?=,)"), ",")
	}

;---- PlayerStats.txt ----

;Sets key:value lines in PlayerStats.txt (each replaced where it is, else added at the end, under the learned-cards
;heading; a value "" takes the key's line out) and reads the stats again. pairs: [[key, value]]; comment: after the
;first one's value
StatsSet(pairs, comment := "")
	{
	edits := []
	for each, kv in pairs
		edits.Push([kv[1], kv[2] = "" ? "" : kv[1] ":" kv[2] (each = 1 && comment != "" ? "   `; " comment : "")])
	return LearnStatsWrite(edits)
	}

;Whole lines of PlayerStats.txt set: edits [[key, line]] - the key's line replaced by line where it is (else added at
;the end, under the learned-cards heading), line "" takes every line of the key out. Every other line stays as it was,
;byte for byte. Reads the stats again. True if written
LearnStatsWrite(edits)
	{
	;(the Settings window's Save doesn't write the file halfway through this: Settings.ahk CfgWrite)
	wasCrit := A_IsCritical
	Critical
	path := A_WorkingDir "\PlayerStats.txt"
	FileRead, text, %path%
	if (ErrorLevel || !InStr(text, ":"))
		{
		DebugLog("  couldn't read PlayerStats.txt - the learned card's numbers weren't written")
		return CfgUncritical(wasCrit, false)
		}
	lines := StrSplit(StrReplace(text, "`r"), "`n")
	if (lines.Length() && lines[lines.Length()] = "")
		lines.Pop()
	heading := "; ---- Cards the bot learned by itself (CardLearn.ahk; learned\cards.txt lists them) ----"
	for each, kv in edits
		{
		found := false, i := 1
		while (i <= lines.Length())
			{
			if (RegExMatch(lines[i], "i)^\s*\Q" kv[1] "\E\s*:"))
				{
				if (kv[2] = "")
					{
					lines.RemoveAt(i)
					continue
					}
				if (!found)
					lines[i] := kv[2], found := true
				}
			i += 1
			}
		if (found || kv[2] = "")
			continue
		headAt := 0
		for i, ln in lines
			if (ln = heading)
				headAt := i
		if (!headAt)
			lines.Push(""), lines.Push(heading)
		lines.Push(kv[2])
		}
	out := ""
	for i, ln in lines
		out .= ln "`r`n"
	FileDelete, %path%.tmp
	FileAppend, %out%, %path%.tmp
	if (ErrorLevel)
		return CfgUncritical(wasCrit, false)
	FileMove, %path%.tmp, %path%, 1
	if (ErrorLevel)
		return CfgUncritical(wasCrit, false)
	LoadStats(true)
	return CfgUncritical(wasCrit, true)
	}

;PlayerStats.txt's lines for keys: {key: the line as it is (its first), or "-" none}
LearnStatLines(keys)
	{
	FileRead, text, % A_WorkingDir "\PlayerStats.txt"
	out := {}
	for i, kk in keys
		out[kk] := "-"
	Loop, Parse, text, `n, `r
		for i, kk in keys
			if (out[kk] = "-" && RegExMatch(A_LoopField, "i)^\s*\Q" kk "\E\s*:"))
				out[kk] := A_LoopField
	return out
	}

;The keys PlayerStats.txt itself sets (lower case: 1) - not the built-in guesses LoadStats starts from
LearnFileStats()
	{
	FileRead, text, % A_WorkingDir "\PlayerStats.txt"
	out := {}
	Loop, Parse, text, `n, `r
		if (RegExMatch(RegExReplace(A_LoopField, ";.*"), "^\s*([\w.]+)\s*:\s*-?\d", m))
			out[Format("{:L}", m1)] := 1
	return out
	}

;Writes lines (LearnStatLines) for keys to file, one "key|line" a line
LearnWriteLines(file, keys, lines)
	{
	out := ""
	for i, kk in keys
		out .= kk "|" lines[kk] "`r`n"
	FileDelete, %file%
	FileAppend, %out%, %file%
	}

;Reads a LearnWriteLines file: {key: line or "-"}
LearnReadLines(file)
	{
	out := {}
	FileRead, text, %file%
	Loop, Parse, text, `n, `r
		if ((at := InStr(A_LoopField, "|")) > 1)
			out[SubStr(A_LoopField, 1, at - 1)] := SubStr(A_LoopField, at + 1)
	return out
	}

;s with everything but letters, digits and -_.~ as %XX (for a request's query string)
LearnUri(s)
	{
	out := ""
	Loop, Parse, s
		out .= RegExMatch(A_LoopField, "[A-Za-z0-9_.~-]") ? A_LoopField : "%" Format("{:02X}", Ord(A_LoopField))
	return out
	}
