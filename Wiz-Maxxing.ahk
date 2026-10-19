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
if (FileExist(dir "\Autofarmer.exe"))
	Run, "%dir%\Autofarmer.exe", %dir%, UseErrorLevel
else
	Run, "%dir%\Autofarmer.ahk", %dir%, UseErrorLevel
if (ErrorLevel)
	MsgBox, 48, Wiz-Maxxing, % "Couldn't start the bot in " dir ". Without Autofarmer.exe there, AutoHotkey v1.1 is needed to run Autofarmer.ahk (Setup.exe can install it), or download the zip with the exes from the GitHub Releases page."
ExitApp

#Include %A_ScriptDir%\Updater.ahk
#Include %A_ScriptDir%\Watch.ahk
