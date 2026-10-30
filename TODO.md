# Wiz-Maxxing to-do

Gold only, never Crowns. Game memory is read-only (the one exception: Cheat Engine's speedhack keys).

## 1. Party of 4: synced quests
Four bots, one per PC, quest together: a leader picks the quest, the others follow it into its battles and through its doors, each with a battle role.
- [ ] Teleport to a friend when the leader is somewhere a door doesn't lead - half built in v0.9.0 (a follower knows a door walked through from a teleport, the leader's last 3 doors, says 'can't follow - waiting' and gives up a door after 3 tries; teleport advice sent), to try in the game; still to do: the Friends list click itself (needs its window names from bagmem.py --tree)

Done: the home network link, following and waiting, each bot's own name plate in party battles, battle roles (hitter, healer, blader), battles only (Settings: the wizards riding the driver's 4-player mount play its battles and move nothing else).

## 2. Never stuck
The walker gets anywhere a quest sends it, without help.
- [ ] Pass behind moving mobs: which way each mob is walking, its sight cone projected along it, the route behind it; a line of mobs treated as one wall and routed all the way round - built in v0.9.0 (vision\navroute.py: each mob's heading and speed, cones swept along it, replans on where a mob will be, waits timed to it; the line of mobs as a wall behind the mobwall setting, off), to try in the game
- [ ] Keep away from other players' battles (active duel circles in the game's memory) - built in v0.9.0 behind the duelavoid setting, off until the duel objects are confirmed (python bossmem.py --duels next to a battle), to try in the game
- [ ] Measure it: badly-stuck count and time lost per run - built in v0.9.0 (the Dashboard's Badly stuck row, 'Walk: badly stuck' / 'stuck over' log lines, vision\stuckreport.py for past logs), to try in the game
- [x] Puzzles: a way blocked (a gate) tried first - the side guards fought, levers / switches X'd, the zone's NPCs talked to - then the notice
- [x] Puzzles learned from you: after a notice, what you did to solve it recorded (enemies fought, X / talks, where) and repeated next time; the quest's Wizard101 Central link in the notice
- [ ] Puzzle things with no name key (a lever the game names nowhere): found by the zone's triggers' use events - built in v0.9.0 (each use event's targets and states, levers matched to it by name, behind the puzzlelevers setting, off; python vision\puzzlefile.py --uses / --find to learn which file ties an object to its event), to try in the game
- [ ] A gate's open / shut read from its state in the game's memory (ObjectStateBehavior), not only the door collision going - built in v0.9.0 (vision\statemem.py reads it by reflected name; the state rules behind the puzzlestate setting, off, until python vision\statemem.py --watch at a gate pins the property and its values); also: a gate model that stays in memory once open is walked through to see, not taken as shut, to try in the game
- [ ] A sigil that never starts after a relog (2026-10-26 21:44): leave it, go home and come back - built in v0.9.0 (a sigil X that didn't load counted per spot, one gate for every sigil X, Mark / Home / Recall then the Commons behind the sigilhome setting, off; otherwise the notice), to try in the game; the thresholds are guesses until the 21:44 log lines are seen

Done: mob rings and sight cones avoided, the quest's goal and its kind read from the game's memory, walking up to goals, "Use ..." / go-to / talk goals with no map marker, a blocked way (a gate) tried first - side guards, levers, NPCs - and learned from you after a notice; the quest's Wizard101 Central link in every notice.

## 3. Battles: reliable, then smart
Every card known from the game's memory and played well, with a deck that fits the fight.
- [ ] Every card cast by the game's memory (where it sits in hand, its target's plate), pictures only a fallback - and every other on-screen check switched to memory where it can be - built in v0.9.0: each card's and plate's box from memory (clicks there behind the memclicks setting, off, checked against the screen in the log every round), your school and health, the enemies' and allies' health from memory first; still to do with the game: cast checks, round start, Pass / Flee / Draw and mana by memory
- [ ] Battle logic learned (an enormous task), in steps:
  - [ ] Every battle recorded from the game's memory (enemies, hands, cards played and why, damage, rounds to the kill; school, deck, party seat and role)
  - [ ] A battle simulator on the bot's damage maths, the deck's real cards, the wiki's spells and each enemy's cast history - built in v0.8.0 (vision\battlesim.py: resists, block and hits from the battles recorded), to try in the game; not in it yet: shields, the enemies' boosts and heals, DoTs past their first part, stuns, the party's other wizards
  - [ ] A planner that tries the plays in the simulator each round - learned plays kept per school, all schools' data while a school has few battles; decks matched to each enemy - built in v0.9.0 as advice only (the planner setting, off: 'Plan: would play ...' each round; vision\battlelearn.py keeps the learned plays), to try in the game; still to do: playing the advice (needs cards cast by memory), decks matched to each enemy group
  - [ ] In a party: the leader plans the whole team's round (each bot told its card), and the hitter announces its hit round and schools so the others time their blades and traps to it (also when a bot doesn't answer the leader in time)
- [ ] "Can this deck beat it": the deck's damage against an enemy's health, block and resists - built in v0.8.0 (a boss ahead fought in the simulator with each deck for bosses, the likeliest winner picked), to try in the game
- [ ] Decks learned from the ones set up in the game - built in v0.8.0 (the Cards tab's From game, and every 30 minutes: each in-game deck in an Equipment Set linked to a deck here, its set, school and the settings its cards call for), to try in the game

Done: cards read from memory, blades and traps by damage school, traps on the enemy with the most health, deck profiles with the boss deck put on before the fight, the Spells and Keys tabs.

## 4. Card quests and spell learning, automatic
- [ ] Spell quests taken and done as they come up
- [ ] Training points spent at trainers (a set plan per school)
- [ ] New spells put in the deck and learned

Done: NPCs with a quest marker talked to when passed.

## 5. Gear dungeons until all gear is swapped
- [ ] Olympus, Waterworks, Hades, Darkmoor: routes, bosses, cheats
- [ ] Gear read and compared to what's worn; better pieces equipped before anything is sold
- [ ] Repeat each until its gear is all swapped; then the next

Done: quick sell when the backpack's full.

## 6. Perfect pets, automatic
- [ ] Build on AutoPetTrainer: training, snacks (gold only)
- [ ] Hatching for the wanted talents; stop when a pet has them all (pets kept out of quick sell by then)
