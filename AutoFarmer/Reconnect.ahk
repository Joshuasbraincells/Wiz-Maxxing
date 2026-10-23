; Reconnect.ahk - gets Wizard101 back online by itself after a disconnect. AHK v1.1, functions only,
; #Included by Autofarmer.ahk, whose main loop calls ReconnectCheck() on every pass.
;
; How it knows: the game writes what it's doing to Bin\WizardClient.log as it happens. A disconnect is a
; "DisplayMessageBox(" line there, e.g. "You have been disconnected due to inactivity." (key
; GUI_ConnectionAFK - about 15 minutes with no input outside battle) or "Connection Lost!"
; (GUI_ConnectionLost). The box the game draws for it has RECONNECT and QUIT buttons.
;
; What it does:
;  1. A disconnect box is up: finds RECONNECT on screen (OCR, word by word, so never QUIT) and clicks
;     it. The game logs back in with the launcher's session - no password - and puts you back where
;     you were in about 5 s. It first clicks without bringing the game to the front; if the game
;     ignores that, it brings the game up for a moment, clicks, and gives focus back.
;  2. Still on the character select screen 6 s after logging back in: brings the game to the front
;     and clicks Play (that screen ignores background clicks), then gives focus back.
;  3. The game closed (a crash, or Quit): asks for 60 s whether to start it again (yes if nobody
;     answers), then starts it and logs in with the login saved with "Set Wizard101 login..." in the
;     tray menu. That's kept in Windows Credential Manager (encrypted, as "Wizard101Bot"), never in a
;     file, never written to debug.log, and only typed into the game's own login box once that box can
;     be seen - and Enter is only pressed once the username can be read back in it.
;  4. "Client is out of date" (a patch came out during maintenance): closes the game and starts the
;     launcher, fills in the login there so it can patch, and the launcher starts the game.
;  A failed try waits longer before the next: 30 s, 1, 2, 4 minutes, then every 10 minutes (servers
;  down for maintenance: 10 minutes straight away). After 6 failed RECONNECTs it restarts the game
;  (step 3). A login the game turns down is never typed again until it's saved again.
;
; Needs from the including script: the super-globals GameExe, GameClass, GameLeft, GameTop, GameW, GameH
; (kept up to date by its UpdateGameRect()), UiScale (optional), OcrRect() (Ocr.ahk), and optionally
; DebugLog(), UpdateGameRect() and ReleaseKeys(). Locals must not share a name with any super-global of
; the including script (AHK names are case-insensitive).

global RcOn, RcLog, RcPos, RcPid, RcExe, RcState, RcStateAt, RcMsg, RcTries, RcNext, RcLookAt
global RcCheckAt, RcProcAt, RcClickBg, RcLastBg, RcClickAt, RcCharAt, RcPlayTries, RcNoRelaunch
global RcLoginBad, RcNote, RcScanning, RcTyped, RcCredTarget, RcHead, RcPeekAt, RcPeeks, RcFrontOk, RcFindInfo

