; Collect.ahk - "collect N things" goals whose things lie about the zone (2026-10-23: Piece Of Coral in The Grotto),
; collected by the game's memory: the vision helper's /items (read-only) gives each one's place; the nearest the goal
; line names is walked to round walls and mobs (/navto, as a follower walks to its leader) and stepped onto - picked up
; on contact, else X pressed once standing on it. The walker's collecting (AutoQuester\Walker.ahk CollectStep) asks
; here first at each step; none seen: it roams and walks into monsters as before. Settings: collectmem.
; AutoHotkey v1.1, #Included by Autofarmer.ahk.

;The item being walked to (its gid; "" none), since when; the items last read and when; items left for a while
;({gid: till when}); standing still (since when, where) and the tries at getting unstuck; when it was first stood on,
;when X was last pressed on it
global CiGid, CiFrom, CiItems, CiAskAt, CiSkip, CiStillAt, CiStillX, CiStillY, CiTries, CiOnAt, CiXAt

;The zone's quest items by the game's memory, for goal line goal: [{name, x, y, z, dist, quest, gid}] nearest first
;(quest: the goal line names it); "" when they can't be read (no helper, the game's memory unreadable)
CollectItems(goal)
	{
	answer := VisionGet("/items?goal=" NavUri(goal), 2500, true)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	out := []
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "item" && f.Length() >= 8)
			out.Push({name: f[2], x: f[3] + 0, y: f[4] + 0, z: f[5] + 0, dist: f[6] + 0, quest: f[7] = 1, gid: f[8]})
		}
	return out
	}

;One step of collecting goal's items by the game's memory: the nearest the goal names walked to, stood on (X pressed if
;it's still there), then the next. True when it did this step (walking to one, or at one); false when it sees none to go
;for - the walker does its own collecting (monsters, roaming)
CollectItemStep(goal)
	{
	if (Stats.HasKey("collectmem") && !Stats["collectmem"])
		return false
	if (!IsObject(CiSkip))
		CiSkip := {}
	if (!CiAskAt || A_TickCount - CiAskAt > 1500)
		{
		CiAskAt := A_TickCount
		got := CollectItems(goal)
		CiItems := IsObject(got) ? got : []
		}
	it := ""
	for i, x in CiItems
		if (x.quest && !(CiSkip.HasKey(x.gid) && A_TickCount < CiSkip[x.gid]))
			{
			it := x
			break
			}
	if (!IsObject(it))
		{
		if (CiGid != "")
			{
			CiGid := ""
			WalkLog("collect: none of the goal's items left in the game's memory - roaming and looking for monsters")
			ReleaseKeys()
			}
		return false
		}
	if (it.gid != CiGid)
		{
		CiGid := it.gid, CiFrom := A_TickCount, CiTries := 0, CiOnAt := 0, CiXAt := 0, CiStillAt := 0
		WalkLog("collect: " it.name " " Round(it.dist) " away (the game's memory, at " Round(it.x) ", " Round(it.y) ") - walking to it")
		}
	;(a minute on one without getting it - out of reach, or not one to pick up: another one first, this one again in 3
	;minutes)
	if (A_TickCount - CiFrom > 60000)
		{
		CiSkip[it.gid] := A_TickCount + 180000, CiGid := ""
		WalkLog("collect: couldn't get " it.name " in a minute - another one first")
		ReleaseKeys()
		return true
		}
	nav := PartyNavTo({x: it.x, y: it.y, z: it.z}, true)
	if (!IsObject(nav))
		{
		ReleaseKeys()
		return false
		}
	d := Sqrt((nav.x - it.x) ** 2 + (nav.y - it.y) ** 2)
	;Standing on it: picked up on contact - still there after 1.5 s: X pressed (again after 4 s)
	if (d <= 45)
		{
		ReleaseKeys()
		CiOnAt := CiOnAt ? CiOnAt : A_TickCount
		if (A_TickCount - CiOnAt > 1500 && (!CiXAt || A_TickCount - CiXAt > 4000))
			{
			CiXAt := A_TickCount
			WalkLog("collect: on " it.name " and it's still there - pressing X")
			PressKey("x")
			}
		SetStatus("collecting - at " it.name)
		Sleep, 150
		return true
		}
	CiOnAt := 0
	;(stuck: hardly moving for 3 s with W down - backed up and turned; after 4 tries another one first)
	if (HeldW && CiStillAt && Sqrt((nav.x - CiStillX) ** 2 + (nav.y - CiStillY) ** 2) < 60)
		{
		if (A_TickCount - CiStillAt > 3000)
			{
			CiTries += 1, CiStillAt := 0
			if (CiTries > 4)
				{
				CiSkip[it.gid] := A_TickCount + 180000, CiGid := ""
				WalkLog("collect: stuck on the way to " it.name " - another one first")
				ReleaseKeys()
				return true
				}
			WalkLog("collect: stuck on the way to " it.name " (" Round(d) " away) - backing up and turning, try " CiTries)
			BackUp(700)
			DgTurn(CiTries & 1 ? 90 : -90)
			HoldW(1)
			Sleep, 900
			return true
			}
		}
	else
		CiStillAt := A_TickCount, CiStillX := nav.x, CiStillY := nav.y
	SetStatus("collecting - walking to " it.name " (" Round(d) " away)")
	DgSteer(nav, {x: it.x, y: it.y}, d)
	return true
	}
