#Requires AutoHotkey v2.0
;(v1's #InstallMouseHook / #InstallKeybdHook: both hooks from the start)
V1Start() ; (v2 port: v1 started every variable blank - CONVENTIONS.md "Blank start")
InstallMouseHook()
InstallKeybdHook()
;(v1's default sending mode was Event - v2's is Input, which moves the mouse at once (MouseMove's speed ignored) and
;sends with no key or click delays)
SendMode("Event")

#1::
{
global ; (v1: a hotkey label - global scope)

;Screen Varibles
CoordMode("Mouse", "Window")
leftoffset := (A_ScreenWidth - 800) / 2
topoffset := (A_ScreenHeight - 600) / 2

;Rng Varibles
up := 1
left := 2
right := 3
down := 4

;Mouse timings
Mousespeedfast := 5 ;Default is 5
Mousespeedslow := 10 ;Default is 10

;Sleep Timings
Loading := 5100 ;Default is 5000
Wait := 325 ;Default is 300
Delay := 175 ;Default is 150
BufferVar := 10 ;Default is 10

Loop{
  BlockInput("SendAndMouse")
  BlockInput("MouseMove")
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
  Sleep(BufferVar)
  MouseMove(A_ScreenWidth/2, A_ScreenHeight/2, Mousespeedfast)
  BlockInput("SendAndMouse")
  BlockInput("Mousemove")
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
    Sleep(BufferVar)
  }
    ;(v1: "sleep, %Loading% - 1500" was an expression whose %Loading% read the variable named "5100" - a blank one:
    ;blank - 1500 is blank, a sleep of 0 - checked with v1.1. Kept: no wait here)
    Sleep(0)
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
}
}
Esc::Reload()
#Include %A_ScriptDir%\..\V1Compat.ahk ; (v2 port: the v1 behaviours it keeps)