; Wiz-Maxxing.ahk - opens the bot: first checks GitHub for a newer version (Updater.ahk) and asks to install it,
; then starts AutoFarmer\Autofarmer.exe (else AutoFarmer\Autofarmer.ahk, with AutoHotkey). Built to
; Wiz-Maxxing.exe by build.ps1, with the wizard icon; Setup puts it in the Start menu and on the desktop.
;   Wiz-Maxxing.exe /check   only the update check, with a message either way (the tray menu's "Check for
;                            updates"); the bot is started again only if it was updated
;   Wiz-Maxxing.exe /watch   the watcher ("Open with Wizard101" - started with Windows): opens the bot in standby
;                            when Wizard101 starts (Watch.ahk); F6 then starts it
; AutoHotkey v1.1.
#NoEnv
#NoTrayIcon
#SingleInstance off
checkOnly := (A_Args[1] = "/check")
dir := A_ScriptDir "\AutoFarmer"
if (A_Args[1] = "/watch")
	{
	WatchGame(dir)
	ExitApp
	}
if (!FileExist(dir "\Autofarmer.ahk") && !FileExist(dir "\Autofarmer.exe"))
	{
	MsgBox, 48, Wiz-Maxxing, % "The bot isn't here: Wiz-Maxxing.exe has to stay in the bot's folder, next to AutoFarmer\ (it's in " A_ScriptDir ")."
	ExitApp
	}
updated := UpCheck(!checkOnly)
if (checkOnly && !updated)
	ExitApp
hasExe := FileExist(dir "\Autofarmer.exe") != ""
if (hasExe)
	Run, "%dir%\Autofarmer.exe", %dir%, UseErrorLevel
else
	Run, "%dir%\Autofarmer.ahk", %dir%, UseErrorLevel
if (ErrorLevel)
	{
	runErr := A_LastError
	MsgBox, 48, Wiz-Maxxing, % "Couldn't start the bot in " dir ".`n`n" LaunchWhy(hasExe, runErr)
	}
ExitApp

;Why the bot didn't start: Autofarmer.exe there but Windows wouldn't run it (its error; a virus alarm - a false one,
;common with AutoHotkey programs - pointed at Windows Security's Protection history), or not there at all
LaunchWhy(hasExe, err)
	{
	security := "Windows Security often takes AutoHotkey programs for a virus (a false alarm): Windows Security > Virus & threat protection > Protection history > the Autofarmer.exe entry > Actions > Allow (or Restore). To keep it from happening again: Virus & threat protection > Manage settings > Exclusions > add the Wiz-Maxxing folder."
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
