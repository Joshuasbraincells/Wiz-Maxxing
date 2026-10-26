#1::
{ ; V1toV2: Added opening brace for [#1]
global ; V1toV2: Made function global

InstallMouseHook()
InstallKeybdHook()

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
Buffer := 10 ;Default is 10

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
  Sleep(Buffer)
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
    Sleep(Buffer)
  }
    Sleep(%Loading% - 1500)
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
} ; V1toV2: Added closing brace for [#1] (NO CLEAR EXIT FOUND)
Esc::Reload()