;Call once at start. Picks up a disconnect box that's already showing
ReconnectInit()
	{
	RcCredTarget := "Wizard101Bot"
	RcOn := 1, RcState := "", RcStateAt := A_TickCount, RcTries := 0, RcNext := 0, RcLookAt := 0
	RcCheckAt := 0, RcProcAt := 0, RcClickBg := -1, RcLastBg := 0, RcClickAt := 0, RcCharAt := 0
	RcPlayTries := 0, RcNoRelaunch := 0, RcLoginBad := 0, RcNote := 0, RcTyped := 0, RcMsg := ""
	RcHead := "", RcPeekAt := 0, RcPeeks := 0
	Process, Exist, %GameExe%
	RcPid := ErrorLevel
	RcSetClient(RcFindClient())
	;Replay the end of the game's log (quietly) to see where things stand
	RcPos := 0
	FileGetSize, logSize, %RcLog%
	if (logSize > 131072)
		RcPos := logSize - 131072
	RcScanning := 1
	RcReadLog()
	RcScanning := 0
	if ((RcState = "box" || RcState = "outdated") && RcPid)
		{
		RcTries := 0, RcNext := 0, RcStateAt := A_TickCount
		RcLogMsg("a disconnect box is already up: """ RcMsg """")
		}
	;Started (or restarted) in the middle of getting back in after a disconnect: carry on from there
	else if ((RcState = "select" || RcState = "enter") && RcPid)
		{
		RcTries := 0, RcNext := 0, RcStateAt := A_TickCount
		RcLogMsg("the game is logging back in after a disconnect (" (RcState = "select" ? "character select" : "going into the world") ")")
		}
	else
		RcState := "", RcTries := 0
	Menu, Tray, Check, Auto-reconnect on/off
	return true
	}

;Call on every pass of the main loop. True while it's getting back online (the caller then skips
;battles and walking)
ReconnectCheck()
	{
	if (!RcOn)
		return false
	nowMs := A_TickCount
	;Is the game still running? A new game process starts a new log, from the top
	if (nowMs - RcProcAt >= 2000)
		{
		RcProcAt := nowMs
		Process, Exist, %GameExe%
		gamePid := ErrorLevel
		if (gamePid && gamePid != RcPid)
			{
			;(its new log is told apart from the old one by its first line: see RcReadLog)
			RcPid := gamePid, RcNoRelaunch := 0
			RcSetClient(RcFindClient())
			if (RcState = "gone" || RcState = "stopped")
				RcSet("", "the game is running again")
			}
		else if (!gamePid && RcPid)
			{
			RcPid := 0
			if (RcState != "patch")
				{
				;Closed by itself (not during one of our own restarts): count tries afresh
				if (!RcTyped && RcState != "start")
					RcTries := 0, RcNext := 0
				RcSet("gone", "the game has closed")
				}
			}
		}
	if (nowMs - RcCheckAt >= 1000)
		{
		RcCheckAt := nowMs
		RcReadLog()
		}
	if (RcState = "" || RcState = "stopped")
		return false
	return RcStep()
	}

;One step of getting back online, by state. True while it's busy
RcStep()
	{
	nowMs := A_TickCount
	if (RcState = "box")
		{
		if (nowMs < RcNext)
			{
			RcStatus("disconnected - trying again in " Ceil((RcNext - nowMs) / 1000) " s")
			return true
			}
		;The first minute: look every second, and the bot waits. After that, if it still can't see the
		;button (the screen asleep, a screensaver, the game covered...): let the bot carry on meanwhile
		;and look again every 30 s - the game only says "disconnected" once, so never give up on it
		early := nowMs - Max(RcStateAt, RcNext) <= 60000
		if (nowMs - RcLookAt < (early ? 1000 : 30000))
			return early
		RcLookAt := nowMs
		;RECONNECT keeps failing: maybe the session ran out - start the game afresh (needs the login)
		if (RcTries >= 6 && !RcLoginBad && RcHaveLogin())
			{
			RcTries := 0
			RcCloseGame()
			RcSet("gone", "RECONNECT didn't work 6 times - restarting the game")
			return true
			}
		;The game in view but not in front: click it in the background (unless it has ignored that
		;before). Otherwise bring it to the front to look and click: when it can't be seen (another
		;window over it), every 20 s in the first minute, after that every 2 minutes and only once
		;you've left the computer alone for a minute
		inFront := RcGameActive()
		btn := RcFindWord("i)^reconn?ect$", "box", "RECONNECT")
		if (IsObject(btn) && !inFront && RcClickBg != 0)
			{
			RcClick(btn.x, btn.y, "RECONNECT")
			RcTries += 1, RcPlayTries := 0
			RcSet("wait", "try " RcTries ": clicked RECONNECT - waiting to log back in")
			return true
			}
		if (IsObject(btn) || inFront || (early ? nowMs - RcPeekAt > 20000 : nowMs - RcPeekAt > 120000 && A_TimeIdlePhysical > 60000))
			{
			RcPeekAt := nowMs
			if (RcFrontClick("i)^reconn?ect$", "box", "RECONNECT", "RECONNECT"))
				{
				RcTries += 1, RcPlayTries := 0
				RcSet("wait", "try " RcTries ": clicked RECONNECT - waiting to log back in")
				return true
				}
			}
		if (!RcNote)
			RcNote := 1, RcLogMsg("can't see the RECONNECT button yet - still looking (" RcFindInfo ")")
		if (!early && RcNote = 1)
			RcNote := 2, RcLogMsg("still can't see the RECONNECT button (" RcFindInfo ") - carrying on meanwhile, looking again every 30 s")
		return early
		}
	if (RcState = "wait")
		{
		;Nothing a while after a background click and RECONNECT still showing: the game ignores
		;those, so bring it to the front and click (and from now on always that way)
		if (RcLastBg && nowMs - RcClickAt > 6000)
			{
			RcLastBg := 0
			if (IsObject(RcFindWord("i)^reconn?ect$", "box", "RECONNECT")))
				{
				RcClickBg := 0
				RcLogMsg("the game ignored the background click - bringing it to the front to click")
				RcFrontClick("i)^reconn?ect$", "box", "RECONNECT", "RECONNECT")
				}
			}
		if (nowMs - RcStateAt > 60000)
			RcFail("no login a minute after clicking RECONNECT")
		return true
		}
	if (RcState = "select")
		{
		;Character select: if the game doesn't carry on by itself after a RECONNECT, click Play - with
		;the game in front (that screen ignores background clicks, even though the RECONNECT box
		;takes them; seen 2026-10-16)
		if (RcCharAt && nowMs - RcCharAt > 6000 && nowMs - RcClickAt > 8000 && RcPlayTries < 3)
			{
			RcPlayTries += 1
			RcFrontClick("i)^play!?$", "low", "Play on the character select screen", "PLAY")
			}
		if (nowMs - RcStateAt > 90000)
			RcFail("still not in the game 90 s after logging in")
		return true
		}
	if (RcState = "enter")
		{
		if (nowMs - RcStateAt > 60000)
			RcFail("the character didn't get into the world within a minute")
		return true
		}
	if (RcState = "gone")
		return RcGone()
	if (RcState = "start")
		return RcStartStep()
	if (RcState = "login")
		return RcLoginStep()
	if (RcState = "outdated")
		return RcOutdated()
	if (RcState = "patch")
		return RcPatchStep()
	return false
	}

;Reads what the game has written to its log since last time, a whole line at a time
RcReadLog()
	{
	logFile := FileOpen(RcLog, "r", "CP0")
	if (!IsObject(logFile))
		return
	logSize := logFile.Length
	;Which log this is: the game starts a new one each time it starts, and its first line (a time
	;stamp) changes - read a new one from the top, even if it's already longer than the old one was
	logHead := logFile.Read(17)
	if (logHead != RcHead)
		{
		if (RcHead != "")
			RcPos := 0
		RcHead := logHead
		}
	if (logSize < RcPos)
		RcPos := 0
	if (logSize - RcPos > 1048576)
		RcPos := logSize - 1048576
	if (logSize <= RcPos)
		{
		logFile.Close()
		return
		}
	logFile.Pos := RcPos
	chunk := logFile.Read(logSize - RcPos)
	logFile.Close()
	;A line still being written is read next time
	lastNl := InStr(chunk, "`n", false, 0)
	if (!lastNl)
		return
	chunk := SubStr(chunk, 1, lastNl)
	RcPos += StrLen(chunk)
	Loop, Parse, chunk, `n, `r
		RcLogLine(A_LoopField)
	}

;What one line of the game's log means for getting back online
RcLogLine(logLine)
	{
	if (InStr(logLine, "DisplayMessageBox("))
		{
		;(the msg string key can be empty - e.g. a Crown Shop error, keyed by its title: GUI_CrownShopError)
		RegExMatch(logLine, "msg = (.*?), title = (.*?), msg string key = (\w*)(?:, title string key = (\w*))?", box)
		boxMsg := box1, boxKey := (box3 != "") ? box3 : box4
		if (boxMsg = "")
			boxMsg := logLine
		if (RegExMatch(boxKey, "i)OutOfDate") || RegExMatch(boxMsg, "i)out of date"))
			{
			RcMsg := boxMsg
			RcSet("outdated", "the game says """ boxMsg """ - it needs patching")
			return
			}
		;Kicked because the account logged in somewhere else, or by an admin: don't fight that
		if (RegExMatch(boxKey, "i)ForceDisconnect|CSRDisconnect|Ban|Suspend")
			|| RegExMatch(boxMsg, "i)someone else has logged in|logged in (from|on|at) another|by an Administrator|suspended|banned"))
			{
			RcMsg := boxMsg
			RcSet("stopped", "not reconnecting: """ boxMsg """ (" boxKey ")")
			if (!RcScanning)
				TrayTip, Wizard101 bot, % "Not reconnecting: " boxMsg, 10, 2
			return
			}
		;While typing the login in: whatever the game says is about that
		if (RcState = "login")
			{
			if (RegExMatch(boxMsg, "i)invalid|password|username|account"))
				{
				RcLoginBad := 1
				RcSet("stopped", "the game turned the saved login down (""" boxMsg """) - it won't be typed again until it's saved again (tray menu: Set Wizard101 login...)")
				TrayTip, Wizard101 bot, The game turned the saved login down. Save it again with "Set Wizard101 login..." in the tray menu., 10, 2
				}
			else
				RcFail("logging in: the game says """ boxMsg """")
			return
			}
		if (!RegExMatch(boxKey, "i)Connect|Disconnect|Shutdown|Maintenance|FailedTo|Attach|ZoneFull|NoZones|Unavailable|EnterWorld|Technical|LoginError")
			&& !RegExMatch(boxMsg, "i)disconnect|connection|connect to|maintenance|failed to (load|enter)|try again later|unable to (connect|reach|contact|log ?in|enter|join)"))
			{
			RcLogMsg("(a game message, not a disconnect: """ boxMsg """)")
			return
			}
		;A disconnect. Straight after one of our tries: that try failed, so wait longer this time
		retry := (RcState = "wait" || RcState = "select" || RcState = "enter")
		if (!retry && RcState != "box")
			RcTries := 0
		RcMsg := boxMsg
		RcNext := RegExMatch(boxKey "|" boxMsg, "i)Shutdown|maintenance|try again later") ? A_TickCount + 600000
			: retry ? A_TickCount + RcBackoff() : 0
		RcSet("box", "disconnected: """ boxMsg """ (" boxKey ")")
		if (!RcScanning && !retry)
			TrayTip, Wizard101 bot, % "Disconnected: " boxMsg "`nReconnecting...", 5, 2
		return
		}
	if (InStr(logLine, "LOGIN RESPONSE: Error=0"))
		{
		;Only after our own tries (not when you log in yourself)
		if (RegExMatch(RcState, "^(box|wait|start|login|patch)$"))
			{
			if (RcLastBg && RcState = "wait")
				RcClickBg := 1
			RcLoginBad := 0, RcCharAt := 0
			RcSet("select", "logged back in")
			}
		return
		}
	if (InStr(logLine, "WizardCharacterSelect: The scene has been loaded successfully"))
		{
		RcCharAt := A_TickCount
		return
		}
	if (InStr(logLine, "MSG_CharacterSelected: Error=0"))
		{
		RcCharAt := 0
		if (RcState = "select")
			RcSet("enter", "character chosen - going into the world")
		return
		}
	if (InStr(logLine, "ConnectComplete destination Zone="))
		{
		if (RcState != "")
			{
			RegExMatch(logLine, "Zone=(\S+)", zone)
			RcSet("", "back in the game (" zone1 ")")
			RcTries := 0, RcNext := 0, RcTyped := 0
			if (!RcScanning)
				TrayTip, Wizard101 bot, Back in the game., 3, 1
			}
		return
		}
	}

;A try didn't work: back to looking for RECONNECT, after a longer wait each time
RcFail(why)
	{
	RcLogMsg(why)
	;On the login box or the character select screen there's no RECONNECT: start the game afresh
	if (RegExMatch(RcState, "^(start|login|select|enter)$"))
		{
		if (!RcLoginBad && RcHaveLogin())
			{
			RcTries := RcTyped ? RcTries + 1 : 1
			RcCloseGame()
			RcNext := A_TickCount + RcBackoff()
			RcSet("gone", "closing the game to start it again")
			return
			}
		RcSet("stopped", "can't get back into the game by itself - please log in yourself")
		if (!RcScanning)
			TrayTip, Wizard101 bot, Couldn't get back into the game by itself - please log in yourself., 10, 2
		return
		}
	RcNext := A_TickCount + RcBackoff()
	RcSet("box", "")
	}

;How long to wait before the next try: 30 s, 1, 2, 4 minutes, then 10 minutes
RcBackoff()
	{
	return RcTries <= 1 ? 30000 : RcTries = 2 ? 60000 : RcTries = 3 ? 120000 : RcTries = 4 ? 240000 : 600000
	}

;The game has closed: start it again (asking first, yes if nobody answers in 60 s) and log in
RcGone()
	{
	if (RcNoRelaunch || RcLoginBad)
		return false
	if (A_TickCount < RcNext)
		return true
	if (!RcHaveLogin())
		{
		if (!RcNote)
			{
			RcNote := 1
			RcLogMsg("the game has closed and there's no saved login (tray menu: Set Wizard101 login...), so it can't start it again by itself")
			TrayTip, Wizard101 bot, Wizard101 has closed. Save your login with "Set Wizard101 login..." in the tray menu and the bot can start it again by itself., 10, 2
			if (IsFunc("AlertSend"))
				Func("AlertSend").Call("reconnect", "Wizard101 has closed", "There's no saved login to start it again with (tray menu: Set Wizard101 login...).")
			}
		return false
		}
	if (RcTries >= 4)
		{
		RcSet("stopped", "couldn't get the game started and logged in after 4 tries - start it yourself")
		TrayTip, Wizard101 bot, Couldn't restart Wizard101 by itself - please start it yourself., 10, 2
		return false
		}
	if (IsFunc("ReleaseKeys"))
		Func("ReleaseKeys").Call()
	MsgBox, 4145, Wizard101 bot, % "Wizard101 has closed.`n`nStart it again and log back in?`n(It will in 60 seconds if nobody answers.)", 60
	IfMsgBox, Cancel
		{
		RcNoRelaunch := 1
		RcLogMsg("the game has closed - you chose not to start it again")
		return false
		}
	;Things may have changed while the question was up: the game started some other way, or
	;auto-reconnect switched off in the tray menu
	Process, Exist, %GameExe%
	if (ErrorLevel || !RcOn || RcState != "gone")
		return false
	return RcLaunchClient()
	}

;Starts the game itself (not the launcher), which then shows its own login box
RcLaunchClient()
	{
	SplitPath, RcExe,, binDir
	loginHost := "login.us.wizard101.com", loginPort := 12000
	FileRead, patchCfg, %binDir%\PatchConfig.xml
	if (RegExMatch(patchCfg, "CommandLine args=""-L\s+(\S+)\s+(\d+)", cfg))
		loginHost := cfg1, loginPort := cfg2
	Run, "%RcExe%" -L %loginHost% %loginPort%, %binDir%, UseErrorLevel, newPid
	if (ErrorLevel)
		{
		RcNext := A_TickCount + 600000
		RcLogMsg("couldn't start " RcExe " - trying again in 10 minutes")
		return true
		}
	RcPid := newPid, RcTyped := 0
	RcSet("start", "started the game - waiting for its login box")
	return true
	}

;Waiting for the game's login box (Account / Password), then types the saved login into it
RcStartStep()
	{
	nowMs := A_TickCount
	if (nowMs - RcStateAt > 180000)
		{
		RcCloseGame()
		RcNext := nowMs + RcBackoff(), RcTries += 1
		RcSet("gone", "no login box 3 minutes after starting the game - closing it and trying again later")
		return true
		}
	if (nowMs - RcStateAt < 5000 || nowMs - RcLookAt < 1500)
		return true
	RcLookAt := nowMs
	WinGet, gameWin, ID, ahk_class %GameClass% ahk_exe %GameExe%
	if (!gameWin)
		return true
	if (IsFunc("UpdateGameRect"))
		Func("UpdateGameRect").Call()
	if (!IsObject(RcFindWord("i)^password:?$", "all")))
		return true
	if (!RcCredLoad(loginUser, loginPass))
		{
		RcSet("stopped", "the saved login is gone - save it again (tray menu: Set Wizard101 login...)")
		return false
		}
	;A fresh start has an empty login box: if the username is already there, don't guess where the
	;typing would go
	if (RcSeeLine(loginUser, gameWin))
		{
		loginUser := "", loginPass := ""
		return RcLoginHelp("the login box already has the username in it")
		}
	;Typed straight to the game window as characters (it doesn't need focus), checking each step.
	;1. The username into the Account box (cleared first), then read it back
	RcChars(gameWin, "", 40)
	RcChars(gameWin, loginUser)
	Sleep, 400
	if (!RcSeeLine(loginUser, gameWin))
		{
		RcChars(gameWin, "", 40)
		loginUser := "", loginPass := ""
		return RcLoginHelp("couldn't see the username in the login box after typing it")
		}
	;2. Tab to the Password box: a test letter typed now mustn't show up in the Account box
	RcChars(gameWin, Chr(9))
	RcChars(gameWin, "x")
	Sleep, 400
	if (!RcSeeLine(loginUser, gameWin))
		{
		RcChars(gameWin, "", 40)
		loginUser := "", loginPass := ""
		return RcLoginHelp("Tab didn't move on to the Password box")
		}
	;3. The password (the test letter cleared first), and the Account box still just the username
	RcChars(gameWin, "", 40)
	RcChars(gameWin, loginPass)
	loginPass := ""
	Sleep, 300
	if (!RcSeeLine(loginUser, gameWin))
		{
		RcChars(gameWin, "", 40)
		loginUser := ""
		return RcLoginHelp("the login box didn't look right after typing the password")
		}
	loginUser := ""
	RcChars(gameWin, Chr(13))
	RcTyped := 1
	RcSet("login", "typed the saved login into the game's login box")
	return true
	}

;Typing the login in didn't work out: stop and leave it to you
RcLoginHelp(why)
	{
	RcSet("stopped", why " - didn't press Enter, log in yourself")
	TrayTip, Wizard101 bot, Couldn't fill in the game's login box - please log in yourself., 10, 2
	return false
	}

;Is there a line of text on the game reading just that (or "Account: " and that), e.g. the username
;in the login box?
RcSeeLine(text, gameWin)
	{
	for each, zoom in [1, 2]
		{
		OcrRect(GameLeft, GameTop, GameW, GameH, "en", zoom, ocrLines)
		if (ErrorLevel || !IsObject(ocrLines))
			continue
		for i, ocrLine in ocrLines
			if (RegExMatch(Trim(ocrLine.text), "i)^(account:?\s*)?\Q" text "\E$")
				&& RcOnGame(ocrLine.x + ocrLine.w // 2, ocrLine.y + ocrLine.h // 2, gameWin))
				return true
		}
	return false
	}
;Logging in: the log's LOGIN RESPONSE moves on to "select"; "Invalid..." stops for good
RcLoginStep()
	{
	nowMs := A_TickCount
	if (nowMs - RcStateAt > 4000 && nowMs - RcLookAt > 2000)
		{
		RcLookAt := nowMs
		if (IsObject(RcFindWord("i)^invalid$", "all")))
			{
			RcLoginBad := 1
			RcSet("stopped", "the game says the saved login is invalid - it won't be typed again until it's saved again")
			TrayTip, Wizard101 bot, The game turned the saved login down. Save it again with "Set Wizard101 login..." in the tray menu., 10, 2
			return false
			}
		}
	if (nowMs - RcStateAt > 60000)
		{
		RcTries += 1
		RcCloseGame()
		RcNext := nowMs + RcBackoff()
		RcSet("gone", "no answer from the login server within a minute - closing the game and trying again later")
		}
	return true
	}

;"Client is out of date": close the game and let the launcher patch it (it needs the login too)
RcOutdated()
	{
	if (RcLoginBad || !RcHaveLogin())
		{
		RcSet("stopped", "the game needs patching and there's no usable saved login - start Wizard101 yourself")
		TrayTip, Wizard101 bot, Wizard101 needs patching - start it yourself (or save your login in the tray menu)., 10, 2
		return false
		}
	RcCloseGame()
	SplitPath, RcExe,, binDir
	SplitPath, binDir,, gameRoot
	Run, "%gameRoot%\Wizard101.exe", %gameRoot%, UseErrorLevel
	if (ErrorLevel)
		{
		RcSet("stopped", "couldn't start the launcher (" gameRoot "\Wizard101.exe) - start Wizard101 yourself")
		return false
		}
	RcTyped := 0
	RcSet("patch", "started the launcher to patch the game")
	return true
	}

;The launcher: fill in the login, press PLAY!, then wait while it patches and starts the game (the
;process check notices the new game, and the log takes it from there)
RcPatchStep()
	{
	nowMs := A_TickCount
	if (RcTyped)
		{
		if (RcPid)
			RcSet("select", "the launcher started the game")
		else if (nowMs - RcStateAt > 1200000)
			RcSet("stopped", "the launcher hasn't started the game after 20 minutes - check it yourself")
		return true
		}
	if (nowMs - RcLookAt < 2000)
		return true
	RcLookAt := nowMs
	WinGet, launchWin, ID, ahk_exe WizardLauncher.exe
	if (!launchWin)
		{
		if (nowMs - RcStateAt > 180000)
			RcSet("stopped", "the launcher didn't open - start Wizard101 yourself")
		return true
		}
	userBox := "", passBox := "", playBtn := "", seen := ""
	WinGet, ctlList, ControlList, ahk_id %launchWin%
	Loop, Parse, ctlList, `n
		{
		ControlGet, ctlVis, Visible,, %A_LoopField%, ahk_id %launchWin%
		ControlGet, ctlStyle, Style,, %A_LoopField%, ahk_id %launchWin%
		if (!ctlVis)
			continue
		if (InStr(A_LoopField, "Edit") = 1)
			{
			if (ctlStyle & 0x20)
				passBox := A_LoopField
			else if (userBox = "")
				userBox := A_LoopField
			continue
			}
		ControlGetText, ctlText, %A_LoopField%, ahk_id %launchWin%
		if (RegExMatch(ctlText, "i)^\s*(play!?|log\s*in)\s*$"))
			playBtn := A_LoopField
		seen .= A_LoopField " "
		}
	if (passBox = "")
		{
		;Its login boxes show once the page has loaded
		if (nowMs - RcStateAt > 120000)
			{
			RcLogMsg("launcher controls seen: " seen)
			RcSet("stopped", "the launcher is open but its password box wasn't found - log in there yourself")
			TrayTip, Wizard101 bot, The launcher needs you: log in there yourself., 10, 2
			}
		return true
		}
	if (!RcCredLoad(loginUser, loginPass))
		{
		RcSet("stopped", "the saved login is gone - log in to the launcher yourself")
		return false
		}
	if (userBox != "")
		{
		ControlGetText, curUser, %userBox%, ahk_id %launchWin%
		if (curUser != loginUser)
			ControlSetText, %userBox%, %loginUser%, ahk_id %launchWin%
		}
	ControlSetText, %passBox%, %loginPass%, ahk_id %launchWin%
	loginUser := "", loginPass := ""
	Sleep, 300
	if (playBtn != "")
		ControlClick, %playBtn%, ahk_id %launchWin%,,,, NA
	else
		ControlSend, %passBox%, {Enter}, ahk_id %launchWin%
	RcTyped := 1, RcStateAt := A_TickCount
	RcLogMsg("launcher: filled in the login and pressed " (playBtn = "" ? "Enter" : playBtn) " - it patches, then starts the game")
	return true
	}

;Closes the game (and makes sure it's gone)
RcCloseGame()
	{
	WinClose, ahk_class %GameClass% ahk_exe %GameExe%
	Process, WaitClose, %GameExe%, 15
	if (ErrorLevel)
		Process, Close, %GameExe%
	RcPid := 0
	}

;Clicks at a screen point in the game, leaving it in the background: mouse messages straight to its
;window (some games ignore those - then RcFrontClick)
RcClick(px, py, what)
	{
	WinGet, gameWin, ID, ahk_class %GameClass% ahk_exe %GameExe%
	if (!gameWin)
		return false
	RcClickAt := A_TickCount
	cx := px - GameLeft, cy := py - GameTop
	pos := (cy << 16) | (cx & 0xFFFF)
	PostMessage, 0x200, 0, pos,, ahk_id %gameWin%
	Sleep, 50
	PostMessage, 0x201, 1, pos,, ahk_id %gameWin%
	Sleep, 80
	PostMessage, 0x202, 0, pos,, ahk_id %gameWin%
	RcLastBg := 1
	RcLogMsg("clicked " what " at " cx "," cy " (game left in the background)")
	return true
	}

;Brings the game to the front (if it isn't), finds the word there again and clicks it with the real
;mouse - your mouse movements held off meanwhile - then gives the focus and the mouse back. False if
;the game couldn't be brought up or the word isn't there
RcFrontClick(pattern, area, what, fuzzy := "")
	{
	WinGet, gameWin, ID, ahk_class %GameClass% ahk_exe %GameExe%
	if (!gameWin)
		return false
	RcClickAt := A_TickCount, RcLastBg := 0, RcFrontOk := 0
	WinGet, prevWin, ID, A
	MouseGetPos, mouseX, mouseY
	if (prevWin != gameWin)
		{
		WinActivate, ahk_id %gameWin%
		WinWaitActive, ahk_id %gameWin%,, 2
		;Windows sometimes won't hand over the focus (e.g. to Windows' own hidden input window): a
		;real click on the game's title bar always brings it up, and does nothing in the game
		if (ErrorLevel)
			{
			WinGetPos, winX, winY, winW,, ahk_id %gameWin%
			barX := winX + winW // 2, barY := winY + (GameTop - winY) // 2
			if (GameTop - winY >= 12 && RcOnGame(barX, barY, gameWin))
				{
				BlockInput, MouseMove
				MouseMove, %barX%, %barY%, 0
				Click
				BlockInput, MouseMoveOff
				WinWaitActive, ahk_id %gameWin%,, 2
				}
			}
		if (ErrorLevel)
			{
			MouseMove, %mouseX%, %mouseY%, 0
			RcLogMsg("couldn't bring the game to the front to click " what)
			return false
			}
		Sleep, 700
		if (IsFunc("UpdateGameRect"))
			Func("UpdateGameRect").Call()
		}
	RcFrontOk := 1
	btn := RcFindWord(pattern, area, fuzzy)
	if (IsObject(btn))
		{
		BlockInput, MouseMove
		MouseMove, % btn.x, % btn.y, 0
		Sleep, 150
		Click
		Sleep, 150
		BlockInput, MouseMoveOff
		}
	;(the focus back to your window - not when you've left the PC, nothing touched for 5 minutes: the game stays in front,
	;else the bot can't walk and the game logs out for inactivity again)
	if (prevWin && prevWin != gameWin && A_TimeIdlePhysical < 300000)
		{
		Sleep, 200
		MouseMove, %mouseX%, %mouseY%, 0
		WinActivate, ahk_id %prevWin%
		}
	if (IsObject(btn))
		RcLogMsg("clicked " what " at " btn.x - GameLeft "," btn.y - GameTop (prevWin != gameWin ? " (brought the game to the front for it)" : ""))
	return IsObject(btn)
	}

RcGameActive()
	{
	return WinActive("ahk_class " GameClass " ahk_exe " GameExe)
	}

;Is that screen point on the game window itself (not on another window over it)?
RcOnGame(px, py, gameWin)
	{
	hitWin := DllCall("WindowFromPoint", "Int64", (py << 32) | (px & 0xFFFFFFFF), "Ptr")
	return hitWin && DllCall("GetAncestor", "Ptr", hitWin, "UInt", 2, "Ptr") = gameWin
	}

;Screen {x, y, text} of the middle of the first word on screen matching pattern, read by OCR in an
;area of the game: "box" (the middle, where the disconnect box is), "low" (the bottom half) or "all".
;With fuzzy (e.g. "RECONNECT"), a word OCR got slightly wrong counts too - a letter or two off, 0 for
;O and the like, or split in two - but never QUIT
RcFindWord(pattern, area, fuzzy := "")
	{
	uiS := (UiScale > 0) ? UiScale : 1
	midX := GameLeft + GameW // 2, midY := GameTop + GameH // 2
	if (area = "box")
		ax := midX - Round(450 * uiS), ay := midY - Round(220 * uiS), aw := Round(900 * uiS), ah := Round(440 * uiS)
	else if (area = "low")
		ax := GameLeft, ay := midY, aw := GameW, ah := GameH - GameH // 2
	else
		ax := GameLeft, ay := GameTop, aw := GameW, ah := GameH
	;Keep it inside the game
	if (ax < GameLeft)
		aw -= GameLeft - ax, ax := GameLeft
	if (ay < GameTop)
		ah -= GameTop - ay, ay := GameTop
	aw := (ax + aw > GameLeft + GameW) ? GameLeft + GameW - ax : aw
	ah := (ay + ah > GameTop + GameH) ? GameTop + GameH - ay : ah
	if (aw < 20 || ah < 20)
		return ""
	;Only words on the game itself: OCR reads the screen, and another window over the game could show
	;the same word
	WinGet, gameWin, ID, ahk_class %GameClass% ahk_exe %GameExe%
	if (!gameWin)
		return ""
	;For the log if it isn't found: how many words it read, and what window is over the middle
	hitWin := DllCall("GetAncestor", "Ptr", DllCall("WindowFromPoint", "Int64", (midY << 32) | (midX & 0xFFFFFFFF), "Ptr"), "UInt", 2, "Ptr")
	WinGet, hitExe, ProcessName, ahk_id %hitWin%
	WinGetClass, hitClass, ahk_id %hitWin%
	wordCount := 0, wordsSeen := ""
	for each, zoom in [1, 2]
		{
		OcrRect(ax, ay, aw, ah, "en", zoom, ocrLines)
		if (ErrorLevel || !IsObject(ocrLines))
			continue
		for i, ocrLine in ocrLines
			for j, ocrWord in ocrLine.words
				{
				wordCount += 1
				if (zoom = 1 && wordCount <= 30)
					wordsSeen .= (wordsSeen = "" ? "" : " ") ocrWord.text
				wx := ocrWord.x + ocrWord.w // 2, wy := ocrWord.y + ocrWord.h // 2
				found := RegExMatch(Trim(ocrWord.text), pattern) || RcLooksLike(ocrWord.text, fuzzy)
				;Split in two ("RECON NECT"): both halves together
				if (!found && fuzzy != "" && j < ocrLine.words.Length())
					{
					nextWord := ocrLine.words[j + 1]
					if (RcLooksLike(ocrWord.text nextWord.text, fuzzy))
						found := true, wx := (ocrWord.x + nextWord.x + nextWord.w) // 2
					}
				if (found && RcOnGame(wx, wy, gameWin))
					return {x: wx, y: wy, text: ocrWord.text}
				}
		}
	RcFindInfo := wordCount " words read there (" SubStr(wordsSeen, 1, 200) "), over the middle: " (hitWin = gameWin ? "the game" : (hitClass = "" ? "an unknown window" : hitClass) (hitExe = "" ? "" : " (" hitExe ")"))
	return ""
	}

;Is an OCR'd word close enough to want (a word in capitals)? Letters only, digits OCR often swaps in
;for letters turned back, then at most 1 letter off (2 for words of 7 or more). Never QUIT
RcLooksLike(word, want)
	{
	if (want = "")
		return false
	StringUpper, word, word
	word := RegExReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(word, "0", "O"), "1", "I"), "5", "S"), "8", "B"), "|", "I"), "[^A-Z]")
	if (word = "" || word = "QUIT" || Abs(StrLen(word) - StrLen(want)) > 1)
		return false
	return RcEditDistance(word, want) <= (StrLen(want) >= 7 ? 2 : 1)
	}

;How many single-letter changes (add, drop or swap one) turn a into b
RcEditDistance(a, b)
	{
	lenB := StrLen(b), prevRow := []
	Loop, % lenB + 1
		prevRow[A_Index] := A_Index - 1
	Loop, Parse, a
		{
		row := [A_Index]
		charA := A_LoopField
		Loop, % lenB
			row[A_Index + 1] := Min(prevRow[A_Index + 1] + 1, row[A_Index] + 1, prevRow[A_Index] + (charA == SubStr(b, A_Index, 1) ? 0 : 1))
		prevRow := row
		}
	return prevRow[lenB + 1]
	}

;Types text into a window as WM_CHAR messages (backspaces first: clears the box it goes into)
RcChars(win, text, backspaces := 0)
	{
	Loop, % backspaces
		SendMessage, 0x102, 8, 0,, ahk_id %win%
	Loop, Parse, text
		{
		SendMessage, 0x102, Ord(A_LoopField), 0,, ahk_id %win%
		Sleep, 15
		}
	}

;Where the game is: the running one's path, else the last known one, else the usual install folder
RcFindClient()
	{
	WinGet, exePath, ProcessPath, ahk_class %GameClass% ahk_exe %GameExe%
	if (exePath != "")
		return exePath
	if (RcExe != "")
		return RcExe
	EnvGet, progData, ProgramData
	return (progData = "" ? "C:\ProgramData" : progData) "\KingsIsle Entertainment\Wizard101\Bin\" GameExe
	}

RcSetClient(exePath)
	{
	RcExe := exePath
	SplitPath, exePath,, binDir
	RcLog := binDir "\WizardClient.log"
	}

RcSet(newState, why := "")
	{
	RcState := newState, RcStateAt := A_TickCount, RcNote := 0, RcPeeks := 0, RcPeekAt := 0
	if (why != "")
		RcLogMsg(why)
	;(stopped: it needs you - to Discord too, if alerts are set up: Alerts.ahk)
	if (newState = "stopped" && !RcScanning && IsFunc("AlertSend"))
		Func("AlertSend").Call("reconnect", "can't get back into the game", why)
	if (newState = "")
		RcStatus("online")
	}

RcLogMsg(text)
	{
	if (!RcScanning && IsFunc("DebugLog"))
		Func("DebugLog").Call("Reconnect: " text)
	}

RcStatus(text)
	{
	static lastText := ""
	if (RcScanning || text = lastText)
		return
	lastText := text
	Menu, Tray, Tip, % "Wizard101 bot " BotVersion() ": " SubStr(text, 1, 100)
	}

;Tray menu: switches auto-reconnect on and off
ReconnectToggle()
	{
	RcOn := !RcOn
	if (RcOn)
		{
		RcState := "", RcTries := 0, RcNext := 0, RcNoRelaunch := 0
		Menu, Tray, Check, Auto-reconnect on/off
		}
	else
		Menu, Tray, Uncheck, Auto-reconnect on/off
	RcLogMsg("auto-reconnect " (RcOn ? "on" : "off"))
	TrayTip, Wizard101 bot, % "Auto-reconnect " (RcOn ? "on" : "off"), 3, 1
	}

;Tray menu: asks for the Wizard101 login and keeps it in Windows Credential Manager
ReconnectSetLogin()
	{
	if (IsFunc("ReleaseKeys"))
		Func("ReleaseKeys").Call()
	RegRead, rememberedUser, HKCU\Software\KingsIsle\Wizard101, UserName
	InputBox, loginUser, Wizard101 login, Your Wizard101 username.`nUsed only to log back in if the game closes.,, 380, 160,,,,, %rememberedUser%
	if (ErrorLevel || Trim(loginUser) = "")
		return
	InputBox, loginPass, Wizard101 login, % "Password for " Trim(loginUser) ".`nKept encrypted in Windows Credential Manager as """ RcCredTarget """.", HIDE, 380, 160
	if (ErrorLevel || loginPass = "")
		return
	saved := RcCredSave(Trim(loginUser), loginPass)
	loginPass := ""
	if (saved)
		{
		RcLoginBad := 0
		RcLogMsg("login saved (in Windows Credential Manager)")
		MsgBox, 64, Wizard101 bot, % "Saved. If Wizard101 closes, the bot can start it and log back in.`n`n(To remove it: Windows Credential Manager > Windows Credentials > " RcCredTarget ")", 15
		}
	else
		MsgBox, 16, Wizard101 bot, % "Couldn't save the login in Windows Credential Manager (error " A_LastError ")." 
	}

;Is there a saved login?
RcHaveLogin()
	{
	found := RcCredLoad(loginUser, loginPass)
	loginUser := "", loginPass := ""
	return found
	}

;Windows Credential Manager (CredWriteW / CredReadW): a "generic" credential named RcCredTarget.
;CREDENTIALW offsets differ between 32- and 64-bit AutoHotkey
RcCredSave(user, pass)
	{
	is64 := (A_PtrSize = 8)
	VarSetCapacity(targetW, (StrLen(RcCredTarget) + 1) * 2, 0), StrPut(RcCredTarget, &targetW, "UTF-16")
	VarSetCapacity(userW, (StrLen(user) + 1) * 2, 0), StrPut(user, &userW, "UTF-16")
	blobSize := StrLen(pass) * 2
	VarSetCapacity(blob, blobSize + 2, 0), StrPut(pass, &blob, "UTF-16")
	VarSetCapacity(cred, is64 ? 80 : 52, 0)
	NumPut(1, cred, 4, "UInt")                          ;Type: CRED_TYPE_GENERIC
	NumPut(&targetW, cred, 8, "Ptr")                    ;TargetName
	NumPut(blobSize, cred, is64 ? 32 : 24, "UInt")      ;CredentialBlobSize
	NumPut(&blob, cred, is64 ? 40 : 28, "Ptr")          ;CredentialBlob
	NumPut(2, cred, is64 ? 48 : 32, "UInt")             ;Persist: CRED_PERSIST_LOCAL_MACHINE
	NumPut(&userW, cred, is64 ? 72 : 48, "Ptr")         ;UserName
	saved := DllCall("Advapi32\CredWriteW", "Ptr", &cred, "UInt", 0)
	DllCall("RtlZeroMemory", "Ptr", &blob, "Ptr", blobSize + 2)
	return saved
	}

RcCredLoad(ByRef user, ByRef pass)
	{
	user := "", pass := "", credPtr := 0
	is64 := (A_PtrSize = 8)
	VarSetCapacity(targetW, (StrLen(RcCredTarget) + 1) * 2, 0), StrPut(RcCredTarget, &targetW, "UTF-16")
	if (!DllCall("Advapi32\CredReadW", "Ptr", &targetW, "UInt", 1, "UInt", 0, "Ptr*", credPtr) || !credPtr)
		return false
	blobSize := NumGet(credPtr + 0, is64 ? 32 : 24, "UInt")
	blobPtr := NumGet(credPtr + 0, is64 ? 40 : 28, "Ptr")
	userPtr := NumGet(credPtr + 0, is64 ? 72 : 48, "Ptr")
	if (blobPtr && blobSize)
		pass := StrGet(blobPtr, blobSize // 2, "UTF-16")
	if (userPtr)
		user := StrGet(userPtr, "UTF-16")
	if (blobPtr && blobSize)
		DllCall("RtlZeroMemory", "Ptr", blobPtr, "Ptr", blobSize)
	DllCall("Advapi32\CredFree", "Ptr", credPtr)
	return (user != "" && pass != "")
	}
