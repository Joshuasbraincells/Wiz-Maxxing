#Warn Unreachable, Off
#Requires Autohotkey v2.0
; AutoQuester - walks your Wizard101 wizard towards the current quest goal by following the yellow
; quest arrow at the bottom of the screen. AHK v1.1. Walking only: AutoFarmer\Autofarmer.ahk does
; battles AND this walking in one script, so you normally don't need to run this one as well.
;   F8        start / stop walking
;   Shift+F8  quit
; Keys are only sent while Wizard101 is the active window. When there's no arrow (battle, loading
; screen, dialogue) it stops and waits. The walking itself lives in Walker.ahk (settings at its top).
; V1toV2: Removed #NoEnv
#SingleInstance force
; V1toV2: Removed SetBatchLines, -1
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")
SetWorkingDir(A_ScriptDir)

global GameExe := "WizardGraphicalClient.exe"
global GameClass := "Wizard Graphical Client"
global GameLeft := 0, GameTop := 0, GameW := 0, GameH := 0

OnExit("WalkerQuit")
;No standard tray menu: its "Pause Script" would freeze the walker with a key held down
Tray := A_TrayMenu
Tray.Delete() ; V1toV2: not 100% replacement of NoStandard, Only if NoStandard is used at the beginning
Tray.Add("Start/stop walking (F8)", ToggleWalk)
Tray.Add("Exit (Shift+F8)", QuitApp)
Tray.Default := "Start/stop walking (F8)"
if (!WalkerInit("AutoQuester"))
	{
	MsgBox("Couldn't load resources\arrow_refs.txt - AutoQuester can't read the quest arrow without it.", "AutoQuester", 16)
	ExitApp()
	}
SetStatus("stopped - press F8 in Wizard101 to start walking")
return

F8::HK1_F8()
ToggleWalk:
ToggleWalk()
return

+F8::HK2_F8()
QuitApp:
QuitApp()
ExitApp()

WalkLoop:
WalkLoop()
return

;Finds the Wizard101 client area on screen (same as AutoFarmer)
UpdateGameRect()
	{
	hwnd := WinGetID("ahk_class " GameClass " ahk_exe " GameExe)
	if (!hwnd)
		return false
	rect := Buffer(16, 0) ; V1toV2: if 'rect' is a UTF-16 string, use 'VarSetStrCapacity(&rect, 16)' and replace all instances of 'rect.Ptr' with 'StrPtr(rect)'
	pt := Buffer(8, 0) ; V1toV2: if 'pt' is a UTF-16 string, use 'VarSetStrCapacity(&pt, 8)' and replace all instances of 'pt.Ptr' with 'StrPtr(pt)'
	DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect.Ptr)
	DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt.Ptr)
	w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
	if (w <= 0 || h <= 0)
		return false
	GameLeft := NumGet(pt, 0, "Int"), GameTop := NumGet(pt, 4, "Int"), GameW := w, GameH := h
	return true
	}

#Include "%A_ScriptDir%\Walker.ahk"
#Include "%A_ScriptDir%\ArrowReader.ahk"

;###############  V1toV2 FUNCS  ###############
HK1_F8() { ; V1toV2: HK->Func
global
ToggleWalk()
}
;##############################################
ToggleWalk(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
WalkToggle()
if (Walking)
	SetTimer(WalkLoop,-1)
return
}
;##############################################
HK2_F8() { ; V1toV2: HK->Func
global
QuitApp()
}
;##############################################
QuitApp(A_ThisMenuItem:="", A_ThisMenuItemPos:="", MyMenu:="", *) { ; V1toV2: Lbl->Func
global
ExitApp()
}
;##############################################
WalkLoop() { ; V1toV2: Lbl->Func
global
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
}
