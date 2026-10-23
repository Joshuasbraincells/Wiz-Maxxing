; Kill calculator for AutoFarmer.ahk (AHK v1.1), #Included at the end of Autofarmer.ahk.
; Reads enemy health off the 2D Combat Display nameplates with Windows OCR (Ocr.ahk), predicts
; the minimum (no crit) damage of each hit in hand from PlayerStats.txt plus the boosts we've cast,
; and picks the cheapest hit that kills every enemy. Whenever something can't be trusted it claims
; no kill, so the normal battle code plays the round instead.
; Uses the super-globals declared at the top of #1:: in Autofarmer.ahk: Stats, EnemyHP, BossSlot,
; BossMax, HealthStatus, AppliedBlades, BossTraps, AuraRounds, EnchantedHits, PipsNow.

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
	;A value for one school's wizard first (e.g. myth.damage, myth.pierce for the Myth wizard - each
	;wizard has its own stats), when the battle is being fought as that school
	if (hitschool != "" && !InStr(key, ".") && Stats.HasKey(hitschool "." key))
		return Stats[hitschool "." key]
	return Stats.HasKey(key) ? Stats[key] : 0
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

;Remembers a blade/trap we cast, keyed by card so recasting the same card doesn't count twice
AddBoost(list, card, bonus)
	{
	list[card . (bonus ? "+" : "")] := Stat(card) + bonus
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
;blader's or healer's own blades went on the hitter: cast again after the hitter's hit, not its own
ConsumeBoosts()
	{
	AppliedBlades := {}
	BossTraps := {}
	PartyHits := (PartyHits ? PartyHits : 0) + 1, PartyHitR := (BlRound ? BlRound : 0) + 1
	if (Stat("reboost") == 1 && !PartySupport())
		ResetUsed()
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
	BossSlot := 0
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
		gl := HealthGlyphs(cx - b.h * 3, cy, cw + b.h * 6, ch)
		;(the plate's own box kept as it is - the boss click's matched against it below)
		gx := cx, gy := cy, gw := cw, gh := ch
		if (IsObject(gl) && gl.Length() >= 3)
			GlyphsBox(gl, (gl[1].y2 - gl[1].y1) // 2 + 2, gx, gy, gw, gh)
		p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", scale1, redLines, 1), gl)))
		p.votes.Push(ParseHealth(HealthDigits(OcrRect(gx, gy, gw, gh, "en", scale2, redLines, 1), gl)))
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
	return true
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
	t := RegExReplace(text, "(?<=[\dSsOoB])\s*[,.']\s*(?=[\dSsOoB])|\s+(?=/)|(?<=/)\s+")
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
	base := Stat(hitschool . "." . hitName)
	if (base <= 0)
		return 0
	;X-pip spells (pip cost 0) are stored as damage per pip: they spend all your pips (not the wand's card:
	;it costs nothing)
	if (hitName != "wand" && Stat(hitschool . "." . hitName . "pips") = 0)
		base *= (PipsNow > 0 ? PipsNow : 1)
	if (EnchantedHits[hitName])
		base += Stat("enchant" . EnchantedHits[hitName])
	else if (useEnchant && enchant >= 1)
		base += Stat("enchant" . enchant)
	dmg := base * DamageMultiplier(Stat("damage")) * BoostMult(AppliedBlades)
	if (AuraRounds > 0)
		dmg *= 1 + Stat("aura") / 100
	;Another player's hit on the boss uses up our traps without us seeing it
	if (toBoss && Stat("solotraps") == 1)
		dmg *= BoostMult(BossTraps)
	resist := Stat("enemyresist") - Stat("pierce")
	if (resist > 0)
		dmg *= 1 - resist / 100
	return Floor(dmg)
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
	for i, e in EnemyHP
		{
		if (HitDamage(hitName, useEnchant, i == BossSlot) < e.cur * margin)
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
		text .= (text = "" ? "" : ", ") . e.cur . "/" . e.max . (i == BossSlot ? " (boss)" : "")
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
				if (BossSlot)
					info .= " (boss " . HitDamage("hit" . A_Index, 0, 1) . ")"
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
		slot := A_Index - 1, purple := 0, blue := 0, yellow := 0, white := 0
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
				}
			}
		if (purple + blue + yellow >= 30 * area)
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

