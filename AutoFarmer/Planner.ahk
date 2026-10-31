; Planner.ahk - the round planner's AutoHotkey side (TODO goal 3, step 3 of learned battle play): in a round the bot plays
; itself - after the kill check, defending and the heals, before the traps, blades and hits (Autofarmer.ahk's battle
; loop: one call, PlannerRound) - the vision helper is asked which card it would play (/plan - vision\vision.py
; plan_lines_for, vision\battlesim.py plan_round): every card in hand that can go now, and a pass, tried in the battle
; simulator from this very round on - your hand, pips and health from the game's memory, the enemies' health (memory),
; the blades, traps and aura the bot counts (KillCalc.ahk AppliedBlades, BossTraps, AuraRounds), the worn deck less the
; hand as the draw pile, the rest of the battle played your settings' way; learned plays (vision\battlelearn.py, from the
; battles recorded) only nudge near-equal plays.
; AutoHotkey v2, written for v2 (v1 never had this: nothing here is ported); #Included by Autofarmer.ahk only.
;
; Setting (PlayerStats.txt, the Settings window's HOW IT PLAYS ITS CARDS): planner - 0 off (the default: nothing asked,
; nothing new runs in a round), 1 advise: the advice logged -
;   "  Plan: would play Tempest on all (won 92% in 3 rounds, 100 tries; ends it this round in 40%) - your settings' way:
;   Stormblade on you (won 85%) [tid 1234] - advice only (planner:1, 340 ms)"
; - a line of the round, so the battle recorder keeps it with what was played (python vision\battlelearn.py --advice: how
; often the bot's card was the one advised, and how those battles went). The bot then plays its own way, as ever: the
; planner never clicks, never changes a play and never sets a global the round reads. 2 play: NOT BUILT (PlannerRound's
; TODO) - read as 1, said once.
; Not asked (said once a battle): in dual mode, the helper not running, navmem off, learning every card, after you took a
; round of this battle (PlayerTookRound: the bot's count of the blades and traps on isn't sure), a party battle's blader
; or healer (its advice needs the hitter's hand - the leader's orders, not built), no school known (hitter 0). Once a
; round at most (the log's round and the bot's); the helper keeps to 300 ms (budget=, the game's reads included), the
; bot waits 1.5 s at most - a slow or missing answer is never counted against the helper (VisionGet's noCount).
; A party battle (v0.9.0, the team model - advice only, as the rest): the party's other wizards on your side go with the
; question (mates=: each one's seat, school, health and battle role from the party's state - PlannerMates; their hands
; aren't known: a hitter is played as the generic hitter, a blader or healer as doing nothing), your seat, and
; charms=log: the blades, traps and shields on you and the enemies from the game's log (the party's and the enemies'
; too - vision\battlerec.py charms_now) instead of the bot's own count.

;(v2-only globals - declared here with no value: a top-level := in an #Included file never runs - PlannerBlank sets
;them blank, the entry script calls it first thing) The round last asked about (duel|log round|bot round); the last
;advice logged; answers missed in a row; the reason it wasn't asked last said (once a battle) / the mode-2 notice said
global PlannerAsked, PlannerLast, PlannerFails, PlannerSaid

;(v2 port, CONVENTIONS.md "Blank start": this file's globals start blank)
PlannerBlank()
	{
	global PlannerAsked := "", PlannerLast := "", PlannerFails := "", PlannerSaid := ""
	}

;The setting: 0 off, 1 advise (2 play isn't built: read as 1). Never throws
PlannerMode()
	{
	plmM := 0
	try plmM := StatOr("planner", 0)
	return (V1IsNum(plmM) && plmM >= 1) ? 1 : 0
	}

;Whether this round is asked about: the setting on and nothing ruling it out - why: what does ("" none, or the setting off)
PlannerOn(&why := "")
	{
	why := ""
	if (!PlannerMode())
		return false
	try
		{
		if (dualmode == 1)
			why := "dual mode (the game's memory is one client's)"
		else if (!VisionOn)
			why := "the vision helper isn't running"
		else if (!Stat("navmem"))
			why := "navmem:0 in PlayerStats.txt"
		else if (LearnAll)
			why := "learning every card"
		else if (PlayerTookRound)
			why := "you played a round of this battle (the blades and traps on aren't sure)"
		else if (PartySupport())
			why := "a party battle's " BattleRole " (the simulator plays one wizard)"
		else if (!hitter)
			why := "no school known"
		}
	catch
		why := "not ready"
	return why = ""
	}

;The round's advice (the battle loop, after the healer's Tower Shield and before TrapWhere - planner 1): /plan asked once
;a round, its best play logged with your settings' own pick (the simulator's chain) and the time it took - the round then
;goes on exactly as without it. False: nothing cast (always, in this version - planner 2 isn't built)
PlannerRound()
	{
	global PlannerAsked, PlannerLast, PlannerFails, PlannerSaid ; (globals it sets)
	try
		{
		if (!PlannerOn(&plrWhy))
			{
			;(why not, said once a battle while it holds - nothing at all with planner 0)
			if (plrWhy != "" && PlannerSaid != BlDuel "|" plrWhy)
				PlannerSaid := BlDuel "|" plrWhy, DebugLog("  Plan: not asked - " plrWhy)
			return false
			}
		plrKey := BlDuel "|" BlRound "|" roundnumber
		if (plrKey == PlannerAsked)
			return false
		PlannerAsked := plrKey
		if (StatOr("planner", 0) >= 2 && PlannerSaid != "mode2")
			PlannerSaid := "mode2", DebugLog("  Plan: planner:" StatOr("planner", 0) " (play) isn't built yet - advice only")
		plrAt := A_TickCount
		plrAns := VisionGet(PlannerQuery(), 1500, true)
		plrMs := A_TickCount - plrAt
		if (plrAns = "" || SubStr(plrAns, 1, 5) = "none|")
			{
			PlannerFails := V1N(PlannerFails) + 1
			DebugLog("  Plan: no advice (" plrMs " ms) - " (plrAns != "" ? SubStr(Trim(plrAns, " `r`n"), 6, 160) : VisionErr != "" ? VisionErr : "no answer"))
			return false
			}
		PlannerFails := 0
		PlannerLast := PlannerText(plrAns, plrMs)
		DebugLog("  " PlannerLast)
		}
	catch Any as e
		{
		try DebugLog("  Plan: failed - " (IsObject(e) ? e.Message : e) " (the round goes on as ever)")
		}
	;TODO(planner:2, play - needs the game): cast the advised card here and return true (the battle loop then goes to
	;EndRound), only once (1) a card can be cast by the game's memory - its place in the hand: plan| field 2 (i, 0 the
	;leftmost; -1 a pass), field 3 (its slot: Card1-7 / PetCard) and field 4 (its template id), matched to VisionCards'
	;cards (the pattern of Autofarmer.ahk CastLearnedHit / UseMemAt) - and (2) its target's plate is known: plan| field 6
	;is the enemy's index in the answer's foe| lines (the game's memory's order; foe| field 7 its plate's middle across
	;the client, 0-1) - how those map to EnemyPlates hasn't been checked in the game. A hit whose tid is a slot's
	;(hit1-4) through UseHit, a blade / trap through UseBlade / UseTrap with their KeyFlags (the used flags; BoostRun++),
	;a heal through UseHeal, a pass ClickPass; a cast that fails falls through to the chain. Then Settings.ahk's planner
	;entry offers 2, and battlerec.py's 'planner' rule (a line "  planner: <card> cast at ...") names those rounds
	return false
	}

;The /plan query: your school, the deck in use's in-game deck (its gid - the worn one when not linked), the log's round,
;the bot's own count of the blades on you (AppliedBlades), the traps on one enemy (BossTraps: on the boss picked - its
;most health BossMax -, else the one whose most health was TrapFoeMax), the aura (AuraRounds left, AuraSch, aura %), the
;boosts since your last hit (BoostRun), your stats for that school and the settings - Decks.ahk DeckBeat's way
;(DeckStatFor, DeckKeys); a boss picked: boss=1
PlannerQuery()
	{
	plqD := IsObject(DeckNow) ? DeckNow : ""
	plqSch := hitschool
	plqQ := "/plan?school=" plqSch "&round=" V1Add(BlRound, 1) "&boostrun=" V1N(BoostRun) "&budget=300&n=100"
	plqG := IsObject(plqD) ? V1At(plqD, "game") : ""
	if (plqG != "")
		plqQ .= "&deck=" plqG
	plqB := PlannerBoosts(AppliedBlades)
	if (plqB != "")
		plqQ .= "&blades=" NavUri(plqB)
	plqT := PlannerBoosts(BossTraps)
	if (plqT != "")
		plqQ .= "&traps=" NavUri(plqT) "&trapmax=" ((BossChoosen == 1) ? V1N(BossMax) : V1N(TrapFoeMax))
	if (V1N(AuraRounds) > 0 && BoostSchools("aura") != "")
		plqQ .= "&aura=" NavUri(BoostSchools("aura") "~" Stat("aura") "~" AuraRounds)
	if (BossChoosen == 1)
		plqQ .= "&boss=1"
	;(a party battle - the team model: the party's other wizards on your side, your seat, the charms from the game's log)
	if (BattleTeam() >= 2)
		{
		plqM := PlannerMates()
		if (plqM != "")
			plqQ .= "&mates=" NavUri(plqM)
		plqS := V1IsFunc("PartySeat") ? PartySeat.Call() : ""
		if (plqS != "")
			plqQ .= "&seat=" plqS
		plqQ .= "&charms=log"
		}
	plqVals := ""
	for plqI, plqK in DeckKeys()
		{
		plqV := DeckStatFor(plqD, plqSch, plqK)
		if (plqV != "" && ((IsObject(plqD) && IsObject(V1At(plqD, "vals")) && plqD.vals.Has(plqK)) || Stats.Has(plqK) || (plqSch != "" && Stats.Has(plqSch "." plqK))))
			plqVals .= (plqVals = "" ? "" : ",") plqK ":" plqV
		}
	plqQ .= "&vals=" NavUri(plqVals)
	for plqI, plqK in [["damage", "damage"], ["pierce", "pierce"], ["crit", "critical"], ["block", "block"], ["acc", "accuracy"]]
		{
		plqV := DeckStatFor(plqD, plqSch, plqK[2])
		if (plqV != "" && plqV != 0)
			plqQ .= "&" plqK[1] "=" NavUri(plqV "")
		}
	return plqQ
	}

;The party's other wizards on your side of this battle as /plan's mates= takes them: name~seat~school~hp~max~role~~~|...
;(up to 3) - each a party member (the leader, the followers: Party.ahk's state, heard from in the last 5 s, in battle)
;whose wizard's name is one of your side's in the game's log (its seat: that subcircle; not yours, no two so named);
;its health as the party says it (a %) out of your own most (OwnHpMax - its own most isn't sent), its role its battle
;part (partybattle). No hand: the helper plays it its role's way. "" none
PlannerMates()
	{
	plmOut := "", plmN := 0
	if (!IsObject(BlNames) || !V1IsFunc("PartyKey"))
		return ""
	plmMe := PartyKey.Call(OwnName())
	plmAll := []
	if (IsObject(PartyLeader))
		plmAll.Push(PartyLeader)
	if (IsObject(PartyMembers))
		for plmI, plmP in PartyMembers
			plmAll.Push(plmP)
	for plmI, plmP in plmAll
		{
		plmK := PartyKey.Call(plmP.wiz)
		if (plmP.age = "" || plmP.age > 5000 || plmP.battle != 1 || StrLen(plmK) < 3 || plmK = plmMe)
			continue
		plmSeat := "", plmTwice := 0
		Loop 4
			if (BlNames.Has(A_Index + 3) && PartyKey.Call(BlNames[A_Index + 3]) = plmK)
				plmTwice += plmSeat != "" ? 1 : 0, plmSeat := A_Index + 3
		if (plmSeat = "" || plmTwice)
			continue
		plmMax := V1N(OwnHpMax) > 0 ? OwnHpMax : 3000
		plmHp := V1IsNum(plmP.hp) ? Round(plmMax * plmP.hp / 100) : ""
		plmOut .= (plmOut = "" ? "" : "|") RegExReplace(plmP.wiz, "[~|]", " ") "~" plmSeat "~" plmP.school "~" plmHp "~" plmMax "~" plmP.brole "~~~"
		if (++plmN >= 3)
			break
		}
	return plmOut
	}

;A boost list (AppliedBlades / BossTraps: {key: %}) as /plan takes it: key~schools~%|... - each key's schools as the kill
;check counts them (KillCalc.ahk BoostSchools: "all", "fire,ice,storm"); a key whose schools aren't known left out. The
;helper names a blade's plain key ("storm/blade", "blade3") as the card in hand or in the deck that boosts the same
;schools (vision\battlesim.py bot_blades), so another copy of it in hand counts as on already - never tried or stacked,
;as UseBlade's used flags never cast it; a sharpened ("+") or treasure / item card's copy ("@tc", "@item") keeps its
;key and stacks with the deck's, as AddBoost counts it
PlannerBoosts(list)
	{
	plbOut := ""
	if (!IsObject(list))
		return ""
	for plbK, plbP in list
		{
		plbS := BoostSchools(plbK)
		if (plbS = "" || !V1IsNum(plbP) || plbP <= 0)
			continue
		plbOut .= (plbOut = "" ? "" : "|") StrReplace(StrReplace(plbK, "|", " "), "~", " ") "~" plbS "~" plbP
		}
	return plbOut
	}

;The advice as logged (/plan's plan| line, the chain| line when your settings' own pick differs, learned|, planned|):
;"Plan: would play <card> at <enemy> / on all / on you (won N% in R rounds, n tries; why) - your settings' way: <card>
;(won M%) [tid T] - advice only (planner:1, ms)" (+ the learned plays' why). battlelearn.py's ADVICE_RX reads it back
PlannerText(ans, ms)
	{
	pltBest := "", pltChain := "", pltLearn := ""
	Loop Parse, ans, "`n", "`r"
		{
		pltF := StrSplit(A_LoopField, "|")
		pltTag := V1At(pltF, 1)
		if (pltTag = "plan" && pltF.Length >= 15)
			pltBest := pltF
		else if (pltTag = "chain" && pltF.Length >= 15)
			pltChain := pltF
		else if (pltTag = "learned")
			pltLearn := SubStr(A_LoopField, 9)
		}
	if (!IsObject(pltBest))
		return "Plan: an odd answer - " SubStr(RegExReplace(ans, "\s+", " "), 1, 120)
	pltT := "Plan: would play " pltBest[11] PlannerAt(pltBest) " (won " pltBest[7] "%" (pltBest[8] != "" ? " in " pltBest[8] " rounds" : "") ", " pltBest[13] " tries; " pltBest[10] ")"
	if (IsObject(pltChain))
		pltT .= " - your settings' way: " pltChain[11] PlannerAt(pltChain) " (won " pltChain[7] "%)"
	if (pltBest[4] != "")
		pltT .= " [tid " pltBest[4] "]"
	pltT .= " - advice only (planner:1, " ms " ms)"
	if (pltLearn != "")
		pltT .= " - " SubStr(pltLearn, 1, 150)
	return pltT
	}

;" at <enemy>" / " on all" / " on you" of a plan| / chain| line's target ("" a pass)
PlannerAt(f)
	{
	if (f[6] = "all")
		return " on all"
	if (f[6] != "")
		return " at " f[12]
	return (f[12] = "me") ? " on you" : ""
	}
