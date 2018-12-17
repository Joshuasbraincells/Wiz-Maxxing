Made By JoshuasBrainCells

Sometimes we just need a break from all that farming in wizard101
or maybe you've been questing and are just sick of it, i have just
the solution for you. I thought I'd take some time out of my life
to create a program which basically plays the game for me. With this
program, I've been able to read so many books AND get Darkmoor gear
easily. Sound Good? You say you don't like to read? Well just endure
this much and then you'll be overpowered in Wizard101 in no time.

To begin install Autohotkey from https://www.autohotkey.com then 
open the AutoFarmer.ahk file. Once its open, you should be able to see 
it in the tab menu on the Taskbar. You can then activate the script 
by pressing the key combo "Windows+1".

Now whenever you join a battle the program will take over your
mouse and create a strategy based on the cards you have. Please
note however it only has a select few cards out of the many that 
are in Wizard101. so far it mainly uses hit all spells, blades,
traps, feints, auras, enchants, towers, and bubbles

This program prioritizes cards based on priority. The priority 
chart goes in this order, feint, trap, blade, aura, hit, tower,
reshuffle, and if no other move can be found, it'll pass. So what
this means is that if there's a blade and a tower in hand, it'll use
the blade first because it has a higher priority.

Now this program isn't smart enough to figure out where a 
boss might be(If it can't do that it can't trap, feint or convert!), 
so I've added a hotkey that allows you to manually set it, the 
key combo is Alt+1, A message box will appear instructing 
the player to click where the boss is. Please be careful where you click
if you click in the wrong spot, it'll remember it and won't work correctly.

Occasionally the program chooses a ally to blade which the player
using the program disagrees with, I've added a hotkey to 
solve this issue as well. Use the key combo Alt+2 to 
manually set the "Hammers" location. Works exactly like the 
boss location.

Along side simply playing the game this program has certain modes
all of which include, command mode, response mode, dual mode and lore mode.
Just as a note, all of these can be turned off be re-inputing the
same key combo.

At any moment you can close the program with "Windows+Escape"

Dual mode:
Pressing the key combo Alt+D will activate this mode. When activated,
at the end of each round the program will tab out as to switch to another
instance of wizard101. Dual mode is only to be used when you're playing on
two accounts. For better consistency close everything but the two instances
of Wizard101.

Command mode:
This mode allows the use of commands from other players, especially used
for teleporting. To activate, use the key combo "Alt+C". When activated
all commands are available to other players. The phrases are as shown.
	Port: 
		When sent to the player running the program, it'll teleport to
		the playing calling.
	Afk: 
		When sent to the player running the program, it goes 
		into a "Timeout prevention sequence" which basically means it
		makes the player move so that you wont disconnect from timeout.
	Enter:
		When sent to the player running the program, 
		it'll press "X" and it's used for interacting with things, and 
		entering sigils.
	Walk:
		When sent to the player running the program, it walks
		the recipient exactly two seconds forward.
		
LoreMode:
When activated, this mode will proceed to farm lore infinitely
so long as the player has mana and or potions. The main way of getting back
to the sigil is by logging out and in, so don't get scared when it does so.
Every cycle, the program waits exactly 30 seconds for the player to regain health.
		
Response mode:
what this mode does is respond to the player issuing the command before 
initiating the command itself. I Primarily made it for shits and giggles but
it does have its uses. For instance, when a command cannot be achieved for 
whatever reason, response mode will report an error instead of it's 
normal phrase.
