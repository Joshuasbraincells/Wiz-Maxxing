; ==============================================================================
;  OcrRect() - Windows built-in OCR (Windows.Media.Ocr WinRT API) for AutoHotkey v1.1
;  No external dependencies. 32-bit and 64-bit safe.
;
;  Based on malcev's "Optical character recognition (OCR) with UWP API" (AHK v1)
;    https://www.autohotkey.com/boards/viewtopic.php?t=72674
;  and the SoftwareBitmap / LockBuffer approach of Descolada's OCR library (AHK v2)
;    https://github.com/Descolada/OCR  (Lib/OCR.ahk, HBitmapToSoftwareBitmap)
;
;  OcrRect(x, y, w, h, lang := "en", scale := 1, ByRef lineRects := "", redOnly := 0)
;    x, y, w, h : SCREEN rectangle (same space as CoordMode Screen / ImageSearch;
;                 may be negative on a monitor left of / above the primary one)
;    lang       : BCP-47 tag, e.g. "en" or "en-US". "" = first OCR-capable
;                 language from the Windows user profile.
;    scale      : upscale factor applied before OCR (HALFTONE StretchBlt).
;                 Small game text usually reads better at 2-3 (test 1, 2 and 3).
;    lineRects  : (out) [{text, x, y, w, h, words}, ...] one per recognized line, SCREEN coordinates;
;                 words = [{text, x, y, w, h}, ...] each word's own box in that line.
;    redOnly    : 1 = OCR only the reddish pixels (as black on white), e.g. red health numbers.
;                 5 = only the bright green ones (an NPC's name under a quest marker).
;                 2 = OCR only the dark ink (as black on white), e.g. numbers on the Spellbook's parchment.
;                 3 = only the white pixels, e.g. a spell card's name (white letters, dark outline).
;                 4 = only the yellow pixels, e.g. a spell card's pip cost.
;                 Filters pixel by pixel in script code, so keep the rectangle small.
;  Returns the recognized lines joined by `n ("" when nothing was recognized).
;  On failure returns "" and ErrorLevel holds a message; ErrorLevel = 0 on success.
;  The WinRT factories and the OcrEngine (per language) are created once and cached.
;
;  Example:
;    txt := OcrRect(BossX - 60, BossY - 95, 120, 22, "en", 3)
;    if (ErrorLevel)
;        ToolTip, %ErrorLevel%
;    digits := RegExReplace(txt, "[^0-9]")   ; OCR may drop/alter "," and "/"
; ==============================================================================
OcrRect(x, y, w, h, lang := "en", scale := 1, ByRef lineRects := "", redOnly := 0)
{
    static Init := 0, OcrStatics := 0, LangFactory := 0, SbFactory := 0, MaxDim := 0
         , Engine := 0, EngineLang := "", Busy := 0, Pad := 8
         , IID_IOcrEngineStatics       := "{5BFFA85A-3384-3540-9940-699120D428A8}"
         , IID_ILanguageFactory        := "{9B0252AC-0C27-44F8-B792-9793FB66C63E}"
         , IID_ISoftwareBitmapFactory  := "{C99FEB69-2D62-4D47-A6B3-4FDB6A07FDF8}"
         , IID_IMemoryBuffer           := "{FBC4DD2A-245B-11E4-AF98-689423260CF8}"
         , IID_IMemoryBufferByteAccess := "{5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D}"

    if (Busy)   ; Sleep inside the async wait lets timers/hotkeys run; refuse re-entry
    {
        ErrorLevel := "OcrRect: called again while a previous call is still running"
        return ""
    }
    Busy := 1, err := "", text := "", opRunning := 0
    hdcScreen := 0, hdcMem := 0, hbm := 0, obm := 0, pBits := 0
    sbmp := 0, bbuf := 0, mbuf := 0, mref := 0, bya := 0, op := 0, res := 0, lines := 0

    try
    {
        Loop, 1   ; single pass - "break" jumps straight to the cleanup section
        {
            ; ---------------- one-time WinRT setup ----------------
            if (!Init)
            {
                DllCall("LoadLibrary", "Str", "combase.dll", "Ptr")   ; keep combase pinned
                OcrStatics  := _OcrFactory("Windows.Media.Ocr.OcrEngine", IID_IOcrEngineStatics)
                LangFactory := _OcrFactory("Windows.Globalization.Language", IID_ILanguageFactory)
                SbFactory   := _OcrFactory("Windows.Graphics.Imaging.SoftwareBitmap", IID_ISoftwareBitmapFactory)
                if (!OcrStatics || !LangFactory || !SbFactory)
                {
                    if (OcrStatics)
                        ObjRelease(OcrStatics)
                    if (LangFactory)
                        ObjRelease(LangFactory)
                    if (SbFactory)
                        ObjRelease(SbFactory)
                    OcrStatics := 0, LangFactory := 0, SbFactory := 0
                    err := "OcrRect: Windows.Media.Ocr is not available (Windows 10 or later required)"
                    break
                }
                ; IOcrEngineStatics::get_MaxImageDimension (vtbl 6)
                DllCall(_OcrVT(OcrStatics, 6), "Ptr", OcrStatics, "UInt*", MaxDim, "Int")
                if (!MaxDim)
                    MaxDim := 10000
                Init := 1
            }

            ; ---------------- cached OcrEngine, rebuilt only when the language changes ----------------
            if (lang = "FirstFromAvailableLanguages")
                lang := ""
            if (!Engine || lang != EngineLang)
            {
                if (Engine)
                    ObjRelease(Engine)
                Engine := 0, EngineLang := ""
                if (lang = "")
                {
                    ; IOcrEngineStatics::TryCreateFromUserProfileLanguages (vtbl 10)
                    DllCall(_OcrVT(OcrStatics, 10), "Ptr", OcrStatics, "Ptr*", Engine, "Int")
                }
                else
                {
                    hLang := _OcrHStr(lang), oLang := 0
                    ; ILanguageFactory::CreateLanguage (vtbl 6)
                    DllCall(_OcrVT(LangFactory, 6), "Ptr", LangFactory, "Ptr", hLang, "Ptr*", oLang, "Int")
                    DllCall("combase\WindowsDeleteString", "Ptr", hLang)
                    if (oLang)
                    {
                        ; IOcrEngineStatics::TryCreateFromLanguage (vtbl 9) - returns S_OK + NULL if unsupported
                        DllCall(_OcrVT(OcrStatics, 9), "Ptr", OcrStatics, "Ptr", oLang, "Ptr*", Engine, "Int")
                        ObjRelease(oLang)
                    }
                }
                if (!Engine)
                {
                    err := "OcrRect: no OCR engine for language """ lang """ (add that language's OCR feature in Windows Settings > Time & language)"
                    break
                }
                EngineLang := lang
            }

            ; ---------------- capture the screen rectangle into a 32bpp top-down DIB ----------------
            x := Round(x), y := Round(y), w := Round(w), h := Round(h)
            if (w < 1 || h < 1)
            {
                err := "OcrRect: empty rectangle"
                break
            }
            if scale is not number
                scale := 1
            if (scale <= 0)
                scale := 1
            sw := Round(w * scale), sh := Round(h * scale)
            sw := (sw < 1) ? 1 : sw, sh := (sh < 1) ? 1 : sh
            bw := sw + 2 * Pad, bh := sh + 2 * Pad          ; small margin + at least 40x40
            bw := (bw < 40) ? 40 : bw, bh := (bh < 40) ? 40 : bh
            if (bw > MaxDim || bh > MaxDim)
            {
                err := "OcrRect: scaled image " bw "x" bh " exceeds OcrEngine.MaxImageDimension (" MaxDim ")"
                break
            }
            ox := (bw - sw) // 2, oy := (bh - sh) // 2

            VarSetCapacity(bi, 40, 0)                                        ; BITMAPINFOHEADER
            NumPut(40, bi, 0, "UInt"), NumPut(bw, bi, 4, "Int"), NumPut(-bh, bi, 8, "Int")   ; -height = top-down
            NumPut(1, bi, 12, "UShort"), NumPut(32, bi, 14, "UShort")        ; 1 plane, 32 bpp, BI_RGB
            hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")                   ; virtual-screen DC: source coords = screen coords
            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
            hbm := DllCall("CreateDIBSection", "Ptr", hdcMem, "Ptr", &bi, "UInt", 0, "Ptr*", pBits, "Ptr", 0, "UInt", 0, "Ptr")
            if (!hdcScreen || !hdcMem || !hbm || !pBits)
            {
                err := "OcrRect: GDI capture setup failed"
                break
            }
            obm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
            if (redOnly)
            {
                ; keep only reddish pixels, as black text on white: capture 1:1, filter, then scale into the OCR bitmap
                VarSetCapacity(bi1, 40, 0)
                NumPut(40, bi1, 0, "UInt"), NumPut(w, bi1, 4, "Int"), NumPut(-h, bi1, 8, "Int")
                NumPut(1, bi1, 12, "UShort"), NumPut(32, bi1, 14, "UShort")
                pBits1 := 0, obm1 := 0
                hdc1 := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
                hbm1 := hdc1 ? DllCall("CreateDIBSection", "Ptr", hdc1, "Ptr", &bi1, "UInt", 0, "Ptr*", pBits1, "Ptr", 0, "UInt", 0, "Ptr") : 0
                if (hbm1 && pBits1)
                {
                    obm1 := DllCall("SelectObject", "Ptr", hdc1, "Ptr", hbm1, "Ptr")
                    DllCall("BitBlt", "Ptr", hdc1, "Int", 0, "Int", 0, "Int", w, "Int", h
                          , "Ptr", hdcScreen, "Int", x, "Int", y, "UInt", 0x00CC0020)
                    DllCall("GdiFlush")
                    Loop, % w * h
                    {
                        px := pBits1 + (A_Index - 1) * 4, c := NumGet(px + 0, "UInt")
                        cr := (c >> 16) & 0xFF, cg := (c >> 8) & 0xFF, cb := c & 0xFF
                        keep := (redOnly = 2) ? (cr < 90 && cg < 90 && cb < 90)
                              : (redOnly = 3) ? (cr > 195 && cg > 195 && cb > 195)
                              : (redOnly = 4) ? (cr > 170 && cg > 140 && cb < 130 && cr - cb > 70)
                              : (redOnly = 5) ? (cg > 170 && cg - cr > 70 && cg - cb > 70)
                              : (cr > 100 && cr - cg > 45 && cr - cb > 30)
                        NumPut(keep ? 0 : 0xFFFFFF, px + 0, "UInt")
                    }
                    DllCall("PatBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", bw, "Int", bh, "UInt", 0x00FF0062)   ; WHITENESS
                    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 4)                    ; HALFTONE
                    DllCall("SetBrushOrgEx", "Ptr", hdcMem, "Int", 0, "Int", 0, "Ptr", 0)
                    DllCall("StretchBlt", "Ptr", hdcMem, "Int", ox, "Int", oy, "Int", sw, "Int", sh
                          , "Ptr", hdc1, "Int", 0, "Int", 0, "Int", w, "Int", h, "UInt", 0x00CC0020)
                    DllCall("SelectObject", "Ptr", hdc1, "Ptr", obm1, "Ptr")
                }
                if (hbm1)
                    DllCall("DeleteObject", "Ptr", hbm1)
                if (hdc1)
                    DllCall("DeleteDC", "Ptr", hdc1)
                if (!obm1)
                {
                    err := "OcrRect: GDI capture setup failed (red filter)"
                    break
                }
            }
            else
            {
                ; margin: stretch the rectangle's top-left pixel over the whole bitmap (background-coloured border)
                DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", bw, "Int", bh
                      , "Ptr", hdcScreen, "Int", x, "Int", y, "Int", 1, "Int", 1, "UInt", 0x00CC0020)   ; SRCCOPY
                if (sw = w && sh = h)
                    DllCall("BitBlt", "Ptr", hdcMem, "Int", ox, "Int", oy, "Int", w, "Int", h
                          , "Ptr", hdcScreen, "Int", x, "Int", y, "UInt", 0x00CC0020)
                else
                {
                    DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 4)                    ; HALFTONE
                    DllCall("SetBrushOrgEx", "Ptr", hdcMem, "Int", 0, "Int", 0, "Ptr", 0)   ; required after HALFTONE
                    DllCall("StretchBlt", "Ptr", hdcMem, "Int", ox, "Int", oy, "Int", sw, "Int", sh
                          , "Ptr", hdcScreen, "Int", x, "Int", y, "Int", w, "Int", h, "UInt", 0x00CC0020)
                }
            }
            DllCall("GdiFlush")                                   ; finish GDI work before reading pBits
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen), hdcScreen := 0

            ; ---------------- copy pixels into a WinRT SoftwareBitmap ----------------
            ; ISoftwareBitmapFactory::CreateWithAlpha (vtbl 7): BitmapPixelFormat.Bgra8 = 87,
            ; BitmapAlphaMode.Ignore = 2 (HALFTONE writes alpha = 0, so alpha must be ignored)
            hr := DllCall(_OcrVT(SbFactory, 7), "Ptr", SbFactory, "Int", 87, "Int", bw, "Int", bh, "Int", 2, "Ptr*", sbmp, "Int")
            if (hr < 0 || !sbmp)
            {
                err := "OcrRect: SoftwareBitmap.CreateWithAlpha failed " _OcrHex(hr)
                break
            }
            ; ISoftwareBitmap::LockBuffer (vtbl 15): BitmapBufferAccessMode.Write = 2
            hr := DllCall(_OcrVT(sbmp, 15), "Ptr", sbmp, "Int", 2, "Ptr*", bbuf, "Int")
            if (hr < 0 || !bbuf)
            {
                err := "OcrRect: SoftwareBitmap.LockBuffer failed " _OcrHex(hr)
                break
            }
            ; IBitmapBuffer::GetPlaneDescription(0) (vtbl 7) -> {Int32 StartIndex, Width, Height, Stride}
            VarSetCapacity(pd, 16, 0)
            DllCall(_OcrVT(bbuf, 7), "Ptr", bbuf, "Int", 0, "Ptr", &pd, "Int")
            rowBytes := bw * 4
            start := NumGet(pd, 0, "Int"), stride := NumGet(pd, 12, "Int")
            if (stride < rowBytes)
                start := 0, stride := rowBytes
            pDst := 0, cap := 0
            if (_OcrQI(bbuf, IID_IMemoryBuffer, mbuf) >= 0 && mbuf)                       ; IUnknown::QueryInterface
            {
                ; IMemoryBuffer::CreateReference (vtbl 6)
                if (DllCall(_OcrVT(mbuf, 6), "Ptr", mbuf, "Ptr*", mref, "Int") >= 0 && mref)
                {
                    if (_OcrQI(mref, IID_IMemoryBufferByteAccess, bya) >= 0 && bya)
                        DllCall(_OcrVT(bya, 3), "Ptr", bya, "Ptr*", pDst, "UInt*", cap, "Int")   ; IMemoryBufferByteAccess::GetBuffer (vtbl 3)
                }
            }
            if (!pDst || cap < start + stride * (bh - 1) + rowBytes)
            {
                err := "OcrRect: cannot access the SoftwareBitmap pixel buffer"
                break
            }
            if (stride = rowBytes)
                DllCall("RtlMoveMemory", "Ptr", pDst + start, "Ptr", pBits, "Ptr", rowBytes * bh)
            else
                Loop, % bh
                    DllCall("RtlMoveMemory", "Ptr", pDst + start + (A_Index - 1) * stride
                          , "Ptr", pBits + (A_Index - 1) * rowBytes, "Ptr", rowBytes)
            ; unlock: drop the byte view, Close+Release the reference, then Close+Release the BitmapBuffer
            ObjRelease(bya), bya := 0
            _OcrClose(mref), ObjRelease(mref), mref := 0
            ObjRelease(mbuf), mbuf := 0
            _OcrClose(bbuf), ObjRelease(bbuf), bbuf := 0

            ; ---------------- recognize ----------------
            ; IOcrEngine::RecognizeAsync (vtbl 6) -> IAsyncOperation<OcrResult>
            hr := DllCall(_OcrVT(Engine, 6), "Ptr", Engine, "Ptr", sbmp, "Ptr*", op, "Int")
            if (hr < 0 || !op)
            {
                err := "OcrRect: RecognizeAsync failed " _OcrHex(hr)
                break
            }
            hr := _OcrAwait(op, res, opRunning)
            if (opRunning)
            {
                ; the canceled operation never left "Started": it may still hold/use the bitmap and
                ; the engine, so do not Close the bitmap and rebuild the engine on the next call
                ObjRelease(Engine), Engine := 0, EngineLang := ""
            }
            if (hr < 0 || !res)
            {
                err := "OcrRect: recognition failed " _OcrHex(hr)
                break
            }
            ; IOcrResult::get_Lines (vtbl 6) -> IVectorView<OcrLine>
            hr := DllCall(_OcrVT(res, 6), "Ptr", res, "Ptr*", lines, "Int")
            if (hr < 0)
            {
                err := "OcrRect: OcrResult.Lines failed " _OcrHex(hr)
                break
            }
            n := 0
            if (lines)
                DllCall(_OcrVT(lines, 7), "Ptr", lines, "UInt*", n, "Int")              ; IVectorView::get_Size
            ; lineRects (optional out): [{text, x, y, w, h}, ...] per line, in SCREEN coordinates
            lineRects := []
            fx := w / sw, fy := h / sh                                                 ; bitmap px -> screen px
            VarSetCapacity(wr, 16, 0)
            Loop, % n
            {
                line := 0, hTxt := 0
                DllCall(_OcrVT(lines, 6), "Ptr", lines, "UInt", A_Index - 1, "Ptr*", line, "Int")   ; IVectorView::GetAt
                if (!line)
                    continue
                DllCall(_OcrVT(line, 7), "Ptr", line, "Ptr*", hTxt, "Int")             ; IOcrLine::get_Text (HSTRING)
                lineText := _OcrHStrTake(hTxt)
                text .= (text = "" ? "" : "`n") . lineText
                ; union of the line's word boxes: IOcrLine::get_Words (vtbl 6) -> IVectorView<OcrWord>
                words := 0, nw := 0, x1 := "", y1 := "", x2 := "", y2 := "", wordRects := []
                DllCall(_OcrVT(line, 6), "Ptr", line, "Ptr*", words, "Int")
                if (words)
                {
                    DllCall(_OcrVT(words, 7), "Ptr", words, "UInt*", nw, "Int")
                    Loop, % nw
                    {
                        word := 0
                        DllCall(_OcrVT(words, 6), "Ptr", words, "UInt", A_Index - 1, "Ptr*", word, "Int")
                        if (!word)
                            continue
                        ; IOcrWord::get_BoundingRect (vtbl 6) -> Windows.Foundation.Rect {float X, Y, Width, Height}
                        if (DllCall(_OcrVT(word, 6), "Ptr", word, "Ptr", &wr, "Int") >= 0)
                        {
                            rx := NumGet(wr, 0, "Float"), ry := NumGet(wr, 4, "Float")
                            rx2 := rx + NumGet(wr, 8, "Float"), ry2 := ry + NumGet(wr, 12, "Float")
                            x1 := (x1 = "" || rx < x1) ? rx : x1, y1 := (y1 = "" || ry < y1) ? ry : y1
                            x2 := (x2 = "" || rx2 > x2) ? rx2 : x2, y2 := (y2 = "" || ry2 > y2) ? ry2 : y2
                            ; IOcrWord::get_Text (vtbl 7): each word's own box too (two buttons on one row
                            ; can come back as one line)
                            hWord := 0
                            DllCall(_OcrVT(word, 7), "Ptr", word, "Ptr*", hWord, "Int")
                            wordRects.Push({text: _OcrHStrTake(hWord), x: Round(x + (rx - ox) * fx), y: Round(y + (ry - oy) * fy)
                                , w: Round((rx2 - rx) * fx), h: Round((ry2 - ry) * fy)})
                        }
                        ObjRelease(word)
                    }
                    ObjRelease(words)
                }
                if (x1 != "")
                    lineRects.Push({text: lineText, x: Round(x + (x1 - ox) * fx), y: Round(y + (y1 - oy) * fy)
                        , w: Round((x2 - x1) * fx), h: Round((y2 - y1) * fy), words: wordRects})
                ObjRelease(line)
            }
        }
    }
    catch e
        err := "OcrRect: " (IsObject(e) ? e.Message " (" e.What ")" : e)

    ; ---------------- cleanup (runs on every path) ----------------
    if (lines)
        ObjRelease(lines)
    if (res)
        ObjRelease(res)
    if (op)
        ObjRelease(op)
    if (bya)
        ObjRelease(bya)
    if (mref)
        _OcrClose(mref), ObjRelease(mref)
    if (mbuf)
        ObjRelease(mbuf)
    if (bbuf)
        _OcrClose(bbuf), ObjRelease(bbuf)
    if (sbmp)
    {
        if (!opRunning)
            _OcrClose(sbmp)                      ; IClosable::Close frees the pixel memory immediately
        ObjRelease(sbmp)                         ; still-running op keeps its own reference
    }
    if (obm)
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", obm, "Ptr")
    if (hbm)
        DllCall("DeleteObject", "Ptr", hbm)
    if (hdcMem)
        DllCall("DeleteDC", "Ptr", hdcMem)
    if (hdcScreen)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    Busy := 0
    ErrorLevel := (err = "") ? 0 : err
    return text
}

