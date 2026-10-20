;Pictures for any UI size (included by Autofarmer.ahk)
;
;The pictures are cut at a few UI sizes: the main set at UI scale 1 and the ui<scale> folders (see
;LoadPicSets). At any other size the bot makes its own set from them: it measures the UI scale from a
;battle round's Pass and Flee buttons (DetectUiScale), then resizes each picture, the first time it's
;needed, from the cut set nearest above that size (PicPath -> PicMake) into generated\ui<scale>\ as a
;.bmp. A made picture is never pixel-exact, so it's searched for with at least GenTol colour tolerance,
;and it's see-through magenta (*TransFF00FF) wherever the resizing isn't sure of the colour (PicOpt).
;Made pictures are made again when the picture they came from changes; deleting generated\ makes
;them all again.

global GenTol, GenRoot, PassFleeDist
;Made pictures that were enlarged (from a smaller cut set): searched with a little more tolerance
global PicEnlarged
;The pictures PicMake has looked up (set dir|rel -> file, "" none); emptied when pictures are added
global PicMade

;Called by LoadPicSets
PicScaleInit()
	{
	GenTol := 20, PicEnlarged := {}, PicMade := {}
	GenRoot := A_WorkingDir "\generated"
	;Distance between the middles of the Pass and Flee buttons at UI scale 1 (521 px at UI 1.144,
	;580 px at UI 1.265)
	PassFleeDist := 457
	}

;The main picture set plus every ui<scale> folder (e.g. ui1.265 = UI 1.265 times the main size),
;then the sets made before at other sizes (generated\ui<scale>, gen: 1)
LoadPicSets()
	{
	PicScaleInit()
	PicSets := [{dir: A_WorkingDir, scale: 1.0}]
	for each, root in [A_WorkingDir, GenRoot]
		{
		Loop, Files, %root%\ui*, D
			{
			sc := SubStr(A_LoopFileName, 3)
			if sc is number
				{
				if (sc >= 0.5 && sc <= 3)
					PicSets.Push({dir: A_LoopFileFullPath, scale: sc + 0, gen: (root = GenRoot)})
				}
			}
		}
	}

;Looks for the spellbook (out of battle) or the Pass button (a battle round) with each picture set,
;and switches to the first set that finds one. skipCurrent: only try the other sets. True if found
DetectPicSet(skipCurrent := false)
	{
	;(another set than the one in use: found twice, 3-20 s apart, before it's used - a made set's mostly see-through
	;pictures can match something else once)
	static cand := 0, candAt := 0
	for i, set in PicSets
		{
		if (skipCurrent && i = PicSet)
			continue
		for each, pic in ["roundfinish", "roundstart"]
			{
			file := set.dir "\resources\" pic (set.gen ? ".bmp" : ".png")
			if (!FileExist(file))
				continue
			ImageSearch, fx, fy, GameLeft, GameTop, GameLeft + GameW, GameTop + GameH, % (set.gen ? "*" GenTol " *TransFF00FF " : "*3 ") file
			if (ErrorLevel = 0)
				{
				if (skipCurrent && i != PicSet && !(cand = i && A_TickCount - candAt >= 2500 && A_TickCount - candAt <= 20000))
					{
					if (cand != i || A_TickCount - candAt > 20000)
						cand := i, candAt := A_TickCount
					return false
					}
				cand := 0
				if (i != PicSet || !skipCurrent)
					UsePicSet(i)
				return true
				}
			}
		}
	return false
	}

;ImageSearch options and file for picture rel (e.g. "resources\player.png"): "*<tol> <file>", or for a
;made picture at least GenTol and *TransFF00FF
PicOpt(rel, tol := 3)
	{
	return PicOptFile(PicPath(rel), tol)
	}

;The same for a picture file already looked up with PicPath. An enlarged made picture (the cut one was
;smaller) gets 4 more: enlarging can't add back the detail the game draws at the bigger size
PicOptFile(p, tol := 3)
	{
	if (SubStr(p, -3) = ".bmp")
		return "*" (Max(tol, GenTol) + (PicEnlarged.HasKey(p) ? 4 : 0)) " *TransFF00FF " p
	;(a cut picture can have see-through parts too, e.g. the round badges)
	return "*" tol " *TransFF00FF " p
	}

