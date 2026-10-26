; StatsRead.ahk - reads the wizard's stats off the Spellbook's stats pages, at any UI size. AHK v1.1,
; functions only. Shared by StatsReader.ahk (run by hand) and Autofarmer.ahk (which reads them by
; itself when the school it just fought with has none yet - see StatsAuto there).
;
; Needs from the including script: the super-globals GameLeft, GameTop, GameW, GameH (the game's client
; area) and UiScale (1 = a 1920x1080 window at UI Size Small), PicOpt() (PicScale.ahk: a picture at the
; UI size in use), OcrRect() (Ocr.ahk), DebugLog(), and CoordMode Pixel and Mouse set to Screen.
;
; Where things are on the book was measured at UI scale 1 from the middle of the game area; at another
; size it's that times UiScale (the book is drawn round the middle). Numbers are read with digit
; pictures cut from the stats page (resources\stats\digits.txt, resized to the UI size), checked with
; Windows OCR of the dark ink at two sizes (see SrNumber); a value that can't be read for sure keeps
; its old value, so a wrong one is never written.

global SrDigitsRaw, SrDigits, SrDigitsAt, SrSchools
;The character that fought the last battle AutoFarmer saw, and its school (StatsNoteSchool)
global SrBattleChar, SrBattleSchool
;SrHandsOff: 1 = stop if the user touches the mouse or keyboard (AutoFarmer reading by itself);
;SrStop: why it stopped ("" = carrying on)
global SrHandsOff, SrStop

