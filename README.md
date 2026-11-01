<p align="center"><img src="assets/avatar.png" width="180" alt="Wizard101 bots"></p>

# Wizard101 Wiz-Maxxer Bot

Deisnged to play the game for you and Max wizards with very little necessary intervention.

Setup:

1. Download the newest **Wiz-Maxxing-v#.#.#.zip**

2. Double-click **Setup.exe**. It shows what's there already and installs what's missing: first it copies the bot
   into your own Programs folder (`%LOCALAPPDATA%\Programs\Wiz-Maxxing` - no admin needed, updates keep working;
   over an earlier install there, its settings and learned cards are kept), then, from there, Python 3 and its
   numpy and Pillow packages (for the card matching), unblocks the downloaded files, and adds **Wiz-Maxxing** to the
   Start menu, the desktop, the Run box (Win+R) and your PATH. AutoHotkey v2 and Git are optional (only to change
   the bot or get updates with `git pull`). At the end it offers to move the download - the unzipped folder and the
   Wiz-Maxxing zip(s) beside it - to the Recycle Bin.
   
3. Start the bot from the Start menu (search "Wiz-Maxxing") or the desktop shortcut.
   If Windows says "Windows protected your PC", click **More info**, then **Run anyway**.

Updating:

Tick **GitHub updates** in Setup once per PC: it opens GitHub's token page (make a fine-grained token with
read-only **Contents** access to this repository - and **Issues: Read and write** for the dashboard's
**Report a bug**) and keeps the token in Windows Credential Manager. From then
on, opening **Wiz-Maxxing** checks for a newer release and asks before installing it - your PlayerStats.txt,
learned cards, potion routes and the bot's memory are kept. The bot's tray menu has **Check for updates** too.
