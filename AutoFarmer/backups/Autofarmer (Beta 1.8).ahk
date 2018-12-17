#1::

#NoEnv
#InstallMouseHook
#InstallKeybdHook

MsgBox, 0, Loading..., Autofarmer will start checking for battles. ,0.5

roundnumber = 0
battles = 0
inbattle = 0

;Checks if in battle
TestRound:
loop,
{
ImageSearch, roundX, roundY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\roundfinish.png
if ErrorLevel = 0
	{
	inbattle = 0
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
	if (inbattle = 1)
		{
		battles++
		}
	}
roundnumber = 0
ImageSearch, startX, startY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\roundstart.png
If ErrorLevel = 0
	{
	roundnumber++
	Goto, RoundStart
	}
sleep, 100
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
		}
		
;Find player school
if playerschoolpriority >= 1
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
	;Checks who's hammer
	TestHammer:
	hitter = 0
	ImageSearch, hitterX, hitterY, 0, A_ScreenHeight / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\storm\storm.png
	if Errorlevel = 0
		{
		hitpriority = 1
		hitter := 1
		hitschool := "storm"
		}
	if Errorlevel = 1
		{	
		ImageSearch, hitterX, hitterY, 0, A_ScreenHeight / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\fire\fire.png
		if Errorlevel = 0
			{
			hitpriority = 2
			hitter := 2
			hitschool := "fire"
			}
		if Errorlevel = 1
			{
			ImageSearch, hitterX, hitterY, 0, A_ScreenHeight / 2, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\myth\myth.png
			if Errorlevel = 0
				{
				hitpriority = 3
				hitter := 3
				hitschool := "myth"
				}
			} 
		}
	}
	
Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5

if (hitter <= 3)
	{
	hammerX = %hitterX%
	hammerY = %hitterY%
	}
	
if (Manual = 1)
	{
	hammerX = %ManualX%
    hammerY = %ManualY%
	}
	
;Enchants
enchant = 0 
ImageSearch, enchantX, enchantY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\epic.png
If ErrorLevel = 0
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
ImageSearch, bladeX, bladeY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\blade.png
if ErrorLevel = 0
	{
	blade = 1
	} 
trap = 0
ImageSearch, trapX, trapY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\trap.png
if ErrorLevel = 0
	{
	trap = 1
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
feint = 0
ImageSearch, feintX, feintY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\feint.png
if ErrorLevel = 0
	{
	feint = 1
	}
	
	
If hitpriority < 3
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
	} else if hitpriority >= 3 
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
	
;Finds hit specific cards
if (schoolpriority <= 6)
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
ImageSearch, PlayerHitX, PlayerHitY, 0, 0, A_ScreenWidth, A_ScreenHeight, *145 %A_WorkingDir%\resources\PlayerHit.png
if ErrorLevel = 0
	{
	BlockInput, Send
	Send, {Enter}
	Sleep, 100
	;SendInput {Raw}Okay, I'll Try Override The Auto Sequence And Use A Hit Instead.
	Send, {Enter}
	sleep, 200
	if (BossChoosen = 1) && (enchant >= 1) && (hit4 = 1)
		{
		Mousemove, enchantX, enchantY, 5
		Click
		Mousemove, hit4X, hit4Y, 5
		Click
		Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
		Sleep, 400
		ImageSearch, hit4X, hit4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit4.png
		Sleep, 400
		Mousemove, hit4X, hit4Y, 5
		Click
		Mousemove, BossX, BossY, 5
		Click
		} else if (BossChoosen = 1) && (hit4 = 1) 
			{
			Mousemove, hit4X, hit4Y, 5
			Click
			Sleep, 200
			Mousemove, BossX, BossY, 5
			Click
			} else if (enchant >= 1) && (hit3 = 1)
				{
				Mousemove, enchantX, enchantY, 5
				Click
				Mousemove, hit3X, hit3Y, 5
				Click
				Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
				Sleep, 400
				ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit3.png
				Sleep, 400
				Mousemove, hit3X, hit3Y, 5
				Click
				} else if (hit3 = 1)
					{
					Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
					Sleep, 400
					ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 	%A_WorkingDir%\%school%\hit3.png
					Sleep, 400
					Mousemove, hit3X, hit3Y, 5
					Click
					} else if (enchant >= 1) && (hit2 = 1)
						{
						Mousemove, enchantX, enchantY, 5
						Click
						Mousemove, hit2X, hit2Y, 5
						Click
						Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
						sleep, 400
						ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
						Sleep, 400
						Mousemove, hit2X, hit2Y, 5
						Click
						} else if (hit2 = 1)
							{
							Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
							Sleep, 400
							ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
							Sleep, 400
							Mousemove, hit2X, hit2Y, 5
							Click
							} else if (enchant >= 1) && (hit1 = 1)
								{
								Mousemove, enchantX, enchantY, 5
								Click
								Mousemove, hit1X, hit1Y, 5
								Click
								Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
								Sleep, 400
								ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
								Sleep, 400
								Mousemove, hit1X, hit1Y, 5
								Click
								} else if (hit1 = 1)
									{
									Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
									Sleep, 400
									ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
									Sleep, 400
									Mousemove, hit1X, hit1Y, 5
									Click
									} else {
										BlockInput, Send
										Send, {Enter}
										Sleep, 400
										;SendInput {Raw}It Seems I Have No Available Hits. Ill Pass Instead.
										Send, {Enter}
										sleep, 400
										Mousemove, PassX, PassY, 5
										Click
										}
Goto, TestRound
} 