;Reads the stats of school's column (fire ice storm myth life death balance shadow). school "" = the
;column with clearly the highest damage (a wizard's gear boosts its own school most) - school is then
;set to it. got gets {damage, accuracy, critical, block, pierce}, "" for one that couldn't be read for
;sure. Opens the Spellbook (out of battle only), turns to the two stats pages and closes it again.
;Returns "" if it got that far, else why not
StatsRead(&school, &got)
	{
	got := {}, SrStop := ""
	SrSchools := ["fire", "ice", "storm", "myth", "life", "death", "balance", "shadow"]
	s := UiScale, cx := GameLeft + GameW // 2, cy := GameTop + GameH // 2
	if (school != "" && !SrColumn(school))
		return "unknown school `"" school "`""
	if (!SrLoadDigits())
		return "couldn't load resources\stats\digits.txt"
	;The Spellbook icon (bottom right) only shows out of battle
	ErrorLevel := !ImageSearch(&bookX, &bookY, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundfinish.png"))
	if (ErrorLevel)
		return "the Spellbook icon isn't showing (in a battle, or something over it?)"
	;C opens the book straight at the character page (the game's ToggleCharStats key). If it doesn't (or
	;the book was open on another page already), the Spellbook icon and then the character tab - the
	;top red tab on the right of the book
	tabNeeded := SrBookOpen(cx, cy)
	if (!tabNeeded && SrOk())
		{
		Send("{c}")
		Loop 8
			{
			Sleep(300)
			if (SrBookOpen(cx, cy))
				break
			}
		}
	if (!SrBookOpen(cx, cy))
		{
		DebugLog("  stats: C didn't open the book - clicking the Spellbook icon")
		SrClick(bookX + Round(12 * s), bookY + Round(12 * s))
		Loop 10
			{
			Sleep(300)
			if (SrBookOpen(cx, cy))
				break
			}
		if (SrStop != "")
			return "stopped: " SrStop
		if (!SrBookOpen(cx, cy))
			return "the Spellbook didn't open"
		tabNeeded := true
		}
	Sleep(500)
	if (tabNeeded)
		SrClick(cx + Round(450 * s), cy - Round(325 * s))
	Sleep(1000)
	;Stats page 1: Damage / Resistance / Accuracy (the book turns its pages slowly, so it retries)
	if (!SrCategory(cx + Round(20 * s), cy - Round(290 * s), "header_damage", "RESISTANCE", cx, cy))
		{
		if (SrStop != "")
			return "stopped: " SrStop
		SrSnap("page1_failed")
		SrCloseBook(cx, cy)
		return "couldn't find the Damage table on the stats page"
		}
	SrSnap("page1")
	if (school = "")
		{
		school := SrGuessSchool(cx, cy)
		if (school = "")
			{
			SrCloseBook(cx, cy)
			return "couldn't tell which school this wizard is (no school has clearly the highest damage)"
			}
		}
	col := SrColumn(school) - 1
	got.damage := SrNumber("damage", cx + Round((6 + 46 * col) * s), cy - Round(124 * s), Round(46 * s), Round(34 * s))
	got.accuracy := SrNumber("accuracy", cx + Round((6 + 46 * col) * s), cy + Round(292 * s), Round(46 * s), Round(33 * s))
	;Stats page 2: Critical / Block / Armor Piercing
	if (SrStop != "")
		return "stopped: " SrStop
	if (!SrCategory(cx + Round(75 * s), cy - Round(290 * s), "header_pierce", "PIERCING", cx, cy))
		{
		if (SrStop != "")
			return "stopped: " SrStop
		SrSnap("page2_failed")
		SrCloseBook(cx, cy)
		return "couldn't find the Armor Piercing table on the stats page"
		}
	SrSnap("page2")
	got.critical := SrNumber("critical", cx + Round((18 + 44 * col) * s), cy - Round(100 * s), Round(44 * s), Round(30 * s))
	got.block := SrNumber("block", cx + Round((18 + 44 * col) * s), cy + Round(25 * s), Round(44 * s), Round(30 * s))
	got.pierce := SrNumber("pierce", cx + Round((18 + 44 * col) * s), cy + Round(148 * s), Round(44 * s), Round(30 * s))
	;(the numbers are read: they count even if closing the book was cut short)
	SrCloseBook(cx, cy)
	return ""
	}

;False (and SrStop says why) once the game isn't the active window any more, a battle has started, or
;- when AutoFarmer reads by itself (SrHandsOff) - the user has touched the mouse or keyboard: then it
;stops clicking
SrOk()
	{
	if (SrStop != "")
		return false
	if (!WinActive("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe"))
		SrStop := "Wizard101 isn't the active window any more"
	else if (SrHandsOff && (IsFunc("UserIdle") ? UserIdle.Call() : A_TimeIdlePhysical) < 500)
		SrStop := "you used the mouse or keyboard"
	else
		{
		;A battle started (its Pass button is up): no more clicks or C
		ErrorLevel := !ImageSearch(&px, &py, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, PicOpt("resources\roundstart.png"))
		if (ErrorLevel = 0)
			SrStop := "a battle started"
		}
	return SrStop = ""
	}

;1-based column of a school on the stats pages, 0 if it isn't one
SrColumn(school)
	{
	for i, name in ["fire", "ice", "storm", "myth", "life", "death", "balance", "shadow"]
		if (name = school)
			return i
	return 0
	}

;Writes what was read into PlayerStats.txt as <school>.<stat> lines (the kill check uses
;<school>.damage and <school>.pierce for that school's wizard, before the plain damage / pierce lines),
;and <school>.charid = the character they're from (AutoFarmer reads them again when another character
;of that school fights). Other lines are left alone. Returns a summary for the user
StatsWrite(got, school, charID := "")
	{
	path := A_ScriptDir "\PlayerStats.txt"
	text := FileRead(path)
	if (ErrorLevel || !InStr(text, ":"))
		return "Couldn't read PlayerStats.txt, so nothing was changed."
	lines := StrSplit(StrReplace(text, "`r"), "`n")
	if (lines.Length && lines[lines.Length] = "")
		lines.Pop()
	heading := "; ---- Read from your stats pages by StatsReader (per school: <school>.damage and .pierce are what the kill check uses for that school's wizard) ----"
	headAt := 0
	for i, ln in lines
		if (InStr(ln, "; ---- Read from your stats page"))
			headAt := i, lines[i] := heading ;  V1toV2: Invalid Index errors?, try 'lines.Push(<val>)'
	if (!headAt)
		lines.Push(""), lines.Push(heading)
	summary := "", failed := ""
	for each, stat in ["damage", "pierce", "critical", "accuracy", "block"]
		{
		val := got[stat], key := school "." stat
		if (val = "")
			{
			failed .= "`n   " stat " (kept the old value)"
			continue
			}
		found := false
		for i, ln in lines
			if (RegExMatch(ln, "i)^\s*\Q" key "\E\s*:"))
				{
				lines[i] := key ":" val, found := true ;  V1toV2: Invalid Index errors?, try 'lines.Push(<val>)'
				break
				}
		if (!found)
			lines.Push(key ":" val)
		summary .= "`n   " stat ": " val
		}
	if (charID != "" && summary != "")
		{
		got.charid := charID, found := false
		for i, ln in lines
			if (RegExMatch(ln, "i)^\s*\Q" school ".charid\E\s*:"))
				{
				lines[i] := school ".charid:" charID, found := true ;  V1toV2: Invalid Index errors?, try 'lines.Push(<val>)'
				break
				}
		if (!found)
			lines.Push(school ".charid:" charID)
		}
	now := FormatTime(, "yyyy-MM-dd HH:mm")
	note := "; StatsReader last read your " school " stats on " now
	noteAt := 0, keepAt := 0
	for i, ln in lines
		{
		if (InStr(ln, "; StatsReader last read"))
			noteAt := i
		if (InStr(ln, "Keep these two lines first"))
			keepAt := i
		}
	if (noteAt)
		lines[noteAt] := note ;  V1toV2: Invalid Index errors?, try 'lines.Push(<val>)'
	else
		lines.InsertAt(keepAt ? keepAt + 1 : 3, note)
	out := ""
	for i, ln in lines
		out .= ln "`r`n"
	;A temporary copy first, so a failed write can't leave PlayerStats.txt empty
	Try FileDelete(path ".tmp")
	FileAppend(out, path ".tmp")
	if (ErrorLevel)
		return "Couldn't write PlayerStats.txt (is it open in another program?). Nothing was changed."
	Try {
		FileMove(path ".tmp", path, 1)
		ErrorLevel := 0
	} Catch as Err {
		ErrorLevel := Err.Extra
	}
	if (ErrorLevel)
		return "Couldn't replace PlayerStats.txt (is it open in another program?). Nothing was changed."
	return "Read the " school " wizard's stats into PlayerStats.txt:" (summary = "" ? "`n   (nothing)" : summary)
		. (failed = "" ? "" : "`n`nCouldn't read for sure:" failed)
	}

