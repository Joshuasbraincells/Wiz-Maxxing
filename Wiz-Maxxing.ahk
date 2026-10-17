; Wiz-Maxxing.ahk - starts the bot: AutoFarmer\Autofarmer.exe (else AutoFarmer\Autofarmer.ahk, with AutoHotkey).
; Built to Wiz-Maxxing.exe by build.ps1, with the wizard icon; Setup puts it in the Start menu and on the
; desktop. AutoHotkey v1.1.
#NoEnv
#NoTrayIcon
#SingleInstance off
dir := A_ScriptDir "\AutoFarmer"
if (FileExist(dir "\Autofarmer.exe"))
	Run, "%dir%\Autofarmer.exe", %dir%, UseErrorLevel
else if (FileExist(dir "\Autofarmer.ahk"))
	Run, "%dir%\Autofarmer.ahk", %dir%, UseErrorLevel
else
	{
	MsgBox, 48, Wiz-Maxxing, % "The bot isn't here: Wiz-Maxxing.exe has to stay in the bot's folder, next to AutoFarmer\ (it's in " A_ScriptDir ")."
	ExitApp
	}
if (ErrorLevel)
	MsgBox, 48, Wiz-Maxxing, % "Couldn't start the bot in " dir ". Without Autofarmer.exe there, AutoHotkey v1.1 is needed to run Autofarmer.ahk (Setup.exe can install it), or download the zip with the exes from the GitHub Releases page."
ExitApp
