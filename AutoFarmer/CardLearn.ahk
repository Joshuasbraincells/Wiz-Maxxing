; CardLearn.ahk - learns the cards in hand the bot has no picture for yet, as they show up. AHK v1.1,
; functions only; #Included by Autofarmer.ahk. Needs the vision helper (Vision.ahk): without it nothing
; is learned.
;
; Once a round, after the hand's been looked at, the helper reads the hand card by card (vision.py /hand):
; where each card is, whether it's one the bot knows, whether it's greyed out (not enough pips), its type
; from the icon at the bottom right of its picture (cardicons\: damage = one enemy, aoe = all enemies,
; heal, ward = a shield) and its pip cost from the yellow digit (carddigits\). For a card it doesn't know
; (in colour - a greyed-out card's colours are gone) it:
;   - saves it in <the cut picture set for this UI size>\learned\<id>: .png (its picture, cut like the
;     hand-cut ones), .card.png (the whole card, for you to see), .icon.png, .pips.png
;   - reads its text with OCR for the numbers (e.g. "65-105" -> 65 damage, "400 for Self" -> heals 400)
;   - puts it to use in a free slot - a slot whose picture isn't cut yet:
;       damage / aoe with pips -> <school>\hit1-3 (kept weakest to strongest where it can; hit4 only for
;                                 one stronger than all of them, since hit4 is only cast on bosses)
;       damage / aoe, no pips  -> <school>\wand
;       heal                   -> <school>\heal1, heal2
;       ward                   -> resources\tower (cast on yourself)
;     copying its picture there and writing its numbers into PlayerStats.txt (<school>.hitN, hitNpips,
;     hitNtarget, ...), so the battle code uses it like any other card
;   - otherwise (no free slot, or a type it doesn't know yet) it's only kept, and recognised from then on
;     (it's tried for a slot again whenever it's in hand)
; A pip cost that couldn't be read is guessed as the pips you have (the card's in colour, so it costs no
; more), and brought down whenever the card shows up in colour with fewer.
; Everything learned is listed in learned\cards.txt; debug.log: "learned a new card ...".

global LearnedThisRound := 0
;The catalog (learned\cards.txt): [{id, sch, type, pips, guess, value, target, slot, scale, dir, when, text}]
global LearnedCards := ""
;Whether each slot is free (LearnFree), asked once a round
global LearnFreeCache := ""

;Called once a round after the hand's been looked at (FindCards). True if a card went into a slot (or a
;slot's learned picture was just made to fit a copy that differs a little): look at the hand again, so
;it's used this round
LearnCards()
	{
	if (!VisionOn || hitschool = "")
		return false
	if (!IsObject(LearnedCards))
		LearnLoad()
	;(this school's learned cards - and shields, which go in a slot of every school's - also by
	;themselves: copies of a card differ a little, so a picture cut from one copy is compared leaving out
	;the pixels that differ most, and those go see-through in it; vision.py. The ones in no slot are
	;looked for too, but only here - the battle's own search never asks about them)
	learnedList := "", learnedPics := "", LearnFreeCache := {}
	for i, c in LearnedCards
		if (c.sch = hitschool || InStr(c.slot, "resources\") = 1)
			{
			learnedList .= c.id ":" c.dir ":" c.slot ","
			if (c.slot = "")
				learnedPics .= ",learned/" c.id
			}
	here := LearnSetDir(false)
	hereRel := SubStr(here, StrLen(A_WorkingDir) + 2)
	answer := VisionGet("/hand?x1=" Round(ScreenX - HandHalf) "&y1=" Round(ScreenY - Px(75)) "&x2=" Round(ScreenX + HandHalf) "&y2=" Round(ScreenY + Px(150)) "&scale=" Round(UiScale, 3) "&pics=" VisionPicList() learnedPics "&learned=" LearnUri(learnedList) "&here=" LearnUri(hereRel) "&thumbs=" LearnUri(A_ScriptDir "\generated\hand"), 3000)
	if (answer = "")
		return false
	;(what's in hand, for the dashboard)
	DashHandSeen(answer)
	;(a card learned at another UI size was cut into a new folder for this size: a picture set from now on)
	if (InStr(FileExist(here), "D"))
		LearnSetDir(true)
	placed := 0, fresh := 0, greyNew := 0, relook := 0, setsBefore := PicSets.Length()
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f.Length() < 12 || f[1] != "card")
			continue
		card := {left: f[2] + 0, top: f[3] + 0, known: f[6], grey: f[8] + 0, type: f[9], pips: f[11], same: f[13] + 0}
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
		;(two new cards a round at most: each takes about half a second)
		else if (fresh < 2)
			{
			fresh++
			placed += LearnNew(card)
			}
		}
	if (greyNew)
		DebugLog("  " greyNew " card(s) in hand the bot doesn't know are greyed out (not enough pips) - learned once they're in colour")
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
	if (VisionGet("/cut?left=" card.left "&top=" card.top "&scale=" Round(UiScale, 3) "&out=" LearnUri(setDir "\learned\" id), 3000) = "")
		{
		DebugLog("  a new card in hand couldn't be saved (vision\vision.log)")
		return 0
		}
	;Its numbers, from its text (e.g. "65-105", "400 for Self Only", "-50% to next"): read at three sizes,
	;a number two of them agree on (OCR misreads now and then - Scorpion's 160-200 once came out 260-200)
	k := UiScale, votes := {}, value := "", text := ""
	for each, zoom in [3, 2, 4]
		{
		t := OcrRect(card.left + Round(2.6 * k), card.top + Round(74.3 * k), Round(65.6 * k), Round(29.7 * k), "en", zoom)
		t := Trim(RegExReplace(t, "[|\r\n]+", " "))
		if (text = "")
			text := t
		v := LearnValue(t, card.type)
		if (v = "")
			continue
		votes[v] := votes.HasKey(v) ? votes[v] + 1 : 1
		if (votes[v] >= 2)
			{
			value := v, text := t
			break
			}
		}
	if (value = "" && text != "")
		DebugLog("  the new card's numbers couldn't be read for sure (""" text """) - its damage counts as 0 for the kill check")
	c := {id: id, sch: hitschool, type: card.type, pips: card.pips, guess: 0, value: value, target: (card.type = "damage") ? 1 : 0, slot: ""
		, scale: Round(UiScale, 3), dir: SubStr(setDir, StrLen(A_WorkingDir) + 2), when: A_Now, text: text}
	;(no pip digit read: it's in colour, so it costs no more than the pips you have)
	if (c.pips = "" && PipsNow >= 0)
		c.pips := PipsNow, c.guess := 1
	LearnedCards.Push(c)
	got := LearnPlace(c)
	LearnSave()
	where := c.slot != "" ? "using it as " c.slot : "kept, not used (" (c.type = "" ? "a type the bot doesn't know yet" : "no free slot for it") ")"
	DebugLog("  learned a new card: " LearnDescribe(c) " - " where " (picture: " c.dir "\learned\" id ".card.png)")
	TrayTip, Wizard101 bot, % "New card learned: " LearnDescribe(c) "`n" (c.slot != "" ? "Using it as " c.slot "." : "Kept, not used yet."), 5, 1
	return got
	}

;The number on a card's text that matters: a damage range's lowest ("65-105" -> 65; "" when the range
;can't be right - Wizard101's tops are 1.1-1.7 times the bottoms, a misread 260-200 isn't), else the first
;number ("65", "400 for Self", "-50% to next" -> 50)
LearnValue(text, type)
	{
	if (RegExMatch(text, "(\d+)\s*-\s*(\d+)", m))
		{
		lo := m1 + 0, hi := m2 + 0
		return (lo > 0 && hi >= lo && hi <= 2 * lo) ? lo : ""
		}
	if (RegExMatch(text, "\d+", m))
		return m + 0
	return ""
	}

;A card the bot knows, seen again in colour: a learned one that isn't in a slot gets one if it can now;
;a guessed pip cost comes down to the pips you have. 1 if it went into a slot
LearnSeenAgain(card)
	{
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
		;put another there - so it's out of that slot)
		if (c.slot != "" && "learned/" c.id = card.known)
			{
			DebugLog("  learned card " c.id " (" LearnDescribe(c) "): " c.slot " has another picture now - not using it there any more")
			c.slot := "", changed := 1
			}
		if (c.pips = "" && PipsNow >= 0)
			{
			c.pips := PipsNow, c.guess := 1, changed := 1
			if (c.slot != "")
				LearnStats(c)
			}
		;(a hit's pips never go to 0 that way: 0 means an X-pip spell there)
		low := InStr(c.slot, "\hit") ? 1 : 0
		if (c.guess && PipsNow >= 0 && c.pips != "" && PipsNow < c.pips && PipsNow >= low)
			{
			DebugLog("  " (c.slot != "" ? c.slot : "learned card " c.id) " is in colour with " PipsNow " pips: it costs no more than that (was guessed " c.pips ")")
			c.pips := PipsNow, changed := 1
			if (c.slot != "")
				LearnStats(c)
			}
		if (c.slot = "")
			got := LearnPlace(c)
		if (got)
			DebugLog("  learned card " c.id " (" LearnDescribe(c) ") now in use as " c.slot)
		if (changed || got)
			LearnSave()
		return got
		}
	return 0
	}

;Puts learned card c in a free slot (picture copied there, numbers into PlayerStats.txt). 1 if it did
LearnPlace(c)
	{
	slot := LearnSlotFor(c)
	if (slot = "")
		return 0
	setDir := A_WorkingDir (c.dir = "" ? "" : "\" c.dir)
	src := setDir "\learned\" c.id
	dest := setDir "\" slot
	SplitPath, dest,, destDir
	FileCreateDir, %destDir%
	;(what was there - only an old placeholder, or the slot would have counted as taken - is kept in backups\)
	if (FileExist(dest ".png"))
		FileCopy, %dest%.png, % A_WorkingDir "\backups\" StrReplace(slot, "\", "_") " (" (c.dir = "" ? "main" : c.dir) ", before learned card " c.id ").png", 1
	FileCopy, %src%.png, %dest%.png, 1
	if (ErrorLevel)
		{
		DebugLog("  couldn't copy learned card " c.id " to " dest ".png")
		return 0
		}
	FileCopy, %src%.raw.png, %dest%.raw.png, 1
	;(pictures made from what was there before)
	Loop, Files, % A_WorkingDir "\generated\ui*", D
		FileDelete, % A_LoopFileFullPath "\" slot ".bmp"
	LearnFreeCache := {}
	c.slot := slot
	LearnStats(c)
	return 1
	}

;The free slot for learned card c ("" none): see the top of this file
LearnSlotFor(c)
	{
	sch := c.sch
	if (c.type = "damage" || c.type = "aoe")
		{
		if (c.pips = "")
			return ""
		if (c.pips = 0)
			return LearnFree(sch "\wand") ? sch "\wand" : ""
		;(only where it keeps hit1-3 weakest to strongest - the battle casts hit3 first, then hit2, hit1 -
		;else it's kept out of use rather than cast before a stronger hit)
		val := (c.value != "") ? c.value + 0 : 0
		strongest := 0
		Loop, 4
			if (!LearnFree(sch "\hit" A_Index))
				strongest := Max(strongest, Stat(sch ".hit" A_Index))
		Loop, 3
			{
			n := A_Index
			if (!LearnFree(sch "\hit" n))
				continue
			inOrder := true
			Loop, 4
				{
				if (A_Index = n || LearnFree(sch "\hit" A_Index))
					continue
				v := Stat(sch ".hit" A_Index)
				if ((A_Index < n && v > val) || (A_Index > n && v < val))
					inOrder := false
				}
			if (inOrder)
				return sch "\hit" n
			}
		if (val > strongest && LearnFree(sch "\hit4"))
			return sch "\hit4"
		return ""
		}
	if (c.type = "heal")
		{
		if (c.pips = "")
			return ""
		Loop, 2
			if (LearnFree(sch "\heal" A_Index))
				return sch "\heal" A_Index
		return ""
		}
	if (c.type = "ward")
		return LearnFree("resources\tower") ? "resources\tower" : ""
	return ""
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

;Learned card c's numbers into PlayerStats.txt
LearnStats(c)
	{
	slot := c.slot
	SplitPath, slot, name
	key := c.sch "." name, pairs := []
	if (InStr(name, "hit") = 1 || name = "wand")
		{
		;(damage not read: 0, so the kill check never counts on it - never the number of the card the slot
		;was meant for)
		pairs.Push([key, c.value != "" ? c.value : 0])
		if (name != "wand" && c.pips != "")
			pairs.Push([key "pips", c.pips])
		pairs.Push([key "target", c.target])
		}
	else if (InStr(name, "heal") = 1 && c.pips != "")
		pairs.Push([key "pips", c.pips])
	if (pairs.Length())
		StatsSet(pairs, "learned " SubStr(c.when, 1, 8) ": " c.text (c.guess ? " (pips guessed: brought down as it shows up in colour with fewer)" : "") " - picture " c.dir "\learned\" c.id ".card.png")
	}

;What learned card c is, for you
LearnDescribe(c)
	{
	pips := (c.pips = "") ? "pips unknown" : c.pips " pip" (c.pips = 1 ? "" : "s") (c.guess ? " (guessed)" : "")
	if (c.type = "damage")
		return "hits one enemy for " (c.value = "" ? "?" : c.value) ", " pips
	if (c.type = "aoe")
		return "hits all enemies for " (c.value = "" ? "?" : c.value) ", " pips
	if (c.type = "heal")
		return "heals " (c.value = "" ? "?" : c.value) ", " pips
	if (c.type = "ward")
		return "a shield (" c.text "), " pips
	return "type unknown (""" c.text """), " pips
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

;learned\cards.txt -> LearnedCards
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
		c := {id: f[1], sch: f[2], type: f[3], pips: f[4], guess: f[5] + 0, value: f[6], target: f[7] + 0, slot: f[8], scale: f[9], dir: f[10], when: f[11], text: f[12]}
		LearnedCards.Push(c)
		}
	}

;LearnedCards -> learned\cards.txt
LearnSave()
	{
	out := "; Cards AutoFarmer learned by itself (CardLearn.ahk), one per line:`r`n"
		. "; id|school it was learned for|type (damage = one enemy, aoe = all, heal, ward; blank = unknown)|pips|pips guessed (1)|number on the card|single target (1)|slot it's used as|UI scale|picture set|when|text read off it`r`n"
		. "; Pictures: <picture set>\learned\<id>.card.png (whole card) and .png (the picture cut from it).`r`n"
	for i, c in LearnedCards
		out .= c.id "|" c.sch "|" c.type "|" c.pips "|" c.guess "|" c.value "|" c.target "|" c.slot "|" c.scale "|" c.dir "|" c.when "|" c.text "`r`n"
	FileCreateDir, % A_WorkingDir "\learned"
	path := A_WorkingDir "\learned\cards.txt"
	FileDelete, %path%.tmp
	FileAppend, %out%, %path%.tmp
	FileMove, %path%.tmp, %path%, 1
	}

;Sets key:value lines in PlayerStats.txt (each replaced where it is, else added under the learned-cards
;heading) and reads the stats again
StatsSet(pairs, comment := "")
	{
	path := A_WorkingDir "\PlayerStats.txt"
	FileRead, text, %path%
	if (ErrorLevel || !InStr(text, ":"))
		{
		DebugLog("  couldn't read PlayerStats.txt - the learned card's numbers weren't written")
		return false
		}
	lines := StrSplit(StrReplace(text, "`r"), "`n")
	if (lines.Length() && lines[lines.Length()] = "")
		lines.Pop()
	heading := "; ---- Cards the bot learned by itself (CardLearn.ahk; learned\cards.txt lists them) ----"
	headAt := 0
	for i, ln in lines
		if (ln = heading)
			headAt := i
	if (!headAt)
		lines.Push(""), lines.Push(heading), headAt := lines.Length()
	for each, kv in pairs
		{
		found := false
		for i, ln in lines
			if (RegExMatch(ln, "i)^\s*\Q" kv[1] "\E\s*:"))
				{
				lines[i] := kv[1] ":" kv[2] (each = 1 && comment != "" ? "   `; " comment : ""), found := true
				break
				}
		if (!found)
			lines.Push(kv[1] ":" kv[2] (each = 1 && comment != "" ? "   `; " comment : ""))
		}
	out := ""
	for i, ln in lines
		out .= ln "`r`n"
	FileDelete, %path%.tmp
	FileAppend, %out%, %path%.tmp
	if (ErrorLevel)
		return false
	FileMove, %path%.tmp, %path%, 1
	LoadStats(true)
	return true
	}

;s with everything but letters, digits and -_.~ as %XX (for a request's query string)
LearnUri(s)
	{
	out := ""
	Loop, Parse, s
		out .= RegExMatch(A_LoopField, "[A-Za-z0-9_.~-]") ? A_LoopField : "%" Format("{:02X}", Ord(A_LoopField))
	return out
	}