;---- Which wizard is logged in, and its school ----

;The logged-in character's id, from the game's log ("MSG_LoginComplete CharID:..."), "" if not found.
;Looked up again at most every 20 s
StatsCharID()
	{
	static charNow := "", readAt := 0
	if (readAt && A_TickCount - readAt < 20000)
		return charNow
	readAt := A_TickCount
	logPath := SrLogPath()
	text := FileRead(logPath)
	at := InStr(text, "MSG_LoginComplete CharID:", false, -1)
	charNow := (at && RegExMatch(SubStr(text, (at)<1 ? (at)-1 : (at), 80), "CharID:(\d+)", &m)) ? m[1] : ""
	return charNow
	}

SrLogPath()
	{
	exePath := WinGetProcessPath("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient.exe")
	if (exePath != "")
		{
		SplitPath(exePath, , &binDir)
		if (FileExist(binDir "\WizardClient.log"))
			return binDir "\WizardClient.log"
		}
	return "C:\ProgramData\KingsIsle Entertainment\Wizard101\Bin\WizardClient.log"
	}

;The school AutoFarmer saw this character fight with (resources\characters.txt), "" if never
StatsSchoolOf(charID)
	{
	if (charID = "")
		return ""
	Loop Read, A_ScriptDir "\resources\characters.txt"
		if (RegExMatch(A_LoopReadLine, "^(\d+)\|(\w+)", &m) && m[1] = charID)
			return m[2]
	return ""
	}

