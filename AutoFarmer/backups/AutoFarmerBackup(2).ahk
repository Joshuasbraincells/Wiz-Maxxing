#`::

SetWorkingDir, C:\Users\Joshua\Desktop

CoordMode, Pixel, Screen
blade = false

ImageSearch, playerX, playerY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\player.png

ImageSearch, sharpX, sharpY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\sharpen.png
if !ErrorLevel = 1
{
	sharpen = true
} else {
	sharpen = false
}

ImageSearch, bladeX, bladeY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\stormblade.png
if !ErrorLevel = 1
{
	if sharpen = true
	{
      Mousemove, sharpX, sharpY, 5
	  Click
	  sleep, 100
	  Mousemove, bladeX, bladeY, 5
	  Click
	  sleep, 500
	}
	sleep, 1000
    Mousemove, bladeX, bladeY
	Click
	sleep, 500
	Mousemove, playerX, PlayerY, 5
	Click
	blade = true
}

if blade = true 
{
MsgBox, Blade is true
} else {
MsgBox, Blade is false
}

if blade = true {} else 
{
  ImageSearch, epicX, epicY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\epic.png
  if !ErrorLevel = 1
  {	
    epic = true
	Mousemove, epicX, epicY, 5
  } else {
    epic = false
  }

ImageSearch, bugsX, bugsY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\bugs.png
Msgbox, %ErrorLevel%
if !ErrorLevel = 1
{	
	if epic = true
	{
      Mousemove, epicX, epicY, 5
	  Click
	  sleep, 100
	  Mousemove, bugsX, bugsY, 5
	  Click
	}
	sleep, 1000
	Mousemove, bugsX, bugsY
	Click
	} else {
		ImageSearch, lordX, lordY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\stormlord.png
		Msgbox, %ErrorLevel%
		if !ErrorLevel = 1
		{
			if epic = true
			{
			Mousemove, epicX, epicY, 5
			Click
			sleep, 100
			Mousemove, lordX, lordY, 5
			Click
			}
			sleep, 1000
			Mousemove, lordX, lordY, 1
			Click
		} else {
			ImageSearch, tempX, tempY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\temp.png
			Msgbox, %ErrorLevel%
			if !ErrorLevel = 1
			{
				if epic = true
				{
					Mousemove, epicX, epicY, 5
					Click
					sleep, 100
					Mousemove, tempX, tempY, 5
					Click
				}
				sleep, 500
				Mousemove, tempX, tempY, 1
				Click
			}
		}
	}
}
^Esc::Exit