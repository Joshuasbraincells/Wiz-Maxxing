# Wiz-Maxxing to-do

Gold only, never Crowns. Game memory is read-only (the one exception: Cheat Engine's speedhack keys).

## 1. Party of 4: synced quests
- [ ] One client per PC (2 desktops + 2 laptops); a leader picks the quest, the others follow it
- [ ] Bots talk over the home network: quest, zone, position, "in battle", "ready"
- [ ] Followers walk to the leader, join its battle, and wait at loading screens and teleports
- [ ] Battle roles (hitter, healer, blader) so 4 bots don't all hit or all pass

## 2. Stuck: mitigate completely
- [ ] Ranked list from the stuck analysis (workflow run wf_60d57f89-04e), then pick routes
- [x] Inside a mob's reach or sight: walks out (the quest's side) instead of waiting there (v0.34.0)
- [ ] Throne Room: the goal is behind a wall the zone map lacks
- [ ] Measure it: badly-stuck count and time lost per run (07:10-09:34 run: 4 incidents)

## 3. Card learning, use and battle logic: reliable
- [ ] Live-test what shipped untested: draw for a killing enchant, learned hits, enchant learning, MoveToCard
- [ ] The 913 s battle (07:10-09:34 run): find why it lasted so long
- [ ] Fewer passes (24 passes to 74 casts in that run)

## 4. Card quests and spell learning, automatic
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
