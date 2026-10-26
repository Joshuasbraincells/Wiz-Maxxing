#Requires AutoHotkey v1.1.33+
; AutoQuester - walks your Wizard101 wizard towards the current quest goal by following the yellow
; quest arrow at the bottom of the screen. AHK v1.1. Walking only: AutoFarmer\Autofarmer.ahk does
; battles AND this walking in one script, so you normally don't need to run this one as well.
;   F8        start / stop walking
;   Shift+F8  quit
; Keys are only sent while Wizard101 is the active window. When there's no arrow (battle, loading
; screen, dialogue) it stops and waits. The walking itself lives in Walker.ahk (settings at its top).
#NoEnv
#SingleInstance force
SetBatchLines, -1
CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
SetWorkingDir, %A_ScriptDir%

global GameExe := "WizardGraphicalClient.exe"
global GameClass := "Wizard Graphical Client"
global GameLeft := 0, GameTop := 0, GameW := 0, GameH := 0

OnExit("WalkerQuit")
;No standard tray menu: its "Pause Script" would freeze the walker with a key held down
Menu, Tray, NoStandard
Menu, Tray, Add, Start/stop walking (F8), ToggleWalk
Menu, Tray, Add, Exit (Shift+F8), QuitApp
Menu, Tray, Default, Start/stop walking (F8)
if (!WalkerInit("AutoQuester"))
	{
	MsgBox, 16, AutoQuester, Couldn't load resources\arrow_refs.txt - AutoQuester can't read the quest arrow without it.
	ExitApp
	}
SetStatus("stopped - press F8 in Wizard101 to start walking")
return

F8::
ToggleWalk:
WalkToggle()
if (Walking)
	SetTimer, WalkLoop, -1
return

+F8::
QuitApp:
ExitApp

WalkLoop:
;A quick stop+start can queue a second run of this; only run while walking
if (!Walking)
	return
while (Walking)
	{
	UpdateGameRect()
	if (!WalkStep())
		break
	}
if (KeysDown || HeldW)
	ReleaseKeys()
;"stuck" keeps its own message, everything else says it's stopped
if (StatusKind != "stuck")
	SetStatus("stopped - press F8 to start walking")
return

;Finds the Wizard101 client area on screen (same as AutoFarmer)
UpdateGameRect()
	{
	WinGet, hwnd, ID, ahk_class %GameClass% ahk_exe %GameExe%
	if (!hwnd)
		return false
	VarSetCapacity(rect, 16, 0)
	VarSetCapacity(pt, 8, 0)
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rect)
	DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", &pt)
	w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
	if (w <= 0 || h <= 0)
		return false
	GameLeft := NumGet(pt, 0, "Int"), GameTop := NumGet(pt, 4, "Int"), GameW := w, GameH := h
	return true
	}

#Include %A_ScriptDir%\Walker.ahk
#Include %A_ScriptDir%\ArrowReader.ahk
