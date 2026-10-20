<p align="center"><img src="assets/avatar.png" width="180" alt="Wizard101 bots"></p>

# Wizard101 bots

AutoHotkey bots for Wizard101: **AutoFarmer** (battles, quest walking, card learning, potions, dashboard) and
**AutoQuester** (the quest walker on its own). Details: [AutoFarmer/README.txt](AutoFarmer/README.txt).

## Set up a PC

1. Download the newest **Wiz-Maxxing-v#.#.#.zip** (versions are MAJOR.MAIN.BUG: new features go v0.14 → v0.15, bug fixes v0.14 → v0.14.1) from the [Releases](../../releases) page and unzip it anywhere.
2. Double-click **Setup.exe**. It shows what's there already and installs what's missing: first it copies the bot
   into your own Programs folder (`%LOCALAPPDATA%\Programs\Wiz-Maxxing` - no admin needed, updates keep working;
   over an earlier install there, its settings and learned cards are kept), then, from there, Python 3 and its
   numpy and Pillow packages (for the card matching), unblocks the downloaded files, and adds **Wiz-Maxxing** to the
   Start menu, the desktop, the Run box (Win+R) and your PATH. AutoHotkey v1.1 and Git are optional (only to change
   the bot or get updates with `git pull`). At the end it offers to move the download - the unzipped folder and the
   Wiz-Maxxing zip(s) beside it - to the Recycle Bin.
3. Start the bot from the Start menu (search "Wiz-Maxxing") or the desktop shortcut.
   If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.

## Updates

Tick **GitHub updates** in Setup once per PC: it opens GitHub's token page (make a fine-grained token with
read-only **Contents** access to this repository) and keeps the token in Windows Credential Manager. From then
on, opening **Wiz-Maxxing** checks for a newer release and asks before installing it - your PlayerStats.txt,
learned cards, potion routes and the bot's memory are kept. The bot's tray menu has **Check for updates** too.

## Change the bot

Edit the `.ahk` scripts, then double-click **build.cmd** to rebuild the exes (needs AutoHotkey v1.1 with its
compiler; close the bot first).
