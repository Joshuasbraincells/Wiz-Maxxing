<p align="center"><img src="assets/avatar.png" width="180" alt="Wizard101 bots"></p>

# Wizard101 bots

AutoHotkey bots for Wizard101: **AutoFarmer** (battles, quest walking, card learning, potions, dashboard) and
**AutoQuester** (the quest walker on its own). Details: [AutoFarmer/README.txt](AutoFarmer/README.txt).

## Set up a PC

1. Download the newest **Wiz-Maxxing-v0.##.zip** (versions go v0.01, v0.02, ... v0.99, v1.00, v1.01) from the [Releases](../../releases) page and unzip it anywhere.
2. Double-click **Setup.exe**. It shows what's there already and installs what's missing:
   Python 3 and its numpy and Pillow packages (for the card matching), unblocks the downloaded files,
   and adds **Wiz-Maxxing** to the Start menu and the desktop. AutoHotkey v1.1 and Git are optional (only
   to change the bot or get updates with `git pull`).
3. Start the bot from the Start menu (search "Wiz-Maxxing") or with **Wiz-Maxxing.exe** in the folder.
   Keep the folder where it is - the shortcuts point into it.
   If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.

## Change the bot

Edit the `.ahk` scripts, then double-click **build.cmd** to rebuild the exes (needs AutoHotkey v1.1 with its
compiler; close the bot first).
