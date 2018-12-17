#1::

#NoEnv
#InstallMouseHook
#InstallKeybdHook

on = 1

MsgBox, 0, Loading..., Autofarmer will start checking for battles. ,0.5

battles = 0
BossChoosen = 0
afk = 0
commandmode = 0
dualmode = 0

;Sleep timings
Tick = 100
Buffer = 300
Half = 600
Second = 1100
Five = 5000
Ten = 10000

;Checks if in battle
TestRound:
loop,
{
	ImageSearch, roundX, roundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\roundfinish.png
	if ErrorLevel = 0
		{
		if (inbattle = 1)
			{
			battles++
			}
		if (commandmode = 1)
			{
			ImageSearch, walkX, walkY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\walk.png
			if ErrorLevel = 0
				{
				Send, {w Down}
				Sleep, %Second%
				Send, {w Up}
				Sleep, %Ten%
				}
			ImageSearch, enterX, enterY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\enter.png
			if ErrorLevel = 0
				{
				Send, {x}
				Sleep, %Tick%
				Send, {x}
				Sleep, %Tick%
				Send, {x}
				}
			ImageSearch, afkX, afkY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\afk.png
			if ErrorLevel = 0
				{
				if afk != 0 
					{
					afk = 0
					Send, {d}
					Send, {a}
					Sleep, %Ten%
					Goto, TestRound
					}
				Send, {a down}
				Sleep, %Tick%
				Send, {shift down}
				Sleep, %Tick%
				Send, {a up}
				Sleep, %Tick%
				Send, {shift up}
				afk = 1
				Sleep, %Ten%
				}
			;Auto Port code
			ImageSearch, wordportX, wordportY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\wordport.png
			if ErrorLevel = 0
				{
				Send, {/}
				Sleep, %Tick%
				Send, {BS}
				Sleep, %Tick%
				Send, {Enter}
				Sleep, %Half%
				ImageSearch, checkX, checkY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\check.png
				if Errorlevel = 0
					{
					Sleep, %Half%
					ImageSearch, nameX, nameY, 0, checkY - 20, checkX, checkY + 20, *3 %A_WorkingDir%\resources\name.png
					if ErrorLevel = 0
						{		
						Mousemove, nameX + 30, nameY, 5
						Click
						Sleep, %Half%
						ImageSearch, portX, portY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\port.png
						if Errorlevel = 0
							{
							Mousemove, portX, portY, 5
							Click
							Sleep, %Half%
							ImageSearch, yesX, yesY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\yes.png
							if Errorlevel = 0
								{
								Mousemove, yesX, yesY, 5
								Click
								Send, {r}
								Sleep, %Tick%
								SendInput {Raw}Teleporting.
								Sleep, %Tick%
								Send, {Enter}
								Sleep, %Second%
								ImageSearch, okX, okY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\ok.png
								if Errorlevel = 0
									{
									Mousemove, okX, okY, 5
									Click
									Send, {r}
									Sleep, %Half%
									SendInput {Raw}Couldn't Teleport.
									Send, {Enter}
									Sleep, %Half%
									}
								}
							}
						}
					}
				Sleep, %Ten%
				}		
			}
			
		inbattle = 0
		roundnumber = 0
		playerschoolpriority = 0
		Player = ""
		schoolpriority = 0
		school := ""
		hitter := 0
		hitschool = ""
		BossChoosen = 0
		sharp = 0 
		potent = 0
		blade = 0
		blade2 = 0
		blade3 = 0
		blade4 = 0
		trap = 0
		trap2 = 0
		feint = 0
		aura = 0
		enchant = 0 
		reshuffle = 0
		hit1 = 0
		hit2 = 0
		hit3 = 0
		hit4 = 0
		tower = 0  
		Used1 = 0
		Used2 = 0
		Used3 = 0
		Used4 = 0
		Used5 = 0
		Used6 = 0
		Used7 = 0
		Used8 = 0
		Used9 = 0
		Used10 = 0
		Used11 = 0
		Used12 = 0
		Used13 = 0
		Used14 = 0
		Used15 = 0
		}
	ImageSearch, startX, startY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\roundstart.png
	If ErrorLevel = 0
		{
		roundnumber++
		Goto, RoundStart
		}
}

RoundStart:
Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5

inbattle = 1