;The picture rel for the made set `set`: generated\ui<scale>\<rel as .bmp>, made now if it isn't there
;yet or the picture it's made from has changed since. "" if no cut set has rel (or it couldn't be made)
PicMake(rel, set)
	{
	key := set.dir "|" rel
	if (PicMade.HasKey(key))
		return PicMade[key]
	dest := set.dir "\" RegExReplace(rel, "i)\.png$", ".bmp")
	srcs := PicMasters(rel, set.scale)
	if (!srcs.Length())
		return PicMade[key] := ""
	if (srcs[1].scale < set.scale * 0.97)
		PicEnlarged[dest] := 1
	;(cut at nearly this size - under 1% off: that picture as it is; resizing a mostly see-through one
	;that little only loses pixels)
	if (Abs(set.scale / srcs[1].scale - 1) < 0.01)
		return PicMade[key] := srcs[1].file
	if (FileExist(dest))
		{
		;(made before: kept unless a picture it could come from has changed since)
		FileGetTime, destTime, %dest%
		newer := false
		for each, src in srcs
			{
			FileGetTime, srcTime, % src.file
			if (srcTime > destTime)
				newer := true
			}
		if (!newer)
			return PicMade[key] := dest
		}
	SplitPath, dest,, destDir
	FileCreateDir, %destDir%
	;From the best one; a picture that's mostly see-through can come out too thin to use, then the next
	for each, src in srcs
		{
		madeFrom := A_TickCount
		kept := PicResize(src.resize, dest, set.scale / src.scale)
		DebugLog("  made " rel " for UI size " Round(set.scale, 3) " from the one cut at " Round(src.scale, 3) " (" (kept ? kept "% of it kept" : "too little left to use") ", " A_TickCount - madeFrom " ms)")
		if (kept)
			return PicMade[key] := dest
		}
	FileDelete, %dest%
	return PicMade[key] := ""
	}

