#Warn Unreachable, Off
#Requires Autohotkey v2.0
InstallMouseHook()
InstallKeybdHook()
#SingleInstance force

;All the pictures are found relative to this folder, however the script was started (shortcut, editor, ...)
SetWorkingDir(A_ScriptDir)

;The wizard icon in the tray and on the dashboard (built into the exe; run as a script, set here)
if (!A_IsCompiled && FileExist(A_ScriptDir "\..\assets\wizard.ico"))
	TraySetIcon(A_ScriptDir . "\..\assets\wizard.ico")

;All ImageSearch/Mouse coordinates are absolute screen coordinates, offset from the game's client area (see UpdateGameRect)
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

;Battles (this script) and quest walking (..\AutoQuester\Walker.ahk) run together in one loop and
;start by themselves: fight when a battle round is up, otherwise follow the quest arrow.
;  F6           the bot on / off (off: no battles, walking, potions or reconnecting). Opened by the game -
;               "Open with Wizard101", /standby - it starts off and waits for F6
;  F8           walking on / off
;  Windows+1    restart (also Alt+Esc)
;  Windows+Esc  quit
;(the keys out of the box - yours to change on the dashboard's Keys tab: Hotkeys.ahk makes them, these labels run)
;Disconnected: it clicks the game's RECONNECT, and if the game closes it can start it and log back in
;(Reconnect.ahk). Tray menu: "Auto-reconnect on/off" and "Set Wizard101 login..." (the login it uses then)
OnExit("WalkerQuit")
;No standard tray menu: its "Pause Script" would freeze the walker with a key held down
Tray := A_TrayMenu
Tray.Delete() ; V1toV2: not 100% replacement of NoStandard, Only if NoStandard is used at the beginning
;(the version, on top - not a command)
Tray.Add("Wiz-Maxxing " (BotVersion() = "" ? "(no version.txt)" : BotVersion()), MenuNothing)
Tray.Disable("Wiz-Maxxing " (BotVersion() = "" ? "(no version.txt)" : BotVersion()))
Tray.Add()
Tray.Add(HkMenu("bot"), MenuBotToggle)
Tray.Add(HkMenu("walk"), MenuWalk)
Tray.Add("Wait while I play", MenuHandsOff)
Tray.Add("Play for me (leave it alone for days)", MenuPlayForMe)
Tray.Add("Bring Wizard101 to the front", MenuGameFront)
Tray.Add("Auto-reconnect on/off", MenuReconnect)
Tray.Add("Set Wizard101 login...", MenuLogin)
Tray.Add("Discord alerts...", MenuAlerts)
Tray.Add("Party...", MenuParty)
Tray.Add(HkMenu("dash"), MenuDash)
Tray.Add("Learned spells", MenuSpells)
Tray.Add("Settings...", MenuSettings)
Tray.Add("Map of the zone", MenuMap)
Tray.Add("Speedhack: press its walking key in 3 s (for Cheat Engine)", MenuSpeedKeyFast)
Tray.Add("Speedhack: press its 1x key in 3 s (for Cheat Engine)", MenuSpeedKeyNormal)
Tray.Add("Check for updates", MenuUpdates)
Tray.Add("Report a bug...", MenuBug)
Tray.Add(HkMenu("standby"), MenuWatch)
Tray.Add("Read wizard stats now", MenuStats)
Tray.Add("Record potion buying...", MenuPotionRoute)
Tray.Add("Buy potions now", MenuPotionRun)
Tray.Add("Quick sell the backpack now", MenuQuickSell)
Tray.Add("Quick sell rehearsal (stops at the confirmation)", MenuQuickSellRehearse)
Tray.Add("Learn every card (a deck of one of each)", MenuLearnAll)
Tray.Add(HkMenu("restart"), MenuRestart)
Tray.Add(HkMenu("quit"), MenuExit)
Tray.Default := HkMenu("walk")
SetTimer(StartBot,-300)
return

;(F6 / F8 - the bot on / off, walking on / off; while the bot is off - standby, paused: only in Wizard101, not taken
;from other programs. Their keys: Hotkeys.ahk)
MenuBotToggle:
MenuBotToggle()
return

MenuWalk:
MenuWalk()
return

;"Open with Wizard101": a watcher started with Windows opens the bot when the game starts (..\Watch.ahk)
MenuWatch:
MenuWatch()
return

MenuReconnect:
MenuReconnect()
return

MenuHandsOff:
MenuHandsOff()
return

MenuPlayForMe:
MenuPlayForMe()
return

MenuGameFront:
MenuGameFront()
return

MenuLearnAll:
MenuLearnAll()
return

MenuStats:
MenuStats()
return

MenuDash:
MenuDash()
return

;The dashboard's Spells tab: the cards the bot learned by itself, and your corrections (Spells.ahk)
MenuSpells:
MenuSpells()
return

;The Settings window (Settings.ahk): the mouse, the waits, how it plays its cards
MenuSettings:
MenuSettings()
return

;Cheat Engine's speedhack keys (F13-F24 - no keyboard has them): pressed 3 s after you pick this, so you can click into
;Cheat Engine's hotkey box first and set them there
MenuSpeedKeyFast:
MenuSpeedKeyFast()
return
MenuSpeedKeyNormal:
MenuSpeedKeyNormal()
return

;The map window (Dashboard.ahk): a top-down picture of the zone, the wizard and the quest goal
MenuMap:
MenuMap()
return

;(Wiz-Maxxing /check - the exe, or the script when this runs as one: asks GitHub; if you update, it closes this and
;starts the new one)
MenuUpdates:
MenuUpdates()
return

;What went wrong, posted as an issue on GitHub (BugReport.ahk)
MenuBug:
MenuBug()
return

MenuNothing:
MenuNothing()
return

;The latest release looked up now and then, out of this process (Wiz-Maxxing /latest writes updater.ini): the
;dashboard's Updates button and STATISTICS say from it whether a newer version is out - and UpdAuto installs it.
;45 s after start, then every autoupdate minutes (Settings; 2 hours with it off)
UpdPeekNow:
UpdPeekNow()
return

MenuPotionRoute:
MenuPotionRoute()
return

MenuPotionRun:
MenuPotionRun()
return

;The backpack quick sold for gold now - whether it's full or not (never in a dungeon) - or up to the confirmation only, read
;and closed: nothing sold (QuickSell.ahk)
MenuQuickSell:
MenuQuickSell()
return

MenuQuickSellRehearse:
MenuQuickSellRehearse()
return

MenuLogin:
MenuLogin()
return

;Discord alerts when the wizard needs you (Alerts.ahk): the webhook set, tested or removed
;This wizard's party name and the leader's address (Party.ahk; the role is in Settings > PARTY)
MenuParty:
MenuParty()
return

MenuAlerts:
MenuAlerts()
return

MenuRestart:
MenuRestart()
return

MenuExit:
MenuExit()
ExitApp()

StartBot:
StartBot()
return

;Checks if in battle
TestRound:
TestRound()
return

RoundStart:
RoundStart()
return

;Checks who's hammer
TestHammer:
TestHammer()
return
FindCards:
FindCards()
return
EndRound:
EndRound()
Return
	
;Functions
;You're playing: a key, a click or a mouse move of yours (not the bot's own, nor what the mouse lock swallowed: UserIdle
;leaves those out) in the last handsoff seconds (PlayerStats.txt, default 3 - and 3 at every start; 0 = never wait for you), while "Wait while
;I play" is on (HandsOffOn). Logged when it starts and ends; PlayerActive tells the dashboard
PlayerActing()
	{
	static logged := 0
	secs := Stats.Has("handsoff") ? Stats["handsoff"] : 3
	acting := (HandsOffOn() && secs > 0 && UserIdle() < secs * 1000)
	;(the bot's own hotkeys aren't you playing: the key itself, and for Alt+1 / Alt+2 / Windows+3 the click
	;on the boss / player that follows within 10 s)
	if (acting && A_ThisHotkey != "")
		{
		;(a click or wheel turn of yours the mouse lock swallowed is a hotkey too - Settings.ahk MouseLockSwallow: the bot's
		;own is the one before it. Your last input as UserIdle has it: what the lock swallowed isn't you)
		hkNow := A_ThisHotkey, keyAt := A_TickCount - A_TimeSinceThisHotkey
		if (MouseLockIsKey(hkNow))
			hkNow := A_PriorHotkey, keyAt := A_TickCount - A_TimeSincePriorHotkey
		lastInput := A_TickCount - UserIdle()
		if (hkNow != "" && lastInput >= keyAt - 50 && lastInput <= keyAt + (HkIsAny(hkNow, "boss,boost,player") ? 11000 : 600))
			acting := false
		}
	if (acting && !logged)
		{
		DebugLog("You're playing - the bot waits until you've left the keyboard and mouse alone for " secs " s"), logged := 1
		SpeedSet(0, "you're playing")
		}
	else if (!acting && logged)
		{
		DebugLog("You've stopped - the bot carries on")
		logged := 0
		;(the walker starts its watch afresh: you may have moved, and the time you played isn't it being stuck - a sigil's
		;wait goes on: WalkResume)
		if (IsFunc("WalkResume"))
			WalkResume.Call()
		else if (IsFunc("WalkReset"))
			WalkReset.Call()
		}
	PlayerActive := acting
	return acting
	}

;The bot on / off (F6, the tray menu, the dashboard's button): off, the main loop does nothing; keys held let go
BotToggle()
	{
	BotOn := !BotOn
	if (BotOn)
		{
		BotEverOn := 1
		;(turned on in a battle: what was played meanwhile isn't known - no kill check till it ends, and the boss
		;picked again with Alt+1)
		if (inbattle == 1)
			PlayerTookRound := 1, BossChoosen := 0, DebugLog("  (turned on in a battle: no kill check till it ends - " HkText("boss") " the boss again to put traps on it, else they go on the enemy with the most health)")
		;(the walker starts afresh: the wizard may have moved meanwhile)
		if (IsFunc("WalkReset"))
			WalkReset.Call()
		DebugLog("Bot on (" HkText("bot") ") - battles, quest walking and potions")
		TrayTip("Wizard101 bot", "On - battles, "4, 1")
		}
	else
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(your mouse let go at once - Settings.ahk MouseLockRelease)
		MouseLockRelease("the bot's off")
		if (IsObject(DeckBoss))
			DebugLog("Deck: no boss ahead now - " DeckBoss.name " (the bot's off)"), DeckBoss := ""
		DebugLog("Bot off (" HkText("bot") ") - it does nothing till " HkText("bot") " again")
		SpeedSet(0, "bot off", true)
		TrayTip("Wizard101 bot", "Off - the bot does nothing till you press " HkText("bot") " again.", 1)
		}
	BotOnShow()
	}

;A restart (Windows+1, Alt+Esc, the tray menu) that keeps the bot off or in standby - Reload drops the arguments
BotRestart()
	{
	arg := (BotStandby && !BotEverOn) ? "/standby" : (!BotOn ? "/off" : "")
	if (arg = "")
		{
		Reload()
		return
		}
	if (A_IsCompiled)
	{
		{   ErrorLevel := "ERROR"
		   Try ErrorLevel := Run("`"" A_ScriptFullPath "`" /restart " arg, A_ScriptDir, "", )
		}
	}
	else
	{
		{   ErrorLevel := "ERROR"
		   Try ErrorLevel := Run("`"" A_AhkPath "`" /restart `"" A_ScriptFullPath "`" " arg, A_ScriptDir, "", )
		}
	}
	}

;Walker.ahk's check before it presses a key or clicks for the game's menu: the bot on (F6) - or a potion run you
;started from the tray - and no key or mouse of yours since from (A_TickCount; 0: not looked at)
WalkHostOn(from := 0)
	{
	return (BotOn || PotionManual) && !(from && A_TickCount - UserIdle() > from)
	}

;The tray menu's tick and the dashboard's button for the bot on / off
BotOnShow()
	{
	if (BotOn)
		Tray.Check(HkMenu("bot"))
	else
		Tray.Uncheck(HkMenu("bot"))
	if (IsFunc("DashBotShow"))
		DashBotShow.Call(BotOn)
	}

;The tray menu's tick for "Open with Wizard101"
WatchShow()
	{
	if (WatchIsOn())
		Tray.Check(HkMenu("standby"))
	else
		Tray.Uncheck(HkMenu("standby"))
	}

;For Reconnect.ahk's hung-loading check: the game seen in the world since (tick) - the spellbook (out of battle) or a
;battle round's Pass; look: if not, looked for on screen now too (the main loop's own look can be a while ago)
BotWorldSeenSince(since, look := false)
	{
	if (BookSeenAt > since || PassSeenAt > since)
		return true
	if (!look)
		return false
	UpdateGameRect()
	ErrorLevel := !ImageSearch(&bwX, &bwY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
	if (ErrorLevel = 0)
		{
		BookSeenAt := A_TickCount
		return true
		}
	return PassButtonAt(&bwX, &bwY) = 0
	}

;For Reconnect.ahk: the bot on (F6), or a run from the tray
BotIsOn()
	{
	return BotOn || PotionManual
	}

;For the walker: no battle on - the spellbook (it only shows out of battle) seen in the last 2 s
BotNoBattle(since := 0)
	{
	return BookSeenAt > since && A_TickCount - BookSeenAt < 2000
	}

;"Bring Wizard101 to the front" (tray menu, dashboard button): gamefront in PlayerStats.txt, off unless it's 1
GameFrontOn()
	{
	;(Play for me: the game brought up whenever it's needed)
	return PlayForMe || (Stats.Has("gamefront") && Stats["gamefront"] = 1)
	}

;Turns it on/off and keeps it in PlayerStats.txt (gamefront)
GameFrontToggle()
	{
	;(the setting itself switched - not what Play for me makes of it)
	frontOn := !(Stats.Has("gamefront") && Stats["gamefront"] = 1)
	if (!StatsSet([["gamefront", frontOn ? 1 : 0]]))
		Stats["gamefront"] := frontOn ? 1 : 0 ;  V1toV2: Invalid Index errors?, try 'Stats.Push(<val>)'
	GameFrontShow()
	DebugLog("Bring Wizard101 to the front: " (frontOn ? "on - when the quest arrow shows or a battle round is up, and you've left the keyboard and mouse alone 3 s" : "off"))
	TrayTip("Wizard101 bot", "Bring Wizard101 to the front: " (frontOn ? "ON - when there's something to do (the quest arrow, a battle round)." : "OFF - click into Wizard101 yourself."), 1)
	}

;The tray menu's tick and the dashboard button's label
GameFrontShow()
	{
	frontOn := GameFrontOn()
	if (frontOn)
		Tray.Check("Bring Wizard101 to the front")
	else
		Tray.Uncheck("Bring Wizard101 to the front")
	if (IsFunc("DashFrontShow"))
		DashFrontShow.Call(frontOn)
	}

;Wizard101 to the front (gamefront on, it isn't): why - for debug.log; idle - only once you've left the keyboard and
;mouse alone 3 s (walking: what you type elsewhere mustn't end up in the game). WinActivate - never a click (the game's
;Crown shop is in its corner). force: gamefront off too (you've left the PC: nothing touched for 5 minutes). True if it's
;in front now
GameToFront(why, idle := true, force := false)
	{
	static saidAt := 0
	if ((!GameFrontOn() && !force) || GameActive())
		return GameActive()
	if (idle && UserIdle() < 3000)
		return false
	WinActivate("ahk_class " GameClass " ahk_exe " GameExe)
	ErrorLevel := !WinWaitActive("ahk_class " GameClass " ahk_exe " GameExe, , 1)
	front := GameActive()
	if (A_TickCount - saidAt > 30000)
		saidAt := A_TickCount, DebugLog((front ? "Wizard101 brought to the front - " : "Wizard101 couldn't be brought to the front (Windows wouldn't let it) - ") why)
	return front
	}

;"Wait while I play" (tray menu, dashboard button): handsoffon in PlayerStats.txt, on unless it's 0
HandsOffOn()
	{
	return !(Stats.Has("handsoffon") && !Stats["handsoffon"])
	}

;Turns "Wait while I play" on/off and keeps it in PlayerStats.txt (handsoffon)
HandsOffToggle()
	{
	waitOn := !HandsOffOn()
	if (!StatsSet([["handsoffon", waitOn ? 1 : 0]]))
		Stats["handsoffon"] := waitOn ? 1 : 0 ;  V1toV2: Invalid Index errors?, try 'Stats.Push(<val>)'
	HandsOffShow()
	DebugLog("Wait while I play: " (waitOn ? "on - the bot waits while you use the keyboard or mouse" : "off - the bot carries on while you play"))
	TrayTip("Wizard101 bot", "Wait while I play: " (waitOn ? "ON - the bot waits while you use the keyboard or mouse." : "OFF - the bot carries on even while you play."), 1)
	}

;The tray menu's tick and the dashboard button's label
;"Play for me" on/off - the dashboard's button (red off, green on), the tray menu. On: every check for you off (UserIdle) -
;the bot plays on as if you've left the PC, taking the mouse and the game's window whenever it needs them. F6 / F8 still
;stop it. On and off at a click - no box to type in (you asked, 2026-10-26: the pimpmeout box of 2026-10-23 gone). Never
;kept: off at every start
PlayForMeToggle()
	{
	PlayForMe := !PlayForMe
	PlayForMeShow()
	DebugLog("Play for me: " (PlayForMe ? "ON - every check for you is off: the bot takes the mouse and the game's window whenever it needs them (" HkText("bot") " stops it)" : "off - the bot waits for you and keeps its hands off while you play, as set"))
	TrayTip("Wizard101 bot", PlayForMe ? "PLAY FOR ME is on: the bot no longer waits for you - it takes the mouse and the game whenever it needs them. " HkText("bot") " stops it." : "Play for me is off: the bot waits for you again.", "PlayForMe ? 2 : 1")
	}

;The tray menu's tick and the dashboard's button (green while it's on)
PlayForMeShow()
	{
	if (PlayForMe)
		Tray.Check("Play for me (leave it alone for days)")
	else
		Tray.Uncheck("Play for me (leave it alone for days)")
	if (IsFunc("DashPlayShow"))
		DashPlayShow.Call(PlayForMe)
	;(Game to front's label too: Play for me brings the game up whatever it's set to)
	GameFrontShow()
	}

HandsOffShow()
	{
	waitOn := HandsOffOn()
	if (waitOn)
		Tray.Check("Wait while I play")
	else
		Tray.Uncheck("Wait while I play")
	if (IsFunc("DashHandsShow"))
		DashHandsShow.Call(waitOn)
	}

;Moves the mouse to x, y and clicks, quickly: mousespeed (0 = jump there, 1 = fastest glide; it used to
;be 5), clickwait ms before the click (used to be 150) plus up to clickrandom ms, and after it `after` ms
;times clickafter % (PlayerStats.txt, the Settings window; it used to wait the whole of it)
ClickAt(x, y, after := 0)
	{
	;(not in a battle round: the mouse goes back where it was after the click - mousereturn)
	ownGrab := MouseGrab()
	;(your mouse locked meanwhile - a battle round has it locked already: Settings.ahk MouseLockOn)
	MouseLockOn("click")
	MoveToCard(x, y)
	Sleep(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
	;(and a random bit more: clickrandom)
	if (Stat("clickrandom") > 0)
		{
		clickExtra := Random(0, Stat("clickrandom"))
		Sleep(clickExtra)
		}
	Click()
	if (after)
		AfterClick(after)
	if (ownGrab)
		MouseLetGo()
	MouseLockOff("click")
	}

;A wait after a click: ms times clickafter % (PlayerStats.txt; lower is faster)
AfterClick(ms)
	{
	Sleep(Round(ms * (Stats.Has("clickafter") ? Stats["clickafter"] : 50) / 100))
	}

;The mouse to x, y - a card in the hand from above: moved straight across the hand it passes over the cards between,
;the game zooms each up as it's hovered, and a zoomed card covers part of its neighbour - the click lands on it
;(2026-10-22: Sharpened Blade picked up, the click meant for the Balanceblade at the hand's end hit the greyed Sandstorm
;beside it and the enchant dropped). So: straight up above the hand, across, a moment for the zoom to go down, then
;down onto the card. Not on the hand's row (an enemy, Pass, yourself): straight there. Already on that card: just there
MoveToCard(x, y)
	{
	;(the bot still at it: the mouse lock's watchdog starts again - Settings.ahk MouseLockRenew; after each move, your
	;clicks swallowed now the pointer's on the game - MouseLockMoved)
	MouseLockRenew()
	top := ScreenY - Px(90), bottom := ScreenY + Px(80), above := ScreenY - Px(150)
	if (y < top || y > bottom)
		{
		MouseMove(x, y, MouseSpeedNow())
		MouseLockMoved()
		return
		}
	MouseGetPos(&mx, &my)
	if (Abs(mx - x) > Px(20) || my < top || my > bottom)
		{
		if (my >= top)
			MouseMove(mx, above, MouseSpeedNow())
		MouseMove(x, above, MouseSpeedNow())
		MouseLockMoved()
		Sleep(120)
		}
	MouseMove(x, y, MouseSpeedNow())
	MouseLockMoved()
	}

MouseSpeedNow()
	{
	return Stats.Has("mousespeed") ? Stats["mousespeed"] : 1
	}

CenterMouse()
	{
	UpdateGameRect()
	MouseLockRenew()
	MouseMove(ScreenX, ScreenY + Px(100), MouseSpeedNow())
	MouseLockMoved()
	}

;This bot's version (version.txt in its folder: v0.25.1...), "" if there's none
BotVersion()
	{
	static v := "-"
	if (v = "-")
		{
		v := FileRead(A_ScriptDir "\..\version.txt")
		v := Trim(v, " `t`r`n")
		}
	return v
	}

;The update check (Wiz-Maxxing /check): a newer version offered and installed if you say so, the bot then started
;again as it is now (off: /off, in standby: /standby). False (and a tray tip) if Wiz-Maxxing can't be started
UpdCheckNow()
	{
	updArg := UpdBotArgs(), updArg := updArg = "" ? "" : " " updArg
	if (BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/check" updArg, A_ScriptDir "\.."))
		return true
	TrayTip("Wizard101 bot", "Couldn't start Wiz-Maxxing for the update check (error " A_LastError ").", 2)
	return false
	}

;Updates by itself (Settings: autoupdate - you asked 2026-10-23, so Claude's fixes get tried with nobody at the PC).
;1. A newer release seen by the look-up (UpdPeekNow): Wiz-Maxxing /check /auto downloads it while the bot plays on.
;2. It's ready (updater.ini [auto] ready, by a Wiz-Maxxing still running - readypid): the bot closes itself at a safe
;point (UpdSafe), writing how it is (handover, args - UpdBotArgs), and Wiz-Maxxing installs it and starts it again so.
;Never closed under it. A version tried 3 times in 6 hours (Updater.ahk UpAuto) is left to the Updates button
UpdAuto()
	{
	static lookAt := 0, startAt := 0, ranAt := 0, saidTag := "", gaveUpTag := "", waitTag := "", aliveAt := 0, aliveTag := ""
	static alive := false
	if (A_TickCount - lookAt < 5000)
		return
	lookAt := A_TickCount
	startAt := startAt ? startAt : A_TickCount
	if (Stat("autoupdate") <= 0 || A_TickCount - startAt < 60000)
		return
	ini := A_ScriptDir "\..\updater.ini"
	ready := IniRead(ini, "auto", "ready", A_Space)
	if (ready != "" && VersionCompare(ready, BotVersion()) > 0)
		{
		;(the Wiz-Maxxing that downloaded it still waiting - UpdReadyAlive; looked at every 30 s, and again just before
		;closing)
		if (A_TickCount - aliveAt > 30000 || aliveTag != ready)
			alive := UpdReadyAlive(ini), aliveAt := A_TickCount, aliveTag := ready
		if (!alive)
			{
			aliveAt := 0
			return
			}
		;(the Updates button clicked meanwhile: closed for it as soon as it's out of battle - you asked)
		nowAsked := IniRead(ini, "auto", "now", 0)
		if (!UpdSafe(nowAsked := 1))
			{
			if (waitTag != ready)
				DebugLog("Updates: " ready " is downloaded - the bot closes for it once out of battle, nothing's loading and you've left the keys and mouse alone a minute")
			waitTag := ready
			return
			}
		if (!UpdReadyAlive(ini))
			{
			aliveAt := 0
			return
			}
		hand := UpdBotArgs()
		IniWrite(hand, ini, "auto", "args")
		IniWrite(1, ini, "auto", "handover")
		DebugLog("Updates: closing for " ready " - Wiz-Maxxing installs it and starts the bot again as it is now" (hand = "" ? "" : " (" hand ")"))
		ExitApp()
		}
	upd := UpdState()
	if (!upd.newer)
		return
	triedTag := IniRead(ini, "auto", "tag", A_Space)
	tries := IniRead(ini, "auto", "tries", 0)
	triedAt := IniRead(ini, "auto", "at", A_Space)
	age := A_Now
	age := DateDiff((age != "" ? age : A_Now), (triedAt != "" ? triedAt : A_Now), "Hours")
	if (triedTag = upd.latest && age != "" && age < 6 && tries >= 3)
		{
		if (gaveUpTag != upd.latest)
			DebugLog("Updates: " upd.latest " didn't install by itself in 3 tries (updater.log) - left to the Updates button")
		gaveUpTag := upd.latest
		return
		}
	;(one download at a time - another try 15 minutes on, if this one's come to nothing)
	if ((ranAt && A_TickCount - ranAt < 900000) || (A_IsCompiled && !FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe")))
		return
	ranAt := A_TickCount
	if (saidTag != upd.latest)
		DebugLog("Updates: " upd.latest " is out - downloading it (Settings: autoupdate); the bot plays on till it's ready")
	saidTag := upd.latest
	if (!BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/check /auto", A_ScriptDir "\.."))
		DebugLog("Updates: couldn't start Wiz-Maxxing to download " upd.latest " (error " A_LastError ")")
	}

;The Wiz-Maxxing that downloaded an update by itself still waiting for the bot to close (UpdAuto): its process there with
;/auto, under 58 minutes since it said ready (it waits an hour: never closed just as it gives up). Else - the PC restarted, it was ended - nothing to close for (a recycled
;process id taken for it would leave the bot closed): its marks cleared
UpdReadyAlive(ini)
	{
	readyPid := IniRead(ini, "auto", "readypid", 0)
	readyAt := IniRead(ini, "auto", "readyat", A_Space)
	age := A_Now
	age := DateDiff((age != "" ? age : A_Now), (readyAt != "" ? readyAt : A_Now), "Minutes")
	if (RegExMatch(readyPid, "^\d+$") && age != "" && age < 58)
		for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" readyPid)
			if (InStr(p.CommandLine, "/auto"))
				return true
	for i, k in ["ready", "readypid", "readyat", "now"]
		IniDelete(ini, "auto", k)
	return false
	}

;A safe point to close the bot for an update (UpdAuto; out of battle: its caller): nothing loading, no login or restart of
;the game going on, no dungeon run or recording under way, and the keyboard and mouse left alone a minute (Play for me:
;never waited for; anyNow: you clicked Update). The loading / reconnect state only counts while it's kept up to date -
;the bot on, auto-reconnect on and not told to leave the game closed ("stopped": it gave up - nothing going on)
UpdSafe(anyNow := false)
	{
	rcBusy := BotOn && RcOn && !RcNoRelaunch && (RcLoadAt || (RcState != "" && RcState != "stopped"))
	;(the game closed with no login to start it again with - or one it turned down: nothing going on either)
	if (rcBusy && !RcLoadAt && RcState = "gone" && (RcLoginBad || !RcHaveLogin()))
		rcBusy := false
	return !(BattleLogInBattle() || rcBusy || IsObject(DgRun) || DgRecording || PotionRecording
		|| (!anyNow && UserIdle() < 60000))
	}

;How the bot is, for starting it again so after an update (Wiz-Maxxing /check passes them on - StartBot): off or in
;standby, Play for me on, walking (F8) or auto-reconnect off, Learn every card on
UpdBotArgs()
	{
	a := (BotStandby && !BotEverOn) ? " /standby" : !BotOn ? " /off" : ""
	a .= (PlayForMe ? " /playforme" : "") (!Walking ? " /nowalk" : "") (!RcOn ? " /noreconnect" : "") (LearnAll ? " /learnall" : "")
	return Trim(a)
	}

;"v0.25.2" vs "v0.25.1" (vMAJOR.MAIN.BUG): 1 newer, 0 the same, -1 older; "" is older than any
VersionCompare(a, b)
	{
	if (a = b)
		return 0
	if (!RegExMatch(a, "(\d+)\.(\d+)(?:\.(\d+))?", &x))
		return -1
	if (!RegExMatch(b, "(\d+)\.(\d+)(?:\.(\d+))?", &y))
		return 1
	pa := [x[1] + 0, x[2] + 0, x[3] = "" ? 0 : x[3] + 0], pb := [y[1] + 0, y[2] + 0, y[3] = "" ? 0 : y[3] + 0]
	Loop 3
		{
		if (pa[A_Index] != pb[A_Index])
			return pa[A_Index] > pb[A_Index] ? 1 : -1
		}
	return 0
	}

;What the last look-up of the latest release said (updater.ini [latest], read at most every 5 s): {latest: its
;tag, err, newer: true when it's newer than this bot}
UpdState()
	{
	static state := "", readAt := 0
	if (!IsObject(state) || A_TickCount - readAt > 5000)
		{
		readAt := A_TickCount
		ini := A_ScriptDir "\..\updater.ini"
		latest := IniRead(ini, "latest", "tag", A_Space)
		err := IniRead(ini, "latest", "err", A_Space)
		state := {latest: Trim(latest), err: Trim(err), newer: Trim(latest) != "" && VersionCompare(Trim(latest), BotVersion()) > 0}
		}
	return state
	}

;A pixel distance measured at UI scale 1 (a 1920x1080 window, UI Size Small), at the UI size in use
Px(n)
	{
	return Round(n * UiScale)
	}

;Full path of a picture (e.g. "storm\hit1.png") in the picture set for the UI size in use; the main
;one if that set has no picture of its own for it (logged once)
PicPath(rel)
	{
	static missing := {}
	if (PicDir != A_WorkingDir)
		{
		;(a made set: the picture made at its size, see PicMake)
		p := PicSets[PicSet].gen ? PicMake(rel, PicSets[PicSet]) : PicDir "\" rel
		if (p != "" && FileExist(p))
			return p
		;A cut set without this picture: one made at its size from the other sets
		if (!PicSets[PicSet].gen)
			{
			p := PicMake(rel, {dir: GenRoot "\ui" Round(UiScale, 3), scale: UiScale})
			if (p != "" && FileExist(p))
				return p
			}
		if (!missing.Has(PicDir "|" rel))
			{
			missing[PicDir "|" rel] := 1 ;  V1toV2: Invalid Index errors?, try 'missing.Push(<val>)'
			DebugLog("  (no " rel " at UI size " Round(UiScale, 3) " and none to make it from - using the main picture, which won't match at this size)")
			}
		}
	return A_WorkingDir "\" rel
	}

;Switches to picture set i and sizes the search areas to its UI scale; why: what chose it (the log - every switch says
;why since 2026-10-25, when one at 23:14:47 didn't)
UsePicSet(i, why := "")
	{
	static upsUsed := 0
	upsWas := upsUsed ? PicSet : "", upsUsed := 1
	PicSet := i, PicDir := PicSets[i].dir, UiScale := PicSets[i].scale
	HandHalf := Px(400), HalfPitch := Px(41)
	DebugLog("Pictures: " (i = 1 ? "main set (UI scale 1)" : SubStr(PicDir, (StrLen(A_WorkingDir) + 2)<1 ? (StrLen(A_WorkingDir) + 2)-1 : (StrLen(A_WorkingDir) + 2)) " (UI scale " Round(UiScale, 3) (PicSets[i].gen ? (PicSets[i].copy ? ", the cut set's copy made 1:1" : ", made from the cut pictures") : "") ")") " - card area +-" HandHalf " px, card spacing " 2 * HalfPitch " px"
		. (why != "" ? " - " why : "") (upsWas != "" && upsWas != i ? " (was " PicSetName(upsWas) ")" : ""))
	}

;Finds the Wizard101 client area on screen so searches follow the window when it's moved or resized
UpdateGameRect()
	{
	hwnd := WinGetID("A")
	proc := WinGetProcessName("ahk_id " hwnd)
	cls := WinGetClass("ahk_id " hwnd)
	if (proc != GameExe) || (cls != GameClass)
		{
		;Active window isn't the game (e.g. one of our popups, or the game's short-lived D3DProxyWindow),
		;use the top-most real Wizard101 window instead
		gameHwnd := WinGetID("ahk_class " GameClass " ahk_exe " GameExe)
		if (!gameHwnd)
			{
			;Game not open: keep the last known position rather than measuring some other window
			return
			}
		hwnd := gameHwnd
		}
	if (!hwnd)
		{
		return
		}
	rect := Buffer(16, 0) ; V1toV2: if 'rect' is a UTF-16 string, use 'VarSetStrCapacity(&rect, 16)' and replace all instances of 'rect.Ptr' with 'StrPtr(rect)'
	pt := Buffer(8, 0) ; V1toV2: if 'pt' is a UTF-16 string, use 'VarSetStrCapacity(&pt, 8)' and replace all instances of 'pt.Ptr' with 'StrPtr(pt)'
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr)
	DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt.Ptr)
	w := NumGet(rect, 8, "Int")
	h := NumGet(rect, 12, "Int")
	if (w <= 0 || h <= 0)
		{
		;Minimized, keep the last known position
		return
		}
	GameLeft := NumGet(pt, 0, "Int")
	GameTop := NumGet(pt, 4, "Int")
	GameW := w
	GameH := h
	GameRight := GameLeft + w
	GameBottom := GameTop + h
	ScreenX := GameLeft + w // 2
	ScreenY := GameTop + h // 2
	}

TestSchool(class)
	{
	ErrorLevel := !ImageSearch(&schoolX, &schoolY, playerX - Px(100), playerY - Px(100), playerX + Px(250), playerY + Px(250), PicOpt(class "\" class ".png"))
	if (Errorlevel = 0)
		{
		school := class
		return true
		} else {
			return false
			}
	}
	
Tri(type1, type2) 
	{
	global
	visionHit := VisionFind("resources", type1 type2, typeX, typeY)
	if (visionHit = -1)
		{
		ErrorLevel := !ImageSearch(&typeX, &typeY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), PicOpt("resources\" type1 type2 ".png", CardTol))
		visionHit := (ErrorLevel = 0)
		}
	if (visionHit = 1)
		{
		%type2%2X := typeX
		%type2%2Y := typeY
		;(the blade found names the blade kind, the trap found the trap kind - each by itself: an Elemental Blade in hand no
		;longer stands for an Elemental Trap)
		%type2%type := type1 type2
		return true
		} else 
			{
			return false
			}
	}

ErrorBox(&funcN, &dir, &title)
	{
	if (devmode == 1)
		{
		n1 := "Error in " . funcN . " Function"
		n2 := "Directory: " PicPath(dir "\" title ".png")
		msgResult := MsgBox(n2 "`n`nWould You like to continue running script?", n1, "4 T5")
		if (msgResult = "Yes")
			{
			return
			}
		if (msgResult = "No")
			{
			ExitApp()
			}
		if (msgResult = "Timeout")
			{
			return
			}
		}
	}
	
Find(title, &card, &X, &Y, &dir)
	{
	global
	;(the vision helper, if it's running: 1 found, 0 not in hand)
	visionHit := VisionFind(dir, title, X, Y)
	if (visionHit >= 0)
		{
		card := visionHit
		return
		}
	ErrorLevel := !ImageSearch(&X, &Y, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(150), PicOpt(dir "\" title ".png", CardTol))
	if (Errorlevel == 0)	
		{
		card := 1
		} else if (Errorlevel == 1)
			{
			card := 0
			} else if (Errorlevel == 2)
				{
				ErrorBox(&"Find", &dir, &title)
				}
	}
	
Click(&title, &click, &dir)
	{
	global
	Find(title, &click, &clickX, &clickY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" click " at " clickX - GameLeft "," clickY - GameTop)
	if (click == 1)
		{
		ClickAt(clickX + Px(5), clickY + Px(5), 100)
		return true
		} else 
			{
			return false
			}
	}
	
;Your school's bubble (<school>\bubble - a global, all of the battle; the battle chain casts it before a hit, usebubble):
;by its picture (Click), or - no picture found it, or the picture may be on another global (KillCalc.ahk BubbleMem:
;BoostMemOnly["<school>/bubble"]) - at the game's card's box, only while the hand's boxes and the game's cards line up for
;sure (KillCalc.ahk BoostMemBox, as UseMemAt casts a Tower Shield); not sure: the picture's spot as before, unless there's
;none or the global already up may be under it (BubbleUpHeld). A global has no target: the card alone is clicked. The
;global it put up is noted (BubbleUp - the game's name: the same one isn't cast again this battle; the slot's learned card
;up already: its picture not clicked, the game's hand read or not). True if clicked; false: nothing was (the chain goes on
;to the next card)
ClickBubble()
	{
	global
	local cbKey, cbAt, cbName, cbSlot
	cbKey := BoostKey("bubble", hitschool)
	if (IsObject(BoostMemOnly) && BoostMemOnly.Has(cbKey))
		{
		cbAt := BoostMemBox(cbKey, 0, "", "")
		if (cbAt.x != "")
			{
			DebugLog("  " cbKey ": " (bubbleX != "" ? "its picture found a global, the game has another in hand too" : "no picture found it") " - the game's " cbAt.name " is card " cbAt.n " of " cbAt.of " in hand: cast at its box " cbAt.x - GameLeft "," cbAt.y - GameTop cbAt.note)
			ClickAt(cbAt.x, cbAt.y, 100)
			bubble := 1, BubbleUp := cbAt.name
			return true
			}
		if (bubbleX = "" || BubbleUpHeld())
			{
			DebugLog("  " cbKey ": in hand (the game), not cast: " cbAt.why (bubbleX != "" ? " - the global up already may be under its picture" : ""))
			bubble := 0
			return false
			}
		DebugLog("  " cbKey ": in hand (the game), its box not sure (" cbAt.why ") - its picture's spot")
		}
	;(the slot's picture is its learned card's own: that card the global the bot put up this battle - not cast again,
	;whether or not the game's hand is read this look: the hand still changing after a discard, the helper restarting...)
	cbSlot := BubbleSlotName(hitschool)
	if (BubbleUp != "" && cbSlot = BubbleUp)
		{
		if (IsObject(BoostSaid) && !BoostSaid.Has("up|" BubbleUp))
			BoostSaid["up|" BubbleUp] := 1, DebugLog("  " cbKey ": its picture is " cbSlot "'s, the global the bot put up this battle - not cast again") ;  V1toV2: Invalid Index errors?, try 'BoostSaid.Push(<val>)'
		bubble := 0
		return false
		}
	;(the game's name of the global the picture is on - the one every global in hand has, else the slot's learned card's
	;(KillCalc.ahk BubbleHandName) - before the hand changes; not known: the global known up stays known, never blanked)
	cbName := BubbleHandName()
	if (!Click(&"bubble", &bubble, &hitschool))
		return false
	if (cbName != "")
		BubbleUp := cbName
	return true
	}

;Pass: its picture in the hand's area (resources\pass.png - Click), else the round's Pass button where the round start
;finds it (PassButtonAt: resources\roundstart.png, or drawn hovered with the mouse on it) - clicked in its middle. A made
;pass.png can miss when roundstart.png matches (2026-10-25 at UI 1.130: made from the 1.265 cut, it missed 9 times running,
;the round start's Pass found each time at 984,829 - nothing cast, the same planning phase played again every 3 s till the
;timer ended it). True if clicked
ClickPass()
	{
	global
	local cpX, cpY
	if (Click(&"pass", &pass, &"resources"))
		return true
	if (PassButtonAt(&cpX, &cpY) != 0)
		return false
	DebugLog("  Click pass: found=1 at " cpX - GameLeft "," cpY - GameTop " - the round's Pass button" (PassHover ? ", drawn hovered" : "") ", as the round start finds it (pass.png missed it)")
	;(the button's middle: the Pass picture is 64 x 26 at UI 1 - 81 x 33 cut at 1.265)
	ClickAt(cpX + Px(32), cpY + Px(13), 100)
	pass := 1
	return true
	}

UseOnSelf(&title, &card, &dir) 
	{
	global
	Find(title, &card, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " foundX - GameLeft "," foundY - GameTop)
	;(no picture found it, the game's hand has it - Tower Shield: at its card box - UseMemAt)
	UseMemAt(title, dir, &card, &foundX, &foundY)

	if (card == 1)
		{
		ClickAt(foundX, foundY, 150)
		ClickAt(playerX, playerY, 150)
		}
	;(true if the card was in hand - clicked - as UseOnHammer: the solo filler goes on to Reshuffle when it wasn't)
	return card == 1
	}

;The card, then the hitter's plate (hammerX, hammerY) - or tx, ty (a party battle's ally). True if the card was in hand
UseOnHammer(&title, &card, &dir, tx := "", ty := "")
	{
	global
	Find(title, &card, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " foundX - GameLeft "," foundY - GameTop)
	;(no picture found it, the game's hand has it: at its card box - UseMemAt)
	UseMemAt(title, dir, &card, &foundX, &foundY)

	if (card == 1)
		{
		ClickAt(foundX, foundY, 150)
		ClickAt(tx != "" ? tx : hammerX, ty != "" ? ty : hammerY, 150)
		}
	return card == 1
	}

;A card dir\title no picture found that the game's hand has (KillCalc.ahk BoostSearch's BoostMemOnly - Tower Shield:
;TowerMem): card 1 and x, y its card box's middle - a fresh look at the hand's boxes laid on the game's cards, only while
;they line up for sure (KillCalc.ahk BoostMemBox, as UseBlade / UseTrap cast a blade or trap no picture found). Found by its
;picture while the game's hand has a Tower Shield and another shield the picture may be on (TowerMem): its card box the
;same way, else the picture's spot as found. False, nothing set: not one the game's hand found, or the boxes and the game's
;cards not lining up for sure
UseMemAt(title, dir, &card, &x, &y)
	{
	global BoostMemOnly, GameLeft, GameTop
	umaKey := BoostKey(title, dir)
	if (!IsObject(BoostMemOnly) || !BoostMemOnly.Has(umaKey))
		return false
	umaAt := BoostMemBox(umaKey, 0, "", "")
	if (umaAt.x = "")
		{
		DebugLog("  " umaKey ": in hand (the game), " (card == 1 ? "found by its picture - another shield's too? - its box not sure, the picture's spot: " : "no picture found it - not cast: ") umaAt.why)
		return false
		}
	umaPic := (card == 1)
	card := 1, x := umaAt.x, y := umaAt.y
	DebugLog("  " umaKey ": " (umaPic ? "its picture found a shield, the game has another shield in hand too" : "no picture found it") " - the game's " umaAt.name " is card " umaAt.n " of " umaAt.of " in hand: cast at its box " x - GameLeft "," y - GameTop umaAt.note)
	return true
	}

;The solo filler's absorb (the battle chain, when no Tower Shield went - 2026-10-26): one that costs no pips (AbsorbFreeOk -
;an X-pip or 3-pip one would spend what the next hit needs), on you - by its picture, else at its card box (UseOnSelf /
;UseMemAt with AbsorbOnlyFree: only such a card's box). With usetower and useabsorb (KillCalc.ahk AbsorbOn). True if clicked
AbsorbFiller()
	{
	global absorb, AbsorbFreeOk, AbsorbOnlyFree
	if (absorb != 1 || !AbsorbFreeOk || !AbsorbOn())
		return false
	AbsorbOnlyFree := 1
	afGo := UseOnSelf(&"absorb", &absorb, &"resources")
	AbsorbOnlyFree := 0
	return afGo
	}

;The battle chain's negative aura (KillCalc.ahk NegAuraMem - an Attenuate: +N% damage taken for 4 rounds): one that adds to
;the planned hit's schools (NegAuraMatches) at its card box - only while the hand's boxes and the game's cards line up for
;sure (BoostMemBox) -, then the trap rule's enemy (NegAuraWhere: the Alt+1 boss, else the one with the most health) - not
;one it went on in the last 4 rounds (NegAuraOn - the enemy by the game's memory's participant, else its most health, else
;its plate's place: KillCalc.ahk NegAuraKey, NegAuraWhen, NegAuraNote). Never by a picture (it has no slot). True if cast;
;false: nothing clicked, the chain goes on (said once a battle why)
UseNegAura()
	{
	global negaura, roundnumber, GameLeft, GameTop, BoostSaid
	if (negaura != 1 || !Stat("usetraps"))
		return false
	unHand := IsFunc("VisionCards") ? VisionCards.Call(300, 5000) : ""
	if (!IsObject(unHand) || !NegAuraMatches(unHand.cards).Length())
		{
		if (IsObject(BoostSaid) && !BoostSaid.Has("negaura|nofit"))
			BoostSaid["negaura|nofit"] := 1, DebugLog("  negaura: none in hand adds to the planned hit's schools - not cast") ;  V1toV2: Invalid Index errors?, try 'BoostSaid.Push(<val>)'
		return false
		}
	if (!NegAuraWhere(unX, unY, unKey, unWho))
		{
		DebugLog("  negaura: no enemy's plate found to put it on - not cast")
		return false
		}
	unWhen := NegAuraWhen(unKey)
	if (unWhen != "" && roundnumber - unWhen < 4)
		{
		DebugLog("  negaura: " unWho " has one from round " unWhen " (4 rounds) - not cast again yet")
		return false
		}
	unAt := BoostMemBox("negaura", 0, "", "")
	if (unAt.x = "")
		{
		DebugLog("  negaura: in hand (the game), not cast: " unAt.why)
		return false
		}
	DebugLog("  negaura: the game's " unAt.name " is card " unAt.n " of " unAt.of " in hand: cast at its box " unAt.x - GameLeft "," unAt.y - GameTop " on " unWho " (" unX - GameLeft "," unY - GameTop ")" unAt.note)
	ClickAt(unAt.x, unAt.y, 150)
	ClickAt(unX, unY, 200)
	NegAuraNote(unKey, roundnumber), negaura := 0
	return true
	}

UseBlade(&title, &blade, &Use1, &Use2, &dir)
	{
	global
	local ubKey, ubCp, ubSrc, ubItem, ubGo1, ubGo2, ubMoved, ubMem, ubAt, ubEnch
	Find(title, &blade, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" blade " at " foundX - GameLeft "," foundY - GameTop)

	;The hand may have re-centred since FindCards (a discard or a used enchant)
	Find("sharpen", &sharpen, &SharpX, &SharpY, &"resources")
	;(the game's hand read this look - KillCalc.ahk BoostSearch: which copy of the card this is. A pet's or gear's - an item
	;card - is never sharpened: it can't be enchanted. A treasure or item card's copy stacks with the deck's - the user,
	;2026-10-24 - so it goes once a battle besides the deck's casts; a copy that can't go swapped for one that can)
	ubKey := BoostKey(title, dir), ubSrc := "", ubItem := 0, ubMoved := 0, ubMem := 0, ubEnch := 0
	;(no picture found it but the game's hand has it - BoostSearch's BoostMemOnly: cast at its card box, a fresh look at the
	;hand's boxes laid on the game's cards - only while they line up for sure; that copy's own kind - KillCalc.ahk BoostMemBox)
	if (blade != 1 && IsObject(BoostMemOnly) && BoostMemOnly.Has(ubKey))
		{
		ubAt := BoostMemBox(ubKey, sharpen :== 1, Use1, Use2)
		if (ubAt.x = "")
			{
			DebugLog("  " ubKey ": in hand (the game), no picture found it - not cast: " ubAt.why)
			BoostOneOfBack("blade")
			return UseHeldBack("blade", title)
			}
		blade := 1, foundX := ubAt.x, foundY := ubAt.y, ubSrc := ubAt.src, ubItem := ubAt.item, ubMem := 1, ubEnch := ubAt.ench ? 1 : 0
		DebugLog("  " ubKey ": no picture found it - the game's " ubAt.name " is card " ubAt.n " of " ubAt.of " in hand: cast at its box " foundX - GameLeft "," foundY - GameTop ubAt.note)
		}
	else if (blade == 1 && IsObject(BoostHand) && BoostHand.Has(ubKey))
		{
		ubCp := BoostCopyPick(ubKey, foundX, foundY, sharpen :== 1, Use1, Use2)
		if (!IsObject(ubCp))
			{
			DebugLog("  " ubKey ": no copy in hand can be cast now (each one's casts used this battle, or one would need a Sharpen it can't get)")
			;(the blades held back this round for it go on instead - KillCalc.ahk BoostOneOf: the chain's next one; one before
			;it in the chain, which has passed it already, right here - UseHeldBack)
			BoostOneOfBack("blade")
			return UseHeldBack("blade", title)
			}
		ubSrc := ubCp.src, ubItem := ubCp.item, ubMoved := ubCp.moved
		}
	ubGo1 := (ubSrc = "") ? (Use1 != 1) : !BoostSrcUsed.Has(ubKey "@" ubSrc)
	ubGo2 := (ubSrc = "") ? (Use2 != 1) : ubGo1
	;(a copy that carries an enchantment already - only the game's hand finds one, KillCalc.ahk BoostMemBox: a plain copy
	;first - is never sharpened again: cast as it is, counted with the Sharpen it carries)
	if (sharpen == 1) && (blade == 1) && ubGo1 && !ubItem && !ubMoved && !ubEnch
		{
		boostX := SharpX
		ClickAt(SharpX, SharpY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has (one cast by the game's
		;hand: where the game's hand has it then - no picture finds it)
		if (ubMem)
			BoostSettleMem(ubKey, &foundX, &foundY, boostX)
		else
			BoostSettle(n, &foundX, &foundY, boostX)
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox(&"UseBlade", &dir, &title)
			}
			ClickAt(foundX, foundY, 150)
		if (title != "blade4")
			{
			ClickAt(hammerX, hammerY, 200)
			}
		boosts++
		if (ubSrc = "")
			Use1 := 1
		else
			BoostSrcUsed[ubKey "@" ubSrc] := 1 ;  V1toV2: Invalid Index errors?, try 'BoostSrcUsed.Push(<val>)'
		if BladeOnUs(title)
			{
			AddBoost(AppliedBlades, ubKey, Stat("sharpen"), ubSrc)
			}
		;(cast on you but not seen there - your plate or badge not read this round: noted, so reboost:1 casts it again after
		;a hit it fits - KillCalc.ahk ConsumeBoosts; not Alt+2's pick's or a party support's: those went on another wizard)
		else if (Manual != 1 && !PartySupport())
			BoostUnrec.Push(ubKey (ubSrc != "" ? "@" ubSrc : "") "+")
		return true
		} else if (blade == 1) && (ubGo2 || (ubEnch && ubGo1))
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was (not when it's another copy's box: BoostCopyPick; nor one
			;cast by the game's hand - its box: no picture finds it, and one that doesn't fit might match elsewhere)
			keepX := foundX, keepY := foundY
			if (!ubMoved && !ubMem)
				ErrorLevel := !ImageSearch(&foundX, &foundY, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(n, CardTol))
			if (ErrorLevel || ubMoved || ubMem)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox(&"UseBlade", &dir, &title)
				}
				ClickAt(foundX, foundY, 150)
			if (title != "blade4")
				{
				ClickAt(hammerX, hammerY, 200)
				}
			boosts++
			;(an enchanted copy takes the sharpened cast's flag while it's free)
			if (ubSrc != "")
				BoostSrcUsed[ubKey "@" ubSrc] := 1 ;  V1toV2: Invalid Index errors?, try 'BoostSrcUsed.Push(<val>)'
			else if (ubEnch && Use1 != 1)
				Use1 := 1
			else
				Use2 := 1
			if BladeOnUs(title)
				{
				AddBoost(AppliedBlades, ubKey, ubEnch ? Stat("sharpen") : 0, ubSrc)
				}
			;(cast on you but not seen there: noted, as above)
			else if (Manual != 1 && !PartySupport())
				BoostUnrec.Push(ubKey (ubSrc != "" ? "@" ubSrc : "") (ubEnch ? "+" : ""))
			return true
			} else
				{
				return false
				}
	}

UseTrap(&title, &trap, &Use1, &Use2, &dir)
	{
	global
	local utKey, utCp, utSrc, utItem, utGo1, utGo2, utMoved, utMem, utAt, utEnch
	Find(title, &trap, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" trap " at " foundX - GameLeft "," foundY - GameTop)

	;The hand may have re-centred since FindCards (a discard or a used enchant)
	Find("potent", &potent, &PotentX, &PotentY, &"resources")
	;(which copy of the card this is, as UseBlade: an item card's never made potent; a treasure or item card's goes once a
	;battle besides the deck's)
	utKey := BoostKey(title, dir), utSrc := "", utItem := 0, utMoved := 0, utMem := 0, utEnch := 0
	;(no picture found it but the game's hand has it: cast at its card box, as UseBlade's)
	if (TrapOn == 1 && trap != 1 && IsObject(BoostMemOnly) && BoostMemOnly.Has(utKey))
		{
		utAt := BoostMemBox(utKey, potent :== 1, Use1, Use2)
		if (utAt.x = "")
			{
			DebugLog("  " utKey ": in hand (the game), no picture found it - not cast: " utAt.why)
			if (utKey != "feint" && utKey != "trap4")
				{
				BoostOneOfBack("trap")
				return UseHeldBack("trap", title)
				}
			return false
			}
		trap := 1, foundX := utAt.x, foundY := utAt.y, utSrc := utAt.src, utItem := utAt.item, utMem := 1, utEnch := utAt.ench ? 1 : 0
		DebugLog("  " utKey ": no picture found it - the game's " utAt.name " is card " utAt.n " of " utAt.of " in hand: cast at its box " foundX - GameLeft "," foundY - GameTop utAt.note)
		}
	else if (TrapOn == 1 && trap == 1 && IsObject(BoostHand) && BoostHand.Has(utKey))
		{
		utCp := BoostCopyPick(utKey, foundX, foundY, potent :== 1, Use1, Use2)
		if (!IsObject(utCp))
			{
			DebugLog("  " utKey ": no copy in hand can be cast now (each one's casts used this battle, or one would need a Potent it can't get)")
			;(the traps held back this round for it go on instead - KillCalc.ahk BoostOneOf; not for a Feint or trap4: they
			;aren't among those it picks from, so nothing was held back for them; one before it in the chain right here -
			;UseHeldBack)
			if (utKey != "feint" && utKey != "trap4")
				{
				BoostOneOfBack("trap")
				return UseHeldBack("trap", title)
				}
			return false
			}
		utSrc := utCp.src, utItem := utCp.item, utMoved := utCp.moved
		}
	utGo1 := (utSrc = "") ? (Use1 != 1) : !BoostSrcUsed.Has(utKey "@" utSrc)
	utGo2 := (utSrc = "") ? (Use2 != 1) : utGo1
	;(a copy already potent - the game's hand finds one: cast as it is, counted potent - as UseBlade's)
	if (TrapOn == 1) && (potent == 1) && (trap == 1) && utGo1 && !utItem && !utMoved && !utEnch
		{
		boostX := PotentX
		ClickAt(potentX, potentY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has (by the game's hand for
		;one cast so)
		if (utMem)
			BoostSettleMem(utKey, &foundX, &foundY, boostX)
		else
			BoostSettle(n, &foundX, &foundY, boostX)
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox(&"UseTrap", &dir, &title)
			}
		ClickAt(foundX, foundY, 150)
		ClickAt(TrapAtX, TrapAtY, 200)
		boosts++
		if (utSrc = "")
			Use1 := 1
		else
			BoostSrcUsed[utKey "@" utSrc] := 1 ;  V1toV2: Invalid Index errors?, try 'BoostSrcUsed.Push(<val>)'
		;(the kill check counts them on the enemy they went on - the boss's, the one with the most health: KillCalc.ahk
		;TrapPut; a party support's aren't)
		if (BossChoosen == 1 || TrapMine)
			TrapPut(utKey, Stat("potent"), utSrc)
		return true
		} else if (TrapOn == 1) && (trap == 1) && (utGo2 || (utEnch && utGo1))
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was (not when it's another copy's box: BoostCopyPick, nor one
			;cast by the game's hand)
			keepX := foundX, keepY := foundY
			if (!utMoved && !utMem)
				ErrorLevel := !ImageSearch(&foundX, &foundY, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(n, CardTol))
			if (ErrorLevel || utMoved || utMem)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox(&"UseTrap", &dir, &title)
				}
			ClickAt(foundX, foundY, 150)
			ClickAt(TrapAtX, TrapAtY, 200)
			boosts++
			if (utSrc != "")
				BoostSrcUsed[utKey "@" utSrc] := 1 ;  V1toV2: Invalid Index errors?, try 'BoostSrcUsed.Push(<val>)'
			else if (utEnch && Use1 != 1)
				Use1 := 1
			else
				Use2 := 1
			if (BossChoosen == 1 || TrapMine)
				TrapPut(utKey, utEnch ? Stat("potent") : 0, utSrc)
			return true
			} else 
				{
				return false
				}
	}

;The blades (kind "blade") or traps ("trap") BoostOneOf held back, set again by BoostOneOfBack because the one it kept
;(title) can't go after all: those before it in the battle chain (blade, blade2, blade3 / trap, trap2) the chain has
;passed already - tried here, in the chain's order; those after it the chain reaches itself. True if one was cast. (Its
;own function: inside UseBlade the name blade is the ByRef parameter; it can't loop - BoostOneOfBack empties its list)
UseHeldBack(kind, title)
	{
	global
	if (kind = "blade")
		{
		if (title != "blade" && blade == 1 && UseBlade(&"blade", &blade, &used%BladeU1%, &used%BladeU2%, &BladeDir))
			return true
		if ((title = "blade3" || title = "blade4") && blade2 == 1 && UseBlade(&bladetype, &%bladetype%, &used%Blade2U1%, &used%Blade2U2%, &"resources"))
			return true
		if (title = "blade4" && blade3 == 1 && UseBlade(&"blade3", &blade3, &used15, &used16, &"resources"))
			return true
		return false
		}
	if (title != "trap" && trap == 1 && UseTrap(&"trap", &trap, &used%TrapU1%, &used%TrapU2%, &TrapDir))
		return true
	if (title = "trap3" && trap2 == 1 && UseTrap(&traptype, &%traptype%, &used%Trap2U1%, &used%Trap2U2%, &"resources"))
		return true
	return false
	}

;Your school's prism (<school>\convert) on the boss picked with Alt+1 (the chain asks NeedsConvert first: it's of your
;school): by its picture, else - no picture found it, the game's hand has it (KillCalc.ahk ConvertMem) - at its card box
;(UseMemAt); then the boss. True if clicked (before 2026-10-26 it clicked where the picture had been even when it wasn't
;found again, and gave nothing back - the chain went on to the next card). Noted as on the boss till a hit of yours goes
;out (ConvertOn: your hits counted now - KillCalc.ahk ConvertUp)
UseConvert(&title, &convert, &dir)
	{
	global
	CenterMouse()
	Find(title, &convert, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" convert " at " foundX - GameLeft "," foundY - GameTop)
	UseMemAt(title, dir, &convert, &foundX, &foundY)
	if (convert != 1)
		return false
	ClickAt(foundX, foundY, 150)
	ClickAt(bossX, bossY, 200)
	ConvertOn := {hits: PartyHits ? PartyHits : 0, round: roundnumber}
	return true
	}
	
UseHit(&title, &hit, &dir, useEnchant := 1)
	{
	global
	;Saving pips for a hit that ends the battle (PlanPips): no other hit spends them. The wand's card is free,
	;but it uses up blades, traps and an enchant: only when the saved hit kills without them, unenchanted
	if (PipSaveFor != "" && title != PipSaveFor && (title != "wand" || !PipSaveBare))
		{
		DebugLog("  " title ": not cast - saving pips for " PipSaveFor)
		return false
		}
	if (PipSaveFor != "" && title = "wand")
		useEnchant := 0
	;(never on an item card - the wand's own, a pet's or gear's: it can't be enchanted - the user, 2026-10-24; the game's
	;hand or the learned card says which is one - KillCalc.ahk HitHeads)
	if (useEnchant && (title = "wand" || HitHeads(title).item))
		useEnchant := 0
	Find(title, &hit, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" hit " at " foundX - GameLeft "," foundY - GameTop)

	;Can you pay for it yet? If not, keep it for a later round (no click, no enchant used on it)
	if (hit == 1) && !Affordable(title)
		{
		DebugLog("  " title " costs more pips than you have (" PipsNow "): keeping it for later")
		hit := 0
		return false
		}
	;The hand may have re-centred since FindCards (a discard or a used enchant)
	if (useEnchant)
		FindEnchant()
	if (useEnchant) && (enchant >= 1) && (hit == 1) && !EnchantedHits[title]
		{
		EnchantedHits[title] := enchant ;  V1toV2: Invalid Index errors?, try 'EnchantedHits.Push(<val>)'
		boostX := enchantX
		ClickAt(enchantX, enchantY, 150)
		ClickAt(foundX, foundY, 150)
		CenterMouse()	
		n := PicPath(dir "\" title ".png")
		;The boost card left the hand and the hand re-centres, so the card moves: go as soon as it has
		BoostSettle(n, &foundX, &foundY, boostX)
		;The enchant card is used up and the hand has shifted
		FindEnchant()
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox(&"UseHit", &dir, &title)
			}
		ClickAt(foundX, foundY)
		HitTarget(title, dir, 0, HitDamage(title, false, BossChoosen :== 1))
		return CastResult(title, &hit, dir, 1)
		} else if (hit == 1)
			{
			n := PicPath(dir "\" title ".png")
			;If the card can't be found again, click where it was
			keepX := foundX, keepY := foundY
			ErrorLevel := !ImageSearch(&foundX, &foundY, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(n, CardTol))
			if (ErrorLevel)
				foundX := keepX, foundY := keepY
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox(&"UseHit", &dir, &title)
				}
			ClickAt(foundX, foundY)
			HitTarget(title, dir, 0, HitDamage(title, false, BossChoosen :== 1))
			return CastResult(title, &hit, dir, 0)
			} else
				{
				return false
				}
	}	
	
;A name plate's health - the red cur/max under its name (nx, ny: where the name starts) - read by the helper by its
;digits' shape (VisionPlate: 3 votes, 2 when a glyph's only fairly like its picture), else by OCR at four sizes, what at
;least two of them agree on: {cur, max, votes} ("" not read for sure). Yours (OwnHealthLow), an ally's (Party.ahk)
PlateHealth(nx, ny)
	{
	local x, y, w, h, t, a, key, n, best, bestN, zoom, gl, votes, phLines, phW, vp
	;(2026-10-23, 1440p: OCR read 2,848/3,153 at 1 of its 8 tries - none of the round's 4 reads of yours came out)
	;(the box ends above the pips - a Balance pip's red joins the digits: from ny + Px(50))
	vp := VisionPlate(nx - Px(22), ny + Px(10), nx + Px(165), ny + Px(43))
	if (IsObject(vp))
		return (AHKv1v2_Temp := {cur: vp.cur, max: vp.max, votes: vp.worst < 0.2 ? 3 : 2}, AHKv1v2_Temp) ; V1toV2: Wrapped Multi-statement return with parentheses
	;(110 wide first; not read: 150 - a four-figure health, 1,772/3,153, runs past 110 and its last figure is cut, never
	;read: 2026-10-23 - the wider box takes in more of what's round it, so it's only the second try)
	for each, phW in [110, 150]
		{
		x := nx - Px(8), y := ny + Px(20), w := Px(phW), h := Px(24)
		;(its 3s, 5s and 8s told by their shape - the OCR reads 1,234 as 1,254: KillCalc.ahk HealthGlyphs)
		gl := HealthGlyphs(x - Px(20), y, w + Px(40), h)
		;(the game's digits fool OCR now and then - B for 8, a 3 for an 8 - so it reads at four sizes and
		;takes what at least two of them read)
		votes := {}, best := "", bestN := 0
		for each2, zoom in [2, 3, 4, 5]
			{
			t := OcrRect(x, y, w, h, "en", zoom, phLines, 1)
			if (ErrorLevel)
				continue
			t := StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(t, "B", "8"), "O", "0"), "o", "0"), "S", "5"), "l", "1"), "I", "1")
			a := ParseHealth(HealthDigits(t, gl))
			if (!IsObject(a) || a.Length != 1)
				continue
			key := a[1].cur "/" a[1].max, n := votes.Has(key) ? votes[key] + 1 : 1, votes[key] := n ;  V1toV2: Invalid Index errors?, try 'votes.Push(<val>)'
			if (n > bestN)
				best := a, bestN := n
			}
		if (bestN >= 2 && best[1].max > 0)
			return {cur: best[1].cur, max: best[1].max, votes: bestN}
		}
	return ""
	}

;Your own health off your name plate (the red cur/max under your name), read by OCR at two sizes that
;must agree. True if it's under healat % (PlayerStats.txt, default 40). Logged each round it's read
;quiet: only read (and logged) - not a heal's question (EnemySpells.ahk's look). Read once a round: a second ask in the same
;round (within 15 s) uses that reading (OwnHpCur, OwnHpMax, OwnHpVotes)
OwnHealthLow(quiet := false)
	{
	global
	local pct, limit, bestN, cur, most, r
	limit := StatOr("healat", 40)
	if (OwnHpCur != "" && OwnHpRound = roundnumber && A_TickCount - OwnHpAt < 15000 && OwnHpWin = WinExist("A"))
		{
		cur := OwnHpCur, most := OwnHpMax, bestN := OwnHpVotes
		Goto("OwnHealthLowRead")
		Return ; V1toV2: post-return for Goto
		}
	r := PlateHealth(playerX, playerY)
	if (!IsObject(r))
		{
		DebugLog("  own health: couldn't read it for sure" (VisionPlateWhy != "" ? " (by shape: " SubStr(VisionPlateWhy, 1, 80) ")" : ""))
		return false
		}
	cur := r.cur, most := r.max, bestN := r.votes
	;(your most health, for the potions out of battle)
	PotionNoteMax(most)
	OwnHpCur := cur, OwnHpMax := most, OwnHpAt := A_TickCount, OwnHpVotes := bestN, OwnHpWin := WinExist("A")
OwnHealthLowRead:
	pct := Round(100 * cur / most)
	;(for saving pips: not while your health is low)
	OwnHpPct := pct, OwnHpRound := roundnumber
	if (quiet)
		{
		DebugLog("  own health: " cur "/" most " (" pct "%)")
		return pct < limit
		}
	;(healing on a misread wastes the card - e.g. 775 read as 75 by two sizes - so a low reading needs
	;three of the four sizes to agree)
	if (pct < limit && bestN < 3)
		{
		DebugLog("  own health: read " cur "/" most " only " bestN " times out of 4 - not sure enough to heal")
		return false
		}
	DebugLog("  own health: " cur "/" most " (" pct "%)" (pct < limit ? " - under " limit "%: healing" : ""))
	return pct < limit
	}

;A healing card on yourself: the card, then your own name plate (a heal for one wizard asks who; one that
;heals only you or everyone doesn't, and the extra click does nothing). tx, ty: an ally's plate instead (a party
;battle's healer) - a heal that went out with the card's click, not asking who: one that heals all of you (its learned
;text says "all") kept as <school>.healNtarget:2, still used on an ally; one that heals only you :0, not used on an ally
;again (a heal slot learned afresh asks again: CardLearn.ahk). True if it was cast
UseHeal(title, &card, dir, tx := "", ty := "")
	{
	global
	local lc, allOf
	Find(title, &card, &foundX, &foundY, &dir)
	DebugLog("  " A_ThisFunc " " title ": found=" card " at " foundX - GameLeft "," foundY - GameTop)
	if (card != 1)
		return false
	if !Affordable(title)
		{
		DebugLog("  " title " costs more pips than you have (" PipsNow ")")
		return false
		}
	ClickAt(foundX, foundY, 300)
	if (tx = "")
		ClickAt(playerX, playerY)
	else if (Stats[dir "." title "target"] = 2)
		DebugLog("  " title " heals all of you - the ally too")
	else if (!TargetPending())
		{
		lc := IsFunc("LearnCardInSlot") ? LearnCardInSlot.Call(dir "\" title) : ""
		allOf := IsObject(lc) && RegExMatch(lc.text, "i)\ba[l1][l1]\b")
		StatsSet([[dir "." title "target", allOf ? 2 : 0]])
		DebugLog("  " title " went out without asking who - " (allOf ? "it heals all of you: still used on an ally (" dir "." title "target:2)" : "it heals only you: not used on an ally again (" dir "." title "target:0)"))
		}
	else
		{
		if (!Stats.Has(dir "." title "target"))
			StatsSet([[dir "." title "target", 1]])
		TargetClick(tx, ty)
		DebugLog("  " title ": the ally's plate clicked at " tx - GameLeft "," ty - GameTop)
		}
	;(a heal: the blades and traps out stay - the kill check still counts them)
	return CastResult(title, &card, dir, 0, false)
	}

;A hit that strikes one enemy (<school>.hitNtarget:1 in PlayerStats.txt, e.g. Scarab) waits for a target
;after its card is clicked: click the boss if one was picked (Alt+1), else the enemy with the least
;health, else the leftmost one (their nameplates along the top). All-enemy hits need nothing
HitTarget(title, dir, force := 0, dmg := "")
	{
	global
	local key, i, e, pick, tx, ty, eff, best, why
	key := dir "." title "target"
	;(force: a learned hit in no slot that needs a target - its card says so, not PlayerStats.txt)
	if (!force && (!Stats.Has(key) || Stats[key] != 1))
		return
	;(the plates as they are now - not as they were when last read: the kill check's off for a battle you played a
	;round in, and an enemy gone since leaves its place behind)
	if (BossChoosen != 1 && A_TickCount - EnemyPlatesAt > 8000)
		ReadEnemyHealth()
	if (BossChoosen == 1)
		tx := BossX, ty := BossY, pick := "the boss"
	else if (EnemyPlates.Length)
		{
		;(the enemy the hit does the most to - HitPick)
		pick := HitPick(dmg), why := ""
		if (dmg > 0 && IsObject(EnemyHP) && EnemyHP.Length > 1 && EnemyHP.Length = EnemyPlates.Length)
			why := ", " Min(dmg, EnemyHP[pick].cur) " of its " dmg " damage on it" (dmg >= EnemyHP[pick].cur ? " - kills it" : "")
		tx := EnemyPlates[pick].x, ty := EnemyPlates[pick].y
		pick := "enemy " pick " of " EnemyPlates.Length (IsObject(EnemyHP) ? " (" EnemyHP[pick].cur " health" why ")" : "")
		}
	else
		{
		DebugLog("  " title " needs a target, but no enemy nameplate was found to click")
		return
		}
	;(the game asking for a target a moment after the card's clicked: then the plate hovered, then clicked)
	AfterClick(600)
	if (!TargetClick(tx, ty))
		return
	DebugLog("  " title ": clicked " pick " as the target at " tx - GameLeft "," ty - GameTop)
	;(a click on a nameplate doesn't always take: the round's still waiting - its Pass button there - 0.8 s later:
	;once more, on the plate's health line just under the name)
	if (TargetPending())
		{
		TargetClick(tx, ty + Px(20))
		DebugLog("  " title ": the target click didn't take - clicked the plate again at " tx - GameLeft "," ty + Px(20) - GameTop)
		}
	}

;Which enemy a hit on one enemy goes for (HitTarget; KillCalc.ahk TrapTarget: the planned hit's target): the one it does
;the most to - the least of its damage dmg and that enemy's health: not a big hit thrown at one nearly dead while another's
;at full (2026-10-23, a Hydra); one it kills, the healthiest of those; none, the weakest - the first to go. Its damage not
;known: the weakest. Equal: the leftmost. Health not read: the leftmost plate (1). among: only those slots ({slot: 1}), ""
;all. Its slot in EnemyPlates
HitPick(dmg, among := "")
	{
	global EnemyHP, EnemyPlates
	hpPick := "", hpBest := ""
	if (IsObject(EnemyHP) && EnemyHP.Length = EnemyPlates.Length)
		for hpI, hpE in EnemyHP
			{
			if (IsObject(among) && !among.Has(hpI))
				continue
			hpEff := (dmg > 0) ? Min(dmg, hpE.cur) : -hpE.cur
			if (hpBest = "" || hpEff > hpBest || (hpEff = hpBest && hpE.cur < EnemyHP[hpPick].cur))
				hpPick := hpI, hpBest := hpEff
			}
	return (hpPick = "") ? 1 : hpPick
	}

;A target clicked: the mouse there, a moment on it (the game takes a nameplate click better hovered), the click;
;the mouse back where it was afterwards (MouseGrab: mousereturn)
TargetClick(x, y)
	{
	;(never in the Crown shop's corner - SHOP and EARN CROWNS at its top left, to about Px(170): an enemy's plate read
	;that far left isn't clicked)
	if (x < GameLeft + Px(185) && y < GameTop + Px(110))
		{
		DebugLog("  a target click at " x - GameLeft "," y - GameTop " is in the Crown shop's corner - not clicked")
		return 0
		}
	ownGrab := MouseGrab()
	;(your mouse locked meanwhile - Settings.ahk MouseLockOn)
	MouseLockOn("click")
	MouseMove(x, y, MouseSpeedNow())
	;(a battle move: the round's hold renewed, your clicks swallowed now the pointer's on the game - Settings.ahk
	;MouseLockRenew)
	MouseLockRenew()
	Sleep(Max(150, Stats.Has("clickwait") ? Stats["clickwait"] : 40))
	Click()
	if (ownGrab)
		MouseLetGo()
	MouseLockOff("click")
	return 1
	}

;The round's Pass button (resources\roundstart.png) - or as Wizard101 draws it with the mouse on it: white, not yellow
;(roundstart_hover.png, cut 2026-10-23 at 1440p - the mouse left on Pass hid two battles' first rounds that afternoon).
;ErrorLevel as ImageSearch's - 0 found (x, y its top left), 1 not, 2 the picture can't be opened - and returned;
;PassHover 1 when it was the hovered one
PassButtonAt(&x, &y)
	{
	ErrorLevel := !ImageSearch(&x, &y, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundstart.png"))
	pbErr := ErrorLevel, PassHover := 0
	if (pbErr = 1)
		{
		;(the main set - UI 1 - has none of its own: one made from the 1.144 cut, in a folder that isn't a picture set)
		hp := (PicDir = A_WorkingDir && !FileExist(A_WorkingDir "\resources\roundstart_hover.png"))
			? PicMake("resources\roundstart_hover.png", {dir: GenRoot "\main", scale: 1.0}) : PicPath("resources\roundstart_hover.png")
		if (hp != "")
			{
			ErrorLevel := !ImageSearch(&x, &y, GameLeft, GameTop, GameRight, GameBottom, PicOptFile(hp))
			if (ErrorLevel = 0)
				pbErr := 0, PassHover := 1
			}
		}
	ErrorLevel := pbErr
	return pbErr
	}

;True while the round still waits for us 0.8 s on: its Pass button is still there (a target click that took starts
;the cast and the button goes)
TargetPending()
	{
	t0 := A_TickCount
	while (A_TickCount - t0 < 800)
		{
		Sleep(100)
		if (PassButtonAt(&pendX, &pendY))
			return false
		}
	return true
	}

Switch()
	{
	if (dualmode == 1)
		{
		Send("{Alt down}")
		Send("{Tab down}")
		Send("{Alt up}")
		Send("{Tab up}")
		}
	}
	
s(time) 
	{
	Sleep(time)
	}
	
Respond(Text) 
	{
	if (responcemode == 1)
		{
		BlockInput("Send")
		Send("{r}")
		s(100)
		SendInput("{Raw}" Text)
		Send("{Enter}")
		}
	}
	
Spam(key)
	{
	Send("{" key "}")
	Send("{" key "}")
	Send("{" key "}")
	}
	
ResetUsed()
	{
	;Assume-global so used1..used52 are the battle code's flags, not locals that vanish on return (21-52: each school's
	;blade and trap, the spirit ones - KillCalc.ahk KeyFlags); and the treasure / item copies cast (BoostSrcUsed), the
	;blades cast on you that weren't seen there (BoostUnrec: UseBlade)
	global
	local n := 0
	while (n <= 52)
		{
		used%n% := 0
		n++
		}
	BoostSrcUsed := {}, BoostUnrec := []
	}
	
ResetVariables() 
	{
	global
	inbattle := 0
	roundnumber := 0
	playerX := 0
	playerY := 0
	Player := ""
	BossChoosen := 0
	boosts := 0
	BoostRun := 0
	sharpen := 0 
	potent := 0
	blade := 0
	blade2 := 0
	blade3 := 0
	blade4 := 0
	trap := 0
	trap2 := 0
	trap3 := 0
	trap4 := 0
	feint := 0
	aura := 0
	enchant := 0 
	reshuffle := 0
	hit1 := 0
	hit2 := 0
	hit3 := 0
	hit4 := 0
	EnchantedHits := {}
	PipSaveFor := "", PipSaveRounds := 0, PipSaveGaveUp := 0, PipSaveTarget := "", PipSaveStall := 0, PipSaveLastPips := -1
	PlayerTookRound := 0, RoundLeft := 0, RoundAgain := 0
	;(the no-hits flee counts afresh - Flee.ahk; treasure cards drawn for an enchant too - Draw.ahk)
	FleeNoHits := 0, FleeHitsRound := ""
	DrawsBattle := 0, DrawOff := "", LearnHitFails := {}
	OwnHpPct := 0, OwnHpRound := -1
	tower := 0  
	hitter := 0
	hitschool := ""
	hammerX := 0
	hammerY := 0
	hitterX := 0
	hitterY := 0
	school := ""
	schoolX := 0
	schoolY := 0
	bladetype := ""
	traptype := ""
	;(a party battle's roles - and Alt+2's pick, for that battle only)
	BattleRole := "", HammerSchool := "", HammerName := "", HammerSlot := 0, HammerGroup := "", SidePlatesKey := "", MySlot := 0
	PartyHitsSeen := "", PartyHitsDuel := "", PartyHitsWait := "", PartyLowKey := "", PartyLowX := "", PartyLowY := "", TrapOn := 0
	TrapMine := 0, TrapAtMax := "", TrapPick := 0, TrapWhy := "", TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0, TrapSlot := 0
	PartyFlagDuel := "", PartyFlagRound := {}, PartyCastRound := ""
	Manual := 0, ManualSchool := ""
	bossX := 0
	bossY := 0
	AppliedBlades := {}
	BossTraps := {}
	AuraRounds := 0
	;(blades and traps by damage school - KillCalc.ahk; SlotGame is kept: the slots' cards don't change with the battle)
	HeadsMemo := {}, BoostPctMem := {}, AuraSch := "", PartyLastSch := "", PlanHit := "", PlanHeads := "", PlanList := ""
	BladeDir := "", TrapDir := "", BladeU1 := "", BladeU2 := "", TrapU1 := "", TrapU2 := "", Blade2U1 := "", Blade2U2 := "", Trap2U1 := "", Trap2U2 := ""
	SbFound := {}, GbFound := {}, BoostHand := {}, BoostSrcUsed := {}, BoostExtra := "", HammerPlan := "", BoostMemOk := 0, BoostSaid := {}, BoostMisfitDone := 0
	BoostUnrec := [], BoostOneOfOff := {}, BoostMemOnly := {}, BubbleUp := ""
	;(the negative auras put up this battle, an absorb or one in hand, your prism on the boss - 2026-10-26)
	NegAuraOn := {}, absorb := 0, AbsorbFreeOk := 0, AbsorbOnlyFree := 0, negaura := 0, ConvertOn := ""
	EnemyHP := ""
	BossSlot := 0
	BossMax := 0
	DualBattle := 0
	HealthStatus := ""
	ToolTip(, , , 20)
}
	
;Whether the boss picked with Alt+1 needs your school's prism (the chain's convert): the game's memory says it's of your
;school - it resists your hits (KillCalc.ahk ConvertNeedMem, read-only). Not known - the memory not read: no. (Before
;2026-10-26 it looked for <school>\convertN.png by the boss with a folder that was always blank, so it never found it - a
;10 px badge at tolerance 100 would match about anything: not looked for). Your prism on it already and no hit of yours since
;(KillCalc.ahk ConvertUp - the review, 2026-10-26: one went out every round while one was in hand): no
NeedsConvert()
	{
	global BossChoosen, hitschool, BoostSaid, ConvertOn
	if (BossChoosen != 1 || !IsFunc("ConvertNeedMem"))
		return false
	if (IsFunc("ConvertUp") && ConvertUp.Call())
		{
		if (IsObject(BoostSaid) && !BoostSaid.Has("convert|up" ConvertOn.round))
			BoostSaid["convert|up" ConvertOn.round] := 1, DebugLog("  convert: your prism went on the boss in round " ConvertOn.round " and no hit of yours has gone out since - not a second one") ;  V1toV2: Invalid Index errors?, try 'BoostSaid.Push(<val>)'
		return false
		}
	ncMem := ConvertNeedMem.Call()
	ncSay := "convert|" (ncMem = "" ? "unknown" : ncMem)
	if (IsObject(BoostSaid) && !BoostSaid.Has(ncSay))
		BoostSaid[ncSay] := 1, DebugLog("  convert: the boss " (ncMem = 1 ? "is " hitschool " (the game's memory) - it resists your hits: your prism first"
			: ncMem = 0 ? "isn't " hitschool " (the game's memory) - no prism" : "- its school not read from the game's memory (" NavBattleWhy "): no prism")) ;  V1toV2: Invalid Index errors?, try 'BoostSaid.Push(<val>)'
	return (ncMem = 1)
	}
	
LockMove(&direction)
	{
	Send("{" direction " down}")
	s(50)
	Send("{Shift down}")
	s(50)
	Send("{" direction " up}")
	s(50)
	Send("{Shift up}")
	}
	
Log()
	{
	Send("{Esc}")
	s(1000)
	UpdateGameRect()
	ErrorLevel := !ImageSearch(&logX, &logY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\log.png"))
	if (Errorlevel == 0)
		{
		ClickAt(logX, logY)
		} else if (Errorlevel == 2)
			{
			ErrorBox(&"Log", &dir, &title)
			}
	s(5000)
	}
	
Join()
	{
	UpdateGameRect()
	ErrorLevel := !ImageSearch(&joinX, &joinY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\join.png"))
	if (Errorlevel == 0)
		{
		ClickAt(joinX, joinY)
		} else if (Errorlevel == 2)
			{
			ErrorBox(&"Join", &dir, &title)
			}
	s(5000)
	}

UsePotion()
	{
	UpdateGameRect()
	ErrorLevel := !ImageSearch(&potionX, &potionY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\potion.png"))
	ClickAt(potionX, potionY)
	}

CheckAfk()
	{
	if (afk == 1)
		{
		;Waits for you to press w/a/s/d, checking for a disconnect every second meanwhile - held for mana: every
		;30 s the mana globe looked at, and on by itself once there's enough for the cheapest hit (at least 3), or
		;once the 10 minutes after a failed run to buy potions are up (checkmana tries another)
		;(3 tries at most a hold - each a run and its alert; on again by itself once there's mana, or by your keys)
		waitRun := (AfkWhy = "mana" && Stat("fleeon") && A_TickCount < PotionFailUntil && AfkRetries < 3)
		Loop
			{
			ihOutputVar := InputHook("T1","{w} {a} {s} {d}","w, a, s, d"), ihOutputVar.Start(), ErrorLevel := ihOutputVar.Wait(), OutputVar := ihOutputVar.Input
			if (Errorlevel != "Timeout")
				{
				AfkRetries := 0
				break
				}
			ReconnectCheck()
			if (AfkWhy = "mana" && VisionOn && Mod(A_Index, 30) = 0 && GameActive())
				{
				afkMana := PotionGlobes().mana
				if (afkMana != "" && afkMana + 0 >= Max(3, FleeCheapestHit() = "" ? 0 : FleeCheapestHit()))
					{
					DebugLog("no mana: the mana globe reads " afkMana " now - carrying on")
					AfkRetries := 0
					break
					}
				;(FleeAfter, right after this, tries: a potion, else a run - whether the mana picture matches or not)
				if (waitRun && A_TickCount >= PotionFailUntil)
					{
					AfkRetries += 1, FleeWhy := "mana"
					DebugLog("no mana: 10 minutes since the run to buy potions failed - trying again (" AfkRetries " of 3)")
					break
					}
				}
			}
		afk := 0, AfkWhy := ""
		}
	}
return

Afk(why := "")
	{
	if (afk == 0)
		{
		LockMove(&"a")
		afk := 1, AfkWhy := why
		}
	}

checkmana()
	{
	;(when the picture was last found with mana in the globe - logged at most every 5 minutes)
	static wrongSaid := 0
	if (afk == 0)
		{
		ErrorLevel := !ImageSearch(&manaX, &manaY, GameLeft, ScreenY, GameLeft + GameW / 4, GameBottom, PicOpt("resources\manaempty.png"))
		if (Errorlevel == 0)
			{
			;(the picture is small and, made for other UI sizes, mostly see-through: it can match the energy globe
			;beside the mana globe, clear when it's low. The mana globe's number, read by the helper, has the last
			;word: enough for the cheapest hit - at least 3 - is mana)
			manaNow := VisionOn ? PotionGlobes().mana : ""
			manaNeed := Max(3, FleeCheapestHit() = "" ? 0 : FleeCheapestHit())
			;(the helper running but the number not read - the wrong picture set, a window over it: not on the
			;picture alone)
			if (VisionOn && manaNow = "")
				{
				if (!wrongSaid || A_TickCount - wrongSaid > 300000)
					DebugLog("no mana? The mana-empty picture matched, but the mana globe's number can't be read - not acting on the picture alone")
				wrongSaid := A_TickCount
				return
				}
			if (manaNow != "" && manaNow + 0 >= manaNeed)
				{
				if (!wrongSaid || A_TickCount - wrongSaid > 300000)
					DebugLog("no mana? The mana-empty picture matched at " manaX - GameLeft "," manaY - GameTop " (the energy globe beside it?), but the mana globe reads " manaNow " - carrying on")
				wrongSaid := A_TickCount
				return
				}
			;(a potion first - or a run to buy some - so it can carry on; only then keep the character from timing out)
			if (Stat("fleeon") && FleeRefillMana("no mana"))
				return
			Respond("Error, It Seems I Have No Mana. Preventing Timeout.")
			AlertSend("mana", "out of mana", "No mana and no potion to be had - the bot is holding (kept from timing out) and carries on by itself once there's mana again.")
			afk("mana")
			}
		}
	}
	
mobloop:
mobloop()
return
	
LoreLoop:
LoreLoop()
return 
return

NewStaticGui(&Text, &x, &y, &w, &h) 
	{
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	myGui := Gui()
	myGui.OnEvent("Close", GuiClose)
	myGui.Add("Text", box, Text)
	myGui.Title := "AutoFarmer"
	myGui.Show("AutoSize Center")
	}

NewTempGui(&timeout, &Text, &x, &y, &w, &h) 
	{
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	myGui.Add("Text", box, Text)
	myGui.Title := "AutoFarmer"
	myGui.Show("AutoSize Center")
	Sleep(timeout)
	Try myGui.Destroy()
	}
	
ModeBox(&mode, &name, &x, &y, &w, &h)
	{
	
	if ((inbattle == 1) && (mode != 1))
		{
		NewTempGui(1500, &"Please Don't turn modes on while in combat", 10, 10, 210, 30)
		}	
	
	if (mode == 0) && (inbattle == 0)
		{
		gui := "Turning On " . name . " Mode."
		NewTempGui(1000, &gui, &x, &y, &w, &h)
		mode := 1
		} else if (mode == 1)
			{
			gui := "Turning Off " . name . " Mode."
			NewTempGui(1000, &gui, &x, &y, &w, &h)
			mode := 0
			}
	}
	
;(the modes and picks below - Alt+D, Alt+S, Alt+1... - only while the bot is on: off, their keys go to whatever
;program has them; their keys: Hotkeys.ahk)
HkDev:
HkDev()
return

HkLore:
HkLore()
return

HkDual:
HkDual()
return
		
HkCommand:
HkCommand()
return

HkStats:
HkStats()
return

HkResponse:
HkResponse()
return
	
HkBoss:
HkBoss()
return

HkLoop:
HkLoop()
return

HkBoost:
HkBoost()
return

HkPlayer:
HkPlayer()
return

GuiClose:
GuiClose()
return

HkDash:
HkDash()
return

CommandOff()
	{
	global
	if ((devmode == 1) && (commandmode == 1)) 
		{
		ErrorLevel := !ImageSearch(&offX, &offY, GameLeft, GameBottom - Px(25), GameLeft + GameW / 4 + Px(20), GameBottom, PicOpt("resources\off.png", 120))
		if (ErrorLevel == 0) 
			{			
			Respond("Shutting Down.")
			ExitApp()
			} else if (Errorlevel == 2)
				{
				ErrorBox(&"CommandOff", &dir, &title)
				}
		}
	}
	
CommandReload()
	{
	global
	if ((devmode == 1) && (commandmode == 1)) 
		{
		;Requires devmode to be on to reloaded script manually
		ErrorLevel := !ImageSearch(&relX, &relY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\rel.png", 120))
		if (ErrorLevel == 0) 
			{
			Respond("Reloading Script.")
			BotRestart()
			} else if (Errorlevel == 2)
				{
				ErrorBox(&"CommandReload", &dir, &title)
				}
		}
	}

CommandHit()
	{
	global
	if (commandmode == 1)
		{
		ErrorLevel := !ImageSearch(&X, &Y, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\PlayerHit.png", 120))
		if (Errorlevel == 0)
			{
			Respond("Okay, Ill OverRide The Automatic Battle Sequence.")
			if ((hit == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1))
				{
				if (hit4 == 1) && (BossChoosen = 1)
					{
					UseHit(&"hit4", &hit4, &hitschool)
					} else if (hit3 == 1)
						{
						UseHit(&"hit3", &hit3, &hitschool)
						} else if (hit2 == 1)
							{
							UseHit(&"hit2", &hit2, &hitschool)
							} else if (hit1 == 1)
								{
								UseHit(&"hit1", &hit1, &hitschool)
								} else 
									{
									Respond("It Seems There Are No Hits In Hand, I'll Pass Instead.")
									ClickPass()
									}
				}
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&"CommandHit", &dir, &title)
					}
		}
	}
	
CommandPass()
	{	
	global
	if (commandmode == 1)
		{
		ErrorLevel := !ImageSearch(&PlayerPassX, &PlayerPassY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\PlayerPass.png", 120))
		if (ErrorLevel == 0)
			{
			Respond("Alright, Ill Pass Instead.")
			ClickAt(passX, passY)
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&"CommandPass", &dir, &title)
					return false
					} 
		}
	}
	
CommandWalk()
	{
	global
	if (commandmode == 1)
		{
		ErrorLevel := !ImageSearch(&walkX, &walkY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\walk.png", 120))
		if (ErrorLevel == 0) 
			{
			Respond("I'm Not A Dog, But Ill Do It Anyways")
			Send("{w Down}")
			Sleep(2000)
			Send("{w Up}")
			Sleep(Ten)
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&"CommandWalk", &dir, &title)
					return false
					}
		}
	}
	
CommandEnter()
	{
	global
	if (commandmode == 1)
		{
		ErrorLevel := !ImageSearch(&enterX, &enterY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\enter.png", 120))
		if (ErrorLevel == 0) 
			{
			Respond("Entering Sigil. Make Sure You Have The Right Deck On.")
			Send("{x}")
			Sleep(Tick)
			Send("{x}")
			Sleep(Tick)
			Send("{x}")
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&"CommandEnter", &dir, &title)
					return false
					}
		} 
	}
	
CommandAfk()
	{
	global
	if (commandmode == 1)
		{
		ErrorLevel := !ImageSearch(&afkX, &afkY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\afk.png", 120))
		if (ErrorLevel == 0)
			{
			Respond("Okay, I'll Prevent Time Out Until Further Notice.")
			afk()
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox(&"CommandAfk", &dir, &title)
					return false
					}
		}
	}
	
CommandPort() 
	{
	global
	if (commandmode == 1)
		{
		ErrorLevel := !ImageSearch(&wordportX, &wordportY, GameLeft, GameTop + GameH * 0.65, GameLeft + GameW / 7.4, GameTop + GameH * 0.775, PicOpt("resources\wordport.png", 120))
		if (ErrorLevel == 0)
			{
		
			Send("{/}")
			Sleep(Tick)
			Send("{BS}")
			Sleep(Tick)
			Send("{Enter}")
			Sleep(Half)
			
			ErrorLevel := !ImageSearch(&checkX, &checkY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\check.png"))
			if (Errorlevel == 0) 
				{
				Sleep(Half)
				ErrorLevel := !ImageSearch(&nameX, &nameY, GameLeft, checkY - Px(20), checkX, checkY + Px(20), PicOpt("resources\name.png"))
				if (ErrorLevel == 0) 
					{		
					ClickAt(nameX + Px(30), nameY)
					
					s(2000)		
					ErrorLevel := !ImageSearch(&portX, &portY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\port.png"))
					if (Errorlevel == 0) 
						{
						ClickAt(portX, portY)
						Sleep(Half)
						
						ErrorLevel := !ImageSearch(&yesX, &yesY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\yes.png"))
						if (Errorlevel == 0) 
							{
							ClickAt(yesX, yesY)
							Sleep(Half)
							
							Respond("Initiating Teleportation Sequence.")
								
							ErrorLevel := !ImageSearch(&okX, &okY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\ok.png"))
							if (Errorlevel == 0) 
								{
								ClickAt(okX, okY)
								
								Respond("Error Teleporting, Check If Ports Are On, Or If You're In A Dungeon.")
									
								}
							} else if ((Errorlevel == 1) && (devmode == 1))
								{
								Respond("Error Teleporting, Invalid Gui.")
								}
						} else if ((Errorlevel == 1) && (devmode == 1))
							{
							Respond("Error Teleporting, Invalid Gui.")
							}
					} else if ((Errorlevel == 1) && (devmode == 1))
						{
						Respond("Error Teleporting, Invalid Gui.")
						}
				} else if ((Errorlevel == 1) && (devmode == 1))
					{
					Respond("Error Teleporting, Invalid Gui.")
					}
			return true
			Sleep(Ten)
			} else if (Errorlevel == 1)
				{
				return false
				} else if (Errorlevel == 2)
					{
					ErrorBox(&"CommandPort", &dir, &title)
					return false
					}
		}
	}

#HotIf BotOn
!0::HK1_()

#`::HK2_()
return

#HotIf

HkQuit:
HkQuit()
ExitApp()
return

HkRestart2:
HkRestart2()
return


;Which school's badge (a name plate's school icon) matches best in the rectangle: each school with a
;badge picture at this UI size is looked for, and where it's found, how little colour tolerance it
;still matches with there decides - a badge made at another size roughly matches the other schools'
;too (they share the gold ring), the right one matches closest. Returns the school ("" if none) and
;its position in bx, by
BestBadge(x1, y1, x2, y2, &bx, &by, nearX := 0, nearY := 0)
	{
	;(the vision helper, if it's running; with several plates, the one nearest nearX, nearY)
	sch := VisionBadge(x1, y1, x2, y2, bx, by, nearX, nearY)
	if (sch != -1)
		return sch
	best := "", bestTol := 99, bx := 0, by := 0
	for each, sch in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		{
		rel := sch "\" sch ".png", p := PicPath(rel)
		;(the main set's 2018 badge, which doesn't match at another size)
		if (UiScale != 1 && p = A_WorkingDir "\" rel)
			continue
		ErrorLevel := !ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" GenTol " *TransFF00FF " p)
		if (ErrorLevel)
			continue
		for each2, tol in [0, 3, 6, 10, 14, GenTol]
			{
			if (tol >= bestTol)
				break
			ErrorLevel := !ImageSearch(&gx, &gy, fx - 3, fy - 3, fx + Px(40), fy + Px(40), "*" tol " *TransFF00FF " p)
			if (ErrorLevel = 0)
				{
				best := sch, bestTol := tol, bx := gx, by := gy
				break
				}
			}
		}
	return best
	}

;The bot's number for a hitter school (0 = none)
BadgeNumber(sch)
	{
	for i, name in ["storm", "fire", "myth", "balance", "ice", "life", "death"]
		if (name = sch)
			return i
	return 0
	}

;A school's blades and traps: "elemental" (storm, fire, ice), "spirit" (myth, life, death), "balance"; "" not a school
SchoolGroup(sch)
	{
	n := BadgeNumber(sch)
	return (n = 1 || n = 2 || n = 5) ? "elemental" : (n = 3 || n = 6 || n = 7) ? "spirit" : n = 4 ? "balance" : ""
	}

;Did the card just clicked go out? The Pass button has to stay gone for 1 s (it can blink out for a moment while
;the hand updates) - looked at every 100 ms; still there 0.7 s after the click = the card didn't cast
CastWentOut()
	{
	global
	local passX, passY, stillThere, t0, goneFrom
	stillThere := false, goneFrom := 0, t0 := A_TickCount
	while (A_TickCount - t0 < 2500)
		{
		Sleep(100)
		UpdateGameRect()
		if (PassButtonAt(&passX, &passY) = 0)
			{
			goneFrom := 0
			if (A_TickCount - t0 >= 700)
				{
				stillThere := true
				break
				}
			}
		else if (!goneFrom)
			goneFrom := A_TickCount
		else if (A_TickCount - goneFrom >= 1000)
			break
		}
	return !stillThere
	}

;A learned hit in no slot cast (CastBestHit, when no hit1-4 went): the strongest in hand you can pay for, by a fresh
;look at the hand (LearnHitCards) - an enchant in hand on it first (as UseHit does for hit1-4: free, more damage), its
;card clicked, then a target if it hits one enemy. Not the kill check's (it knows the slots' hits only).
;learnedhits:0 in PlayerStats.txt: never. True if it went out
CastLearnedHit()
	{
	global
	local ans, list, c, enchanted
	if (!Stat("learnedhits") || !VisionOn || hitschool = "" || PipSaveFor != "" || !IsFunc("LearnHitCards"))
		return false
	if (!LearnHitReady())
		return false
	;(the strongest first; one that doesn't go - an off-school card's power pips count 1, a guessed cost - is left for
	;this battle till there are more pips, and the next is tried: two a round at most, each looked for afresh)
	Loop 2
		{
		ans := LearnHandRead()
		list := LearnHitCards(ans)
		if (!list.Length)
			return false
		c := list[1]
		;(an enchant in hand: on the hit first - then the hand closes up round the gap it left, the hit half a card's
		;width towards it)
		enchanted := false
		;(never on an item card - a pet's or gear's: it can't be enchanted)
		if (A_Index = 1 && !LearnHasFlag(c.c, "item"))
			{
			FindEnchant()
			if (enchant >= 1 && enchantX != "" && Abs(enchantX - c.x) > HalfPitch)
				{
				DebugLog("  enchant (level " enchant ") on learned hit " c.id " first, at " enchantX - GameLeft "," enchantY - GameTop)
				ClickAt(enchantX, enchantY, 150)
				ClickAt(Round(c.x), Round(c.y), 150)
				CenterMouse()
				Sleep(500)
				c.x += (c.x < enchantX ? HalfPitch : -HalfPitch), enchanted := true
				}
			}
		DebugLog("  learned hit " c.id " (" LearnDescribe(c.c) ")" (enchanted ? ", enchanted," : "") " - in no slot: cast at " Round(c.x) - GameLeft "," Round(c.y) - GameTop)
		ClickAt(Round(c.x), Round(c.y))
		if (c.c.type = "damage" && c.c.target != 0)
			HitTarget("learned hit", hitschool, 1, LearnedHitDamage(c.c, enchanted))
		if (CastWentOut())
			{
			;(the blades and traps that fit its heads used up - KillCalc.ahk)
			ConsumeBoosts(LearnHitHeads(c.c))
			DashCast("learned/" c.id)
			return true
			}
		LearnHitFails[c.id] := PipsNow ;  V1toV2: Invalid Index errors?, try 'LearnHitFails.Push(<val>)'
		DebugLog("  learned hit " c.id " didn't cast (not enough pips?) - not tried again this battle with " PipsNow " pips or fewer")
		CenterMouse()
		VisionForget()
		}
	return false
	}

;The enchant cards it knows, the most damage added first (PlayerStats.txt enchantN - change one and the order
;follows): [level (enchantN), picture folder, name]. 1 is the old life\enchant placeholder; Strong, Giant and
;Monstrous (5-7) are learned from the card the first time one's in hand (CardLearn.ahk, kind "enchant")
EnchantList()
	{
	list := []
	for i, e in [[4, "resources", "epic"], [3, "resources", "colossal"], [2, "resources", "gargantuan"], [7, "resources", "monstrous"], [6, "resources", "giant"], [5, "resources", "strong"], [1, "life", "enchant"]]
		{
		at := 1
		while (at <= list.Length && Stat("enchant" list[at][1]) >= Stat("enchant" e[1]))
			at++
		list.InsertAt(at, e)
		}
	return list
	}

;Looks for an enchant card in hand - the best (EnchantList): enchant := its level, enchantX/Y where it is; 0 none.
;Epic only once a hitter's known (as before). By the vision helper; what it can't tell (-1: not running, no picture
;it can use) by ImageSearch. Run again after one is used, since the hand shifts
FindEnchant()
	{
	global
	local each, ench, r, unsure
	enchant := 0, unsure := []
	for each, ench in EnchantList()
		{
		if (ench[1] = 4 && hitter = 0)
			continue
		r := VisionOn ? VisionFind(ench[2], ench[3], enchantX, enchantY) : -1
		if (r = 1)
			{
			enchant := ench[1]
			return
			}
		if (r = -1)
			unsure.Push(ench)
		}
	for each, ench in unsure
		{
		ErrorLevel := !ImageSearch(&enchantX, &enchantY, ScreenX - HandHalf, ScreenY - Px(75), ScreenX + HandHalf, ScreenY + Px(75), PicOpt(ench[2] "\" ench[3] ".png", CardTol))
		if (ErrorLevel = 0)
			{
			enchant := ench[1]
			return
			}
		}
	}

;Checks a hit really got cast: once a spell is chosen the Pass button goes away. If it's still
;there the card couldn't be cast (not enough pips), so the round tries the next option instead
;consume: a hit uses up the blades and traps on it (ConsumeBoosts) - a heal doesn't (false)
;Another of your wizards' name plates (player.png, player2.png, player3.png) in the battle besides the one found: a party
;battle - which plate is this PC's isn't sure (phase 1b), so its school isn't saved for the character (StatsNoteSchool)
PlayerPlates2()
	{
	;(only when the battle has more than one wizard on your side - the game's log, EnemySpells.ahk)
	n := 0
	if (IsObject(BlNames))
		Loop 4
			n += BlNames.Has(A_Index + 3) ? 1 : 0
	if (n < 2)
		return false
	n := 0
	for each, pic in ["player.png", "player2.png", "player3.png"]
		{
		if (!FileExist(A_ScriptDir "\resources\" pic))
			continue
		ErrorLevel := !ImageSearch(&px, &py, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, PicOpt("resources\" pic))
		if (ErrorLevel = 0)
			n += 1
		}
	if (n > 1)
		DebugLog("  " n " of your wizards' name plates in this battle - its school not saved for this character")
	return n > 1
	}

CastResult(title, &hit, dir, enchanted, consume := true)
	{
	global
	if (CastWentOut())
		{
		EnchantedHits.Delete(title)
		;(the blades and traps that fit its heads used up - KillCalc.ahk HitHeads, ConsumeBoosts)
		if (consume)
			ConsumeBoosts(HitHeads(title))
		DashCast(title)
		return true
		}
	DebugLog("  " title " didn't cast (not enough pips?)")
	hit := 0
	;An unaffordable card is discarded, unless it carries an enchant (now or from an earlier round)
	if (!enchanted && !EnchantedHits[title] && Stat("discardunaffordable") == 1)
		DiscardCard(title, dir)
	CenterMouse()
	return false
	}

;Right-clicks (discards) cards that can't help this battle. Returns how many were discarded
DiscardSpare()
	{
	global
	local did := 0, dsK, dsF, dsKeys, dsI, dsSharpUsed, dsNeed, dsC
	;(a party battle's blader or healer casts its blades again after each of the hitter's hits: none is spare - not with
	;Alt+2's pick, whose hits nothing follows; but one that boosts neither the hitter's planned hit nor its own school
	;goes - KillCalc.ahk BoostMisfitDiscard)
	if (PartySupport() && HammerSlot)
		return BoostMisfitDiscard()
	;A blade whose sharpened and plain casts have both been used this battle won't stack again - each school's (SbFound),
	;the group's (GbFound), Balanceblade, Bladestorm (a treasure or item card's copy still to go - the game's hand - stays)
	dsKeys := []
	for dsK in SbFound
		if (BoostKind(dsK) = "blade")
			dsKeys.Push(dsK)
	for dsK in GbFound
		if (BoostKind(dsK) = "blade")
			dsKeys.Push(dsK)
	for dsI, dsK in ["blade3", "blade4"]
		if (%dsK% == 1)
			dsKeys.Push(dsK)
	for dsI, dsK in dsKeys
		{
		dsF := KeyFlags(dsK)
		if (IsObject(dsF) && UsedFlag(dsF[1]) == 1 && UsedFlag(dsF[2]) == 1 && !BoostCanGo(dsK))
			did += InStr(dsK, "/") ? DiscardCard("blade", SubStr(dsK, 1, InStr(dsK, "/") - 1)) : DiscardCard(dsK, "resources")
		}
	;Sharpen is spare once a sharpened blade has been used and no blade in hand still needs sharpening (an item card's never
	;does: it can't be enchanted)
	dsSharpUsed := 0, dsNeed := 0
	for dsI, dsK in ["blade3", "blade4", "elementalblade", "spiritblade", "storm/blade", "fire/blade", "myth/blade", "ice/blade", "life/blade", "death/blade"]
		if (UsedFlag(KeyFlags(dsK)[1]) == 1)
			dsSharpUsed := 1
	for dsI, dsK in dsKeys
		{
		dsF := KeyFlags(dsK)
		if (IsObject(BoostHand) && BoostHand.Has(dsK))
			{
			for dsC, dsF in BoostHand[dsK]
				if (!dsF.item && (dsF.src = "" ? UsedFlag(KeyFlags(dsK)[1]) != 1 : !BoostSrcUsed.Has(dsK "@" dsF.src)))
					dsNeed := 1
			}
		else if (UsedFlag(dsF[1]) != 1)
			dsNeed := 1
		}
	if (sharpen == 1) && dsSharpUsed && !dsNeed
		did += DiscardCard("sharpen", "resources")
	return did
	}

;Right-clicks one card in hand to discard it. Returns 1 if it was found
DiscardCard(title, dir)
	{
	global
	local card := 0, cardX := 0, cardY := 0
	Find(title, &card, &cardX, &cardY, &dir)
	if (card != 1)
		return 0
	;(never a treasure card - discarding one uses it up: one drawn for an enchant (Draw.ahk) looks like the deck's)
	if (IsFunc("DiscardIsTc") && DiscardIsTc(cardX + Px(5)))
		{
		DebugLog("  " title " not discarded: it's a treasure card")
		return 0
		}
	MoveToCard(cardX + Px(5), cardY + Px(5))
	s(Stats.Has("clickwait") ? Stats["clickwait"] : 40)
	Click(&"right")
	;(the hand has changed: a fresh look next time, not the vision helper's picture of it from before)
	VisionForget()
	s(Stat("discardafter"))
	DebugLog("  Discarded " title " (right-click at " cardX - GameLeft "," cardY - GameTop ")")
	return 1
	}

;A boost card was just put on the card at fx,fy: the hand re-centres. Looks for the card where it slides
;to every 100 ms (from 250 ms on) and goes once it's in the same spot twice running - the slide is over -
;instead of a fixed 1.5 s; not seen by then: RefindAfterBoost's guess
BoostSettle(n, &fx, &fy, boostX)
	{
	global
	local expX, nx, ny, lastX := "", lastY := "", t0 := A_TickCount
	expX := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	Sleep(250)
	while (A_TickCount - t0 < 1500)
		{
		ErrorLevel := !ImageSearch(&nx, &ny, expX - Px(30), fy - Px(25), expX + Px(50), fy + Px(40), PicOptFile(n, CardTol))
		if (ErrorLevel = 0)
			{
			if (nx = lastX && ny = lastY)
				{
				DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " nx - GameLeft "," ny - GameTop " (settled in " A_TickCount - t0 " ms)")
				fx := nx, fy := ny
				return
				}
			lastX := nx, lastY := ny
			}
		Sleep(100)
		}
	RefindAfterBoost(n, &fx, &fy, boostX)
	}

;A boost card (enchant, Sharpen or Potent) was just put on the card at fx,fy and left the hand.
;The hand re-centres: cards left of the boost card slide right by half a card, cards right of it
;slide left. Looks for the card where it should be now; if it can't be seen there, uses that spot
RefindAfterBoost(n, &fx, &fy, boostX)
	{
	global
	local expX, nx, ny
	expX := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	ErrorLevel := !ImageSearch(&nx, &ny, expX - Px(30), fy - Px(25), expX + Px(50), fy + Px(40), PicOptFile(n, CardTol))
	if (ErrorLevel = 0)
		{
		DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " nx - GameLeft "," ny - GameTop)
		fx := nx, fy := ny
		}
	else
		{
		DebugLog("    card not seen after the hand moved, using where it should be: " expX - GameLeft "," fy - GameTop)
		fx := expX
		}
	}

;A Sharpen or Potent was just put on the card at fx, fy that no picture finds - one cast by the game's hand (UseBlade,
;UseTrap: BoostMemOnly) - and the hand re-centres: where the game's hand has boost key's card once it's settled (a fresh
;look at the hand's boxes laid on the game's cards - KillCalc.ahk BoostMemBox): the copy with the enchantment on it, else a
;copy of it that's there (the enchant didn't take); neither (they don't line up): where it should be, as RefindAfterBoost
BoostSettleMem(key, &fx, &fy, boostX)
	{
	global
	local bsmExp, bsmAt, bsmT0 := A_TickCount
	bsmExp := fx + (fx < boostX ? HalfPitch : -HalfPitch)
	Sleep(250)
	VisionForget()
	bsmAt := BoostMemBox(key, 0, "", "", 1, 1500)
	if (bsmAt.x = "")
		{
		VisionForget()
		bsmAt := BoostMemBox(key, 0, "", "", 0, 1500)
		}
	if (bsmAt.x != "")
		{
		DebugLog("    card moved from " fx - GameLeft "," fy - GameTop " to " bsmAt.x - GameLeft "," bsmAt.y - GameTop " (the game's hand: card " bsmAt.n " of " bsmAt.of ", " A_TickCount - bsmT0 " ms)")
		fx := bsmAt.x, fy := bsmAt.y
		return
		}
	DebugLog("    card not found in the game's hand after it moved (" bsmAt.why "), using where it should be: " bsmExp - GameLeft "," fy - GameTop)
	fx := bsmExp
	}

;Reads the wizard's stats off the Spellbook (StatsRead.ahk) into PlayerStats.txt and reloads them,
;out of battle: by itself when the wizard logged in now (whose school it knows from a battle) has no
;<school>.damage yet, or the ones there are from another character of that school - at most every 30
;minutes per character - or when asked (StatsWanted). Only with the game in front and nobody having
;touched the mouse or keyboard for 5 s, since it clicks through the book
StatsAuto()
	{
	static triedAt := {}
	;(cheap checks first: this runs on every pass out of battle)
	if (!StatsWanted && SrBattleSchool = "")
		return
	if (UserIdle() < 5000 || afk || loopmode || loremode || !WinActive("ahk_class " GameClass " ahk_exe " GameExe))
		return
	;The school of the wizard logged in now: the last battle's if that was this character (it may have
	;switched since), else the one noted for it before
	charNow := StatsCharID()
	statsFor := (charNow != "" && charNow = SrBattleChar) ? SrBattleSchool : StatsSchoolOf(charNow)
	if (statsFor = "" && !StatsWanted)
		return
	need := StatsWanted || !Stats.Has(statsFor ".damage") || (charNow != "" && Stats[statsFor ".charid"] != charNow)
	tryKey := charNow "|" statsFor
	if (!need || (!StatsWanted && triedAt.Has(tryKey) && A_TickCount - triedAt[tryKey] < 1800000))
		return
	if (KeysDown || HeldW)
		ReleaseKeys()
	triedAt[tryKey] := A_TickCount, StatsWanted := 0 ;  V1toV2: Invalid Index errors?, try 'triedAt.Push(<val>)'
	;(it stops if you touch the mouse or keyboard while it reads)
	SrHandsOff := 1
	DebugLog("Stats: reading the " (statsFor = "" ? "wizard's" : statsFor " wizard's") " stats off the Spellbook (character " (charNow = "" ? "?" : charNow) ", UI scale " Round(UiScale, 3) ")")
	err := StatsRead(statsFor, statsGot)
	if (err != "")
		{
		DebugLog("Stats: " err)
		TrayTip("Wizard101 bot", "Couldn't read your stats: " err, 2)
		return
		}
	msg := StatsWrite(statsGot, statsFor, charNow)
	LoadStats(true)
	DebugLog("Stats: " StrReplace(msg, "`n", " "))
	TrayTip("Wizard101 bot", msg, 1)
	}

;On exit: stop the vision helper too (it would stop by itself within 5 s anyway)
VisionOnExit(reason, code)
	{
	VisionStop()
	}

;StatsReader.ahk was started while this runs: it asks this script to read them (no two scripts
;clicking at once)
StatsAsked(wParam, lParam, msg, hwnd)
	{
	StatsWanted := 1
	TrayTip("Wizard101 bot", "Reading your stats at the next quiet moment out of battle (hands off the mouse and keys for 5 s).", 1)
	return 1
	}

;Saves the game as a picture (BMP) for cutting new pictures from, in the Windows temp folder
;("Wizard101 bot rounds"), keeping the newest 25. Returns the file name, or "" if it couldn't
SaveRoundPicture()
	{
	dir := A_Temp "\Wizard101 bot rounds"
	DirCreate(dir)
	files := ""
	Loop Files, dir "\round_*.bmp"
		files .= A_LoopFileName "`n"
	files := Sort(files)
	list := StrSplit(Trim(files, "`n"), "`n")
	while (list.Length >= 25)
		Try FileDelete(dir "\" list.RemoveAt(1))
	if (!ArrowCapture(GameLeft, GameTop, GameW, GameH, pix))
		return ""
	stamp := FormatTime(, "yyyyMMdd_HHmmss")
	path := dir "\round_" stamp ".bmp"
	bmp := FileOpen(path, "w")
	if (!IsObject(bmp))
		return ""
	bmp.WriteUShort(0x4D42), bmp.WriteUInt(54 + GameW * GameH * 4), bmp.WriteUInt(0), bmp.WriteUInt(54)
	bmp.WriteUInt(40), bmp.WriteInt(GameW), bmp.WriteInt(-GameH), bmp.WriteUShort(1), bmp.WriteUShort(32)
	bmp.WriteUInt(0), bmp.WriteUInt(GameW * GameH * 4), bmp.WriteInt(2835), bmp.WriteInt(2835), bmp.WriteUInt(0), bmp.WriteUInt(0)
	bmp.RawWrite(pix, GameW * GameH * 4)
	bmp.Close()
	return path
	}

;Appends a timestamped line to debug.log next to this script (and to its copy on OneDrive: LogMirrorDir)
DebugLog(msg)
	{
	now := FormatTime(, "HH:mm:ss")
	FileAppend(now " " msg "`r`n", A_ScriptDir "\debug.log")
	lmTo := LogMirrorDir(&lmFresh)
	if (lmTo != "" && !lmFresh)
		FileAppend(now " " msg "`r`n", lmTo "\debug.log")
	;(and onto the dashboard's log)
	if (DashHwnd)
		DashLog(now " " msg)
	}

;The log copied to OneDrive as well (logmirror:1 - Settings, ALERTS), for help from another PC (OneDrive syncs it
;there): <OneDrive>\Wiz-Maxxing logs\<this PC's name>\ - debug.log line by line (when it's switched on, the run so far
;and debug.previous.log are copied over first), and pictures of the game (LogMirrorSnap). The folder, or "" when it's
;off or this PC has no OneDrive folder; fresh: 1 when it was switched on just now (the log copied, this line in it)
LogMirrorDir(&fresh := 0)
	{
	static lmDir := "", lmOn := 0
	fresh := 0
	if (!(Stats.Has("logmirror") && Stats["logmirror"]))
		{
		lmOn := 0
		return ""
		}
	if (!lmOn)
		{
		lmOn := 1, lmDir := ""
		;(your own OneDrive first - a work account's is %OneDrive% too)
		od := EnvGet("OneDriveConsumer")
		if (od = "" || !InStr(FileExist(od), "D"))
			od := EnvGet("OneDrive")
		now := FormatTime(, "HH:mm:ss")
		if (od != "" && InStr(FileExist(od), "D"))
			{
			lmDir := od "\Wiz-Maxxing logs\" A_ComputerName
			DirCreate(lmDir)
			FileAppend(now " Log copy: on - " lmDir "`r`n", A_ScriptDir "\debug.log")
			Try {
				FileCopy(A_ScriptDir "\debug.previous.log", lmDir "\debug.previous.log", 1)
				ErrorLevel := 0
			} Catch as Err {
				ErrorLevel := Err.Extra
			}
			Try {
				FileCopy(A_ScriptDir "\debug.log", lmDir "\debug.log", 1)
				ErrorLevel := 0
			} Catch as Err {
				ErrorLevel := Err.Extra
			}
			fresh := 1
			}
		else
			FileAppend(now " Log copy: no OneDrive folder on this PC - not copied`r`n", A_ScriptDir "\debug.log")
		}
	return lmDir
	}

;A picture of the game into the log's OneDrive copy (snap_<when>.jpg, the newest 15 kept; the vision helper makes
;it): every: at most this often (ms) - out of battle and at a round's start every 2 minutes, an alert's at once (kind:
;the alert's). Only the game itself: its window there and not minimised with nothing else's over it (the bot's own may
;be: LogMirrorGameShown), in its world - its spellbook or a battle's Pass button on screen, never the login screen -
;and no reconnect under way (nor for a reconnect alert)
LogMirrorSnap(every := 0, kind := "")
	{
	static lmLast := 0
	if (every && lmLast && A_TickCount - lmLast < every)
		return
	if (InStr(kind, "reconnect") || RcState != "")
		return
	lmTo := LogMirrorDir()
	if (lmTo = "" || !VisionOn || !LogMirrorGameShown())
		return
	ErrorLevel := !ImageSearch(&lmX, &lmY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
	if (ErrorLevel)
		{
		ErrorLevel := !ImageSearch(&lmX, &lmY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundstart.png"))
		if (ErrorLevel)
			return
		}
	lmLast := A_TickCount
	stamp := FormatTime(A_NowUTC, "yyyyMMdd_HHmmss")
	VisionGet("/snap?x1=" GameLeft "&y1=" GameTop "&x2=" GameLeft + GameW "&y2=" GameTop + GameH "&keep=15&out=" NavUri(lmTo "\snap_" stamp ".jpg"), 3000, true)
	}

;The game's window is up, not minimised, and on top over the game area: at its middle, corners and edges the window
;there is the game's (or one of the bot's own - its notices, the dashboard)
LogMirrorGameShown()
	{
	g := WinGetID("ahk_class " GameClass " ahk_exe " GameExe)
	if (!g || DllCall("IsIconic", "Ptr", g) || GameW <= 0 || GameH <= 0)
		return false
	me := DllCall("GetCurrentProcessId")
	for i, f in [[0.5, 0.5], [0.05, 0.05], [0.5, 0.05], [0.95, 0.05], [0.05, 0.5], [0.95, 0.5], [0.05, 0.95], [0.5, 0.95], [0.95, 0.95]]
		{
		x := GameLeft + Round(GameW * f[1]), y := GameTop + Round(GameH * f[2])
		w := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
		top := w ? DllCall("GetAncestor", "Ptr", w, "UInt", 2, "Ptr") : 0
		if (top = g)
			continue
		pid := WinGetPID("ahk_id " top)
		if (!top || pid != me)
			return false
		}
	return true
	}

#Include "%A_ScriptDir%\Ocr.ahk"
#Include "%A_ScriptDir%\KillCalc.ahk"
#Include "%A_ScriptDir%\Reconnect.ahk"
#Include "%A_ScriptDir%\PicScale.ahk"
#Include "%A_ScriptDir%\StatsRead.ahk"
#Include "%A_ScriptDir%\Vision.ahk"
#Include "%A_ScriptDir%\CardLearn.ahk"
#Include "%A_ScriptDir%\Potions.ahk"
#Include "%A_ScriptDir%\Flee.ahk"
#Include "%A_ScriptDir%\Draw.ahk"
#Include "%A_ScriptDir%\EnemySpells.ahk"
#Include "%A_ScriptDir%\Party.ahk"
#Include "%A_ScriptDir%\Settings.ahk"
#Include "%A_ScriptDir%\Alerts.ahk"
#Include "%A_ScriptDir%\Dashboard.ahk"
#Include "%A_ScriptDir%\BugReport.ahk"
#Include "%A_ScriptDir%\Dungeons.ahk"
#Include "%A_ScriptDir%\Collect.ahk"
#Include "%A_ScriptDir%\Network.ahk"
#Include "%A_ScriptDir%\Decks.ahk"
#Include "%A_ScriptDir%\QuickSell.ahk"
#Include "%A_ScriptDir%\Hotkeys.ahk"
#Include "%A_ScriptDir%\Spells.ahk"
#Include "%A_ScriptDir%\..\AutoQuester\Walker.ahk"
#Include "%A_ScriptDir%\..\AutoQuester\ArrowReader.ahk"
#Include "%A_ScriptDir%\..\Watch.ahk"

;###############  V1toV2 FUNCS  ###############
MenuBotToggle(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
BotToggle()
return
}
;##############################################
MenuWalk(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
WalkToggle()
return
}
;##############################################
MenuWatch(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
SplitPath(A_ScriptDir, , &watchRoot)
watchOn := !WatchIsOn()
if (WatchSet(watchRoot, watchOn))
	TrayTip("Wizard101 bot", watchOn ? "The bot now opens by itself when Wizard101 starts - in standby: " HkText("bot") " starts it." : "The bot won't open by itself with Wizard101 any more.", 1)
else
	TrayTip("Wizard101 bot", "Couldn't change `"Open with Wizard101`" (the Startup folder's shortcut).", 2)
WatchShow()
return
}
;##############################################
MenuReconnect(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
ReconnectToggle()
return
}
;##############################################
MenuHandsOff(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
HandsOffToggle()
return
}
;##############################################
MenuPlayForMe(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
PlayForMeToggle()
return
}
;##############################################
MenuGameFront(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
GameFrontToggle()
return
}
;##############################################
MenuLearnAll(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
LearnAllToggle()
return
}
;##############################################
MenuStats(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
StatsWanted := 1
TrayTip("Wizard101 bot", "Reading your stats at the next quiet moment out of battle (hands off the mouse and keys for 5 s).", 1)
return
}
;##############################################
MenuDash(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
DashToggle()
return
}
;##############################################
MenuSpells(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
SpShowTab()
return
}
;##############################################
MenuSettings(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
CfgShow()
return
}
;##############################################
MenuSpeedKeyFast(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
MenuSpeedKeyNormal()
}
;##############################################
MenuSpeedKeyNormal(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
speedKeyName := SpeedKey(A_ThisLabel := "MenuSpeedKeyFast")
TrayTip("Wizard101 bot", "Click into Cheat Engine's hotkey box now - " speedKeyName " is pressed in 3 seconds.", 1)
Sleep(3000)
Send("{" speedKeyName " down}")
Sleep(250)
Send("{" speedKeyName " up}")
;(if Cheat Engine already has it: the game's at that speed now)
SpeedNow := (A_ThisLabel = "MenuSpeedKeyFast") ? SpeedFactor() : 1, SpeedSentAt := A_TickCount
DebugLog("Speedhack: " speedKeyName " pressed (for Cheat Engine's hotkey box)")
return
}
;##############################################
MenuMap(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
DashMapToggle()
return
}
;##############################################
MenuUpdates(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
UpdCheckNow()
return
}
;##############################################
MenuBug(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
BugShow()
return
}
;##############################################
MenuNothing(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
return
}
;##############################################
UpdPeekNow() { ; V1toV2: Lbl->Func
global
;(only with a program that can run it: Wiz-Maxxing.exe - or, run as a script, Wiz-Maxxing.ahk by this AutoHotkey)
if (!A_IsCompiled || FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe"))
	BotRun(A_ScriptDir "\..\Wiz-Maxxing", "/latest", A_ScriptDir "\..")
else
	IniWrite("Wiz-Maxxing.exe is missing", A_ScriptDir "\..\updater.ini", "latest", "err")
;(updating by itself - Settings: autoupdate: every that many minutes, 5 at least. Wiz-Maxxing.exe not found: again in a
;minute - 2026-10-23 23:22 it wasn't for a moment while Windows Security restarted, and the look-up waited 10 minutes)
updEvery := Stat("autoupdate") > 0 ? Max(5, Stat("autoupdate")) : 120
if (A_IsCompiled && !FileExist(A_ScriptDir "\..\Wiz-Maxxing.exe"))
	updEvery := 1
SetTimer(UpdPeekNow,-60000 * updEvery)
return
}
;##############################################
MenuPotionRoute(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
PotionRecordStart()
return
}
;##############################################
MenuPotionRun(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
WinActivate("ahk_class " GameClass " ahk_exe " GameExe)
Sleep(500)
;(the mouse back where it was afterwards - mousereturn)
mouseOwn := MouseGrab()
PotionManual := 1
PotionRun()
PotionManual := 0
if (mouseOwn)
	MouseLetGo()
return
}
;##############################################
MenuQuickSell(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
QsMenuNow(false)
return
}
;##############################################
MenuQuickSellRehearse(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
QsMenuNow(true)
return
}
;##############################################
MenuLogin(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
ReconnectSetLogin()
return
}
;##############################################
MenuParty(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
PartySetup()
return
}
;##############################################
MenuAlerts(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
AlertSetup()
return
}
;##############################################
MenuRestart(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
BotRestart()
return
}
;##############################################
MenuExit(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
ExitApp()
}
;##############################################
StartBot() { ; V1toV2: Lbl->Func
global
global on := 1
;(the keys - yours from the Keys tab, else F6, F8, Alt+1...: Hotkeys.ahk)
HkApply()
;The bot on (F6): off, it does nothing - no battles, walking, potions or reconnecting. Opened by the game in
;standby (/standby: "Open with Wizard101") it starts off; never turned on, the game closing closes it too
global BotOn := 1, BotStandby := 0, BotEverOn := 1, BotGameSeenAt := A_TickCount
;(a potion run started from the tray: on for it even with the bot off)
global PotionManual := 0
for each, botArg in A_Args
	if (botArg = "/standby")
		BotOn := 0, BotStandby := 1, BotEverOn := 0
	else if (botArg = "/off")
		BotOn := 0
if (BotOn)
	TrayTip("Wizard101 bot", "Running: battles and quest walking. " HkText("bot") " pauses it, 4)
else
	TrayTip("Wizard101 bot", "Ready - Wizard101 started. Press " HkText("bot") " to start the bot (battles, quest walking, potions).")

;Kill calculator (KillCalc.ahk): settings from PlayerStats.txt, enemy health read off the screen,
;and the blades/traps/aura/bubble we've put up this battle
global Stats := {}
global EnemyHP := ""
global BossSlot := 0
global HealthStatus := ""
global AppliedBlades := {}
global BossTraps := {}
global AuraRounds := 0
;Hits we put an enchant on that haven't been cast yet (they keep the enchant): title -> enchant level
global EnchantedHits := {}
;Saving pips for a hit that ends the battle (KillCalc.ahk PlanPips): the hit ("" none), rounds saved so far,
;given up this battle; and your health % off your name plate, and the round it was read in
;(PipSaveBare: the wand's free hit is fine meanwhile; PipSaveTarget/LastPips/Stall: counting the rounds
;saved; PipOrbs: pip orb slots filled, from PipValue)
global PipSaveFor := "", PipSaveRounds := 0, PipSaveGaveUp := 0, OwnHpPct := 0, OwnHpRound := -1
global PipSaveBare := 0, PipSaveTarget := "", PipSaveLastPips := -1, PipSaveStall := 0, PipOrbs := 0
;You're at the keyboard and mouse right now (PlayerActing): the bot waits. PlayerTookRound: you played (part
;of) a round of this battle - the bot's record of blades/traps may be wrong, so no kill check till it ends.
;RoundLeft: the bot left the round that's up to you (seeing it again isn't a new round)
global PlayerActive := 0, PlayerTookRound := 0, RoundLeft := 0, RoundAgain := 0
;"Play for me" (the dashboard's button - green while on -, the tray menu): every check for you off - nothing waits for you or keeps its
;hands off the mouse for you (UserIdle, Walker.ahk). Off at every start: the bot takes control only once you've said so
global PlayForMe := 0
;Walking without a mob the quest doesn't want catching the wizard, since the last catch or the last time the mobs' reach
;was made smaller (ms - Vision.ahk MobShrinkTick)
global MobWalkMs := 0
;(started again by an update - Wiz-Maxxing /check passes /playforme on when it was on: kept on, you'd said so)
for each, botArg in A_Args
	if (botArg = "/playforme")
		PlayForMe := 1
;The game log's planning phase the enemies' odds were last worked out for while you played (EnemyDanger)
global EnemyPhaseDone := 0
;The battle (the game log's duel) your plate was last found in - playerX is that battle's
global PlateDuel := ""
;When the spellbook (out of battle only) was last seen - the walker's "no battle on" (BotNoBattle)
global BookSeenAt := 0
;When a battle round's Pass button was last seen, when the mouse was last moved onto the scene for one that wasn't, and
;how many times since (a button shown as hovered: see the main loop)
global PassSeenAt := 0, PassNudgeAt := 0, PassNudges := 0, PassNudgeSaidAt := 0, PassHover := 0, PassHoverSaidAt := 0
;Your pips this round, from the game's memory or read off your nameplate (-1 = couldn't read; KillCalc.ahk PipsRead),
;and what the log says about where they came from
global PipsNow := -1, PipsNote := ""
;Boost cards cast since the last hit (Settings.ahk CardBoostOk: boostmax)
global BoostRun := 0
global BossMax := 0
global DualBattle := 0
;Party battle roles (Party.ahk PartyBattleRole): this wizard's part this round ("hitter" - plays as ever -, "blader",
;"healer"); who the boosts go to - its school, wizard's name, slot (hammerX/Y its plate) -, the school of Alt+2's pick;
;the blade and trap kind for it (SchoolGroup)
global BattleRole := "", HammerSchool := "", HammerName := "", HammerSlot := 0, ManualSchool := "", HammerGroup := ""
;Your side's name plates this round ({slot: {name, x, y, me}} - EnemySpells.ahk ReadSidePlates, once a round: the round
;it was read for) and your slot; the healer's ally lowest on health (its plate, %, name; the round read)
global SidePlates := {}, SidePlatesKey := "", MySlot := 0
global PartyLowX := "", PartyLowY := "", PartyLowPct := 101, PartyLowName := "", PartyLowKey := ""
;Your hits (shared: a support's blades on you are spent when it goes up) and the log's round of the last; the hitter's
;as last seen, in which battle, and the round its new hit goes out in (blades cast again once it's resolved: Party.ahk
;PartyReblade); your school (shared)
global PartyHits := 0, PartyHitR := 0, PartyHitsSeen := "", PartyHitsDuel := "", PartyHitsWait := "", PartyMySchool := ""
;A support's boosts: the round (the log's) each used flag's cast went out in ({n: round}), the battle that's for, the
;round this round's cast goes out in, the round each treasure / item copy's cast went out in ({"storm/blade@tc": round} -
;KillCalc.ahk BoostSrcUsed) (Party.ahk PartyNoteBoosts)
global PartyFlagRound := {}, PartyFlagDuel := "", PartyCastRound := "", PartySrcRound := {}
;Where traps go this round: on (the boss picked with Alt+1, a party support's pick, else the enemy with the most health -
;KillCalc.ahk TrapTarget) and where; TrapMine: noted for the kill check (BossTraps - not a party support's), the picked
;enemy's most health and slot (TrapPick), why it was picked (the log)
global TrapOn := 0, TrapAtX := 0, TrapAtY := 0, TrapMine := 0, TrapAtMax := "", TrapPick := 0, TrapWhy := ""
;The enemy this battle's traps (BossTraps) went on when no boss was picked: where its plate was and its most health, how
;many plates there were then (KillCalc.ahk TrapPut); its slot in each round's health read (TrapSlot - ReadEnemyHealth;
;the boss's BossSlot when one was picked): the kill check counts them on it only (solotraps:1)
global TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0, TrapSlot := 0
;Blades and traps by damage school (KillCalc.ahk): the game's name of the card on each hit slot's picture ({"balance/hit3":
;"Hydra"} - CardLearn.ahk LearnCards; kept across battles), each hit's heads this look (HitHeads), the % of each boost's
;card in the game's hand, the aura's schools, the schools of the party's last hit (Party.ahk); the planned hit, its heads
;and schools (BoostPick); the school blade's and trap's folders and used flags, the group's; the boosts found (SbFound,
;GbFound), their copies in the game's hand and the treasure / item copies cast (BoostHand, BoostSrcUsed), the other
;schools' pictures asked about this battle, the hitter's planned hit's schools (a support's - Party.ahk), the game's hand
;read this look, what's been said once a battle, a support's misfit blades thrown away this round; the blades cast on you
;that weren't seen there (UseBlade - reboost:1 casts them again after a hit they fit: ConsumeBoosts), the flags BoostOneOf
;held back this round ({blade: [...], trap: [...]})
global SlotGame := {}, HeadsMemo := {}, BoostPctMem := {}, AuraSch := "", PartyLastSch := ""
global PlanHit := "", PlanHeads := "", PlanList := ""
global BladeDir := "", TrapDir := "", BladeU1 := "", BladeU2 := "", TrapU1 := "", TrapU2 := "", Blade2U1 := "", Blade2U2 := "", Trap2U1 := "", Trap2U2 := ""
;(the game's hand's hit the boosts go for while it waits for its pips - KillCalc.ahk BoostPick)
global PlanWait := ""
global SbFound := {}, GbFound := {}, BoostHand := {}, BoostSrcUsed := {}, BoostExtra := "", HammerPlan := "", BoostMemOk := 0, BoostSaid := {}, BoostMisfitDone := 0
global BoostUnrec := [], BoostOneOfOff := {}
;(the boosts this look found by the game's hand alone - no picture found them: cast at their card box - KillCalc.ahk
;BoostSearch, BoostMemBox)
global BoostMemOnly := {}
;(the game's name of the global - bubble - the bot put up this battle: the same isn't cast again - KillCalc.ahk BubbleMem,
;ClickBubble; ResetVariables empties it)
global BubbleUp := ""
;(2026-10-26 - KillCalc.ahk "Absorbs, negative auras and your school's prism": an absorb in hand this look - resources\absorb
;or the game's hand - and whether one that costs no pips can go (the filler casts only such: AbsorbFiller sets
;AbsorbOnlyFree for its box); a negative aura that adds damage taken in hand this look, and the enemies one went on this
;battle - {each of its identities - KillCalc.ahk NegAuraKey: the round} - once in 4 rounds an enemy: UseNegAura; your
;prism on the boss this battle - {hits: your hits counted then (PartyHits), round} - once till a hit of yours goes out:
;UseConvert, KillCalc.ahk ConvertUp; ResetVariables empties them)
global absorb := 0, absorbX := "", absorbY := "", AbsorbFreeOk := 0, AbsorbOnlyFree := 0, negaura := 0, NegAuraOn := {}, ConvertOn := ""
LoadStats()
;"Wait while I play" on, 3 s, at every start - the bot never takes the mouse from you as it starts (you asked,
;2026-10-23); the tray menu, the dashboard and Settings change it for the run
if (!HandsOffOn() || !Stats.Has("handsoff") || Stats["handsoff"] != 3)
	{
	if (!StatsSet([["handsoffon", 1], ["handsoff", 3]], "Wait while I play: on and 3 s at every start"))
		Stats["handsoffon"] := 1, Stats["handsoff"] := 3 ;  V1toV2: Invalid Index errors?, try 'Stats.Push(<val>)'
	}

;Misc Initilization
global inbattle := 0
global roundnumber := 0
global battles := 0
global BossChoosen := 0
;The boss picked with Alt+1, from the game window's top left in UI scale 1 pixels (BossX/BossY are
;worked out from it each round, so a moved or resized window still finds it)
global BossRelX := 0, BossRelY := 0
;Enemy nameplates found this round, left to right ({x, y} on screen; KillCalc's ReadEnemyHealth)
global EnemyPlates := []
;(when they were last read - ReadEnemyHealth)
global EnemyPlatesAt := 0
global boosts := 0
global afk := 0
global bossX := 0
global bossY := 0
global afk := 0

;Screen variable initilization
;Game* is the Wizard101 client area in screen coordinates, ScreenX/ScreenY is its center
global GameExe := "WizardGraphicalClient.exe"
global GameClass := "Wizard Graphical Client"
;Colour tolerance for card pictures (cards shimmer a little between rounds)
global CardTol := 20
;The game draws its UI bigger or smaller with the window size, the Windows display scaling and its
;UI Size setting, and ImageSearch only finds a picture at the size it was cut at. So there's a set of
;pictures per UI size: the main one (resources\, storm\, ... cut at a 1920x1080 window, UI Size
;Small) and a ui<scale> folder for each other size, e.g. ui1.265\ (1920x1200 window at 100%
;scaling: the UI 1.265 times as big). A ui folder only needs the pictures cut at its size; for the
;rest the main picture is used (it won't match at that size, so that card counts as not in hand).
;The set whose Pass button or spellbook is on screen is used (UsePicSet), and every pixel distance
;below is times UiScale. At a size with no pictures cut for it, the bot makes a set itself from the
;cut ones (PicScale.ahk: generated\ui<scale>\)
global PicSets := []
global PicSet := 1
global PicDir := A_WorkingDir
global UiScale := 1.0
global LastSetTry := 0
;Half the width of the area searched for cards in hand (a full 7-card hand is about 580 px wide at
;UI scale 1). Set by UsePicSet
global HandHalf := 400
;Half the distance between two cards in hand: when a card leaves the hand the rest slide this far
;(41 at UI scale 1). Set by UsePicSet
global HalfPitch := 41
global GameLeft := 0
global GameTop := 0
global GameW := A_ScreenWidth
global GameH := A_ScreenHeight
global GameRight := A_ScreenWidth
global GameBottom := A_ScreenHeight
global ScreenX := A_ScreenWidth / 2
global ScreenY := A_ScreenHeight / 2
UpdateGameRect()

;debug.log: what the script sees and decides each round (starts fresh every start / restart; the last
;run's is kept as debug.previous.log - e.g. to see why a wizard died before you restarted)
Try {
	FileMove(A_ScriptDir "\debug.log", A_ScriptDir "\debug.previous.log", 1)
	ErrorLevel := 0
} Catch as Err {
	ErrorLevel := Err.Extra
}
;The dashboard: statistics, what the bot sees, the log as it's written (Dashboard.ahk; Windows+2)
DashInit()
SetTimer(UpdPeekNow,-45000)
HandsOffShow()
PlayForMeShow()
GameFrontShow()
BotOnShow()
WatchShow()
DebugLog("Started " BotVersion() ". Game area " GameLeft "," GameTop " " GameW "x" GameH)
if (PlayForMe)
	DebugLog("Play for me kept on: started again by an update while it was on")
LoadPicSets()
;(nothing to tell the size by yet: the set this window size was last played at, else the main one)
if (!DetectPicSet())
	UsePicSet(PicSetForSize(), "nothing on screen to tell the size by yet: " (PicScaleFor(GameW "x" GameH) != "" ? "the size this window was last played at (generated\scales.txt: " GameW "x" GameH "=" PicScaleFor(GameW "x" GameH) ")" : "no size remembered for " GameW "x" GameH " - the main set"))
LastBeat := 0
SeenOut := 0

;Quest walking: on from the start (F8 switches it off and on)
if (WalkerInit("Wizard101 bot " BotVersion()))
	{
	Walking := 1
	DebugLog("Walking on (" HkText("walk") " switches it off)")
	}
else
	DebugLog("Walking off: couldn't load the quest arrow shapes (AutoQuester\resources\arrow_refs.txt)")

;Auto-reconnect (Reconnect.ahk): on from the start (tray menu switches it off and on)
ReconnectInit()

;(started again by an update: walking, auto-reconnect and Learn every card as they were - Wiz-Maxxing /check passes
;them on, UpdBotArgs)
for each, botArg in A_Args
	if (botArg = "/nowalk" && Walking)
		{
		Walking := 0
		DebugLog("Walking off: it was off before the update (" HkText("walk") " switches it on)")
		}
	else if (botArg = "/noreconnect" && RcOn)
		{
		RcOn := 0
		Tray.Uncheck("Auto-reconnect on/off")
		DebugLog("Auto-reconnect off: it was off before the update")
		}
	else if (botArg = "/learnall" && !LearnAll && IsFunc("LearnAllToggle"))
		LearnAllToggle.Call()

;Stats (StatsRead.ahk): read by itself out of battle when the school it fights with has none yet, or
;when asked (tray menu, or StatsReader.ahk started while this runs - it sends message 0x5555)
global StatsWanted := 0
OnMessage(0x5555, StatsAsked)

;The Python vision helper (Vision.ahk): finds the cards in hand and school badges; ImageSearch if it
;can't run
VisionStart()
;(the party - Party.ahk: this bot's state to the helper and the party back, every half second, battles too)
SetTimer(PartyTimer,500)
;(the Network tab - Network.ahk: this bot's state to the others on your home network, theirs and commands back)
SetTimer(NetTick,2000)
OnExit("VisionOnExit")

;Initializes modes
global commandmode := 0
global dualmode := 0
global responcemode := 0
global devmode := 0
global loremode := 0
global boostlimitmode := 0
global dualhittermode := 0
global statsmode := 0
global loopmode := 0

;Sleep timings
global Tick := 100
;Why the bot is holding (afk): "mana" - it carries on by itself once there's mana again (CheckAfk)
global AfkWhy := "", AfkRetries := 0
;When the picture set in use last matched (the spellbook or a round's Pass button), and at what game size
global PicSetOkAt := 0, PicSetOkSize := ""
global Buffer := 300
global Half := 600
global Second := 1100
global Five := 5000
global Ten := 10000
global Loading := 15000 

ResetUsed()	
TestRound()
}
;##############################################
TestRound() { ; V1toV2: Lbl->Func
global
Loop
{
	;(no round being played here: a battle round's hold on your mouse let go, however the round was left - Settings.ahk
	;MouseLockOff)
	MouseLockOff("round")
	;Corrections made on the dashboard's Spells tab: applied here, out of battle only - never in a round, where a hit
	;moved to another slot would take the round's enchants and saved pips with it (Spells.ahk). With the bot off too
	;An update installed by itself (UpdAuto - Settings: autoupdate): out of battle only too
	if (inbattle != 1)
		{
		SpApplyPending()
		UpdAuto()
		;(the deck for what's ahead - Decks.ahk)
		DeckTick()
		}
	;Off (F6) - or opened by the game in standby: nothing till F6 (no battles, walking, potions or reconnecting).
	;Opened in standby and never turned on: Wizard101 closing closes the bot too (it opens again with the game)
	if (!BotOn)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(your mouse never locked with the bot off - Settings.ahk MouseLockRelease)
		MouseLockRelease("the bot's off")
		if (BotStandby && !BotEverOn)
			{
			ErrorLevel := ProcessExist(GameExe)
			if (ErrorLevel)
				BotGameSeenAt := A_TickCount
			else if (A_TickCount - BotGameSeenAt > 15000)
				{
				DebugLog("Wizard101 closed while the bot was waiting for " HkText("bot") " - closing the bot (it opens again with the game)")
				ExitApp()
				}
			}
		Sleep(300)
		continue
		}
	UpdateGameRect()
	if (A_TickCount - LastBeat > 10000)
		{
		LastBeat := A_TickCount
		;(another program's window: only its program's name - its title can be anything of yours, and the log goes to the
		;OneDrive copy, bug reports and the Network tab)
		activeTitle := WinGetTitle("A")
		activePid := WinGetPID("A")
		if (!GameActive() && activePid != DllCall("GetCurrentProcessId"))
			{
			activeExe := WinGetProcessName("A")
			activeTitle := "another program (" (activeExe != "" ? activeExe : "?") ")"
			}
		DebugLog("Watching for a round. Active window: " activeTitle " | game area " GameLeft "," GameTop " " GameW "x" GameH)
		}
	;You're playing (a key, click or mouse move of yours in the last handsoff seconds): the bot waits - no
	;battle rounds, no walking, no potions; it lets go of any walking key at once
	if (PlayerActing())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		;(never your mouse locked while you play - Settings.ahk MouseLockRelease)
		MouseLockRelease("you're playing")
		if (inbattle == 1 && !PlayerTookRound)
			PlayerTookRound := 1, DebugLog("  (you're playing in this battle: no kill check till it ends - the bot can't know which blades and traps are left)")
		;(the enemies' likely spells kept up on the dashboard while you play the rounds - once a round, by the game's log,
		;read here too: 2026-10-23 its list stayed on the last round the bot played. Your plate as found in another battle
		;isn't read for your health - an ally's can be there now)
		BattleLogRead()
		if (IsFunc("BattleLogInBattle") && BattleLogInBattle() && BlPhase = "kPhase_Planning" && BlPhaseAt != EnemyPhaseDone && A_TickCount - BlPhaseAt > 1500)
			{
			if (PlateDuel != BlDuel)
				playerX := 0, playerY := 0
			EnemyPhaseDone := BlPhaseAt, EnemyDanger()
			}
		;(the round left to you is over once its Pass button goes)
		if (RoundLeft)
			{
			if (PassButtonAt(&gx, &gy))
				RoundLeft := 0
			}
		Sleep(200)
		continue
		}
	;(the game's log, for the battle: who's in it, what each cast - EnemySpells.ahk)
	BattleLogRead()
	;(mobs kept off less far after 10 minutes of walking unbothered - Vision.ahk)
	MobShrinkTick()
	;Disconnected, or the game closed: get back online first (no battles or walking meanwhile)
	if (ReconnectCheck())
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		Sleep(300)
		continue
		}
	ErrorLevel := !ImageSearch(&roundX, &roundY, GameLeft, GameTop, GameRight, GameBottom, PicOpt("resources\roundfinish.png"))
	bookSeen := (ErrorLevel = 0)
	;(the spellbook only proves the set right when its picture isn't too see-through to tell sizes apart)
	if (bookSeen)
		{
		BookSeenAt := A_TickCount
		if (!PicTooThin(PicPath("resources\roundfinish.png")))
			PicSetOkAt := A_TickCount, PicSetOkSize := GameW "x" GameH, PicCutOk(PicPath("resources\roundfinish.png"))
		}
	if (bookSeen)
		{
		if (!SeenOut)
			{
			DebugLog("Out of battle (spellbook visible)")
			SeenOut := 1
			}
		if (inbattle = 1)
			{
			battles++
			;(the backpack looked at after the bot's battle - QuickSell.ahk: noted before ResetVariables clears inbattle)
			QsBattleEnd()
			}
		;(the mouse, if any of this takes it - potions, stats - goes back where it was at the end: mousereturn)
		MouseGrab()
		;(the mob loop, lore farming, afk: they move the wizard themselves - the walker's keys let go and the game at 1x
		;first, not after their first steps)
		if ((afk || loopmode || loremode) && (KeysDown || HeldW || SpeedNow > 1))
			ReleaseKeys()
		checkafk()
		;Fled a battle out of mana or cards (Flee.ahk): a potion first (or a run to buy some), then on as usual
		FleeAfter()
		checkmana()
		CommandAfk()
		CommandEnter()
		CommandWalk()
		CommandPort()
		CommandOff()
		CommandReload()
		ResetVariables() 
		ResetUsed()	
		;(the card learner's work out of battle: its catalog checked once a run, stray copies of a learned picture put
		;right, a stronger learned hit arranged into hit1-3 - CardLearn.ahk)
		if (IsFunc("LearnOutOfBattle"))
			LearnOutOfBattle.Call()
		StatsAuto()
		;Low on health: a potion, or a run to buy more (Potions.ahk)
		PotionCheck()
		;The backpack full after the battle (Prospector Zeke's alert, the game's memory): quick sold for gold - quicksell,
		;Settings: THE BACKPACK (QuickSell.ahk). Here, before the walker's step: walking waits while it runs
		QsTick()
		MouseLetGo()
		;(the log's OneDrive copy, when it's on: a picture of the game every 2 minutes - LogMirrorSnap)
		LogMirrorSnap(120000)
		mobloop() ; V1toV2: Gosub
		LoreLoop() ; V1toV2: Gosub
		}
	;(the Pass button, or as it's drawn with the mouse on it - PassButtonAt)
	PassButtonAt(&startX, &startY)
	;Kept, since writing the log line below resets ErrorLevel (which would start a round that isn't there)
	startErr := ErrorLevel
	if (startErr = 2 && !PicError)
		{
		DebugLog("Can't open " PicPath("resources\roundstart.png") " - the pictures aren't where the script expects them")
		PicError := 1
		}
	If (startErr = 0)
		{
		PassSeenAt := A_TickCount, PassNudges := 0
		;(a battle: the game at normal speed - Cheat Engine's speedhack, if walking had it on)
		SpeedSet(0, "a battle round", true)
		;(gamefront: the game in front for its cards - a first click on a window behind only brings it forward)
		if (!GameActive())
			GameToFront("a battle round is up", false, UserIdle() > 300000)
		;(the first round at a window size: the UI size measured from Pass and Flee before it's played - a made set's
		;Pass button, mostly see-through, matches at a size a little off too: a 2544x1401 window's 1.121 was kept at
		;2560x1440 borderless, 1.144, and your nameplate never found. 3 rounds tried, then played with the set in use)
		pmSize := GameW "x" GameH
		;(not on a hovered Pass - the yellow one's picture tells the size: the next round, the mouse moved off it)
		if (PicMeasuredSize != pmSize && !PassHover)
			{
			;(the Pass button just found is a cut picture - it only matches nearly pixel for pixel, *3: that's the size.
			;A made one is mostly see-through and matches at a size a little off too)
			pmPic := PicPath("resources\roundstart.png")
			if (SubStr(pmPic, -4) = ".png")
				{
				PicMeasuredSize := pmSize
				DebugLog("UI size: the Pass button cut at " Round(PicSets[PicSet].scale, 3) " matches - that's the size (" pmSize ")")
				}
			else
				{
				if (PicMeasureSize != pmSize)
					PicMeasureSize := pmSize, PicMeasureTries := 0
				if (PicMeasureTries < 3)
					{
					PicMeasureTries += 1, pmWas := PicSet, PicMeasureWhy := ""
					;(another set: the round start looked for again with it)
					if (DetectUiScale())
						{
						if (PicSet != pmWas)
							continue
						}
					else
						DebugLog("UI size: not measured this round - " PicMeasureWhy " (try " PicMeasureTries " of 3)")
					}
				}
			}
		;(PicCutOk: only the set's own cut Pass button counts - not one made for a card learner's folder at its size)
		PicSetOkAt := A_TickCount, PicSetOkSize := GameW "x" GameH, PicCutOk(PicPath(PassHover ? "resources\roundstart_hover.png" : "resources\roundstart.png"))
		PicRemember()
		;(the set's UI scale against the game's memory's: a disagreement logged, nothing switched on it yet - Vision.ahk)
		PicMemCheck()
		;A battle round is up: stop walking first (a key could still be held from the last step)
		if (KeysDown || HeldW)
			ReleaseKeys()
		RoundAgain := RoundLeft, RoundLeft := 0
		if (RoundAgain)
			{
			;(the round the bot left to you, still up: not a new round)
			DebugLog("Round start again (the round left to you is still up): Pass button at " startX - GameLeft "," startY - GameTop)
			RoundStart() ; V1toV2: Goto->FuncCall
			Return ; V1toV2: post-return for Goto
			}
		DebugLog("Round start: Pass button at " startX - GameLeft "," startY - GameTop)
		;(a battle's first round: which mob started it, from how far and how far off its facing - Vision.ahk)
		if (SeenOut)
			CaughtLog()
		LogMirrorSnap(120000)
		SeenOut := 0
		if (dualmode == 1)
			{
			roundnumber++
			roundnumber := %roundnumber% / 2
			} else
				{
				roundnumber++
				}
		RoundStart() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
		}
	;Neither the spellbook nor the Pass button: maybe the game's UI is another size now (the window
	;or the display scaling changed), so every few seconds look with the other picture sets - and if
	;none fits and a round is up, measure the UI size and make a set for it
	;(only when the game's window changed size since the pictures last matched, or nothing has matched for 10
	;minutes - between battle rounds and in dialogues neither shows, and a made set can match what's there then)
	if (!bookSeen && A_TickCount - LastSetTry > 3000 && (PicSetOkSize != GameW "x" GameH || A_TickCount - PicSetOkAt > 600000))
		{
		LastSetTry := A_TickCount
		if (DetectPicSet(true) || DetectUiScale())
			continue
		}
	;In a battle (no spellbook since one) and no round seen for 15 s: Wizard101 draws a button as hovered - white, not
	;yellow - when the mouse last left the game from it (a jump to another monitor never crosses the game), and the Pass
	;button isn't known by its picture then (2026-10-23 06:35: a whole battle left to auto-pass). You away, the game in
	;front: the mouse moved onto the scene - every 15 s, said at most once in 5 minutes (a round's spells take 15 s and more).
	;A battle's first round too: by the game's log, its planning phase up 4 s and no round seen (2026-10-23 17:22: a
	;first round's Pass drawn hovered, not one round of the battle seen till 17:25)
	;(only before a round of the battle's been seen: after the bot's own, a party's planning goes on while the others choose)
	passLog := inbattle != 1 && BattleLogPlanning(4000)
	if (!bookSeen && ((inbattle = 1 && PassSeenAt && A_TickCount - PassSeenAt > 15000) || passLog) && A_TickCount - PassNudgeAt > 15000
		&& GameActive() && UserIdle() > 5000)
		{
		PassNudgeAt := A_TickCount, PassNudges += 1
		MouseMove(ScreenX, GameTop + Round(GameH * 0.4), 0)
		if (A_TickCount - PassNudgeSaidAt > 300000)
			PassNudgeSaidAt := A_TickCount, DebugLog("In a battle, no round seen " (passLog ? "though the game's log says one is up (" Round((A_TickCount - BlPhaseAt) / 1000) " s)" : "for " Round((A_TickCount - PassSeenAt) / 1000) " s") " - the mouse moved onto the scene (a button the mouse was left on shows as hovered, and isn't known; said once in 5 minutes)")
		}
	;No battle round to play right now: take a step towards the quest goal (with no quest arrow
	;on screen, e.g. during the battle's spell animations, it just lets go of the keys and waits).
	;Not while afk, mob-loop or lore farming: those move the wizard themselves
	if (afk || loopmode || loremode)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		}
	;(low on health with no potions and none to be bought: standing still till it's back - Potions.ahk)
	else if (PotionResting)
		{
		if (KeysDown || HeldW)
			ReleaseKeys()
		PotionRestCheck()
		}
	;(a party's follower: where the leader goes instead of its own quest - Party.ahk)
	else if (PartyFollowing())
		PartyFollowStep()
	;(a dungeon run on the Dungeons tab: its way instead of the quest's - Dungeons.ahk)
	else if (IsObject(DgRun))
		DungeonStep()
	else
		WalkStep()
}
RoundStart()
}
;##############################################
RoundStart() { ; V1toV2: Lbl->Func
global

;A wait before playing a new round (roundwait, the Settings window) - then, as the round's look began: you may
;have started playing meanwhile (the round's yours - nothing's been taken yet), or the round may be over
if (!RoundAgain && Stat("roundwait") > 0)
	{
	Sleep(Stat("roundwait"))
	UpdateGameRect()
	if (PlayerActing())
		{
		DebugLog("  you're playing (during the wait before the round) - leaving this round to you")
		RoundLeft := 1
		if (!PlayerTookRound)
			PlayerTookRound := 1
		TestRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
		}
	if (PassButtonAt(&rwX, &rwY))
	{
		TestRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
	}
	}
;(a walker notice mustn't cover what the battle reads)
WalkNoteHide()
;(where the mouse is now: it goes back there when the round's done - mousereturn)
MouseGrab()
;(your mouse locked till the round's done - Settings.ahk MouseLockOn; mouselock:0 not)
MouseLockOn("round")
;(Pass drawn hovered - the mouse on it: moved onto the scene, so the buttons and cards look as their pictures)
if (PassHover)
	{
	MouseMove(ScreenX, GameTop + Round(GameH * 0.4), 0)
	;(and the mouse's way back - mousereturn - there too, not onto Pass: the next round would come up hovered again)
	if (MouseHomeSet && MouseOnGame(MouseHomeX, MouseHomeY))
		MouseHomeX := ScreenX, MouseHomeY := GameTop + Round(GameH * 0.4)
	if (A_TickCount - PassHoverSaidAt > 300000)
		PassHoverSaidAt := A_TickCount, DebugLog("  the Pass button was drawn hovered (the mouse on it) - the mouse moved onto the scene (said once in 5 minutes)")
	}
CenterMouse()

;The Alt+1 boss where the window and UI size are now (the nameplates are drawn from its top left)
if (BossChoosen == 1)
	BossX := GameLeft + Round(BossRelX * UiScale), BossY := GameTop + Round(BossRelY * UiScale)

global inbattle := 1
LearnedThisRound := 0, LastHandAnswer := "", DiscardedUnused := 0, DiscardOffCount := 0, BoostMisfitDone := 0

;Both windows share one record of blades/traps in dual mode, so the kill check is off for that whole battle
if (dualmode == 1)
	{
	DualBattle := 1
	}

;Finds the player
global playerX := 0
global playerY := 0
global player := 1

;(the game's log read now: a battle's first round names its wizards only as the Pass button comes up - the loop's last
;read, at most every 500 ms, can be from before; only what's new is read)
BattleLogRead(true)
;(more than one of your wizards in the battle - a party: your plate by your name, EnemySpells.ahk PlayerPlateByName)
global PlateByName := 0
if (PlayerPlateByName(pbnX, pbnY))
	{
	playerX := pbnX, playerY := pbnY, PlateByName := 1, player := 1
	}
else
	{
	ErrorLevel := !ImageSearch(&playerX, &playerY, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, PicOpt("resources\player.png"))
	if (ErrorLevel = 0)
		{
		player := 1
		} else if (ErrorLevel = 1)
			{
			ErrorLevel := !ImageSearch(&playerX, &playerY, GameLeft, GameTop + GameH / 4, GameRight, GameBottom, PicOpt("resources\player2.png"))
			if (Errorlevel = 0)
				{
				player := 1
				}
			} else 
				{
				TestHammer() ; V1toV2: Goto->FuncCall
				Return ; V1toV2: post-return for Goto
				}
	}
		
;(the battle it's this battle's plate for)
if (player == 1)
	PlateDuel := BlDuel

;Find player school

global school := ""
global schoolX := 0
global schoolY := 0

;(the badge nearest your plate - it's left of your name: a party battle's next plate is ~300 px on, past the box)
if (player == 1)
	school := BestBadge(playerX - Px(100), playerY - Px(100), playerX + Px(250), playerY + Px(250), &schoolX, &schoolY, playerX - Px(45), playerY + Px(15))
TestHammer()
}
;##############################################
TestHammer() { ; V1toV2: Lbl->Func
global

global hitter := 0
global hitschool := ""
global hammerX := 0
global hammerY := 0
global hitterX := 0
global hitterY := 0

;(the school whose badge matches best: a badge made at another size roughly matches the others too) - your own: the
;cards are looked for in your school's pictures whoever the boosts go to (Alt+2's pick, or a party battle's hitter -
;after). Your plate found by your name (a party battle): its badge, read by it - the helper's one-badge-a-school answer
;could be a teammate's of the same school
if (PlateByName && BadgeNumber(school))
	hitschool := school, hitterX := schoolX, hitterY := schoolY, hitter := BadgeNumber(school)
else
	{
	hitschool := BestBadge(GameLeft, GameTop + GameH * 3 // 4, GameRight, GameBottom, &hitterX, &hitterY, playerX, playerY)
	hitter := BadgeNumber(hitschool)
	}

hammerX := hitterX
hammerY := hitterY

;No school badge found on the name plates - your plate in another slot can show none (seen with a 1280x1024
;window, the left plate): the school this character was seen fighting with before (resources\characters.txt,
;by its CharID in the game's log), and your own plate - found by your name - as the hitter's (a solo battle)
if (hitter = 0) && (player == 1)
	{
	knownSchool := StatsSchoolOf(StatsCharID())
	if (BadgeNumber(knownSchool))
		{
		hitschool := knownSchool, hitter := BadgeNumber(knownSchool)
		hammerX := playerX + Px(25), hammerY := playerY + Px(8)
		if (school = "")
			school := knownSchool
		DebugLog("  no school badge found on the name plates - this character fought as " knownSchool " before: using that, with your own plate as the hitter's")
		}
	}
;(the deck for this battle, once the school's known - the badge's or the one fought as before: a new battle, or your
;Alt+1 boss pick: Decks.ahk)
if (hitter != 0)
	DeckRound()

;A character the bot has no pictures for (no school icon it knows on the screen, e.g. a new wizard of
;another school): leave the round to you rather than passing it, and keep a picture of the round so
;that character's name, school icon and cards can be cut from it
if (hitter = 0)
	{
	MouseLockOff("round")
	savedTo := SaveRoundPicture()
	;(the mouse back once the picture's taken)
	MouseLetGo()
	DebugLog("  no school icon the bot knows - leaving this round to you" (savedTo = "" ? "" : " (picture of it: " savedTo ")"))
	TrayTip("Wizard101 bot", "The bot doesn't know this wizard's school yet - play this round yourself.", 1)
	AlertSend("school", "a wizard it doesn't know", "No school icon the bot knows on the name plates - the round is left to you (a new wizard? its pictures get cut from the round pictures it saves).")
	;Wait for the round to be played (the Pass button goes), then watch for the next one
	unknownFrom := A_TickCount
	Loop
		{
		Sleep(500)
		UpdateGameRect()
		if (PassButtonAt(&unknownX, &unknownY) != 0 || A_TickCount - unknownFrom > 180000)
			break
		}
	TestRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	}

;Who the boosts go to: you - as found above -, the plate picked with Alt+2, or a party battle's hitter (Party.ahk
;PartyBattleRole: this wizard a blader or healer); its school picks the elemental / spirit blade and trap (SchoolGroup -
;Ice is elemental)
HammerSchool := hitschool
if (Manual = 1)
	hammerX := ManualX, hammerY := ManualY, HammerSchool := ManualSchool != "" ? ManualSchool : hitschool
PartyBattleRole()
HammerGroup := SchoolGroup(HammerSchool)
;(the elemental / spirit blades and traps are looked for by the planned hit's schools now - KillCalc.ahk BoostSearch)

;Looks at the hand (and again after discarding, since the cards shift)
if (!RoundAgain)
	Discards := 0
FindCards()
}
;##############################################
FindCards() { ; V1toV2: Lbl->Func
global

;Enchants (and a fresh look at the hand for the vision helper; each hit's heads looked at afresh - KillCalc.ahk HitHeads)
VisionForget()
HeadsMemo := {}
FindEnchant()

;Finds cards avaliable

global sharpen := 0
Find("sharpen", &sharpen, &SharpX, &SharpY, &"resources") 
 
global potent := 0
Find("potent", &potent, &PotentX, &PotentY, &"resources") 

;(the school blades and traps - yours and those of every school the hits need: KillCalc.ahk BoostSearch, once the pips
;are read)
global blade := 0

global blade3 := 0
Find("blade3", &blade3, &Blade3X, &Blade3Y, &"resources")
 
global blade4 := 0
Find("blade4", &blade4, &Blade4X, &Blade4Y, &"resources")

global trap := 0

global trap3 := 0
Find("trap3", &trap3, &trap3X, &trap3Y, &"resources")

global aura := 0
Find("aura", &aura, &auraX, &auraY, &hitschool)

global tower := 0
Find("tower", &tower, &towerX, &towerY, &"resources")

global reshuffle := 0
Find("reshuffle", &reshuffle, &reshuffleX, &reshuffleY, &"resources")

global feint := 0
Find("feint", &feint, &feintX, &feintY, &"resources")

global bubble := 0
Find("bubble", &bubble, &bubbleX, &bubbleY, &hitschool)

global convert := 0
Find("convert", &convert, &convertX, &convertY, &hitschool)
;(whether the boss needs it - the game's memory: of your school, it resists your hits - is asked when the chain gets to it:
;NeedsConvert; your school's prism no picture finds: by the game's hand - KillCalc.ahk ConvertMem)

;(an absorb - resources\absorb, its learned slot, by its picture when it has one; else the game's hand: KillCalc.ahk
;AbsorbMem - and a negative aura, by the game's hand only: NegAuraMem)
global absorb := 0
absorbX := "", absorbY := "", AbsorbFreeOk := 0, negaura := 0
if (AbsorbPicThere())
	{
	Find("absorb", &absorb, &absorbX, &absorbY, &"resources")
	AbsorbFreeOk := (absorb == 1) ? AbsorbSlotFree() : 0
	}

;Finds hit specific cards
if (hitter != 0)
	{
	global hit4 := 0
	Find("hit4", &hit4, &hit4X, &hit4Y, &hitschool)
	
	global hit3 := 0
	Find("hit3", &hit3, &hit3X, &hit3Y, &hitschool)
	
	global hit2 := 0
	Find("hit2", &hit2, &hit2X, &hit2Y, &hitschool)
	
	global hit1 := 0
	Find("hit1", &hit1, &hit1X, &hit1Y, &hitschool)

	;The wand's own card (an item card from the wand, e.g. Minor Clash: no pips)
	global wand := 0
	Find("wand", &wand, &wandX, &wandY, &hitschool)

	;Healing cards (heal1 / heal2 pictures in the school's folder), used when your health is low
	global heal1 := 0
	Find("heal1", &heal1, &heal1X, &heal1Y, &hitschool)
	global heal2 := 0
	Find("heal2", &heal2, &heal2X, &heal2Y, &hitschool)
	}
;(the deck in use's slots it doesn't play: out of this round's hand - Decks.ahk)
DeckFilterHand()

;(the boosts going to another school's wizard - Alt+2's pick, a party battle's hitter: your school's bubble only boosts
;your school's hits - not cast; its blades and traps are looked for in its school's folder - BoostSearch; a blader's or
;healer's aura only boosts itself)
if (HammerSchool != hitschool)
	bubble := 0
if (PartySupport())
	aura := 0

;How many pips you have (the game doesn't grey out cards you can't afford): the game's own count from its memory, else
;off the pip row under your name (KillCalc.ahk PipsRead)
PipsNow := PipsRead()
DebugLog("  pips=" PipsNow PipsNote)
DebugLog("  player=" player " at " playerX - GameLeft "," playerY - GameTop " school=" school " | hitter=" hitschool " at " hammerX - GameLeft "," hammerY - GameTop " | enchant=" enchant
	. (PartySupport() ? " | " BattleRole ": the boosts to " HammerName " (" (HammerSchool = "" ? "school not known" : HammerSchool) ")" : ""))
;The blades and traps of every school the hits need - a Balance Hydra's fire, ice and storm (KillCalc.ahk BoostSearch: the
;game's memory, read-only, says what's in hand; without it, your school's as before)
BoostSearch()
;(which school the logged-in character is, for StatsReader: the badge by its own name plate - the
;hitter can be an ally)
if (PlateByName || !PlayerPlates2())
	{
	StatsNoteSchool(school)
	;(and the party's told it: Party.ahk)
	if (BadgeNumber(school))
		PartyMySchool := school
	}
DebugLog("  cards: hit1-4=" hit1 hit2 hit3 hit4 " wand=" wand " heal1-2=" heal1 heal2 " blade=" blade " blade2=" blade2 " blade3=" blade3 " blade4=" blade4 " sharpen=" sharpen " trap=" trap " trap2=" trap2 " trap3=" trap3 " potent=" potent " feint=" feint " aura=" aura " bubble=" bubble " convert=" convert " tower=" tower " reshuffle=" reshuffle " absorb=" absorb " negaura=" negaura)

;Cards in hand the bot has no picture for yet: learned (CardLearn.ahk); one that went into a free slot is
;used this round, so look at the hand again
if (Manual != 1) && (!LearnedThisRound)
	{
	LearnedThisRound := 1
	if (LearnCards())
	{
		FindCards() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
	}
	}

;Discard (right-click) cards that can't help this battle, then look at the hand again (not while learning
;every card: that discards everything it knows): first, once a round, the cards it never plays (learned, in no
;slot - CardLearn.ahk DiscardUnused, off the hand as the helper read it), then spare blades and Sharpen
;(and cards of kinds switched off in the Settings window: Settings.ahk DiscardSwitchedOff)
if (!LearnAll) && (Discards < 3) && (DiscardUnused() + DiscardSpare() + DiscardSwitchedOff())
	{
	Discards++
	s(Stat("discardlook"))
	FindCards() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	}

CenterMouse()

;Our aura only lasts a few rounds
if (AuraRounds > 0 && !RoundAgain)
	{
	AuraRounds--
	}

;Turned off (F6) during the round: it's left - nothing more cast, the mouse given back
if (!BotOn)
	{
	DebugLog("  bot off (" HkText("bot") ") - leaving this round")
	RoundLeft := 1
	MouseLetGo()
	MouseLockOff("round")
	TestRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	}

;You started playing while the bot looked at the hand: the round is yours
if (PlayerActing())
	{
	DebugLog("  you're playing - leaving this round to you")
	RoundLeft := 1
	if (!PlayerTookRound)
		PlayerTookRound := 1, DebugLog("  (no kill check till this battle ends - the bot can't know which blades and traps you use)")
	EndRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	}

;Out of mana or cards - it could only pass for the rest of the battle: flee, and try again (Flee.ahk)
if FleeCheck()
{
	EndRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
}

;Learning every card (dashboard button / tray menu): no casting but a heal when low - learn, discard what
;it knows so the next round draws new cards, pass (CardLearn.ahk LearnAllRound)
if (LearnAll)
	{
	if (player == 1) && ((heal1 == 1) || (heal2 == 1)) && OwnHealthLow()
		{
		if (heal1 == 1) && UseHeal("heal1", &heal1, hitschool)
		{
			EndRound() ; V1toV2: Goto->FuncCall
			Return ; V1toV2: post-return for Goto
		}
		if (heal2 == 1) && UseHeal("heal2", &heal2, hitschool)
		{
			EndRound() ; V1toV2: Goto->FuncCall
			Return ; V1toV2: post-return for Goto
		}
		}
	LearnAllRound()
	ClickPass()
	EndRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	}

;Kill check: read every enemy's health and, if a hit in hand already kills them all, cast it now instead of boosting more
global KillHit := ""
global KillEnchant := 0
PipSaveFor := ""
if (hitter != 0) && (DualBattle != 1) && (!PlayerTookRound) && (Stat("healthocr") == 1) && ((hit1 == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1) || (wand == 1 && Stat("usewand")))
	{
	if (ReadEnemyHealth())
		{
		;(nothing ends it now: one would with an enchant on it and there's none in hand - drawenchant: treasure cards
		;drawn for one, then looked at again - Draw.ahk; still nothing: is a hit worth saving pips for? KillCalc.ahk
		;PlanPips)
		if (!FindLethalHit(KillHit, KillEnchant))
			{
			if (DrawWouldKill() && DrawForKill())
				FindLethalHit(KillHit, KillEnchant)
			;(a blader's or healer's pips are for its boosts: no saving them for a hit)
			if (KillHit = "" && !PartySupport())
				PlanPips()
			}
		}
	ShowKillInfo()
	DebugLog("  kill check: " HealthText() " -> " (KillHit = "" ? "no lethal hit" : KillHit (KillEnchant ? " with enchant" : "")))
	;(and the damage it counts on from each hit in hand - you asked, 2026-10-23)
	khText := KillHitsText()
	if (khText != "")
		DebugLog("  your hits now: " khText)
	CenterMouse()
	if (KillHit != "")
		{
		if UseHit(&KillHit, &%KillHit%, &hitschool, KillEnchant)
			{
			;(a saved-for hit went out: the next save counts afresh)
			PipSaveRounds := 0, PipSaveTarget := "", PipSaveStall := 0, BoostRun := 0
			EndRound() ; V1toV2: Goto->FuncCall
			Return ; V1toV2: post-return for Goto
			}
		}
	}

;Enemy spells (EnemySpells.ahk): what each enemy will likely cast, off the wiki and the battle so far (the game's log) -
;logged and on the dashboard; the chance their hits kill you this round defendat % or more: a heal, else Tower Shield,
;first (a hit that ends the battle went first, above)
;(worked out every round the bot plays - the dashboard's list kept up even after you played one; defending only while
;the bot's record of the battle is its own)
if (hitter != 0) && (playerX != "")
	{
	EnemyPhaseDone := BlPhaseAt
	if (EnemyDanger() && !PlayerTookRound && EnemyDefend())
	{
		EndRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
	}
	}

;A party battle's healer (Party.ahk): the ally lowest on health - under healat % and lower than you - healed first
if (BattleRole = "healer") && ((heal1 == 1) || (heal2 == 1)) && PartyHealAlly()
{
	EndRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
}

;Low on health (under healat % of it, PlayerStats.txt): a healing card on yourself before anything else
if (player == 1) && ((heal1 == 1) || (heal2 == 1)) && OwnHealthLow()
	{
	if (heal1 == 1) && UseHeal("heal1", &heal1, hitschool)
	{
		EndRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
	}
	if (heal2 == 1) && UseHeal("heal2", &heal2, hitschool)
	{
		EndRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
	}
	}

;(the healer: Tower Shield on the ally that's low, else on the hitter - Party.ahk PartyShield)
if (BattleRole = "healer") && PartyShield()
{
	EndRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
}

;How it plays its cards (the Settings window: cardlogic, boostmax, use...): hit first - before any boost - when
;the card logic says so (Settings.ahk CardHitFirst); boosts only up to boostmax before a hit it can cast
;(CardBoostOk); kinds switched off aren't played. BoostRun counts the boosts since the last hit
;Turned off (F6) during the round: it's left - nothing more cast, the mouse given back
if (!BotOn)
	{
	DebugLog("  bot off (" HkText("bot") ") - leaving this round")
	RoundLeft := 1
	MouseLetGo()
	MouseLockOff("round")
	TestRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	}
;Where traps go: the boss picked with Alt+1; a party battle's blader or healer - the enemy the hitter goes for (Party.ahk
;PartyTrapTarget); else, in every battle (the user, 2026-10-24: "the enemy with the highest health always"), the enemy
;with the most health - a tie or health not read: the planned hit's target (KillCalc.ahk TrapTarget, only with a trap in
;hand). Which traps: those that fit the planned hit's schools (BoostPick), one a round, as ever
TrapWhere()

;The hit this round's boosts are for - with the game's hand read, the one dealing the most with the boosts in hand and on;
;a blader's or healer's: the hitter's - and the blades and traps that fit its schools, the most that adds first
;(KillCalc.ahk BoostPick; CastBestHit casts that hit first)
BoostPick()

;(a blader or healer: no hit first, no boost limit - boosting is what it's for)
HitsTried := 0
if (!PartySupport()) && CardHitFirst()
	{
	HitsTried := 1
	if CastBestHit()
	{
		EndRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
	}
	}
BoostOk := PartySupport() ? 1 : CardBoostOk()

;Automatic Battle code
;(each school's blade and trap with its own used flags - KillCalc.ahk KeyFlags: BoostPick names them)
if (feint == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&"feint", &feint, &Used1, &Used2, &"resources")
	{
	BoostRun++
	EndRound() ; V1toV2: Goto->FuncCall
	Return ; V1toV2: post-return for Goto
	} else if (convert == 1) && (BossChoosen == 1) && BoostOk && NeedsConvert() && UseConvert(&"convert", &convert, &hitschool)
		{
		;(a boost - boostmax counts it -, once till a hit of yours goes out: NeedsConvert, KillCalc.ahk ConvertUp - the
		;review, 2026-10-26)
		BoostRun++
		EndRound() ; V1toV2: Goto->FuncCall
		Return ; V1toV2: post-return for Goto
		;(a negative aura - an Attenuate: +N% damage taken on the trap rule's enemy for 4 rounds, before the traps and blades;
		;once in 4 rounds an enemy, only one that adds to the planned hit - UseNegAura, KillCalc.ahk NegAuraMem)
		} else if (negaura == 1) && BoostOk && Stat("usetraps") && UseNegAura()
			{
			BoostRun++
			EndRound() ; V1toV2: Goto->FuncCall
			Return ; V1toV2: post-return for Goto
			} else if (trap == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&"trap", &trap, &used%TrapU1%, &used%TrapU2%, &TrapDir)
			{
			BoostRun++
			EndRound() ; V1toV2: Goto->FuncCall
			Return ; V1toV2: post-return for Goto
			} else if (trap2 == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&traptype, &%traptype%, &used%Trap2U1%, &used%Trap2U2%, &"resources")
				{
				BoostRun++
				EndRound() ; V1toV2: Goto->FuncCall
				Return ; V1toV2: post-return for Goto
				} else if (trap3 == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&"trap3", &trap3, &used7, &used8, &"resources")
					{
					BoostRun++
					EndRound() ; V1toV2: Goto->FuncCall
					Return ; V1toV2: post-return for Goto
					} else if (trap4 == 1) && (TrapOn == 1) && BoostOk && Stat("usetraps") && UseTrap(&"trap4", &trap4, &used9, &used10, &"resources")
						{
						BoostRun++
						EndRound() ; V1toV2: Goto->FuncCall
						Return ; V1toV2: post-return for Goto
						} else if (blade == 1) && BoostOk && Stat("useblades") && UseBlade(&"blade", &blade, &used%BladeU1%, &used%BladeU2%, &BladeDir)
							{
							BoostRun++
							EndRound() ; V1toV2: Goto->FuncCall
							Return ; V1toV2: post-return for Goto
							} else if (blade2 == 1) && BoostOk && Stat("useblades") && UseBlade(&bladetype, &%bladetype%, &used%Blade2U1%, &used%Blade2U2%, &"resources")
								{
								BoostRun++
								EndRound() ; V1toV2: Goto->FuncCall
								Return ; V1toV2: post-return for Goto
								} else if (blade3 == 1) && BoostOk && Stat("useblades") && UseBlade(&"blade3", &blade3, &used15, &used16, &"resources")
									{
									BoostRun++
									EndRound() ; V1toV2: Goto->FuncCall
									Return ; V1toV2: post-return for Goto
									}  else if (blade4 == 1) && BoostOk && Stat("useblades") && UseBlade(&"blade4", &blade4, &used17, &used18, &"resources")
										{
										BoostRun++
										EndRound() ; V1toV2: Goto->FuncCall
										Return ; V1toV2: post-return for Goto
										} else if (bubble == 1) && BoostOk && Stat("usebubble") && ClickBubble()
											{
											;(by its picture, else at the game's card's box - ClickBubble; not clicked: on
											;down the chain, not a round with nothing cast)
											BoostRun++
											} else if (aura == 1) && BoostOk && Stat("useaura") && (AuraRounds <= 0)
												{
												if Click(&"aura", &aura, &hitschool)
													{
													AuraRounds := 4
													;(the schools it boosts: its card's in the game's hand, else yours)
													AuraSch := BoostAuraSchools()
													BoostRun++
													}
												} else if (BattleRole = "blader") && PartyShield()
													{
													EndRound() ; V1toV2: Goto->FuncCall
													Return ; V1toV2: post-return for Goto
													} else if (!HitsTried) && CastBestHit()
													{
													EndRound() ; V1toV2: Goto->FuncCall
													Return ; V1toV2: post-return for Goto
													} else if (wand == 1) && Stat("usewand") && !WandWastes() && UseHit(&"wand", &wand, &hitschool)
														{
														BoostRun := 0
														EndRound() ; V1toV2: Goto->FuncCall
														Return ; V1toV2: post-return for Goto
														} else if (tower == 1) && Stat("usetower") && UseOnSelf(&"tower", &tower, &"resources") || AbsorbFiller()
															{
															;(it has to go out, as when defending - CastWentOut; the card didn't go: passed,
															;not left to the round's timer. Not clicked at all - the game's Tower Shield's box
															;not lined up for sure (UseMemAt): on to Reshuffle, else Pass. No Tower Shield: an
															;absorb that costs no pips the same way - AbsorbFiller, 2026-10-26)
															if (!CastWentOut())
																ClickPass()
															} else if (reshuffle == 1) && Stat("usereshuffle")
																{
																;(a party battle's blader or healer: on itself - hammerX/Y is the hitter's
																;plate; its boosts on the hitter are cast again by Party.ahk, not here)
																if (PartySupport())
																	UseOnSelf(&"reshuffle", &reshuffle, &"resources")
																else
																	{
																	UseOnHammer(&"reshuffle", &reshuffle, &"resources")
																	ResetUsed()
																	}
																} else if ClickPass()
																	{
																	EndRound() ; V1toV2: Goto->FuncCall
																	Return ; V1toV2: post-return for Goto
																	}
EndRound()
}
;##############################################
EndRound() { ; V1toV2: Lbl->Func
global
DebugLog("Round done")
;The mouse back where it was when the round began (mousereturn, the Settings window), else off the cards - not
;if you've used the mouse or keys meanwhile (MouseLetGo -1: it's yours)
if (MouseLetGo() = 0)
	CenterMouse()
;(your mouse unlocked - Settings.ahk MouseLockOff)
MouseLockOff("round")

Switch()
	
TestRound() ; V1toV2: Goto->FuncCall
Return ; V1toV2: post-return for Goto
}
;##############################################
mobloop() { ; V1toV2: Lbl->Func
global
if (loopmode == 1)
	{
	Send("{s down}")
	s(1000)
	Send("{s up}")
	;(the backpack full and not sold - held for a dungeon's drops, quick sell failed or waiting: QuickSell.ahk's last look
	;after the battle, by the game's memory. resources\full.png never existed - that search never found anything)
	if (QsStillFull())
		{
		AlertSend("inventory", "backpack full", "The backpack is full and wasn't quick sold - mob-loop farming has stopped (kept from timing out).")
		afk()
		loopmode := 0
		return
		}
	s(5000)
	Send("{w down}")
	s(1000)
	Send("{w up}")
	}
return
}
;##############################################
LoreLoop()
	{ ; V1toV2: Lbl->Func
	;global
	if ((loremode == 1) && (dualmode == 0))
		{
		num := Mod(%battles% + 1, 50)
		if (num == 0)
			{
			UsePotion()
			}	
		log()	
		join()
		s(5000)
		Spam("x")
		s(16000)
		LockMove(&"w")
		s(5000)
		} else if ((loremode == 1) && (dualmode == 1))
			{
			;Joins Battles with same wizard you started the loop in
			;(your mouse locked the whole way - about a minute: Settings.ahk MouseLockOn, 2 minutes before its watchdog)
			MouseLockOn("lore", 120000)
			num := Mod(%battles% + 1, 50)
			if (num == 0)
				{
				UsePotion()
				Switch()
				s(500)
				UsePotion()
				Switch()
				}	
			log()
			switch()
			centermouse()
			log()
			join()
			switch()
			centermouse()
			join()
			switch()
			s(30000)
			Spam("x")
			Switch()
			s(1000)
			Spam("x")
			s(17000)
			LockMove(&"w")
			Switch()
			s(1000)
			LockMove(&"w")
			s(5000)
			switch()
			MouseLockOff("lore")
			return
			} else 
				{
				return
				}
	}
;##############################################
HkDev() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	ModeBox(&devmode, &"Developer", 10, 10, 144, 30)
	}
return
}
;##############################################
HkLore() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	msgResult := MsgBox("Please make sure you're standing next to the lore sigil when activating this mode.`n`nPress Ok to continue.", "AutoFarmer: Lore Mode", 1)
	if (msgResult = "ok")
		{
		ModeBox(&loremode, &"Lore", 10, 10, 140, 30)
		}
	if (msgResult = "cancel")
		{
		return
		}
	if (msgResult = "timeout")
		{
		return
		}
	}
return
}
;##############################################
HkDual() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	msgResult := MsgBox("Please make sure that, when activating this mode two Wizard101 instances are open and that, when `"Alt+Tab`" is pressed it'll switch bewteen them.`n`nPress Ok to continue.", "AutoFarmer: Dual Mode", 1)
	if (msgResult = "ok")
		{
		ModeBox(&dualmode, &"Dual", 10, 10, 120, 30)
		}
	if (msgResult = "cancel")
		{
		return
		}
	}
return
}
;##############################################
HkCommand() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	ModeBox(&commandmode, &"Command", 10, 10, 144, 30)
	}
return
}
;##############################################
HkStats() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	ModeBox(&statsmode, &"Statistic", 10, 10, 140, 30)
	}
return
}
;##############################################
HkResponse() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	ModeBox(&responcemode, &"Responce", 10, 10, 140, 30)
	}
return
}
;##############################################
HkBoss() { ; V1toV2: Lbl->Func
global
if ((on == 1) && (inbattle == 1))
	{
	;(your mouse free for the pick - Settings.ahk MouseLockPause; locked again after if a round still has it)
	MouseLockPause(1)
	NewStaticGui(&"Please Select Boss Location.", 10, 10, 140, 30)
	ErrorLevel := !KeyWait("LButton", "D, 10")
		If (Errorlevel = 0)
			{
			global BossChoosen := 1
			MouseGetPos(&BossX, &bossY)
			UpdateGameRect()
			BossRelX := (BossX - GameLeft) / UiScale, BossRelY := (BossY - GameTop) / UiScale
			;A newly picked boss starts with no traps counted (those on the enemy with the most health too: KillCalc.ahk
			;TrapPut - BossTraps holds one enemy's)
			BossMax := 0
			BossTraps := {}, TrapFoeX := "", TrapFoeY := "", TrapFoeMax := "", TrapFoeN := 0, TrapSlot := 0
			Try myGui.Destroy()
			}
	MouseLockPause(0)
	CenterMouse()
	}
return
}
;##############################################
HkLoop() { ; V1toV2: Lbl->Func
global
if (on == 1)
	{
	ModeBox(&loopmode, &"Loop", 10, 10, 140, 30)
	}
return
}
;##############################################
HkBoost() { ; V1toV2: Lbl->Func
global
if ((on == 1) && (inbattle == 1))
	{
	MouseLockPause(1)
	NewStaticGui(&"Please Select Hammer Location.", 10, 10, 140, 30)
	ErrorLevel := !KeyWait("LButton", "D, 10")
		If (Errorlevel == 0)
			{
			Manual := 1
			MouseGetPos(&ManualX, &ManualY)
			;(its school - the blade and trap kind for it; your own school - the cards looked for - stays yours)
			ManualSchool := BestBadge(ManualX - Px(75), ManualY - Px(75), ManualX + Px(75), ManualY + Px(75), &manualBX, &manualBY, ManualX, ManualY)
			DebugLog(HkText("boost") ": the boosts go to the plate at " ManualX - GameLeft "," ManualY - GameTop " (" (ManualSchool = "" ? "its school not read" : ManualSchool) ") this battle")
			Try myGui.Destroy()
			CenterMouse()
			}
	;(locked again whether or not a plate was picked - if a round still has it)
	MouseLockPause(0)
}
return
}
;##############################################
HkPlayer() { ; V1toV2: Lbl->Func
global
if ((on == 1) && (inbattle == 1))
	{
	MouseLockPause(1)
	NewStaticGui(&"Please Select New Player Location.", 10, 10, 140, 30)
	ErrorLevel := !KeyWait("LButton", "D, 10")
		If (Errorlevel = 0)
			{
			global ManualPlayer := 1
			MouseGetPos(&ManualPlayerX, &ManualPlayerY)
			Try myGui.Destroy()
			}
	MouseLockPause(0)
	CenterMouse()
	}
return
}
;##############################################
GuiClose(*) { ; V1toV2: Lbl->Func
global
Try myGui.Destroy()
return
}
;##############################################
HkDash() { ; V1toV2: Lbl->Func
global
;Windows+2: the dashboard (Dashboard.ahk) - in dev mode, the info box below
if (devmode != 1)
	{
	DashToggle()
	return
	}
if (devmode == 1)
{
HealthInfo := HealthText()
;(the school blade's and trap's flags, the group's - this round's: KillCalc.ahk BoostPick)
DevB1 := used%BladeU2%, DevSB1 := used%BladeU1%, DevB2 := used%Blade2U2%, DevSB2 := used%Blade2U1%
DevT1 := used%TrapU2%, DevPT1 := used%TrapU1%, DevT2 := used%Trap2U2%, DevPT2 := used%Trap2U1%
MsgBox(
( 
"GENERAL:
Window:(X:" GameLeft " Y:" GameTop " " GameW "x" GameH ")
InBattle:(" inbattle ")
Battles:(" battles ")
Round:(" roundnumber ") 
Player:(" player ")
Hammer:(" hitschool " (X:" hammerX " Y:" hitterY ")) 
Boss:(" BossChoosen ":(X:" BossX " Y:" BossY "))
Enemy Health:(" HealthInfo ")
Boosts(" boosts ":" boostlimit ")

CARDS: 
Sharpen:(" sharpen ") 
Potent:(" potent ")
Blade:(" blade ") 
Blade2:(" blade2 ":(" bladetype ")) 
Balanceblade:(" blade3 ")
Bladestorm:(" blade4 ")
Convert(" convert ")
Trap:(" trap ")  
Trap2:(" trap2 ":(" traptype "))
Trap3:(" trap3 ")
Feint:(" feint ") 
Aura:(" aura ") 
Enchant:(" enchant ") 
Active Hits:(" hit4 ":" hit3 ":" hit2 ":" hit1 ") 
Tower:(" tower ")  
Reshuffle:(" reshuffle ")

     USED:
 F(" used2 ")   pF(" used1 ") 
B1(" DevB1 ") sB1(" DevSB1 ") " BladeDir "
B2(" DevB2 ") sB2(" DevSB2 ")
B3(" Used16 ") sB3(" Used15 ")
B4(" Used18 ") sB4(" Used17 ")
T1(" DevT1 ")  pT1(" DevPT1 ") " TrapDir "
T2(" DevT2 ")  pT2(" DevPT2 ")
T3(" Used8 ")  pT3(" Used7 ")
T4(" Used10 ") pT4(" Used9 ")

MODES: 
Developer(" devmode ") Command(" commandmode ") 
Respond(" responsemode ") Dual(" dualmode ")
Lore(" loremode ")"
))
}
return
}
;##############################################
HK1_() { ; V1toV2: HK->Func
global
if (on = 1)
	{
	if (devmode = 1)
		{	
		if (inbattle = 0)
			{
			InstallMouseHook()
			InstallKeybdHook()
			CoordMode("Mouse", "Window")
			leftoffset := (A_ScreenWidth - 800) / 2
			topoffset := (A_ScreenHeight - 600) / 2
			up := 1
			left := 2
			right := 3
			down := 4
			Mousespeedfast := 5 ;Default is 5
			Mousespeedslow := 10 ;Default is 10
			Loading := 5100 ;Default is 5000
			Wait := 325 ;Default is 300
			Delay := 175 ;Default is 150
			Buffer := 10 ;Default is 10
			
			Loop
				{
				BlockInput("SendAndMouse")
				;(your mouse locked - Settings.ahk MouseLockOn; a loop's turn takes about 20 s)
				MouseLockOn("dev", 120000)
				Sleep(Wait)
				Send("x")
				Sleep(Wait)
				Send("x")
				Sleep(Wait)
				MouseMove(625 + leftoffset, 470 + topoffset, Mousespeedfast)
				Click()
				Sleep(Wait)
				MouseMove(615 + leftoffset, 575 + topoffset, Mousespeedfast)
				Click()
				Sleep(Buffer)
				MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedfast)
				BlockInput("SendAndMouse")
				MouseLockRenew()
				Sleep(Loading)
				Loop 600
					{
					direction := Random(1, 4)
					if (direction == up) 
					{
					Send("w")
					}
					if (direction == left) 
					{
					Send("a")
					} 
					if (direction == right) 
					{
					Send("d")
					}
					if (direction == down) 
					{
					 Send("s")
					 }
					Sleep(Buffer)
					}
				Sleep(%Loading% - 1500a)
				MouseMove(610 + leftoffset, 575 + topoffset, Mousespeedfast)
				Sleep(Delay)
				Click()
				Sleep(Delay)
				MouseMove(170 + leftoffset, 470 + topoffset, Mousespeedfast)
				Click()
				Sleep(Delay)
				MouseMove(615 + leftoffset, 575 + topoffset, Mousespeedfast)
				Click()
				Sleep(Wait)
				MouseMove(635 + leftoffset, 540 + topoffset, Mousespeedfast)
				Click()
				Sleep(Delay)
				MouseMove(180 + leftoffset, 570 + topoffset, Mousespeedfast)
				Click()
				MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedslow)
				Sleep(Loading)
				BlockInput("Off")
				MouseLockOff("dev")
				}
			}
		}
	}
}
;##############################################
HK2_() { ; V1toV2: HK->Func
global
if (on = 1)
	{
	if (devmode = 1)
		{
		Loop
			{
			Click()
			}
		}
	}
return
}
;##############################################
HkQuit() { ; V1toV2: Lbl->Func
global
ExitApp()
}
;##############################################
HkRestart2() { ; V1toV2: Lbl->Func
global
BotRestart()
return
}