;Find the player
playerschoolpriority = 0
ImageSearch, playerX, playerY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\player.png
if (ErrorLevel = 0)
	{
	playerschoolpriority = 1
	player = "Wolf"
	} else if ErrorLevel = 1
		{
		ImageSearch, playerX, playerY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\player2.png
		if (Errorlevel = 0)
			{
			playerschoolpriority = 2
			player = "Alyssa"
			}
		} else {
			Goto, TestHammer
			}
		
;Find player school
if (playerschoolpriority >= 1)
	{
	SchoolTest:
	school = 0	
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\storm\storm.png
	if Errorlevel = 0
		{
		schoolpriority = 1
		school := "storm"
		Goto, TestHammer
		}
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\fire\fire.png
	if Errorlevel = 0
		{
		schoolpriority = 2
		school := "fire"
		Goto, TestHammer
		} 
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\myth\myth.png
	if Errorlevel = 0
		{
		schoolpriority = 3
		school := "myth"
		Goto, TestHammer
		}
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\life\life.png
	if Errorlevel = 0
		{
		schoolpriority = 4
		school := "life"
		Goto, TestHammer
		}
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\death\death.png
	if Errorlevel = 0
		{
		schoolpriority = 5
		school := "death"
		Goto, TestHammer
		}
	ImageSearch, schoolX, schoolY, playerX - 100, playerY - 100, playerX + 250, playerY + 250, *3 %A_WorkingDir%\balance\balance.png
	if Errorlevel = 0
		{
		schoolpriority = 6
		school := "balance"
		Goto, TestHammer
		}
	}
	
