; EnemySpells.ahk - what each enemy will likely cast this round, and defending first when their hits could kill the
; wizard. AHK v1.1, functions only; #Included by Autofarmer.ahk.
;
; Who's fighting and what each cast: the game's own log (Bin\WizardClient.log - read only, the file Reconnect.ahk reads
; too, RcLog). Each planning phase names every slot ("CombatPlanningP Subcircle 1", then "MINION
; CombatantDataControlSmall, name:Ahnic Strider" - slots 0-3 the enemies, 4-7 your side), and each round each caster's
; spell ("CombatResolver::ResolveCombatRound. Duel ID:.. Round:3 Caster:1 Spell:Dark Sprite" - None: it passed); a new
; "Duel N: MSG_CombatPhase(...)" number is a new battle. Each enemy cast is counted for its creature (the vision helper's
; /enemyseen - wiki\casts.json), so the odds sharpen with every battle.
;
; The odds (the helper's /enemies - vision\enemies.py): each creature's spells off the Fandom wiki, its pips estimated by
; the round, the casts so far. Each round: logged ("  enemy spells: ...") and shown on the dashboard (WHAT IT SEES:
; Threat). Defending (EnemyDefend): when the chance this round's enemy hits kill the wizard is defendat % or more and no
; hit in hand kills them all (the kill check runs first) - a heal, else Tower Shield, before anything else.

;The battle log: where it was read to, its first line (a new log: from the top), the battle (its duel number), each
;slot's name ({slot: name}), the slot a name line is for, the casts ([{round, slot, spell}]), the last round resolved,
;when it was last read
global BlPos, BlHead, BlDuel, BlNames, BlSub, BlCasts, BlRound, BlReadAt
;Your own wizard's name: the one wizard on your side of a battle with no other (learned this run - party.ini [me] keeps
;the last for the next)
global BlMe
;Your own health as last read (OwnHealthLow): now, most, when, how many of its 4 reads agreed
global OwnHpCur, OwnHpMax, OwnHpAt, OwnHpVotes, OwnHpWin
;This round's prediction (EnemyDanger): the chance their hits kill the wizard (0-1, "" unknown), for the round
global EnemyLethal, EnemyLethalRound

;What the game's log has said since the last read - at most every 500 ms (force: now). The first read starts at its end:
;only what happens from now on (a battle going on is picked up at its next planning phase, which names every slot)
BattleLogRead(force := false)
	{
	if (!force && BlReadAt && A_TickCount - BlReadAt < 500)
		return
	BlReadAt := A_TickCount
	if (RcLog = "" || !FileExist(RcLog))
		return
	blFile := FileOpen(RcLog, "r", "CP0")
	if (!IsObject(blFile))
		return
	blSize := blFile.Length
	blTop := blFile.Read(17)
	if (BlHead = "")
		{
		BlHead := blTop, BlPos := blSize
		blFile.Close()
		return
		}
	;(a new log - the game restarted: from its top)
	if (blTop != BlHead || blSize < BlPos)
		BlHead := blTop, BlPos := 0
	if (blSize - BlPos > 1048576)
		BlPos := blSize - 1048576
	if (blSize <= BlPos)
		{
		blFile.Close()
		return
		}
	blFile.Pos := BlPos
	blChunk := blFile.Read(blSize - BlPos)
	blFile.Close()
	;(a line still being written is read next time)
	blNl := InStr(blChunk, "`n", false, 0)
	if (!blNl)
		return
	blChunk := SubStr(blChunk, 1, blNl)
	BlPos += StrLen(blChunk)
	Loop, Parse, blChunk, `n, `r
		BattleLogLine(A_LoopField)
	}

;One line of the game's log, for the battle
BattleLogLine(blLine)
	{
	if (!InStr(blLine, "Combat") && !InStr(blLine, "Subcircle"))
		return
	if (RegExMatch(blLine, "Duel (\d+): MSG_CombatPhase\((kPhase_\w+)\)", blM))
		{
		if (blM1 != BlDuel)
			BlDuel := blM1, BlNames := {}, BlCasts := [], BlRound := 0, BlSub := ""
		;(each planning phase names those still in the circle - one that died isn't: the names afresh)
		else if (blM2 = "kPhase_Planning")
			BlNames := {}, BlSub := ""
		;(the planning over: one wizard on your side - that's you)
		else if (blM2 = "kPhase_Execution" && IsObject(BlNames))
			{
			blOne := "", blN := 0
			Loop, 4
				if (BlNames.HasKey(A_Index + 3))
					blN += 1, blOne := BlNames[A_Index + 3]
			if (blN = 1 && blOne != "" && blOne != BlMe)
				{
				BlMe := blOne
				IniWrite, %blOne%, %A_ScriptDir%\party.ini, me, name
				DebugLog("Battle log: this wizard is " blOne " (the only one on your side)")
				}
			}
		return
		}
	if (RegExMatch(blLine, "CombatPlanningP\s+Subcircle (\d+)\s*$", blM))
		{
		BlSub := blM1 + 0
		return
		}
	if (BlSub != "" && RegExMatch(blLine, "CombatantDataControl(?:Small)?, name:(.*?)\s*$", blM))
		{
		if (!IsObject(BlNames))
			BlNames := {}
		BlNames[BlSub] := blM1, BlSub := ""
		return
		}
	if (RegExMatch(blLine, "ResolveCombatRound\. Duel ID:\d+ Round:(\d+) Caster:(\d+) Spell:(.*?)\s*$", blM))
		{
		if (!IsObject(BlCasts))
			BlCasts := []
		blSlot := blM2 + 0, blRnd := blM1 + 0
		;(a second line for the same caster in a round - a pet's may-cast - isn't the enemy's own choice)
		for each, blC in BlCasts
			if (blC.round = blRnd && blC.slot = blSlot)
				return
		BlCasts.Push({round: blRnd, slot: blSlot, spell: blM3})
		BlRound := Max(BlRound ? BlRound : 0, blRnd)
		;(an enemy's: counted for its creature - the odds learn)
		if (blSlot <= 3 && IsObject(BlNames) && BlNames.HasKey(blSlot) && VisionOn)
			VisionGet("/enemyseen?name=" NavUri(BlNames[blSlot]) "&spell=" NavUri(blM3) "&round=" blRnd, 600, true)
		}
	}

;How many wizards are on your side of this battle (the game's log; 0 not known)
BattleTeam()
	{
	n := 0
	if (IsObject(BlNames))
		Loop, 4
			n += BlNames.HasKey(A_Index + 3) ? 1 : 0
	return n
	}

;Your own wizard's name: learned from a battle with no other wizard on your side (this run, else the last one kept in
;party.ini), else the party name typed in (Party...); "" none
OwnName()
	{
	if (BlMe != "")
		return BlMe
	IniRead, n, %A_ScriptDir%\party.ini, me, name, %A_Space%
	if (Trim(n) = "")
		IniRead, n, %A_ScriptDir%\party.ini, party, name, %A_Space%
	return Trim(n)
	}

;Your plate when more than one wizard is on your side: the name pictures (player.png...) would find whichever of your
;wizards' plates comes first - so the plates' names along the bottom are read (OCR) and yours (OwnName) picked. x, y:
;where its name starts (as the name picture's match would be). False: not a team battle, no name known, or not read
PlayerPlateByName(ByRef x, ByRef y)
	{
	if (BattleTeam() < 2)
		return false
	ppMe := OwnName()
	if (ppMe = "" || !IsFunc("WalkLetters"))
		return false
	ppKey := Func("WalkLetters").Call(ppMe)
	if (StrLen(ppKey) < 3)
		return false
	ppT := OcrRect(GameLeft, Round(GameTop + GameH * 0.8), GameW, Round(GameH * 0.2), "en", 2, ppLines)
	if (ErrorLevel || !IsObject(ppLines))
		return false
	for each, ppLine in ppLines
		for each, ppW in ppLine.words
			{
			ppWk := Func("WalkLetters").Call(ppW.text)
			if (StrLen(ppWk) >= 3 && (ppWk = ppKey || (IsFunc("WalkNameLike") && Func("WalkNameLike").Call(ppWk, ppKey))))
				{
				x := ppW.x, y := ppW.y
				DebugLog("  your plate by its name (" ppMe ", a battle with " BattleTeam() " of you) at " x - GameLeft "," y - GameTop)
				return true
				}
			}
	DebugLog("  " ppMe "'s plate not read among " BattleTeam() " wizards on your side - the name pictures instead")
	return false
	}

;This round's odds - the enemies' likely spells and the chance their hits kill the wizard: logged, on the dashboard
;(Threat), EnemyLethal. True if that chance is defendat % or more. Needs the battle log (the game's), the vision helper
;and your own health (read here if this round hasn't yet)
EnemyDanger()
	{
	EnemyLethal := "", EnemyLethalRound := roundnumber
	if (!Stat("enemyspells") || !VisionOn)
		return false
	BattleLogRead(true)
	edNames := "", edSlots := [], edTeam := 0
	if (!IsObject(BlNames))
		return false
	Loop, 4
		{
		edS := A_Index - 1
		if (BlNames.HasKey(edS))
			edNames .= (edNames = "" ? "" : "|") NavUri(BlNames[edS]), edSlots.Push(edS)
		}
	Loop, 4
		if (BlNames.HasKey(A_Index + 3))
			edTeam += 1
	if (!edSlots.Length())
		return false
	;(your health: read this round already - the heal check - or now, quietly)
	if (!(OwnHpCur != "" && OwnHpRound = roundnumber && A_TickCount - OwnHpAt < 20000 && OwnHpWin = WinExist("A")) && playerX != "")
		OwnHealthLow(true)
	edHealth := (OwnHpCur != "" && OwnHpRound = roundnumber && OwnHpWin = WinExist("A")) ? OwnHpCur : ""
	;(a low reading only 2 of its 4 reads agreed on - 775 read as 75 - isn't trusted: as for a heal)
	if (edHealth != "" && OwnHpVotes < 3 && 100 * OwnHpCur / OwnHpMax < (Stats.HasKey("healat") ? Stats["healat"] : 40))
		edHealth := ""
	;(the casts so far: round:enemy index (its place among the enemies):spell)
	edHist := ""
	for each, edC in BlCasts
		for edI, edS in edSlots
			if (edC.slot = edS)
				edHist .= (edHist = "" ? "" : "|") edC.round ":" (edI - 1) ":" NavUri(edC.spell)
	edAns := VisionGet("/enemies?names=" edNames "&round=" BlRound + 1 "&health=" edHealth "&team=" Max(1, edTeam) "&hist=" edHist, 1500, true)
	if (edAns = "")
		return false
	edText := "", edDash := "", edLethal := ""
	Loop, Parse, edAns, `n, `r
		{
		edF := StrSplit(A_LoopField, "|")
		if (edF[1] = "lethal")
			edLethal := edF[2]
		if (edF[1] != "enemy")
			continue
		edTop := ""
		for each, edT in StrSplit(edF[8], ";")
			{
			edP := StrSplit(edT, ":")
			if (edP[1] != "" && A_Index <= 3)
				edTop .= (edTop = "" ? "" : ", ") edP[1] " " Round(edP[2] * 100) "%"
			}
		edWhat := edF[4] = "pending" ? "looking it up on the wiki" : edF[4] = "missing" ? "not on the wiki" : edTop
		edText .= (edText = "" ? "" : " | ") edF[3] " (~" Round(edF[5]) " pips): " edWhat
		edDash .= (edDash = "" ? "" : " | ") edF[3] ": " (edF[4] = "ok" ? StrSplit(edTop, ",")[1] : edWhat)
		}
	EnemyLethal := edLethal
	edRisk := edLethal = "" ? "your health unknown" : Round(edLethal * 100) "% chance their hits kill you this round"
	DebugLog("  enemy spells: " edText " - " edRisk)
	if (IsFunc("DashSee"))
		Func("DashSee").Call("threat", edDash (edLethal = "" ? "" : " - " Round(edLethal * 100) "% lethal"))
	edAt := Stat("defendat")
	return edLethal != "" && edAt > 0 && edLethal * 100 >= edAt
	}

;Defending first (EnemyDanger said so): a heal on yourself (heal1, heal2), else Tower Shield (resources\tower, usetower
;on). True if one went out
EnemyDefend()
	{
	global
	local edWhy
	edWhy := "  defending: " Round(EnemyLethal * 100) "% chance this round's enemy hits kill you"
	;(a heal only with health to restore - at full, Tower Shield)
	if ((heal1 == 1 || heal2 == 1) && OwnHpCur != "" && OwnHpCur < OwnHpMax * 0.9)
		{
		DebugLog(edWhy " - a heal first")
		if (heal1 == 1) && UseHeal("heal1", heal1, hitschool)
			return true
		if (heal2 == 1) && UseHeal("heal2", heal2, hitschool)
			return true
		}
	if (tower == 1 && Stat("usetower"))
		{
		DebugLog(edWhy " - Tower Shield first")
		UseOnSelf("tower", tower, "resources")
		if (tower == 1 && CastWentOut())
			{
			if (IsFunc("DashCast"))
				Func("DashCast").Call("tower")
			return true
			}
		}
	DebugLog(edWhy " - nothing to heal or shield with in hand")
	return false
	}
