# donkey kong
transcode of Donkey Kong arcade version for Amiga

Credits:

- jotd: Z80 to Amiga 68000 conversion (code, gfx & sfx)
- no9: Amiga remade tunes
- Jeff Willms, Kef Schecter, anon: Z80 reverse engineering
- Mark (tcdev): arcade graphics extraction
- DanyPPC: icons
- mrv2k: boxart

Features:

- 100% identical game, 50fps on A500/68000 1MB
- high score save
- kill screen fix (level 22, good luck for reaching that!)
- option to change level orders from original to alternate/crazy kong
- "nice barrel" option (found in one japan version): barrels don't fall on
  Mario when Mario is at the top of the ladder.

Command line arguments (DOS bootable version):

- INVINCIBLE/S: invincible
- INFLIVES/S: infinite lives
- INFTIME/S: infinite time
- CHEATKEYS/S: enable cheat keys (see below)
- STARTLIVES/K/N: set start lives
- STARTLEVEL/K/N: set start level
- SKIPINTRO/S: skip Kong climb sequence
- CRAZYKONGLEVELS/S: "crazy kong" japanese version order
- NICEBARRELS/S: barrels don't fall on the ladder if Mario
  is high enough (like Japanese version)
	
Instructions:

keys+<kbd>CTRL</kbd> or joystick: controls\
<kbd>5</kbd> or fire: insert coin\
<kbd>1</kbd> or joy up: start 1P game\
<kbd>2</kbd> or joy down: start 2P game\
<kbd>P</kbd>: pause/unpause\
<kbd>Q</kbd>: quit current game\
<kbd>ESC</kbd>: return to DOS

Cheat keys:

<kbd>F1</kbd>: skip level\
<kbd>F2</kbd>: get hammer\
<kbd>F3</kbd>: add 1000 points

