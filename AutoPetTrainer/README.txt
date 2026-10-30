Author: Joshuabrain2K1

TUTORIAL:
1: Download and install AutoHotkey v2 from https://www.autohotkey.com/download/ (the script needs v2; keep this
   folder inside the Wiz-Maxxing folder - it uses the V1Compat.ahk there).
2: Double click the PetTrainer.ahk file in this folder.
3: To start the hotkey use the Windows key and 1. To stop the program at anytime press Esc.
4: Pressing Esc closes the program (and lets your mouse go), so to reactivate Double click the program file again.
5: Make sure you're standing next to the sigil in the Pet Pavilion when activating the program.

KNOWN LIMITS (v0.9.0 - not fixed yet, AutoFarmer's own pet trainer is to replace this one: TODO.md goal 6):
- It reads nothing from the game. It presses random W/A/S/D keys in the dance game instead of the moves the game
  shows, so most rounds fail; it doesn't stop at a level or when the pet is out of energy.
- Its clicks are fixed spots of an 800x600 window: they only land right when your SCREEN is 800x600. At other sizes
  check where they land before you leave it running.
- Keep Wizard101 the window in front: the keys and clicks go to whatever window is.
- While a round plays your mouse is locked (between rounds, and after Esc, it's free).

