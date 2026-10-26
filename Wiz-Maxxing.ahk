#Requires AutoHotkey v1.1.33+
; Wiz-Maxxing.ahk - opens the bot: first checks GitHub for a newer version (Updater.ahk) and asks to install it,
; then starts AutoFarmer\Autofarmer.exe (else AutoFarmer\Autofarmer.ahk, with AutoHotkey). Built to
; Wiz-Maxxing.exe by build.ps1, with the wizard icon; Setup puts it in the Start menu and on the desktop.
;   Wiz-Maxxing.exe /check   only the update check, with a message either way (the tray menu's "Check for
;                            updates", the dashboard's Updates button); the bot is started again only if it was
;                            updated - /check /off or /check /standby: started again as it was (off, in standby);
;                            /playforme /nowalk /noreconnect /learnall: Play for me still on, walking or
;                            auto-reconnect still off, Learn every card still on
;   Wiz-Maxxing.exe /check /auto   the same with no question and no window (the bot - Settings: autoupdate): a newer
;                            one downloaded, the bot closes itself for it at a safe point, installed (Updater.ahk
;                            UpAuto) and the bot started again as it was then
;   Wiz-Maxxing.exe /watch   the watcher ("Open with Wizard101" - started with Windows): opens the bot in standby
;                            when Wizard101 starts (Watch.ahk); F6 then starts it
;   Wiz-Maxxing.exe /latest  only looks up the latest release, into updater.ini (the dashboard's Updates button and
;                            STATISTICS say from it whether a newer one is out) - nothing shown, nothing installed
;   Wiz-Maxxing.exe /report <file>   posts a bug report as an issue on GitHub (the dashboard's Report a bug -
;                            Updater.ahk UpReport); its answer in <file>.result
; AutoHotkey v1.1.
#NoEnv
#NoTrayIcon
#SingleInstance off
checkOnly := (A_Args[1] = "/check")
;(/check's other words: /auto - an update by itself; how to start the bot again - off, in standby, Play for me on)
autoUp := false, botArg := ""
if (checkOnly)
	for i, a in A_Args
		if (a = "/auto")
			autoUp := true
		else if (BotArgOk(a))
			botArg .= (botArg = "" ? "" : " ") a
dir := A_ScriptDir "\AutoFarmer"
if (A_Args[1] = "/watch")
	{
	WatchGame(dir)
	ExitApp
	}
if (A_Args[1] = "/latest")
	{
	UpPeek()
	ExitApp
	}
if (A_Args[1] = "/report")
	{
	UpReport(A_Args[2])
	ExitApp
	}
if (!FileExist(dir "\Autofarmer.ahk") && !FileExist(dir "\Autofarmer.exe"))
	{
	MsgBox, 48, Wiz-Maxxing, % "The bot isn't here: Wiz-Maxxing.exe has to stay in the bot's folder, next to AutoFarmer\ (it's in " A_ScriptDir ")."
	ExitApp
	}
;(one check at a time: another running - its question brought forward - this one only starts the bot, or stops)
if (!UpOnlyOne(!autoUp))
	{
	;(the Updates button while an update by itself is downloaded and waiting for the bot to close for it: it's asked to
	;close for it now - as soon as it's out of battle with nothing loading, not waiting for you to leave the keys and
	;mouse alone - and you're told)
	if (checkOnly && !autoUp && UpAutoWaiting(waitTag))
		{
		IniWrite, 1, %A_ScriptDir%\updater.ini, auto, now
		MsgBox, 262208, Wiz-Maxxing update, % waitTag " is downloaded - the bot closes for it as soon as it's out of battle with nothing loading, installs it and starts again as it is now.", 30
		}
	if (checkOnly)
		ExitApp
	updated := false
	}
else
	updated := autoUp ? UpAuto() : UpCheck(!checkOnly)
;(an update by itself: the bot started again only when it closed itself for it - as it was then, whether the files
;went in or were all put back; not when it's still running or you'd closed it)
if (autoUp)
	{
	if (!UpHandedOver)
		ExitApp
	botArg := ""
	Loop, Parse, UpHandArgs, %A_Space%
		if (BotArgOk(A_LoopField))
			botArg .= (botArg = "" ? "" : " ") A_LoopField
	}
;(after /check the bot is started again only when it was closed: updated - or closed for an update that then couldn't
;replace the files and put everything back)
else if (checkOnly && !updated && !UpBotsClosed)
	ExitApp
;(started as a script - Wiz-Maxxing.ahk, e.g. with Smart App Control on: the bot as a script too, by this same
;AutoHotkey - Watch.ahk BotProgram)
hasExe := A_IsCompiled && FileExist(dir "\Autofarmer.exe") != ""
started := BotRun(dir "\Autofarmer", botArg, dir), runErr := A_LastError
;(after an update by itself nobody may be there: tried again a few times, then the script by AutoHotkey if it's
;installed - a new Autofarmer.exe is often held up by Windows Security a while - and said in updater.log)
if (!started && autoUp)
	{
	UpLog("auto: couldn't start the bot (error " runErr ") - trying again")
	Loop, 3
		{
		Sleep, 5000
		if (started := BotRun(dir "\Autofarmer", botArg, dir))
			break
		runErr := A_LastError
		}
	if (!started && A_IsCompiled && (v1Ahk := AhkV1()) != "" && FileExist(dir "\Autofarmer.ahk"))
		{
		Run, % """" v1Ahk """ """ dir "\Autofarmer.ahk""" (botArg = "" ? "" : " " botArg), %dir%, UseErrorLevel
		started := !ErrorLevel
		if (started)
			UpLog("auto: started the bot as a script (Autofarmer.ahk by AutoHotkey) - Autofarmer.exe wouldn't run")
		}
	if (!started)
		UpLog("auto: the bot couldn't be started: " RegExReplace(LaunchWhy(hasExe, runErr), "`n+", " "))
	}
if (!started)
	MsgBox, 48, Wiz-Maxxing, % "Couldn't start the bot in " dir ".`n`n" LaunchWhy(hasExe, runErr)
ExitApp

;A word of /check's that says how to start the bot again (off, in standby, Play for me on, walking or auto-reconnect
;off, Learn every card on)
BotArgOk(a)
	{
	return a = "/off" || a = "/standby" || a = "/playforme" || a = "/nowalk" || a = "/noreconnect" || a = "/learnall"
	}

;Why the bot didn't start: Autofarmer.exe there but Windows wouldn't run it (its error; a virus alarm - a false one,
;common with AutoHotkey programs - pointed at Windows Security's Protection history), or not there at all
LaunchWhy(hasExe, err)
	{
	security := "Windows Security often takes AutoHotkey programs for a virus (a false alarm): Windows Security > Virus & threat protection > Protection history > the Autofarmer.exe entry > Actions > Allow (or Restore). To keep it from happening again: Virus & threat protection > Manage settings > Exclusions > add the Wiz-Maxxing folder.`n`n""Smart App Control blocked"" instead: it blocks the bot's exes (they aren't signed) and lets no exceptions be made - install AutoHotkey v1.1 (autohotkey.com) and open Wiz-Maxxing.ahk instead of Wiz-Maxxing.exe: the bot then runs as scripts."
	if (hasExe)
		{
		VarSetCapacity(msg, 1024, 0)
		n := DllCall("FormatMessage", "UInt", 0x1200, "Ptr", 0, "UInt", err, "UInt", 0, "Str", msg, "UInt", 512, "Ptr", 0)
		text := n ? Trim(msg, " `r`n.") : "error " err
		return "Windows wouldn't start AutoFarmer\Autofarmer.exe: " text " (" err ").`n`n" ((err = 225 || err = 1260 || err = 5) ? security : "Run Setup.exe and tick ""Unblock the bot's files"", then try again.")
		}
	return "AutoFarmer\Autofarmer.exe isn't there, and AutoHotkey v1.1 isn't installed to run Autofarmer.ahk instead.`n`n" security "`n`nOr run Setup.exe and tick ""AutoHotkey v1.1"" - then the bot runs as a script."
	}

#Include %A_ScriptDir%\Updater.ahk
#Include %A_ScriptDir%\Watch.ahk

;A v1.1 AutoHotkey to run the bot's scripts with ("" none): the installed one if it's v1.1 - with v2 installed too it
;can be v2 (or its launcher), and the scripts are v1.1 - else v1.1 where the v2 installer puts it (a v1.1.x folder)
AhkV1()
	{
	cands := [A_AhkPath]
	SplitPath, A_AhkPath, , ahkDir
	for each, root in [ahkDir, A_ProgramFiles "\AutoHotkey", A_AppData "\..\Local\Programs\AutoHotkey"]
		{
		if (root = "")
			continue
		cands.Push(root "\AutoHotkeyU64.exe")
		Loop, Files, %root%\v1.1*, D
			cands.Push(A_LoopFileFullPath "\AutoHotkeyU64.exe")
		}
	for each, exe in cands
		if (exe != "" && FileExist(exe))
			{
			FileGetVersion, ver, %exe%
			if (SubStr(ver, 1, 4) = "1.1.")
				return exe
			}
	return ""
	}