;Checks who's hammer
TestHammer:
hitter = 0
ImageSearch, hitterX, hitterY, 0, A_ScreenHeight / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\storm\storm.png
if (Errorlevel = 0) && (Manual != 1)
	{
	hitter := 1
	hitschool := "storm"
	} else if Errorlevel = 1
		{	
		ImageSearch, hitterX, hitterY, 0, A_ScreenHeight / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\fire\fire.png
		if (Errorlevel = 0) && (Manual != 1)
			{
			hitter := 2
			hitschool := "fire"
			} else if Errorlevel = 1
				{
				ImageSearch, hitterX, hitterY, 0, A_ScreenHeight / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\myth\myth.png
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
	blade2 = 0
	ImageSearch, blade2X, blade2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\elementalblade.png
	if ErrorLevel = 0
		{
		bladetype := "elementalblade.png"
		blade2 = 1
		}
	trap2 = 0
	ImageSearch, trap2X, trap2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\elementaltrap.png
	if ErrorLevel = 0
		{
		traptype := "elementaltrap.png"
		trap2 = 1
		}
	} else if (hitter >= 3)
		{
		blade2 = 0
		ImageSearch, blade2X, blade2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\spiritblade.png
		if ErrorLevel = 0
			{
			bladetype := "spiritblade.png"
			blade2 = 1
			}
		trap2 = 0
		ImageSearch, trap2X, trap2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\spirittrap.png
		if ErrorLevel = 0
			{
			traptype := "spirittrap.png"
			trap2 = 1
			}
		} 	
	
if (Manual = 1)
	{
	hammerX = %ManualX%
    hammerY = %ManualY%
	}
	
;Enchants
enchant = 0 
ImageSearch, enchantX, enchantY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\epic.png
If (ErrorLevel = 0) && (hitter != 0)
	{
	enchant = 4
	} else if Errorlevel = 1
		{
		ImageSearch, enchantX, enchantY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\colossal.png
		if ErrorLevel = 0
			{
			enchant = 3
			} else if ErrorLevel = 1
				{
				ImageSearch, enchantX, enchantY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\gargantuan.png
				if ErrorLevel = 0
					{
					enchant = 2
					} else if Errorlevel = 1 
						{
						ImageSearch, enchantX, enchantY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\life\enchant.png
						if ErrorLevel = 0
							{
							enchant = 1
							} 
						}
				} 
		}

;Finds cards avaliable
sharp = 0
ImageSearch, sharpX, sharpY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\sharpen.png
If ErrorLevel = 0
	{
	sharp = 1
	}
potent = 0
ImageSearch, potentX, potentY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\potent.png
If ErrorLevel = 0
	{
	potent = 1
	}
pass = 0
ImageSearch, passX, passY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\pass.png
If ErrorLevel = 0
	{
	pass = 1
    }
blade = 0
ImageSearch, bladeX, bladeY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%hitschool%\blade.png
if ErrorLevel = 0
	{
	blade = 1
	} 
blade3 = 0
ImageSearch, blade3X, blade3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\blade3.png
if ErrorLevel = 0
	{
	blade3 = 1
	} 
blade4 = 0
ImageSearch, blade4X, blade4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\blade4.png
if ErrorLevel = 0
	{
	blade4 = 1
	} 
trap = 0
ImageSearch, trapX, trapY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%hitschool%\trap.png
if ErrorLevel = 0
	{
	trap = 1
	}
trap3 = 0
ImageSearch, trap3X, trap3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\trap.png
if ErrorLevel = 0
	{
	trap3 = 1
	} 
aura = 0
ImageSearch, auraX, auraY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\aura.png
if ErrorLevel = 0
	{
	aura = 1
	} 
tower = 0
ImageSearch, towerX, towerY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\tower.png
if ErrorLevel = 0
	{
	tower = 1
	}
reshuffle = 0
ImageSearch, reshuffleX, reshuffleY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\reshuffle.png
if ErrorLevel = 0
	{
	reshuffle = 1
	}
feint = 0
ImageSearch, feintX, feintY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\feint.png
if ErrorLevel = 0
	{
	feint = 1
	}
	
;Finds hit specific cards
if (schoolpriority >= 1) && (hitter != 0)
{
	hit4 = 0
	ImageSearch, hit4X, hit4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit4.png
	if ErrorLevel = 0
		{
		hit4 = 1
		}
	hit3 = 0
	ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit3.png
	if ErrorLevel = 0
		{
		hit3 = 1
		}
	hit2 = 0
	ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
	if ErrorLevel = 0
		{
		hit2 = 1
		}
	hit1 = 0
	ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
	if ErrorLevel = 0
		{
		hit1 = 1
		}
}	

;Manual Hit
PlayerHit:
if (commandmode = 1)
{
	ImageSearch, PlayerHitX, PlayerHitY, 0, 0, A_ScreenWidth, A_ScreenHeight, *1 %A_WorkingDir%\resources\PlayerHit.png
	if (ErrorLevel = 0) && (commandmode = 1)
		{
		if (responcemode = 1)
			{
			BlockInput, Send
			Send, {r}
			Sleep, %Half%
			SendInput {Raw}Okay, I'll Try To Override The Auto Sequence And Use A Hit Instead.
			Send, {Enter}
			Sleep, %Half%
			}
		if (BossChoosen != 0) && (enchant >= 1) && (hit4 = 1)
			{
			Mousemove, enchantX, enchantY, 5
			Click
			Mousemove, hit4X, hit4Y, 5
			Click
			Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
			Sleep, %Half%
			ImageSearch, hit4X, hit4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit4.png
			Sleep, %Half%
			Mousemove, hit4X, hit4Y, 5
			Click
			Mousemove, BossX, BossY, 5
			Click
			} else if (BossChoosen = 1) && (hit4 = 1) 
				{
				Mousemove, hit4X, hit4Y, 5
				Click
				Sleep, %Buffer%
				Mousemove, BossX, BossY, 5
				Click
				} else if (enchant >= 1) && (hit3 = 1)
					{
					Mousemove, enchantX, enchantY, 5
					Click
					Mousemove, hit3X, hit3Y, 5
					Click
					Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
					Sleep, %Half%
					ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit3.png
					Sleep, %Half%
					Mousemove, hit3X, hit3Y, 5
					Click
					} else if (enchant = 0) && (hit3 = 1)
						{
						Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
						Sleep, %Half%
						ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 	%A_WorkingDir%\%school%\hit3.png
						Sleep, %Half%
						Mousemove, hit3X, hit3Y, 5
						Click
						} else if (enchant >= 1) && (hit2 = 1)
							{
							Mousemove, enchantX, enchantY, 5
							Click
							Mousemove, hit2X, hit2Y, 5
							Click
							Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
							Sleep, %Half%
							ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
							Sleep, %Half%
							Mousemove, hit2X, hit2Y, 5
							Click
							} else if (enchant = 0) && (hit2 = 1)
								{
								Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
								Sleep, %Half%
								ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
								Sleep, %Half%
								Mousemove, hit2X, hit2Y, 5
								Click
								} else if (enchant >= 1) && (hit1 = 1)
									{
									Mousemove, enchantX, enchantY, 5
									Click
									Mousemove, hit1X, hit1Y, 5
									Click
									Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
									Sleep, %Half%
									ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
									Sleep, %Half%
									Mousemove, hit1X, hit1Y, 5
									Click
									} else if (enchant = 0) && (hit1 = 1)
										{
										Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
										Sleep, %Half%
										ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
										Sleep, %Half%
										Mousemove, hit1X, hit1Y, 5
										Click
										} else {
											if (responcemode = 1)
												{
												BlockInput, Send
												Send, {r}
												Sleep, %Half%
												SendInput {Raw}It Seems I Have No Available Hits. Ill Pass Instead.
												Send, {Enter}
												Sleep, %Half%
												}
											Mousemove, PassX, PassY, 5
											Click
											}
	Goto, TestRound
	}
}

;Manual Pass
PlayerPass:
if (commandmode = 1)
{
	ImageSearch, PlayerPassX, PlayerPassY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\PlayerPass.png
	if (ErrorLevel = 0)
		{
		if (responcemode = 1)
			{
			BlockInput, Send
			Send, {r}
			Sleep, %Half%
			SendInput {Raw}Alright. Ill pass instead.
			Send, {Enter}
			Sleep, %Half%
			}
		Mousemove, passX, passY, 5
		Click
		Goto, TestRound
		}
}
		
Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
	
;Automatic Battle code
if (BossChoosen != 0) && (potent = 1) && (feint = 1)  && (Used1 != 1)
	{
	Mousemove,  potentX, potentY, 5
	Click
	Mousemove,  feintX, feintY, 5
	Click
	Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
	Sleep, %Second%
	ImageSearch, feintX, feintY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\feint.png
	Sleep, %Half%
	Mousemove,  feintX, feintY, 5
	Click
	Mousemove, bossX, BossY, 5
	Sleep, %Tick%
	Click
	Used1 = 1
	} else if (BossChoosen != 0) && (potent = 0) && (feint = 1) && (Used2 != 1)
		{
		Mousemove,  feintX, feintY, 5
		Click
		Sleep, %Buffer%
		Mousemove, bossX, BossY, 5
		Sleep, %Tick%
		Click
		Used2 = 1
		}  else if (sharp = 1) && (blade2 = 1) && (Used3 != 1) 
			{	
			Mousemove, sharpX, sharpY, 5
			Click
			Sleep, %Tick%
			Mousemove, blade2X, blade2Y, 5
			Click
			Sleep, %Tick%
			Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
			Sleep, %Second%
			ImageSearch, blade2X, blade2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\%bladetype%
			Sleep, %Half%
			Mousemove, blade2X, blade2Y, 5
			Click
			Sleep, %Tick%
			Mousemove, hammerX, hammerY, 5
			Click
			Sleep, %Tick%
			Used3 = 1
			} else if (sharp = 0) && (blade2 = 1) && (Used4 != 1)
				{
				Mousemove, blade2X, blade2Y, 5
				Click
				Sleep, %Buffer%
				Mousemove, hammerX, hammerY, 5
				Click
				Used4 = 1
				} else if (sharp = 1) && (blade3 = 1) && (Used5 != 1) 
					{	
					Mousemove, sharpX, sharpY, 5
					Click
					Sleep, %Tick%
					Mousemove, blade3X, blade3Y, 5
					Click
					Sleep, %Tick%
					Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
					Sleep, %Second%
					ImageSearch, blade3X, blade3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\blade3.png
					Sleep, %Half%
					Mousemove, blade3X, blade3Y, 5
					Click
					Sleep, %Tick%
					Mousemove, hammerX, hammerY, 5
					Click
					Used5 = 1
					} else if (sharp = 0) && (blade3 = 1) && (Used6 != 1)
						{
						Mousemove, blade3X, blade3Y, 5
						Click
						Sleep, %Buffer%
						Mousemove, hammerX, hammerY, 5
						Click
						Used6 = 1
						} else if (sharp = 1) && (blade4 = 1) && (Used7 != 1) 
							{	
							Mousemove, sharpX, sharpY, 5
							Click
							Sleep, %Tick%
							Mousemove, blade4X, blade4Y, 5
							Click
							Sleep, %Tick%
							Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
							Sleep, %Second%
							ImageSearch, blade4X, blade4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\blade4.png
							Sleep, %Half%
							Mousemove, blade4X, blade4Y, 5
							Click
							Used7 = 1
							} else if (hitter >= 1) && (sharp = 0) && (blade4 = 1) && (Used8 != 1)
								{
								Mousemove, blade4X, blade4Y, 5
								Click
								Sleep, %Buffer%
								Used8 = 1 
								} else if (hitter >= 1) && (sharp = 1) && (blade = 1) && (Used9 != 1)
									{
									Mousemove, sharpX, sharpY, 5
									Click
									Sleep, %Tick%
									Mousemove, bladeX, bladeY, 5
									Click
									Sleep, %Tick%
									Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
									Sleep, %Second%
									ImageSearch, bladeX, bladeY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%hitschool%\blade.png
									Sleep, %Half%
									Mousemove, bladeX, bladeY, 5
									Click
									Sleep, %Tick%
									Mousemove, hammerX, hammerY, 5
									Click
									Used9 = 1
									} else if (sharp = 0) && (blade = 1)
										{
										Mousemove, bladeX, bladeY, 5
										Click
										Sleep, %Buffer%
										Mousemove, hammerX, hammerY, 5
										Click
										} else if (BossChoosen = 1) && (potent = 1) && (trap = 1) && (Used10 != 1)
											{
											Mousemove,  potentX, potentY, 5
											Click
											Sleep, %Tick%
											Mousemove,  trapX, trapY, 5
											Click
											Sleep, %Tick%
											Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
											Sleep, %Second%
											ImageSearch, trapX, trapY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\trap.png
											Sleep, %Half%
											Mousemove,  trapX, trapY, 5
											Click
											Sleep, %Tick%
											Mousemove, bossX, BossY, 5
											Click
											Sleep, %Tick%
											Used10 = 1
											} else if (BossChoosen = 1) && (potent = 0) && (trap = 1) && (Used11 != 1)
												{
												Mousemove,  trapX, trapY, 5
												Click
												Sleep, %Buffer%
												Mousemove, bossX, BossY, 5
												Click
												Used11 = 1
												} else if (BossChoosen = 1) && (potent = 1) && (trap2 = 1)  && (Used12 != 1)
													{
													Mousemove,  potentX, potentY, 5
													Click
													Sleep, %Tick%
													Mousemove,  trap2X, trap2Y, 5
													Click
													Sleep, %Tick%
													Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
													Sleep, %Second%
													ImageSearch, trap2X, trap2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\%traptype%
													Sleep, %Half%
													Mousemove,  trap2X, trap2Y, 5
													Click
													Sleep, %Tick%
													Mousemove, bossX, BossY, 5
													Click
													Used12 = 1
													} else if (BossChoosen = 1) && (potent = 0) && (trap2 = 1) && (Used13 != 1)
														{
														Mousemove,  trap2X, trap2Y, 5
														Click
														Sleep, %Buffer%
														Mousemove, bossX, BossY, 5
														Click
														Used13 = 1
														} else if (BossChoosen = 1) && (potent = 1) && (trap3 = 1)  && (Used14 != 1)
															{
															Mousemove,  potentX, potentY, 5
															Click
															Sleep, %Tick%
															Mousemove,  trap3X, trap3Y, 5
															Click
															Sleep, %Tick%
															Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
															Sleep, %Second%
															ImageSearch, trap3X, trap3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\trap.png
															Sleep, %Half%
															Mousemove,  trap3X, trap3Y, 5
															Click
															Sleep, %Tick%
															Mousemove, bossX, BossY, 5
															Click
															Used14 = 1
															} else if (BossChoosen = 1) && (potent = 0) && (trap3 = 1) && (Used15 != 1)
																{
																Mousemove,  trap3X, trap3Y, 5
																Click
																Sleep, %Buffer%
																Mousemove, bossX, BossY, 5
																Click
																Used15 = 1 
																} else if (aura = 1)
																	{
																	Mousemove, auraX, auraY, 5
																	Click
																	} else if (BossChoosen = 1) && (enchant >= 1) && (hit4 = 1)
																		{
																		Mousemove, enchantX, enchantY, 5
																		Click
																		Mousemove, hit4X, hit4Y, 5
																		Click
																		Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																		Sleep, %Second%
																		ImageSearch, hit4X, hit4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit4.png
																		Sleep, %Half%
																		Mousemove, hit4X, hit4Y, 5
																		Click
																		Mousemove, BossX, BossY, 5
																		Click
																		} else if (BossChoosen = 1) && (enchant = 0) && (hit4 = 1) 
																			{
																			Mousemove, hit4X, hit4Y, 5
																			Click
																			Sleep, %Buffer%
																			Mousemove, BossX, BossY, 5
																			Click
																			} else if (enchant >= 1) && (hit3 = 1)
																				{
																				Mousemove, enchantX, enchantY, 5
																				Click
																				Mousemove, hit3X, hit3Y, 5
																				Click
																				Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																				Sleep, %Second%
																				ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit3.png
																				Sleep, %Half%
																				Mousemove, hit3X, hit3Y, 5
																				Click
																				} else if (enchant = 0) && (hit3 = 1)
																					{
																					Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																					Sleep, %Second%
																					ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 	%A_WorkingDir%\%school%\hit3.png
																					Sleep, %Half%
																					Mousemove, hit3X, hit3Y, 5
																					Click
																					} else if (enchant >= 1) && (hit2 = 1)
																						{
																						Mousemove, enchantX, enchantY, 5
																						Click
																						Mousemove, hit2X, hit2Y, 5
																						Click
																						Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																						Sleep, %Second%
																						ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
																						Sleep, %Half%
																						Mousemove, hit2X, hit2Y, 5
																						Click
																						} else if (enchant = 0) && (hit2 = 1)
																							{
																							Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																							Sleep, %Second%
																							ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
																							Sleep, %Half%
																							Mousemove, hit2X, hit2Y, 5
																							Click
																							} else if (enchant >= 1) && (hit1 = 1)
																								{
																								Mousemove, enchantX, enchantY, 5
																								Click
																								Mousemove, hit1X, hit1Y, 5
																								Click
																								Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																								Sleep, %Second%
																								ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
																								Sleep, %Half%
																								Mousemove, hit1X, hit1Y, 5
																								Click
																								} else if (enchant = 0) && (hit1 = 1)
																									{
																									Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																									Sleep, %Second%
																									ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
																									Sleep, %Half%
																									Mousemove, hit1X, hit1Y, 5
																									Click
																									} else if (tower = 1)
																										{
																										Mousemove, towerX, towerY, 5
																										Click
																										Mousemove, hammerX, hammerY, 5
																										Click
																										} else if (reshuffle = 1)
																											{
																											Mousemove, reshuffleX, reshuffleY, 5
																											Click
																											Mousemove, playerX, playerY, 5
																											Click
																											} else 
																												{
																												Mousemove, passX, passY, 5
																												Click
																												}
																												
Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5

if (commandmode = 1)
{
	loop, 10
	{
	Sleep, %Tick%
	ImageSearch, PlayerHitX, PlayerHitY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\PlayerHit.png
	If Errorlevel = 0
		{
		Click
		Goto, PlayerHit
		}
	ImageSearch, PlayerPassX, PlayerPassY, 0, 0, A_ScreenWidth, A_ScreenHeight, *100 %A_WorkingDir%\resources\PlayerPass.png
	If Errorlevel = 0
		{
		Click
		Goto, PlayerPass
		}
	}
}
if (dualmode = 1)
	{
	Send, {Alt down}
	Sleep, %Tick%
	Send, {Tab down}
	Sleep, %Tick%
	Send, {Alt up}
	Sleep, %Tick%
	Send, {Tab up}
	}

Goto, TestRound

Esc::Reload
#Esc::ExitApp
	
!q::
if (on = 1)

	if (responcemode = 0)
		{
		Gui,5:Add, Text, x10 y9 w140 h30 , Turning Responce Mode On...
		Gui,5:Show,, New GUI Window
		responcemode = 1
		Sleep, 1000
		Gui, 5:Destroy
		return
		} else if (responcemode = 1)
			{
			Gui,5:Add, Text, x10 y9 w140 h30 , Turning Responce Mode Off...
			Gui,5:Show,, New GUI Window
			responcemode = 0
			Sleep, 1000
			Gui, 4:Destroy
			return
			}
	return
	
!w::
if (on = 1)
{
	if (dualmode = 0)
		{
		Gui,4:Add, Text, x10 y9 w140 h30 , Turning Dual Mode On...
		Gui,4:Show,, New GUI Window
		dualmode = 1
		Sleep, 1000
		Gui, 4:Destroy
		return
		} else if (dualmode = 1)
			{
			Gui,4:Add, Text, x10 y9 w140 h30 , Turning Dual Mode Off...
			Gui,4:Show,, New GUI Window
			dualmode = 0
			Sleep, 1000
			Gui, 4:Destroy
			return
			}
	return
}
	
!e::
if (on = 1)
{
	if (commandmode = 0)
		{
		Gui,2:Add, Text, x10 y9 w140 h30 , Turning Command Mode On...
		Gui,2:Show,, New GUI Window
		commandmode = 1
		Sleep, 1000
		Gui, 2:Destroy
		return
		} else if (commandmode = 1)
			{
			Gui,2:Add, Text, x10 y9 w140 h30 , Turning Command Mode Off...
			Gui,2:Show,, New GUI Window
			commandmode = 0
			Sleep, 1000
			Gui, 2:Destroy
			return
			}
	return	
}	
		
!1::
if (on = 1)
{
	Gui,3:Add, Text, x10 y9 w140 h30 , Please Select Boss Position
	Gui,3:Show,, New GUI Window
	KeyWait, LButton, D, 10
		If Errorlevel = 0
			{
			BossChoosen = 1
			MouseGetPos, BossX, bossY
			Gui, 3:Destroy
			return
			}
	return
}
		
!2::
if (on = 1)
{
	Gui,1:Add, Text, x10 y9 w140 h30 , Please Select New Hammer Location
	Gui,1:Show,, New GUI Window
	KeyWait, LButton, D, 10
		If Errorlevel = 0
			{
			Manual = 1
			MouseGetPos, ManualX, ManualY
			ImageSearch, schoolX, schoolY, ManualX - 75, ManualY - 75, ManualX + 75, ManualY + 75, *3 %A_WorkingDir%\storm\storm.png
			If Errorlevel = 0
				{
				hitter := 1
				hitschool := "storm"
				} Else If Errorlevel = 1
					{
					ImageSearch, schoolX, schoolY, ManualX - 75, ManualY - 75, ManualX + 75, ManualY + 75, *3 %A_WorkingDir%\fire\fire.png
					If Errorlevel = 0
						{
						hitter := 2
						hitschool := "fire"
						} Else If Errorlevel = 1
							{
							ImageSearch, schoolX, schoolY, ManualX - 75, ManualY - 75, ManualX + 75, ManualY + 75, *3 %A_WorkingDir%\myth\myth.png
							If Errorlevel = 0
								{
								hitter := 3
								hitschool := "myth"
								}
						}
			}
			Gui, 1:Destroy
			return
			}
	return
}

GuiClose:
Gui, Destroy
	
!3::
;Auto Pet Trainer

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
Bufer = 10 ;Default is 10

loop {
  BlockInput, SendAndMouse
  BlockInput, Mousemove
  Sleep, %Bufer%
  send, x
  Sleep, %Bufer%
  send, x
  Sleep, %Bufer%
  Mousemove, 625 + leftoffset, 470 + topoffset, %Mousespeedfast%
  Click
  Sleep, %Bufer%
  Mousemove, 615 + leftoffset, 575 + topoffset, %Mousespeedfast%
  Click
  sleep, %Bufer%
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
    sleep, %Bufer%
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
  Sleep, %Buffer%
  Mousemove, 635 + leftoffset, 540 + topoffset, %Mousespeedfast%
  Click
  sleep, %Delay%
  Mousemove, 180 + leftoffset, 570 + topoffset, %Mousespeedfast%
  Click
  Mousemove, A_ScreenWidth/2, A_ScreenHeight/2, %Mousespeedslow%
  sleep, %Loading%
  BlockInput, Off
}
	
#`::
MsgBox,
( 
InBattle:(%inbattle%)
Battles:(%battles%)
Round:(%roundnumber%) 
Player:(%player% %school% (X:%playerX% Y:%playerY%))
Hammer:(%hitschool% (X:%hammerX% Y:%hitterY%)) 
Boss:(%BossChoosen%:(X:%BossX% Y:%BossY%))
Sharp:(%sharp%) 
Potent:(%potent%)
Blade:(%blade%) 
Blade2:(%blade2%:(%bladetype%)) 
Balanceblade:(%blade3%)
Bladestorm:(%blade4%)
Trap:(%trap%)  
Trap2:(%trap2%:(%traptype%))
Feint:(%feint%) 
Aura:(%aura%) 
Enchant:(%enchant%) 
Active Hits:(%hit4%:%hit3%:%hit2%:%hit1%) 
Tower:(%tower%)  
Reshuffle: (%reshuffle%)
Used:(sF(%Used1%):F(%Used2%):sB2(%Used3%):B2(%Used4%):sB3(%Used5%):B3(%Used6%):sB4(%Used7%):B4(%Used8%))
)