; Party.ahk - a party of up to 4 wizards, one per PC on the same home network (TODO goal 1, phase 1). AHK v1.1,
; functions and labels only; #Included by Autofarmer.ahk.
;
; Settings (PARTY): partyrole - Off, Leader (quests as now; waits while a follower is far, in another zone or not ready -
; partywaitdist, partywaitmax) or Follower (goes where the leader goes - partynear - instead of following its own quest
; arrow; into the leader's battles; through the door the leader took). The party's port: partyport. This wizard's party
; name and (a follower) the leader PC's address: the tray menu's Party... (party.ini - not secret: a name, an address).
;
; The vision helper does the talking (vision\party.py): every half second PartyTick tells it this bot's state (/party)
; and gets the party back - the leader's place, door and battle spot; the followers'; each one's battle part
; (partybattle), wizard's name, school and hits. State only: nothing one bot sends can make another press anything -
; a blader's or healer's boosts go to the party's hitter's plate, found on its own screen by the name the game's log
; gives for its own side. Phase 2 (teleport to friend across zones) isn't in yet: a follower whose leader went where it
; can't follow waits, and says so.
;
; Battle roles (phase 3 - Settings: partybattle): with more than one wizard on your side, a Blader puts its blades on the
; hitter (the wizard set to Hitter - the leader's first -, else the leader), its traps on the enemy the hitter goes for,
; casts them again after each of the hitter's hits, Tower Shield on it, and hits only for a kill or with nothing else to
; do; a Healer heals the one of you lowest under healat %, shields them, else boosts as a blader. Anything not sure (no
; party state, the hitter not on your side, its plate not read): this wizard hits, as ever.

;The party as last heard: the role, the helper's state (off/serving/following/unreachable/error) and why; this wizard
;({zone, x, y, z, yaw}); the leader (a follower's view: {name, zone, x, y, z, yaw, battle, hp, ready, walk, age, dist,
;dzone, dx, dy, dz, ddx, ddy, dto, bx, by, bz, hold}); the followers ([{name, zone, x, y, z, battle, hp, ready, age, dist,
;walk, loading, hold}]); when it was last asked
global PartyRole, PartyState, PartyWhy, PartyMe, PartyLeader, PartyMembers, PartyAskAt
;The leader's hold: why it's holding now, since when each follower's been held for ({name: tick}), the ones not waited
;for any more until they've been near ({name: 1})
global PartyHolding, PartyHeldFrom, PartySkip
;The follower: what it walks to now ({x, y, z, kind}), when its own place last moved, and the stuck tries
global PartyTgt, PartyStillAt, PartyStillX, PartyStillY, PartyTries, PartyPushUntil, PartyNear

;The role set in Settings: "off", "leader" or "follower"
PartyRoleSet()
	{
	r := Stat("partyrole")
	return r = 2 ? "leader" : r = 3 ? "follower" : "off"
	}

;A follower, on (the walking dispatch: PartyFollowStep instead of the quest's WalkStep)
PartyFollowing()
	{
	return PartyRoleSet() = "follower"
	}

;This PC's party name and (a follower) the leader's address: party.ini
PartyIni(key)
	{
	IniRead, v, %A_ScriptDir%\party.ini, party, %key%, %A_Space%
	return Trim(v)
	}

;Every half second (a timer - on through battle rounds too): this bot's state to the helper, the party back
PartyTick()
	{
	static schoolAskAt := 0, schoolChar := ""
	role := PartyRoleSet()
	if (role = "off" && PartyRole = "off")
		return
	if (!VisionOn || !IsFunc("VisionGet"))
		return
	;(your health only as read this battle round - out of battle it's set to 0, before the first read it's blank)
	hp := (inbattle = 1 && OwnHpAt != "" && OwnHpRound = roundnumber && A_TickCount - OwnHpAt < 30000) ? OwnHpPct : ""
	;(your school for the party: off your plate - else the one this character fought as before, looked for once in 20 s)
	if (A_TickCount - schoolAskAt > 20000)
		{
		schoolAskAt := A_TickCount, psChar := StatsCharID()
		;(another character logged in: its school)
		if (PartyMySchool = "" || (psChar != "" && psChar != schoolChar))
			schoolChar := psChar, PartyMySchool := StatsSchoolOf(psChar)
		}
	;(not while it's quick selling the backpack - QuickSell.ahk: a leader waits for a follower that is)
	ready := BotOn && Walking && !PlayerActive && GameActive() && !PotionResting && !QsBusy ? 1 : 0
	;(plan: the hitter's planned hit's schools - a support boosts for them; lasthit: its last hit's - a support's blades that
	;fit none of those stay on it - KillCalc.ahk BoostPick, ConsumeBoosts)
	q := "/party?role=" role "&name=" NavUri(PartyIni("name")) "&leader=" NavUri(PartyIni("leader"))
		. "&port=" Stat("partyport") "&battle=" (inbattle = 1 ? 1 : 0) "&hp=" hp "&ready=" ready "&walk=" (Walking ? 1 : 0)
		. "&bot=" (BotOn ? 1 : 0) "&loading=" (WkLoading ? 1 : 0) "&hold=" NavUri(SubStr(PartyHolding, 1, 80))
		. "&brole=" PartyBattleSet() "&wiz=" NavUri(OwnName()) "&school=" PartyMySchool "&hits=" (PartyHits ? PartyHits : 0) "&hitr=" (PartyHitR ? PartyHitR : 0)
		. "&plan=" NavUri(PartySupport() ? "" : PlanList) "&lasthit=" NavUri(PartyLastSch)
	ans := VisionGet(q, 600, true)
	PartyAskAt := A_TickCount
	if (ans = "")
		{
		;(nothing heard: the party as last heard isn't kept - a support would go on boosting a hitter not heard from)
		PartyState := "error", PartyWhy := "the vision helper didn't answer", PartyLeader := "", PartyMembers := []
		return
		}
	members := []
	leader := ""
	Loop, Parse, ans, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "party")
			{
			if (PartyRole != f[2] || PartyState != f[3])
				DebugLog("Party: " f[2] " - " f[3] (f[4] != "" ? " (" f[4] ")" : ""))
			PartyRole := f[2], PartyState := f[3], PartyWhy := f[4]
			}
		else if (f[1] = "me")
			PartyMe := {zone: f[2], x: f[3], y: f[4], z: f[5], yaw: f[6]}
		else if (f[1] = "leader")
			leader := {name: f[2], zone: f[3], x: f[4], y: f[5], z: f[6], yaw: f[7], battle: f[8], hp: f[9], ready: f[10]
				, walk: f[11], age: f[12], dist: f[13], dzone: f[14], dx: f[15], dy: f[16], dz: f[17], ddx: f[18], ddy: f[19]
				, dto: f[20], bx: f[21], by: f[22], bz: f[23], hold: f[24], brole: f[25], wiz: f[26], school: f[27], hits: f[28], hitr: f[29]
				, plan: f[30], lasthit: f[31]}
		else if (f[1] = "member")
			members.Push({name: f[2], zone: f[3], x: f[4], y: f[5], z: f[6], battle: f[7], hp: f[8], ready: f[9], age: f[10]
				, dist: f[11], walk: f[12], loading: f[13], hold: f[14], brole: f[15], wiz: f[16], school: f[17], hits: f[18], hitr: f[19]
				, plan: f[20], lasthit: f[21]})
		}
	PartyLeader := leader, PartyMembers := members
	if (IsFunc("DashSee"))
		Func("DashSee").Call("party", PartyText())
	}

;---- Battle roles ----

;This wizard's part in a party battle (Settings: partybattle - <school>.partybattle for one school's wizard): "hitter",
;"blader" or "healer"
PartyBattleSet()
	{
	k := (PartyMySchool != "" && Stats.HasKey(PartyMySchool ".partybattle")) ? PartyMySchool ".partybattle" : "partybattle"
	r := Stats.HasKey(k) ? Stats[k] : 1
	return r = 2 ? "blader" : r = 3 ? "healer" : "hitter"
	}

;A blader or healer this round: its boosts go to the party's hitter (PartyBattleRole)
PartySupport()
	{
	return BattleRole = "blader" || BattleRole = "healer"
	}

;A name as the plates and the log are matched by: its letters, in capitals (AutoQuester's WalkLetters)
PartyKey(name)
	{
	if (IsFunc("WalkLetters"))
		return Func("WalkLetters").Call(name)
	StringUpper, name, name
	return RegExReplace(name, "[^A-Z]")
	}

;This round's part (RoundStart, once the hitter's found): a party battle - more than one wizard on your side (the game's
;log), not dual mode - with this wizard set to Blader or Healer (partybattle) and the party's hitter on your side, its
;plate read: BattleRole that, the boosts to the hitter (hammerX/Y its plate, HammerSchool, HammerName). Else "hitter": as
;ever, each time it's not sure (logged once a battle). Alt+2's pick (Manual) is the hitter: a friend without the bot too
PartyBattleRole()
	{
	global
	local want, h, p, bx, by
	BattleRole := "hitter", HammerName := "", HammerSlot := 0, HammerPlan := ""
	want := PartyBattleSet()
	if (want = "hitter" || DualBattle = 1 || BattleTeam() < 2)
		return
	if (Manual = 1)
		{
		BattleRole := want, HammerName := "the plate picked with " HkText("boost")
		return
		}
	if (PartyRoleSet() = "off")
		return PartyRoleNote("this wizard's a " want ", but the party's off (Settings, PARTY) - it hits")
	h := PartyHitter()
	if (!IsObject(h))
		return PartyRoleNote("this wizard's a " want ", but no party hitter is on your side of this battle (heard from in the last 5 s, its wizard's name known) - it hits")
	ReadSidePlates()
	p := SidePlates[h.slot]
	if (!IsObject(p))
		return PartyRoleNote(h.wiz "'s name plate wasn't read this round - this wizard hits")
	hammerX := p.x + Px(25), hammerY := p.y + Px(8)
	;(its school: as it says, else its plate's badge - left of its name)
	HammerSchool := BadgeNumber(h.school) ? h.school : BestBadge(p.x - Px(100), p.y - Px(60), p.x + Px(10), p.y + Px(80), bx, by, p.x - Px(45), p.y + Px(15))
	BattleRole := want, HammerName := h.wiz, HammerSlot := h.slot
	;(its planned hit's schools - the boosts are for them: KillCalc.ahk BoostSearch, BoostPick)
	HammerPlan := PartySchools(h.plan)
	PartyNoteBoosts()
	PartyReblade(h)
	}

;The party's hitter in this battle, from the party's state - the leader's and the followers' (heard from in the last 5 s,
;in battle, its wizard's name one of your side's in the game's log, not yours, no two of your side so named): the one set
;to Hitter - the leader first, else the first by name, so every support picks the same -, else the leader.
;{wiz, school, hits, hitr, slot} or "". MySlot: your slot (by your name in the log)
PartyHitter()
	{
	phSlots := {}, phTwice := {}, MySlot := 0
	phMe := PartyKey(OwnName())
	Loop, 4
		{
		phS := A_Index + 3
		if (!IsObject(BlNames) || !BlNames.HasKey(phS))
			continue
		phK := PartyKey(BlNames[phS])
		if (phSlots.HasKey(phK))
			phTwice[phK] := 1
		phSlots[phK] := phS
		if (phK != "" && phK = phMe)
			MySlot := phS
		}
	phAll := []
	if (IsObject(PartyLeader))
		phAll.Push({m: PartyLeader, lead: 1})
	if (IsObject(PartyMembers))
		for each, phM in PartyMembers
			phAll.Push({m: phM, lead: 0})
	phLead := "", phBest := "", phBestK := ""
	for each, phC in phAll
		{
		phM := phC.m, phK := PartyKey(phM.wiz)
		if (phM.age = "" || phM.age > 5000 || phM.battle != 1 || StrLen(phK) < 3 || phK = phMe || !phSlots.HasKey(phK) || phTwice.HasKey(phK))
			continue
		phW := {wiz: phM.wiz, school: phM.school, hits: phM.hits, hitr: phM.hitr, slot: phSlots[phK], plan: phM.plan, lasthit: phM.lasthit}
		if (phC.lead)
			phLead := phW
		if (phM.brole = "hitter" && (phC.lead || (!IsObject(phBest) || (phBestK != "lead" && phK < phBestK))))
			phBest := phW, phBestK := phC.lead ? "lead" : phK
		}
	return IsObject(phBest) ? phBest : phLead
	}

;The schools in a comma list (a peer's plan / lasthit), the seven only, each once: "storm,fire,ice" ("" none)
PartySchools(list)
	{
	psOut := ","
	Loop, Parse, list, `,
		{
		psS := Format("{:L}", Trim(A_LoopField))
		if (BadgeNumber(psS) && !InStr(psOut, "," psS ","))
			psOut .= psS ","
		}
	return Trim(psOut, ",")
	}

;A blader's or healer's boosts cast last round: each used flag (used0-52: UseBlade, UseTrap, PartyShield - KillCalc.ahk
;KeyFlags) newly set since the last look went out in the round noted then - the game's log's (PartyCastRound); each
;treasure or item card's copy newly cast (KillCalc.ahk BoostSrcUsed) the same (PartySrcRound). Called at each round's start
PartyNoteBoosts()
	{
	global
	local n, pnbK, pnbI, pnbGone
	if (PartyFlagDuel != BlDuel || !IsObject(PartyFlagRound))
		PartyFlagDuel := BlDuel, PartyFlagRound := {}, PartyCastRound := "", PartySrcRound := {}
	if (!IsObject(PartySrcRound))
		PartySrcRound := {}
	Loop, 53
		{
		n := A_Index - 1
		if (used%n% = 1)
			{
			if (!PartyFlagRound.HasKey(n))
				PartyFlagRound[n] := PartyCastRound != "" ? PartyCastRound : 0
			}
		else
			PartyFlagRound.Delete(n)
		}
	pnbGone := []
	for pnbK in PartySrcRound
		if (!IsObject(BoostSrcUsed) || !BoostSrcUsed.HasKey(pnbK))
			pnbGone.Push(pnbK)
	for pnbI, pnbK in pnbGone
		PartySrcRound.Delete(pnbK)
	if (IsObject(BoostSrcUsed))
		for pnbK in BoostSrcUsed
			if (!PartySrcRound.HasKey(pnbK))
				PartySrcRound[pnbK] := PartyCastRound != "" ? PartyCastRound : 0
	;(this round's cast goes out in the log's next round)
	PartyCastRound := (BlRound ? BlRound : 0) + 1
	}

;A blader's or healer's boosts on the hitter are spent when it hits: its hits (shared) went up since last seen - once the
;round that hit goes out in is in the game's log, each of ours that went out before it (an earlier round, or that round
;before its hit in the log) is cast again - its used flag cleared; one after its hit is still on it. The first look in a
;battle only notes the count
PartyReblade(h)
	{
	global
	local ours, theirs, i, c, wait, n, at, spent, kept, prLast, prK, prGone
	if (h.hits = "")
		return
	if (PartyHitsDuel != BlDuel)
		{
		PartyHitsDuel := BlDuel, PartyHitsSeen := h.hits, PartyHitsWait := ""
		return
		}
	if (h.hits != PartyHitsSeen)
		{
		;(the round its hit goes out in - its log's; not said: the next one here)
		wait := (h.hitr > 0) ? h.hitr : (BlRound ? BlRound : 0) + 1
		PartyHitsSeen := h.hits, PartyHitsWait := wait
		}
	if (PartyHitsWait = "")
		return
	BattleLogRead(true)
	if ((BlRound ? BlRound : 0) < PartyHitsWait)
		return
	ours := 0, theirs := 0
	for i, c in BlCasts
		if (c.round = PartyHitsWait && c.spell != "None")
			{
			if (MySlot && c.slot = MySlot)
				ours := i
			if (c.slot = h.slot)
				theirs := i
			}
	spent := 0, kept := 0
	;(the schools of its hit, as the hitter read them - "" not known: an older bot, or its heads weren't: every boost spent)
	prLast := PartySchools(h.lasthit)
	Loop, 53
		{
		n := A_Index - 1
		if (used%n% != 1)
			continue
		at := (IsObject(PartyFlagRound) && PartyFlagRound.HasKey(n)) ? PartyFlagRound[n] : 0
		if (at > PartyHitsWait || (at = PartyHitsWait && ours && theirs && ours > theirs))
			kept += 1
		;(one that boosts none of its hit's schools is still on it: a Storm Blade through the hitter's Power Nova)
		else if (prLast != "" && (prK := FlagKey(n)) != "" && !BoostFitsAny(prK, prLast))
			kept += 1
		else
			{
			used%n% := 0, spent += 1
			if (IsObject(PartyFlagRound))
				PartyFlagRound.Delete(n)
			}
		}
	;(a treasure or item card's copy cast on it - KillCalc.ahk BoostSrcUsed: spent the same way - one cast after its hit, or
	;that boosts none of its hit's schools, is still on it: cast again, a second treasure card wouldn't stack with it)
	if (IsObject(BoostSrcUsed))
		{
		prGone := []
		for prK in BoostSrcUsed
			{
			at := (IsObject(PartySrcRound) && PartySrcRound.HasKey(prK)) ? PartySrcRound[prK] : 0
			if (at > PartyHitsWait || (at = PartyHitsWait && ours && theirs && ours > theirs))
				kept += 1
			else if (prLast = "" || BoostFitsAny(prK, prLast))
				prGone.Push(prK)
			else
				kept += 1
			}
		for i, prK in prGone
			{
			BoostSrcUsed.Delete(prK), spent += 1
			if (IsObject(PartySrcRound))
				PartySrcRound.Delete(prK)
			}
		}
	DebugLog("  " h.wiz " hit (" h.hits " hits so far, round " PartyHitsWait "): " spent " of our boosts on it spent - cast again" (kept ? "; " kept " still on it (cast after its hit)" : ""))
	PartyHitsWait := ""
	}

;The ally on your side lowest on health this round (the healer): each of your side's plates but yours read (Autofarmer.ahk
;PlateHealth - a low reading only with 3 of its 4 reads agreeing, as for your own). PartyLowX/Y: its plate (the name),
;PartyLowPct, PartyLowName ("" none read). Read once a round. True if one was read
PartyLowest()
	{
	global
	local i, p, r, pct, limit, key
	key := BlDuel "|" roundnumber
	if (PartyLowKey = key)
		return PartyLowName != ""
	PartyLowKey := key, PartyLowX := "", PartyLowY := "", PartyLowPct := 101, PartyLowName := ""
	limit := StatOr("healat", 40)
	ReadSidePlates()
	for i, p in SidePlates
		{
		if (p.me)
			continue
		r := PlateHealth(p.x, p.y)
		if (!IsObject(r))
			{
			DebugLog("  " p.name "'s health: not read for sure")
			continue
			}
		pct := Round(100 * r.cur / r.max)
		if (pct < limit && r.votes < 3)
			{
			DebugLog("  " p.name "'s health: read " r.cur "/" r.max " only " r.votes " times out of 4 - not sure enough to heal")
			continue
			}
		DebugLog("  " p.name "'s health: " r.cur "/" r.max " (" pct "%)")
		if (pct < PartyLowPct)
			PartyLowPct := pct, PartyLowName := p.name, PartyLowX := p.x + Px(25), PartyLowY := p.y + Px(8)
		}
	return PartyLowName != ""
	}

;The healer: the ally lowest on health (PartyLowest) under healat % and lower than you - a heal for one wizard on it, or
;one that heals all of you (heal1, then heal2; not one known to heal only you: <school>.healNtarget:0; :2 heals all of
;you). True if one went out
PartyHealAlly()
	{
	global
	local limit, hcard, each
	limit := StatOr("healat", 40)
	if (!PartyLowest() || PartyLowPct >= limit)
		return false
	;(you lower - a reading your own heal acts on, 3 of its 4 reads agreeing: your own heal, next)
	if (OwnHpRound != roundnumber && playerX != "")
		OwnHealthLow(true)
	if (OwnHpRound = roundnumber && OwnHpPct != "" && OwnHpPct <= PartyLowPct && OwnHpVotes >= 3)
		return false
	DebugLog("  healer: " PartyLowName " at " PartyLowPct "% (under " limit "%) - a heal on " PartyLowName)
	for each, hcard in ["heal1", "heal2"]
		{
		if (%hcard% != 1 || (Stats.HasKey(hitschool "." hcard "target") && Stats[hitschool "." hcard "target"] = 0))
			continue
		if UseHeal(hcard, %hcard%, hitschool, PartyLowX, PartyLowY)
			return true
		}
	DebugLog("  healer: no heal in hand that goes on an ally")
	return false
	}

;Tower Shield (resources\tower, usetower on - one no picture finds at its card box by the game's hand: KillCalc.ahk
;TowerMem, Autofarmer.ahk UseMemAt) for the party: the healer's on the ally lowest on health while under twice healat %,
;else - and the blader's - on the hitter; once till the hitter's next hit (used19). True if it went out
PartyShield()
	{
	global
	local limit, tx, ty, who
	if (tower != 1 || !Stat("usetower") || used19 = 1)
		return false
	limit := StatOr("healat", 40)
	if (BattleRole = "healer" && PartyLowest() && PartyLowPct < 2 * limit)
		tx := PartyLowX, ty := PartyLowY, who := PartyLowName " (" PartyLowPct "%)"
	else
		tx := hammerX, ty := hammerY, who := HammerName
	DebugLog("  " BattleRole ": Tower Shield on " who)
	if (UseOnHammer("tower", tower, "resources", tx, ty) && CastWentOut())
		{
		used19 := 1
		if (IsFunc("DashCast"))
			Func("DashCast").Call("tower")
		return true
		}
	return false
	}

;Where a blader's or healer's traps go (no boss picked with Alt+1): the enemy the hitter goes for - the one with the
;least health, as its hits pick (Autofarmer.ahk HitTarget); the enemies' plates as read in the last 8 s, else now
;(KillCalc.ahk ReadEnemyHealth). False: none read - no traps (nowhere sure to put them)
PartyTrapTarget(ByRef x, ByRef y)
	{
	if (A_TickCount - EnemyPlatesAt > 8000)
		ReadEnemyHealth()
	if (!IsObject(EnemyPlates) || !EnemyPlates.Length() || !IsObject(EnemyHP) || EnemyHP.Length() != EnemyPlates.Length())
		return false
	ptPick := 1
	for ptI, ptE in EnemyHP
		if (ptE.cur < EnemyHP[ptPick].cur)
			ptPick := ptI
	x := EnemyPlates[ptPick].x, y := EnemyPlates[ptPick].y
	return true
	}

;Why this wizard hits after all (a blader or healer that isn't sure): in debug.log once a battle
PartyRoleNote(why)
	{
	static saidDuel := "", saidWhy := ""
	if (saidDuel = BlDuel && saidWhy = why)
		return
	saidDuel := BlDuel, saidWhy := why
	DebugLog("  party battle: " why)
	}

;The party in a line (the dashboard)
PartyText()
	{
	if (PartyRole = "off" || PartyRole = "")
		return ""
	if (PartyState = "unreachable" || PartyState = "error")
		return PartyRole " - " PartyWhy
	if (PartyRole = "leader")
		{
		t := ""
		for each, m in PartyMembers
			t .= (t = "" ? "" : ", ") (m.name != "" ? m.name : "?") " " (m.zone != PartyMe.zone ? "in another zone" : m.battle = 1 ? "in battle" : m.dist != "" ? m.dist " away" : "?")
		return "leader - " (t = "" ? "no followers yet" : t) (PartyHolding != "" ? " (waiting: " PartyHolding ")" : "")
		}
	L := PartyLeader
	if (!IsObject(L))
		return "follower - waiting to hear from the leader"
	return "following " (L.name != "" ? L.name : "the leader") " - " (L.zone != PartyMe.zone ? "in " L.zone : L.battle = 1 ? "in battle" : L.dist " away")
	}

;The leader's hold (the walker asks: Walker.ahk WalkStep): why it should wait now - a follower (heard from in the last 5 s)
;in another zone, farther than partywaitdist, or not ready; "" walk on. One held partywaitmax s isn't waited for again
;till it's been near once
PartyHoldWhy()
	{
	PartyHolding := ""
	if (PartyRoleSet() != "leader" || PartyState != "serving" || !IsObject(PartyMembers))
		return ""
	if (!IsObject(PartyHeldFrom))
		PartyHeldFrom := {}, PartySkip := {}
	maxS := Stat("partywaitmax"), far := Stat("partywaitdist")
	why := ""
	for each, m in PartyMembers
		{
		if (m.age = "" || m.age > 5000)
			continue
		key := m.name != "" ? m.name : "a follower"
		;(near again: waited for again)
		if (m.zone = PartyMe.zone && m.dist != "" && m.dist <= far / 2)
			PartySkip.Delete(key), PartyHeldFrom.Delete(key)
		if (PartySkip.HasKey(key))
			continue
		w := m.loading = 1 ? key " is loading" : m.zone != PartyMe.zone ? key " is in another zone" : (m.dist != "" && m.dist > far) ? key " is " m.dist " away"
			: m.ready != 1 ? key " isn't ready (bot off, not walking, or played by hand)" : ""
		if (w = "")
			{
			PartyHeldFrom.Delete(key)
			continue
			}
		if (!PartyHeldFrom.HasKey(key))
			PartyHeldFrom[key] := A_TickCount
		if (maxS > 0 && A_TickCount - PartyHeldFrom[key] > maxS * 1000)
			{
			PartySkip[key] := 1
			DebugLog("Party: waited " maxS " s for " key " - walking on without them till they're near again")
			continue
			}
		why .= (why = "" ? "" : "; ") w
		}
	PartyHolding := why
	return why
	}

;The follower's step (the walking dispatch, instead of WalkStep): to the leader - stopping partynear from it, walking
;again past twice that; into its battle (its battle spot, mobs not avoided - the battle's own are there); through the
;door it took (its last spot in this zone, then 400 on the way it was going). Stuck (its own place hardly moving with W
;down for 3 s): back up, turn 90, walk - 4 times at most, then it waits for the leader to come back near
PartyFollowStep()
	{
	if (!Walking || !GameActive() || inbattle = 1 || !BotNoBattle())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(Wizard101 behind another window, you away 5 minutes - or Play for me: brought to the front, as the walker does)
		if (Walking && !GameActive() && inbattle != 1 && IsFunc("GameToFront") && UserIdle() > 300000 && A_TickCount - WkFrontLook > 1500)
			WkFrontLook := A_TickCount, Func("GameToFront").Call("following the leader", true, true)
		Sleep, 150
		return
		}
	L := PartyLeader
	if (PartyState != "following" || !IsObject(L) || L.age = "" || L.age > 5000)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("party: waiting for the leader" (PartyWhy != "" ? " - " PartyWhy : ""))
		Sleep, 300
		return
		}
	near := Stat("partynear")
	;Where to: the leader's battle, the leader, or the door it took
	if (L.zone = PartyMe.zone && L.battle = 1 && L.bx != "")
		tgt := {x: L.bx, y: L.by, z: L.bz, kind: "battle", stop: 40}
	else if (L.zone = PartyMe.zone && L.x != "")
		{
		tgt := {x: L.x, y: L.y, z: L.z, kind: "leader", stop: near}
		;(standing by it: still till it's twice as far)
		if (!PartyNear && L.dist != "" && L.dist <= near)
			PartyNear := 1
		if (PartyNear && L.dist != "" && L.dist > near * 2)
			PartyNear := 0
		if (PartyNear)
			{
			if (KeysDown || HeldW)
				ReleaseKeys()
			PartyTries := 0, PartyStillAt := 0
			SetStatus("party: by " (L.name != "" ? L.name : "the leader") " (" L.dist " away)")
			Sleep, 200
			return
			}
		}
	else if (L.dzone = PartyMe.zone && L.dx != "")
		tgt := {x: L.dx, y: L.dy, z: L.dz, kind: "door", stop: 100}
	else
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("party: the leader is in " L.zone " - not a door from here (teleport to friend comes in phase 2)")
		Sleep, 500
		return
		}
	;(through the door: walked on the way the leader went, for 4 s)
	if (tgt.kind = "door" && A_TickCount < PartyPushUntil)
		tgt := {x: L.dx + 400 * L.ddx, y: L.dy + 400 * L.ddy, z: L.dz, kind: "push", stop: 0}
	nav := PartyNavTo(tgt, tgt.kind = "leader" || tgt.kind = "door")
	if (!IsObject(nav))
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		SetStatus("party: the game's memory can't be read for the way to the leader")
		Sleep, 300
		return
		}
	d := Sqrt((nav.x - tgt.x) ** 2 + (nav.y - tgt.y) ** 2)
	if (tgt.kind = "door" && d <= tgt.stop)
		{
		PartyPushUntil := A_TickCount + 4000
		DebugLog("Party: at the door " (L.name != "" ? L.name : "the leader") " took - walking on through it")
		}
	if (d <= tgt.stop && tgt.kind != "door")
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		Sleep, 150
		return
		}
	;(stuck: its own place hardly moving for 3 s with W down)
	if (HeldW && PartyStillAt && Sqrt((nav.x - PartyStillX) ** 2 + (nav.y - PartyStillY) ** 2) < 60)
		{
		if (A_TickCount - PartyStillAt > 3000)
			{
			PartyTries += 1, PartyStillAt := 0
			if (PartyTries > 4)
				{
				ReleaseKeys()
				SetStatus("party: stuck on the way to the leader - waiting for it to come back near")
				Sleep, 1000
				return
				}
			DebugLog("Party: stuck on the way to the " tgt.kind " (" Round(d) " away) - backing up and turning, try " PartyTries)
			BackUp(700)
			DgTurn(PartyTries & 1 ? 90 : -90)
			HoldW(1)
			Sleep, 900
			return
			}
		}
	else
		PartyStillAt := A_TickCount, PartyStillX := nav.x, PartyStillY := nav.y
	SetStatus("party: following " (L.name != "" ? L.name : "the leader") " - to its " tgt.kind ", " Round(d) " away")
	DgSteer(nav, tgt, d)
	}

;The way to p ({x, y, z}) by the helper's route (/navto: round walls - and mobs, avoid); {x, y, z, yaw, ax, ay, left, why,
;zone} or ""
PartyNavTo(p, avoid)
	{
	answer := VisionGet("/navto?x=" Round(p.x, 1) "&y=" Round(p.y, 1) "&z=" Round(p.z, 1) (avoid ? NavMobArgs() : ""), 2500, true)
	if (answer = "" || SubStr(answer, 1, 3) = "ERR")
		return ""
	nav := {x: "", y: "", z: "", yaw: "", ax: "", ay: "", left: "", why: "", zone: ""}
	Loop, Parse, answer, `n, `r
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "pos")
			nav.x := f[2], nav.y := f[3], nav.z := f[4], nav.yaw := f[5]
		else if (f[1] = "zone")
			nav.zone := f[2]
		else if (f[1] = "route")
			nav.ax := f[2], nav.ay := f[3], nav.left := f[4]
		else if (f[1] = "routewhy")
			nav.why := Trim(SubStr(A_LoopField, 10))
		}
	return (nav.x = "" || nav.yaw = "") ? "" : nav
	}

;Tray menu "Party...": this wizard's party name, and (a follower) the leader PC's address - kept in party.ini
PartySetup()
	{
	name := PartyIni("name"), leader := PartyIni("leader")
	InputBox, newName, Party - this wizard's name, % "A name for this wizard in the party (shown on the other PCs' dashboards) - its in-game name is best.`n`nThe role (Off / Leader / Follower) is in Settings > PARTY.", , 420, 190, , , , , % name != "" ? name : A_ComputerName
	if (ErrorLevel)
		return
	newName := RegExReplace(Trim(newName), "[^\w .'-]")
	IniWrite, %newName%, %A_ScriptDir%\party.ini, party, name
	InputBox, newLeader, Party - the leader's PC, % "Followers only: the leader PC's address on your home network - its name (e.g. " A_ComputerName ") or its IP (e.g. 192.168.1.20: on the leader PC, Settings > Network > Properties > IPv4 address).`n`nLeave it empty on the leader.", , 460, 220, , , , , %leader%
	if (ErrorLevel)
		return
	newLeader := RegExReplace(Trim(newLeader), "[^\w.-]")
	IniWrite, %newLeader%, %A_ScriptDir%\party.ini, party, leader
	DebugLog("Party: this wizard's name '" newName "'" (newLeader != "" ? ", the leader at " newLeader : ""))
	}

PartyTimer:
PartyTick()
return