;Manual Pass
PlayerPass:
ImageSearch, PlayerPassX, PlayerPassY, 0, 0, A_ScreenWidth, A_ScreenHeight, *145 %A_WorkingDir%\resources\PlayerPass.png
if ErrorLevel = 0
	{
	Send, {Enter}
	Sleep, 400
	;SendInput {Raw}Alright.
	Send, {Enter}
	sleep, 400
	PlayerPass = 1
	Mousemove, passX, passY, 5
	Click
	Goto, TestRound
	}
	
Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
	
;Automatic Battle code	
if (BossChoosen = 1) && (potent = 1) && (feint = 1)  && (Used1 != 1)
	{
	Mousemove,  potentX, potentY, 5
	Click
	Mousemove,  feintX, feintY, 5
	Click
	Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
	sleep, 400
	ImageSearch, feintX, feintY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\feint.png
	Sleep, 400
	Mousemove,  feintX, feintY, 5
	Click
	Mousemove, bossX, BossY, 5
	Click
	Used1 = 1
	} else if (BossChoosen = 1) && (feint = 1) && (Used2 != 1)
		{
		Mousemove,  feintX, feintY, 5
		Click
		sleep, 200
		Mousemove, bossX, BossY, 5
		Click
		Used2 = 1
		} else if (sharp = 1) && (blade2 = 1) && (Used3 != 1) 
			{	
			Mousemove, sharpX, sharpY, 5
			Click
			Mousemove, blade2X, blade2Y, 5
			Click
			Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
			sleep, 400
			ImageSearch, blade2X, blade2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\%bladetype%
			sleep, 400
			Mousemove, blade2X, blade2Y, 5
			Click
			Mousemove, hammerX, hammerY, 5
			Click
			Used3 = 1
			} else if (blade2 = 1) && (Used4 != 1)
				{
				Mousemove, blade2X, blade2Y, 5
				Click
				Sleep, 200
				Mousemove, hammerX, hammerY, 5
				Click
				Used4 = 1
				} else if (sharp = 1) && (blade = 1) && (Used5 != 1)
					{
					Mousemove, sharpX, sharpY, 5
					Click
					Mousemove, bladeX, bladeY, 5
					Click
					Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
					sleep, 400
					ImageSearch, bladeX, bladeY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\blade.png
					sleep, 400
					Mousemove, bladeX, bladeY, 5
					Click
					Mousemove, hammerX, hammerY, 5
					Click
					Used5 = 1
					} else if (blade = 1) && (Used4 != 1)
						{
						Mousemove, bladeX, bladeY, 5
						Click
						Sleep, 200
						Mousemove, hammerX, hammerY, 5
						Click
						Used4 = 1
						} else if (BossChoosen = 1) && (potent = 1) && (trap = 1) && (Used6 != 1)
							{
							Mousemove,  potentX, potentY, 5
							Click
							Mousemove,  trapX, trapY, 5
							Click
							Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
							Sleep, 400
							ImageSearch, trapX, trapY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\trap.png
							Sleep, 400
							Mousemove,  trapX, trapY, 5
							Click
							Mousemove, bossX, BossY, 5
							Click
							Used6 = 1
							} else if (BossChoosen = 1) && (trap = 1) && (Used7 != 1)
								{
								Mousemove,  trapX, trapY, 5
								Click
								Sleep, 200
								Mousemove, bossX, BossY, 5
								Click
								Used7 = 1
								} else if (BossChoosen = 1) && (potent = 1) && (trap2 = 1)  && (Used8 != 1)
									{
									Mousemove,  potentX, potentY, 5
									Click
									Mousemove,  trap2X, trap2Y, 5
									Click
									Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
									Sleep, 400
									ImageSearch, trap2X, trap2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\%traptype%
									Sleep, 400
									Mousemove,  trap2X, trap2Y, 5
									Click
									Mousemove, bossX, BossY, 5
									Click
									Used8 = 1
									} else if (BossChoosen = 1) && (trap2 = 1) && (Used9 != 1)
										{
										Mousemove,  trap2X, trap2Y, 5
										Click
										Sleep, 200
										Mousemove, bossX, BossY, 5
										Click
										Used9 = 1
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
												Sleep, 400
												ImageSearch, hit4X, hit4Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit4.png
												Sleep, 400
												Mousemove, hit4X, hit4Y, 5
												Click
												Mousemove, BossX, BossY, 5
												Click
												} else if (BossChoosen = 1) && (hit4 = 1) 
													{
													Mousemove, hit4X, hit4Y, 5
													Click
													Sleep, 200
													Mousemove, BossX, BossY, 5
													Click
													} else if (enchant >= 1) && (hit3 = 1)
														{
														Mousemove, enchantX, enchantY, 5
														Click
														Mousemove, hit3X, hit3Y, 5
														Click
														Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
														Sleep, 400
														ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit3.png
														Sleep, 400
														Mousemove, hit3X, hit3Y, 5
														Click
														} else if (hit3 = 1)
															{
															Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
															Sleep, 400
															ImageSearch, hit3X, hit3Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 	%A_WorkingDir%\%school%\hit3.png
															Sleep, 400
															Mousemove, hit3X, hit3Y, 5
															Click
															} else if (enchant >= 1) && (hit2 = 1)
																{
																Mousemove, enchantX, enchantY, 5
																Click
																Mousemove, hit2X, hit2Y, 5
																Click
																Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																sleep, 400
																ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
																Sleep, 400
																Mousemove, hit2X, hit2Y, 5
																Click
																} else if (hit2 = 1)
																	{
																	Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																	Sleep, 400
																	ImageSearch, hit2X, hit2Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit2.png
																	Sleep, 400
																	Mousemove, hit2X, hit2Y, 5
																	Click
																	} else if (enchant >= 1) && (hit1 = 1)
																		{
																		Mousemove, enchantX, enchantY, 5
																		Click
																		Mousemove, hit1X, hit1Y, 5
																		Click
																		Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																		Sleep, 400
																		ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
																		Sleep, 400
																		Mousemove, hit1X, hit1Y, 5
																		Click
																		} else if (hit1 = 1)
																			{
																			Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5
																			Sleep, 400
																			ImageSearch, hit1X, hit1Y, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\%school%\hit1.png
																			Sleep, 400
																			Mousemove, hit1X, hit1Y, 5
																			Click
																			} else if (tower = 1)
																				{
																				ImageSearch, towerX, towerY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\tower.png
																				Mousemove, towerX, towerY, 5
																				Click
																				Mousemove, hammerX, hammerY, 5
																				Click
																				} else {
																					ImageSearch, passX, passY, 0, 0, A_ScreenWidth, A_ScreenHeight, *3 %A_WorkingDir%\resources\pass.png
																					Mousemove, passX, passY, 5
																					Click
}

