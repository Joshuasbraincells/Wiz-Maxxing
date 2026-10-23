; Party.ahk - a party of up to 4 wizards, one per PC on the same home network (TODO goal 1, phase 1). AHK v1.1,
; functions and labels only; #Included by Autofarmer.ahk.
;
; Settings (PARTY): partyrole - Off, Leader (quests as now; waits while a follower is far, in another zone or not ready -
; partywaitdist, partywaitmax) or Follower (goes where the leader goes - partynear - instead of following its own quest
; arrow; into the leader's battles; through the door the leader took). The party's port: partyport. This wizard's party
; name and (a follower) the leader PC's address: the tray menu's Party... (party.ini - not secret: a name, an address).
;
; The vision helper does the talking (vision\party.py): every half second PartyTick tells it this bot's state (/party)
; and gets the party back - the leader's place, door and battle spot; the followers'. State only: nothing one bot sends
; can make another press or click anything. Phase 2 (teleport to friend across zones) and phase 3 (battle roles) aren't
; in yet: a follower whose leader went where it can't follow waits, and says so.

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
	role := PartyRoleSet()
	if (role = "off" && PartyRole = "off")
		return
	if (!VisionOn || !IsFunc("VisionGet"))
		return
	hp := (OwnHpPct != "" && A_TickCount - OwnHpAt < 60000) ? OwnHpPct : ""
	ready := BotOn && Walking && !PlayerActive && GameActive() && !PotionResting ? 1 : 0
	q := "/party?role=" role "&name=" NavUri(PartyIni("name")) "&leader=" NavUri(PartyIni("leader"))
		. "&port=" Stat("partyport") "&battle=" (inbattle = 1 ? 1 : 0) "&hp=" hp "&ready=" ready "&walk=" (Walking ? 1 : 0)
		. "&bot=" (BotOn ? 1 : 0) "&loading=" (WkLoading ? 1 : 0) "&hold=" NavUri(SubStr(PartyHolding, 1, 80))
	ans := VisionGet(q, 600, true)
	PartyAskAt := A_TickCount
	if (ans = "")
		{
		PartyState := "error", PartyWhy := "the vision helper didn't answer"
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
				, dto: f[20], bx: f[21], by: f[22], bz: f[23], hold: f[24]}
		else if (f[1] = "member")
			members.Push({name: f[2], zone: f[3], x: f[4], y: f[5], z: f[6], battle: f[7], hp: f[8], ready: f[9], age: f[10]
				, dist: f[11], walk: f[12], loading: f[13], hold: f[14]})
		}
	PartyLeader := leader, PartyMembers := members
	if (IsFunc("DashSee"))
		Func("DashSee").Call("party", PartyText())
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
