; ArrowReader.ahk - reads Wizard101's yellow quest arrow (direction and distance) off the screen.
; AHK v1.1, functions only, #Included by AutoQuester.ahk and AutoFarmer.ahk. Uses the super-globals
; GameLeft, GameTop, GameW, GameH (the game's client area in screen coordinates) and OcrRect() from
; ..\AutoFarmer\Ocr.ahk. Locals must not share a name with any AutoFarmer super-global (AHK names are
; case-insensitive): e.g. no "second", "digits", "half", "on".
;
; How it works:
;  - the arrow is drawn in the 3D world at the wizard's feet, normally just above the bottom centre
;    of the game. Its yellow top face is found at half resolution and the hole the distance number
;    leaves is filled in. In shadow the arrow is darker, so if the bright-yellow test matches poorly
;    a colour test (any arrow-yellow shade) with its own reference shapes is tried as well
;  - the arrow turns around a fixed point 6 px under the centre of the distance number, so that hole
;    gives the turning point even when the arrow is pushed up the screen (e.g. by a talk prompt)
;  - the centre of mass sits towards the tail, so the direction from the turning point gives a rough
;    heading (never more than ~40 degrees off)
;  - the exact heading comes from matching the shape against 16 reference shapes captured from the
;    game (resources\arrow_refs.txt / arrow_refs_hue.txt, one every 22.5 degrees), each tried at small
;    rotations, but only near the rough heading (pointing up and down have very similar outlines)
;  - the arrow and the rest of the bottom-of-screen UI grow and shrink with the window size, the
;    Windows display scaling and the game's UI Size setting (about 1.21 times at 1920x1200 with 125%
;    scaling). All sizes here are for a 1920x1080 window at UI Size Small, times ArrowScale().scale,
;    which ReadArrow works out from the size of the arrow itself whenever it matches poorly

#Include %A_LineFile%\..\..\AutoFarmer\Ocr.ahk

