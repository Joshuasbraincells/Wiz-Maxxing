; Spells.ahk - the dashboard's Spells tab: every card the bot learned by itself (learned\cards.txt), what it took
; each one for and where it uses it - and your corrections. AHK v1.1, functions and labels only; #Included by
; Autofarmer.ahk after Dungeons.ahk (Dashboard.ahk makes the tab's controls).
;
; Pick a spell (or several) and:
;   Change kind...   what it is: a hit on one enemy or on all, a heal, a shield, a blade, a trap, an aura - or a kind
;                    the bot doesn't play (kept in the list, never cast). It's taken out of its slot (a hit that made
;                    room for itself in hit1-3 puts the hits it moved back) and gets the slot the new kind fits, if
;                    one is free
;   Edit...          its name, its number (damage, heal, %) and its pips - a misread number, guessed pips
;   Forget           out of the list, its pictures to backups\learned forgotten. A real card is learned again the
;                    next time it's in hand: to keep one out of use, change its kind to "Not used" instead
;   Never discard    it stays in hand (the bot discards the cards it never plays - never a treasure card)
;   Show picture, Open folder, Moved away... (backups\: non-cards taken out of the list, forgotten spells, the hits
;                    moved to make room for a stronger one), Refresh (learned\cards.txt read again)
; A correction is only queued here (SpQueue). The bot applies it from its own loop, out of battle (SpApplyPending),
; through the card learner's own functions (CardLearn.ahk: LearnSetKind, LearnEdit, LearnForgetById, LearnToggleHold)
; - never in a round, where a slot's picture moving would change what the round's plan is about. What you set is
; marked yours (flag user): the learner never changes it by itself again.

;The tab's controls (Dashboard.ahk makes them)
global SpList, SpHelp, SpStatus, SpKindBtn, SpEditBtn, SpForgetBtn, SpHoldBtn, SpPicBtn, SpFolderBtn, SpMovedBtn, SpRefreshBtn
global SpPreview, SpPreviewTxt
;Corrections waiting for the bot's loop ([{op, arg, ids}]: SpQueue); the list to be filled again (LearnSave sets it);
;the kinds in the Change kind menu ([{kind, label, played}], in its order); the Moved away menu's folders; the note
;under the counts on the status line
global SpPending, SpDirty, SpKinds, SpMovedPaths, SpNoteText
;The Edit window: it, the spell it edits, its fields
global SpEdHwnd, SpEdId, SpEdName, SpEdValue, SpEdPips, SpEdNote
;(tests only: the answer to the Forget question without asking - blank: it's asked)
global SpAskAnswer

;Called once by DashInit, after the other tabs are made: the queue, the Change kind menu, the list
SpInit()
	{
	;(declared without a value: an initializer in an #Included file never runs)
	if (!IsObject(SpPending))
		SpPending := []
	SpDirty := 0, SpNoteText := ""
	SpKinds := SpKindList()
	for i, k in SpKinds
		Menu, SpKindMenu, Add, % SpKindItem(k), SpKindChosen
	SpListFill()
	}

;The kinds a learned spell can be set to, for the Change kind menu ([{kind, label, played}]): CardLearn.ahk's
;LearnTypes() - the ones it offers (menu) - else the ones the learner has always known. Not "" (unknown): "Not used"
;keeps one out of use
SpKindList()
	{
	list := []
	got := SpL("LearnTypes")
	if (IsObject(got))
		for i, t in got
			{
			if (!IsObject(t) || t.kind = "" || (t.HasKey("menu") && !t.menu))
				continue
			list.Push({kind: t.kind, label: t.label != "" ? t.label : t.kind, played: t.played ? 1 : 0})
			}
	if (!list.Length())
		for i, t in [["damage", "Hits one enemy"], ["aoe", "Hits all enemies"], ["heal", "Heals you"], ["ward", "Shield (cast on you)"], ["blade", "Blade"]
			, ["trap", "Trap"], ["aura", "Aura"], ["dot", "Damage over time"], ["stun", "Stun"], ["dispel", "Dispel"], ["prism", "Prism (converts the school)"]
			, ["clear", "Removes shields or charms (N times Clear)"], ["keep", "Not used (stays in the list)"]]
			list.Push({kind: t[1], label: t[2], played: InStr(",damage,aoe,heal,ward,blade,trap,aura,", "," t[1] ",") ? 1 : 0})
	return list
	}

;A kind's line in the Change kind menu: its label, "(not played)" for one the bot doesn't play
SpKindItem(k)
	{
	return StrReplace(k.label, "&", "and") (k.played ? "" : "   (not played)")
	}

;A kind's label for the list (CardLearn.ahk's LearnKindLabel: "unknown" for "")
SpKindLabel(kind)
	{
	if (IsFunc("LearnKindLabel"))
		return Func("LearnKindLabel").Call(kind)
	if (IsObject(SpKinds))
		for i, k in SpKinds
			if (k.kind = kind)
				return k.label
	return kind = "" ? "unknown" : kind
	}

;A function of the card learner (CardLearn.ahk) called by its name: "" when there's no such function, so this tab
;loads whatever the learner's functions are called
SpL(fn, args*)
	{
	return IsFunc(fn) ? Func(fn).Call(args*) : ""
	}

;---- The list ----

;Fills the list from the catalog (the spells selected stay selected) and the status line. Only what the catalog
;says: never asks the vision helper or looks for a free slot (LearnSlotFor / LearnFree would)
SpListFill()
	{
	if (!DashHwnd)
		return
	wasCrit := A_IsCritical
	Critical
	if (!IsObject(LearnedCards))
		SpL("LearnLoad")
	prevLV := SpListSelect()
	keep := {}
	row := 0
	while (row := LV_GetNext(row))
		{
		LV_GetText(id, row, 11)
		keep[id] := 1
		}
	GuiControl, Dash:-Redraw, SpList
	LV_Delete()
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			{
			row := LV_Add("", SpName(c), SpKindText(c), c.sch, SpPipsText(c), SpValueText(c), SpInUse(c), c.text, SpFlag(c, "tc") ? "yes" : ""
				, SpWhen(c.when), c.dir = "" ? "main" : c.dir, c.id)
			if (keep.HasKey(c.id))
				LV_Modify(row, "Select")
			}
	GuiControl, Dash:+Redraw, SpList
	SpListBack(prevLV)
	SpDirty := 0
	SpStatusShow()
	CfgUncritical(wasCrit, 0)
	}

;Makes SpList the ListView the LV_ functions work on (the window has two: the Dungeons tab's too) and returns the
;one that was - SpListBack puts it back, so a DgListFill this interrupted carries on in its own list
SpListSelect()
	{
	Gui, Dash:Default
	prevLV := A_DefaultListView
	Gui, Dash:ListView, SpList
	return prevLV
	}

SpListBack(prevLV)
	{
	if (prevLV != "" && prevLV != "SpList")
		Gui, Dash:ListView, %prevLV%
	}

;The ids of the spells selected in the list ([] none)
SpSelectedIds()
	{
	ids := []
	if (!DashHwnd)
		return ids
	wasCrit := A_IsCritical
	Critical
	prevLV := SpListSelect()
	row := 0
	while (row := LV_GetNext(row))
		{
		LV_GetText(id, row, 11)
		if (id != "")
			ids.Push(id)
		}
	SpListBack(prevLV)
	return CfgUncritical(wasCrit, ids)
	}

;The counts, the corrections waiting and the last note
SpStatusShow()
	{
	if (!DashHwnd)
		return
	n := 0, nUse := 0
	if (IsObject(LearnedCards))
		for i, c in LearnedCards
			n += 1, nUse += (c.slot != "")
	text := n " spell" (n = 1 ? "" : "s") " - " nUse " in use, " n - nUse " kept"
	junk := SpLineCount(A_WorkingDir "\backups\learned junk\cards.txt")
	if (junk)
		text .= " | " junk " non-card" (junk = 1 ? "" : "s") " moved away"
	waiting := IsObject(SpPending) ? SpPending.Length() : 0
	if (waiting)
		text .= " | " waiting " change" (waiting = 1 ? "" : "s") " waiting (applied out of battle)"
	;(two lines, each cut to what fits the narrowest window: Consolas 9 is about 7 px a letter)
	note := StrLen(SpNoteText) > 100 ? SubStr(SpNoteText, 1, 99) "~" : SpNoteText
	GuiControl, Dash:, SpStatus, % text (note != "" ? "`n" note : "")
	}

;A line under the counts (what was queued, what was done)
SpNote(text)
	{
	SpNoteText := text
	SpStatusShow()
	}

;How many lines that aren't comments a file has (0 if it isn't there)
SpLineCount(file)
	{
	n := 0
	if (!FileExist(file))
		return 0
	Loop, Read, %file%
		if (Trim(A_LoopReadLine) != "" && SubStr(A_LoopReadLine, 1, 1) != ";")
			n += 1
	return n
	}

;A learned spell's name: the one you gave it, else the first words of its text in brackets, else ? (LearnName)
SpName(c)
	{
	if (IsFunc("LearnName"))
		return Func("LearnName").Call(c)
	if (!IsObject(c))
		return "?"
	return c.name != "" ? c.name : c.text != "" ? "(" c.text ")" : "?"
	}

;The Kind column: the kind's label (X-pip ones say so)
SpKindText(c)
	{
	return SpKindLabel(c.type) (SpFlag(c, "xpip") && c.type != "xpip" ? ", X pips" : "")
	}

;The Pips column: ? not known, 3? guessed (not read off the card)
SpPipsText(c)
	{
	if (c.pips = "")
		return "?"
	return c.pips (c.guess ? "?" : "")
	}

;The Value column: its number (a hit's least damage, a heal, a %), with the part over time of a hit that has one
SpValueText(c)
	{
	dot := SpFlag(c, "dot")
	if (c.value = "")
		return (c.type = "" || c.type = "keep" || c.type = "stun" || c.type = "dispel" || c.type = "prism" || c.type = "clear") ? "" : "?"
	return c.value (dot != "" && dot != 1 ? " (+" dot " over time)" : "")
	}

;The In use column: its slot, else why it's kept (LearnInUse: from the catalog alone - never asks the helper)
SpInUse(c)
	{
	if (IsFunc("LearnInUse"))
		return Func("LearnInUse").Call(c)
	return c.slot != "" ? c.slot : "kept"
	}

;yyyyMMddHHmmss as yyyy-MM-dd HH:mm
SpWhen(when)
	{
	if (!RegExMatch(when, "^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)", w))
		return when
	return w1 "-" w2 "-" w3 " " w4 ":" w5
	}

;Learned spell c's flag key (learned\cards.txt's last field, a comma list: ok, tc, hold, out=<id>...): its value
;(out=<id>: the id; one without a value: 1), "" when it hasn't it
SpFlag(c, key)
	{
	if (!IsObject(c))
		return ""
	fl := c.flags
	if (IsObject(fl))
		return fl.HasKey(key) ? (fl[key] = "" ? 1 : fl[key]) : ""
	Loop, Parse, fl, `,
		{
		p := InStr(A_LoopField, "=")
		k := Trim(p ? SubStr(A_LoopField, 1, p - 1) : A_LoopField)
		if (k = key)
			return p ? SubStr(A_LoopField, p + 1) : 1
		}
	return ""
	}

;Its picture: <set>\learned\<id>.card.png (the whole card), else .png - "" when neither is there
SpPicPath(c)
	{
	setDir := A_WorkingDir (c.dir = "" ? "" : "\" c.dir)
	for i, ext in [".card.png", ".png"]
		if (FileExist(setDir "\learned\" c.id ext))
			return setDir "\learned\" c.id ext
	return ""
	}

;What's under the picture: what the learner took it for, its text, when and at what size it was learned, its flags
SpAbout(c)
	{
	desc := SpL("LearnDescribe", c)
	t := SpName(c) (desc != "" ? ": " desc : "")
	t .= "`nText read: " (c.text = "" ? "-" : c.text)
	t .= "`nLearned " SpWhen(c.when) (c.scale != "" ? " at UI " c.scale : "") " (" (c.dir = "" ? "main" : c.dir) ")"
	if (SpFlag(c, "tc"))
		t .= "`nA treasure card"
	if (SpFlag(c, "user"))
		t .= "`nSet by you - the learner leaves it as it is"
	if (SpFlag(c, "hold"))
		t .= "`nNever discarded"
	snap := SpFlag(c, "snap")
	if (snap != "" && snap != 1)
		t .= "`nMade room in hit1-3 - what was there: backups\" snap
	return t
	}

;The picture and what's under it, for the spell selected first
SpPreviewShow()
	{
	ids := SpSelectedIds()
	c := ids.Length() ? SpL("LearnCardOf", ids[1]) : ""
	if (!IsObject(c))
		{
		GuiControl, Dash:Hide, SpPreview
		GuiControl, Dash:, SpPreviewTxt, % ids.Length() ? "" : "Pick a spell to see it."
		return
		}
	pic := SpPicPath(c)
	if (pic != "")
		{
		;(the control is sized for 100% display scaling; the picture is loaded at real pixels - as DashHandCard)
		GuiControl, Dash:, SpPreview, % "*w" Round(140 * A_ScreenDPI / 96) " *h" Round(233 * A_ScreenDPI / 96) " " pic
		GuiControl, Dash:Show, SpPreview
		}
	else
		GuiControl, Dash:Hide, SpPreview
	GuiControl, Dash:, SpPreviewTxt, % SpAbout(c) (ids.Length() > 1 ? "`n(" ids.Length() " selected)" : "")
	}

;The dashboard on the Spells tab (the tray menu's "Learned spells")
SpShowTab()
	{
	if (!DashHwnd)
		return
	if (!DashShown)
		DashToggle()
	;(minimised - put away - it's shown again)
	WinGet, spMinMax, MinMax, ahk_id %DashHwnd%
	if (spMinMax = -1)
		WinRestore, ahk_id %DashHwnd%
	GuiControl, Dash:Choose, DashTabs, 3
	SpDirty := 1
	DashRefresh()
	}

;---- Corrections: queued here, applied by the bot's loop ----

;Queues a correction (op: kind / edit / forget / hold / reload; arg: the new kind, the edit's {name, value, pips},
;never-discard on or off) for spells ids. Nothing in the catalog changes here: the GUI thread can interrupt the
;battle's in the middle of going through it
SpQueue(op, arg, ids)
	{
	if (!IsObject(SpPending))
		SpPending := []
	SpPending.Push({op: op, arg: arg, ids: ids})
	SpNote("Queued: " SpJobText(op, arg, ids) " - the bot applies it as soon as it's out of battle")
	}

;A correction in words
SpJobText(op, arg, ids)
	{
	n := IsObject(ids) ? ids.Length() : 0
	who := n = 1 ? SpName(SpL("LearnCardOf", ids[1])) : n " spells"
	if (op = "kind")
		return who " -> " SpKindLabel(arg)
	if (op = "edit")
		return who " edited"
	if (op = "forget")
		return "forget " who
	if (op = "hold")
		return who (arg ? " never discarded" : " may be discarded again")
	if (op = "reload")
		return "the list read again"
	return op
	}

;The corrections queued on the tab, applied - called by the bot's loop (Autofarmer.ahk, the top of TestRound), out
;of battle only: a hit moved between slots mid-battle would leave the round's enchants and saved pips on the
;wrong card. Each goes through the card learner's own function for it (it saves the catalog, writes PlayerStats.txt,
;moves pictures and tells the vision helper)
SpApplyPending()
	{
	if (!IsObject(SpPending) || !SpPending.Length() || inbattle = 1)
		return
	wasCrit := A_IsCritical
	Critical
	todo := SpPending, SpPending := []
	if (!IsObject(LearnedCards))
		SpL("LearnLoad")
	said := []
	for i, job in todo
		{
		if (job.op = "reload")
			{
			SpL("LearnLoad")
			said.Push("the list read again from learned\cards.txt")
			continue
			}
		for j, id in job.ids
			{
			c := SpL("LearnCardOf", id)
			if (!IsObject(c))
				continue
			who := SpName(c) " (" id ")"
			if (job.op = "kind")
				said.Push(who ": " SpDoKind(c, job.arg))
			else if (job.op = "edit")
				said.Push(who ": " SpCallLearn("LearnEdit", id, job.arg.name, job.arg.value, job.arg.pips))
			else if (job.op = "forget")
				said.Push(who ": " SpCallLearn("LearnForgetById", id))
			else if (job.op = "hold")
				said.Push(who ": " SpDoHold(c, job.arg))
			}
		}
	text := ""
	for i, t in said
		text .= (text = "" ? "" : "; ") t
	if (text = "")
		text := "nothing to change (not in the list any more)"
	DebugLog("Spells: " text)
	SpNoteText := "Done: " text
	SpDirty := 1
	CfgUncritical(wasCrit, 0)
	}

;Kind change (LearnSetKind: out of its slot - a hit that made room for itself puts what it moved back - the new kind,
;marked yours, then the slot it fits now). The kind it has already: only marked yours (so the learner leaves it), its
;slot kept
SpDoKind(c, kind)
	{
	if (kind = c.type)
		{
		SpL("LearnSetFlag", c, "user")
		SpL("LearnSave")
		return "kept as " SpKindLabel(kind) " - marked yours" (c.slot != "" ? ", still in use as " c.slot : "")
		}
	return SpCallLearn("LearnSetKind", c.id, kind)
	}

;Never discard on (holdOn) or off - LearnToggleHold, only when it isn't so already (several picked at once)
SpDoHold(c, holdOn)
	{
	if ((SpFlag(c, "hold") ? 1 : 0) = (holdOn ? 1 : 0))
		return holdOn ? "never discarded already" : "may be discarded already"
	got := SpCallLearn("LearnToggleHold", c.id)
	return got = 1 ? "never discarded" : got = 0 ? "may be discarded again" : got
	}

;fn of the card learner with args - its answer, or why it couldn't be (no such function in CardLearn.ahk)
SpCallLearn(fn, args*)
	{
	if (!IsFunc(fn))
		{
		DebugLog("Spells: CardLearn.ahk has no " fn "() - nothing changed")
		return "not changed (CardLearn.ahk has no " fn ")"
		}
	return Func(fn).Call(args*)
	}

;---- The Edit window ----

;Opens it for the spell selected first (hidden: made but not shown - tests)
SpEditShow(hidden := false)
	{
	ids := SpSelectedIds()
	c := ids.Length() ? SpL("LearnCardOf", ids[1]) : ""
	if (!IsObject(c))
		return SpNote("Pick a spell in the list first")
	if (SpEdHwnd)
		Gui, SpEd:Destroy
	SpEdId := c.id
	Gui, SpEd:New, +OwnerDash +HwndSpEdHwnd -MaximizeBox -MinimizeBox, % "Wizard101 bot " BotVersion() " - edit a learned spell"
	Gui, SpEd:Color, 1B1D22, 111317
	Gui, SpEd:Margin, 12, 10
	Gui, SpEd:Font, s9 w600 c8AB4F8, Segoe UI
	Gui, SpEd:Add, Text, x12 y12 w380 h18, % SpName(c) " - " SpKindLabel(c.type) " (" c.sch ")"
	Gui, SpEd:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, SpEd:Add, Text, x12 y34 w380 h62, % "Text read: " (c.text = "" ? "-" : c.text) "`nThe number: a hit's least damage, a heal's amount, the % of a blade, trap, shield or aura. Blank: not known. What you set is kept - the learner never changes it by itself."
	Gui, SpEd:Font, s9 w400 cDADADA, Segoe UI
	Gui, SpEd:Add, Text, x12 y107 w80 h18, Name
	Gui, SpEd:Add, Text, x12 y137 w80 h18, Number
	Gui, SpEd:Add, Text, x12 y167 w80 h18, Pips
	Gui, SpEd:Font, s9 w400 cF2F2F2, Segoe UI
	Gui, SpEd:Add, Edit, x96 y104 w296 h22 Limit40 vSpEdName, % c.name
	Gui, SpEd:Add, Edit, x96 y134 w80 h22 Number Limit5 vSpEdValue, % c.value
	Gui, SpEd:Add, Edit, x96 y164 w50 h22 Number Limit2 vSpEdPips, % c.pips
	Gui, SpEd:Font, s9 w400 c9AA0A6, Segoe UI
	Gui, SpEd:Add, Text, x156 y167 w236 h18, % c.guess && c.pips != "" ? "(guessed - Save makes it read)" : ""
	Gui, SpEd:Font, s9 w400 cB9E2B9, Segoe UI
	Gui, SpEd:Add, Text, x12 y196 w380 h32 vSpEdNote
	Gui, SpEd:Font, s9 w400 c000000, Segoe UI
	Gui, SpEd:Add, Button, x12 y234 w90 h26 Default gSpEdSave, Save
	Gui, SpEd:Add, Button, x110 y234 w90 h26 gSpEdGuiClose, Close
	;(next to the dashboard when it's up, else in the middle of the screen)
	pos := ""
	if (DashHwnd && DashShown)
		{
		WinGet, mm, MinMax, ahk_id %DashHwnd%
		WinGetPos, dx, dy, , , ahk_id %DashHwnd%
		if (dx != "" && mm != -1)
			pos := "x" dx + 30 " y" dy + 60 " "
		}
	Gui, SpEd:Show, % pos (hidden ? "Hide " : "") "AutoSize", % "Wizard101 bot " BotVersion() " - edit a learned spell"
	}

;Save: what was typed checked, then queued (the window closes); a note in the window when it can't be
SpEdSaveNow()
	{
	Gui, SpEd:Submit, NoHide
	name := Trim(RegExReplace(SpEdName, "[^\x20-\x7E]|\|", "")), value := Trim(SpEdValue), pips := Trim(SpEdPips)
	c := SpL("LearnCardOf", SpEdId)
	if (!IsObject(c))
		return SpEdSay("That spell isn't in the list any more.")
	if (value != "" && !RegExMatch(value, "^\d{1,5}$"))
		return SpEdSay("The number: digits only (or blank: not known).")
	if (pips != "" && !(RegExMatch(pips, "^\d{1,2}$") && pips <= 14))
		return SpEdSay("Pips: 0 to 14 (or blank: not known).")
	if (pips = "" && RegExMatch(c.slot, "\\hit\d$"))
		return SpEdSay("It's used as " c.slot ": a hit there needs its pips.")
	value := value = "" ? "" : value + 0, pips := pips = "" ? "" : pips + 0
	if (name == c.name && value = c.value && pips = c.pips && !(pips != "" && c.guess))
		return SpEdSay("Nothing changed.")
	SpQueue("edit", {name: name, value: value, pips: pips}, [SpEdId])
	Gui, SpEd:Destroy
	SpEdHwnd := 0
	}

SpEdSay(text)
	{
	GuiControl, SpEd:, SpEdNote, %text%
	}

;---- The buttons' other work ----

;The Forget question; Yes queues it
SpForgetAsk()
	{
	ids := SpSelectedIds()
	if (!ids.Length())
		return SpNote("Pick one or more spells in the list first")
	n := ids.Length()
	if (SpAsk("Forget " (n = 1 ? SpName(SpL("LearnCardOf", ids[1])) : n " spells") "? Their pictures go to backups\learned forgotten. A real card is learned again the next time it is in hand - to keep one out of use, change its kind to 'Not used' instead.") != "Yes")
		return
	SpQueue("forget", "", ids)
	}

;A Yes/No question on top of everything ("Yes" / "No"; SpAskAnswer: tests)
SpAsk(text)
	{
	if (SpAskAnswer != "")
		return SpAskAnswer
	MsgBox, 262436, Learned spells, %text%
	IfMsgBox, Yes
		return "Yes"
	return "No"
	}

;Never discard: on for all the selected if any of them hasn't it, else off for all
SpHoldToggle()
	{
	ids := SpSelectedIds()
	if (!ids.Length())
		return SpNote("Pick one or more spells in the list first")
	holdOn := 0
	for i, id in ids
		if (!SpFlag(SpL("LearnCardOf", id), "hold"))
			holdOn := 1
	SpQueue("hold", holdOn, ids)
	}

;The Change kind menu's pick (its position in SpKinds) for the spells selected
SpKindPick(pos)
	{
	ids := SpSelectedIds()
	if (!ids.Length() || !IsObject(SpKinds) || !SpKinds.HasKey(pos))
		return
	SpQueue("kind", SpKinds[pos].kind, ids)
	}

;The picture of the spell selected first, or its folder (learned\ when none is selected)
SpOpenPic(folder)
	{
	ids := SpSelectedIds()
	c := ids.Length() ? SpL("LearnCardOf", ids[1]) : ""
	pic := IsObject(c) ? SpPicPath(c) : ""
	if (folder && pic != "")
		Run, % "explorer.exe /select,""" pic """"
	else if (folder)
		{
		FileCreateDir, %A_WorkingDir%\learned
		Run, % "explorer.exe """ A_WorkingDir "\learned"""
		}
	else if (pic != "")
		Run, % """" pic """"
	else
		SpNote(ids.Length() ? "That spell's picture isn't there any more" : "Pick a spell in the list first")
	}

;The Moved away menu: the folders in backups\ with what was taken out of use - non-cards, forgotten spells, stray
;copies, the hits moved to make room (newest first) - and backups\ itself. Shown when there's anything (show false:
;only made - tests); how many folders it lists
SpMovedMenu(show := true)
	{
	static made := 0
	SpMovedPaths := []
	if (made)
		Menu, SpMovedMenu, DeleteAll
	back := A_WorkingDir "\backups"
	items := []
	for i, f in [["learned junk", "Non-cards taken out of the list"], ["learned forgotten", "Spells you forgot"], ["learned strays", "Stray copies of learned pictures"]]
		if (InStr(FileExist(back "\" f[1]), "D"))
			items.Push([f[2] " (backups\" f[1] ")", back "\" f[1]])
	snaps := ""
	Loop, Files, % back "\hits *", D
		snaps .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"
	Sort, snaps, R
	Loop, Parse, snaps, `n
		{
		if (A_LoopField = "" || A_Index > 10)
			continue
		f := SubStr(A_LoopField, InStr(A_LoopField, "`t") + 1)
		items.Push(["Hits moved to make room: " f, back "\" f])
		}
	if (InStr(FileExist(back), "D"))
		items.Push(["The backups folder", back])
	if (!items.Length())
		{
		SpNote("Nothing has been moved away yet")
		return 0
		}
	for i, it in items
		{
		Menu, SpMovedMenu, Add, % StrReplace(it[1], "&", "and"), SpMovedChosen
		SpMovedPaths.Push(it[2])
		}
	made := 1
	if (show)
		Menu, SpMovedMenu, Show
	return items.Length()
	}

;---- The tab's buttons (labels run in the global scope: Sp-named variables only) ----

SpListEvent:
	if (A_GuiEvent = "I" && InStr(ErrorLevel, "S"))
		SetTimer, SpPreviewTick, -60
	else if (A_GuiEvent = "DoubleClick" && A_EventInfo)
		SpOpenPic(false)
	return

;(after a moment: a select-all doesn't load the picture once per row)
SpPreviewTick:
	SpPreviewShow()
	return

SpKindClick:
	if (!SpSelectedIds().Length())
		SpNote("Pick one or more spells in the list first")
	else
		Menu, SpKindMenu, Show
	return

SpKindChosen:
	SpKindPick(A_ThisMenuItemPos)
	return

SpEditClick:
	SpEditShow()
	return

SpEdSave:
	SpEdSaveNow()
	return

SpEdGuiClose:
SpEdGuiEscape:
	Gui, SpEd:Destroy
	SpEdHwnd := 0
	return

SpForgetClick:
	SpForgetAsk()
	return

SpHoldClick:
	SpHoldToggle()
	return

SpPicClick:
	SpOpenPic(false)
	return

SpFolderClick:
	SpOpenPic(true)
	return

SpMovedClick:
	SpMovedMenu()
	return

SpMovedChosen:
	if (IsObject(SpMovedPaths) && SpMovedPaths.HasKey(A_ThisMenuItemPos))
		Run, % "explorer.exe """ SpMovedPaths[A_ThisMenuItemPos] """"
	return

;(learned\cards.txt read again - by the bot's loop, out of battle - and the list filled now)
SpRefreshClick:
	SpQueue("reload", "", [])
	SpListFill()
	return
