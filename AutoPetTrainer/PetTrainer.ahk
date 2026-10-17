#1::

#InstallMouseHook
#InstallKeybdHook

;Screen Varibles
CoordMode, Mouse, Window
leftoffset := (A_ScreenWidth - 800) / 2
topoffset := (A_ScreenHeight - 600) / 2

;Rng Varibles
up = 1
left = 2
right = 3
down = 4

;Mouse timings
Mousespeedfast = 5 ;Default is 5
Mousespeedslow = 10 ;Default is 10

;Sleep Timings
Loading = 5100 ;Default is 5000
Wait = 325 ;Default is 300
Delay = 175 ;Default is 150
Buffer = 10 ;Default is 10

loop {
  BlockInput, SendAndMouse
  BlockInput, MouseMove
  sleep, %Wait%
  send, x
  sleep, %Wait%
  send, x
  sleep, %Wait%
  Mousemove, 625 + leftoffset, 470 + topoffset, %Mousespeedfast%
  Click
  sleep, %Wait%
  Mousemove, 615 + leftoffset, 575 + topoffset, %Mousespeedfast%
  Click
  sleep, %Buffer%
  Mousemove, A_ScreenWidth/2, A_ScreenHeight/2,%Mousespeedfast%
  BlockInput, SendAndMouse
  BlockInput, Mousemove 
  sleep, %Loading%
  loop, 600
  {
    Random, direction, 1, 4
    if (direction == up) 
    {
    send, w
    }
    if (direction == left) 
    {
    send, a
    } 
    if (direction == right) 
    {
    send, d
    }
    if (direction == down) 
    {
     send, s
     }
    sleep, %Buffer%
  }
    sleep, %Loading% - 1500
  Mousemove, 610 + leftoffset, 575 + topoffset, %Mousespeedfast%
  sleep, %Delay%
  Click
  sleep, %Delay%
  Mousemove, 170 + leftoffset, 470 + topoffset, %Mousespeedfast%
  Click
  sleep, %Delay%
  Mousemove, 615 + leftoffset, 575 + topoffset, %Mousespeedfast%
  Click
  sleep, %Wait%
  Mousemove, 635 + leftoffset, 540 + topoffset, %Mousespeedfast%
  Click
  sleep, %Delay%
  Mousemove, 180 + leftoffset, 570 + topoffset, %Mousespeedfast%
  Click
  Mousemove, A_ScreenWidth/2, A_ScreenHeight/2, %Mousespeedslow%
  sleep, %Loading%
  BlockInput, Off
}
Esc::Reload