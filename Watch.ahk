; Watch.ahk - "Open with Wizard101": a watcher started with Windows (a shortcut in your Startup folder to
; Wiz-Maxxing.exe /watch) opens the bot when Wizard101 starts - in standby: it does nothing (no battles, walking
; or potions) till you press F6. AHK v1.1, functions and labels only; #Included by Wiz-Maxxing.ahk (the watcher
; itself), Setup.ahk ("Open with Wizard101") and AutoFarmer\Autofarmer.ahk (its tray menu's "Open with Wizard101").
;
; The watcher looks every 3 s whether Wizard101 (WizardGraphicalClient.exe) is running. A game it hasn't seen yet
; (a new process) with no bot running: the update check (it asks only if there's a newer release), then the bot in
; standby (AutoFarmer\Autofarmer.exe /standby). A bot already running (from any folder) is left alone - never a
; second one. One watcher at a time. Its tray icon: stop watching, or don't open with Wizard101 any more.

;The Startup folder's shortcut that starts the watcher with Windows
WatchLink()
	{
	return A_Startup "\Wiz-Maxxing (opens with Wizard101).lnk"
	}

;"Open with Wizard101" on: the shortcut is there
WatchIsOn()
	{
	return FileExist(WatchLink()) != ""
	}

;root: the bot's folder (where Wiz-Maxxing.exe is). wantOn: the Startup shortcut made, and the watcher started now
;(not only at the next sign-in); off: the shortcut deleted and a running watcher closed. True if done
WatchSet(root, wantOn)
	{
	link := WatchLink()
	if (wantOn)
		{
		target := FileExist(root "\Wiz-Maxxing.exe") ? root "\Wiz-Maxxing.exe" : root "\Wiz-Maxxing.ahk"
		FileCreateShortcut, %target%, %link%, %root%, /watch, Opens the Wizard101 bot when Wizard101 starts (in standby - F6 starts it)
		if (ErrorLevel)
			return false
		if (!WatchPids().Length())
			Run, "%target%" /watch, %root%, UseErrorLevel
		return true
		}
	FileDelete, %link%
	DetectHiddenWindows, On
	for i, pid in WatchPids()
		{
		WinClose, ahk_pid %pid% ahk_class AutoHotkey
		Process, WaitClose, %pid%, 3
		if (ErrorLevel)
			Process, Close, %pid%
		}
	return !FileExist(link)
	}

;The running watchers' pids: Wiz-Maxxing.exe /watch, or AutoHotkey running Wiz-Maxxing.ahk /watch
WatchPids()
	{
	pids := []
	for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE CommandLine LIKE '%Wiz-Maxxing%/watch%'")
		if (p.ProcessId != DllCall("GetCurrentProcessId") && RegExMatch(p.CommandLine, "i)Wiz-Maxxing\.(exe|ahk)""?\s+/watch\b"))
			pids.Push(p.ProcessId)
	return pids
	}

;Whether the bot (AutoFarmer\Autofarmer.exe or .ahk, from any folder) is running - or the quest walker on its own
;(AutoQuester: a bot next to it would take its F8): their hidden AutoHotkey windows
WatchBotRunning()
	{
	DetectHiddenWindows, On
	SetTitleMatchMode, 2
	return WinExist("\Autofarmer. ahk_class AutoHotkey") || WinExist("\AutoQuester. ahk_class AutoHotkey")
	}

;After an update: a new watcher from the new Wiz-Maxxing.exe (it waits for this one's mutex), this one goes
WatchRestart()
	{
	if (FileExist(A_ScriptDir "\Wiz-Maxxing.exe"))
		Run, "%A_ScriptDir%\Wiz-Maxxing.exe" /watch, %A_ScriptDir%, UseErrorLevel
	else
		Run, "%A_AhkPath%" "%A_ScriptDir%\Wiz-Maxxing.ahk" /watch, %A_ScriptDir%, UseErrorLevel
	ExitApp
	}

;Starts the bot from dir (the AutoFarmer folder) in standby
WatchStartBot(dir)
	{
	if (FileExist(dir "\Autofarmer.exe"))
		Run, "%dir%\Autofarmer.exe" /standby, %dir%, UseErrorLevel
	else
		Run, "%dir%\Autofarmer.ahk" /standby, %dir%, UseErrorLevel
	}

;The watcher (Wiz-Maxxing.exe /watch) - never returns, except when another watcher is running already (a named
;mutex: a new one started by an update waits up to 8 s for the old one to go)
WatchGame(dir)
	{
	t0 := A_TickCount
	Loop
		{
		mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Wiz-Maxxing watcher", "Ptr")
		if (A_LastError != 183)
			break
		DllCall("CloseHandle", "Ptr", mutex)
		if (A_TickCount - t0 > 8000)
			return
		Sleep, 1000
		}
	if (!A_IsCompiled && FileExist(A_ScriptDir "\assets\wizard.ico"))
		Menu, Tray, Icon, %A_ScriptDir%\assets\wizard.ico
	;(shown: the launcher's #NoTrayIcon hides it)
	Menu, Tray, Icon
	Menu, Tray, NoStandard
	Menu, Tray, Add, Opens the bot when Wizard101 starts (F6 starts it), WatchMenuNothing
	Menu, Tray, Disable, Opens the bot when Wizard101 starts (F6 starts it)
	Menu, Tray, Add, Stop watching (till Windows starts again), WatchMenuStop
	Menu, Tray, Add, Don't open with Wizard101 any more, WatchMenuOff
	Menu, Tray, Tip, Wiz-Maxxing - watching for Wizard101
	seen := 0
	Loop
		{
		Process, Exist, WizardGraphicalClient.exe
		pid := ErrorLevel
		;(the game closed: the next one is new, whatever pid Windows gives it)
		if (!pid)
			seen := 0
		else if (pid != seen)
			{
			seen := pid
			if (!WatchBotRunning())
				{
				;(the game's window first, then the bot - then a newer release, if any, is offered: an update closes
				;the bot, so it's opened again, and the watcher starts again from the new Wiz-Maxxing.exe)
				Sleep, 3000
				WatchStartBot(dir)
				if (IsFunc("UpCheck") && Func("UpCheck").Call(true))
					{
					Sleep, 1500
					if (!WatchBotRunning())
						WatchStartBot(dir)
					WatchRestart()
					}
				}
			}
		Sleep, 3000
		}
	}

WatchMenuNothing:
	return

WatchMenuStop:
	ExitApp

WatchMenuOff:
	FileDelete, % WatchLink()
	TrayTip, Wiz-Maxxing, The bot won't open with Wizard101 any more (the bot's tray menu "Open with Wizard101" turns it back on)., 5, 1
	Sleep, 3000
	ExitApp
