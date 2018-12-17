#`::

SetWorkingDir, C:\Users\Joshua\Desktop

CoordMode, Pixel, Screen

ImageSearch, tempX, tempY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\temp.png
if !ErrorLevel = 1
{
    MsgBox, found tempest. (Coords: %tempX%, %tempY%) (E.L.:%ErrorLevel%) 
}  
ImageSearch, tempX, tempY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 C:\Users\Joshua\Desktop\temp2.png
if !ErrorLevel = 1
{
    MsgBox, found tempest 2. (Coords: %tempX%, %tempY%) (E.L.:%ErrorLevel%)
} 