;Remembers the logged-in character's school (AutoFarmer calls it each round with the school of the
;hitter it found on the name plate): in resources\characters.txt, and which character fought this
;battle (SrBattleChar / SrBattleSchool)
StatsNoteSchool(school)
	{
	if (school = "")
		return
	id := StatsCharID()
	SrBattleChar := id, SrBattleSchool := school
	if (id = "" || StatsSchoolOf(id) = school)
		return
	path := A_ScriptDir "\resources\characters.txt", out := ""
	Loop Read, path
		if (!RegExMatch(A_LoopReadLine, "^" id "\|"))
			out .= A_LoopReadLine "`r`n"
	Try FileDelete(path)
	FileAppend((out = "" ? "; Wizard101 characters (CharID from the game's log) and the school AutoFarmer saw each fight with`r`n" : out) id "|" school "`r`n", path)
	DebugLog("  (character " id " is a " school " wizard - noted for StatsReader)")
	}

;---- Reading the book ----

SrClick(x, y)
	{
	if (!SrOk())
		return
	;(your mouse locked meanwhile, in AutoFarmer - Settings.ahk MouseLockOn; StatsReader has none)
	if (IsFunc("MouseLockOn"))
		MouseLockOn.Call("stats")
	MouseMove(x, y, 5)
	;(its clicks too, now the pointer's on the game - Settings.ahk MouseLockMoved)
	if (IsFunc("MouseLockMoved"))
		MouseLockMoved.Call()
	Sleep(120)
	Click()
	if (IsFunc("MouseLockOff"))
		MouseLockOff.Call("stats")
	Sleep(150)
	}

SrCloseBook(cx, cy)
	{
	;The red X tab at the bottom of the book's tabs, else C (it toggles the character page)
	Loop 2
		{
		SrClick(cx + Round(450 * UiScale), cy + Round(322 * UiScale))
		Sleep(600)
		if (!SrBookOpen(cx, cy))
			return
		}
	if (!SrOk())
		return
	DebugLog("  stats: the close tab didn't close the book - pressing C")
	Send("{c}")
	Sleep(600)
	if (SrBookOpen(cx, cy))
		DebugLog("  stats: the book is still open")
	}

;Is the Spellbook open? (its red X tab is showing)
SrBookOpen(cx, cy)
	{
	s := UiScale
	ErrorLevel := !ImageSearch(&x, &y, cx + Round(380 * s), cy + Round(250 * s), cx + Round(520 * s), cy + Round(400 * s), PicOpt("resources\stats\tab_close.png", 30))
	return (ErrorLevel = 0)
	}

;Clicks a stats category icon until its header shows on the right-hand page (up to 3 tries). The
;header is looked for as a picture (made at the UI size in use), and if that doesn't match, as a word
;read by OCR (big clear letters: "RESISTANCE" on page 1 - OCR garbles the M of DAMAGE - and
;"PIERCING" on page 2)
SrCategory(x, y, header, word, cx, cy)
	{
	s := UiScale, x1 := cx + Round(60 * s), y1 := cy - Round(260 * s), x2 := cx + Round(400 * s), y2 := cy + Round(140 * s)
	Loop 3
		{
		if (!SrOk())
			return false
		SrClick(x, y)
		Loop 6
			{
			Sleep(250)
			ErrorLevel := !ImageSearch(&hx, &hy, x1, y1, x2, y2, PicOpt("resources\stats\" header ".png", 30))
			if (ErrorLevel = 0)
				return true
			if (A_Index >= 3)
				{
				t := OcrRect(x1, y1, x2 - x1, y2 - y1)
				if (!ErrorLevel && InStr(t, word))
					{
					DebugLog("  stats: " header " found by its word '" word "' (not by its picture)")
					return true
					}
				}
			}
		}
	return false
	}

;The school whose damage (read with the digit pictures) is clearly the highest: 10 or more above
;the next, every column read. "" if none is
SrGuessSchool(cx, cy)
	{
	s := UiScale, best := "", bestVal := -1, runnerUp := -1, all := "", missed := 0
	for i, name in SrSchools
		{
		val := SrReadCell(cx + Round((6 + 46 * (i - 1)) * s), cy - Round(124 * s), Round(46 * s), Round(34 * s), &score)
		all .= " " name "=" (val = "" ? "?" : val)
		if (val = "" || score < 0.85)
			{
			missed += 1
			continue
			}
		val += 0
		if (val > bestVal)
			runnerUp := bestVal, bestVal := val, best := name
		else if (val > runnerUp)
			runnerUp := val
		}
	DebugLog("  stats: damage by school:" all)
	return (best != "" && !missed && bestVal - runnerUp >= 10) ? best : ""
	}

;One number cell. The digit pictures (resized to the UI size) read the numbers on this page reliably
;- every cell right at UI 1 and at 1.14 in tests - and a strong match (every digit's score 0.85 or
;more) is taken unless OCR, reading only the dark ink, reads a different number the same way at two
;sizes. A weaker match needs OCR to agree. A number with a digit there's no picture of (there's no 4
;yet) is taken from OCR when both sizes agree. "" unless sure
SrNumber(what, x, y, w, h)
	{
	pics := SrReadCell(x, y, w, h, &score, &marks)
	t := OcrRect(x, y, w, h, "en", 3, lines, 2)
	o3 := ErrorLevel ? "" : RegExReplace(t, "\D")
	t := OcrRect(x, y, w, h, "en", 4, lines, 2)
	o4 := ErrorLevel ? "" : RegExReplace(t, "\D")
	ocrSure := (o3 != "" && o3 = o4)
	val := ""
	if (pics != "" && (pics = o3 || pics = o4))
		val := pics
	else if (pics != "" && score >= 0.85 && !(ocrSure && o3 != pics))
		val := pics
	;(OCR alone: only with as many digits as there are separate marks of ink - a cell border read as
	;an extra 1 doesn't count)
	else if (pics = "" && ocrSure && StrLen(o3) = marks)
		val := o3
	DebugLog("  stats: " what " - digit pictures " (pics = "" ? "?" : pics " (score " Round(score, 2) ")") ", OCR " (o3 = "" ? "?" : o3) " / " (o4 = "" ? "?" : o4) " -> " (val = "" ? "not sure, not written" : val))
	return val
	}

;digits.txt: char|width|height|values (ink darkness 0-255, row by row), one line per sample. Kept as
;read (SrDigitsRaw); SrDigits is them resized to the UI size in use, ready for matching
SrLoadDigits()
	{
	if (!IsObject(SrDigitsRaw))
		{
		SrDigitsRaw := []
		Loop Read, A_ScriptDir "\resources\stats\digits.txt"
			{
			if (SubStr(A_LoopReadLine, 1, 1) = ";" || A_LoopReadLine = "")
				continue
			p := StrSplit(A_LoopReadLine, "|")
			SrDigitsRaw.Push({ch: p[1], w: p[2] + 0, h: p[3] + 0, v: StrSplit(p[4], ",")})
			}
		}
	if (!SrDigitsRaw.Length)
		return false
	if (IsObject(SrDigits) && SrDigitsAt = UiScale)
		return true
	SrDigits := [], SrDigitsAt := UiScale
	for i, d in SrDigitsRaw
		{
		tw := Round(d.w * UiScale), th := Round(d.h * UiScale)
		vals := SrResample(d.v, d.w, d.h, tw, th)
		n := tw * th, sum := 0
		Loop n
			sum += vals[A_Index]
		mean := sum / n, ss := 0
		Loop n
			{
			vals[A_Index] -= mean
			ss += vals[A_Index] ** 2
			}
		SrDigits.Push({ch: d.ch, w: tw, h: th, v: vals, norm: Sqrt(ss)})
		}
	return true
	}

;A grey picture (1-based, row by row) resized from w x h to tw x th, each pixel the average of what it covers
SrResample(vals, w, h, tw, th)
	{
	if (tw = w && th = h)
		return vals.Clone()
	out := [], rx := w / tw, ry := h / th
	Loop th
		{
		y0 := (A_Index - 1) * ry, y1 := A_Index * ry
		Loop tw
			{
			x0 := (A_Index - 1) * rx, x1 := A_Index * rx, sum := 0, area := 0
			j := Floor(y0)
			while (j < y1 && j < h)
				{
				wy := (y1 < j + 1 ? y1 : j + 1) - (y0 > j ? y0 : j)
				i := Floor(x0)
				while (i < x1 && i < w)
					{
					wx := (x1 < i + 1 ? x1 : i + 1) - (x0 > i ? x0 : i)
					sum += vals[j * w + i + 1] * wx * wy, area += wx * wy
					i++
					}
				j++
				}
			out.Push(area ? sum / area : 0)
			}
		}
	return out
	}

;Reads one number cell with the digit pictures. Returns the digits, or "" if it couldn't be read for
;sure; score = the weakest chosen digit's match (0..1), marks = how many separate marks of ink (runs of
;columns with ink) the digit band has
SrReadCell(x, y, w, h, &score := "", &marks := "")
	{
	score := 0, marks := 0
	g := SrInk(x, y, w, h)
	if (!IsObject(g))
		return ""
	;The digit band: the tallest run of rows with black ink in them
	bestLen := 0, run := 0, start := 0
	Loop h + 1
		{
		r := A_Index - 1, cnt := 0
		if (r < h)
			Loop w
				cnt += g.black[r * w + A_Index]
		if (r < h && cnt >= 2)
			{
			if (run = 0)
				start := r
			run++
			}
		else
			{
			if (run > bestLen)
				bestLen := run, b0 := start, b1 := r - 1
			run := 0
			}
		}
	if (bestLen < 8 * UiScale)
		return ""
	;Which columns have ink in the band (a digit starts next to one)
	inkCol := []
	Loop w
		{
		colX := A_Index - 1, ink := 0, r := b0 - 1
		while (++r <= b1)
			if (g.black[r * w + colX + 1])
				ink := 1
		inkCol[colX] := ink ;  V1toV2: Invalid Index errors?, try 'inkCol.Push(<val>)'
		if (ink && !(colX && inkCol[colX - 1]))
			marks += 1
		}
	;Sums of the ink (and of its square) over any window: integral images, (h + 1) x (w + 1)
	iw := w + 1, s1 := [], s2 := []
	Loop iw * (h + 1)
		s1[A_Index] := 0, s2[A_Index] := 0 ;  V1toV2: Invalid Index errors?, try 's1.Push(<val>)'
	Loop h
		{
		r := A_Index, rowSum := 0, rowSq := 0
		Loop w
			{
			v := g.gray[(r - 1) * w + A_Index], rowSum += v, rowSq += v * v
			s1[r * iw + A_Index + 1] := s1[(r - 1) * iw + A_Index + 1] + rowSum ;  V1toV2: Invalid Index errors?, try 's1.Push(<val>)'
			s2[r * iw + A_Index + 1] := s2[(r - 1) * iw + A_Index + 1] + rowSq ;  V1toV2: Invalid Index errors?, try 's2.Push(<val>)'
			}
		}
	;Slide every digit picture across the band and keep the good matches. The pictures are mean-free,
	;so the correlation is sum(ink x picture) / sqrt(spread of the window x spread of the picture)
	cands := [], up := Round(3 * UiScale)
	for i, d in SrDigits
		{
		n := d.w * d.h
		ty := b0 - up - 1
		while (++ty <= b0)
			{
			if (ty < 0 || ty + d.h > h)
				continue
			tx := -1
			while (++tx <= w - d.w)
				{
				if (!(inkCol[tx] || inkCol[tx + 1] || inkCol[tx + 2] || inkCol[tx + 3]))
					continue
				a := ty * iw + tx + 1, z := (ty + d.h) * iw + tx + 1
				sum := s1[z + d.w] - s1[a + d.w] - s1[z] + s1[a]
				sq := s2[z + d.w] - s2[a + d.w] - s2[z] + s2[a]
				spread := sq - sum * sum / n
				if (spread <= 0 || d.norm <= 0)
					continue
				dot := 0, k := 0
				Loop d.h
					{
					base := (ty + A_Index - 1) * w + tx
					Loop d.w
						dot += g.gray[base + A_Index] * d.v[++k]
					}
				ncc := dot / Sqrt(spread * d.norm ** 2)
				if (ncc >= 0.77)
					cands.Push({s: ncc, x: tx + 1, w: d.w - 2, ch: d.ch})
				}
			}
		}
	;Best matches first, no two overlapping (1 px allowed)
	chosen := []
	while (cands.Length)
		{
		bi := 1
		for i, c in cands
			if (c.s > cands[bi].s)
				bi := i
		c := cands.RemoveAt(bi), clash := false
		for j, k in chosen
			if !(c.x + c.w <= k.x + 1 || k.x + k.w <= c.x + 1)
				clash := true
		if (!clash)
			chosen.Push(c)
		}
	;Every column with ink in the band must belong to a recognised digit
	Loop w
		{
		colX := A_Index - 1
		if (!inkCol[colX])
			continue
		covered := false
		for j, k in chosen
			if (colX >= k.x - 1 && colX <= k.x + k.w)
				covered := true
		if (!covered)
			return ""
		}
	;Left to right
	text := "", used := {}, score := 1
	Loop chosen.Length
		{
		bi := 0
		for j, k in chosen
			if (!used[j] && (bi = 0 || k.x < chosen[bi].x))
				bi := j
		used[bi] := true, text .= chosen[bi].ch ;  V1toV2: Invalid Index errors?, try 'used.Push(<val>)'
		if (chosen[bi].s < score)
			score := chosen[bi].s
		}
	if (text = "")
		score := 0
	return text
	}

;Screen rectangle -> {gray: ink darkness 0-255 (1-based, row by row), black: 1 where near-black}
SrInk(x, y, w, h)
	{
	hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
	bi := Buffer(40, 0) ; V1toV2: if 'bi' is a UTF-16 string, use 'VarSetStrCapacity(&bi, 40)' and replace all instances of 'bi.Ptr' with 'StrPtr(bi)'
	NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
	NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", bi.Ptrts, "Ptr", 0, "UInt", 0, "Ptr")
	if (!hbm)
		{
		DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
		return ""
		}
	obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
	DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
	DllCall("GdiFlush")
	gray := [], blk := []
	Loop w * h
		{
		c := NumGet(bits + (A_Index - 1) * 4, "UInt")
		r := (c >> 16) & 0xFF, gr := (c >> 8) & 0xFF, b := c & 0xFF
		gray.Push(255 - (r + gr + b) / 3)
		mx := r > gr ? r : gr
		mx := mx > b ? mx : b
		blk.Push(mx < 60 ? 1 : 0)
		}
	DllCall("SelectObject", "Ptr", mdc, "Ptr", obm), DllCall("DeleteObject", "Ptr", hbm)
	DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
	return {gray: gray, black: blk}
	}

;A picture of the game area (BMP) in the Windows temp folder ("Wizard101 bot rounds\stats_<what>_<time>.bmp"),
;so a stats page that didn't read right can be looked at. Keeps the newest 8
SrSnap(what)
	{
	dir := A_Temp "\Wizard101 bot rounds"
	DirCreate(dir)
	files := ""
	Loop Files, dir "\stats_*.bmp"
		files .= A_LoopFileTimeModified "|" A_LoopFileName "`n"
	files := Sort(files)
	list := StrSplit(Trim(files, "`n"), "`n")
	while (list.Length >= 8)
		Try FileDelete(dir "\" StrSplit(list.RemoveAt(1), "|")[2])
	w := GameW, h := GameH
	hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
	bi := Buffer(40, 0) ; V1toV2: if 'bi' is a UTF-16 string, use 'VarSetStrCapacity(&bi, 40)' and replace all instances of 'bi.Ptr' with 'StrPtr(bi)'
	NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
	NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
	bits := 0
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi.Ptr, "UInt", 0, "Ptr*", bi.Ptrts, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", GameLeft, "Int", GameTop, "UInt", 0x00CC0020)
		DllCall("GdiFlush")
		stamp := FormatTime(, "yyyyMMdd_HHmmss")
		bmp := FileOpen(dir "\stats_" what "_" stamp ".bmp", "w")
		if (IsObject(bmp))
			{
			bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + w * h * 4), bmp.WriteUInt(0), bmp.WriteUInt(54)
			bmp.WriteUInt(40), bmp.WriteInt(w), bmp.WriteInt(-h), bmp.WriteUShort(1), bmp.WriteUShort(32)
			bmp.WriteUInt(0), bmp.WriteUInt(w * h * 4), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
			bmp.RawWrite(bits + 0, w * h * 4)
			bmp.Close()
			}
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm), DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc), DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
	}
