; MouseSteer.ahk - turning the wizard with the mouse while it walks: the right button held and the mouse slid left or
; right turns the wizard itself while W runs (you checked it, 2026-10-23), at once - no 400-unit arc as with A/D (the
; wizard walks ~1000 units a second and A/D turns ~145 degrees a second). AHK v1.1; #Included at the end of Walker.ahk.
;
; Only while walking (W held), steering by the game's memory (it reads the facing back as it turns: the turn is closed
; loop, and how far a mouse count turns the wizard is measured on the first turn - MsK), out of battle, Wizard101 in
; front, you away from the keyboard and mouse (3 s - its own moves don't count; you touching anything mid-turn ends it,
; the mouse left to you), at 5x or less, no window open over the middle of the game (a window's words there: Crowns,
; shop, buy, quest...). The right button is pressed at a point in the middle of the scene, the mouse slid, the button let
; go; the mouse back where it was. A right click that doesn't drag opens nothing (you checked it). Anything not sure: A/D
; as before (turns on the spot always A/D). Setting: mousesteer (on unless 0).

;How far one mouse count turns the wizard (degrees, its sign the way it turns - "" not measured yet) and the WkNavSign it
;was measured under, off till (tick), probes that found no turn, the right button held by the bot, the window check
;(when, its answer, why), what was last said and when, the radius sent with the last route ask and whether it was the
;mouse's
global MsK, MsKSign, MsOffUntil, MsFails, MsHeld, MsWinAt, MsWinOk, MsWinWhy, MsSaid, MsSaidAt, WkArcSentR, WkArcMouse
;Measured mouse turns that didn't turn the wizard, in a row (two: the count's worth measured again - one alone is
;likely the moment's: a battle pulling him round, a window)
global MsMiss
;When a mouse turn last missed (it isn't tried again at once by another way round - Turn, BackUp, DgTurn); one that
;worked doesn't count
global MsTriedAt
;Turns from standing by the mouse that didn't turn the wizard, in a row, and till when they aren't tried (two: 10 minutes)
global MsStandMiss, MsStandOff

;The setting (mousesteer, on unless 0) and the game's memory there to read the facing by
MouseSteerOn()
	{
	return IsFunc("NavRead") && !(IsObject(Stats) && Stats.HasKey("mousesteer") && !Stats["mousesteer"])
	}

;Whether a mouse turn may go now: why not ("" it may). needW: W held already (false: about to be). byMem false: a
;dungeon run, following the party's leader or walking to a quest item (AutoFarmer DgSteer) - steering by the game's
;memory, not the walker's arrow, and not at the walker's goal
MouseSteerWhyNot(needW := true, byMem := true)
	{
	if (!MouseSteerOn())
		return "off"
	if (MsOffUntil && A_TickCount < MsOffUntil)
		return "off for now (the mouse didn't turn the wizard)"
	if (!Walking || (needW && !HeldW) || inbattle)
		return "not walking"
	;(the wizard running already - the right button turns him while he runs; standing, it turns the camera)
	if (needW && WkWalkFrom && A_TickCount - WkWalkFrom < 600)
		return "just set off"
	if (!GameActive())
		return "Wizard101 not in front"
	if (byMem && (!WkNavUse || !WkNavOk))
		return "not steering by the game's memory"
	if (SpeedNow > 5)
		return "sped up over 5x"
	if (byMem && WkArrived != 0 && WkArrived != 3 && WkArrived != 7)
		return "at the goal"
	if (PlayerActive || UserIdle() < 3000)
		return "you're at the keyboard or mouse"
	if (GetKeyState("RButton", "P") || GetKeyState("LButton", "P") || GetKeyState("Shift", "P") || GetKeyState("Ctrl", "P")
		|| GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
		return "a key or button of yours is down"
	if (!MouseSteerWindowClear())
		return MsWinWhy
	return ""
	}

;No window over the middle of the game - a shop, a quest offer, a Crown one: none of a window's words where the button's
;pressed (an OCR of the middle - a close-button search over the whole game takes seconds). Looked at once in 2.5 s - and
;afresh after the walker presses a key or clicks (PressKey, WalkClick: MsWinAt := 0)
MouseSteerWindowClear()
	{
	if (MsWinAt && A_TickCount - MsWinAt < 2500)
		return MsWinOk
	MsWinOk := 0, MsWinWhy := ""
	mwT := OcrRect(Round(GameLeft + GameW * 0.3), Round(GameTop + GameH * 0.15), Round(GameW * 0.4), Round(GameH * 0.3))
	if (ErrorLevel)
		{
		MsWinWhy := "the middle of the game couldn't be read", MsWinAt := A_TickCount
		return 0
		}
	if (RegExMatch(mwT, "i)cr[o0]wn|\bshop|\bbuy\b|\bsell\b|purchase|accept|decline|\bquest|reward|\btrade|upgrade|member|recipe|reagent|\bgold\b|friend|okay|\bok\b|cancel|confirm|\bclose\b", mwM))
		{
		MsWinWhy := "a window over the game (""" mwM """)", MsWinAt := A_TickCount
		return 0
		}
	MsWinOk := 1, MsWinAt := A_TickCount
	return 1
	}

;Where the right button's pressed: the middle of the scene, a little high - not the hand, the arrow, the prompt or any
;corner's buttons
MouseSteerPoint(ByRef x, ByRef y)
	{
	x := Round(GameLeft + GameW * 0.5), y := Round(GameTop + GameH * 0.3)
	}

;The wizard's facing now off the game's memory (radians, "" not read) - a short ask without the route; a miss doesn't
;put the walker's own reads off (NavRead's wait after one is put back)
MouseSteerYaw()
	{
	mwWait := NavWait, mwUntil := NavWaitUntil, mwWhy := NavWhy
	nav := Func("NavRead").Call(120)
	NavWait := mwWait, NavWaitUntil := mwUntil, NavWhy := mwWhy
	return (IsObject(nav) && nav.yaw != "") ? nav.yaw : ""
	}

;The mouse slid c counts sideways (+ right), in steps of at most 8, 2 ms apart - as a mouse sends them (Windows' pointer
;speed works on each step). With the right button held the game hides the cursor and puts it back where it was pressed
;every 25-40 ms, turning by how far it went meanwhile (watched 2026-10-23 on a drag of yours)
MouseSteerMove(c)
	{
	left := c
	DllCall("winmm\timeBeginPeriod", "UInt", 1)
	while (left != 0)
		{
		d := left > 8 ? 8 : left < -8 ? -8 : left
		DllCall("mouse_event", "UInt", 0x0001, "Int", d, "Int", 0, "UInt", 0, "UPtr", 0)
		left -= d
		if (left != 0)
			DllCall("Sleep", "UInt", 2)
		}
	DllCall("winmm\timeEndPeriod", "UInt", 1)
	}

;The right button down (1) or up (0) where the mouse is
MouseSteerButton(down)
	{
	DllCall("mouse_event", "UInt", down ? 0x0008 : 0x0010, "Int", 0, "Int", 0, "UInt", 0, "UPtr", 0)
	MsHeld := down ? 1 : 0
	}

;How far the wizard turned since yaw0 (degrees, positive to the right - as Turn's h)
MouseSteerTurned(yaw, yaw0)
	{
	return WkNavSign * ArrowWrap((yaw - yaw0) * 57.29578)
	}

;You touched the keyboard or mouse since from (the bot's own input doesn't count: the hooks), or Wizard101 isn't in front
MouseSteerYours(from)
	{
	return UserIdle() < A_TickCount - from || !GameActive()
	}

;Where the cursor is and whether it shows: "x,y shown" / "x,y hidden" (screen), "?" not known
MouseSteerCursor()
	{
	VarSetCapacity(ci, 16 + A_PtrSize, 0), NumPut(16 + A_PtrSize, ci, 0, "UInt")
	if (!DllCall("GetCursorInfo", "Ptr", &ci))
		return "?"
	return NumGet(ci, 8 + A_PtrSize, "Int") "," NumGet(ci, 12 + A_PtrSize, "Int") (NumGet(ci, 4, "UInt") & 1 ? " shown" : " hidden")
	}

;Said in debug.log at most once a minute for the same thing
MouseSteerNote(what)
	{
	if (what = MsSaid && A_TickCount - MsSaidAt < 60000)
		return
	MsSaid := what, MsSaidAt := A_TickCount
	WalkLog("mouse steering: " what)
	}

;Turn the wizard h degrees (+ right) walking on, by the mouse: how far it turned ("" not done - A/D then). The first
;turn measures how far a count turns it (a few counts more each look till it turns 3 degrees); each turn after goes in
;up to 5 looks, to within 4 degrees (45 degrees' worth in the first, 90 after). A look turning it the wrong way: undone,
;and measured again next time; measured, but not turning him now (a window, the game's menu): A/D, which notices and
;deals with it, and measured again next time; no turn after 168 counts, three times: off for 10 minutes. You touching
;anything meanwhile: the turn ends there, the mouse left where you have it
MouseTurn(h, byMem := true)
	{
	;(the memory's heading turned round since the count was measured: so is the count)
	if (MsK != "" && MsKSign != WkNavSign)
		MsK := -MsK, MsKSign := WkNavSign
	why := MouseSteerWhyNot(true, byMem)
	if (why != "")
		{
		if (why != "not walking" && why != "off" && why != "just set off")
			MouseSteerNote("not now - " why)
		return ""
		}
	yaw0 := MouseSteerYaw()
	if (yaw0 = "")
		return ""
	wasCrit := A_IsCritical
	Critical
	;(the window and the read let other threads run: F6, F8, you - looked at again before anything's pressed)
	if (!Walking || !HeldW || inbattle || !GameActive() || PlayerActive || UserIdle() < 3000)
		{
		if (!wasCrit)
			Critical, Off
		return ""
		}
	MouseGetPos, msX0, msY0
	MouseSteerPoint(msPx, msPy)
	MouseMove, %msPx%, %msPy%, 0
	sent := 0, turned := 0, probed := false, msUser := false, msFrom := A_TickCount
	try
		{
		MouseSteerButton(1)
		Sleep, 60
		;(where the cursor is and whether it shows, before the slide and after: the game hiding it or putting it back
		;says it took the drag - for debug.log when the mouse doesn't turn him)
		msCur0 := MouseSteerCursor()
		;(how far a count turns it, not known: a few counts at a time, more each look, the way it should turn - mouse
		;right taken to turn it right till it's seen)
		if (MsK = "")
			{
			probed := true
			for each, msC in [8, 24, 64, 72]
				{
				msC := h > 0 ? msC : -msC
				MouseSteerMove(msC), sent += msC
				Sleep, 40
				msY := MouseSteerYaw()
				if (MouseSteerYours(msFrom))
					{
					if (msY != "")
						turned := MouseSteerTurned(msY, yaw0)
					msUser := true
					break
					}
				if (msY = "")
					break
				turned := MouseSteerTurned(msY, yaw0)
				if (Abs(turned) >= 3)
					{
					MsK := turned / sent, MsKSign := WkNavSign, MsFails := 0
					MouseSteerNote("a mouse count turns the wizard " Round(Abs(MsK), 3) " degrees (" (MsK > 0 ? "" : "the other way - ") "measured: " Round(Abs(turned)) " degrees for " Abs(sent) " counts)")
					break
					}
				}
			if (MsK = "" && msY != "" && !msUser)
				{
				MsFails := (MsFails ? MsFails : 0) + 1
				MouseSteerNote("the mouse didn't turn the wizard (" Abs(sent) " counts, " Round(turned, 1) " degrees; the cursor " msCur0 " before the slide, " MouseSteerCursor() " after) - A/D" (MsFails >= 3 ? ", and the mouse left alone for 10 minutes" : ""))
				if (MsFails >= 3)
					MsFails := 0, MsOffUntil := A_TickCount + 600000
				}
			}
		if (MsK != "" && !msUser)
			Loop, 5
				{
				if (MouseSteerYours(msFrom))
					{
					msUser := true
					break
					}
				err := h - turned
				if (Abs(err) <= 4)
					break
				;(45 degrees' worth at most in the first look, 90 after: a count's worth measured wrong can't swing him far)
				;(and never more than a third of the game's width at once: should the game read where the cursor is, it
				;doesn't run off the screen)
				most := Min(Round((A_Index = 1 ? 45 : 90) / Abs(MsK)), Round(GameW * 0.3))
				msC := Round(err / MsK)
				msC := msC > most ? most : msC < -most ? -most : msC
				if (msC = 0)
					break
				MouseSteerMove(msC), sent += msC
				Sleep, 35
				msY := MouseSteerYaw()
				if (MouseSteerYours(msFrom))
					{
					if (msY != "")
						turned := MouseSteerTurned(msY, yaw0)
					msUser := true
					break
					}
				;(not read: taken as turned as far as the counts should have)
				if (msY = "")
					{
					turned += msC * MsK
					break
					}
				;(summed look by look - this look's own turn, wrapped - so a turn past 180 isn't read as one the other way)
				got := ArrowWrap(MouseSteerTurned(msY, yaw0) - turned), now := turned + got
				want := msC * MsK
				;(turned the wrong way: measured again next time - the camera snapped, a battle pulled him round)
				if (want * got < 0 && Abs(got) >= 3)
					{
					MouseSteerNote("a look turned the wizard the wrong way (" Round(got) " degrees, " Round(want) " wanted) - undone, measured again next turn")
					MouseSteerMove(-msC), sent -= msC
					MsK := ""
					break
					}
				;(10 degrees' worth sent and nothing turned: the mouse isn't turning him now - no more counts after it)
				if (Abs(want) >= 10 && Abs(got) < 1)
					{
					turned := now
					break
					}
				;(the count's worth refined as it goes - a fifth each look)
				if (Abs(got) >= 2 && Abs(want) >= 2)
					MsK := MsK * 0.8 + (got / msC) * 0.2
				turned := now
				}
		}
	finally
		{
		MouseSteerButton(0)
		Sleep, 20
		;(the mouse back where it was - not if you've taken it meanwhile)
		if (!MouseSteerYours(msFrom))
			MouseMove, %msX0%, %msY0%, 0
		if (!wasCrit)
			Critical, Off
		}
	;(you took over: what it got to - not "", or the walker would turn him with A/D against you)
	if (msUser)
		return turned
	;(nothing sent, or the measuring found no turn - not read, or none: A/D does this one)
	if (!sent || (probed && MsK = ""))
		{
		MsTriedAt := A_TickCount
		return ""
		}
	;(measured before, and the mouse doesn't turn him now - a window, the game's menu: A/D, which notices and deals with
	;it; measured again next time - three of those with no turn switch the mouse off)
	if (!probed && Abs(h) > 6 && Abs(turned) < 2)
		{
		;(once: likely the moment's - a battle pulling him round, a window - the mouse again next turn; twice in a row:
		;measured again. The keyboard only for this turn either way - 2026-10-24: the mouse is the steadier)
		MsMiss := (MsMiss ? MsMiss : 0) + 1
		MouseSteerNote("the mouse didn't turn the wizard (" Abs(sent) " counts) - A/D this once" (MsMiss >= 2 ? ", measured again next time" : ""))
		if (MsMiss >= 2)
			MsK := "", MsMiss := 0
		MsTriedAt := A_TickCount
		return ""
		}
	MsMiss := 0
	if (IsObject(WkMet))
		WkMet.mturns := (WkMet.mturns ? WkMet.mturns : 0) + 1
	if (Abs(turned) >= 15)
		WkTurnAt := A_TickCount
	return turned
	}

;A turn from standing by the mouse (2026-10-24: the keyboard only when the mouse fails): the right button held, the
;camera turned h degrees' worth of counts (the right button turns only the camera while he stands), then W tapped with
;the button still down - the wizard faces where the camera does (a step that way). Checked by the game's memory: within
;25 degrees of h - else "" (A/D then). He's left standing, as a turn on the spot leaves him. Only once a count's worth
;is measured. Two misses in a row: not tried for 10 minutes (said in the log)
MouseStandTurn(h)
	{
	;(the memory's heading turned round since the count was measured: so is the count - as MouseTurn)
	if (MsK != "" && MsKSign != WkNavSign)
		MsK := -MsK, MsKSign := WkNavSign
	if (MsK = "" || Abs(h) < 3 || (MsStandOff && A_TickCount < MsStandOff) || (MsTriedAt && A_TickCount - MsTriedAt < 500))
		return ""
	;(the heading's sign not checked yet: a mouse turn can't tell it turned the wrong way - A/D's check does)
	if (!WkNavTrusted && !WkNavChecked)
		return ""
	;(the W tap is a step: not with a mob's reach or sight ahead - on the spot by A/D instead)
	if (IsObject(WkNavObj) && WkNavObj.blindahead != "" && IsObject(WkNavPrev) && A_TickCount - WkNavPrev.at < 1500)
		return ""
	if (MouseSteerWhyNot(false, false) != "")
		return ""
	yaw0 := MouseSteerYaw()
	if (yaw0 = "")
		return ""
	MsTriedAt := A_TickCount
	wasCrit := A_IsCritical
	Critical
	if (!Walking || inbattle || !GameActive() || PlayerActive || UserIdle() < 3000)
		{
		if (!wasCrit)
			Critical, Off
		return ""
		}
	MouseGetPos, msX0, msY0
	MouseSteerPoint(msPx, msPy)
	MouseMove, %msPx%, %msPy%, 0
	yaw1 := ""
	try
		{
		MouseSteerButton(1)
		Sleep, 60
		;(the counts for h in looks of 90 degrees' worth at most, a third of the game's width at most each)
		want := Round(h / MsK), most := Min(Round(90 / Abs(MsK)), Round(GameW * 0.3))
		while (want != 0)
			{
			c := want > most ? most : want < -most ? -most : want
			MouseSteerMove(c), want -= c
			Sleep, 35
			}
		Sleep, 40
		;(W tapped here, inside the Critical - HoldW lets other threads in, with the button and W down - a short step at
		;any speed)
		KeysDown := 1
		Send, {Blind}{w down}
		HeldW := 1, WkWalkFrom := A_TickCount
		Sleep, % Max(40, Round(120 / (SpeedNow ? SpeedNow : 1)))
		Send, {Blind}{w up}
		HeldW := 0
		Sleep, 40
		yaw1 := MouseSteerYaw()
		if (yaw1 = "")
			{
			Sleep, 60
			yaw1 := MouseSteerYaw()
			}
		}
	finally
		{
		MouseSteerButton(0)
		Sleep, 20
		if (!MouseSteerYours(A_TickCount - 1000))
			MouseMove, %msX0%, %msY0%, 0
		if (!wasCrit)
			Critical, Off
		}
	turned := yaw1 != "" ? MouseSteerTurned(yaw1, yaw0) : ""
	;(off from h by the wrap - a turn of 180 reads -180 as often as 180)
	if (turned != "" && Abs(ArrowWrap(turned - h)) <= 25)
		{
		MsStandMiss := 0
		WkTurnAt := A_TickCount
		if (IsObject(WkMet))
			WkMet.mturns := (WkMet.mturns ? WkMet.mturns : 0) + 1
		return h + ArrowWrap(turned - h)
		}
	MsTriedAt := A_TickCount
	MsStandMiss := (MsStandMiss ? MsStandMiss : 0) + 1
	MouseSteerNote("a turn from standing by the mouse didn't turn the wizard (" Round(h) " wanted, " (turned = "" ? "not read" : Round(turned)) ") - A/D" (MsStandMiss >= 2 ? ", and not tried from standing for 10 minutes" : ""))
	if (MsStandMiss >= 2)
		MsStandMiss := 0, MsStandOff := A_TickCount + 600000
	return ""
	}

;Any turn by the mouse: running - MouseTurn; standing - MouseStandTurn (still standing after it). "" it couldn't
MouseTurnAny(h)
	{
	if (HeldW)
		return MouseTurn(h, false)
	return MouseStandTurn(h)
	}
