#InstallMouseHook
#InstallKeybdHook
#SingleInstance force

#1::

global on := 1
		
MsgBox, 0, Loading AutoFarmer..., Remember`, You can always shut me off with Windows+Esc. , 1.2

stats := FileOpen("PlayerStats.txt", "r")
damage := stats.ReadLine()
damage := SubStr(damage, 8, 3)
avbossdamage := stats.ReadLine()
avbossdamage := SubStr(avbossdamage, 14, 10)

;Misc Initilization
global inbattle := 0
global roundnumber := 0
global battles := 0
global BossChoosen := 0
global boosts := 0
global afk := 0
global bossX := 0
global bossY := 0
global afk := 0

;Screen variable initilization
global ScreenX := A_ScreenWidth / 2
global ScreenY := A_ScreenHeight / 2

;Initializes modes
global commandmode := 0
global dualmode := 0
global responcemode := 0
global devmode := 0
global loremode := 0
global boostlimitmode := 0
global dualhittermode := 0
global statsmode := 0
global loopmode := 0

;Sleep timings
global Tick := 100
global Buffer := 300
global Half := 600
global Second := 1100
global Five := 5000
global Ten := 10000
global Loading := 15000 

ResetUsed()	

;Checks if in battle
TestRound:
loop, 
{
	ImageSearch, roundX, roundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\roundfinish.png
	if (ErrorLevel = 0)
		{
		if (inbattle = 1) 
			{
			battles++
			}
		checkafk()
		checkmana()
		CommandAfk()
		CommandEnter()
		CommandWalk()
		CommandPort()
		CommandOff()
		CommandReload()
		ResetVariables() 
		ResetUsed()	
		gosub, mobloop
		gosub, LoreLoop
		}
	ImageSearch, startX, startY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\roundstart.png
	If (ErrorLevel = 0)
		{
		if (dualmode == 1)
			{
			roundnumber++
			roundnumber := %roundnumber% / 2
			} else
				{
				roundnumber++
				}
		Goto, RoundStart
		}
}

RoundStart:

BlockInput, MouseMove
CenterMouse()

global inbattle = 1

;Finds the player
global playerX := 0
global playerY := 0
global player := 1

ImageSearch, playerX, playerY, 0, ScreenY / 2, A_ScreenWidth, A_ScreenHeight, A_ScreenHeight, *3 %A_WorkingDir%\resources\player3.png
if (ErrorLevel = 0)
	{
	player := 1
	} else 
		{
		Goto, TestHammer
		}
		
;Find player school

global school := ""
global schoolX := 0
global schoolY := 0

if (player == 1)
	{
	if TestSchool("balance")
		{
		Goto, TestHammer
		}
	if TestSchool("storm")
		{
		Goto, TestHammer
		} 
	if TestSchool("fire")
		{
		Goto, TestHammer
		} 
	if TestSchool("ice")
		{
		Goto, TestHammer
		}
	if TestSchool("myth")
		{
		Goto, TestHammer
		} 
	if TestSchool("life")
		{
		Goto, TestHammer
		}
	if TestSchool("death")
		{
		Goto, TestHammer
		} 
	}

;Checks who's hammer
TestHammer:

global hitter := 0
global hitschool := ""
global hammerX := 0
global hammerY := 0
global hitterX := 0
global hitterY := 0

ImageSearch, hitterX, hitterY, 0, ScreenY / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\storm\storm.png
if (Errorlevel = 0) && (Manual != 1)
	{
	hitter := 1
	hitschool := "storm"
	} else if (Errorlevel = 1)
		{	
		ImageSearch, hitterX, hitterY, 0, ScreenY / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\fire\fire.png
		if (Errorlevel = 0) && (Manual != 1)
			{
			hitter := 2
			hitschool := "fire"
			} else if (Errorlevel = 1)
				{
				ImageSearch, hitterX, hitterY, 0, ScreenY / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\myth\myth.png
				if (Errorlevel = 0) && (Manual != 1)
					{
					hitter := 3
					hitschool := "myth"
					}
				} 
		}

hammerX = %hitterX%
hammerY = %hitterY%	
	
if (hitter <= 2) 
	{
	if Tri("elemental", "blade")
		{
		blade2 := 1
		} else if (Tri("elemental", "trap"))
			{
			trap2 := 1
			} else 
				{
				blade2 := 0
				trap2 := 0
				}
	} else
		{
		if Tri("spirit", "blade")
			{
			blade2 := 1
			} else if (Tri("spirit", "trap"))
				{
				trap2 := 1
				} else 
					{
					blade2 := 0
					trap2 := 0
					}
		}	

if (Manual = 1)
	{
	hammerX = %ManualX%
    hammerY = %ManualY%
	}
	
;Enchants
enchant = 0 
ImageSearch, enchantX, enchantY, ScreenX - 300, ScreenY - 75, ScreenX + 300, ScreenY + 75, *3 %A_WorkingDir%\resources\epic.png
If (ErrorLevel = 0) && (hitter != 0)
	{
	enchant = 4
	} else if (Errorlevel = 1)
		{
		ImageSearch, enchantX, enchantY, ScreenX - 300, ScreenY - 75, ScreenX + 300, ScreenY + 75, *3 %A_WorkingDir%\resources\colossal.png
		if ErrorLevel = 0
			{
			enchant = 3
			} else if (ErrorLevel = 1)
				{
				ImageSearch, enchantX, enchantY, ScreenX - 300, ScreenY - 75, ScreenX + 300, ScreenY + 75, *3 %A_WorkingDir%\resources\gargantuan.png
				if (ErrorLevel = 0)
					{
					enchant = 2
					} else if (Errorlevel = 1) 
						{
						ImageSearch, enchantX, enchantY, ScreenX - 300, ScreenY - 75, ScreenX + 300, ScreenY + 75, *3 %A_WorkingDir%\life\enchant.png
						if (ErrorLevel = 0)
							{
							enchant = 1
							} 
						}
				} 
		}

;Finds cards avaliable

global sharpen := 0
Find("sharpen", sharpen, SharpX, SharpY, "resources") 
 
global potent := 0
Find("potent", potent, PotentX, PotentY, "resources") 

global blade := 0
Find("blade", blade, BladeX, BladeY, hitschool)

global blade3 := 0
Find("blade3", blade3, Blade3X, Blade3Y, "resources")
 
global blade4 := 0
Find("blade4", blade4, Blade4X, Blade4Y, "resources")

global trap := 0
Find("trap", trap, trapX, trapY, hitschool)

global trap3 := 0
Find("trap3", trap3, trap3X, trap3Y, "resources")

global aura := 0
Find("aura", aura, auraX, auraY, hitschool)

global tower := 0
Find("tower", tower, towerX, towerY, "resources")

global reshuffle := 0
Find("reshuffle", reshuffle, reshuffleX, reshuffleY, "resources")

global feint := 0
Find("feint", feint, feintX, feintY, "resources")

global bubble := 0
Find("bubble", bubble, bubbleX, bubbleY, hitschool)

global convert := 0
Find("convert", convert, convertX, convertY, hitschool)
if NeedsConvert()
	{
	NeedsConvert := 1
	}
	
;Finds hit specific cards
if (hitter != 0)
	{
	global hit4 := 0
	Find("hit4", hit4, hit4X, hit4Y, hitschool)
	
	global hit3 := 0
	Find("hit3", hit3, hit3X, hit3Y, hitschool)
	
	global hit2 := 0
	Find("hit2", hit2, hit2X, hit2Y, hitschool)
	
	global hit1 := 0
	Find("hit1", hit1, hit1X, hit1Y, hitschool)
	}	
		
CenterMouse()	
	
;Automatic Battle code
if (feint == 1) && (BossChoosen == 1) && UseTrap("feint", feint, Used1, Used2, "resources")
	{
	Goto, EndRound
	} else if (convert == 1) && (NeedsConvert == 1) && (BossChoosen == 1) && UseConvert("convert", convert, hitschool)
		{
		Goto, EndRound
		} else if (trap == 1) && (BossChoosen == 1) && UseTrap("trap", trap, used3, used4, hitschool)
			{
			Goto, EndRound 
			} else if (trap2 == 1) && (BossChoosen == 1) && UseTrap(traptype, %traptype%, used5, used6, "resources")
				{ 
				Goto, EndRound
				} else if (trap3 == 1) && (BossChoosen == 1) && UseTrap("trap3", trap3, used7, used8, "resources")
					{
					Goto, EndRound
					} else if (trap4 == 1) && (BossChoosen == 1) && UseTrap("trap4", trap4, used9, used10, "resources")
						{
						Goto, EndRound
						} else if (blade == 1) && UseBlade("blade", blade, used11, used12, hitschool)
							{
							Goto, EndRound
							} else if (blade2 == 1) && UseBlade(bladetype, %bladetype%, used13, used14, "resources")
								{
								Goto, EndRound
								} else if (blade3 == 1) && UseBlade("blade3", blade3, used15, used16, "resources")
									{
									Goto, EndRound
									}  else if (blade4 == 1) && UseBlade("blade4", blade4, used17, used18, "resources")
										{
										Goto, EndRound
										} else if (bubble == 1)
											{
											Click("bubble", bubble, hitschool)
											} else if (aura == 1)
												{
												Click("aura", aura, hitschool)
												} else if (hit4 == 1) && (BossChoosen = 1) && UseHit("hit4", hit4, hitschool)
													{
													Goto, EndRound
													} else if (hit3 == 1) && UseHit("hit3", hit3, hitschool)
														{
														Goto, EndRound
														} else if (hit2 == 1) && UseHit("hit2", hit2, hitschool)
															{
															Goto, EndRound
															} else if (hit1 == 1) && UseHit("hit1", hit1, hitschool)
																{
																Goto, EndRound
																} else if (tower == 1)
																	{
																	UseOnSelf("tower", tower, "resources")
																	} else if (reshuffle == 1)
																		{
																		UseOnHammer("reshuffle", reshuffle, "resources")
																		ResetUsed()
																		} else if Click("pass", pass, "resources")
																			{
																			Goto, EndRound
																			}
EndRound:
CenterMouse()
BlockInput, MouseMoveOff
	
Switch()
	
Goto, TestRound
	
;Functions
CenterMouse()
	{
	Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
	}

TestSchool(class)
	{
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\%class%\%class%.png
	if (Errorlevel = 0)
		{
		school := class
		return true
		} else {
			return false
			}
	}
	
Tri(type1, type2) 
	{
	global
	ImageSearch, typeX, typeY, ScreenX - 300, ScreenY - 75, ScreenX + 300, ScreenY + 75, *3 %A_WorkingDir%\resources\%type1%%type2%.png
	if (ErrorLevel = 0)
		{
		%type2%2X := typeX
		%type2%2Y := typeY
		if (type1 = "elemental")
			{
			bladetype := "elementalblade"
			traptype := "elementaltrap"
			} else if (type1 = "spirit")
				{
				bladetype := "spiritblade"
				traptype := "spirittrap"
				}
		return true
		} else 
			{
			return false
			}
	}

ErrorBox(ByRef funcN, ByRef dir, ByRef title)
	{
	if (devmode == 1)
		{
		n1 := "Error in " . funcN . " Function"
		n2 := "Directory: " A_WorkingDir . "\" dir . "\" . title . ".png"
		MsgBox, 4, %n1%, %n2%`n`nWould You like to continue running script?, 5
		IfMsgBox, Yes
			{
			return
			}
		IfMsgBox, No
			{
			ExitApp
			}
		IfMsgBox, Timeout
			{
			return
			}
		}
	}
	
Find(title, ByRef card, ByRef X, ByRef Y, ByRef dir)
	{
	global
	ImageSearch, X, Y, ScreenX - 300, ScreenY - 75, ScreenX + 300, ScreenY + 150, *3 %A_WorkingDir%\%dir%\%title%.png
	if (Errorlevel == 0)	
		{
		card := 1
		} else if (Errorlevel == 1)
			{
			card := 0
			} else if (Errorlevel == 2)
				{
				ErrorBox("Find", dir, title)
				}
	}
	
Click(ByRef title, ByRef click, ByRef dir)
	{
	global
	Find(title, click, clickX, clickY, dir)
	if (click == 1)
		{
		Mousemove, clickX + 5, clickY + 5, 5
		s(100)
		Click
		s(100)
		return true
		} else 
			{
			return false
			}
	}
	
UseOnSelf(ByRef title, ByRef card, ByRef dir) 
	{
	global
	Find(title, card, foundX, foundY, dir)
	
	if (card == 1)
		{
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(150)
		Mousemove, playerX, playerY, 5
		s(150)
		Click
		s(150)
		}
	}
	
UseOnHammer(ByRef title, ByRef card, ByRef dir) 
	{
	global
	Find(title, card, foundX, foundY, dir)
	
	if (card == 1)
		{
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(150)
		Mousemove, hammerX, hammerY, 5
		s(150)
		Click
		s(150)
		}
	}
	
UseBlade(ByRef title, ByRef blade, ByRef Use1, ByRef Use2, ByRef dir) 
	{
	global
	Find(title, blade, foundX, foundY, dir)
	
	if (sharpen == 1) && (blade == 1) && (Use1 != 1)
		{
		Mousemove, SharpX, SharpY, 5
		s(150)
		Click
		s(150)
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(150)
		CenterMouse()	
		s(1000)
		n := A_WorkingDir . "\" . dir . "\" . title . ".png"
		ImageSearch, foundX, foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %n%
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox("UseBlade", dir, title)
			}
		s(500)
			Mousemove, foundX, foundY, 5
			s(150)
			Click
			s(150)
		if (title != "blade4")
			{
			Mousemove, hammerX, hammerY, 5
			s(150)
			Click
			s(200)
			}
		boosts++
		Use1 := 1
		return true
		} else if (blade == 1) && (Use2 != 1) 
			{
			n := A_WorkingDir . "\" . dir . "\" . title . ".png"
			ImageSearch, foundX, foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %n%
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox("UseBlade", dir, title)
				}
				Mousemove, foundX, foundY, 5
				s(150)
				Click
				s(150)	
			if (title != "blade4")
				{
				Mousemove, hammerX, hammerY, 5
				s(150)	
				Click
				s(200)
				}
			boosts++
			Use2 := 1
			return true
			} else
				{
				return false
				}
	}

UseTrap(ByRef title, ByRef trap, ByRef Use1, ByRef Use2, ByRef dir) 
	{
	global
	Find(title, trap, foundX, foundY, dir)
	
	if (BossChoosen == 1) && (potent == 1) && (trap == 1) && (Use1 != 1)
		{
		Mousemove, potentX, potentY, 5
		s(150)
		Click
		s(150)
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(150)
		CenterMouse()	
		s(1000)
		n := A_WorkingDir . "\" . dir . "\" . title . ".png"
		ImageSearch, foundX, foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %n%
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox("UseTrap", dir, title)
			}
		s(500)
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(150)
		Mousemove, bossX, bossY, 5
		s(150)
		Click
		s(200)
		boosts++
		Use1 := 1
		return true
		} else if (BossChoosen == 1) && (trap == 1) && (Use2 != 1) 
			{
			n := A_WorkingDir . "\" . dir . "\" . title . ".png"
			ImageSearch, foundX, foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %n%
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox("UseTrap", dir, title)
				}
			Mousemove, foundX, foundY, 5
			s(150)
			Click
			s(150)					
			Mousemove, bossX, bossY, 5
			s(150)	
			Click
			s(200)
			boosts++
			Use2 := 1
			return true
			} else 
				{
				return false
				}
	}
	
UseConvert(ByRef title, ByRef convert, ByRef dir) 
	{
	global
	CenterMouse()
	Find(title, convert, foundX, foundY, dir)
	Mousemove, foundX, foundY, 5
	s(150)
	Click
	s(150)
	Mousemove, bossX, bossY, 5
	s(150)
	Click
	s(200)
	}
	
UseHit(ByRef title, ByRef hit, ByRef dir) 
	{
	global
	Find(title, hit, foundX, foundY, dir)
	
	if (enchant >= 1) && (hit == 1)
		{
		Mousemove, enchantX, enchantY, 5
		s(150)
		Click
		s(150)
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(150)
		CenterMouse()	
		s(1000)
		n := A_WorkingDir . "\" . dir . "\" . title . ".png"
		ImageSearch, foundX, foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %n%
		if ((Errorlevel == 2) && (devmode == 1))
			{
			ErrorBox("UseHit", dir, title)
			}
		s(500)
		Mousemove, foundX, foundY, 5
		s(150)
		Click
		s(200)
		return true
		} else if (hit == 1) 
			{
			n := A_WorkingDir . "\" . dir . "\" . title . ".png"
			ImageSearch, foundX, foundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %n%
			if ((Errorlevel == 2) && (devmode == 1))
				{
				ErrorBox("UseHit", dir, title)
				}
			Mousemove, foundX, foundY, 5
			s(150)
			Click
			s(200)
			return true
			} else
				{
				return false
				}
	}	
	
Switch() 
	{
	if (dualmode == 1)
		{
		Send, {Alt down}
		Send, {Tab down}
		Send, {Alt up}
		Send, {Tab up}
		}
	}
	
s(time) 
	{
	Sleep, time
	}
	
Respond(Text) 
	{
	if (responcemode == 1)
		{
		BlockInput, Send
		Send, {r}
		s(100)
		SendInput {Raw}%Text%
		Send, {Enter}
		}
	}
	
Spam(key)
	{
	Send, {%key%}
	Send, {%key%}
	Send, {%key%}
	}
	
ResetUsed()
	{
	used := 0 
	while(used < 20)
		{
		used%used% := 0
		used++
		}
	}
	
ResetVariables() 
	{
	global
	inbattle := 0
	roundnumber := 0
	playerX := 0
	playerY := 0
	Player := ""
	BossChoosen := 0
	boosts := 0
	sharpen := 0 
	potent := 0
	blade := 0
	blade2 := 0
	blade3 := 0
	blade4 := 0
	trap := 0
	trap2 := 0
	trap3 := 0
	trap4 := 0
	feint := 0
	aura := 0
	enchant := 0 
	reshuffle := 0
	hit1 := 0
	hit2 := 0
	hit3 := 0
	hit4 := 0
	tower := 0  
	hitter := 0
	hitschool := ""
	hammerX := 0
	hammerY := 0
	hitterX := 0
	hitterY := 0
	school := ""
	schoolX := 0
	schoolY := 0
	bladetype := ""
	traptype := ""
	bossX := 0
	bossY := 0
}
	
NeedsConvert()
	{
	if (BossChoosen == 1)
		{
		n := A_WorkingDir . "\" . dir . "\" . "convertN" . ".png"
		ImageSearch, nX, nY, BossX - 100, BossY - 100, BossX + 100, BossY + 100, *100 %n%
		if (Errorlevel == 0)
			{
			return true
			}
		}
	}
	
LockMove(ByRef direction)
	{
	Send, {%direction% down}
	s(50)
	Send, {Shift down}
	s(50)
	Send, {%direction% up}
	s(50)
	Send, {Shift up}
	}
	
Log()
	{
	Send, {Esc}
	s(1000)
	ImageSearch, logX, logY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\log.png
	if (Errorlevel == 0)
		{
		Mousemove, logX, logY, 5
		Click	
		} else if (Errorlevel == 2)
			{
			ErrorBox("Log", dir, title)
			}
	s(5000)
	}
	
Join()
	{
	ImageSearch, joinX, joinY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\join.png
	if (Errorlevel == 0)
		{
		Mousemove, joinX, joinY, 5
		Click
		} else if (Errorlevel == 2)
			{
			ErrorBox("Join", dir, title)
			}
	s(5000)
	}

UsePotion()
	{
	ImageSearch, potionX, potionY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\potion.png
	Mousemove, potionX, potionY, 5
	Click
	}

CheckAfk()
	{
	if (afk == 1)
		{
		Input , OutputVar,, {w} {a} {s} {d}, w, a, s, d
		if (Errorlevel != "")
			{
			afk := 0
			}
		}
	}
return

Afk()
	{
	if (afk == 0)
		{
		LockMove("a")
		afk := 1
		}
	}

checkmana()
	{
	if (afk == 0)
		{
		ImageSearch, manaX, manaY, 0, ScreenY, ScreenX / 2, A_ScreenHeight, *3 %A_WorkingDir%\resources\manaempty.png
		if (Errorlevel == 0)
			{
			Respond("Error, It Seems I Have No Mana. Preventing Timeout.")
			afk()
			}
		}
	}
	
mobloop:
if (loopmode == 1)
	{	
	Send, {s down}
	s(1000)
	Send, {s up}
	ImageSearch, inventoryX, inventoryY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\full.png
	if (Errorlevel == 0)
		{
		Respond("Error, Inventory Full. Preventing Time out.")
		afk()
		loopmode := 0
		return
		}	
	s(5000)
	Send, {w down}
	s(1000)
	Send, {w up} 
	}
return
	
LoreLoop:
	{
	if ((loremode == 1) && (dualmode == 0))
		{
		num := Mod(%battles% + 1, 50)
		if (num == 0)
			{
			UsePotion()
			}	
		log()	
		join()
		s(5000)
		Spam("x")
		s(16000)
		LockMove("w")
		s(5000)
		} else if ((loremode == 1) && (dualmode == 1))
			{
			;Joins Battles with same wizard you started the loop in
			BlockInput, MouseMove
			num := Mod(%battles% + 1, 50)
			if (num == 0)
				{
				UsePotion()
				Switch()
				s(500)
				UsePotion()
				Switch()
				}	
			log()
			switch()
			centermouse()
			log()
			join()
			switch()
			centermouse()
			join()
			switch()
			s(30000)
			Spam("x")
			Switch()
			s(1000)
			Spam("x")
			s(17000)
			LockMove("w")
			Switch()
			s(1000)
			LockMove("w")
			s(5000)
			switch()
			BlockInput, MouseMoveOff
			return
			} else 
				{
				return
				}
	} 
return

NewStaticGui(ByRef Text, ByRef x, ByRef y, ByRef w, ByRef h) 
	{
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	Gui,1:Add, Text, %box%, %Text%
	Gui,1:Show, AutoSize Center, AutoFarmer
	}

NewTempGui(ByRef timeout, ByRef Text, ByRef x, ByRef y, ByRef w, ByRef h) 
	{
	box := " x" . x . " y" . y . " w" . w . " h" . h 
	Gui,1:Add, Text, %box%, %Text%
	Gui,1:Show, AutoSize Center, AutoFarmer
	Sleep, timeout
	Gui,1:Destroy
	}
	
ModeBox(ByRef mode, ByRef name, ByRef x, ByRef y, ByRef w, ByRef h)
	{
	
	if ((inbattle == 1) && (mode != 1))
		{
		NewTempGui(1500, "Please Don't turn modes on while in combat", 10, 10, 210, 30)
		}	
	
	if (mode == 0) && (inbattle == 0)
		{
		gui = Turning On %name% Mode.
		NewTempGui(1000, gui, x, y, w, h)
		mode := 1
		} else if (mode == 1)
			{
			gui = Turning Off %name% Mode.
			NewTempGui(1000, gui, x, y, w, h)
			mode := 0
			}
	}
	
#!d::
if (on == 1)
	{
	ModeBox(devmode, "Developer", 10, 10, 144, 30)
	}
return

!l::
if (on == 1)
	{
	MsgBox, 1, AutoFarmer: Lore Mode, Please make sure you're standing next to the lore sigil when activating this mode.`n`nPress Ok to continue.
	ifMsgBox, ok
		{
		ModeBox(loremode, "Lore", 10, 10, 140, 30)
		}
	ifMsgBox, cancel
		{
		return
		}
	ifMsgBox, timeout
		{
		return
		}
	}
return

!d::
if (on == 1)
	{
	MsgBox, 1, AutoFarmer: Dual Mode, Please make sure that, when activating this mode two Wizard101 instances are open and that, when "Alt+Tab" is pressed it'll switch bewteen them.`n`nPress Ok to continue.
	ifMsgBox, ok
		{
		ModeBox(dualmode, "Dual", 10, 10, 120, 30)
		}
	ifMsgBox, cancel
		{
		return
		}
	}
return
		
!c::
if (on == 1)
	{
	ModeBox(commandmode, "Command", 10, 10, 144, 30)
	}
return

!s::
if (on == 1)
	{
	ModeBox(statsmode, "Statistic", 10, 10, 140, 30)
	}
return

!r::
if (on == 1)
	{
	ModeBox(responcemode, "Responce", 10, 10, 140, 30)
	}
return
	
!1::
if ((on == 1) && (inbattle == 1))
	{
	BlockInput, MouseMoveOff
	NewStaticGui("Please Select Boss Location.", 10, 10, 140, 30)
	KeyWait, LButton, D, 10
		If (Errorlevel = 0)
			{
			global BossChoosen = 1
			MouseGetPos, BossX, bossY
			Gui, 1:Destroy
			}
	BlockInput, MouseMove
	CenterMouse()
	}
return

!e::
if (on == 1)
	{
	ModeBox(loopmode, "Loop", 10, 10, 140, 30)
	}
return

!2::
if ((on == 1) && (inbattle == 1))
	{
	BlockInput, MouseMoveOff
	NewStaticGui("Please Select Hammer Location.", 10, 10, 140, 30)
	KeyWait, LButton, D, 10
		If (Errorlevel == 0)
			{
			Manual = 1
			MouseGetPos, ManualX, ManualY
			ImageSearch, schoolX, schoolY, ManualX - 75, ManualY - 75, ManualX + 75, ManualY + 75, *3 %A_WorkingDir%\storm\storm.png
			If (Errorlevel == 0)
				{
				hitter := 1
				hitschool := "storm"
				} else if (Errorlevel == 1)
					{
					ImageSearch, schoolX, schoolY, ManualX - 75, ManualY - 75, ManualX + 75, ManualY + 75, *3 %A_WorkingDir%\fire\fire.png
					if (Errorlevel == 0)
						{
						hitter := 2
						hitschool := "fire"
						} else if (Errorlevel == 1)
							{
							ImageSearch, schoolX, schoolY, ManualX - 75, ManualY - 75, ManualX + 75, ManualY + 75, *3 %A_WorkingDir%\myth\myth.png
							if (Errorlevel == 0)
								{
								hitter := 3
								hitschool := "myth"
								}
							}
					}
			Gui, 1:Destroy
			BlockInput, MouseMove
			CenterMouse()
			}

}
return

#3::
if ((on == 1) && (inbattle == 1))
	{
	BlockInput, MouseMoveOff
	NewStaticGui("Please Select New Player Location.", 10, 10, 140, 30)
	KeyWait, LButton, D, 10
		If (Errorlevel = 0)
			{
			global ManualPlayer := 1
			MouseGetPos, ManualPlayerX, ManualPlayerY
			Gui, 1:Destroy
			}	
	BlockInput, MouseMove
	CenterMouse()
	}
return

GuiClose:
Gui, Destroy
	
#2::
if (devmode == 1)
{
MsgBox,
( 
GENERAL:
InBattle:(%inbattle%)
Battles:(%battles%)
Round:(%roundnumber%) 
Player:(%player%)
Hammer:(%hitschool% (X:%hammerX% Y:%hitterY%)) 
Boss:(%BossChoosen%:(X:%BossX% Y:%BossY%))
Boosts(%boosts%:%boostlimit%)

CARDS: 
Sharpen:(%sharpen%) 
Potent:(%potent%)
Blade:(%blade%) 
Blade2:(%blade2%:(%bladetype%)) 
Balanceblade:(%blade3%)
Bladestorm:(%blade4%)
Convert(%convert%)
Trap:(%trap%)  
Trap2:(%trap2%:(%traptype%))
Trap3:(%trap3%)
Feint:(%feint%) 
Aura:(%aura%) 
Enchant:(%enchant%) 
Active Hits:(%hit4%:%hit3%:%hit2%:%hit1%) 
Tower:(%tower%)  
Reshuffle:(%reshuffle%)

     USED:
 F(%used2%)   pF(%used1%) 
B1(%Used12%) sB1(%Used11%)  
B2(%Used14%) sB2(%Used13%)
B3(%Used16%) sB3(%Used15%)
B4(%Used18%) sB4(%Used17%)
T1(%Used4%)  pT1(%Used3%)
T2(%Used6%)  pT2(%Used5%)
T3(%Used8%)  pT3(%Used7%)
T4(%Used10%) pT4(%Used9%)

MODES: 
Developer(%devmode%) Command(%commandmode%) 
Respond(%responsemode%) Dual(%dualmode%)
Lore(%loremode%)
)
}
return

CommandOff()
	{
	global
	if ((devmode == 1) && (commandmode == 1)) 
		{
		ImageSearch, offX, offY, 0, ScreenY * 2 - 25,  ScreenX / 2 + 20, A_ScreenHeight, *120 %A_WorkingDir%\resources\off.png
		if (ErrorLevel == 0) 
			{			
			Respond("Shutting Down.")
			ExitApp
			} else if (Errorlevel == 2)
				{
				ErrorBox("CommandOff", dir, title)
				}
		}
	}
	
CommandReload()
	{
	global
	if ((devmode == 1) && (commandmode == 1)) 
		{
		;Requires devmode to be on to reloaded script manually
		ImageSearch, relX, relY, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\rel.png
		if (ErrorLevel == 0) 
			{
			Respond("Reloading Script.")
			Reload
			} else if (Errorlevel == 2)
				{
				ErrorBox("CommandReload", dir, title)
				}
		}
	}

CommandHit()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, X, Y, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\PlayerHit.png
		if (Errorlevel == 0)
			{
			Respond("Okay, Ill OverRide The Automatic Battle Sequence.")
			if ((hit == 1) || (hit2 == 1) || (hit3 == 1) || (hit4 == 1))
				{
				if (hit4 == 1) && (BossChoosen = 1)
					{
					UseHit("hit4", hit4, hitschool)
					} else if (hit3 == 1)
						{
						UseHit("hit3", hit3, hitschool)
						} else if (hit2 == 1)
							{
							UseHit("hit2", hit2, hitschool)
							} else if (hit1 == 1)
								{
								UseHit("hit1", hit1, hitschool)
								} else 
									{
									Respond("It Seems There Are No Hits In Hand, I'll Pass Instead.")
									Click("pass", pass, "resources")
									}
				}
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandHit", dir, title)
					}
		}
	}
	
CommandPass()
	{	
	global
	if (commandmode == 1)
		{
		ImageSearch, PlayerPassX, PlayerPassY, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\PlayerPass.png
		if (ErrorLevel == 0)
			{
			Respond("Alright, Ill Pass Instead.")
			Mousemove, passX, passY, 5
			Click
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandPass", dir, title)
					return false
					} 
		}
	}
	
CommandWalk()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, walkX, walkY, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\walk.png
		if (ErrorLevel == 0) 
			{
			Respond("I'm Not A Dog, But Ill Do It Anyways")
			Send, {w Down}
			Sleep, 2000
			Send, {w Up}
			Sleep, %Ten%
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandWalk", dir, title)
					return false
					}
		}
	}
	
CommandEnter()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, enterX, enterY, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\enter.png
		if (ErrorLevel == 0) 
			{
			Respond("Entering Sigil. Make Sure You Have The Right Deck On.")
			Send, {x}
			Sleep, %Tick%
			Send, {x}
			Sleep, %Tick%
			Send, {x}
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandEnter", dir, title)
					return false
					}
		} 
	}
	
CommandAfk()
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, afkX, afkY, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\afk.png
		if (ErrorLevel == 0)
			{
			Respond("Okay, I'll Prevent Time Out Until Further Notice.")
			afk()
			return true
			} else if (Errorlevel == 1)
				{
				return false
				} else if (ErrorLevel == 2)
					{
					ErrorBox("CommandAfk", dir, title)
					return false
					}
		}
	}
	
CommandPort() 
	{
	global
	if (commandmode == 1)
		{
		ImageSearch, wordportX, wordportY, 0, ScreenY * 1.3, ScreenX / 3.7, ScreenY * 1.55, *120 %A_WorkingDir%\resources\wordport.png
		if (ErrorLevel == 0)
			{
		
			Send, {/}
			Sleep, %Tick%
			Send, {BS}
			Sleep, %Tick%
			Send, {Enter}
			Sleep, %Half%
			
			ImageSearch, checkX, checkY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\check.png
			if (Errorlevel == 0) 
				{
				Sleep, %Half%
				ImageSearch, nameX, nameY, 0, checkY - 20, checkX, checkY + 20, *3 %A_WorkingDir%\resources\name.png
				if (ErrorLevel == 0) 
					{		
					Mousemove, nameX + 30, nameY, 5
					s(100)
					Click
					
					s(2000)		
					ImageSearch, portX, portY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\port.png
					if (Errorlevel == 0) 
						{
						Mousemove, portX, portY, 5
						s(100)
						Click
						Sleep, %Half%
						
						ImageSearch, yesX, yesY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\yes.png
						if (Errorlevel == 0) 
							{
							Mousemove, yesX, yesY, 5
							s(100)
							Click
							Sleep, %Half%
							
							Respond("Initiating Teleportation Sequence.")
								
							ImageSearch, okX, okY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\ok.png
							if (Errorlevel == 0) 
								{
								Mousemove, okX, okY, 5
								s(100)
								Click
								
								Respond("Error Teleporting, Check If Ports Are On, Or If You're In A Dungeon.")
									
								}
							} else if ((Errorlevel == 1) && (devmode == 1))
								{
								Respond("Error Teleporting, Invalid Gui.")
								}
						} else if ((Errorlevel == 1) && (devmode == 1))
							{
							Respond("Error Teleporting, Invalid Gui.")
							}
					} else if ((Errorlevel == 1) && (devmode == 1))
						{
						Respond("Error Teleporting, Invalid Gui.")
						}
				} else if ((Errorlevel == 1) && (devmode == 1))
					{
					Respond("Error Teleporting, Invalid Gui.")
					}
			return true
			Sleep, %Ten%
			} else if (Errorlevel == 1)
				{
				return false
				} else if (Errorlevel == 2)
					{
					ErrorBox("CommandPort", dir, title)
					return false
					}
		}
	}

!0::
if (on = 1)
	{
	if (devmode = 1)
		{	
		if (inbattle = 0)
			{
			#InstallMouseHook
			#InstallKeybdHook
			CoordMode, Mouse, Window
			leftoffset := (A_ScreenWidth - 800) / 2
			topoffset := (A_ScreenHeight - 600) / 2
			up = 1
			left = 2
			right = 3
			down = 4
			Mousespeedfast = 5 ;Default is 5
			Mousespeedslow = 10 ;Default is 10
			Loading = 5100 ;Default is 5000
			Wait = 325 ;Default is 300
			Delay = 175 ;Default is 150
			Buffer = 10 ;Default is 10
			
			loop 
				{
				BlockInput, SendAndMouse
				BlockInput, Mousemove
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
				sleep, %Loading% - 1500a
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
			}
		}
	}

#`::
if (on = 1)
	{
	if (devmode = 1)
		{
		loop, 
			{
			click
			}
		}
	}
return

#Esc::
ExitApp
return

!Esc::
Reload
return