# Wiz-Maxxing to-do

Gold only, never Crowns. Game memory is read-only (the one exception: Cheat Engine's speedhack keys).

## 1. Party of 4: synced quests
- [x] One client per PC (2 desktops + 2 laptops); a leader picks the quest, the others follow it (v0.37.0)
- [x] Bots talk over the home network: zone, position, in battle, health, ready (v0.37.0)
- [x] Followers walk to the leader, into its battles, through its doors; the leader waits for them (v0.37.0)
- [ ] Teleport to friend when the leader is somewhere a door doesn't lead (phase 2 - needs friends-list screenshots)
- [x] Own name plate in a party battle: its name learned from solo battles (the game's log), its plate read by name (v0.38.0)
- [x] Battle roles (hitter, healer, blader) so 4 bots don't all hit or all pass (v0.40.0)

## 2. Stuck: mitigate completely
- [ ] Ranked list from the stuck analysis (workflow run wf_60d57f89-04e), then pick routes
- [x] Inside a mob's reach or sight: walks out (the quest's side) instead of waiting there (v0.34.0)
- [x] Walked through mob rings after a battle start (memory steering dropped, the arrow's straight way): route kept by the arrow, no turning on the spot in a ring (v0.35.0)
- [ ] Other players' battles kept away from: active duel circles found in the game's memory (read-only; the log's "MSG_EndDuel ... NOT a part of it" to cross-check), the WHOLE arena blocked with a margin - the players' side too: the route now goes through it outside the mobs' sight, and any active arena pulls the wizard in (seen by you) - unless the duel has the quest's mob; fallback: the arena from where its mobs and players stand (opposite sides of the circle); drawn on the dashboard map (asked 2026-10-23)
- [ ] Throne Room: the goal is behind a wall the zone map lacks
- [ ] Measure it: badly-stuck count and time lost per run (07:10-09:34 run: 4 incidents)

## 3. Card learning, use and battle logic: reliable
- [ ] Live-test what shipped untested: draw for a killing enchant, learned hits, enchant learning, MoveToCard
- [ ] The 913 s battle (07:10-09:34 run): find why it lasted so long
- [ ] Fewer passes (24 passes to 74 casts in that run)
- [ ] Blades and traps by damage school: each hit's damage schools known (the wiki, the card's text - Hydra: storm, fire and ice heads); a blade/trap used when it matches any of the planned hit's schools (Elemental Blade: all three heads; only a Storm Blade in hand: still boosts Hydra's storm head) and counted per head in the kill check; a support's other-school blades (a pet's Storm Blade) cast on the hitter they boost; asked 2026-10-23 (code check: workflow wf_71ffa745-5e6, scratchpad blade_audit.md). Found: hits all taken as the wizard's school (a Balance wizard never looks for Elemental Blade/Trap); every blade counted on every hit; a learned Hydra stored as its first head only; Elemental/Spirit pictures are placeholders at 1440p; a support never looks in the hitter's school folder; a wand's cast clears every blade from the model. (Learned blades/traps no longer thrown away: v0.43.0)
- [ ] Card titles read: the title banner of each card in hand OCR'd (today only its picture and text box are matched - "is the bot unable to read the card title?"), then a Fandom wiki lookup (not Wizard101 Central - it blocks bots) for its school, pips and damage heads, filling the Spells tab and the blade logic above; asked 2026-10-23. Found 2026-10-24: a hovered card is drawn ~1.55x bigger (81x135 -> ~125x195 at 1440p, UI 1.144) and its title and text are far clearer - read each new card hovered on purpose (the mouse onto it from above, ~250 ms, then OCR), not off the small hand
- [x] Spells tab cells: Tab / Shift+Tab across, Enter / Shift+Enter down and up, as in a spreadsheet; asked 2026-10-24 (v0.47.1)
- [x] A page to change the hotkeys: the dashboard's Keys tab - every action's key, caught by pressing it, refused when the game or the bot needs it; asked 2026-10-24 (v0.48.0)
- [x] Spells tab: how sure the learner is of each card (Sure %, why under the picture: kind / number read alike twice or once, pips read or guessed); asked 2026-10-24 (v0.47.0)
- [x] Deck switching: a "small" deck for weak collect mobs, a "large" deck for bosses - switched before the fight by what's ahead (collect goal / the quest's boss); asked 2026-10-23 (v0.47.0: deck profiles picked by dungeon run / pinned / Alt+1 boss / collect / farming / default; in-game deck by Equipment Set Ctrl+1-9; damage range with stats and crits)
  - [ ] Bosses and elites from the game files (Root.wad templates: title Boss/Elite, rank, health, block): the boss deck before the fight, Elite only when it takes 3+ of your best hits; "can this deck beat it" from its range and the boss's health and block (v0.49.0)
  - [ ] Per-deck slot pictures - each deck its own hit1-4 etc. (asked: yes) (v0.50.0)
  - [ ] Decks learned from the game (Learn this deck) (v0.51.0)
  - [x] The dashboard's Cards tab gets two tabs of its own, Small deck and Large deck: each deck's settings and behaviour (its cards and slots, how it plays - blades/traps before hitting, healing, passing, when it's used) set there (v0.47.0: a button row - tabs can't sit in a tab)
  - [x] Adaptive decks: more decks than the two - you add one (or the bot learns from the decks you set up in the game which ones you want) and define what it's for and how it plays; used for dungeons and farming. A dungeon's deck picked on the Dungeons tab (per recorded dungeon run); farming's on the Cards tab (v0.47.0: + Deck / Copy, up to 6; a dungeon run's deck on the Dungeons tab)

## 4. Card quests and spell learning, automatic
- [x] NPCs with a quest marker ("?") talked to when passed on the way (v0.35.0)
- [ ] Spell quests taken and done as they come up
- [ ] Training points spent at trainers (a set plan per school)
- [ ] New spells put in the deck and learned by the card reader

## 5. Gear dungeons until all gear is swapped
- [ ] Olympus, Waterworks, Hades, Darkmoor: routes, bosses, cheats
- [ ] Gear read and compared to what's worn; better pieces equipped
- [ ] Repeat each until its gear is all swapped; then the next

## 6. Perfect pets, automatic
- [ ] Build on AutoPetTrainer: training, snacks (gold only)
- [ ] Hatching for the wanted talents; stop when a pet has them all