;Heading of the quest arrow: 0 = straight ahead, negative = to the left, positive = to the right
;(-180..180). Returns "" when no arrow is on screen. dist = the distance printed on it ("" if
;unreadable), score = how well the shape matched (0..1)
ReadArrow(ByRef dist := "", ByRef score := "")
	{
	dist := "", score := ""
	if (!IsObject(ArrowRefs(0)))
		return ""
	size := ArrowScale()
	res := ArrowFind(size.scale)
	;A poor match can mean the UI is drawn at another size than assumed (window size, display scaling,
	;UI Size setting): the arrow's own size says roughly how big, so read it again at that size. Done
	;until a size has matched well, then only when poor matches keep pointing at another size (a
	;shadow or a half-hidden arrow also matches poorly, and another size doesn't help those)
	if (IsObject(res) && res.score < 0.8 && res.est != "" && Abs(res.est / res.scale - 1) > 0.05)
		size.poor += 1
	else if (IsObject(res) && res.score >= 0.8)
		size.poor := 0
	if (IsObject(res) && (!size.sure || size.poor >= 3))
		res := ArrowFindSize(res), size.poor := 0
	;Keep the size it found. A size that has matched well is only swapped for a clearly good match
	if (IsObject(res) && res.score >= 0.8)
		{
		if (res.scale != size.scale && (!size.sure || res.score >= 0.85))
			size.scale := res.scale, size.sure := 0
		if (res.score >= 0.85 && res.scale = size.scale)
			size.sure := 1
		}
	if (!IsObject(res) || res.h = "")
		return ""
	score := res.score
	info := ArrowInfo()
	info.pvx := res.pvx, info.pvy := res.pvy, info.mode := res.mode, info.boxY := res.boxY, info.homeY := res.homeY, info.scale := res.scale
	;Distance printed on the arrow: always upright, in the same place relative to the turning point.
	;Windows OCR often misses a lone digit at normal size (e.g. "9" right next to an NPC), so try bigger
	s := res.scale
	for each, zoom in [1, 2, 3]
		{
		t := OcrRect(Round(res.pvx - 34.3 * s), Round(res.pvy - 26.7 * s), Round(100 * s), Round(40 * s), "en", zoom), ocrErr := ErrorLevel
		distText := RegExReplace(t, "\D")
		if (!ocrErr && StrLen(distText) >= 1 && StrLen(distText) <= 5)
			{
			dist := distText + 0
			break
			}
		}
	return res.h
	}

;UI size (see the top of this file): {scale, sure (a read matched well at that size), poor (poor
;matches in a row that point at another size)}. One object shared by every ReadArrow
ArrowScale()
	{
	static size := {scale: 1, sure: 0, poor: 0}
	return size
	}

;Sizes the arrow reader copes with: 0.7 to 1.8 times a 1920x1080 window at UI Size Small
ArrowClampScale(s)
	{
	s := Round(s, 2)
	return s < 0.7 ? 0.7 : s > 1.8 ? 1.8 : s
	}

;Reads the arrow again at the UI size res (a poor match) points at, up to 4 times: each read's size
;estimate is closer than the last, as the box gets closer to the arrow's size. A shape cut off by the
;edge of the box (the box too small for it) only gives a lower bound, so then it tries 15% bigger.
;With nothing new to go on and still a really poor match, it tries a couple of typical sizes.
;Returns the best match
ArrowFindSize(res)
	{
	best := res, last := res, tried := [res.scale], probes := [1.3, 0.85]
	Loop, 4
		{
		if (best.score >= 0.85)
			break
		next := ""
		if (IsObject(last) && last.est != "")
			next := ArrowClampScale(last.clipped ? (last.est > last.scale ? last.est : last.scale) * 1.15 : last.est)
		if (next != "" && ArrowTried(tried, next))
			next := ""
		while (next = "" && best.score < 0.75 && probes.Length())
			{
			p := probes.RemoveAt(1)
			if (!ArrowTried(tried, p))
				next := p
			}
		if (next = "")
			break
		tried.Push(next)
		last := ArrowFind(next)
		if (IsObject(last) && last.score > best.score)
			best := last
		}
	return best
	}

;True if size s is within 3% of one already in tried
ArrowTried(tried, s)
	{
	for each, t in tried
		if (Abs(s / t - 1) < 0.03)
			return true
	return false
	}

;Reads the arrow at UI size scale: in its usual box first, and higher up the screen if it isn't
;there (pushed up by a prompt, say). Returns {h, score, pvx, pvy, mode, boxY, homeY, scale, est} or ""
ArrowFind(scale)
	{
	bx := Round(GameLeft + GameW / 2 - 100 * scale), by := Round(GameTop + GameH - 220 * scale)
	res := ArrowAt(bx, by, scale)
	if (!IsObject(res) || res.score < 0.75)
		{
		ly := ArrowLocate(scale)
		if (ly != "" && Abs(ly - by) > 12 * scale)
			{
			moved := ArrowAt(bx, ly, scale)
			if (IsObject(moved) && (!IsObject(res) || moved.score > res.score))
				res := moved
			}
		}
	if (IsObject(res))
		res.homeY := by
	return res
	}

;Reads the arrow in the box at screen (bx, by), 220x135 times scale: the bright-yellow test first,
;the colour test (shadow) if that matches poorly. Returns {h, score, pvx, pvy, mode, boxY, scale, est} or ""
ArrowAt(bx, by, scale)
	{
	bw := Round(220 * scale)
	if (!ArrowCapture(bx, by, bw, Round(135 * scale), pix))
		return ""
	res := ArrowShape(pix, bx, by, 0, scale, bw)
	if (!IsObject(res) || res.score < 0.75)
		{
		shade := ArrowShape(pix, bx, by, 1, scale, bw)
		if (IsObject(shade) && (!IsObject(res) || shade.score > res.score))
			res := shade
		}
	;Wading in deep water: the arrow at the wizard's feet is under the surface, a dark olive
	if (!IsObject(res) || res.score < 0.75)
		{
		;(the loosest colour test, so only a close match counts: olive scenery mustn't pass for the arrow)
		wet := ArrowShape(pix, bx, by, 2, scale, bw)
		if (IsObject(wet) && wet.score >= 0.8 && (!IsObject(res) || wet.score > res.score))
			res := wet
		}
	return res
	}

;Arrow-yellow pixel? mode 0 = the bright top face in normal light, mode 1 = any arrow-yellow shade,
;mode 2 = under water: dark olive (measured 2026-10-16 at the Gumdrop Forest dock: the arrow about
;41,81,35 against the water's 11,60,36 - the arrow's red is at or above its blue, the water's well under)
ArrowYellow(c, mode)
	{
	r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
	if (mode = 0)
		return r > 200 && g > 180 && b < 110 && Abs(r - g) < 60
	if (mode = 2)
		return r >= 24 && r <= 150 && g >= 50 && r - b >= -4 && g - r >= 12 && g - b >= 25
	return r > 90 && g * 100 > 78 * r && g * 100 < 108 * r && b * 100 < 35 * r
	}

;Finds the arrow's shape in a captured box (bw pixels wide) and matches it. Sampled on a 110x67 grid
;(every 2nd pixel at scale 1), so the shape comes out the size of the reference shapes at any UI size.
;Returns {h, score, pvx, pvy, mode, boxY, scale, est} or "". est = the UI size the arrow's area points
;at (the area changes a little with the heading, so it's only a few percent accurate)
ArrowShape(ByRef pix, bx, by, mode, scale, bw)
	{
	static OFF := 70, GridW := 141, HoleDX := [0.25, 0.10, 0.10], HoleDY := [-5.95, -5.74, -5.74], TypicalN := [970, 1180, 1180]
	refs := ArrowRefs(mode)
	if (!IsObject(refs))
		return ""
	w2 := 110, h2 := 67, cells := w2 * h2, step := 2 * scale

	;Arrow-yellow pixels on the grid
	colAt := []
	Loop, % w2
		colAt.Push(Round((A_Index - 1) * step) * 4)
	VarSetCapacity(mask, cells, 0)
	Loop, % h2
		{
		j := A_Index - 1, row := Round(j * step) * bw * 4
		Loop, % w2
			{
			if (ArrowYellow(NumGet(pix, row + colAt[A_Index], "UInt"), mode))
				NumPut(1, mask, j * w2 + A_Index - 1, "UChar")
			}
		}

	;Largest 4-connected yellow blob is the arrow (the quest text under it is thin, separate glyphs)
	VarSetCapacity(lab, cells * 2, 0), VarSetCapacity(stack, cells * 4, 0)
	cur := 0, best := 0, bestN := 0
	Loop, % cells
		{
		p := A_Index - 1
		if (!NumGet(mask, p, "UChar") || NumGet(lab, p * 2, "UShort"))
			continue
		cur++, n := 0
		NumPut(cur, lab, p * 2, "UShort"), NumPut(p, stack, 0, "UInt"), sp := 1
		while (sp)
			{
			sp--, q := NumGet(stack, sp * 4, "UInt"), n++
			qx := Mod(q, w2), qy := q // w2
			Loop, 4
				{
				nb := ArrowNeighbour(A_Index, q, qx, qy, w2, h2)
				if (nb >= 0 && NumGet(mask, nb, "UChar") && !NumGet(lab, nb * 2, "UShort"))
					{
					NumPut(cur, lab, nb * 2, "UShort"), NumPut(nb, stack, sp * 4, "UInt"), sp++
					}
				}
			}
		if (n > bestN)
			best := cur, bestN := n
		}
	if (bestN < 400)
		return ""
	;Far too big for an arrow at this size: maybe the UI is bigger than assumed, so say how much
	if (bestN > 2600)
		return {h: "", score: 0, pvx: "", pvy: "", mode: mode, boxY: by, scale: scale, est: scale * Sqrt(bestN / TypicalN[mode + 1])}

	;Fill the hole the distance number leaves: background reachable from the border stays background
	VarSetCapacity(outside, cells, 0), sp := 0
	Loop, % cells
		{
		p := A_Index - 1, px := Mod(p, w2), py := p // w2
		if (px = 0 || py = 0 || px = w2 - 1 || py = h2 - 1) && (NumGet(lab, p * 2, "UShort") != best)
			{
			NumPut(1, outside, p, "UChar"), NumPut(p, stack, sp * 4, "UInt"), sp++
			}
		}
	while (sp)
		{
		sp--, q := NumGet(stack, sp * 4, "UInt")
		qx := Mod(q, w2), qy := q // w2
		Loop, 4
			{
			nb := ArrowNeighbour(A_Index, q, qx, qy, w2, h2)
			if (nb >= 0 && !NumGet(outside, nb, "UChar") && NumGet(lab, nb * 2, "UShort") != best)
				{
				NumPut(1, outside, nb, "UChar"), NumPut(nb, stack, sp * 4, "UInt"), sp++
				}
			}
		}
	n := 0, sx := 0, sy := 0, holeN := 0, hsx := 0, hsy := 0, edge := 0
	Loop, % cells
		{
		p := A_Index - 1
		if (NumGet(outside, p, "UChar"))
			continue
		px := Mod(p, w2), py := p // w2
		n++, sx += px, sy += py
		if (px = 0 || py = 0 || px = w2 - 1 || py = h2 - 1)
			edge++
		if (NumGet(lab, p * 2, "UShort") != best)
			holeN++, hsx += px, hsy += py
		}
	cx := sx / n, cy := sy / n

	;The shape relative to its centre, as a grid
	VarSetCapacity(obs, GridW * GridW, 0), nObs := 0
	Loop, % cells
		{
		p := A_Index - 1
		if (NumGet(outside, p, "UChar"))
			continue
		dx := Round(Mod(p, w2) - cx), dy := Round(p // w2 - cy)
		if (Abs(dx) > OFF || Abs(dy) > OFF)
			continue
		idx := (dy + OFF) * GridW + dx + OFF
		if (!NumGet(obs, idx, "UChar"))
			NumPut(1, obs, idx, "UChar"), nObs++
		}

	;Turning point: just under the distance number's hole. Without a believable hole, where the
	;arrow's turning point sits in its usual box
	fx := bx + step * cx, fy := by + step * cy
	pvx := bx + 99.3 * scale, pvy := by + 81.7 * scale
	if (holeN >= 4 && holeN <= 200)
		{
		hx := bx + step * hsx / holeN - HoleDX[mode + 1] * scale, hy := by + step * hsy / holeN - HoleDY[mode + 1] * scale
		if (Abs(hx - fx) < 30 * scale && Abs(hy - fy) < 30 * scale)
			pvx := hx, pvy := hy
		}
	;Rough heading: from the turning point to the centre of mass points at the tail
	rough := ArrowWrap(ArrowAtan2(fx - pvx, -(fy - pvy)) * 57.29577951 + 180)
	info := ArrowInfo()
	info.blob := bestN, info.filled := n, info.holes := holeN, info.cx := cx, info.cy := cy, info.nObs := nObs, info.rough := rough

	;Exact heading: the two best references near the rough heading, each tried at small rotations
	first := 0, firstIoU := -1, runnerUp := 0, runnerUpIoU := -1
	for i, ref in refs
		{
		if (Abs(ArrowWrap(ref.h - rough)) > 82.5)
			continue
		iou := ArrowIoU(ref.v[6], obs, nObs)
		if (iou > firstIoU)
			runnerUp := first, runnerUpIoU := firstIoU, first := i, firstIoU := iou
		else if (iou > runnerUpIoU)
			runnerUp := i, runnerUpIoU := iou
		}
	bestIoU := -1, bestH := rough
	for each, i in [first, runnerUp]
		{
		if (!i)
			continue
		ref := refs[i]
		Loop, 11
			{
			h := ref.h - 15 + 2.5 * A_Index
			if (Abs(ArrowWrap(h - rough)) > 70)
				continue
			iou := ArrowIoU(ref.v[A_Index], obs, nObs)
			if (iou > bestIoU)
				bestIoU := iou, bestH := h
			}
		}
	;The UI size the arrow's area points at, going by the best reference near the rough heading
	est := first ? scale * Sqrt(nObs / refs[first].v[6].n) : ""
	return {h: ArrowWrap(bestH), score: (bestIoU < 0 ? 0 : bestIoU), pvx: pvx, pvy: pvy, mode: mode, boxY: by, scale: scale, est: est, clipped: (edge >= 3)}
	}

;Screen y of an arrow box (135 px tall at scale 1) around the densest arrow-yellow area between 560
;and 60 px (times scale) above the bottom of the game, or "" if there's nothing arrow-sized there.
;Sampled every 4th pixel. The box is placed like the usual one: the arrow's middle about 80 px below its top
ArrowLocate(scale)
	{
	lx := Round(GameLeft + GameW / 2 - 110 * scale), ly := Round(GameTop + GameH - 560 * scale)
	lw := Round(220 * scale), lh := Round(500 * scale)
	if (!ArrowCapture(lx, ly, lw, lh, pix))
		return ""
	rows := lh // 4, cols := lw // 4, rowCount := []
	Loop, % rows
		{
		j := A_Index - 1, row := j * 4 * lw * 4, cnt := 0
		Loop, % cols
			cnt += ArrowYellow(NumGet(pix, row + (A_Index - 1) * 16, "UInt"), 1)
		rowCount.Push(cnt)
		}
	win := Round(34 * scale), sum := 0, bestSum := 0, bestTop := 0
	Loop, % rows
		{
		sum += rowCount[A_Index]
		if (A_Index > win)
			sum -= rowCount[A_Index - win]
		if (A_Index >= win && sum > bestSum)
			bestSum := sum, bestTop := A_Index - win
		}
	if (bestSum < 60 * scale * scale)
		return ""
	;Middle of the yellow in that window, so the box doesn't cut the arrow off
	wsum := 0
	Loop, % win
		wsum += rowCount[bestTop + A_Index] * (bestTop + A_Index - 1)
	return Round(ly + (wsum / bestSum) * 4 - 80 * scale)
	}

;Reference shapes for mode 0 (arrow_refs.txt) or modes 1 and 2 (arrow_refs_hue.txt), each pre-rotated by
;-12.5..12.5 degrees (11 steps of 2.5, index 6 = 0). Loaded once; "" if the file is missing
;The AutoQuester folder (resources\ is in it). A compiled script has no .ahk files to go by, so then:
;next to the exe (AutoQuester.exe), else ..\AutoQuester (AutoFarmer.exe in AutoFarmer\)
AqDir()
	{
	static dir := ""
	if (dir != "")
		return dir
	if (!A_IsCompiled)
		SplitPath, A_LineFile,, dir
	else if (FileExist(A_ScriptDir "\resources\arrow_refs.txt"))
		dir := A_ScriptDir
	else
		dir := A_ScriptDir "\..\AutoQuester"
	return dir
	}

ArrowRefs(mode := 0)
	{
	static cache := {}, OFF := 70, GridW := 141
	if (cache.HasKey(mode))
		return cache[mode]
	cache[mode] := ""
	dir := AqDir()
	FileRead, text, % dir "\resources\" (mode >= 1 ? "arrow_refs_hue.txt" : "arrow_refs.txt")
	if (ErrorLevel)
		return ""
	list := []
	Loop, Parse, text, `n, `r
		{
		line := Trim(A_LoopField)
		if (line = "" || SubStr(line, 1, 1) = ";")
			continue
		parts := StrSplit(line, "|")
		if (parts.Length() != 2)
			continue
		pts := [], ptsText := parts[2]
		Loop, Parse, ptsText, %A_Space%
			{
			xy := StrSplit(A_LoopField, ",")
			if (xy.Length() = 2)
				pts.Push([xy[1] + 0, xy[2] + 0])
			}
		ref := {h: parts[1] + 0, v: []}
		Loop, 11
			{
			t := (-15 + 2.5 * A_Index) * 0.01745329252, c := Cos(t), s := Sin(t)
			VarSetCapacity(seen, GridW * GridW, 0)
			v := {n: 0}
			v.SetCapacity("idx", pts.Length() * 4)
			addr := v.GetAddress("idx"), cnt := 0
			for each, pt in pts
				{
				rx := Round(pt[1] * c - pt[2] * s), ry := Round(pt[1] * s + pt[2] * c)
				if (Abs(rx) > OFF || Abs(ry) > OFF)
					continue
				idx := (ry + OFF) * GridW + rx + OFF
				if (NumGet(seen, idx, "UChar"))
					continue
				NumPut(1, seen, idx, "UChar"), NumPut(idx, addr + 0, cnt * 4, "UInt"), cnt++
				}
			v.n := cnt
			ref.v.Push(v)
			}
		list.Push(ref)
		}
	if (list.Length())
		cache[mode] := list
	return cache[mode]
	}

;Details of the last ReadArrow (blob size, centre, rough heading, turning point...), for status and debugging
ArrowInfo()
	{
	static info := {}
	return info
	}

;Overlap (intersection over union) of one pre-rotated reference with the shape on screen
ArrowIoU(v, ByRef obs, nObs)
	{
	p := v.GetAddress("idx"), n := v.n, inter := 0
	Loop, % n
		inter += NumGet(obs, NumGet(p + 0, (A_Index - 1) * 4, "UInt"), "UChar")
	return inter / (nObs + n - inter)
	}

;k-th 4-neighbour of cell q (x qx, y qy) in a w x h grid, or -1 off the edge
ArrowNeighbour(k, q, qx, qy, w, h)
	{
	if (k = 1)
		return qx > 0 ? q - 1 : -1
	if (k = 2)
		return qx < w - 1 ? q + 1 : -1
	if (k = 3)
		return qy > 0 ? q - w : -1
	return qy < h - 1 ? q + w : -1
	}

;Copies a screen rectangle into pix as 32-bit BGRA pixels, top row first
ArrowCapture(x, y, w, h, ByRef pix)
	{
	VarSetCapacity(bi, 40, 0)
	NumPut(40, bi, 0, "UInt"), NumPut(w, bi, 4, "Int"), NumPut(-h, bi, 8, "Int")
	NumPut(1, bi, 12, "UShort"), NumPut(32, bi, 14, "UShort")
	sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
	bits := 0, ok := false
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", &bi, "UInt", 0, "Ptr*", bits, "Ptr", 0, "UInt", 0, "Ptr")
	if (hbm && bits)
		{
		obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
		ok := DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", sdc, "Int", x, "Int", y, "UInt", 0x00CC0020)
		DllCall("GdiFlush")
		VarSetCapacity(pix, w * h * 4, 0)
		DllCall("RtlMoveMemory", "Ptr", &pix, "Ptr", bits, "Ptr", w * h * 4)
		DllCall("SelectObject", "Ptr", mdc, "Ptr", obm, "Ptr")
		DllCall("DeleteObject", "Ptr", hbm)
		}
	DllCall("DeleteDC", "Ptr", mdc)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
	return ok
	}

ArrowAtan2(y, x)
	{
	return DllCall("msvcrt\atan2", "Double", y, "Double", x, "Cdecl Double")
	}

;Angle to -180..180
ArrowWrap(a)
	{
	a := Mod(a + 180, 360)
	if (a < 0)
		a += 360
	return a - 180
	}