; ---- helpers (prefixed _Ocr to avoid clashing with the rest of the script) ----

_OcrVT(p, i)   ; address of vtable slot i of interface pointer p
{
    return NumGet(NumGet(p + 0, 0, "Ptr"), i * A_PtrSize, "Ptr")
}

_OcrQI(p, iid, ByRef out)   ; IUnknown::QueryInterface (vtbl 0) -> HRESULT; out = new reference
{
    out := 0
    VarSetCapacity(guid, 16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", iid, "Ptr", &guid, "Int")
    return DllCall(_OcrVT(p, 0), "Ptr", p, "Ptr", &guid, "Ptr*", out, "Int")
}

_OcrClose(p)   ; Windows.Foundation.IClosable::Close (vtbl 6)
{
    static IID_IClosable := "{30D5A829-7FA4-4026-83BB-D75BAE4EA99E}"
    c := 0
    if (_OcrQI(p, IID_IClosable, c) >= 0 && c)
    {
        DllCall(_OcrVT(c, 6), "Ptr", c, "Int")
        ObjRelease(c)
    }
}

_OcrFactory(className, iid)   ; RoGetActivationFactory -> statics/factory interface, or 0
{
    VarSetCapacity(guid, 16, 0)
    if (DllCall("ole32\CLSIDFromString", "WStr", iid, "Ptr", &guid, "Int") != 0)
        return 0
    hCls := _OcrHStr(className), fac := 0
    hr := DllCall("combase\RoGetActivationFactory", "Ptr", hCls, "Ptr", &guid, "Ptr*", fac, "Int")
    DllCall("combase\WindowsDeleteString", "Ptr", hCls)
    return (hr = 0 && fac) ? fac : 0
}

_OcrHStr(str)   ; new HSTRING - caller must WindowsDeleteString it
{
    h := 0
    len := StrPut(str, "UTF-16") - 1          ; UTF-16 code units (correct on ANSI and Unicode builds)
    DllCall("combase\WindowsCreateString", "WStr", str, "UInt", len, "Ptr*", h, "Int")
    return h
}

_OcrHStrTake(h)   ; read an HSTRING returned by a WinRT getter, then free it
{
    if (!h)
        return ""
    len := 0
    p := DllCall("combase\WindowsGetStringRawBuffer", "Ptr", h, "UInt*", len, "Ptr")
    s := (p && len) ? StrGet(p, len, "UTF-16") : ""
    DllCall("combase\WindowsDeleteString", "Ptr", h)
    return s
}

; wait for an IAsyncOperation<T>, then GetResults.
; running (out) = 1 if the op was canceled after a timeout but never left the Started state.
_OcrAwait(op, ByRef result, ByRef running := 0, timeoutMs := 5000)
{
    static IID_IAsyncInfo := "{00000036-0000-0000-C000-000000000046}"
    result := 0, running := 0, info := 0, status := 0
    hr := _OcrQI(op, IID_IAsyncInfo, info)
    if (hr < 0 || !info)
        return (hr < 0) ? hr : -2147467259                                 ; E_FAIL
    t0 := A_TickCount, canceled := 0
    Loop
    {
        DllCall(_OcrVT(info, 7), "Ptr", info, "UInt*", status, "Int")     ; IAsyncInfo::get_Status
        if (status != 0)                                                    ; 0 = Started
            break
        if (!canceled && A_TickCount - t0 > timeoutMs)
        {
            DllCall(_OcrVT(info, 9), "Ptr", info, "Int")                    ; IAsyncInfo::Cancel
            canceled := 1, t0 := A_TickCount, timeoutMs := 500              ; give the cancel a moment to land
        }
        else if (canceled && A_TickCount - t0 > timeoutMs)
            break
        Sleep, 1
    }
    if (status = 1)                                                         ; 1 = Completed
        hr := DllCall(_OcrVT(op, 8), "Ptr", op, "Ptr*", result, "Int")     ; IAsyncOperation<T>::GetResults
    else
    {
        hr := 0
        if (status = 3)                                                     ; 3 = Error
            DllCall(_OcrVT(info, 8), "Ptr", info, "Int*", hr, "Int")        ; IAsyncInfo::get_ErrorCode
        if (hr >= 0)
            hr := -2147467260                                               ; E_ABORT: canceled / timed out
    }
    if (status != 0)
        DllCall(_OcrVT(info, 10), "Ptr", info, "Int")                       ; IAsyncInfo::Close
    else
        running := 1
    ObjRelease(info)
    return hr
}

_OcrHex(n)
{
    return (n = "") ? "(DllCall failed)" : Format("0x{:08X}", n & 0xFFFFFFFF)
}
