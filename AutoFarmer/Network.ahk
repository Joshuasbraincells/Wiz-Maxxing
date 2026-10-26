#Warn Unreachable, Off
; Network.ahk - the dashboard's Network tab (v0.46.0, asked 2026-10-24: a PC that runs the bot all day, watched and
; steered from another): every bot on your home network with Settings > Network on - its PC, version, wizard, zone,
; on / off, Play for me, what it's doing, health, mana, deaths - and, once you pick it, its recent log and its game's
; picture; buttons turn it on or off, switch its Play for me off or restart it (with the network PIN, the same on both
; PCs - Settings: netpin). Play for me can only be switched OFF from the network: on only at that PC (its button).
; The vision helper does the talking (vision\netmon.py): NetTick tells it this bot's state every 2 s and takes the
; others' and any commands for this one. Settings: neton (off till you switch it on - Windows then asks once to let
; Python through its firewall: allow it on Private networks), netport, netpin. AutoHotkey v1.1, #Included by
; Autofarmer.ahk.

;The bots heard ([{id, ip, age, pc, ver, wiz, school, zone, bot, pfm, doing, hp, mana, deaths, dall, up, status, last}]),
;this bot's network state and why, the last line of its log, the bot picked on the tab (its id), when its log and
;picture were last fetched, when NetTick first ran (the uptime sent)
global NetPeers, NetState, NetWhy, NetLastLine, NetSel, NetLogAt, NetSnapAt, NetStartAt
;The picked bot's PC (the pick kept when it restarts - its id is new each start); a refresh asked for; the Network tab's
;controls (Dashboard.ahk - a control's variable has to be global)
global NetSelPc, NetRefresh
global NetHelp, NetOnBtn, NetOffBtn, NetPfmBtn, NetRestartBtn, NetRefreshBtn, NetStatus, NetList, NetLog, NetPic, NetPicNote
global DashNetId, DashNetCmd

NetTick:
NetTick()
return

NetRestartNow:
NetRestartNow()
return

;This bot's state to the helper and the others' (and commands for this one) back; the picked bot's log and picture
;fetched every 6 s while the Network tab is up
NetTick()
	{
	static wasOn := 0, schoolAt := 0, school := "", busy := 0
	if (busy || !VisionOn || !IsFunc("VisionGet"))
		return
	netOn := Stat("neton") ? 1 : 0
	;(never on: the helper isn't asked at all - no sockets, no firewall question)
	if (!netOn && !wasOn)
		{
		NetState := "off", NetWhy := "Settings > NETWORK > neton", NetPeers := []
		if (IsFunc("DashNetFill"))
			DashNetFill.Call()
		return
		}
	busy := 1
	wasOn := netOn
	NetStartAt := NetStartAt ? NetStartAt : A_TickCount
	;(the school this character fights as - looked for once in 20 s)
	if (!schoolAt || A_TickCount - schoolAt > 20000)
		schoolAt := A_TickCount, school := StatsSchoolOf(StatsCharID())
	bot := (BotStandby && !BotEverOn) ? "standby" : BotOn ? "on" : "off"
	doing := !BotOn ? "off" : inbattle = 1 ? "in a battle" : WkLoading ? "loading" : PlayerActive ? "you're playing"
		: !Walking ? "walking off (" HkText("walk") ")" : WkArrived = 7 ? "collecting" : "walking"
	see := IsObject(DashSees) ? DashSees : {}
	hp := RegExReplace(see.hp, "\s*\(.*")
	;(the bot picked - fetched by the helper's own thread only while the Network tab's up)
	shown := IsFunc("DashNetShown") && DashNetShown.Call()
	q := "/net?on=" netOn "&sel=" (shown ? NetSel : "") "&refresh=" (NetRefresh ? 1 : 0) "&port=" Round(Stat("netport")) "&pin=" Round(Stat("netpin")) "&pc=" NavUri(A_ComputerName)
		. "&ver=" NavUri(BotVersion()) "&wiz=" NavUri(OwnName()) "&school=" school "&zone=" NavUri(WalkZone())
		. "&bot=" bot "&pfm=" (PlayForMe ? 1 : 0) "&doing=" NavUri(doing) "&hp=" NavUri(hp) "&mana=" NavUri(see.mana)
		. "&deaths=" (IsObject(DashN) && DashN.deaths ? DashN.deaths : 0) "&dall=" (IsFunc("DashDeathsAll") ? DashDeathsAll.Call() : 0)
		. "&up=" Round((A_TickCount - NetStartAt) / 1000) "&status=" NavUri(SubStr(StatusText, 1, 120)) "&last=" NavUri(SubStr(NetLastLine, 1, 160))
		. "&front=" (GameActive() ? 1 : 0) "&gx=" GameLeft "&gy=" GameTop "&gw=" GameW "&gh=" GameH
	NetRefresh := 0
	ans := VisionGet(q, 800, true)
	if (ans = "" || SubStr(ans, 1, 3) = "ERR")
		{
		NetState := "error", NetWhy := "the vision helper didn't answer", busy := 0
		return
		}
	peers := []
	Loop Parse, ans, "`n", "`r"
		{
		f := StrSplit(A_LoopField, "|")
		if (f[1] = "net")
			{
			if (NetState != f[2] || NetWhy != f[3])
				DebugLog("Network: " f[2] (f[3] != "" ? " - " f[3] : ""))
			NetState := f[2], NetWhy := f[3]
			}
		else if (f[1] = "peer" && f.Length >= 19)
			peers.Push({id: f[2], ip: f[3], age: f[4], pc: f[5], ver: f[6], wiz: f[7], school: f[8], zone: f[9], bot: f[10]
				, pfm: f[11], doing: f[12], hp: f[13], mana: f[14], deaths: f[15], dall: f[16], up: f[17], status: f[18], last: f[19]})
		else if (f[1] = "cmd")
			NetDo(f[2], f[3])
		}
	NetPeers := peers
	;(the pick by its PC: a bot started again has a new id)
	if (NetSelPc != "")
		{
		NetSel := ""
		for i, p in peers
			if (p.pc = NetSelPc)
				NetSel := p.id
		}
	if (IsFunc("DashNetFill"))
		DashNetFill.Call()
	;(the bot picked on the Network tab: its log and picture as the helper's fetched them - nothing waited for here)
	if (NetSel != "" && shown)
		NetFetchPicked()
	busy := 0
	}

;The picked bot's recent log and its game's picture as the helper's fetch thread has them, onto the Network tab
;(Dashboard.ahk DashNetShow) - an answer at once, never a wait on the network
NetFetchPicked()
	{
	sel := NetSel
	if (sel = "")
		return
	ans := VisionGet("/netpeer?id=" sel, 800, true)
	if (sel != NetSel)
		return
	if (ans = "")
		{
		why := RegExReplace(VisionErr, "^ERR\s*")
		if (IsFunc("DashNetShow"))
			DashNetShow.Call("", "", why != "" ? why : "The vision helper didn't answer")
		return
		}
	text := "", pic := "", why := "", at := ""
	Loop Parse, ans, "`n", "`r"
		{
		if (SubStr(A_LoopField, 1, 4) = "log|")
			text .= SubStr(A_LoopField, 5) "`r`n"
		else if (SubStr(A_LoopField, 1, 5) = "snap|")
			pic := SubStr(A_LoopField, 6)
		else if (SubStr(A_LoopField, 1, 4) = "why|")
			why := SubStr(A_LoopField, 5)
		else if (SubStr(A_LoopField, 1, 3) = "at|")
			at := SubStr(A_LoopField, 4)
		}
	;(the same picture as before: not loaded again)
	if (at != "" && at = NetSnapAt && text = "")
		return
	if (IsFunc("DashNetShow"))
		DashNetShow.Call(text, pic != "" && FileExist(pic) ? pic : "", why)
	}

;A command from another bot on the network (netmon.py checked its PIN): done here, and said in the log
NetDo(c, from)
	{
	who := from != "" ? from : "another PC"
	if (c = "on" && !BotOn)
		DebugLog("Network: " who " turned the bot on"), BotToggle()
	else if (c = "off" && BotOn)
		DebugLog("Network: " who " turned the bot off"), BotToggle()
	else if (c = "pfmoff" && PlayForMe)
		{
		PlayForMe := 0
		PlayForMeShow()
		DebugLog("Network: " who " switched Play for me off - the bot waits for you and keeps its hands off while you play, as set")
		}
	else if (c = "restart")
		{
		DebugLog("Network: " who " restarted the bot")
		SetTimer(NetRestartNow,-500)
		}
	else
		DebugLog("Network: " who " asked for '" c "' - it's that way already")
	}

;A command to the bot picked on the Network tab (signed with this PC's PIN by the helper): what came of it
NetSend(c)
	{
	if (NetSel = "")
		return "Pick a bot in the list first"
	ans := Trim(VisionGet("/netcmd?id=" NetSel "&c=" c, 4000, true), " `r`n")
	;(its ERR's why - VisionGet keeps it in VisionErr)
	if (ans = "")
		return VisionErr != "" ? RegExReplace(VisionErr, "^ERR\s*") : "The vision helper didn't answer"
	return SubStr(ans, 1, 3) = "ok|" ? "Sent - " SubStr(ans, 4) : SubStr(ans, 1, 4) = "ERR " ? SubStr(ans, 5) : ans
	}

;Seconds as "3 h 20 m" / "4 m" / "12 s"
NetAge(s)
	{
	s := Round(s)
	return s >= 3600 ? (s // 3600) " h " Mod(s // 60, 60) " m" : s >= 60 ? (s // 60) " m" : s " s"
	}

;###############  V1toV2 FUNCS  ###############
NetTick() { ; V1toV2: Lbl->Func
global
NetTick()
return
}
;##############################################
NetRestartNow() { ; V1toV2: Lbl->Func
global
BotRestart()
return
}
