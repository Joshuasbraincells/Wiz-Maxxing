#Warn Unreachable, Off
; Watch.ahk - "Open with Wizard101": a watcher started with Windows (a shortcut in your Startup folder to
; Wiz-Maxxing.exe /watch) opens the bot when Wizard101 starts - in standby: it does nothing (no battles, walking
; or potions) till you press F6. AHK v1.1, functions and labels only; #Included by Wiz-Maxxing.ahk (the watcher
; itself), Setup.ahk ("Open with Wizard101") and AutoFarmer\Autofarmer.ahk (its tray menu's "Open with Wizard101").
;
; The watcher looks every 3 s whether Wizard101 (WizardGraphicalClient.exe) is running. A game it hasn't seen yet
; (a new process) with no bot running: the update check (it asks only if there's a newer release), then the bot in
; standby (AutoFarmer\Autofarmer.exe /standby). A bot already running (from any folder) is left alone - never a
; second one. One watcher at a time. Its tray icon: stop watching, or don't open with Wizard101 any more.

;How one of the bot's programs is started - rel: its path without .exe / .ahk (e.g. ...\AutoFarmer\Autofarmer):
;{target, args}. Started as a script ourselves (AutoHotkey running a .ahk - Windows 11's Smart App Control blocks
;the bot's unsigned exes, AutoHotkey itself it lets run): its script, by this same AutoHotkey. Else its exe - or
;its script when there's no exe
BotProgram(rel, args := "")
	{
	if (!A_IsCompiled && FileExist(rel ".ahk"))
		return (AHKv1v2_Temp := {target: A_AhkPath, args: "`"" rel ".ahk`"" (args = "" ? "" : " " args)}, AHKv1v2_Temp) ; V1toV2: Wrapped Multi-statement return with parentheses
	if (FileExist(rel ".exe"))
		return {target: rel ".exe", args: args}
	return {target: rel ".ahk", args: args}
	}

;Starts it (BotProgram) in dir. False if Windows wouldn't (A_LastError says why)
BotRun(rel, args, dir)
	{
	p := BotProgram(rel, args)
	{   ErrorLevel := "ERROR"
	   Try ErrorLevel := Run("""" p.target """" (p.args = "" ? "" : " " p.args), dir, "", )
	}
	return !ErrorLevel
	}

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
		p := BotProgram(root "\Wiz-Maxxing", "/watch")
		FileCreateShortcut(p.target, link, root, p.args, "Opens the Wizard101 bot when Wizard101 starts (in standby - " WatchBotKey(root "\AutoFarmer") " starts it)")
		if (ErrorLevel)
			return false
		if (!WatchPids().Length())
			BotRun(root "\Wiz-Maxxing", "/watch", root)
		return true
		}
	Try FileDelete(link)
	DetectHiddenWindows(true)
	for i, pid in WatchPids()
		{
		WinClose("ahk_pid " pid " ahk_class AutoHotkey")
		ErrorLevel := ProcessWaitClose(pid, 3)
		if (ErrorLevel)
			ErrorLevel := ProcessClose(pid)
		}
	return !FileExist(link)
	}

;The running watchers' pids: Wiz-Maxxing.exe /watch, or AutoHotkey running Wiz-Maxxing.ahk /watch
WatchPids()
	{
	pids := []
	for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE CommandLine LIKE '%Wiz-Maxxing%/watch%'")
		if (p.ProcessId != DllCall("GetCurrentProcessId") && RegExMatch(p.CommandLine, "i)Wiz-Maxxing\.(exe|ahk)`"?\s+/watch\b"))
			pids.Push(p.ProcessId)
	return pids
	}

;Whether the bot (AutoFarmer\Autofarmer.exe or .ahk, from any folder) is running - or the quest walker on its own
;(AutoQuester: a bot next to it would take its F8): their hidden AutoHotkey windows
WatchBotRunning()
	{
	DetectHiddenWindows(true)
	SetTitleMatchMode(2)
	return WinExist("\Autofarmer. ahk_class AutoHotkey") || WinExist("\AutoQuester. ahk_class AutoHotkey")
	}

;After an update: a new watcher from the new Wiz-Maxxing.exe (it waits for this one's mutex), this one goes
WatchRestart()
	{
	BotRun(A_ScriptDir "\Wiz-Maxxing", "/watch", A_ScriptDir)
	ExitApp()
	}

;The bot's on/off key in words, for the texts here - F6 out of the box, yours from the dashboard's Keys tab (dir: the
;AutoFarmer folder, its dashboard.ini [hotkeys] bot). In the bot: Hotkeys.ahk's HkText; the watcher and Setup.ahk
;don't have it, so it's read here
WatchBotKey(dir)
	{
	if (IsFunc("HkText"))
		return HkText.Call("bot")
	k := IniRead(dir "\dashboard.ini", "hotkeys", "bot", A_Space)
	k := Trim(k)
	if (k = "none")
		return "(none)"
	if (!RegExMatch(k, "^([#^!+]*)(.+)$", &m) || !(GetKeyVK(m[2]) || GetKeySC(m[2])))
		return "F6"
	t := ""
	Loop Parse, m[1]
		t .= A_LoopField = "#" ? "Windows+" : A_LoopField = "^" ? "Ctrl+" : A_LoopField = "!" ? "Alt+" : "Shift+"
	key := m[2] = "Escape" ? "Esc" : m[2]
	return t (StrLen(key) = 1 ? Format("{:U}", key) : Format("{:T}", SubStr(key, 1, 1)) SubStr(key, 2))
	}

;Starts the bot from dir (the AutoFarmer folder) in standby
WatchStartBot(dir)
	{
	BotRun(dir "\Autofarmer", "/standby", dir)
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
		Sleep(1000)
		}
	if (!A_IsCompiled && FileExist(A_ScriptDir "\assets\wizard.ico"))
		TraySetIcon(A_ScriptDir . "\assets\wizard.ico")
	;(shown: the launcher's #NoTrayIcon hides it)
	TraySetIcon("Menu, Tray, Icon","Menu, Tray, Icon","Menu, Tray, Icon")
	Tray := A_TrayMenu
	Tray.Delete() ; V1toV2: not 100% replacement of NoStandard, Only if NoStandard is used at the beginning
	watchItem := "Opens the bot when Wizard101 starts (" WatchBotKey(dir) " starts it)"
	Tray.Add(watchItem, WatchMenuNothing)
	Tray.Disable(watchItem)
	Tray.Add("Stop watching (till Windows starts again)", WatchMenuStop)
	Tray.Add("Don't open with Wizard101 any more", WatchMenuOff)
	A_IconTip := "Wiz-Maxxing - watching for Wizard101"
	seen := 0
	Loop
		{
		ErrorLevel := ProcessExist("WizardGraphicalClient.exe")
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
				Sleep(3000)
				WatchStartBot(dir)
				if (IsFunc("UpCheck") && WatchUpCheck())
					{
					Sleep(1500)
					if (!WatchBotRunning())
						WatchStartBot(dir)
					WatchRestart()
					}
				}
			}
		;(the bot's key changed on the Keys tab: the item says the new one)
		now := "Opens the bot when Wizard101 starts (" WatchBotKey(dir) " starts it)"
		if (now != watchItem)
			{
			; V1toV2: Removed UseErrorLevel from Menu Tray
			Tray.Rename(watchItem, now)
			; V1toV2: Removed UseErrorLevel from Menu Tray
			watchItem := now
			}
		Sleep(3000)
		}
	}

;The watcher's update check (UpCheck) - only when no other check or install is going on (the bot's update by
;itself, the Updates button): the same lock as UpOnlyOne, let go of afterwards - the watcher runs for days. True if it
;updated
WatchUpCheck()
	{
	mutex := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Wiz-Maxxing update", "Ptr")
	if (A_LastError = 183)
		{
		DllCall("CloseHandle", "Ptr", mutex)
		return false
		}
	updated := UpCheck.Call(true)
	DllCall("CloseHandle", "Ptr", mutex)
	return updated
	}

WatchMenuNothing:
WatchMenuNothing()
	return

WatchMenuStop:
WatchMenuStop()
	ExitApp()

WatchMenuOff:
WatchMenuOff()
	ExitApp()

;###############  V1toV2 FUNCS  ###############
WatchMenuNothing(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
	global
	return
}
;##############################################
WatchMenuStop(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
	global
	ExitApp()
}
;##############################################
WatchMenuOff(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
	global
	Try FileDelete(WatchLink())
	TrayTip("Wiz-Maxxing", "The bot won't open with Wizard101 any more (the bot's tray menu `"Open with Wizard101`" turns it back on).", 1)
	Sleep(3000)
	ExitApp()
}