;The cut pictures to make rel from for UI scale `scale`, best first: [{file, scale}, ...]. Best is the
;cut set with the smallest scale at or above it (shrinking keeps the detail), then the bigger ones,
;then the smaller ones biggest first
PicMasters(rel, scale)
	{
	up := [], down := []
	for i, set in PicSets
		{
		if (set.gen || !FileExist(set.dir "\" rel))
			continue
		isUp := (set.scale >= scale * 0.97), list := isUp ? up : down, at := 1
		while (at <= list.Length() && (isUp ? list[at].scale < set.scale : list[at].scale > set.scale))
			at++
		;(a cut card is mostly see-through - the parts that change between copies - which leaves too little
		;once resized; a solid copy saved next to it as <name>.raw.png is resized instead)
		raw := set.dir "\" RegExReplace(rel, "i)\.png$", ".raw.png")
		list.InsertAt(at, {file: set.dir "\" rel, scale: set.scale, resize: FileExist(raw) ? raw : set.dir "\" rel})
		}
	for each, m in down
		up.Push(m)
	return up
	}

;Resizes picture src by ratio into dest (a 24-bit BMP). Each pixel is the average of the solid (not
;see-through magenta) src pixels it covers, worked out for phases x phases sub-pixel positions of the
;picture; it's kept only if at least 40% of what it covers is solid and all positions agree within 10
;- so it doesn't matter where exactly the game lands the picture. The rest is magenta. Returns the %
;of pixels kept (at least 1), 0 if it failed or too little was left to tell the picture apart
PicResize(src, dest, ratio, phases := 4)
	{
	if (!PicRead(src, pix, w, h))
		return 0
	tw := Floor(w * ratio) - 1, th := Floor(h * ratio) - 1
	if (tw < 4 || th < 4)
		return 0
	;(a tiny patch, e.g. the 8x8 placeholders cut at UI 1, matches almost anything once resized: the
	;next cut set's picture is used instead)
	if (w < 12 || h < 12)
		return 0
	;src colours and see-through pixels, flat (index y * w + x)
	SrcR := [], SrcG := [], SrcB := [], SrcK := []
	Loop, % w * h
		{
		i := A_Index - 1
		c := NumGet(pix, i * 4, "UInt")
		SrcR[i] := (c >> 16) & 0xFF, SrcG[i] := (c >> 8) & 0xFF, SrcB[i] := c & 0xFF
		SrcK[i] := !(SrcR[i] = 255 && SrcG[i] = 0 && SrcB[i] = 255)
		}
	;across: every src row resized to tw, for each phase (colour sums and solid share, of the solid
	;pixels only)
	PhR := [], PhG := [], PhB := [], PhK := []
	Loop, %phases%
		{
		ph := A_Index, ar := [], ag := [], ab := [], ak := []
		Loop, %tw%
			{
			u := A_Index - 1
			span := PicSpan(u, (ph - 1) / phases, ratio, w)
			Loop, %h%
				{
				row := (A_Index - 1) * w, o := (A_Index - 1) * tw + u
				r := 0, g := 0, b := 0, k := 0
				for each, s in span
					{
					i := row + s[1]
					if (SrcK[i])
						wt := s[2], r += SrcR[i] * wt, g += SrcG[i] * wt, b += SrcB[i] * wt, k += wt
					}
				ar[o] := r, ag[o] := g, ab[o] := b, ak[o] := k
				}
			}
		PhR[ph] := ar, PhG[ph] := ag, PhB[ph] := ab, PhK[ph] := ak
		}
	;down: those resized to th, for each of the phases x phases; summed, and the spread of each colour
	n := tw * th, SR := [], SG := [], SB := [], Keep := [], LoR := [], LoG := [], LoB := [], HiR := [], HiG := [], HiB := []
	Loop, %n%
		{
		o := A_Index - 1
		SR[o] := 0, SG[o] := 0, SB[o] := 0, Keep[o] := 1
		LoR[o] := 999, LoG[o] := 999, LoB[o] := 999, HiR[o] := -1, HiG[o] := -1, HiB[o] := -1
		}
	Loop, %phases%
		{
		fy := (A_Index - 1) / phases
		Loop, %th%
			{
			v := A_Index - 1
			span := PicSpan(v, fy, ratio, h)
			Loop, %phases%
				{
				ar := PhR[A_Index], ag := PhG[A_Index], ab := PhB[A_Index], ak := PhK[A_Index]
				Loop, %tw%
					{
					u := A_Index - 1, o := v * tw + u
					if (!Keep[o])
						continue
					r := 0, g := 0, b := 0, k := 0
					for each, s in span
						{
						i := s[1] * tw + u, wt := s[2]
						r += ar[i] * wt, g += ag[i] * wt, b += ab[i] * wt, k += ak[i] * wt
						}
					if (k < 0.39999)
						{
						Keep[o] := 0
						continue
						}
					r /= k, g /= k, b /= k
					SR[o] += r, SG[o] += g, SB[o] += b
					if (r < LoR[o])
						LoR[o] := r
					if (r > HiR[o])
						HiR[o] := r
					if (g < LoG[o])
						LoG[o] := g
					if (g > HiG[o])
						HiG[o] := g
					if (b < LoB[o])
						LoB[o] := b
					if (b > HiB[o])
						HiB[o] := b
					}
				}
			}
		}
	;24-bit BMP, bottom row first; magenta where not kept
	;(enlarging: only the steadiest pixels - the game draws more detail at the bigger size than the
	;enlarged picture has)
	agree := ratio > 1.03 ? 6 : 10
	stride := (tw * 3 + 3) & ~3, size := stride * th, cnt := phases * phases, kept := 0
	VarSetCapacity(bits, size, 0)
	Loop, %th%
		{
		v := A_Index - 1, line := (th - 1 - v) * stride
		Loop, %tw%
			{
			u := A_Index - 1, o := v * tw + u, at := line + u * 3
			if (Keep[o] && HiR[o] - LoR[o] <= agree && HiG[o] - LoG[o] <= agree && HiB[o] - LoB[o] <= agree)
				{
				kept++
				NumPut(Round(SB[o] / cnt), bits, at, "UChar"), NumPut(Round(SG[o] / cnt), bits, at + 1, "UChar"), NumPut(Round(SR[o] / cnt), bits, at + 2, "UChar")
				}
			else
				NumPut(255, bits, at, "UChar"), NumPut(0, bits, at + 1, "UChar"), NumPut(255, bits, at + 2, "UChar")
			}
		}
	;(a picture that's nearly all see-through would match anything)
	if (kept < 12)
		return 0
	bmp := FileOpen(dest, "w")
	if (!IsObject(bmp))
		return 0
	bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + size), bmp.WriteUInt(0), bmp.WriteUInt(54)
	bmp.WriteUInt(40), bmp.WriteInt(tw), bmp.WriteInt(th), bmp.WriteUShort(1), bmp.WriteUShort(24)
	bmp.WriteUInt(0), bmp.WriteUInt(size), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
	bmp.RawWrite(bits, size)
	bmp.Close()
	return Max(1, Round(100 * kept / n))
	}

;The src pixels (along one side) that pixel t of the resized picture covers at sub-pixel phase f:
;[[index, weight], ...], the weights adding up to 1
PicSpan(t, f, ratio, srcLen)
	{
	a := (t + f) / ratio, z := (t + 1 + f) / ratio, span := []
	i := Floor(a)
	while (i < z && i < srcLen)
		{
		part := Min(z, i + 1) - Max(a, i)
		if (part > 0.000001)
			span.Push([i, part * ratio])
		i++
		}
	return span
	}

;Reads a picture file (PNG, BMP...) into pix: 4 bytes a pixel (blue, green, red, alpha), rows top to
;bottom; w x h its size. True if it could
PicRead(file, ByRef pix, ByRef w, ByRef h)
	{
	static token := 0
	if (!token)
		{
		DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
		VarSetCapacity(si, A_PtrSize = 8 ? 24 : 16, 0), NumPut(1, si, 0, "UInt")
		DllCall("gdiplus\GdiplusStartup", "Ptr*", token, "Ptr", &si, "Ptr", 0)
		if (!token)
			return false
		}
	gbmp := 0
	if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", file, "Ptr*", gbmp) || !gbmp)
		return false
	DllCall("gdiplus\GdipGetImageWidth", "Ptr", gbmp, "UInt*", w)
	DllCall("gdiplus\GdipGetImageHeight", "Ptr", gbmp, "UInt*", h)
	VarSetCapacity(rect, 16, 0), NumPut(w, rect, 8, "Int"), NumPut(h, rect, 12, "Int")
	;BitmapData: Width, Height, Stride, PixelFormat, Scan0, Reserved; read only, 32 bpp ARGB
	VarSetCapacity(data, 16 + 2 * A_PtrSize, 0)
	ok := false
	if (!DllCall("gdiplus\GdipBitmapLockBits", "Ptr", gbmp, "Ptr", &rect, "UInt", 1, "Int", 0x26200A, "Ptr", &data))
		{
		stride := NumGet(data, 8, "Int"), scan := NumGet(data, 16, "Ptr")
		VarSetCapacity(pix, w * h * 4, 0)
		Loop, %h%
			DllCall("RtlMoveMemory", "Ptr", &pix + (A_Index - 1) * w * 4, "Ptr", scan + (A_Index - 1) * stride, "Ptr", w * 4)
		DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", gbmp, "Ptr", &data)
		ok := true
		}
	DllCall("gdiplus\GdipDisposeImage", "Ptr", gbmp)
	return ok
	}

;No picture set finds anything: maybe the UI is a size there are no pictures for. If a battle round
;is up, measures the UI scale from its Pass and Flee buttons (read by OCR; they sit either side of the
;middle of the screen), fine-tunes it by making the Pass button at sizes up to 2% either side of that
;and keeping the one that matches closest, and switches to the made set for that size (new or made
;before). True if it did
DetectUiScale()
	{
	;Cheap look first: Pass and Flee are pure yellow words left and right of the middle (clear of the
	;middle, where the yellow quest arrow is)
	top := GameTop + Round(GameH * 0.45), bottom := GameTop + Round(GameH * 0.8)
	PixelSearch, yx, yy, GameLeft + Round(GameW * 0.2), top, GameLeft + Round(GameW * 0.45), bottom, 0xFFFF00, 0, Fast RGB
	if (ErrorLevel)
		return false
	PixelSearch, yx, yy, GameLeft + Round(GameW * 0.55), top, GameLeft + Round(GameW * 0.8), bottom, 0xFFFF00, 0, Fast RGB
	if (ErrorLevel)
		return false
	OcrRect(GameLeft + GameW // 8, GameTop + Round(GameH * 0.4), GameW * 3 // 4, Round(GameH * 0.45), "en", GameH < 1000 ? 2 : 1, lines)
	if (ErrorLevel || !IsObject(lines))
		return false
	pass := "", flee := "", looksLike := Func("RcLooksLike")
	if (!IsObject(looksLike))
		return false
	for i, line in lines
		for j, word in line.words
			{
			t := RegExReplace(word.text, "[^A-Za-z0-9|]")
			if (!IsObject(pass) && looksLike.Call(t, "PASS"))
				pass := word
			else if (!IsObject(flee) && looksLike.Call(t, "FLEE"))
				flee := word
			}
	if (!IsObject(pass) || !IsObject(flee))
		return false
	passX := pass.x + pass.w / 2, passY := pass.y + pass.h / 2, fleeX := flee.x + flee.w / 2
	if (Abs(passY - (flee.y + flee.h / 2)) > GameH * 0.02 || Abs((passX + fleeX) / 2 - ScreenX) > GameW * 0.03)
		return false
	guess := (fleeX - passX) / PassFleeDist
	if (guess < 0.5 || guess > 3)
		return false
	;Fine-tune: the Pass button made at sizes from 3% under the guess to 3% over, 1% apart, looked for
	;around where OCR saw it. It matches over a range of sizes (a little off still fits); the middle of
	;that range is the size (more tolerance only if it matches at none)
	srcs := PicMasters("resources\roundstart.png", guess)
	if (!srcs.Length())
		return false
	src := srcs[1].file, srcScale := srcs[1].scale
	tmp := A_Temp "\Wizard101 bot pass.bmp"
	tuneFrom := A_TickCount, fits := {}
	Loop, 7
		{
		step := A_Index - 4
		if (!PicResize(src, tmp, guess * (1 + step * 0.01) / srcScale))
			continue
		sc := guess * (1 + step * 0.01)
		for each, tol in [14, 20]
			{
			ImageSearch, sx, sy, passX - 110 * sc, passY - 45 * sc, passX + 110 * sc, passY + 45 * sc, *%tol% *TransFF00FF %tmp%
			if (ErrorLevel = 0)
				{
				fits[step] := tol
				break
				}
			}
		}
	FileDelete, %tmp%
	best := "", fitList := ""
	for each, tol in [14, 20]
		{
		lo := "", hi := ""
		for step, fitTol in fits
			if (fitTol <= tol)
				lo := (lo = "" || step < lo) ? step : lo, hi := (hi = "" || step > hi) ? step : hi
		if (lo != "")
			{
			best := guess * (1 + (lo + hi) / 2 * 0.01)
			break
			}
		}
	for step, fitTol in fits
		fitList .= (fitList = "" ? "" : ", ") (step > 0 ? "+" : "") step "%: *" fitTol
	if (best = "")
		{
		DebugLog("UI size: Pass and Flee are " Round(fleeX - passX) " px apart (UI scale about " Round(guess, 3) "), but the Pass button made at that size doesn't match")
		return false
		}
	;(a set within 1.5% of it already: that one - the Pass button matches a range of sizes that wide)
	sc := Round(best, 3), found := PicSetFor(sc, 0.015)
	;...but only if its own Pass button matches the one on screen now (else it would detect again and
	;again, never playing the round): otherwise a set at exactly this size
	if (PicSets[found].scale != sc)
		{
		other := PicSets[found]
		p := other.gen ? PicMake("resources\roundstart.png", other) : other.dir "\resources\roundstart.png"
		ImageSearch, sx, sy, passX - 110 * sc, passY - 45 * sc, passX + 110 * sc, passY + 45 * sc, % (other.gen ? "*" GenTol " *TransFF00FF " : "*3 ") p
		if (ErrorLevel != 0)
			found := PicSetFor(sc, 0)
		}
	DebugLog("UI size: Pass and Flee are " Round(fleeX - passX) " px apart (UI scale about " Round(guess, 3) "); the Pass button made at that size and a bit off matches at " fitList " - UI scale " sc " (" A_TickCount - tuneFrom " ms)")
	UsePicSet(found)
	;made now, so the round start and the spellbook are known from here on
	PicPath("resources\roundstart.png"), PicPath("resources\roundfinish.png")
	return true
	}

;No picture set finds the spellbook icon (out of battle, at a UI size never seen): finds the size from
;the icon. It's small and plain, so it matches over a range of sizes: every size from 0.6 to 2.2 (2%
;apart) is tried, the run of sizes that match is looked at again 0.5% apart with less colour
;tolerance, and the middle of what still matches is the size. Takes about 10 s. Less exact than
;DetectUiScale (the Pass button in a battle). Returns the UI scale, 0 if not found
PicScaleFromBook()
	{
	x1 := GameLeft + GameW * 3 // 5, y1 := GameTop + GameH * 3 // 5, x2 := GameLeft + GameW, y2 := GameTop + GameH
	tmp := A_Temp "\Wizard101 bot book.bmp"
	;Every size, smallest first; the longest run of sizes in a row that match
	sizes := [], sc := 0.6
	while (sc <= 2.2)
		sizes.Push(sc), sc *= 1.02
	bestLo := 0, bestHi := -1, runLo := 0
	for i, sc in sizes
		{
		if (PicScaleTry("resources\roundfinish.png", sc, tmp, x1, y1, x2, y2, 20))
			{
			if (!runLo)
				runLo := i
			if (i - runLo > bestHi - bestLo)
				bestLo := runLo, bestHi := i
			}
		else
			runLo := 0
		}
	if (!bestLo)
		{
		FileDelete, %tmp%
		return 0
		}
	;That run (and a step either side) again, 0.5% apart: the middle of what matches with the least
	;tolerance that matches anything there
	from := sizes[bestLo] / 1.02, to := sizes[bestHi] * 1.02, fine := []
	sc := from
	while (sc <= to)
		fine.Push(sc), sc *= 1.005
	for each, tol in [8, 12, 16, 20]
		{
		lo := 0, hi := 0
		for i, sc in fine
			if (PicScaleTry("resources\roundfinish.png", sc, tmp, x1, y1, x2, y2, tol))
				lo := lo ? lo : sc, hi := sc
		if (lo)
			break
		}
	FileDelete, %tmp%
	return lo ? Round(Sqrt(lo * hi), 3) : Round(Sqrt(sizes[bestLo] * sizes[bestHi]), 3)
	}

;Makes picture rel at UI scale sc into tmp and looks for it in the rectangle. True if it's there
PicScaleTry(rel, sc, tmp, x1, y1, x2, y2, tol)
	{
	srcs := PicMasters(rel, sc)
	if (!srcs.Length() || !PicResize(srcs[1].file, tmp, sc / srcs[1].scale))
		return false
	ImageSearch, fx, fy, x1, y1, x2, y2, *%tol% *TransFF00FF %tmp%
	return (ErrorLevel = 0)
	}

;The set for UI scale sc: the nearest cut or made one there already is within the share `within` of
;it, else a new made one (generated\ui<sc>). Returns its index in PicSets
PicSetFor(sc, within := 0.005)
	{
	near := 0
	for i, set in PicSets
		if (Abs(set.scale - sc) <= sc * within && (!near || Abs(set.scale - sc) < Abs(PicSets[near].scale - sc)))
			near := i
	if (near)
		return near
	dir := GenRoot "\ui" Round(sc, 3)
	FileCreateDir, %dir%
	PicSets.Push({dir: dir, scale: Round(sc, 3) + 0, gen: 1})
	return PicSets.Length()
	}