Mousemove, A_ScreenWidth/ 2, A_ScreenHeight / 2 + 100, 5

Loop, 10
{
ImageSearch, PlayerHitX, PlayerHitY, 0, 0, A_ScreenWidth, A_ScreenHeight, *150 %A_WorkingDir%\resources\PlayerHit.png
If Errorlevel = 0
	{
	Click
	Goto, PlayerHit
	}
ImageSearch, PlayerPassX, PlayerPassY, 0, 0, A_ScreenWidth, A_ScreenHeight, *150 %A_WorkingDir%\resources\PlayerPass.png
If Errorlevel = 0
	{
	Click
	Goto, PlayerPass
	}
}
Goto, TestRound

Esc::ExitApp
		
#2::
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
		
#3::
Gui,1:Add, Text, x10 y9 w140 h30 , Please Select New Hammer Location
Gui,1:Show,, New GUI Window
KeyWait, LButton, D, 10
	If Errorlevel = 0
		{
		Manual = 1
		MouseGetPos, ManualX, ManualY
		Gui, 1:Destroy
		return
		}
return

GuiClose:
Gui, Destroy
	
#`::
MsgBox,
( 
InBattle:(%inbattle%)
Battles:(%battles%)
Round:(%roundnumber%) 
Player:(%player%:(X:%playerX% Y:%playerY%))
Hammer:(%hitter%:(X:%hammerX% Y:%hitterY%)) 
Boss:(%BossChoosen%:(%BossX%:%BossY%))
School:(%school%)
Sharp:(%sharp%) 
Potent:(%potent%)
Blade:(%blade%) 
Blade2:(%blade2%)
Trap:(%trap%)  
Trap2:(%trap2%)
Feint:(%feint%) 
Aura:(%aura%) 
Enchant:(%enchant%) 
Active Hits:(%hit4%:%hit3%:%hit2%:%hit1%) 
Tower:(%tower%) 
PlayerCommands:(%PlayerPass%:%PlayerHit%) 
Used:(%Used1%:%Used2%:%Used3%:%Used4%:%Used5%:%Used6%:%Used7%:%Used8%:%Used9%)
)