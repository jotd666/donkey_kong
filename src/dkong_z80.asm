;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Originally disassembled with dZ80 v1.31
;
; Z80 code contributors:
; * Jeff Willms (phase 1)
; * Kef Schecter (phase 2)
; * An anonymous contributor (most of the initial work on phase 1)
;
; reworked by JOTD mainly to de-anonymize RAM variables
;
; Memory map:
;   $0000-3fff ROM
;   $6000-6fff RAM
;   $6900-6A7f sprites
;   $7000-73ff unknown; probably not used
;   $7400-77ff Video RAM
;       top left corner:      $77A0
;       bottom left corner:   $77BF
;       top right corner:     $7440
;       bottom right corner:  $745F
;
;   Note that the monitor is rotated 90 degrees, so $77A1 is the tile under
;   $77A0, not the tile to the right of it.


; I/O ports
IN0         equ     $7c00       ; player 1 joystick and jump button
IN1         equ     $7c80       ; player 2 joystick and jump button
IN2         equ     $7d00       ; coins; start buttons
DSW1        equ     $7d80       ; DIP switches

; IN0 and IN1:
;   bit 7 : ?
;   bit 6 : reset
;   bit 5 : ?
;   bit 4 : JUMP
;   bit 3 : DOWN
;   bit 2 : UP
;   bit 1 : LEFT
;   bit 0 : RIGHT
;
; (IN0 is read on player 1's turn; IN1 is read on player 2's turn)

; IN2:
;   bit 7: COIN
;   bit 6: ? Radarscope does some wizardry with this bit
;   bit 5 : ?
;   bit 4 : ?
;   bit 3 : START 2
;   bit 2 : START 1
;   bit 1 : ?
;   bit 0 : ? if this is 1, the code jumps to $4000, outside the rom space

; DSW1:
;   bit 7 : COCKTAIL or UPRIGHT cabinet (1 = UPRIGHT)
;   bit 6 : \ 000 = 1 coin 1 play   001 = 2 coins 1 play  010 = 1 coin 2 plays
;   bit 5 : | 011 = 3 coins 1 play  100 = 1 coin 3 plays  101 = 4 coins 1 play
;   bit 4 : / 110 = 1 coin 4 plays  111 = 5 coins 1 play
;   bit 3 : \bonus at
;   bit 2 : / 00 = 7000  01 = 10000  10 = 15000  11 = 20000
;   bit 1 : \ 00 = 3 lives  01 = 4 lives
;   bit 0 : / 10 = 5 lives  11 = 6 lives

; 7800-780F P8257 Control registers
; @TODO@ -- define constants for this


REG_MUSIC       equ $7c00

; Values written to REG_MUSIC
; @TODO@ -- update code to use these
MUS_NONE        equ $00
MUS_INTRO       equ $01     ; Music when DK climbs ladder
MUS_HOWHIGH     equ $02     ; How high can you get?
MUS_OUTATIME    equ $03     ; Running out of time
MUS_HAMMER      equ $04     ; Hammer music
MUS_ENDING1     equ $05     ; Music after beating even-numbered rivet levels
MUS_HAMMERHIT   equ $06     ; Hammer hit
MUS_FANFARE     equ $07     ; Music for completing a non-rivet stage
MUS_25M         equ $08     ; Music for barrel stage
MUS_50M         equ $09     ; Music for pie factory
MUS_75M         equ $0a     ; Music for elevator stage (or lack thereof)
MUS_100M        equ $0b     ; Music for rivet stage
MUS_ENDING2     equ $0c     ; Music after beating odd-numbered rivet levels
MUS_RM_RIVET    equ $0d     ; Used when rivet removed
MUS_DK_FALLS    equ $0e     ; Music when DK is about to fall in rivet stage
MUS_DK_ROAR     equ $0f     ; Zerbert. Zerbert. Zerbert.

; Sound effects get their own registers
REG_SFX         equ $7d00   ; The first of 8 sound registers, but only the first 6 are used

; These are added to REG_SFX to produce the register to write to
; These are also used by RAM (@TODO@ -- what variable?) to queue sounds
SFX_WALK        equ 0
SFX_JUMP        equ 1
SFX_BOOM        equ 2       ; DK pounds ground; barrel hits Mario
SFX_SPRING      equ 3       ; (writes to i8035's P1)
SFX_FALL        equ 4       ; (writes to i8035's P2)
SFX_POINTS      equ 5       ; Got points, grabbed the hammer, etc.

REG_SFX_DEATH   equ $7d80   ; plays when Mario dies (triggers i8035's interrupt)

; Some other hardware registers
REG_FLIPSCREEN      equ $7d82
REG_SPRITE          equ $7d83   ; cleared at program start and never used
REG_VBLANK_ENABLE   equ $7d84
REG_DMA             equ $7d85   ; @TODO@ -- what does this do, exactly?

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Background palette selectors
;
; These registers each store 1 bit. Only the least-significant bit
; matters when writing. The two values together determine the palette
; for the whole screen. Note that the colors can change from row to row
; in each palette. For example, in the high score screen palette, the
; first row of tiles shows red text; the second and third rows have
; white text; the fourth row has blue text; etc. You can see this in
; MAME by looking at the 0's on the screen while the game is booting up.
;
; Palettes:
; A | B
; -----
; 0 | 0     high score screen
; 0 | 1     barrel and elevator stages
; 1 | 0     pie factory stage
; 1 | 1     rivet stage
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
REG_PALETTE_A       equ $7d86
REG_PALETTE_B       equ $7d87


; Machine accepts no more than 90 credits (this is a BCD value)
MAX_CREDITS     equ $90


RAM             equ unknown_6000
SPRITE_RAM      equ $7000
VIDEO_RAM       equ $7400

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Notes on variables (READ THIS)
;
; Donkey Kong's code is a little nutty and often depends on variables
; being stored in a certain way. For instance, if there's a variable at
; RAM+$a, it may do "DEC HL" to get at the variable at RAM+9, even
; if these variables are loosely related at best. If you're making a
; hack, we strongly suggest you keep the addresses of existing variables
; intact!
;
; For the same reason, it's hard to be 100% sure that every variable has
; been documented. It's easy to miss a variable if it's never directly
; referenced by address.
;
; Finally, be aware that, intentionally or not, some variables may have
; been used for more than one purpose.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; those equates are the same in lower case, suffixed by their RAM address
; Number of credits in BCD. Can't go over MAX_CREDITS.
NumCredits      equ RAM+1

; Counts number of coins inserted until next credit is reached
; E.g., if the machine is set to 4 coins/credit, this starts at 0 and counts up to 4 with each coin.
; When it's 4, it'll be reset to 0 and a credit will be added.
CoinCounter     equ RAM+2

; Usually 1. When a coin is inserted, it changes to 0 momentarily.
; (In MAME, this value will be 0 while the coin key is held down.)
CoinSwitch      equ RAM+3

; 1 when in attract mode, 2 when credits in waiting for start, 3 when playing game
GameMode1       equ RAM+5

; 1 when no credits have been inserted, 0 if any credits exist or a game is being played
NoCredits       equ RAM+7

; General-purpose timer. 16-bit. The code uses the MSB rather than the LSB for 8-bit timers.
WaitTimer       equ RAM+8
WaitTimerLSB    equ RAM+8
WaitTimerMSB    equ RAM+9

; Attract mode: $1
; Intro: $7
; How High Can You Get?: $a
; Right before play: $b
; During play: $c
; Dead: $d
; Game over: $10
; Rivets cleared: $16
; @TODO@ -- list is not complete. Range is [0..$17], and most, possibly all, values seem to be used
GameMode2       equ RAM+$a

; Both of these are 0 if it's player 1's turn, and 1 if it's player 2's turn.
; @TODO@ -- try to find why these are two variables and give them better names.
PlayerTurnA     equ RAM+$d
PlayerTurnB     equ RAM+$e

; 0 if 1-player game, 1 if 2-player game
TwoPlayerGame   equ RAM+$f

; The same as RawInput below, except when jump is pressed, bit 7 is set momentarily
InputState      equ RAM+$10

; Right sets bit 0, left sets bit 1, up sets bit 2, down sets bit 3, jump sets bit 4
RawInput        equ RAM+$11

; constantly changing ... timer of some sort? (@TODO@ -- better name?)
RngTimer1       equ RAM+$18

; RngTimer2 - constantly changing timer - very fast (@TODO@ -- better name?)
RngTimer2       equ RAM+$19

; Constantly counts down from FF to 00 and then FF to 00 again and again, once per frame
FrameCounter    equ RAM+$1a

; Initial number of lives (set with dip switches)
StartingLives   equ RAM+$20

; score needed for bonus life in thousands
ExtraLifeThreshold  equ RAM+$21

CoinsPerCredit  equ RAM+$22

; Coins needed for a two-player game (always CoinsPerCredit*2)
CoinsPer2Credits    equ RAM+$23

; Seems to be used for the same purpose as CoinsPerCredit (@TODO@ -- why is this a distinct variable?)
CoinsPerCredit2 equ RAM+$24

CreditsPerCoin  equ RAM+$25

; 0 = cocktail, 1 = upright cabinet
UprightCab      equ RAM+$26

; Timer counting delay before cursor can move. Keeps the cursor from moving too fast.
; (@XXX@ -- verify this is this variable's function!!)
HSCursorDelay   equ RAM+$30

; Toggles between 0 and 1 as the player's high score in the table blinks
HSBlinkToggle   equ RAM+$31

; Toggles HSBlinkToggle in table whenever it's zero
HSBlinkTimer    equ RAM+$32

; Time left to register name in seconds
HSRegiTime      equ RAM+$33

; Decrements HSRegiTime when zero
HSTimer         equ RAM+$34

; Which character the cursor is highlighting when entering high score
HSCursorPos     equ RAM+$35

; Address of screen RAM for current initial being entered (16-bit variable)
HSInitialPos    equ RAM+$36

; Something to do with high score entry.
; Changing this value to FF in the debugger on high score screen causes the
; game to prompt for another name after entering the first.
Unk6038         equ RAM+$38

; Number of lives remaining for player 1
P1NumLives      equ RAM+$40

; #6041-6047 = ???
Unk6041         equ RAM+$41

; Number of lives for player 2
P2NumLives      equ RAM+$48

; #6049-604f probably serve the same purpose as 6041-6047, but for player 2
Unk6049         equ RAM+$49

NumObstaclesJumped  equ RAM+$60

; #6080 - #608F are used for sounds - they are a buffer to set up a sound to be played on the hardware

; #6080 = 1 or 3 when mario is walking, makes the walking sound

; #6081 counts down 3, 2, 1, 0 when mario jumps

; #6082 = boom sound

; #6083 counts down 3,2,1,0 when the springs bounce on the elevator level

; #6084 used for falling sounds

; #6085 = 1 when the bonus sound is played

; #6086 =

; #6089 = used to determine which music is played: (not all used during play?)
; #608A is used for same?

; #60B0 and #60B1 are some sort of counter.  counts from #C0 192 (decimal) to #FE (256) by twos, then again and again.  Related to #60C0 - #60FF ?

; #60B2, #60B3, #60B4 - player 1 score

; #60B5, #60B6, #60B7 - player 2 score

; #60B8 = ???

; #60C0 - #60FF - loaded with #FF, used for a timer, in conjunction with #60B0 ?

; #6100 - #61A5 - high score table

; #61C6, #61C7 = ???

; #6200 is 1 when mario is alive, 0 when dead

; #6202 varies from 0, 2, 4, 1 when mario is walking left or right

; #6203 = Mario's X position

; #6204 = varies between 80 and 0 when mario jumping left or right

; #6205 = Mario's Y position

; #6206 = left 4 bits vary when mario jumping

; #6207 = a movement indicator. when moving right, 128 bit is set. (bit 7) move left, 128 bit is cleared
; #6207 continuted.  walking, bits 0  and 1 flip around.  jump sets bits 1,2,3 on.  when climbing a ladder,
; #6207 cont.  bit 7 flips on and off, and bits 0,1,2 flip around

; #6208 = ?

; #620C = mario's jump height?

; #620F is movement indicator.  when still it is on 0, 1, or 2.  when moving it moves between 2,1,0,2,1,0... when on a ladder it goes to counts down from 4.  when it reaches zero, it animates mario climbing.

; #620E is set whenever mario jumps, it holds marios Y value when he jumped.

; #6210 = FF when jumping to the left and afterwards until another jump, 0 otherwise

; #6211 = 0 when jumping straight up, #80 when jumping left or right

; #6212 =

; #6214 = is counted from 0 while mario is jumping.

; #6215 is 1 when mario is on ladder, 0 otherwise

; #6216 is 1 while mario is jumping, 0 otherwise

; #6217 is 1 when hammer is active, 0 otherwise

; #6218 = 0, turns to 1 while mario is grabbing the hammer until he lands

; #6219 = 0, turns to 1 when mario is moving on a moving or broken ladder, [but this is never checked ???]

; #621B,C = the top and bottom locations of a ladder mario is on or near

; #621E = counts down from 4 when mario is landing from a jump.  0 otherwise

; #621F = 1 when mario is at apex or on way down after jump, 0 otherwise.

; #6220 = set to 1 when mario falls too far, 0 otherwise

; #6221

; #6222 = toggles between 0 and 1 when mario on ladder.  otherwise 0

; #6224 = toggles between 0 and 1 when mario on ladder.  used for sounds while on ladder

; #6225 = 1 when a bonus sound is to be played, 0 otherwise

; #6227 is screen #:  1-girders, 2-pie, 3-elevator, 4-rivets

; #6228 is the number of lives remaining for current player

; #6229  is the level #

; #622C = game start flag.  1 when game begins, 0 after mario has died ?

; #622D = 0, changed to 1 when player is awarded extra life

; #6280 to #6287 = left side retractable ladder on conveyors?

; #6288, 6289, 628A = ???

; #6290 = counts down how many rivets are left from 8

; #62A0 = top conveyor direction reverse counter

; #62A1 = master direction for top conveyor, 01 = right, FF = left

; #62A2 = middle conveyor direction reverse counter

; #62A3 = master direction for middle conveyor, 01 = outwards, FF = inwards

; #62A5 = bottom conveyor direction reverse counter

; #62A6 = master direction for bottom conveyor, 01 = right, FF = left

; #62A7 = counts down from #34 to zero on elevators

; #62A8

; #62AA

; #62AC -

; #62AF = some sort of timer connected with the barrels counts down from 18 to 00 , then kong moves position for next barrel grab  See #638F
; continued  also used for counter during game intro, used for kong animation

; #62B1 - Bonus timer

; #62B2 controls the timer for blue barrels

; #62B3 = controls the timers for all levels except girders.  Is #78 (120), #64 (100), #50,(80) or #3C (60) depending on level.
; level 1 rivets 5000 bonus lasts 99 seconds (say 100) =  100 bonus every 2 seconds
; level 2 rivets 6000 bonus lasts 99 seconds = 100 bonus every 5/3 (1.66666...) seconds
; level 3 rivets 7000 bonus lasts 92 seconds = 100 bonus every 4/3 (1.3333...) seconds
; level 4 rivets 8000 bonus lasts 80 seconds = 100 bonus every 1 seconds

; level 1 barrels 4700 bonus lasts 94 seconds = 100 bonus every 2 seconds
; level 2 barrels 5700 bonus lasts 105 seconds = 100 bonus every 1.842 seconds ???
; level 3 barrels 6700 bonus lasts 93 seconds = 100 bonus every 1.388 seconds
; level 4 barrels 7700 bonus lasts 130 seconds = 100 bonus every 5/3 seconds 1.666 ?
;

; #62B4 a timer used on conveyors ?

; #62B8 = a timer used on conveyors and girders ?

; #62B9 - used for fire release on conveyors and girders ?  0 when no fires onscreen, 1 when fires are onscreen, 3 when a fire is to be released

; #6300 - ladder sprites / locations ???

; #6340 - usually 0, changes when mario picks up bonus item. jumps over item turns to 1 quickly, then 2 until bonus disappears

; #6341 - timer counts down when mario picks up bonus item or jumps an item for showing bonus on screen

; #6342

; #6343 - changes to 14 when umbrella picked up, 0C for hat, 10 for purse

; #6345 - usually 0.  changes to 1, then 2 when items are hit with the hammer

; #6348 - #00, turns to #01 when the oil can is on fire on girders

; #6350 - 0, turns to 1 when an item has been hit with hammer, back to 0 after score sprite appears in its place

; #6351 through #6354 used for temp storage for items hit with hammer

; #6380 - Internal difficulty. Dictates speed of fires, wild barrel behavior, barrel steerability and other things. Ranges from 1 to 5.

; #6381 = timer that controls when #6380 changes ?

; #6382 = 00 and turns to 80 when a blue barrel is about to be deployed.
;         First blue barrel has this at 81 and then 02.  changes to 1 for crazy barrel
;               Bit 7 is set when barrel is blue
;               Bit 0 is set when barrel is crazy
;               bit 1 is set for the second barrel of the round which can't be crazy

; #6383 = timer used in conjunction with the tasks

; #6384 = timer ?

; #6385 = varies from 0 to 7 while the intro screen runs, when kong climbs the dual ladders and scary music is played

; #6386 - is zero until time runs out.  then it turns to 2, then when it turns to 3 mario dies

; #6387 - is zero until time runs out.  then it counts down from FF to 00, when it hits 00 mario dies and #6386 is set to 3

; #6388 = usually zero, counts from 1 to 5 when the level is complete

; #6389 - ????

; #638C is the onscreen timer

; #638D = counts from 5 to 0 while kong is bouncing during intro

; #638E = counts from #1E to A while kong is climbing ladders at beginning of game

; #638F = Counts down 3,2,1,0 as a barrel is being deployed.  See #62AF

; #6390 - counts from 0 to 7F periodically

; #6391 - is 0, then changed to 1 when timer in #6390 is counting up

; #6392 = barrel deployment indicator.  0 normally, 1 when a barrel is being deployed

; #6393 - Barrel deployment indicator. This gets set to 1 as soon as the barrel deployment process begins, and gets set back to 0 as soon as
;         kong releases the barrel being deployed.

; #6396 = bouncer release flag.  0 normally, 3 when bouncer is to be deployed

; #6398 = 1 when riding an elevator ?

; #639B = pie deployment counter

; #639D = normally 0.  1 while mario dying, 2 when dead

; #639A = indicator for the fires/deployment

; #63A0 = usually 0, flips to 1 quickly when a firefox is deployed

; #63A1 =  number of firefoxes active

; #63A2 = used as a temporary counter

; #63A3 = top conveyor direction for this frame,  flips between 00 (stationary) and either 1 (right) or FF (left) depending on kongs direction

; #63A4 = middle left conveyor direction for this frame

; #63A5 = middle right conveyor direction for this frame

; #63A6 = bottom conveyor direction for this frame

; #63B3 - ???

; #63B5 - ???

; #63B7 - ???

; #63B8 is zero but turns to 1 when the timer expires but before mario dies

; #63B9 - is 1 during girders, changes to 0A when item is hit with hammer.
        ;  on rivets it is 07.  conveyors turns to 6 when pie hit, 5 when fire hit. changes to 0A when mario dies

; #63C0 - ???

; #63C8,9 -  Used during fireball movement processing to store the address of the fireball data array for the current fireball being processed

; #63CC -  ???

; #6400 to #649F - Fireball data tables. There are 5 fireball slots, each with 32 bytes for storing data associated with that fireball. The first
;                  fireball's slot is #6400 to #641F, the second fireball's slot is #6420 to #643F, etc. The following is a description of the data
;                  stored at each offset into a fireball's slot:
; +00 - Fireball status. 0 = inactive (this fireball slot is free), 1 = active
; +01,02 - Empty
; +03 - Fireball actual X-position. This seems to be the same as +0E.
; +04 - Empty
; +05 - Fireball actual Y-position. This Y-position has been adjusted for the bobbing up and down that a each fireball is constantly doing. Note that
;       this bobbing up and down is mainly for visual effect and has no impact on any fireball movement logic (this uses +0F instead, which does not
;       account for the bobbing up and down), however hitboxes are still determined by this actual Y-position and not the effective Y-position
; +06 - Empty
; +07 - Fireball graphic data
; +08 - Fireball color. 0 = blue (Mario has hammer), 1 = normal
; +09 - (Width of fireball hitbox - 1)/2
; +0A - (Height of fireball hitbox - 1)/2
; +0B,0C - Empty
; +0D - Fireball direction of movement. It can take on the following values:
;         0 = left, but it can also mean "frozen" in the case of a freezer that is currently in freezer mode
;         1 = right
;         2 = "special" left, this is different from 0 since here the fireball behaves identically to a right-moving fireball, only moving left instead
;             of right. This means that ladders are permitted to be taken, speed is deterministic and not slowed, and freezers aren't frozen when
;             the direction is 2, unlike a direction of 0. The direction gets set to 2 only immediately after a fireball hits the right edge of a
;             girder, and it will stay at 2 until a "decision point" for reversing direction at which point the direction will become either 0 or 1.
;         4 = descending ladder
;         8 = ascending ladder
; +0E - Fireball effective X-position. This seems to be the same as +03.
; +0F - Fireball effective Y-position. This Y-position does not account for the fireball bobbing up and down and is treated as the true Y-position for
;       the purposes of all fireball movement.
; +10 to +12 - Empty
; +13 - This counter is used as an index into a table that determines how to adjust the fireball's Y-position to make it bob up and down.
; +14 - Ladder climb timer. This timer counts down from 2 as a fireball climbs a ladder. A fireball is only allowed to climb a pixel when this reaches
;       0, at which point it gets reset back to 2. This has the effect of causing fireballs to climb ladders at 1/3 of the speed at which they descend
;       ladders.
; +15 - Fireball animation change timer. This timer counts down from 2, and when it reaches 0 the fireball changes it's graphics.
; +16 - Fireball direction reverse counter. When this counter reaches 0 a fireball reverses direction with 50% probability. Such a decision is referred
;       to as a "decision point".
; +17 - Empty
; +18 - Fireball spawning flag. This is set to 1 to indicate that the fireball is in the process of spawning. Often fireballs follow a special
;       trajectory, such as when jumping out of an oil can, while this is set.
; +19 - Fireball freezer mode flag. Setting this to 2 indicates that freezer mode has been enguaged, at which point a fireball can potentially start
;       freezing. Only fireballs in the 2nd and 4th fireball slots can enter freezer mode.
; +1A,1B - During fireball spawning, when jumping out of an oil can, this is used to store the current index into the Y-position table that dictactes
;          the arc that the fireball follows as it comes out of the oil can.
; +1C - Fireball freeze timer. Freezers use this as a timer until a frozen fireball should unfreeze.
; +1D - Fireball freeze flag. If this gets set during freezer mode, then as long as Mario is not above the fireball it will immediately set the freeze
;       timer (+1C) for 256 frames and says frozen until the timer reaches 0, this can only happen when a fireball reaches the top of a ladder, all
;       other instances of a fireball freezing are caused by the direction being set to 0 during freezer mode and have nothing to do with the freeze
;       timer.
; +1E - Empty
; +1F - When a fireball is climbing up or down a ladder, this stores the Y-position of the other end of the ladder (the end the fireball is headed
;       towards).

; #64A7 -

; #6500 - #65AF = the ten bouncer values, 6510, 6520, etc. are starting values
;        +3 is the X pos, +5 is the Y pos

; #65A0 - #65?? = values for the 6 pies

; #6600 - 665F  = the 6 elevator values.  6610, 6620, 6630, 6640 ,6650 are starting values
;       + 3 is the X position, + 5 is the Y position

; #6680 -

; #6687 -

; #6688

; hammer code for top hammer of girders, lower hammer on rivets, upper left hammer on conveyors

; #6689 - changes from 5 to 6 when hammer active

; #668A - changes from 6 to 3 when hammer active

; #668E - changes from 0 to 10 when hammer active

; #668F - changes from 0 to F0 when hammer active

; #66A0 - ???

; #6700 range - barrel info +20, +40, +60, +80, +A0, +C0, +E0 for the barrels
; 00 = barrel not in use.  #02 = barrel being deployed.  #01 = barrel rolling

; #6701 - crazy barrel indicator.  00 for normal, #01 for crazy barrel

; #6702 - motion indicator.  02 = rolling right, 08 = rolling down, 04 = rolling left, bit 1 set when rolling down ladder

; #6703 - barrel X

; #6705 - barrel Y

; #6707 - right 2 bits are 01 when rolling, 10 when being deployed.  bit 7 toggles as it rolls

; #6708

; #670E = edge indicator.  counts from 0 to 3 while barrel is going over edge

; #670F = counts from 4 to 1 then over again when barrel is moving

; #6710 = 0 when deployed.  changed to #FF when at left edge and after landing after falling off right edge of girder.
          changed to 1 when after landing after falling off left edge of girder and starting to roll right
        changed to 0 while falling off right edge of girder

; #6711 = 60 when barrel is rolling around the right edge, A0 when rolling around left edge

;

; #6714 =

; #6715 =

; #6717 = position of next ladder it is going down or the ladder it just passed.
; ladders are :  70, 6A, 93, 8D, 8B, B3, B0, AC, D1, CD, F3, EE

; #6719 = grabs the Y value of the barrel when its crazy, and has hit a girder

; #6900 - #6907 = 2 sprites used for the girl

; #6908 - (#6908 + #28) = animation states for kong and maybe other things
        ; #6909 - kong's right leg
        ; #6913 -
        ; #6919 - kong's mouth
        ; #691D - kong's right arm
        ; #692D - girl under kong's arms during game intro
        ; #692F - girl under kong's arms ???

; #6944 - #694C = 2 sprites for moving ladders on conveyors

; #694C = mario sprite X value

; #694D = mario sprite value.

; #694E = mario sprite color ?

; #694F = mario sprite Y value

;00 = mario facing left
;01, 02 = mario running left
;03 = mario on ladder with left hand up
;04 = mario on ladder with butt showing
;05 = mario on ladder with butt showing
;06 = mario standing above ladder with back to screen
;07 = blank???
;08 = mario with hammer up, facing left
;09 = mario with hammer down, facing left
;0A = mario with hammer up, facing left
;0B = mario with hammer down, facing left
;0C = mario with hammer up, facing left
;0D = mario with hammer down, facing left
;0E = mario jumping left
;0F = mario landing left
;10 = top of girl
;11 = bottom of girl
;12 = bottom of girl (2nd pose)
;13 = bottom of girl (fat)
;14 = legs of girl when being carried
;15 = rolling barrel
;16, 17 = barrel going down ladder or crazy
;18 = barrel next to kong (vertical)
;19 = blue barrel (skull)
;1A, 1B = barrel going down ladder or crazy
;1C, 1D = blank ?
;1E = hammer
;1F = smashing down hammer
;20, 21, 22 = crazy kong face
;23 = kong face, frowning
;24 = kong face, growling
;25 = kong chest
;26 = kong left leg
;27 = kong right leg
;28 = kong right arm
;29 = kong left arm
;2A = kong right shoulder
;2B = part of kong ?
;2C = kong right foot
;2D = kong left arm grabbing barrel
;2E = kong bottom center
;2F = kong top right shoulder
;30 = kong face facing left
;31 = kong right arm
;32 = kong shoulder
;33 = kong shoulder
;34 = kong left arm
;35 = kong right arm
;36 = kong left foot climbing ladder
;37 = kong right foot climbing ladder
;38 = blank ?
;39 = lines for smashed item
;3A = solid block ?
;3B = bouncer (1)
;3C = bouncer (2 squished)
;3D = fireball (1)
;3E = fireball (2)
;3F = blank ?
;40 = fire on top of oil can
;41 = fire on top of oil can (2)
;42 =  fire on top of oil can (3)
;43 =  fire on top of oil can (4)
;44 =  flat girder (used for elevator?)
;45 = elevator receptacle
;46 =  ladder
;47, 48 = blank ?
;49 = oil can
;4A = blank?
;4B = pie
;4C = pie spilling over
;4D = firefox
;4E = firefox (2)
;4F = blanK?
;50 = edge of conveyor pulley
;51 = edge of conveyor pulley (2)
;52 = edge of conveyor pulley (3)
;53 - 5F = blank ?
;60 = circle for item being hit with hammer
;61 = small circle for item being hit with hammer
;62 = smaller circle for item being hit with hammer
;63 = burst for item being hit with hammer
;64 - 71  = blank
;72 = square for hiscore select
;73 = hat
;74 = purse
;75 = umbrella
;76 = heart
;77 = broken heart
;78 = dying, mario upside down
;79 = dying, mario head to right
;7A = mario dead
;7B = 100
;7C = 200
;7D = 300
;7E = 500
;7F = 800
;
;all values from 80-FF are mirror images of items 0 -7F
;
;80 = starting value, mario facing right
;81, 82 = mario running to right
;83 = mario on ladder with right hand up
;84 = mario on ladder with butt showing
;85 = mario on ladder with butt showing (2)
;86 =
;88 = mario with hammer up, facing right
;89 = mario with hammer down, facing right
;8A = mario with hammer up, facing right
;8B = mario with hammer down, facing right
;8C = mario with hammer up, facing right
;8D = mario with hammer down, facing right
;8E = mario jumping right
;8F = mario landing right
;FA = mario dead with circle (halo?)
;F8 = dying, right side up
;F9 = dying, head on left
;
;3rd sprite is the color
;0 = red
;1 = white
;2 = blue
;3,4,5,6 = cyan
;7 = white
;8 = orange
;9, A = pink
;B = light brown
;C = blue
;D = orange
;E = blue
;F = black
;10 =

; #6980 - X position of a barrel and bouncers (all sprites??) , #6981 = sprite type? , 2= sprite color?, #6983 = Y position
; Add 4 to each barrel/sprite in question up to #6A08

; #69B8 start for pie sprites

; #6A0C - #6A0C + 12 - positions of the bonus extra items, umbrella, purse, etc.

; #6A1C - #6A1F = hammer sprite

; #6A20 - #6A23 heart sprite

; #6A24 - #6A27 sprite used for kong's aching head lines

; #6A29 - sprite for oilcan fire

; #7400-77ff - video ram

; #7700 = 1 up area Letter P
; #7701 = score 10's value
; #7702 = under the score 10's value
; #7708 = area where Kong is on girders
; #7721 = score 100's value
; #7741 = score 1000's value
; #7761 = score 10,000 value
; #7781 = score 100,000 value
; #7641 is the start of high score 100,000 place
; #7521 - the start of player 2 score (100,000's place)


; characters data

;00 - 09 = 0 - 9
;10 = empty
;11 - 2A = A to Z
;12 = B
;13 = C
;14 = D
;15 = E
;16 = F
;17 = G
;18 = H
;19 = I
;1A = J
;1B = K
;1C = L
;1D = M
;1E = N
;1F = O
;20 = P
;21 = Q
;22 = R
;23 = S
;24 = T
;25 = U
;26 = V
;27 = W
;28 = X
;29 = Y
;2A = Z
;2B = .
;2C = -
;2D = high -
;2E = :
;2F = high -
;30 = <
;31 = >
;32 = I
;33 = II
;34 = = (equals sign)
;35 = -
;36 , 37 = !! (two exlamations)
;38 , 39= !
;3A = '
;3B, 3C = "
;3D = " (skinny quote marks)
;3E = L shape (right, bottom)
;3F = L shape, (right, top)
;40 = L shape
;41 = L shape, (left, top)
;42 = .
;43 = ,
;44 - 48 = some graphic (RUB END) ?
;49, 4A = copyrigh logo
;4B, 4C = some logo?
;4D, - 4F = solid blocks of various colors
;50 = 67 = kong graphics (retarded brother?)
;6C - 6F = a graphic
;70-79 = 0 - 9 (larger, used in score and tiemr)
;80 - 89 = 0-9
;8A = M
;8B = m
;8F-8C = some graphic
;9F= Left half of trademark symbol
;9E = right half of TM sybmol
;B1 = Red square with Yellow lines top and bottom
;B0 = Girder with hole in center used in rivets screen
;B6 = white line on top
;B7 = wierd icon?
;B8 = red line on bottom
;C0 - C7 = girder with ladder on bottom going up
;D0 - D7 = ladder graphic with girder under going up and out
;DD = HE  (help graphic)
;DE = EL
;DF = P!
;E1 - E7 = grider graphic going up and out
;EC - E8 = blank ?
;EF = P!
;EE = EL (part of help graphic)
;ED = HE (help graphic)
;F6 - F0 = girder graphic in several vertical phases coming up from bottom
;F7 = bottom yellow line
;FA - F8 = blank ?
;FB = ? (actually a question mark)
;FC = right red edge
;FD = left red edge
;FE = X graphic
;FF = Extra Mario Icon






;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; game start power-on
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

0000: 3E 00       ld   a,$00               ; A := 0
0002: 32 84 7D    ld   (reg_vblank_enable),a           ; disable interrupts
0005: C3 66 02    jp   Init_0266               ; skip ahead

;
; RST     #8
; if there are credits or the game is being played it returns immediately.  if not, it returns to higher subroutine
;

0008: 3A 07 60    ld      a,(nocredits_6007) ; load A with 1 when no credits have been inserted, 0 if any credits exist or game is being played
000B: 0F          rrca                ; any credits in the game ?
000C: D0          ret     nc          ; yes, return

000D: 33          inc     sp
000E: 33          inc     sp
000F: C9          ret                 ; else return to higher subroutine

;
; RST     #10
; if mario is alive, it returns.  if mario is dead, it returns to the higher subroutine.
;

0010: 3A 00 62    ld      a,(mario_array_6200)   ; 1 when mario is alive, 0 when dead
0013: 0F          rrca                ; is mario alive?
0014: D8          ret     c           ; yes, return

0015: 33          inc     sp          ; no, increase SP by 2 and return
0016: 33          inc     sp
0017: C9          ret                 ; effectively returns twice

;
; RST     #18
;

0018: 21 09 60    ld      hl,waittimermsb_6009; load timer that counts down
001B: 35          dec     (hl)        ; Count it down...
001C: C8          ret     z           ; Return if zero

001D: 33          inc     sp          ; otherwise Increase SP twice
001E: 33          inc     sp
001F: C9          ret                 ; and return - effectively returns to higher subroutine

;
; RST     #20
;

0020: 21 08 60    ld      hl,waittimerlsb_6008; load HL with timer
0023: 35          dec     (hl)        ; count it down
0024: 28 F2       jr      z,$0018     ; If zero skip up and count down the other timer

0026: E1          pop     hl          ; else move stack pointer up and return to higher subroutine
0027: C9          ret                 ; return


;
; RST     #28
; jumps program to (2*A + Next program address)
; used in conjuction with a jump table after the call
;

0028: 87          add     a,a         ; A := A * 2
0029: E1          pop     hl          ; load HL with address of jump table
002A: 5F          ld      e,a         ; load E with A
002B: 16 00       ld      d,$00       ; D := 0
002D: C3 32 00    jp      $0032       ; skip ahead

;
; RST #30
;

0030: 18 12       jr      $0044       ; this core sub is actually at #0044

;
; continuation of RST #28 from #002D above
;

0032: 19          add     hl,de       ; HL is now 2A more than it was
0033: 5E          ld      e,(hl)      ; load E with low byte from the table
0034: 23          inc     hl          ; next table entry
0035: 56          ld      d,(hl)      ; load D with high byte from table
0036: EB          ex      de,hl       ; DE <> HL
0037: E9          jp      (hl)        ; jump to the address in HL

;
; RST     #38
; HL and C are preloaded
; updates #A (10 decimal) by adding C from each location from HL to HL + #40 by 4
; [the bytes affected are offset by 4 bytes each]
;
; Also #003D is called from several places. used for updating girl's sprite
;

0038: 11 04 00    ld      de,$0004    ; load offset of 4 to add
003B: 06 0A       ld      b,$0a       ; for B = 1 to #A (10 decimal)

003D: 79          ld      a,c         ; Load A with C
003E: 86          add     a,(hl)      ; Add the contents of HL into A
003F: 77          ld      (hl),a      ; put back into HL, this increases the value in HL by C
0040: 19          add     hl,de       ; next HL to do will be 4 more than previous
0041: 10 FA       djnz    $003d       ; next B

0043: C9          ret                 ; return

; continuation of rst #30
; used to check a screen number.  if it doesn't match, the 2nd level of subroutine is returned
; A is preloaded with the check value, in binary

0044: 21 27 62    ld      hl,screen_number_6227    ; Load HL with address of Screen #
0047: 46          ld      b,(hl)      ; load B with Screen #, For B = 1 to screen # (1, 2, 3 or 4)

0048: 0F          rrca                ; Rotate A right with carry
0049: 10 Fd       djnz    $0048       ; Next B

004B: d8          ret    c            ; return if carry

004C: E1          pop     hl          ; otherwise HL gets the stack = return to higher subroutine
004D: C9          ret                 ; return

; HL is preloaded with source data of kong sprites values
; this subroutine copies the memory values of HL to HL + #28 into #6908 through #6908 + #28
; used to set all the kong sprites

004E: 11 08 69    ld      de,start_of_kong_sprite_6908    ; Kong's Sprites start
0051: 01 28 00    ld      bc,$0028    ; #28 bytes to copy
0054: ED B0       ldir                ; copy
0056: C9          ret                 ; return

; this subroutine takes the value of RngTimer1 and adds into it the values from FrameCounter and RngTimer2
; it returns with A loaded with this result and also RngTimer1 with the answer.
; random number generator

0057: 3A 18 60    ld      a,(rngtimer1_6018) ; load A with timer
005A: 21 1A 60    ld      hl,framecounter_601a; load HL with other timer address
005D: 86          add     a,(hl)      ; add
005E: 21 19 60    ld      hl,rngtimer2_6019; load HL with yet another timer address
0061: 86          add     a,(hl)      ; add
0062: 32 18 60    ld      (rngtimer1_6018),a; store
0065: C9          ret                 ; return

; interrupt routine

0066: F5          push    af
0067: C5          push    bc
0068: D5          push    de
0069: E5          push    hl
006A: DD E5       push    ix
006C: FD E5       push    iy          ; save all registers

006E: AF          xor     a           ; A := 0
006F: 32 84 7D    ld      (reg_vblank_enable),a; disable interrupts
0072: 3A 00 7D    ld      a,(in2)     ; load A with Credit/Service/Start Info
0075: E6 01       and     $01         ; is the Service button being pressed?
0077: C2 00 40    jp      nz,$4000    ; yes, jump to #4000 [??? this would cause a crash ???]

007A: 21 38 01    ld      hl,$0138    ; load HL with start of table data
007D: CD 41 01    call    $0141       ; refresh the P8257 Control registers / refresh sprites to hardware
0080: 3A 07 60    ld      a,(nocredits_6007) ; load the credit indicator
0083: A7          and     a           ; are there credits present / is a game being played ?
0084: C2 B5 00    jp      nz,$00b5    ; No, jump ahead

0087: 3A 26 60    ld      a,(uprightcab_6026) ; yes, load A with upright/cocktail
008A: A7          and     a           ; upright ?
008B: C2 98 00    jp      nz,$0098    ; yes, jump ahead

008E: 3A 0E 60    ld      a,(playerturnb_600e) ; else load A with player number
0091: A7          and     a           ; is this player 2 ?
0092: 3A 80 7C    ld      a,(in1)     ; load A with raw input from player 2
0095: C2 9B 00    jp      nz,$009b    ; yes, skip next step

0098: 3A 00 7C    ld      a,(in0)     ; load A with raw input from player 1
009B: 47          ld      b,a         ; copy to B
009C: E6 0F       and     $0f         ; mask left 4 bits to zero
009E: 4F          ld      c,a         ; copy this to C
009F: 3A 11 60    ld      a,(rawinput_6011) ; load A with player input
00A2: 2F          cpl                 ; The contents of A are inverted (one’s complement).
00A3: A0          and     b           ; logical and with raw input - checks for jump button
00A4: E6 10       and     $10         ; mask all bits but 4.  if jump was pressed it is there
00A6: 17          rla
00A7: 17          rla
00A8: 17          rla                 ; rotate left 3 times
00A9: B1          or      c           ; mix back into masked input
00AA: 60          ld      h,b         ; load H with B = raw input
00AB: 6F          ld      l,a         ; load L with A = modified input
00AC: 22 10 60    ld      (inputstate_6010),hl; store into input memories, InputState and RawInput
00AF: 78          ld      a,b         ; load A with raw input
00B0: CB 77       bit     6,a         ; is the bit 6 set for reset?
00B2: C2 00 00    jp      nz,$0000    ; if reset, jump back to #0000 for a reboot

00B5: 21 1A 60    ld      hl,framecounter_601a; else load HL with Timer constantly counts down from FF to 00 and then FF to 00 again and again ... 1 count per frame
00B8: 35          dec     (hl)        ; decrease this timer
00B9: CD 57 00    call    $0057       ; update the random number gen
00BC: CD 7B 01    call    $017b       ; check for credits being inserted and handle them
00BF: CD E0 00    call    $00e0       ; update all sounds
00C2: 21 D2 00    ld      hl,$00d2    ; load HL with return address
00C5: E5          push    hl          ; push to stack so any RETs go there (#00D2)
00C6: 3A 05 60    ld      a,(gamemode1_6005) ; load A with game mode1

; GameMode1 is 0 when game is turned on, 1 when in attract mode.  2 when credits in waiting for start, 3 when playing game

                RST     #28             ; jump based on above:

00CA  C3 01                             ; #01C3 = startup
00CC  3C 07                             ; #073C = attract mode
00CE  B2 08                             ; #08B2 = credits, waiting
00D0  FE 06                             ; #06FE = playing game

; return here from any of the jumps above, based on return address pushed to stack at #00C5

00D2: FD E1       pop     iy
00D4: DD E1       pop     ix
00D6: E1          pop     hl
00D7: D1          pop     de
00D8: C1          pop     bc          ; restore all registers except AF

00D9: 3E 01       ld      a,$01       ; A := 1
00DB: 32 84 7D    ld      (reg_vblank_enable),a; enable interrupts
00DE: F1          pop     af          ; restore AF
00DF: C9          ret                 ; return from interrupt

; called from #00BF
; updates all sounds

00E0: 21 80 60    ld      hl,walking_sound_buffer_6080    ; source data at sound buffer
00E3: 11 00 7D    ld      de,reg_sfx  ; set destination to sound outputs
00E6: 3A 07 60    ld      a,(nocredits_6007) ; load A with credit indicator
00E9: A7          and     a           ; have credits been inserted / is there a game being played ?
00EA: C0          ret     nz          ; no, return [change to NOP to enable sound in demo ]

; this sub writes the sound buffer to the hardware
; sounds have durations to play in the buffer

00EB: 06 08       ld      b,$08       ; yes, there was a credit or a game is being played.  For B = 1 to 8 Do:

00ED: 7E          ld      a,(hl)      ; load A with sound duration / sound effect for the sound
00EE: A7          and     a           ; is there a sound to play ?
00EF: CA F5 00    jp      z,$00f5     ; no, skip next 2 steps

00F2: 35          dec     (hl)        ; yes, decrease the duration
00F3: 3E 01       ld      a,$01       ; A := 1

00F5: 12          ld      (de),a      ; store sound to output (play sound)
00F6: 1C          inc     e           ; next output address
00F7: 2C          inc     l           ; next source address
00F8: 10 F3       djnz    $00ed       ; Next B

00FA: 21 8B 60    ld      hl,music_timer_608b    ; load HL with music timer
00FD: 7E          ld      a,(hl)      ; load A with this value
00FE: A7          and     a           ; == 0 ?
00FF: C2 08 01    jp      nz,$0108    ; no, skip ahead 4 steps

0102: 2D          dec     l           ; else
0103: 2D          dec     l           ; HL := #6089
0104: 7E          ld      a,(hl)      ; load A with this value to use for music
0105: C3 0B 01    jp      $010b       ; skip next 3 steps

0108: 35          dec     (hl)        ; decrease timer
0109: 2D          dec     l           ; HL := #608A
010A: 7E          ld      a,(hl)      ; load A with this tune to use

010B: 32 00 7C    ld      (reg_music),a; play music
010E: 21 88 60    ld      hl,play_death_sound_6088    ; load HL with address/counter for mario dying sound
0111: AF          xor     a           ; A := 0
0112: BE          cp      (hl)        ; compare.  is mario dying ?
0113: CA 18 01    jp      z,$0118     ; no, skip next 2 steps

0116: 35          dec     (hl)        ; else decrease the counter
0117: 3C          inc     a           ; A := 1

0118: 32 80 7D    ld      (reg_sfx_death),a; store A into digital sound trigger -death (?)
011B: C9          ret                 ; return

; clear all sounds
; called from several places

011C: 06 08       ld      b,$08       ; For B = 1 to 8
011E: AF          xor     a           ; A := 0
011F: 21 00 7D    ld      hl,reg_sfx  ; [REG_SFX..REG_SFX+7] get all zeros
0122: 11 80 60    ld      de,walking_sound_buffer_6080    ; #6080-#6088 get all zeros - clears sound buffer

0125: 77          ld      (hl),a      ; clear this memory - clears sound outputs
0126: 12          ld      (de),a      ; clear this memory
0127: 2C          inc     l           ; next memory
0128: 1C          inc     e           ; next memory
0129: 10 FA       djnz    $0125       ; Next B

012B: 06 04       ld      b,$04       ; For B = 1 to 4

012D: 12          ld      (de),a      ; #6088-#608B get all zeros
012E: 1C          inc     e           ; next DE
012F: 10 FC       djnz    $012d       ; Next B

0131: 32 80 7D    ld      (reg_sfx_death),a; clear the digital sound trigger (death)
0134: 32 00 7C    ld      (reg_music),a; clear the sound output
0137: C9          ret                 ; return

; data used in sub below

0138  53 00 69 80 41 00 70 80
0140  81

; called from #007D
; HL is preloaded with #0138
; This copies the sprite data from $6900 to $7000
; Presumably the reason sprite data isn't stored in $7000 in the first place is to ensure it's updated only during vblank.

0141: AF          xor     a           ; A := 0
0142: 32 85 7D    ld      (reg_dma),a ; store into P8257 DRQ DMA Request
0145: 7E          ld      a,(hl)      ; load table data (#53)
0146: 32 08 78    ld      ($7808),a   ; store into P8257 control register
0149: 23          inc     hl          ; next table entry
014A: 7E          ld      a,(hl)      ; load table data (#00)
014B: 32 00 78    ld      ($7800),a   ; store into P8257 control register
014E: 23          inc     hl          ; next table entry
014F: 7E          ld      a,(hl)      ; load table data (#69)
0150: 32 00 78    ld      ($7800),a   ; store into P8257 control register
0153: 23          inc     hl          ; next table entry
0154: 7E          ld      a,(hl)      ; load table data (#80)
0155: 32 01 78    ld      ($7801),a   ; store into P8257 control register
0158: 23          inc     hl          ; next table entry
0159: 7E          ld      a,(hl)      ; load table data (#41)
015A: 32 01 78    ld      ($7801),a   ; store into P8257 control register
015D: 23          inc     hl          ; next table entry
015E: 7E          ld      a,(hl)      ; load table data (#00)
015F: 32 02 78    ld      ($7802),a   ; store into P8257 control register
0162: 23          inc     hl          ; next table entry
0163: 7E          ld      a,(hl)      ; load table data (#70)
0164: 32 02 78    ld      ($7802),a   ; store into P8257 control register
0167: 23          inc     hl          ; next table entry
0168: 7E          ld      a,(hl)      ; load table data (#80)
0169: 32 03 78    ld      ($7803),a   ; store into P8257 control register
016C: 23          inc     hl          ; next table entry
016D: 7E          ld      a,(hl)      ; load table data (#81)
016E: 32 03 78    ld      ($7803),a   ; store into P8257 control register
0171: 3E 01       ld      a,$01       ; A := 1
0173: 32 85 7D    ld      (reg_dma),a ; store into P8257 DRQ DMA Request
0176: AF          xor     a           ; A := 0
0177: 32 85 7D    ld      (reg_dma),a ; store into P8257 DRQ DMA Request
017A: C9          ret                 ; return

; called from #00BC
; checks for and handles credits

017B: 3A 00 7D    ld      a,(in2)     ; load A with IN2
017E: CB 7F       bit     7,a         ; is the coin switch active?
0180: 21 03 60    ld      hl,coinswitch_6003; load HL with pointer to coin switch indicator
0183: C2 89 01    jp      nz,$0189    ; yes, skip next 2 steps

0186: 36 01       ld      (hl),$01    ; otherwise store 1 into coin switch indicator  -  this is for coin insertion
0188: C9          ret                 ; return

0189: 7E          ld      a,(hl)      ; Load A with coin switch indicator
018A: A7          and     a           ; has a coin been inserted ?
018B: C8          ret     z           ; no, return

; coin has been inserted

018C: E5          push    hl          ; else save HL to stack
018D: 3A 05 60    ld      a,(gamemode1_6005) ; load A with game mode1
0190: FE 03       cp      $03         ; is someone playing?
0192: CA 9D 01    jp      z,$019d     ; yes, skip ahead and don't play the sound

0195: CD 1C 01    call    $011c       ; no, then clear all sounds
0198: 3E 03       ld      a,$03       ; load sound duration
019A: 32 83 60    ld      (play_sound_for_bouncer_6083),a   ; plays the coin insert sound

019D: E1          pop     hl          ; restore HL from stack
019E: 36 00       ld      (hl),$00    ; store 0 into coin switch indicator - no more coins
01A0: 2B          dec     hl          ; HL := CoinCounter
01A1: 34          inc     (hl)        ; increase this counter
01A2: 11 24 60    ld      de,coinspercredit2_6024; load DE with # of coins needed per credit
01A5: 1A          ld      a,(de)      ; load A with coins needed
01A6: 96          sub     (hl)        ; has the player inserted enough coins for a new credit?
01A7: C0          ret     nz          ; yes, return (CoinCounter is now zero)

01A8: 77          ld      (hl),a      ; no; restore CoinCounter
01A9: 13          inc     de          ; DE := CreditsPerCoin
01AA: 2B          dec     hl          ; HL := NumCredits
01AB: EB          ex      de,hl       ; DE := NumCredits, HL := CreditsPerCoin
01AC: 1A          ld      a,(de)      ; load A with number of credits in BCD
01AD: FE 90       cp      max_credits ; is the number of credits already maxed out?
01AF: D0          ret     nc          ; yes; return

01B0: 86          add     a,(hl)      ; add number of credits with # of credits per coin
01B1: 27          daa                 ; decimal adjust
01B2: 12          ld      (de),a      ; store result in credits
01B3: 11 00 04    ld      de,$0400    ; load task #4 - draws credits on screen if any are present
01B6: CD 9F 30    call    $309f       ; insert task
01B9: C9          ret                 ; return

; table data used below in 01C6

01BA  00 37 00 AA AA AA 50 76 00

; this is called when the game is first turned on or reset from #00C9

01C3: CD 74 08    call    $0874       ; clears the screen and sprites
01C6: 21 BA 01    ld      hl,$01ba    ; start of table data above
01C9: 11 B2 60    ld      de,player_1_score_address_60b2    ; set destination
01CC: 01 09 00    ld      bc,$0009    ; set counter to 9
01CF: ED B0       ldir                ; copy 9 bytes above into #60B2-#60BB
01D1: 3E 01       ld      a,$01       ; A := 1
01D3: 32 07 60    ld      (nocredits_6007),a; store into credit indicator == no credits exist
01D6: 32 29 62    ld      (level_number_6229),a   ; initialize level to 1
01D9: 32 28 62    ld      (number_of_lives_remaining_6228),a   ; set number of lives remaining to 1
01DC: CD B8 06    call    $06b8       ; if a game is played or credits exist, display remaining lives-1 and level
01DF: CD 07 02    call    $0207       ; set all dip switch settings and create default high score table from ROM
01E2: 3E 01       ld      a,$01       ; A := 1
01E4: 32 82 7D    ld      (reg_flipscreen),a; store into flip screen setting
01E7: 32 05 60    ld      (gamemode1_6005),a; store into game mode 1
01EA: 32 27 62    ld      (screen_number_6227),a   ; initialize screen to 1 (girders)
01ED: AF          xor     a           ; A := 0
01EE: 32 0A 60    ld      (gamemode2_600a),a; store into game mode 2
01F1: CD 53 0A    call    $0a53       ; draw "1UP" on screen
01F4: 11 04 03    ld      de,$0304    ; load task data to draw "HIGH SCORE"
01F7: CD 9F 30    call    $309f       ; insert task to draw text
01FA: 11 02 02    ld      de,$0202    ; load task #2, parameter 2 to display the high score
01FD: CD 9F 30    call    $309f       ; insert task
0200: 11 00 02    ld      de,$0200    ; load task #2, parameter 0 to display player 1 score
0203: CD 9F 30    call    $309f       ; insert task
0206: C9          ret                 ; return

; this sub reads and sets the dip switch settings, and creates the default high score table

0207: 3A 80 7D    ld      a,(dsw1)    ; load A with Dip switch settings
020A: 4F          ld      c,a         ; copy to C
020B: 21 20 60    ld      hl,startinglives_6020; set destination address to initial number of lives
020E: E6 03       and     $03         ; mask bits, now between 0 and 3 inclusive
0210: C6 03       add     a,$03       ; Add 3, now between 3 and 6 inclusive
0212: 77          ld      (hl),a      ; store in initial number of lives
0213: 23          inc     hl          ; next HL, now at ExtraLifeThreshold = score needed for extra life
0214: 79          ld      a,c         ; load A with original value of dip switches
0215: 0F          rrca
0216: 0F          rrca                ; rotate right twice
0217: E6 03       and     $03         ; mask bits, now between 0 and 3
0219: 47          ld      b,a         ; copy to B.  used in minisub below for loop counter
021A: 3E 07       ld      a,$07       ; A := 7 = default score for extra life
021C: CA 26 02    jp      z,$0226     ; on zero, jump ahead and use 7

021F: 3E 05       ld      a,$05       ; A : = 5

0221: C6 05       add     a,$05       ; add 5
0223: 27          daa                 ; decimal adjust
0224: 10 FB       djnz    $0221       ; loop until done

0226: 77          ld      (hl),a      ; store the result in score for extra life
0227: 23          inc     hl          ; HL := CoinsPerCredit
0228: 79          ld      a,c         ; load A with dipswitch
0229: 01 01 01    ld      bc,$0101    ; B := 1, C := 1
022C: 11 02 01    ld      de,$0102    ; D := 1, E := 2
022F: E6 70       and     $70         ; mask bits.  turns off all except the 3 used for coins/credits
0231: 17          rla
0232: 17          rla
0233: 17          rla
0234: 17          rla                 ; rotate left 4 times.  now in lower 3 bits
0235: CA 47 02    jp      z,$0247     ; if zero, skip ahead and leave BC and DE alone

0238: DA 41 02    jp      c,$0241     ; if there was a carry, skip ahead

023B: 3C          inc     a           ; increase A
023C: 4F          ld      c,a         ; store into C
023D: 5A          ld      e,d         ; E := 1
023E: C3 47 02    jp      $0247       ; skip ahead

0241: C6 02       add     a,$02       ; else A := 2
0243: 47          ld      b,a         ; B := 2
0244: 57          ld      d,a         ; D := 2
0245: 87          add     a,a         ; A := 4
0246: 5F          ld      e,a         ; E := 4

0247: 72          ld      (hl),d      ; store D into CoinsPerCredit
0248: 23          inc     hl          ; HL := CoinsPer2Credits
0249: 73          ld      (hl),e      ; store E into CoinsPer2Credits
024A: 23          inc     hl          ; HL := CoinsPerCredit2
024B: 70          ld      (hl),b      ; store B into CoinsPerCredit2
024C: 23          inc     hl          ; HL := CreditsPerCoin
024D: 71          ld      (hl),c      ; store DE and BC into coins/credits
024E: 23          inc     hl          ; HL := UprightCab = memory for upright/cocktail
024F: 3A 80 7D    ld      a,(dsw1)    ; load A with dipswitch settings
0252: 07          rlca                ; rotate left
0253: 3E 01       ld      a,$01       ; A := 1
0255: DA 59 02    jp      c,$0259     ; if carry, skip next step

0258: 3D          dec     a           ; A := 0

0259: 77          ld      (hl),a      ; store into upright / cocktail
025A: 21 65 35    ld      hl,$3565    ; source = #3565 = default high score table
025D: 11 00 61    ld      de,high_score_ram_6100    ; dest = #6100 = high score RAM
0260: 01 AA 00    ld      bc,$00aa    ; byte counter = #AA
0263: ED B0       ldir                ; copy high score table into RAM
0265: C9          ret                 ; return

; come here from game power-on
; first, clear system RAM
Init_0266:
0266: 06 10       ld      b,$10       ; for B = 0 to #10
0268: 21 00 60    ld      hl,ram      ; set destination
026B: AF          xor     a           ; A := 0

026C: 4F          ld      c,a         ; For C = 0 to #FF

026D: 77          ld      (hl),a      ; store 0 into memory
026E: 23          inc     hl          ; next location
026F: 0D          dec     c           ; Next C
0270: 20 FB       jr      nz,$026d    ; Loop until done

0272: 10 F8       djnz    $026c       ; Next B

; clears sprite memory

0274: 06 04       ld      b,$04       ; For B = 1 to 4
0276: 21 00 70    ld      hl,sprite_ram; load HL with start address
0279: 4F          ld      c,a         ; For C = 0 to #FF

027A: 77          ld      (hl),a      ; Clear this memory
027B: 23          inc     hl          ; next memory
027C: 0D          dec     c           ; Next C
027D: 20 FB       jr      nz,$027a    ; loop until done

027F: 10 F8       djnz    $0279       ; Next B

; this subroutine clears the VIDEO RAM with #10 (clear shape)

0281: 06 04       ld      b,$04       ; for B = 1 to 4
0283: 3E 10       ld      a,$10       ; #10 is the code for clear on the screen
0285: 21 00 74    ld      hl,$7400    ; load HL with beginning of graphics memory

0288: 0E 00       ld      c,$00       ; For C = 1 to #FF

028A: 77          ld      (hl),a      ; load clear into video RAM
028B: 23          inc     hl          ; next location
028C: 0D          dec     c
028D: 20 FB       jr      nz,$028a    ; Next C

028F: 10 F7       djnz    $0288       ; Next B

; Loads #60C0 to #60FF (task list) with #FF

0291: 21 C0 60    ld      hl,start_of_task_list_60c0    ; HL points to start of task list
0294: 06 40       ld      b,$40       ; For B = 1 to #40
0296: 3E FF       ld      a,$ff       ; load A with code for no task

0298: 77          ld      (hl),a      ; store into task location
0299: 23          inc     hl          ; next location
029A: 10 FC       djnz    $0298       ; Next B

; reset some memories to 0 and 1

029C: 3E C0       ld      a,$c0       ; load A with #C0 for the #60B0 and #60B1 timers
029E: 32 B0 60    ld      (task_list_pointer_60b0),a   ; store into timer
02A1: 32 B1 60    ld      (the_task_pointer_60b1),a   ; store into timer
02A4: AF          xor     a           ; A := 0
02A5: 32 83 7D    ld      (reg_sprite),a; Clear dkong_spritebank_w  /* 2 PSL Signal */

02A8: 32 86 7D    ld      (reg_palette_a),a; clear palette bank selector
02AB: 32 87 7D    ld      (reg_palette_b),a; clear palette bank selector
02AE: 3C          inc     a           ; A: = 1
02AF: 32 82 7D    ld      (reg_flipscreen),a; set flip screen setting
02B2: 31 00 6C    ld      sp,stack_pointer_6c00    ; set Stack Pointer to #6C00
02B5: CD 1C 01    call    $011c       ; clear all sounds
02B8: 3E 01       ld      a,$01       ; A := 1
02BA: 32 84 7D    ld      (reg_vblank_enable),a; enable interrupts

;
; arrive after RET encountered after #0306 jump
; check for tasks and do them if they exist
;

02BD: 26 60       ld      h,$60       ; H := #60
02BF: 3A B1 60    ld      a,(the_task_pointer_60b1)   ; load A with task pointer
02C2: 6F          ld      l,a         ; copy to L.  HL now has #60XX which is the current task
02C3: 7E          ld      a,(hl)      ; load A with task
02C4: 87          add     a,a         ; double.  Is there a task to do ?
02C5: 30 1C       jr      nc,$02e3    ; yes, skip ahead to handle task

02C7: CD 15 03    call    $0315       ; else flash the "1UP" above the score when it is time to do so
02CA: CD 50 03    call    $0350       ; check for and handle awarding extra lives
02CD: 21 19 60    ld      hl,rngtimer2_6019; load HL with timer
02D0: 34          inc     (hl)        ; increase the timer
02D1: 21 83 63    ld      hl,memory_used_to_track_tasks_6383    ; load HL with address of memory used to track tasks
02D4: 3A 1A 60    ld      a,(framecounter_601a) ; load A with timer that constantly counts down from #FF to 0
02D7: BE          cp      (hl)        ; equal ?
02D8: 28 E3       jr      z,$02bd     ; yes, loop back to check for more tasks

02DA: 77          ld      (hl),a      ; else store A into the memory, for next time
02DB: CD 7F 03    call    $037f       ; check for updating of difficulty
02DE: CD A2 03    call    $03a2       ; check for releasing fires on girders and conveyors
02E1: 18 DA       jr      $02bd       ; loop back to check for more tasks

; arrive from #02C5
; loads data from the task list at #60C0 through #60CF
; tasks are loaded in subroutine at #309F
; HL is preloaded with task pointer
; A is preloaded with 2x the task number

02E3: E6 1F       and     $1f         ; mask bits.  A now between 0 and #1F
02E5: 5F          ld      e,a         ; copy to E
02E6: 16 00       ld      d,$00       ; D := 0
02E8: 36 FF       ld      (hl),$ff    ; overwrite the task with empty entry
02EA: 2C          inc     l           ; next HL
02EB: 4E          ld      c,(hl)      ; load C with the 2nd byte of the task (parameter)
02EC: 36 FF       ld      (hl),$ff    ; overwrite the task with empty entry
02EE: 2C          inc     l           ; next HL
02EF: 7D          ld      a,l         ; load A with low byte of the address
02F0: FE C0       cp      $c0         ; < #C0 ?
02F2: 30 02       jr      nc,$02f6    ; no, skip next step

02F4: 3E C0       ld      a,$c0       ; reset low byte to #C0

02F6: 32 B1 60    ld      (the_task_pointer_60b1),a   ; store into the task pointer
02F9: 79          ld      a,c         ; load A with the 2nd byte of the task
02FA: 21 BD 02    ld      hl,$02bd    ; load HL with return address
02FD: E5          push    hl          ; push to stack so RET will go to #02BD = task list
02FE: 21 07 03    ld      hl,$0307    ; load HL with data from table below
0301: 19          add     hl,de       ; add the offset based on byte 1 of the task
0302: 5E          ld      e,(hl)      ; load E with the low byte from the table below
0303: 23          inc     hl          ; next HL
0304: 56          ld      d,(hl)      ; load D with the high byte from the table
0305: EB          ex      de,hl       ; DE <> HL
0306: E9          jp      (hl)        ; jump to address from the table

; data for jump table used above
; task table

0307  1C 05                             ; #051C ; 0, for adding to score.  parameter is score in hundreds
0309  9B 05                             ; #059B ; 1, clears and displays scores.  parameter 0 for p1, 1 for p2
030B  C6 05                             ; #05C6 ; 2, displays score.  0 for p1, 1 for p2, 2 for highscore
030D  E9 05                             ; #05E9 ; 3, used to draw text.  parameter is code for text to draw
030F  11 06                             ; #0611 ; 4, draws credits on screen if any are present
0311  2A 06                             ; #062A ; 5, parameter 0 adds bonus to player's score , parameter 1 update onscreen bonus timer and play sound & change to red if below 1000
0313  B8 06                             ; #06B8 ; 6, draws remaining lives and level number.  parameter 1 to draw lives-1

; called from #02C7
; flashes 1UP or 2UP

0315: 3A 1A 60    ld      a,(timer_constantly_counts_down_601a)   ; load A with timer constantly counts down from FF to 00 and then FF to 00 again and again ... 1 count per frame
0318: 47          ld      b,a         ; copy to B
0319: E6 0F       and     $0f         ; mask bits, now between 0 and #F.  Is it zero ?
031B: C0          ret     nz          ; no, return

031C: CF          rst     $8          ; if credits exist or someone is playing, continue.  else RET

031D: 3A 0D 60    ld      a,(playerturna_600d) ; Load A with player # (0 for player 1, 1 for player 2)
0320: CD 47 03    call    $0347       ; Loads HL with location for score (either player 1 or 2)
0323: 11 E0 FF    ld      de,$ffe0    ; load DE with offset for each column
0326: CB 60       bit     4,b         ; test bit 4 of timer.  Is it zero ?
0328: 28 14       jr      z,$033e     ; yes, skip ahead

032A: 3E 10       ld      a,$10       ; A := #10 = blank character
032C: 77          ld      (hl),a      ; clear the text "1" from "1UP" or "2" from "2UP"
032D: 19          add     hl,de       ; add offset for next column
032E: 77          ld      (hl),a      ; clear the text "U" from "1UP"
032F: 19          add     hl,de       ; next column
0330: 77          ld      (hl),a      ; clear the text "P" from "1UP"
0331: 3A 0F 60    ld      a,(twoplayergame_600f) ; load A with # of players in game
0334: A7          and     a           ; is this a 1 player game?
0335: C8          ret     z           ; yes, return

0336: 3A 0D 60    ld      a,(playerturna_600d) ; Load current player #
0339: EE 01       xor     $01         ; change player from 1 to 2 or from 2 to 1
033B: CD 47 03    call    $0347       ; Loads HL with location for score (either player 1 or 2)

033E: 3C          inc     a           ; increase A, now it has the number of the player
033F: 77          ld      (hl),a      ; draw player number on screen
0340: 19          add     hl,de       ; next column
0341: 36 25       ld      (hl),$25    ; draw "U" on screen
0343: 19          add     hl,de       ; next column
0344: 36 20       ld      (hl),$20    ; draw "P" on screen
0346: C9          ret                 ; return

; called from #033B

0347: 21 40 77    ld      hl,$7740    ; for player 1 HL gets #7740 VRAM address
034A: A7          and     a           ; is this player 2?
034B: C8          ret     z           ; no, then return

034C: 21 E0 74    ld      hl,$74e0    ; player 2 gets #74E0 location on screen
034F: C9          ret                 ; return

; called from #02CA
; checks for and handles extra life

0350: 3A 2D 62    ld      a,(extra_life_indicator_622d)   ; load A with high score indicator
0353: A7          and     a           ; has this player already been awarded extra life?
0354: C0          ret     nz          ; yes, return

0355: 21 B3 60    ld      hl,address_for_player_1_score_60b3    ; load HL with address for player 1 score
0358: 3A 0D 60    ld      a,(playerturna_600d) ; load A with 0 when player 1 is up, 1 when player 2 is up
035B: A7          and     a           ; player 1 up ?
035C: 28 03       jr      z,$0361     ; yes, skip next step

035E: 21 B6 60    ld      hl,address_of_player_2_score_60b6    ; else load HL with address of player 2 score

0361: 7E          ld      a,(hl)      ; load A with a byte of the player's score
0362: E6 F0       and     $f0         ; mask bits
0364: 47          ld      b,a         ; copy to B
0365: 23          inc     hl          ; next score byte
0366: 7E          ld      a,(hl)      ; load A with byte of player's score
0367: E6 0F       and     $0f         ; mask bits
0369: B0          or      b           ; mix together the 2 score bytes
036A: 0F          rrca
036B: 0F          rrca
036C: 0F          rrca
036D: 0F          rrca                ; rotate right 4 times, this swaps the high and low bytes
036E: 21 21 60    ld      hl,extralifethreshold_6021; load HL with score needed for extra life
0371: BE          cp      (hl)        ; compare player's score to high score.  is it greater?
0372: D8          ret     c           ; no, return

0373: 3E 01       ld      a,$01       ; A := 1
0375: 32 2D 62    ld      (extra_life_indicator_622d),a   ; store into extra life indicator
0378: 21 28 62    ld      hl,number_of_lives_remaining_6228    ; load HL with address of number of lives remaining
037B: 34          inc     (hl)        ; increase
037C: C3 B8 06    jp      $06b8       ; skip ahead and update # of lives on the screen

; called from #02DB
; checks timers and increments difficulty if needed

; [timer_6384++ ; IF timer_6384 != 256 THEN RETURN ; timer_6384 := 0 ; ]

037F: 21 84 63    ld      hl,timer_address_6384    ; load HL with timer address
0382: 7E          ld      a,(hl)      ; load A with the timer
0383: 34          inc     (hl)        ; increase the timer
0384: A7          and     a           ; was the timer at zero?
0385: C0          ret     nz          ; no, return

; [timer_6381++ ; IF (timer_6381/8) != INT(timer_6381/8) THEN RETURN]

0386: 21 81 63    ld      hl,timer_6381    ; load HL with timer
0389: 7E          ld      a,(hl)      ; load A with timer value
038A: 47          ld      b,a         ; copy to B
038B: 34          inc     (hl)        ; increase timer
038C: E6 07       and     $07         ; mask bits.  are right 3 bits == #000 ? does for every 8 steps of #6381
038E: C0          ret     nz          ; no, return

; increase difficulty if not at max

; [ difficulty := (timer_6381 div 8) + level ; IF difficulty > 5 THEN difficulty := 5 ; RETURN]

038F: 78          ld      a,b         ; load A with original timer value
0390: 0F          rrca                ; roll right 3 times... (div 8)
0391: 0F          rrca
0392: 0F          rrca
0393: 47          ld      b,a         ; store result into B
0394: 3A 29 62    ld      a,(level_number_6229)   ; load A with level number
0397: 80          add     a,b         ; add B to A
0398: FE 05       cp      $05         ; is this answer > 5 ?
039A: 38 02       jr      c,$039e     ; no, skip next step

039C: 3E 05       ld      a,$05       ; otherwise A := 5

039E: 32 80 63    ld      (difficulty_level_6380),a   ; store result into difficulty
03A1: c9          ret                 ; return to #02DE

; called from #02DE

03A2: 3E 03       ld      a,$03       ; A := 3 = 0011 binary
03A4: F7          rst     $30         ; only continue if level is girders or conveyors, else RET

03A5: D7          rst     $10         ; if mario is alive, continue, else RET

03A6: 3A 50 63    ld      a,(item_hit_indicator_unknown_6350)   ; load A with 1 when an item has been hit with hammer
03A9: 0F          rrca                ; has an item been hit with the hammer ?
03AA: D8          ret     c           ; yes, return, we don't do anything here while hammer hits occur

03AB: 21 B8 62    ld      hl,this_counter_62b8    ; load HL with this counter
03AE: 35          dec     (hl)        ; decrease.  at zero?
03AF: C0          ret     nz          ; no, return

03B0: 36 04       ld      (hl),$04    ; yes, reset counter to 4
03B2: 3A B9 62    ld      a,(fire_release_62b9)   ; load A with fire release indicator
03B5: 0F          rrca                ; roll right.  carry?  Is there a fire onscreen or is it time to release a new fire?
03B6: D0          ret     nc          ; no, return

; a fire is onscreen or to be released

03B7: 21 29 6A    ld      hl,sprite_for_fire_above_oil_can_6a29    ; load HL with sprite for fire above oil can
03BA: 06 40       ld      b,$40       ; B := #40
03BC: DD 21 A0 66 ld      ix,oil_can_address_66a0    ; load IX with fire array start ?
03C0: 0F          rrca                ; roll A right again.  carry ?  Is it time to release another fire?
03C1: D2 E4 03    jp      nc,$03e4    ; no, skip ahead, animate oilcan, reset timer and return

; release a fire

03C4: DD 36 09 02 ld      (ix+$09),$02; store 2 into sprite +9 indicator (size ???)
03C8: DD 36 0A 02 ld      (ix+$0a),$02; store 2 into sprite +#A indicator (size ???)
03CC: 04          inc     b
03CD: 04          inc     b           ; B := #42 = extra fire oilcan sprite value
03CE: CD F2 03    call    $03f2       ; randomly store B or B+1 into (HL) - animates the oilcan fire with extra fire
03D1: 21 BA 62    ld      hl,timer_reset_62ba    ; load HL with this timer.  usually it is set at #10 when a level begins
03D4: 35          dec     (hl)        ; decrease timer.  zero ?
03D5: C0          ret     nz          ; no, return

; release a fire, or do something when fires already exist

03D6: 3E 01       ld      a,$01       ; A := 1
03D8: 32 B9 62    ld      (fire_release_62b9),a   ; store into fire release indicator
03DB: 32 A0 63    ld      (unknown_63a0),a   ; store into other fireball release indicator

03DE: 3E 10       ld      a,$10       ; A := #10
03E0: 32 BA 62    ld      (timer_reset_62ba),a   ; reset timer back to #10
03E3: C9          ret                 ; return

03E4: DD 36 09 02 ld      (ix+$09),$02; set +9 to 2 (size ???)
03E8: DD 36 0A 00 ld      (ix+$0a),$00; set +A to 0 (size ???)
03EC: CD F2 03    call    $03f2       ; randomly store B or B+1 into (HL) - animates the oilcan fire
03EF: C3 DE 03    jp      $03de       ; skip back, reset timer, and return

; called from #03CE and #03EC above
; animates the oilcan fire

03F2: 70          ld      (hl),b      ; store B into (HL) - set the oilcan fire sprite
03F3: 3A 19 60    ld      a,(rngtimer2_6019) ; load A with random number
03F6: 0F          rrca                ; rotate right.  carry ?
03F7: D8          ret     c           ; yes, return

03F8: 04          inc     b           ; else increase B
03F9: 70          ld      (hl),b      ; store B into (HL) - set the oilcan fire sprite with higher value
03FA: C9          ret                 ; return

; called from main routine at #19B0
; animates kong, checks for kong beating chest, animates girl and her screams for help

03FB: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
03FE: FE 02       cp      $02         ; are we on the conveyors?
0400: C2 13 04    jp      nz,$0413    ; no, skip ahead

; conveyors

0403: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with kongs sprite start
0406: 3A A3 63    ld      a,(top_conveyor_direction_vector_63a3)   ; load A with kongs direction
0409: 4F          ld      c,a         ; copy to C for subroutine below
040A: FF          rst     $38         ; move kong
040B: 3A 10 69    ld      a,(kongs_x_position_6910)   ; load A with kong's X position
040E: D6 3B       sub     $3b         ; subtract #3B (59 decimal)
0410: 32 B7 63    ld      (kongs_position_63b7),a   ; store into kong's position

; #6390 - counts from 0 to 7F periodically
; #6391 - is 0, then changed to 1 when timer in #6390 is counting up

0413: 3A 91 63    ld      a,(indicator_6391)   ; load A with indicator
0416: A7          and     a           ; == 0 ?
0417: C2 26 04    jp      nz,$0426    ; no, skip next 5 steps

041A: 3A 1A 60    ld      a,(framecounter_601a) ; else load A with this clock counts down from #FF to 00 over and over...
041D: A7          and     a           ; == 0 ?
041E: C2 86 04    jp      nz,$0486    ; no, skip ahead

0421: 3E 01       ld      a,$01       ; else A := 1
0423: 32 91 63    ld      (indicator_6391),a   ; store into indicator

0426: 21 90 63    ld      hl,timer_unknown_6390    ; load HL with timer
0429: 34          inc     (hl)        ; increase
042A: 7E          ld      a,(hl)      ; load A with timer value
042B: FE 80       cp      $80         ; == #80 ?
042D: CA 64 04    jp      z,$0464     ; yes, skip ahead

0430: 3A 93 63    ld      a,(barrel_deployment_indicator_6393)   ; else get barrel deployment
0433: A7          and     a           ; is a barrel deployment in progress?
0434: C2 86 04    jp      nz,$0486    ; yes, jump ahead

0437: 7E          ld      a,(hl)      ; else load A with timer
0438: 47          ld      b,a         ; copy to B
0439: E6 1F       and     $1f         ; mask bits, now == 0 ?
043B: C2 86 04    jp      nz,$0486    ; no, skip ahead

043E: 21 CF 39    ld      hl,$39cf    ; else load HL with start of table data
0441: CB 68       bit     5,b         ; is bit 5 turned on timer ?  (1/8 chance???)
0443: 20 03       jr      nz,$0448    ; no, skip ahead

; kong is beating his chest

0445: 21 F7 39    ld      hl,$39f7    ; start of table data
0448: CD 4E 00    call    $004e       ; update kong's sprites
044B: 3E 03       ld      a,$03       ; load sound duration of 3
044D: 32 82 60    ld      (boom_sound_address_6082),a   ; play boom sound using sound buffer

0450: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
0453: 0F          rrca                ; is this the girders or the elevators ?
0454: D2 78 04    jp      nc,$0478    ; no, skip ahead

0457: 0F          rrca                ; else is this the rivets ?
0458: DA 86 04    jp      c,$0486     ; yes, skip ahead

; else pie factory

045B: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite data
045E: 0E FC       ld      c,$fc       ; C := #FC.  used in sub below to move kong by -4
0460: FF          rst     $38         ; move kong
0461: C3 86 04    jp      $0486       ; skip ahead

; arrive here from #042D when timer in #6390 is #80

0464: AF          xor     a           ; A := 0
0465: 77          ld      (hl),a      ; clear timer
0466: 23          inc     hl          ; increase address to #6391
0467: 77          ld      (hl),a      ; clear this one too
0468: 3A 93 63    ld      a,(barrel_deployment_indicator_6393)   ; Load Barrel deployment indicator
046B: A7          and     a           ; is a deployment in progress?
046C: C2 86 04    jp      nz,$0486    ; yes, jump ahead

046F: 21 5C 38    ld      hl,$385c    ; else load HL with start of table data for kongs sprites
0472: CD 4E 00    call    $004e       ; update kong's sprites
0475: C3 50 04    jp      $0450       ; jump back

; arrive here from #0454 when on rivets and conveyors
; moves kong, updates girl and her screams for help

0478: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of kong sprite X position
047B: 0E 44       ld      c,$44       ; set offset to #44, used only on rivets
047D: 0F          rrca                ; roll screen number right (again).  is this the conveyors screen?
047E: D2 85 04    jp      nc,$0485    ; no, skip next 2 steps

0481: 3A B7 63    ld      a,(kongs_position_63b7)   ; load A with kong's position
0484: 4F          ld      c,a         ; copy to C for sub below, controls position of kong

0485: FF          rst     $38         ; move kong to his position

0486: 3A 90 63    ld      a,(timer_unknown_6390)   ; load A with timer
0489: 4F          ld      c,a         ; copy to C
048A: 11 20 00    ld      de,$0020    ; DE := #20, used for offset in call at #04A6
048D: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
0490: FE 04       cp      $04         ; are we on the rivets level?
0492: CA BE 04    jp      z,$04be     ; yes, jump ahead to handle

0495: 79          ld      a,c         ; load A with the timer
0496: A7          and     a           ; == 0 ?
0497: CA A1 04    jp      z,$04a1     ; yes, skip next 3 steps

049A: 3E EF       ld      a,$ef       ; else A := #EF
049C: CB 71       bit     6,c         ; is bit 6 of the timer set ?
049E: C2 A3 04    jp      nz,$04a3    ; no, skip next step

04A1: 3E 10       ld      a,$10       ; A := #10

04A3: 21 C4 75    ld      hl,$75c4    ; load HL with address of a location in video RAM where girl yells "HELP"
04A6: CD 14 05    call    $0514       ; update girl yelling "HELP"
04A9: 3A 05 69    ld      a,(girls_sprite_6905)   ; load A with girl's sprite

04AC: 32 05 69    ld      (girls_sprite_6905),a   ; store girl's sprite
04AF: CB 71       bit     6,c         ; is bit 6 of the timer set ?
04B1: C8          ret     z           ; yes, return

04B2: 47          ld      b,a         ; else B := A
04B3: 79          ld      a,c         ; A := C (timer)
04B4: E6 07       and     $07         ; mask bits, now betwen 0 and 7.  zero ?
04B6: C0          ret     nz          ; no, return

04B7: 78          ld      a,b         ; restore A which has girl's sprite
04B8: EE 03       xor     $03         ; toggle bits 0 and 1
04BA: 32 05 69    ld      (girls_sprite_6905),a   ; store into girl's sprite
04BD: C9          ret                 ; return to #19B3 - main routine

; arrive here when we are on the rivets level

04BE: 3E 10       ld      a,$10       ; A := #10 = code for clear space
04C0: 21 23 76    ld      hl,$7623    ; load HL with video RAM for girl location
04C3: CD 14 05    call    $0514       ; clear the "help" the girl yells on the left side
04C6: 21 83 75    ld      hl,$7583    ; load HL with video RAM right of girl
04C9: CD 14 05    call    $0514       ; clear the "help" the girl yells on the right side
04CC: CB 71       bit     6,c         ; check timer bit 6.  zero?
04CE: CA 09 05    jp      z,$0509     ; yes, skip ahead

04D1: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario X position
04D4: FE 80       cp      $80         ; is mario on left side of screen ?
04D6: D2 F1 04    jp      nc,$04f1    ; yes, skip ahead

04D9: 3E DF       ld      a,$df       ; else A := #DF
04DB: 21 23 76    ld      hl,$7623    ; load HL with video RAM for girl location
04DE: CD 14 05    call    $0514       ; draw "help" on the left side

04E1: 3A 01 69    ld      a,(unknown_6901)   ; load A with sprite used for girl
04E4: F6 80       or      $80         ; set bit 7
04E6: 32 01 69    ld      (unknown_6901),a   ; store into sprite used for girl
04E9: 3A 05 69    ld      a,(girls_sprite_6905)   ; load A with girl's sprite
04EC: F6 80       or      $80         ; set bit 7
04EE: C3 AC 04    jp      $04ac       ; jump back and animate girl

04F1: 3E EF       ld      a,$ef       ; A := #EF
04F3: 21 83 75    ld      hl,$7583    ; load HL with video RAM for girl location
04F6: CD 14 05    call    $0514       ; draw "help" on the right side

04F9: 3A 01 69    ld      a,(unknown_6901)   ; load A with sprite used for girl
04FC: E6 7F       and     $7f         ; mask bits, turns off bit 7
04FE: 32 01 69    ld      (unknown_6901),a   ; store result
0501: 3A 05 69    ld      a,(girls_sprite_6905)   ; load A with girl's sprite
0504: E6 7F       and     $7f         ; mask bits, turns off bit 7
0506: C3 AC 04    jp      $04ac       ; jump back and store into girl's sprite and check for animation and RET

; jump from #04CE

0509: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario X position
050C: FE 80       cp      $80         ; is mario on left side of screen?
050E: D2 F9 04    jp      nc,$04f9    ; yes, jump back

0511: C3 E1 04    jp      $04e1       ; else jump back

;
; this sub gets called a lot
; HL is preloaded with an address of video RAM ?
; DE is preloaded with an offset to add
; A is preloaded with a value to write
; writes A into HL, A-1 into HL+DE, A-2 into HL+2DE
;

0514: 06 03       ld      b,$03       ; for B = 1 to 3

0516: 77          ld      (hl),a      ; store A into memory
0517: 19          add     hl,de       ; next memory
0518: 3D          dec     a           ; decrease A
0519: 10 FB       djnz    $0516       ; next B

051B: C9          ret                 ; return

;
; Task #0, arrive from jump at #0306
; adds score
; parameter in A is the score to add in hundreds
;

051C: 4F          ld      c,a         ; copy score to C
051D: CF          rst     $8          ; only continue if credits exist or someone is playing, else RET
051E: CD 5F 05    call    $055f       ; load DE with address of player score
0521: 79          ld      a,c         ; load score
0522: 81          add     a,c         ; double
0523: 81          add     a,c         ; triple
0524: 4F          ld      c,a         ; C is now 3 times A for use in the scoring table
0525: 21 29 35    ld      hl,$3529    ; #3529 holds table data for scoring
0528: 06 00       ld      b,$00       ; B := 0
052A: 09          add     hl,bc       ; add offset for scoring table
052B: A7          and     a           ; clear carry flag
052C: 06 03       ld      b,$03       ; for B = 1 to 3

052E: 1A          ld      a,(de)      ; load A with current score
052F: 8E          adc     a,(hl)      ; add the amount the player just scored
0530: 27          daa                 ; decimal adjust
0531: 12          ld      (de),a      ; store result in score
0532: 13          inc     de          ; next byte of score
0533: 23          inc     hl          ; next byte of score to add
0534: 10 F8       djnz    $052e       ; Next B

0536: D5          push    de          ; save DE
0537: 1B          dec     de          ; DE is now the last byte of score
0538: 3A 0D 60    ld      a,(playerturna_600d) ; 0 for player 1, 1 for player 2
053B: CD 6B 05    call    $056b       ; update onscreen score
053E: D1          pop     de          ; restore DE
053F: 1B          dec     de          ; decrement
0540: 21 BA 60    ld      hl,high_score_60ba    ; load HL with high score address
0543: 06 03       ld      b,$03       ; for B = 1 to  3

0545: 1A          ld      a,(de)      ; load A with player score
0546: BE          cp      (hl)        ; compare to high score
0547: D8          ret     c           ; if less, then return

0548: C2 50 05    jp      nz,$0550    ; if greater, then skip ahead to update

054B: 1B          dec     de          ; next score byte
054C: 2B          dec     hl          ; next highscore byte
054D: 10 F6       djnz    $0545       ; next B

054F: C9          ret                 ; return

0550: CD 5F 05    call    $055f       ; load DE with address of player score
0553: 21 B8 60    ld      hl,high_score_60b8    ; load HL with high score address

0556: 1A          ld      a,(de)      ; load A with player score byte
0557: 77          ld      (hl),a      ; store into high score byte
0558: 13          inc     de          ; next address
0559: 23          inc     hl          ; next address
055A: 10 FA       djnz    $0556       ; next B

055C: C3 DA 05    jp      $05da       ; skip ahead to update high score onscreen

; called from #051E and #0550
; loads DE with address of current player's score

055F: 11 B2 60    ld      de,player_1_score_address_60b2    ; load DE with player 1 score
0562: 3A 0D 60    ld      a,(playerturna_600d) ; load number of players
0565: A7          and     a           ; is this player 2 ?
0566: C8          ret     z           ; no, return

0567: 11 B5 60    ld      de,player_2_score_address_60b5    ; else load DE with player 2 score
056A: C9          ret                 ; return

; called from #053B
; update onscreen score

056B: DD 21 81 77 ld      ix,$7781    ; load IX with the start of the score in video RAM (100,000's place)
056F: A7          and     a           ; is this player 1?
0570: 28 0A       jr      z,$057c     ; Yes, jump ahead

0572: DD 21 21 75 ld      ix,$7521    ; else load IX with #7521 - the start of player 2 score (100,000's place)
0576: 18 04       jr      $057c       ; skip next step

0578: DD 21 41 76 ld      ix,$7641    ; #7641 is the start of high score 100,000 place

057C: EB          ex      de,hl       ; DE <> HL
057D: 11 E0 FF    ld      de,$ffe0    ; offset is inverse of 20 ?  to add to next column in scoreboard
0580: 01 04 03    ld      bc,$0304    ; For B = 1 to 3

; can arrive here from #0627 to draw number of credits

0583: 7E          ld      a,(hl)      ; get digit
0584: 0F          rrca
0585: 0F          rrca
0586: 0F          rrca
0587: 0F          rrca                ; rotate right 4 times
0588: CD 93 05    call    $0593       ; draw to screen
058B: 7E          ld      a,(hl)      ; get digit
058C: CD 93 05    call    $0593       ; draw to screen
058F: 2B          dec     hl          ; next digit
0590: 10 F1       djnz    $0583       ; Next B

0592: C9          ret                 ; return

; called from #0588 and #058C above

0593: E6 0F       and     $0f         ; mask out left 4 bits of A
0595: DD 77 00    ld      (ix+$00),a  ; store A on screen
0598: DD 19       add     ix,de       ; adjust to next location
059A: C9          ret                 ; return

;
; task #1
; called from #0306
; parameter is 0 when 1 player game, 1 when 2 player game
; clears score and runs task #2 as well
;

059B: FE 03       cp      $03         ; task parameter < 3 ?
059D: D2 BD 05    jp      nc,$05bd    ; yes, skip ahead [when would it do this???  A always 0 or 1 ???]

; #60B2, #60B3, #60B4 - player 1 score

; #60B5, #60B6, #60B7 - player 2 score

05A0: F5          push    af          ; save AF
05A1: 21 B2 60    ld      hl,player_1_score_address_60b2    ; load HL with player 1 score
05A4: A7          and     a           ; parameter == 0 ?
05A5: CA AB 05    jp      z,$05ab     ; yes, skip next step

05A8: 21 B5 60    ld      hl,player_2_score_address_60b5    ; else load HL with player 2 score
05AB: FE 02       cp      $02         ; parameter == 2 ? [when would it do this ??? A always 0 or 1 ??? ]
05AD: C2 B3 05    jp      nz,$05b3    ; no, skip next step

05B0: 21 B8 60    ld      hl,high_score_60b8    ; load HL with high score

05B3: AF          xor     a           ; A := 0
05B4: 77          ld      (hl),a      ; clear score
05B5: 23          inc     hl          ; next score memory
05B6: 77          ld      (hl),a      ; clear score
05B7: 23          inc     hl          ; next score memory
05B8: 77          ld      (hl),a      ; clear score
05B9: F1          pop     af          ; restore AF
05BA: C3 C6 05    jp      $05c6       ; jump ahead to task 2

; never arrive here ???

05BD: 3D          dec     a           ; decrease A
05BE: F5          push    af          ; save AF
05BF: CD 9B 05    call    $059b       ; ???  call myself ???
05C2: F1          pop     af          ; restore AF
05C3: C8          ret     z           ; return if Zero

05C4: 18 F7       jr      $05bd       ; else loop again

;
; task #2 - displays score
; called from #0306 and at end of task #1, from #05BA
; parameter is 0 for player 1, 1 for player 2, and 3 for high score
;

05C6: FE 03       cp      $03         ; task parameter == 3 ?
05C8: CA E0 05    jp      z,$05e0     ; yes, skip ahead to handle high score

05CB: 11 B4 60    ld      de,player_1_score_60b4    ; load DE with player 1 score
05CE: A7          and     a           ; parameter == 0 ? (1 player game)
05CF: CA D5 05    jp      z,$05d5     ; yes, skip next step

05D2: 11 B7 60    ld      de,player_2_score_60b7    ; else load DE with player 2 score

05D5: FE 02       cp      $02         ; parameter == 2 ?
05D7: C2 6B 05    jp      nz,$056b    ; no, jump back and display score

; arrive here from #055C

05DA: 11 BA 60    ld      de,high_score_60ba    ; yes, load DE with high score
05DD: C3 78 05    jp      $0578       ; jump back and display high score

05E0: 3D          dec     a           ; decrease A
05E1: F5          push    af          ; save AF
05E2: CD C6 05    call    $05c6       ; call this sub again for the lower parameter
05E5: F1          pop     af          ; restore AF.  A == 0 ?  are we done?
05E6: C8          ret     z           ; yes, return

05E7: 18 F7       jr      $05e0       ; else loop back again

; task #3
; draws text to screen
; called from #0306 with code for text to draw in A

05E9: 21 4B 36    ld      hl,$364b    ; start of table data
05EC: 87          add     a,a         ; double the parameter
05ED: F5          push    af          ; save AF to stack
05EE: E6 7F       and     $7f         ; mask bits
05F0: 5F          ld      e,a         ; copy to E
05F1: 16 00       ld      d,$00       ; D := 0
05F3: 19          add     hl,de       ; add to table to get pointer
05F4: 5E          ld      e,(hl)      ; load E with first byte from table
05F5: 23          inc     hl          ; next table entry
05F6: 56          ld      d,(hl)      ; load D with 2nd byte from table
05F7: EB          ex      de,hl       ; DE <> HL
05F8: 5E          ld      e,(hl)      ; load E with 1st byte from dereferenced table
05F9: 23          inc     hl          ; next table entry
05FA: 56          ld      d,(hl)      ; load D with 2ndy byte from derefernced table
05FB: 23          inc     hl          ; next table entry
05FC: 01 E0 FF    ld      bc,$ffe0    ; load BC with offset to print characters across
05FF: EB          ex      de,hl       ; DE <> HL.  HL now has screen destination, DE has table pointer

0600: 1A          ld      a,(de)      ; load A with table data
0601: FE 3F       cp      $3f         ; end code reached?
0603: CA 26 00    jp      z,$0026     ; yes, return to program.  This will effectively RET twice

0606: 77          ld      (hl),a      ; draw letter to screen
0607: F1          pop     af          ; restore AF from stack.  is there a carry?
0608: 30 02       jr      nc,$060c    ; no, skip next step

060A: 36 10       ld      (hl),$10    ; yes, write a blank space to the screen

060C: F5          push    af          ; save AF
060D: 13          inc     de          ; next table data
060E: 09          add     hl,bc       ; add screen offset for next column
060F: 18 EF       jr      $0600       ; loop again

;
; task #4
; jump from #0306
; draws credits on screen if any are present
;

0611: 3A 07 60    ld      a,(nocredits_6007) ; 1 when no credits have been inserted; 0 if any credits exist
0614: 0F          rrca                ; credits in game ?
0615: D0          ret     nc          ; yes, return

; called from #08F0

0616: 3E 05       ld      a,$05       ; load text code for "CREDIT"
0618: cd e9 05    call    $05e9       ; draw to screen
061B: 21 01 60    ld      hl,numcredits_6001; load HL with pointer to number of credits
061E: 11 E0 Ff    ld      de,$ffe0    ; load DE with #ffe0 = offset for columns?
0621: dd 21 Bf 74 ld      ix,$74bf    ; load IX with screen address to draw
0625: 06 01       ld      b,$01       ; B := 1
0627: c3 83 05    jp      $0583       ; jump back to draw number of credits on screen and return

;
; task #5
; called from #0306
; parameter 0 = adds bonus to player's score
; parameter 1 = update onscreen bonus timer and play sound & change to red if below 1000

062A: A7          and     a           ; parameter == 0 ?
062B: cA 91 06    jp      z,$0691     ; yes, skip ahead and add bonus to player's score

062E: 3A 8C 63    ld      a,(onscreen_timer_638c)   ; else load onscreen timer
0631: A7          and     a           ; timer == 0 ?
0632: c2 A8 06    jp      nz,$06a8    ; no, jump ahead

0635: 3A b8 63    ld      a,(mario_dead_flag_63b8)   ; else load A with timer expired indicator
0638: A7          and     a           ; has timer expired ?
0639: c0          ret     nz          ; yes, return

; the following code sets up the on screen timer initial value

063A: 3A b0 62    ld      a,(initial_clock_value_62b0)   ; load a with value from #62B0 (expects a decimal number here)
063D: 01 0A 00    ld      bc,$000a    ; B := 0, C := #0A (10 decimal)

0640: 04          inc     b           ; increment b
0641: 91          sub     c           ; subtract 10 decimal from A
0642: c2 40 06    jp      nz,$0640    ; loop again if not zero; counts how many tens there are

0645: 78          ld      a,b         ; load a with the number of tens in the counter
0646: 07          rlca                ; rotate left (x2)
0647: 07          rlca                ; rotate left (x4)
0648: 07          rlca                ; rotate left (x8)
0649: 07          rlca                ; rotate left (x16)
064A: 32 8C 63    ld      (onscreen_timer_638c),a   ; load on screen timer with result.  hex value converts to decimal.


064D: 21 4A 38    ld      hl,$384a    ; load HL with #384A - table data
0650: 11 65 74    ld      de,$7465    ; load DE with #7465 - screen location for bonus timer
0653: 3E 06       ld      a,$06       ; For A = 1 to 6

; draws timer box on screen with all zeros

0655: dd 21 1D 00 ld      ix,$001d    ; load IX with #001D offset used for each column
0659: 01 03 00    ld      bc,$0003    ; counter := 3
065C: ed b0       ldir                ; transfer (HL) to (DE) 3 times
065E: dd 19       add     ix,de       ; add offset DE to IX
0660: dd e5       push    ix
0662: d1          pop     de          ; load DE with IX
0663: 3D          dec     a           ; decrease counter
0664: c2 55 06    jp      nz,$0655    ; loop again if not zero

; check to see if timer is below 1000

0667: 3A 8C 63    ld      a,(onscreen_timer_638c)   ; load a with value from on screen timer

066A: 4f          ld      c,a         ; copy to C
066b: e6 0F       and     $0f         ; zeroes out left 4 bits
066D: 47          ld      b,a         ; store result in B
066E: 79          ld      a,c         ; restore a with original value from timer
066f: 0F          rrca                ; rotate right 4 times.  divides by 16
0670: 0F          rrca
0671: 0F          rrca
0672: 0F          rrca
0673: e6 0F       and     $0f         ; and with #0F - zero out left 4 bits
0675: c2 89 06    jp      nz,$0689    ; jump if not zero to #0689

; arrive here when timer runs below 1000

0678: 3E 03       ld      a,$03       ; else load A with warning sound
067A: 32 89 60    ld      (background_music_value_6089),a   ; set warning sound
067D: 3E 70       ld      a,$70       ; A := #70 = color code for red?
067f: 32 86 74    ld      ($7486),a   ; store A into #7486 = paint score red (MSB) ?
0682: 32 A6 74    ld      ($74a6),a   ; store A into #74A6 = paint score red (LSB) ?
0685: 80          add     a,b         ; A = A + B
0686: 47          ld      b,a         ; B := A
0687: 3E 10       ld      a,$10       ; A = #10 = code for blank space

0689: 32 E6 74    ld      ($74e6),a   ; draw timer to screen (MSB)
068C: 78          ld      a,b         ; A := B
068D: 32 C6 74    ld      ($74c6),a   ; draw timer to screen (LSB)
0690: c9          ret                 ; return

;
; continuation of task #5 when parameter = 0 from #062B
; adds bonus to player's score
;

0691: 3A 8C 63    ld      a,(onscreen_timer_638c)   ; load A with timer value from #638C
0694: 47          ld      b,a         ; copy to B
0695: e6 0F       and     $0f         ; and with #0F - mask four left bits.  how has low byte of bonus
0697: c5          push    bc          ; save BC
0698: cd 1C 05    call    $051c       ; add to score
069b: c1          pop     bc          ; restore BC
069C: 78          ld      a,b         ; load A with timer
069D: 0F          rrca                ; rotate right 4 times
069E: 0F          rrca
069f: 0F          rrca
06A0: 0F          rrca
06A1: e6 0F       and     $0f         ; mask four left bits to zero
06A3: c6 0A       add     a,$0a       ; add #0A (10 decimal) - this indicates scores of thousands to add
06A5: c3 1C 05    jp      $051c       ; jump to add score (thousands) and RET

; jump here from #0632

06A8: d6 01       sub     $01         ; subtract 1 from bonus timer
06Aa: 20 05       jr      nz,$06b1    ; If not zero, skip next 2 steps

; timer at zero

06Ac: 21 B8 63    ld      hl,mario_dead_flag_63b8    ; load HL with mario dead flag
06Af: 36 01       ld      (hl),$01    ; store 1 - mario will die soon on next timer click

06b1: 27          daa                 ; Decimal adjust
06b2: 32 8C 63    ld      (onscreen_timer_638c),a   ; store A into timer
06b5: c3 6A 06    jp      $066a       ; jump back

;
; task #6
; called from #01DC and #0306.  also jump here from #037C after high score has been exceeded
; parameter used to subtract the number of lives to draw
;

06B8: 4F          ld      c,a         ; load C with the task parameter
06B9: CF          rst     $8          ; is the game being played or credits exists?  If so, continue.  Else RET

06BA: 06 06       ld      b,$06       ; For B = 1 to 6
06BC: 11 E0 FF    ld      de,$ffe0    ; load DE with offset for next column
06BF: 21 83 77    ld      hl,$7783    ; load HL with screen location where mario extra lives drawn

06C2: 36 10       ld      (hl),$10    ; clear this area of screen
06C4: 19          add     hl,de       ; add offset for next column
06C5: 10 FB       djnz    $06c2       ; next B

06C7: 3A 28 62    ld      a,(number_of_lives_remaining_6228)   ; load A with number of lives remaining
06CA: 91          sub     c           ; subtract the task parameter.  zero lives to draw?
06CB: CA D7 06    jp      z,$06d7     ; yes, skip next 5 steps

06CE: 47          ld      b,a         ; For B = 1 to A
06CF: 21 83 77    ld      hl,$7783    ; load HL with screen location to draw remaining lives

06D2: 36 FF       ld      (hl),$ff    ; draw the extra mario
06D4: 19          add     hl,de       ; add offset for next column
06D5: 10 FB       djnz    $06d2       ; next B

06D7: 21 03 75    ld      hl,$7503    ; load HL with screen location for "L="
06DA: 36 1C       ld      (hl),$1c    ; draw "L"
06DC: 21 E3 74    ld      hl,$74e3    ; next location
06DF: 36 34       ld      (hl),$34    ; draw "="
06E1: 3A 29 62    ld      a,(level_number_6229)   ; load A with level #
06E4: fe 64       cp      $64         ; level < #64 (100 decimal) ?
06E6: 38 05       jr      c,$06ed     ; yes, skip next 2 steps

06E8: 3E 63       ld      a,$63       ; otherwise A := #63 (99 decimal)
06Ea: 32 29 62    ld      (level_number_6229),a   ; store into level #

06Ed: 01 0A ff    ld      bc,$ff0a    ; B: = #FF, C := #0A (10 decimal)

06f0: 04          inc     b           ; increment B
06f1: 91          sub     c           ; subtract 10 decimal
06f2: d2 f0 06    jp      nc,$06f0    ; not carry, loop again (counts tens)

06f5: 81          add     a,c         ; add 10 back to A to get a number from 0 to 9
06f6: 32 A3 74    ld      ($74a3),a   ; draw level to screen (low byte)
06f9: 78          ld      a,b         ; load a with b (number of tens)
06fa: 32 C3 74    ld      ($74c3),a   ; draw level to screen (high byte)
06fd: c9          ret                 ; return

; start of main routine when playing a game
; arrive here from #00C9

06FE: 3A 0A 60    ld      a,(gamemode2_600a) ; load A with game mode2
0701: EF          rst     $28         ; jump based on what the game state is

0702  86 09                             ; (0) #0986     ; game start = clears screen, clears sounds, sets screen flip if needed
0704  AB 09                             ; (1) #09AB     ; copy player data, set screen, set next game mode based on number of players
0706  D6 09                             ; (2) #09D6     ; clears palettes, draws "PLAYER <I>", draws player2 score, draws "2UP" (2 player game only)
0708  FE 09                             ; (3) #09FE     ; copy player data into correct area (2 player game only)
070A  1B 0A                             ; (4) #0A1B     ; clears palletes, draws "PLAYER <II>", update player2 score, draw "2UP" to screen (2 player game only)
070C  37 0A                             ; (5) #0A37     ; updates high score, player score, remaining lives, level, 1UP
070E  63 0A                             ; (6) #0A63     ; clears screen and sprites, check for intro screen to run
0710  76 0A                             ; (7) #0A76     ; kong clims ladders and scary music played
0712  DA 0B                             ; (8) #0BDA     ; draw goofy kongs, how high can you get, play music
0714  00 00                             ; (9)           ; unused
0716  91 0C                             ; (A) #0C91     ; clears screen, update timers, draws current screen, sets background music
0718  3C 12                             ; (B) #123C     ; set initial mario sprite position and draw remaining lives and level
071A  7A 19                             ; (C) #197A     ; for when playing a game.  this is the main routine
071C  7C 12                             ; (D) #127C     ; mario died.  handle mario dying animations
071E  F2 12                             ; (E) #12F2     ; clear sounds, decrease life, check for and handle game over
0720  44 13                             ; (F) #1344     ; clear sounds, clear game start flag, draw game over if needed PL2, set game mode2 accordingly
0722  8F 13                             ; (10) #138F    ; check for game over status on a 2 player game
0724  A1 13                             ; (11) #13A1    ; check for game over status on a 2 player game
0726  AA 13                             ; (12) #13AA    ; flip screen if needed, reset game mode2 to zero, set player 2
0728  BB 13                             ; (13) #13BB    ; set player 1, reset game mode2 to zero, set screen flip to not flipped
072A  1E 14                             ; (14) #141E    ; draw credits on screen, clears screen and sprites, checks for high score, flips screen if necessary
072C  86 14                             ; (15) #1486    ; player enters initials in high score table
072E  15 16                             ; (16) #1615    ; handle end of level animations
0730  6B 19                             ; (17) #196B    ; clear screen and all sprites, set game mode2 to #12 for player1 or #13 for player2
0732  00 00 00 00 00 00 00 00 00 00                     ; unused

; arrive from #00C9 when attract mode starts

073C: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode2 address
073F: 3A 01 60    ld      a,(numcredits_6001) ; load A with number of credits
0742: A7          and     a           ; any credits exist ?
0743: C2 5C 07    jp      nz,$075c    ; yes, skip ahead, zero out game mode2, increase game mode1, and RET

0746: 7E          ld      a,(hl)      ; else load A with game mode2
0747: EF          rst     $28         ; jump based on A

0748  79 07                     0       ; #0779         ; clear screen, set color palettes, draw attract mode text and high score table,
                                                        ; [continued] increase game mode2, clear sprites, ; draw "1UP" on screen , draws number of coins needed for play
074A  63 07                     1       ; #0763         ;
074C  3C 12                     2       ; #123C         ; set initial mario sprite position and draw remaining lives and level
074E  77 19                     3       ; #1977         ; set artificial input for demo play [change to #197A to enable playing in demo part 1/2]
0750  7C 12                     4       ; #127C         ; handle mario dying animations
0752  C3 07                     5       ; #07C3         ; clears the screen and sprites and increase game mode2
0754  CB 07                     6       ; #07CB         ; handle intro splash screen ?
0756  4B 08                     7       ; #084B         ; counts down a timer then resets game mode2 to 0

0758  00 00 00 00                       ; unused

; arrive from #0743 when credits exist

075C: 36 00       ld      (hl),$00    ; set game mode2 to zero
075E: 21 05 60    ld      hl,gamemode1_6005; load HL with game mode1
0761: 34          inc     (hl)        ; increase
0762: C9          ret                 ; return

; arrive here from #0747 during attract mode when GameMode2 == 1

0763: E7          rst     $20         ; only continue here once per frame, else RET

0764: AF          xor     a           ; A := 0
0765: 32 92 63    ld      (barrel_deployment_indicator_6392),a   ; clear barrel deployment indicator
0768: 32 A0 63    ld      (unknown_63a0),a   ; clear fireball release indicator
076B: 3E 01       ld      a,$01       ; A := 1
076D: 32 27 62    ld      (screen_number_6227),a   ; load screen number with 1
0770: 32 29 62    ld      (level_number_6229),a   ; load level # with 1
0773: 32 28 62    ld      (number_of_lives_remaining_6228),a   ; load number of lives with 1
0776: C3 92 0C    jp      $0c92       ; skip ahead

; arrive from #0747 when GameMode2 == 0
; clear screen, set color palettes, draw attract mode text and high score table, increase game mode2, clear sprites, ; draw "1UP" on screen , draws number of coins needed for play

0779: 21 86 7D    ld      hl,reg_palette_a
077C: 36 00       ld      (hl),$00    ; clear palette bank selector
077E: 23          inc     hl
077F: 36 00       ld      (hl),$00    ; clear palette bank selector
0781: 11 1B 03    ld      de,$031b    ; load task data for text "INSERT COIN"
0784: CD 9F 30    call    $309f       ; insert task to draw text
0787: 1C          inc     e           ; load task data for text "PLAYER    COIN"
0788: CD 9F 30    call    $309f       ; insert task to draw text
078B: CD 65 09    call    $0965       ; draws credits on screen if any are present and displays high score table
078E: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer address
0791: 36 02       ld      (hl),$02    ; set timer at 2
0793: 23          inc     hl          ; load HL with game mode2
0794: 34          inc     (hl)        ; increase
0795: CD 74 08    call    $0874       ; clears the screen and sprites
0798: CD 53 0A    call    $0a53       ; draw "1UP" on screen
079B: 3A 0F 60    ld      a,(twoplayergame_600f) ; load A with number of players in game
079E: FE 01       cp      $01         ; 2 player game?
07A0: CC EE 09    call    z,$09ee     ; yes, skip ahead to handle

07A3: ED 5B 22 60 ld      de,(coinspercredit_6022) ; D := CoinsPer2Credits; E := CoinsPerCredit
07A7: 21 6C 75    ld      hl,$756c    ; load HL with screen RAM location
07AA: CD AD 07    call    $07ad       ; run this sub below twice

07AD: 73          ld      (hl),e      ; draw to screen number of coins needed for 1 player game
07AE: 23          inc     hl
07AF: 23          inc     hl          ; next screen location 2 rows down
07B0: 72          ld      (hl),d      ; draw to screen number of coins neeeded for 2 player game
07B1: 7A          ld      a,d         ; A := D
07B2: D6 0A       sub     $0a         ; subtract #A (10 decimal). result == 0 ?
07B4: C2 BC 07    jp      nz,$07bc    ; no, skip next 3 steps

07B7: 77          ld      (hl),a      ; else draw this zero to screen
07B8: 3C          inc     a           ; increase A, A := 1 now
07B9: 32 8E 75    ld      ($758e),a   ; draw 1 to screen in front of the zero, so it draws "10" credits needed for 2 players

07BC: 11 01 02    ld      de,$0201    ; D := 2, E := 1, used for next loop for 1 player and 2 players
07BF: 21 8C 76    ld      hl,$768c    ; set screen location to draw for next loop if needed
07C2: C9          ret                 ; return

; arrive from #0747 when GameMode2 == 5

07C3: CD 74 08    call    $0874       ; clears the screen and sprites
07C6: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode 2
07C9: 34          inc     (hl)        ; increase game mode2
07CA: C9          ret                 ; return

; arrive from jump at #0747 when GameMode2 == 6

07CB: 3A 8A 63    ld      a,(kong_intro_flash_counter_638a)   ; load A with kong screen flash counter
07CE: FE 00       cp      $00         ; == 0 ?  time to flash?
07D0: C2 2D 08    jp      nz,$082d    ; no, skip ahead : load C with (#638B), decreases #638A, loads A with (#638A) ; loads C with #638B, decreases #638A returns to #07DA

07D3: 3E 60       ld      a,$60       ; else A := #60
07D5: 32 8A 63    ld      (kong_intro_flash_counter_638a),a   ; store into kong screen flash counter
07D8: 0E 5F       ld      c,$5f       ; C := #5F

; can arrive here from jump at #0838

07DA: FE 00       cp      $00         ; A == 0 ? [why not AND A ?]
07DC: CA 3B 08    jp      z,$083b     ; yes, skip ahead

07DF: 21 86 7D    ld      hl,reg_palette_a; load pallete bank
07E2: 36 00       ld      (hl),$00    ; clear palette bank selector
07E4: 79          ld      a,c         ; A := C
07E5: CB 07       rlc     a           ; rotate left.  carry bit set?
07E7: 30 02       jr      nc,$07eb    ; no, skip next step

07E9: 36 01       ld      (hl),$01    ; set pallete bank selector to 1

07EB: 23          inc     hl          ; HL := REG_PALETTE_B = 2nd pallete bank
07EC: 36 00       ld      (hl),$00    ; clear the pallete bank selector
07EE: CB 07       rlc     a           ; rotate left again.  carry bit set ?
07F0: 30 02       jr      nc,$07f4    ; no, skip next step

07F2: 36 01       ld      (hl),$01    ; set pallete bank selector to 1

07F4: 32 8B 63    ld      (unknown_638b),a   ; store A into ???

; draws DONKEY KONG logo to screen

07F7: 21 08 3D    ld      hl,$3d08    ; load HL with start of table data

07FA: 3E B0       ld      a,$b0       ; A := #B0 = code for girder on screen
07FC: 46          ld      b,(hl)      ; get first data.  this is used as a loop counter
07FD: 23          inc     hl          ; next table entry
07FE: 5E          ld      e,(hl)      ; load E with table data
07FF: 23          inc     hl          ; next entry
0800: 56          ld      d,(hl)      ; load D with table data.  DE now has an address

0801: 12          ld      (de),a      ; draw girder on screen
0802: 13          inc     de          ; next address
0803: 10 FC       djnz    $0801       ; Next B

0805: 23          inc     hl          ; next table entry
0806: 7E          ld      a,(hl)      ; get data
0807: FE 00       cp      $00         ; done ?
0809: C2 FA 07    jp      nz,$07fa    ; no, loop again

080C: 11 1E 03    ld      de,$031e    ; load task data for text "(C) 1981"
080F: CD 9F 30    call    $309f       ; insert task to draw text
0812: 13          inc     de          ; load task data for text "NINTENDO OF AMERICA"
0813: CD 9F 30    call    $309f       ; insert task to draw text
0816: 21 CF 39    ld      hl,$39cf    ; load HL with table data for kong beating chest
0819: CD 4E 00    call    $004e       ; update kong's sprites
081C: CD 24 3F    call    $3f24       ; draw TM logo onscreen [patch? orig japanese had 3 NOPs here]
081F: 00          nop                 ; no operation
0820: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of kong sprite X pos
0823: 0E 44       ld      c,$44       ; load C with offset to add X
0825: FF          rst     $38         ; draw kong in new position
0826: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of kong sprite Y pos
0829: 0E 78       ld      c,$78       ; load C with offset to add Y
082B: FF          rst     $38         ; draw kong
082C: C9          ret                 ; return

; jump here from #07D0
; loads C with #638B, decreases #638A

082D: 3A 8B 63    ld      a,(unknown_638b)   ; load A with ???
0830: 4F          ld      c,a         ; copy to C
0831: 3A 8A 63    ld      a,(kong_intro_flash_counter_638a)   ; load A with kong intro flash counter
0834: 3D          dec     a           ; decrease
0835: 32 8A 63    ld      (kong_intro_flash_counter_638a),a   ; store result
0838: C3 DA 07    jp      $07da       ; jump back

; jump here from #07DC

083B: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer address
083E: 36 02       ld      (hl),$02    ; set timer to 2
0840: 23          inc     hl          ; HL := GameMode2
0841: 34          inc     (hl)        ; increase game mode2
0842: 21 8A 63    ld      hl,kong_intro_flash_counter_638a    ; load HL with kong intro flash counter
0845: 36 00       ld      (hl),$00    ; clear counter
0847: 23          inc     hl          ; HL := #638B = ???
0848: 36 00       ld      (hl),$00    ; clear this memory
084A: C9          ret                 ; return

; arrive from #0747 when GameMode2 == 7

084B: E7          rst     $20         ; update timer and continue here only when complete, else RET

084C: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode2
084F: 36 00       ld      (hl),$00    ; set to 0
0851: C9          ret                 ; return

; called from #0986
; clears screen and all sprites

0852: 21 00 74    ld      hl,$7400    ; #7400 is beginning of video RAM
0855: 0E 04       ld      c,$04       ; for C= 1 to 4
0857: 06 00       ld      b,$00       ; for B = 1 to 256
0859: 3E 10       ld      a,$10       ; #10 is clear for screen in video RAM

085B: 77          ld      (hl),a      ; clear this screen element
085C: 23          inc     hl          ; next screen location
085D: 10 FC       djnz    $085b       ; Next B

085F: 0D          dec     c           ; Next C
0860: C2 57 08    jp      nz,$0857    ; loop until done

0863: 21 00 69    ld      hl,girls_head_sprite_6900    ; load HL with start of sprite RAM
0866: 0E 02       ld      c,$02       ; for C = 1 to 2
0868: 06 C0       ld      b,$c0       ; for B = 1 to #C0
086A: AF          xor     a           ; A := 0

086B: 77          ld      (hl),a      ; clear RAM
086C: 23          inc     hl          ; next memory
086D: 10 FC       djnz    $086b       ; next B

086F: 0D          dec     c           ; next C
0870: C2 68 08    jp      nz,$0868    ; loop until done

0873: C9          ret                 ; return

; called from many places.  EG #08BA and #01C3 and #0C92 and other places
; clears the screen and sprites

0874: 21 04 74    ld      hl,$7404    ; load HL with start of video RAM
0877: 0E 20       ld      c,$20       ; For C = 1 to #20

0879: 06 1C       ld      b,$1c       ; for B = 1 to #1C
087B: 3E 10       ld      a,$10       ; A := #10
087D: 11 04 00    ld      de,$0004    ; DE = 4, used as offset to add later

0880: 77          ld      (hl),a      ; store into memory
0881: 23          inc     hl          ; next memory
0882: 10 FC       djnz    $0880       ; Next B

0884: 19          add     hl,de       ; add offset of 4
0885: 0D          dec     c           ; decrease counter
0886: C2 79 08    jp      nz,$0879    ; loop until zero

0889: 21 22 75    ld      hl,$7522    ; load HL with screen location
088C: 11 20 00    ld      de,$0020    ; load DE with offset to use
088F: 0E 02       ld      c,$02       ; for C = 1 to 2
0891: 3E 10       ld      a,$10       ; A := #10 = clear screen byte

0893: 06 0E       ld      b,$0e       ; for B = 1 to #0E
0895: 77          ld      (hl),a      ; clear the screen element
0896: 19          add     hl,de       ; add offset for next
0897: 10 FC       djnz    $0895       ; Next B

0899: 21 23 75    ld      hl,$7523    ; load HL with next screen location
089C: 0D          dec     c           ; done ?
089D: C2 93 08    jp      nz,$0893    ; no, loop again

08A0: 21 00 69    ld      hl,girls_head_sprite_6900    ; load HL with start of sprite RAM
08A3: 06 00       ld      b,$00       ; For B = 0 to #FF
08A5: 3E 00       ld      a,$00       ; A := 0

08A7: 77          ld      (hl),a      ; clear memory
08A8: 23          inc     hl          ; next memory
08A9: 10 FC       djnz    $08a7       ; Next B

08AB: 06 80       ld      b,$80       ; For B = 0 to #80
08AD: 77          ld      (hl),a      ; store memory
08AE: 23          inc     hl          ; next memory
08AF: 10 FC       djnz    $08ad       ; Next B

08B1: C9          ret                 ; Return

; jump from #00C9
; arrive here when credits have been inserted, waiting for game to start

08B2: 3A 0A 60    ld      a,(gamemode2_600a) ; load A with game mode2

; GameMode2 = 1 during attract mode, 7 during intro , A during how high can u get,
;         B right before play, C during play, D when dead, 10 when game over

08B5: EF          rst     $28         ; jump based on A

08B6  BA 08                             ; #08BA         ; display screen to press start etc.
08B8  F8 08                             ; #08F8         ; wait for start buttons to be pressed

08BA: CD 74 08    call    $0874       ; clear the screen and sprites
08BD: AF          xor     a           ; A := 0
08BE: 32 07 60    ld      (nocredits_6007),a; store into credit indicator
08C1: 11 0C 03    ld      de,$030c    ; load DE with task code to display "PUSH" onscreen
08C4: CD 9F 30    call    $309f       ; insert task
08C7: 21 0A 60    ld      hl,gamemode2_600a; load A with game mode2
08CA: 34          inc     (hl)        ; increase game mode2
08CB: CD 65 09    call    $0965       ; draw credits on screen if any are present and displays high score table
08CE: AF          xor     a           ; A := 0
08CF: 21 86 7D    ld      hl,reg_palette_a; load HL with pallete bank
08D2: 77          ld      (hl),a      ; clear palette bank selector
08D3: 2C          inc     l           ; next pallete bank
08D4: 77          ld      (hl),a      ; clear palette bank selector

; called from #08F8

08D5: 06 04       ld      b,$04       ; B := 4 = 0100 binary
08D7: 1E 09       ld      e,$09       ; E := 9 , code for "ONLY 1 PLAYER BUTTON"
08D9: 3A 01 60    ld      a,(numcredits_6001) ; load A with number of credits
08DC: FE 01       cp      $01         ; == 1 ?
08DE: CA E4 08    jp      z,$08e4     ; yes, skip next 2 steps

08E1: 06 0C       ld      b,$0c       ; B := #0C = 1100 binary
08E3: 1C          inc     e           ; E := #0A, code for "1 OR 2 PLAYERS BUTTON"

08E4: 3A 1A 60    ld      a,(framecounter_601a) ; load A with # Timer constantly counts down from FF to 00
08E7: E6 07       and     $07         ; mask bits. zero ?
08E9: C2 F3 08    jp      nz,$08f3    ; no, skip next 3 steps

08EC: 7B          ld      a,e         ; yes, load A with E for code of text to draw, for buttons to press to start
08ED: CD E9 05    call    $05e9       ; draw text to screen
08F0: CD 16 06    call    $0616       ; draw credits on screen

08F3: 3A 00 7D    ld      a,(in2)     ; load A with IN2 [Credit/Service/Start Info]
08F6: A0          and     b           ; mask bits with B
08F7: C9          ret                 ; return

; jump from #08B5 when GameMode2 == 1

08F8: CD D5 08    call    $08d5       ; draws press player buttons and loads A with IN2, masked by possible player numbers
08FB: FE 04       cp      $04         ; is the player 1 button pressed ?
08FD: CA 06 09    jp      z,$0906     ; yes, skip ahead

0900: FE 08       cp      $08         ; is the player 2 button pressed ?
0902: CA 19 09    jp      z,$0919     ; yes, skip ahead

0905: C9          ret                 ; return to #00D2

; player 1 start

0906: CD 77 09    call    $0977       ; subtract 1 credit and update screen credit counter
0909: 21 48 60    ld      hl,p2numlives_6048; load HL with RAM used for player 2
090C: 06 08       ld      b,$08       ; for B = 1 to 8
090E: AF          xor     a           ; A := 0

090F: 77          ld      (hl),a      ; clear memory
0910: 2C          inc     l           ; next memory
0911: 10 FC       djnz    $090f       ; Next B

0913: 21 00 00    ld      hl,$0000    ; clear HL
0916: C3 38 09    jp      $0938       ; skip ahead

; 2 players start

0919: CD 77 09    call    $0977       ; subtract 1 credit and update screen credit counter
091C: CD 77 09    call    $0977       ; subtract 1 credit and update screen credit counter
091F: 11 48 60    ld      de,p2numlives_6048; load DE with RAM location used for player 2
0922: 3A 20 60    ld      a,(startinglives_6020) ; load initial number of lives
0925: 12          ld      (de),a      ; store into number of lives player 2
0926: 1C          inc     e           ; DE := Unk6049
0927: 21 5E 09    ld      hl,$095e    ; load HL with source data table start
092A: 01 07 00    ld      bc,$0007    ; counter = 7
092D: ED B0       ldir                ; copy #095E into Unk6049 for 7 bytes
092F: 11 01 01    ld      de,$0101    ; load task #1, parameter 1.  clears player 1 and 2 scores and displays them.
0932: CD 9F 30    call    $309f       ; insert task
0935: 21 00 01    ld      hl,$0100    ; HL := #100

0938: 22 0E 60    ld      (playerturnb_600e),hl; store HL into PlayerTurnB and TwoPlayerGame.  TwoPlayerGame is the number of players in the game
093B: CD 74 08    call    $0874       ; clear the screen and sprites
093E: 11 40 60    ld      de,p1numlives_6040; load DE with address for number of lives player 1
0941: 3A 20 60    ld      a,(startinglives_6020) ; number of initial lives set with dip switches (3, 4, 5, or 6)
0944: 12          ld      (de),a      ; store into number of lives
0945: 1C          inc     e           ; DE := Unk6041
0946: 21 5E 09    ld      hl,$095e    ; load HL with start of table data
0949: 01 07 00    ld      bc,$0007    ; counter = 7
094C: ED B0       ldir                ; copy #095E into Unk6041 for 7 bytes
094E: 11 00 01    ld      de,$0100    ; load task #1, parameter 0.  clears player 1 score and displays it
0951: CD 9F 30    call    $309f       ; insert task
0954: AF          xor     a           ; A := 0
0955: 32 0A 60    ld      (gamemode2_600a),a; reset game mode2
0958: 3E 03       ld      a,$03       ; A := 3
095A: 32 05 60    ld      (gamemode1_6005),a; store into game mode1
095D: C9          ret                 ; return

; table data use in code above - gets copied to Unk6041 to Unk6041+7

095E  01 65 3A 01 00 00 00              ; #3A65 is start of table data for screens/levels

; called from #08CB

0965: 11 00 04    ld      de,$0400    ; set task #4 = draws credits on screen if any are present
0968: CD 9F 30    call    $309f       ; insert task
096B: 11 14 03    ld      de,$0314    ; set task #3, parameter 14 through 1A.  For display of high score table
096E: 06 06       ld      b,$06       ; for B = 1 to 6

0970: CD 9F 30    call    $309f       ; insert task
0973: 1C          inc     e           ; increase task parameter
0974: 10 FA       djnz    $0970       ; Next B

0976: C9          ret                 ; return

; subtract 1 credit and update screen credit counter

0977: 21 01 60    ld      hl,numcredits_6001; load HL with pointer to number of credits
097A: 3E 99       ld      a,$99       ; A := #99
097C: 86          add     a,(hl)      ; add to number of credits.   equivalent of subtracting 1
097D: 27          daa                 ; decimal adjust
097E: 77          ld      (hl),a      ; store into number of credits
097F: 11 00 04    ld      de,$0400    ; set task #4 = draws credits on screen if any are present
0982: CD 9F 30    call    $309f       ; insert task
0985: C9          ret                 ; return

; arrive here when a game begins
; clears screen, clears sounds, sets screen flip if needed
; jump from #0701 when GameMode2 == 0

0986: CD 52 08    call    $0852       ; clear screen and all sprites
0989: CD 1C 01    call    $011c       ; clear all sounds
098C: 11 82 7D    ld      de,reg_flipscreen; load DE with flip screen setting
098F: 3E 01       ld      a,$01       ; A := 1
0991: 12          ld      (de),a      ; store
0992: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode 2 address
0995: 3A 0E 60    ld      a,(playerturnb_600e) ; load A with 0 when player 1 is up, = 1 when player 2 is up
0998: A7          and     a           ; is player 1 up?
0999: C2 9F 09    jp      nz,$099f    ; no, skip next 2 steps

099C: 36 01       ld      (hl),$01    ; set game mode 2 to 1
099E: C9          ret                 ; return

099F: 3A 26 60    ld      a,(uprightcab_6026) ; load A with upright/cocktail
09A2: 3D          dec     a           ; is this cocktail mode ?
09A3: CA A8 09    jp      z,$09a8     ; no, skip next 2 steps

09A6: AF          xor     a           ; A := 0
09A7: 12          ld      (de),a      ; set screen to flipped

09A8: 36 03       ld      (hl),$03    ; set game mode 2 to 3
09AA: C9          ret                 ; return

; jump from #0701 when GameMode2 == 1
; copy player data, set screen, set next game mode based on number of players

09AB: 21 40 60    ld      hl,p1numlives_6040; load HL with source data location
09AE: 11 28 62    ld      de,number_of_lives_remaining_6228    ; load DE with destination data location.  start with remaining lives
09B1: 01 08 00    ld      bc,$0008    ; byte counter set to 8
09B4: ED B0       ldir                ; copy (HL) into (DE) from P1NumLives to P2NumLives into #6228 to #622F
09B6: 2A 2A 62    ld      hl,(store_622a)  ; EG #3A65.  start of table data for screens/levels
09B9: 7E          ld      a,(hl)      ; load screen number from table
09BA: 32 27 62    ld      (screen_number_6227),a   ; store screen number
09BD: 3A 0F 60    ld      a,(twoplayergame_600f) ; load A with number of players
09C0: A7          and     a           ; 1 player game?
09C1: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer address
09C4: 11 0A 60    ld      de,gamemode2_600a; load DE with game mode2 address
09C7: CA D0 09    jp      z,$09d0     ; if 1 player game, skip ahead

; 2 player game

09CA: 36 78       ld      (hl),$78    ; store #78 into timer
09CC: EB          ex      de,hl       ; DE <> HL.  HL now has game mode2
09CD: 36 02       ld      (hl),$02    ; GameMode2 := 2
09CF: C9          ret                 ; return

; 1 player game

09D0: 36 01       ld      (hl),$01    ; store 1 into timer
09D2: EB          ex      de,hl       ; DE <> HL.  HL now has game mode2
09D3: 36 05       ld      (hl),$05    ; GameMode2 := 5
09D5: C9          ret                 ; return


; used to draw players during 2 player game
; jump here from #0701
; clears palettes, draws "PLAYER <I>", draws player2 score, draws "2UP"

09D6: AF          xor     a           ; A := 0
09D7: 32 86 7D    ld      (reg_palette_a),a; clear palette bank selector
09DA: 32 87 7D    ld      (reg_palette_b),a; clear palette bank selector
09DD: 11 02 03    ld      de,$0302    ; load task data for text #2 "PLAYER <I>"
09E0: CD 9F 30    call    $309f       ; insert task to draw
09E3: 11 01 02    ld      de,$0201    ; load task #2, parameter 1 to display player 2 score
09E6: CD 9F 30    call    $309f       ; insert task
09E9: 3E 05       ld      a,$05       ; A := 5
09EB: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2

09EE: 3E 02       ld      a,$02       ; load A with "2"
09F0: 32 E0 74    ld      ($74e0),a   ; write to screen
09F3: 3E 25       ld      a,$25       ; load A with "U"
09F5: 32 C0 74    ld      ($74c0),a   ; write to screen
09F8: 3E 20       ld      a,$20       ; load A with "P"
09FA: 32 A0 74    ld      ($74a0),a   ; write to screen
09FD: C9          ret                 ; return

; arrive from #0701 when GameMode2 == 3

09FE: 21 48 60    ld      hl,p2numlives_6048; source location is ???
0A01: 11 28 62    ld      de,number_of_lives_remaining_6228    ; destination is player lives remaining plus other player variables
0A04: 01 08 00    ld      bc,$0008    ; byte counter set to 8
0A07: ED B0       ldir                ; copy
0A09: 2A 2A 62    ld      hl,(store_622a)  ; load HL with table for screens/levels
0A0C: 7E          ld      a,(hl)      ; load A with screen number from table
0A0D: 32 27 62    ld      (screen_number_6227),a   ; store A into screen number
0A10: 3E 78       ld      a,$78       ; A := #78
0A12: 32 09 60    ld      (waittimermsb_6009),a; store into timer
0A15: 3E 04       ld      a,$04       ; A := 4
0A17: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2
0A1A: C9          ret                 ; return

; arrive from #0701 when GameMode2 == 4
; clears palletes, draws "PLAYER <II>", update player2 score, draw "2UP" to screen

0A1B: AF          xor     a           ; A := 0
0A1C: 32 86 7D    ld      (reg_palette_a),a; clear palette bank selector
0A1F: 32 87 7D    ld      (reg_palette_b),a; clear palette bank selector
0A22: 11 03 03    ld      de,$0303    ; load task data for text #3 "PLAYER <II>"
0A25: CD 9F 30    call    $309f       ; insert task to draw text
0A28: 11 01 02    ld      de,$0201    ; load task #2, parameter 1 to display player 2 score
0A2B: CD 9F 30    call    $309f       ; insert task
0A2E: CD EE 09    call    $09ee       ; draw "2UP" to screen
0A31: 3E 05       ld      a,$05       ; A := 5
0A33: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2
0A36: C9          ret                 ; return

; arrive from #0701 when GameMode2 == 5
; updates high score, player score, remaining lives, level, 1UP

0A37: 11 04 03    ld      de,$0304    ; load task data for text #4 "HIGH SCORE"
0A3A: CD 9F 30    call    $309f       ; insert task to draw text
0A3D: 11 02 02    ld      de,$0202    ; load task #2, parameter 2 to display high score
0A40: CD 9F 30    call    $309f       ; insert task
0A43: 11 00 02    ld      de,$0200    ; load task #2, parameter 0 to display player 1 score
0A46: CD 9F 30    call    $309f       ; insert task
0A49: 11 00 06    ld      de,$0600    ; load task #6 parameter 0 to display lives remaining and level
0A4C: CD 9F 30    call    $309f       ; insert task
0A4F: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode2 address
0A52: 34          inc     (hl)        ; increase game mode

;  called from #01F1 , #0798, and other places
; draw "1UP" on screen

0A53: 3E 01       ld      a,$01       ; load A with "1"
0A55: 32 40 77    ld      ($7740),a   ; write to screen
0A58: 3E 25       ld      a,$25       ; load A with "U"
0A5A: 32 20 77    ld      ($7720),a   ; write to screen
0A5D: 3E 20       ld      a,$20       ; load A with "P"
0A5F: 32 00 77    ld      ($7700),a   ; write to screen
0A62: C9          ret                 ; return

; arrive from #0701 when GameMode2 == 6
; clears screen and sprites, check for intro screen to run

0A63: DF          rst     $18         ; count down WaitTimerMSB and only continue here if == 0, else return to higher sub.
0A64: CD 74 08    call    $0874       ; clears the screen and sprites
0A67: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer
0A6A: 36 01       ld      (hl),$01    ; set timer to 1
0A6C: 2C          inc     l           ; HL := GameMode2
0A6D: 34          inc     (hl)        ; increase game mode2 to 7
0A6E: 11 2C 62    ld      de,game_start_flag_622c    ; load DE with game start flag address
0A71: 1A          ld      a,(de)      ; load A with game start flag
0A72: A7          and     a           ; is this game just beginning?
0A73: C0          ret     nz          ; yes, return

0A74: 34          inc     (hl)        ; else increase game mode2 to 8 - skip kong intro to begin
0A75: C9          ret                 ; return

; arrive from #0701 when GameMode2 == 7

0A76: 3A 85 63    ld      a,(intro_screen_counter_6385)   ; varies from 0 to 7 while the intro screen runs, when kong climbs the dual ladders and scary music is played
0A79: EF          rst     $28         ; jump based on A

0A7A  8A 0A                     0       ; #0A8A
0A7C  BF 0A                     1       ; #0ABF
0A7E  E8 0A                     2       ; #0AE8
0A80  69 30                     3       ; #3069
0A82  06 0B                     4       ; #0B06
0A84  69 30                     5       ; #3069
0A86  68 0B                     6       ; #0B68
0A88  B3 0B                     7       ; #0BB3

; arrive from #0A79 when intro screen indicator == 0

0A8A: AF          xor     a           ; A := 0
0A8B: 32 86 7D    ld      (reg_palette_a),a; clear palette bank selector
0A8E: 3C          inc     a           ; A := 1
0A8F: 32 87 7D    ld      (reg_palette_b),a; store into palette bank selector
0A92: 11 0D 38    ld      de,$380d    ; load DE with start of table data
0A95: CD A7 0D    call    $0da7       ; draw the screen
0A98: 3E 10       ld      a,$10       ; A := #10
0A9A: 32 A3 76    ld      ($76a3),a   ; erase a graphic near top of screen
0A9D: 32 63 76    ld      ($7663),a   ; erase a graphic near top of screen
0AA0: 3E D4       ld      a,$d4       ; A := #D4
0AA2: 32 AA 75    ld      ($75aa),a   ; draw a ladder at top of screen
0AA5: AF          xor     a           ; A := 0
0AA6: 32 AF 62    ld      (kong_misc_counter_62af),a   ; store into kong climbing counter
0AA9: 21 B4 38    ld      hl,$38b4    ; load HL with start of table data
0AAC: 22 C2 63    ld      (store_63c2),hl  ; store
0AAF: 21 CB 38    ld      hl,$38cb    ; load HL with start of table data
0AB2: 22 C4 63    ld      (unknown_63c4),hl  ; store
0AB5: 3E 40       ld      a,$40       ; A := #40
0AB7: 32 09 60    ld      (waittimermsb_6009),a; set timer to #40
0ABA: 21 85 63    ld      hl,intro_screen_counter_6385    ; load HL with intro screen counter
0ABD: 34          inc     (hl)        ; increase
0ABE: C9          ret                 ; return

; arrive from #0A79 when intro screen indicator == 1

0ABF: DF          rst     $18         ; count down timer and only continue here if zero, else RET
0AC0: 21 8C 38    ld      hl,$388c    ; load HL with start of table data for kong
0AC3: CD 4E 00    call    $004e       ; update kong's sprites
0AC6: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of Kong sprite
0AC9: 0E 30       ld      c,$30       ; load offset to add
0ACB: FF          rst     $38         ; move kong
0ACC: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite
0ACF: 0E 99       ld      c,$99       ; load offset to add
0AD1: FF          rst     $38         ; move kong
0AD2: 3E 1F       ld      a,$1f       ; A := #1F
0AD4: 32 8E 63    ld      (kong_ladder_climb_counter_638e),a   ; store into kong ladder climb counter
0AD7: AF          xor     a           ; A := 0
0AD8: 32 0C 69    ld      (clear_kongs_top_right_sprite_690c),a   ; store into kong's right arm sprite
0ADB: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load HL with music buffer
0ADE: 36 01       ld      (hl),$01    ; play scary music for start of game sound
0AE0: 23          inc     hl          ; load HL with duration
0AE1: 36 03       ld      (hl),$03    ; set duration to 3
0AE3: 21 85 63    ld      hl,intro_screen_counter_6385    ; load HL with intro screen counter
0AE6: 34          inc     (hl)        ; increase
0AE7: C9          ret                 ; return

; arrive from #0A79 when intro screen indicator == 2

0AE8: CD 6F 30    call    $306f       ; animate kong climbing up the ladder with girl under arm
0AEB: 3A AF 62    ld      a,(kong_misc_counter_62af)   ; load A with kong climbing counter
0AEE: E6 0F       and     $0f         ; mask bits, now between 0 and #F.  zero?
0AF0: CC 4A 30    call    z,$304a     ; yes, roll up kong's ladder behind him

0AF3: 3A 0B 69    ld      a,(kong_sprite_array_690b)   ; load HL with start of Kong sprite
0AF6: FE 5D       cp      $5d         ; < #5D ?
0AF8: D0          ret     nc          ; no, return

0AF9: 3E 20       ld      a,$20       ; A := #20
0AFB: 32 09 60    ld      (waittimermsb_6009),a; set timer to #20
0AFE: 21 85 63    ld      hl,intro_screen_counter_6385    ; load HL with intro screen counter
0B01: 34          inc     (hl)        ; increase
0B02: 22 C0 63    ld      (timer_unknown_63c0),hl  ; store HL into ???
0B05: C9          ret                 ; return

; arrive from #0A79 when intro screen indicator == 4

0B06: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
0B09: 0F          rrca                ; rotate right.  carry bit?
0B0A: D8          ret     c           ; yes, return

0B0B: 2A C2 63    ld      hl,(store_63c2)  ; load HL with ??? EG HL = #38B4
0B0E: 7E          ld      a,(hl)      ; load table data
0B0F: FE 7F       cp      $7f         ; end of data ?
0B11: CA 1E 0B    jp      z,$0b1e     ; yes, jump ahead

0B14: 23          inc     hl          ; next HL
0B15: 22 C2 63    ld      (store_63c2),hl  ; store
0B18: 4F          ld      c,a         ; C := A
0B19: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite
0B1C: FF          rst     $38         ; move kong
0B1D: C9          ret                 ; return

0B1E: 21 5C 38    ld      hl,$385c    ; load HL with start of kong graphic table data
0B21: CD 4E 00    call    $004e       ; update kong's sprites
0B24: 11 00 69    ld      de,girls_head_sprite_6900    ; load destination with girl sprite
0B27: 01 08 00    ld      bc,$0008    ; set counter to 8
0B2A: ED B0       ldir                ; draw the girl after kong takes her up the ladder
0B2C: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with kong sprite start address
0B2F: 0E 50       ld      c,$50       ; C := #50
0B31: FF          rst     $38         ; move kong
0B32: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite
0B35: 0E FC       ld      c,$fc       ; C := #FC
0B37: FF          rst     $38         ; move kong

0B38: CD 4A 30    call    $304a       ; roll up kong's ladder behind him
0B3B: 3A 8E 63    ld      a,(kong_ladder_climb_counter_638e)   ; load A with kong ladder climb counter
0B3E: FE 0A       cp      $0a         ; == #A ? (all done)
0B40: C2 38 0B    jp      nz,$0b38    ; no, loop again

0B43: 3E 03       ld      a,$03       ; set boom sound duration
0B45: 32 82 60    ld      (boom_sound_address_6082),a   ; play boom sound
0B48: 11 2C 39    ld      de,$392c    ; load DE with table data start for first angled girder
0B4B: CD A7 0D    call    $0da7       ; draw the angled girder
0B4E: 3E 10       ld      a,$10       ; A := #10 = clear character
0B50: 32 AA 74    ld      ($74aa),a   ; clear the right end of the top girder
0B53: 32 8A 74    ld      ($748a),a   ; clear the right end of the top girder
0B56: 3E 05       ld      a,$05       ; A := 5
0B58: 32 8D 63    ld      (kong_bounce_counter_638d),a   ; store into kong bounce counter
0B5B: 3E 20       ld      a,$20       ; A := #20
0B5D: 32 09 60    ld      (waittimermsb_6009),a; set timer to #20
0B60: 21 85 63    ld      hl,intro_screen_counter_6385    ; load HL with intro screen counter
0B63: 34          inc     (hl)        ; increase
0B64: 22 C0 63    ld      (timer_unknown_63c0),hl  ; store into ???
0B67: C9          ret                 ; return

; arrive from #0A79 when intro screen indicator == 6

0B68: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
0B6B: 0F          rrca                ; rotate right.  carry bit set?
0B6C: D8          ret     c           ; yes, return

; make kong jump to the left during intro

0B6D: 2A C4 63    ld      hl,(unknown_63c4)  ; load HL with ??? (table data?)
0B70: 7E          ld      a,(hl)      ; get table data
0B71: FE 7F       cp      $7f         ; done ?
0B73: CA 86 0B    jp      z,$0b86     ; yes, jump ahead

0B76: 23          inc     hl          ; next table entry
0B77: 22 C4 63    ld      (unknown_63c4),hl  ; store for next
0B7A: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite
0B7D: 4F          ld      c,a         ; C := A
0B7E: FF          rst     $38         ; move kong
0B7F: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of Kong sprite
0B82: 0E FF       ld      c,$ff       ; C := #FF (negative 1)
0B84: FF          rst     $38         ; move kong
0B85: C9          ret                 ; return

0B86: 21 CB 38    ld      hl,$38cb    ; load HL with start of table data
0B89: 22 C4 63    ld      (unknown_63c4),hl  ; store into ???
0B8C: 3E 03       ld      a,$03       ; set boom sound duration
0B8E: 32 82 60    ld      (boom_sound_address_6082),a   ; play boom sound
0B91: 21 DC 38    ld      hl,$38dc    ; load HL with start of table data
0B94: 3A 8D 63    ld      a,(kong_bounce_counter_638d)   ; load A with kong bounce counter
0B97: 3D          dec     a           ; decrease
0B98: 07          rlca
0B99: 07          rlca
0B9A: 07          rlca
0B9B: 07          rlca                ; rotate left 4 times (mult by 16)
0B9C: 5F          ld      e,a         ; copy to E
0B9D: 16 00       ld      d,$00       ; D := 0
0B9F: 19          add     hl,de       ; add to HL
0BA0: EB          ex      de,hl       ; DE <> HL
0BA1: CD A7 0D    call    $0da7       ; draw the screen
0BA4: 21 8D 63    ld      hl,kong_bounce_counter_638d    ; load HL with kong bounce counter
0BA7: 35          dec     (hl)        ; decrease.  done bouncing?
0BA8: C0          ret     nz          ; no, return

0BA9: 3E B0       ld      a,$b0       ; else A := #B0
0BAB: 32 09 60    ld      (waittimermsb_6009),a; store into counter
0BAE: 21 85 63    ld      hl,intro_screen_counter_6385    ; load HL with intro screen counter
0BB1: 34          inc     (hl)        ; increase
0BB2: C9          ret                 ; return

; arrive from #0A79 - last part of the intro to the game ?

0BB3: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load HL with music sound address
0BB6: 3A 09 60    ld      a,(waittimermsb_6009) ; load A with timer value
0BB9: FE 90       cp      $90         ; == #90 ?
0BBB: 20 0B       jr      nz,$0bc8    ; no, skip ahead

0BBD: 36 0F       ld      (hl),$0f    ; play sound #0F = X X X kong sound
0BBF: 23          inc     hl          ; HL := GameMode2
0BC0: 36 03       ld      (hl),$03    ; set game mode2 to 3
0BC2: 21 19 69    ld      hl,unknown_6919    ; load HL with kong's face sprite
0BC5: 34          inc     (hl)        ; increase - kong is now showing teeth
0BC6: 18 09       jr      $0bd1       ; skip ahead

0BC8: FE 18       cp      $18         ; timer == #18 ?
0BCA: 20 05       jr      nz,$0bd1    ; no, skip ahead

0BCC: 21 19 69    ld      hl,unknown_6919    ; load HL with kong's face sprite
0BCF: 35          dec     (hl)        ; decrease - kong is normal face
0BD0: 00          nop                 ; no operation [?]

0BD1: DF          rst     $18         ; count down timer and only continue here if zero, else RET.  HL is loaded with WaitTimerMSB address
0BD2: AF          xor     a           ; A := 0
0BD3: 32 85 63    ld      (intro_screen_counter_6385),a   ; reset intro screen counter to zero
0BD6: 34          inc     (hl)        ; increase timer in WaitTimerMSB
0BD7: 23          inc     hl          ; HL := GameMode2
0BD8: 34          inc     (hl)        ; increase game mode2 (to 8?)
0BD9: C9          ret                 ; return

; called after kong jump on the girders at start of game ?
; also after mario dies
; how high can you get ?
; draws goofy kongs and 25m, 50m, etc.
; plays music

0BDA: CD 1C 01    call    $011c       ; clear all sounds
0BDD: DF          rst     $18         ; count down timer and only continue here if zero, else RET

0BDE: CD 74 08    call    $0874       ; clear the screen and sprites
0BE1: 16 06       ld      d,$06       ; load task #6
0BE3: 3A 00 62    ld      a,(mario_array_6200)   ; load A with 1 when mario is alive, 0 when dead
0BE6: 5F          ld      e,a         ; store into task parameter
0BE7: CD 9F 30    call    $309f       ; insert task to display remaining lives and level number
0BEA: 21 86 7D    ld      hl,reg_palette_a; load HL with palette bank
0BED: 36 01       ld      (hl),$01    ; set palette bank selector
0BEF: 23          inc     hl          ; next pallete bank
0BF0: 36 00       ld      (hl),$00    ; clear palette bank selector
0BF2: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load HL with tune address
0BF5: 36 02       ld      (hl),$02    ; play how high can you get sound?
0BF7: 23          inc     hl          ; HL := #608B .  load HL with music timer ?
0BF8: 36 03       ld      (hl),$03    ; set to 3 units
0BFA: 21 A7 63    ld      hl,store_63a7    ; load HL with address of counter
0BFD: 36 00       ld      (hl),$00    ; clear the counter
0BFF: 21 DC 76    ld      hl,$76dc    ; load HL with screen address to draw the number of meters ?
0C02: 22 A8 63    ld      (screen_pointer_for_meters_63a8),hl  ; store - used at #0C54
0C05: 3A 2E 62    ld      a,(number_of_goofys_to_draw_622e)   ; load A with number of goofy kongs to draw
0C08: FE 06       cp      $06         ; < 6 ?
0C0A: 38 05       jr      c,$0c11     ; yes, skip next 2 steps [BUG.  change to 0C0A  1805   JR #0C11 to fix]

0C0C: 3E 05       ld      a,$05       ; else A := 5
0C0E: 32 2E 62    ld      (number_of_goofys_to_draw_622e),a   ; store into number of goofy kongs to draw

0C11: 3A 2F 62    ld      a,(current_screen_level_622f)   ; load A with current screen/level
0C14: 47          ld      b,a         ; copy to B
0C15: 3A 2A 62    ld      a,(store_622a)   ; load A with the low byte of the pointer for lookup to screens/levels
0C18: B8          cp      b           ; are they the same ?
0C19: 28 04       jr      z,$0c1f     ; yes, skip next 2 steps

0C1B: 21 2E 62    ld      hl,number_of_goofys_to_draw_622e    ; else load HL with number of goofys to draw
0C1E: 34          inc     (hl)        ; increase

0C1F: 32 2F 62    ld      (current_screen_level_622f),a   ; store A into current screen/level
0C22: 3A 2E 62    ld      a,(number_of_goofys_to_draw_622e)   ; load A with number of goofys to draw
0C25: 47          ld      b,a         ; copy to B for use as loop counter, refer to #0C7E
0C26: 21 BC 75    ld      hl,$75bc    ; load HL with screen location start for goofy kong

0C29: 0E 50       ld      c,$50       ; C := #50 = start graphic for goofy kong

0C2B: 71          ld      (hl),c      ; draw part of goofy kong
0C2C: 0C          inc     c           ; next graphic
0C2D: 2B          dec     hl          ; next screen location
0C2E: 71          ld      (hl),c      ; draw part of goofy kong
0C2F: 0C          inc     c           ; next graphic
0C30: 2B          dec     hl          ; next screen location
0C31: 71          ld      (hl),c      ; draw part of goofy kong
0C32: 0C          inc     c           ; next graphic
0C33: 2B          dec     hl          ; next screen location
0C34: 71          ld      (hl),c      ; draw part of goofy kong
0C35: 79          ld      a,c         ; load A with graphic number
0C36: FE 67       cp      $67         ; == #67 ? (are we done?)
0C38: CA 43 0C    jp      z,$0c43     ; yes, skip next 4 steps

0C3B: 0C          inc     c           ; next C
0C3C: 11 23 00    ld      de,$0023    ; load DE with offset
0C3F: 19          add     hl,de       ; add to screen location
0C40: C3 2B 0C    jp      $0c2b       ; loop again

0C43: 3A A7 63    ld      a,(store_63a7)   ; load A with counter
0C46: 3C          inc     a           ; increase
0C47: 32 A7 63    ld      (store_63a7),a   ; store
0C4A: 3D          dec     a           ; decrease
0C4B: CB 27       sla     a
0C4D: CB 27       sla     a           ; shift left twice, it is now a usable offset
0C4F: E5          push    hl          ; save HL
0C50: 21 F0 3C    ld      hl,$3cf0    ; load HL with start of table data for 25m, 50m, etc.
0C53: C5          push    bc          ; save BC
0C54: DD 2A A8 63 ld      ix,(screen_pointer_for_meters_63a8)  ; load IX with screen VRAM address to draw number of meters
0C58: 4F          ld      c,a         ; C := A, used for offset
0C59: 06 00       ld      b,$00       ; B := 0
0C5B: 09          add     hl,bc       ; add offset
0C5C: 7E          ld      a,(hl)      ; get table data
0C5D: DD 77 60    ld      (ix+$60),a  ; write to screen
0C60: 23          inc     hl          ; next
0C61: 7E          ld      a,(hl)      ; get data
0C62: DD 77 40    ld      (ix+$40),a  ; write to screen
0C65: 23          inc     hl          ; next
0C66: 7E          ld      a,(hl)      ; get table data
0C67: DD 77 20    ld      (ix+$20),a  ; write to screen
0C6A: DD 36 E0 8B ld      (ix-$20),$8b; write "m" to screen
0C6E: C1          pop     bc          ; restore BC
0C6F: DD E5       push    ix          ; transfer IX to HL (part 1/2)
0C71: E1          pop     hl          ; transfer IX to HL (part 2/2)
0C72: 11 FC FF    ld      de,$fffc    ; load offset for next screen location
0C75: 19          add     hl,de       ; add offset
0C76: 22 A8 63    ld      (screen_pointer_for_meters_63a8),hl  ; store result
0C79: E1          pop     hl          ; restore HL
0C7A: 11 5F FF    ld      de,$ff5f    ; load DE with offset for goofy
0C7D: 19          add     hl,de       ; add offset to draw next goofy
0C7E: 05          dec     b           ; decrease B.  done drawing goofy kongs ?
0C7F: C2 29 0C    jp      nz,$0c29    ; no, loop and do another [why not use DJNZ ???]

0C82: 11 07 03    ld      de,$0307    ; load task data for text #7 "HOW HIGH CAN YOU GET?"
0C85: CD 9F 30    call    $309f       ; insert task to draw text
0C88: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer to wait
0C8B: 36 A0       ld      (hl),$a0    ; set timer for #A0 units
0C8D: 23          inc     hl          ; HL := GameMode2
0C8E: 34          inc     (hl)
0C8F: 34          inc     (hl)        ; increase game mode twice - starts game
0C90: C9          ret                 ; return

; arrive here from #0701 when game mode = 9
; clears screen, update timers, draws current screen, sets background music,

0C91: DF          rst     $18         ; count down WaitTimerMSB and only continue when 0

; arrive here from #0776 during attract mode

0C92: CD 74 08    call    $0874       ; clears the screen and sprites
0C95: AF          xor     a           ; A := 0
0C96: 32 8C 63    ld      (onscreen_timer_638c),a   ; reset onscreen timer
0C99: 11 01 05    ld      de,$0501    ; load DE with task #5, parameter 1 update onscreen bonus timer and play sound & change to red if below 1000
0C9C: CD 9F 30    call    $309f       ; insert task
0C9F: 21 86 7D    ld      hl,reg_palette_a; load HL with palette bank selector
0CA2: 36 00       ld      (hl),$00    ; clear palette bank selector
0CA4: 23          inc     hl          ; next bank
0CA5: 36 01       ld      (hl),$01    ; set palette bank selector
0CA7: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
0CAA: 3D          dec     a           ; decrease by 1
0CAB: CA D4 0C    jp      z,$0cd4     ; if zero jump to #0Cd4 - we were on girders - continue on #0CC6

0CAE: 3D          dec     a           ; if not decrease a again
0CAF: CA DF 0C    jp      z,$0cdf     ; if zero jump to #0CDf - we were on pie - continue on #0CC6

0CB2: 3D          dec     a           ; if not decrease a again
0CB3: CA F2 0C    jp      z,$0cf2     ; iF zero jump to #0CF2 - we were on elevators - continue on #0CC6

                                        ; else we are on rivets

0CB6: CD 43 0D    call    $0d43       ; draws the blue vertical bars next to kong on rivets
0CB9: 21 86 7D    ld      hl,reg_palette_a; load HL with palette bank selector
0CBC: 36 01       ld      (hl),$01    ; set palette bank selector
0CBE: 3E 0B       ld      a,$0b       ; load A with music code For rivets
0CC0: 32 89 60    ld      (background_music_value_6089),a   ; set music
0CC3: 11 8B 3C    ld      de,$3c8b    ; load DE with start of table data for rivets

; other screens return here

0CC6: CD A7 0D    call    $0da7       ; draw the screen

0CC9: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
0CCC: FE 04       cp      $04         ; screen is rivets level?
0CCE: CC 00 0D    call    z,$0d00     ; yes, call sub to draw the rivets

0CD1: C3 A0 3F    jp      $3fa0       ; fix rectractable ladders for pie factory and returns to #0D5F. [orig code was JP #0D5F ?]

; girders from #0CAB

0CD4: 11 E4 3A    ld      de,$3ae4    ; Load DE with start of table data for girders
0CD7: 3E 08       ld      a,$08       ; A := 8 = music code for girders
0CD9: 32 89 60    ld      (background_music_value_6089),a   ; set music for girders
0CDC: C3 C6 0C    jp      $0cc6       ; jump back

; conveyors from #0CAF

0CDF: 11 5D 3B    ld      de,$3b5d    ; load DE with start of table data for conveyors
0CE2: 21 86 7D    ld      hl,reg_palette_a; load HL with palette bank selector
0CE5: 36 01       ld      (hl),$01    ; set palette bank selector
0CE7: 23          inc     hl
0CE8: 36 00       ld      (hl),$00    ; clear palette bank selector
0CEA: 3E 09       ld      a,$09       ; load A with conveyor music
0CEC: 32 89 60    ld      (background_music_value_6089),a   ; set music for conveyors
0CEF: C3 C6 0C    jp      $0cc6       ; jump back

; elevators from #0CB3

0CF2: CD 27 0D    call    $0d27       ; draw elevator cables
0CF5: 3E 0A       ld      a,$0a       ; A := #A
0CF7: 32 89 60    ld      (background_music_value_6089),a   ; set music for elevators
0CFA: 11 E5 3B    ld      de,$3be5    ; load DE with start of table data for the elevators
0CFD: C3 C6 0C    jp      $0cc6       ; jump back

; For the rivets level only  - draw the rivets

0D00: 06 08       ld      b,$08       ; for B = 1 to 8 rivets to draw
0D02: 21 17 0D    ld      hl,$0d17    ; load HL with start of table data below

0D05: 3E B8       ld      a,$b8       ; load A with #B8 = start code for rivet
0D07: 0E 02       ld      c,$02       ; For C = 1 to 2
0D09: 5E          ld      e,(hl)      ; load E with the high byte of the address
0D0A: 23          inc     hl          ; next HL
0D0B: 56          ld      d,(hl)      ; load D with the low byte of the adddress
0D0C: 23          inc     hl          ; next HL

0D0D: 12          ld      (de),a      ; draw rivet onscreen
0D0E: 3D          dec     a           ; next graphic
0D0F: 13          inc     de          ; next screen address
0D10: 0D          dec     c           ; Next C
0D11: C2 0D 0D    jp      nz,$0d0d    ; loop until done

0D14: 10 EF       djnz    $0d05       ; Next B

0D16: C9          ret                 ; return

; start of table data for rivets used above
; these are addresses in video RAM for the rivets

0D17  CA 76             ; #76CA
0D19  CF 76             ; #76CF
0D1B  D4 76             ; #76D4
0D1D  D9 76             ; #76D9
0D1F  2A 75             ; #752A
0D21  2F 75             ; #752F
0D23  34 75             ; #7534
0D25  39 75             ; #7539

; called from #0CF2 for elevators only
; draws the elevator cables

0D27: 21 0D 77    ld      hl,$770d    ; load HL with screen RAM location
0D2A: CD 30 0D    call    $0d30       ; draw the left side elevator cable

0D2D: 21 0D 76    ld      hl,$760d    ; load HL with screen RAM location for right side cable

0D30: 06 11       ld      b,$11       ; for B = 1 to #11

0D32: 36 FD       ld      (hl),$fd    ; draw the cable to screen
0D34: 23          inc     hl          ; next location
0D35: 10 FB       djnz    $0d32       ; Next B

0D37: 11 0F 00    ld      de,$000f    ; load DE with offset [why here? should be before loop starts ?]
0D3A: 19          add     hl,de       ; add offset to location
0D3B: 06 11       ld      b,$11       ; for B = 1 to #11

0D3D: 36 FC       ld      (hl),$fc    ; draw cable to screen
0D3F: 23          inc     hl          ; next location
0D40: 10 FB       djnz    $0d3d       ; Next B

0D42: C9          ret                 ; return

; called from #0CB6 for rivets only
; draws top light blue vertical bars next to Kong

0D43: 21 87 76    ld      hl,$7687    ; load HL with screen location (left side)
0D46: CD 4C 0D    call    $0d4c       ; draw the bars
0D49: 21 47 75    ld      hl,$7547    ; load HL with screen location (right side)
0D4C: 06 04       ld      b,$04       ; for B = 1 to 4

0D4E: 36 FD       ld      (hl),$fd    ; draw a bar
0D50: 23          inc     hl          ; next screen location
0D51: 10 FB       djnz    $0d4e       ; Next B

0D53: 11 1C 00    ld      de,$001c    ; load offset
0D56: 19          add     hl,de       ; add offset
0D57: 06 04       ld      b,$04       ; for B = 1 to 4

0D59: 36 FC       ld      (hl),$fc    ; draw a bar
0D5B: 23          inc     hl          ; next screen location
0D5C: 10 FB       djnz    $0d59       ; next B

0D5E: C9          ret                 ; return

; jump here from #0CD1 (via #3FA3)

0D5F: CD 56 0F    call    $0f56       ; clear and initialize RAM values, compute initial timer, draw all initial sprites
0D62: CD 41 24    call    $2441
0D65: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer addr.
0D68: 36 40       ld      (hl),$40    ; set timer to #40
0D6A: 23          inc     hl          ; HL := GameMode2
0D6B: 34          inc     (hl)        ; increase game mode2
0D6C: 21 5C 38    ld      hl,$385c    ; load HL with start of kong graphic table data
0D6F: CD 4E 00    call    $004e       ; update kong's sprites

0D72: 11 00 69    ld      de,girls_head_sprite_6900    ; set destination to girl sprite
0D75: 01 08 00    ld      bc,$0008    ; set counter to 8
0D78: ED B0       ldir                ; draw the girl on screen

0D7A: 3A 27 62    ld      a,(screen_number_6227)   ; load a with screen number
0D7D: fe 04       cp      $04         ; is this rivets screen?
0D7f: 28 0A       jr      z,$0d8b     ; if yes, jump ahead a bit

0D81: 0F          rrca                ; no, roll right twice
0D82: 0F          rrca                ; is this the conveyors or the elevators ?
0D83: d8          ret     c           ; yes, return

                                        ; else this is girders, kong needs to be moved

0D84: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of kong sprite
0D87: 0E FC       ld      c,$fc       ; set to move by -4
0D89: FF          rst     $38         ; move kong
0D8A: C9          ret                 ; return

; on the rivets

0D8B: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with kong sprite RAM
0D8E: 0E 44       ld      c,$44       ; set counter to #44 ?
0D90: FF          rst     $38         ; move kong

0D91: 11 04 00    ld      de,$0004    ; load counters
0D94: 01 10 02    ld      bc,$0210    ; load counters
0D97: 21 00 69    ld      hl,girls_head_sprite_6900    ; load HL with start of sprite RAM (girl sprite first)
0D9A: CD 3D 00    call    $003d       ; move girl to right

0D9D: 01 F8 02    ld      bc,$02f8    ; load counters
0DA0: 21 03 69    ld      hl,sprite_girl_table_data_y_position_6903    ; load HL with Y value of girl -1
0DA3: CD 3D 00    call    $003d       ; move girl up

0DA6: C9          ret                 ; return [to #1983]

; part of routine which draws the screen
; DE is preloaded with address of table data
; called from many places

0DA7: 1A          ld      a,(de)      ; load a with DE - points to start of table data
0DA8: 32 B3 63    ld      (original_data_item_63b3),a   ; save for later use
0DAB: FE AA       cp      $aa         ; is this the end of the data?
0DAD: C8          ret     z           ; yes, return

; else draw screen stuff

0DAE: 13          inc     de          ; next table entry
0DAF: 1A          ld      a,(de)      ; load A with table data
0DB0: 67          ld      h,a         ; copy to H
0DB1: 44          ld      b,h         ; copy to B
0DB2: 13          inc     de          ; next table entry
0DB3: 1A          ld      a,(de)      ; load A with table data
0DB4: 6F          ld      l,a         ; copy to L
0DB5: 4D          ld      c,l         ; copy to C
0DB6: D5          push    de          ; save DE
0DB7: CD F0 2F    call    $2ff0       ; convert HL into VRAM address
0DBA: D1          pop     de          ; restore DE
0DBB: 22 AB 63    ld      (unknown_63ab),hl  ; store the VRAM address into this location for later use.  starting point of whatever we are drawing
0DBE: 78          ld      a,b         ; A := B = original data item
0DBF: E6 07       and     $07         ; mask bits, now between 0 and 7
0DC1: 32 B4 63    ld      (unknown_63b4),a   ; store into ???
0DC4: 79          ld      a,c         ; A := C = 2nd data item
0DC5: E6 07       and     $07         ; mask bits, now between 0 and 7
0DC7: 32 AF 63    ld      (original_data_item__63af),a   ; store into ???
0DCA: 13          inc     de          ; next table entry
0DCB: 1A          ld      a,(de)      ; load A with table data
0DCC: 67          ld      h,a         ; copy to H
0DCD: 90          sub     b           ; subract the original data.  less than zero?
0DCE: D2 D3 0D    jp      nc,$0dd3    ; no, skip next step

0DD1: ED 44       neg                 ; Negate A (A := #FF - A)

0DD3: 32 B1 63    ld      (result_63b1),a   ; store into ???
0DD6: 13          inc     de          ; next table entry
0DD7: 1A          ld      a,(de)      ; load A with table data
0DD8: 6F          ld      l,a         ; copy to L
0DD9: 91          sub     c           ; subtract the 2nd data item
0DDA: 32 B2 63    ld      (unknown_63b2),a   ; store into ???
0DDD: 1A          ld      a,(de)      ; load A with same table data
0DDE: E6 07       and     $07         ; mask bits, now between 0 and 7
0DE0: 32 B0 63    ld      (unknown_63b0),a   ; store into ???
0DE3: D5          push    de          ; save DE
0DE4: CD F0 2F    call    $2ff0       ; convert HL into VRAM address
0DE7: D1          pop     de          ; restore DE
0DE8: 22 AD 63    ld      (unknown_63ad),hl  ; store into ???
0DEB: 3A B3 63    ld      a,(original_data_item_63b3)   ; load A with first data item
0DEE: FE 02       cp      $02         ; < 2 ? are we drawing a ladder or a broken ladder?
0DF0: F2 4F 0E    jp      p,$0e4f     ; no, skip ahead [why P, instead of NC ?]

; else we are drawing a ladder

0DF3: 3A B2 63    ld      a,(unknown_63b2)   ; load A with ???
0DF6: D6 10       sub     $10         ; subtract #10
0DF8: 47          ld      b,a         ; copy answer to B
0DF9: 3A AF 63    ld      a,(original_data_item__63af)   ; load A with ???
0DFC: 80          add     a,b         ; add B
0DFD: 32 B2 63    ld      (unknown_63b2),a   ; store into ???
0E00: 3A AF 63    ld      a,(original_data_item__63af)   ; load A with ??? computed above
0E03: C6 F0       add     a,$f0       ; add #F0
0E05: 2A AB 63    ld      hl,(unknown_63ab)  ; load HL with VRAM address to begin drawing
0E08: 77          ld      (hl),a      ; draw element to screen = girder above top of ladder ?
0E09: 2C          inc     l           ; next location
0E0A: D6 30       sub     $30         ; subtract #30.  now the element to draw is a ladder
0E0C: 77          ld      (hl),a      ; draw element to screen = top of ladder
0E0D: 3A B3 63    ld      a,(original_data_item_63b3)   ; load A with original data item
0E10: FE 01       cp      $01         ; == 1 ? (is this a broken ladder?)
0E12: C2 19 0E    jp      nz,$0e19    ; no, skip next 2 steps

0E15: AF          xor     a           ; A := 0
0E16: 32 B2 63    ld      (unknown_63b2),a   ; store into ???

0E19: 3A B2 63    ld      a,(unknown_63b2)   ; load A with ???
0E1C: D6 08       sub     $08         ; subtract 8
0E1E: 32 B2 63    ld      (unknown_63b2),a   ; store.  are we done?
0E21: DA 2A 0E    jp      c,$0e2a     ; yes, skip ahead

0E24: 2C          inc     l           ; next HL
0E25: 36 C0       ld      (hl),$c0    ; draw ladder to screen
0E27: C3 19 0E    jp      $0e19       ; loop again

0E2A: 3A B0 63    ld      a,(unknown_63b0)   ; load A with ???
0E2D: C6 D0       add     a,$d0       ; add #D0
0E2F: 2A AD 63    ld      hl,(unknown_63ad)
0E32: 77          ld      (hl),a
0E33: 3A B3 63    ld      a,(original_data_item_63b3)   ; load A with original data item
0E36: FE 01       cp      $01         ; == 1 ?  (is this a broken ladder ?)
0E38: C2 3F 0E    jp      nz,$0e3f    ; no, skip next 3 steps

; this is a broken ladder.  draw bottom part of ladder

0E3B: 2D          dec     l           ; decrease HL
0E3C: 36 C0       ld      (hl),$c0    ; set HL to #C0 - draws bottom part of broken ladder to screen
0E3E: 2C          inc     l           ; increase HL

0E3F: 3A B0 63    ld      a,(unknown_63b0)   ; load A with ???
0E42: FE 00       cp      $00         ; == 0 ?
0E44: CA 4B 0E    jp      z,$0e4b     ; yes, skip next 3 steps

0E47: C6 E0       add     a,$e0       ; add #E0
0E49: 2C          inc     l           ; next HL
0E4A: 77          ld      (hl),a      ; store into ???

0E4B: 13          inc     de          ; next table entry
0E4C: C3 A7 0D    jp      $0da7       ; loop again

; arrive from #0DF0

0E4F: 3A B3 63    ld      a,(original_data_item_63b3)   ; load A with original data item [why do this again ?  it was loaded just before coming here]
0E52: FE 02       cp      $02         ; == 2 ?
0E54: C2 E8 0E    jp      nz,$0ee8    ; no, skip ahead

; else data item type 2 = girder ???

0E57: 3A AF 63    ld      a,(original_data_item__63af)   ; load A with original data item #2, masked to be between 0 and 7
0E5A: C6 F0       add     a,$f0       ; add #F0
0E5C: 32 B5 63    ld      (unknown_63b5),a   ; store into ???
0E5F: 2A AB 63    ld      hl,(unknown_63ab)  ; load HL with screen address to being drawing the item

0E62: 3A B5 63    ld      a,(unknown_63b5)   ; load A with ???
0E65: 77          ld      (hl),a      ; draw element to screen
0E66: 23          inc     hl          ; next screen location
0E67: 7D          ld      a,l         ; A := L
0E68: E6 1F       and     $1f         ; mask bits, now between 0 and #1F.  at zero ?
0E6A: CA 78 0E    jp      z,$0e78     ; yes, skip ahead

0E6D: 3A B5 63    ld      a,(unknown_63b5)   ; load A with ???
0E70: FE F0       cp      $f0         ; == #F0 ?
0E72: CA 78 0E    jp      z,$0e78     ; yes, skip next 2 steps

0E75: D6 10       sub     $10         ; subtract #10
0E77: 77          ld      (hl),a      ; store

0E78: 01 1F 00    ld      bc,$001f    ; load BC with offset
0E7B: 09          add     hl,bc       ; add offset to HL
0E7C: 3A B1 63    ld      a,(result_63b1)   ; load A with ???
0E7F: D6 08       sub     $08         ; subtract 8.  done?
0E81: DA CF 0E    jp      c,$0ecf     ; yes, skip ahead for next

0E84: 32 B1 63    ld      (result_63b1),a   ; store A into ???
0E87: 3A B2 63    ld      a,(unknown_63b2)   ; load A with ???
0E8A: FE 00       cp      $00         ; == 0 ? [why written this way?]
0E8C: CA 62 0E    jp      z,$0e62     ; yes, jump back and draw another [of same?]

0E8F: 3A B5 63    ld      a,(unknown_63b5)
0E92: 77          ld      (hl),a      ; draw element to screen
0E93: 23          inc     hl          ; next screen location
0E94: 7D          ld      a,l         ; A := L
0E95: E6 1F       and     $1f         ; mask bits, now between 0 and #1F.  at zero?
0E97: CA A0 0E    jp      z,$0ea0     ; yes, skip next 3 steps

0E9A: 3A B5 63    ld      a,(unknown_63b5)   ; load A with ???
0E9D: D6 10       sub     $10         ; subtract #10
0E9F: 77          ld      (hl),a      ; store to screen.  draws bottom half of a girder

0EA0: 01 1F 00    ld      bc,$001f    ; load BC with offset
0EA3: 09          add     hl,bc       ; add offset for next screen element
0EA4: 3A B1 63    ld      a,(result_63b1)   ; load A with ???
0EA7: D6 08       sub     $08         ; subtract 8.  done?
0EA9: DA CF 0E    jp      c,$0ecf     ; yes, skip ahead for next

0EAC: 32 B1 63    ld      (result_63b1),a   ; store A into ???
0EAF: 3A B2 63    ld      a,(unknown_63b2)   ; load A with ???
0EB2: CB 7F       bit     7,a         ; test bit 7.  is it zero?
0EB4: C2 D3 0E    jp      nz,$0ed3    ; no, skip ahead

0EB7: 3A B5 63    ld      a,(unknown_63b5)   ; load A with ???
0EBA: 3C          inc     a           ; increase
0EBB: 32 B5 63    ld      (unknown_63b5),a   ; store result
0EBE: FE F8       cp      $f8         ; == #F8 ?
0EC0: C2 C9 0E    jp      nz,$0ec9    ; no, skip next 3 steps

0EC3: 23          inc     hl          ; next screen location
0EC4: 3E F0       ld      a,$f0       ; A := #F0
0EC6: 32 B5 63    ld      (unknown_63b5),a   ; store into ???

0EC9: 7D          ld      a,l         ; A := L
0ECA: E6 1F       and     $1f         ; mask bits.  now between 0 and #1F.  at zero?
0ECC: C2 62 0E    jp      nz,$0e62    ; no, jump back

0ECF: 13          inc     de          ; next table entry
0ED0: C3 A7 0D    jp      $0da7       ; loop back for more

0ED3: 3A B5 63    ld      a,(unknown_63b5)   ; load A with ???
0ED6: 3D          dec     a           ; decrease
0ED7: 32 B5 63    ld      (unknown_63b5),a   ; store result
0EDA: FE F0       cp      $f0         ; compare to #F0.  is the sign positive?
0EDC: F2 E5 0E    jp      p,$0ee5     ; yes, skip next 3 steps [why?  #0EE5 is a jump - it should jump directly instead]

0EDF: 2B          dec     hl
0EE0: 3E F7       ld      a,$f7       ; A := #F7
0EE2: 32 B5 63    ld      (unknown_63b5),a   ; store into ???

0EE5: C3 62 0E    jp      $0e62       ; jump back

; arrive from #0E54

0EE8: 3A B3 63    ld      a,(original_data_item_63b3)   ; load A with original data item [why load it again ? A already has #63B3]
0EEB: FE 03       cp      $03         ; == 3?
0EED: C2 1B 0F    jp      nz,$0f1b    ; no, skip ahead

; we are drawing a conveyor

0EF0: 2A AB 63    ld      hl,(unknown_63ab)  ; load HL with VRAM screen address to begin drawing
0EF3: 3E B3       ld      a,$b3       ; A := #B3 = code graphic for conveyor
0EF5: 77          ld      (hl),a      ; draw on screen
0EF6: 01 20 00    ld      bc,$0020    ; load BC with offset
0EF9: 09          add     hl,bc       ; add offset to HL
0EFA: 3A B1 63    ld      a,(result_63b1)   ; load A with ???
0EFD: D6 10       sub     $10         ; subtract #10.  done ?

0EFF: DA 14 0F    jp      c,$0f14     ; yes, skip ahead

0F02: 32 B1 63    ld      (result_63b1),a
0F05: 3E B1       ld      a,$b1       ; A := #B1
0F07: 77          ld      (hl),a      ; store into ???
0F08: 01 20 00    ld      bc,$0020    ; load BC with offset
0F0B: 09          add     hl,bc       ; add offset to HL
0F0C: 3A B1 63    ld      a,(result_63b1)   ; load A with ???
0F0F: D6 08       sub     $08         ; subtract 8
0F11: C3 FF 0E    jp      $0eff       ; loop again

0F14: 3E B2       ld      a,$b2       ; A := #B2
0F16: 77          ld      (hl),a      ; store (onscreen???)
0F17: 13          inc     de          ; next table entry
0F18: C3 A7 0D    jp      $0da7       ; loop back for more

; arrive from #0EED

0F1B: 3A B3 63    ld      a,(original_data_item_63b3)   ; load A with original data item [why load it again ? A already has #63B3]
0F1E: FE 07       cp      $07         ; <= 7 ?
0F20: F2 CF 0E    jp      p,$0ecf     ; no, skip back and loop for next data item

0F23: FE 04       cp      $04         ; first data item == 4 ?
0F25: CA 4C 0F    jp      z,$0f4c     ; yes, skip ahead to handle

0F28: FE 05       cp      $05         ; first data item == 5 ?
0F2A: CA 51 0F    jp      z,$0f51     ; yes, skip ahead to handle

; redraws screen when rivets has been completed

0F2D: 3E FE       ld      a,$fe       ; A := #FE

0F2F: 32 B5 63    ld      (unknown_63b5),a   ; store into ???
0F32: 2A AB 63    ld      hl,(unknown_63ab)  ; load HL with ???

0F35: 3A B5 63    ld      a,(unknown_63b5)   ; load A with ???
0F38: 77          ld      (hl),a      ; store into ???
0F39: 01 20 00    ld      bc,$0020    ; set offset to #20
0F3C: 09          add     hl,bc       ; add offset for next
0F3D: 3A B1 63    ld      a,(result_63b1)   ; load A with ???
0F40: D6 08       sub     $08         ; subtract 8
0F42: 32 B1 63    ld      (result_63b1),a   ; store result.  done ?
0F45: D2 35 0F    jp      nc,$0f35    ; no, loop again

0F48: 13          inc     de          ; else increase DE
0F49: C3 A7 0D    jp      $0da7       ; jump back

0F4C: 3E E0       ld      a,$e0       ; A := #E0
0F4E: C3 2F 0F    jp      $0f2f       ; jump back

0F51: 3E B0       ld      a,$b0       ; A := #B0
0F53: C3 2F 0F    jp      $0f2f       ; jump back

; called from #0D5F
; clears memories from #6200 - 6227 and #6280 to 6B00
; [why are #6280 - #6280+40 cleared?  they are set immediately after]
; computes initial timer
; initializes all sprites

0F56: 06 27       ld      b,$27       ; for B = 1 to #27
0F58: 21 00 62    ld      hl,mario_array_6200    ; load HL with start of address
0F5B: AF          xor     a           ; A := #00

0F5C: 77          ld      (hl),a      ; clear memory
0F5D: 2C          inc     l           ; next
0F5E: 10 FC       djnz    $0f5c       ; next B

0F60: 0E 11       ld      c,$11       ; For C = 1 to 11
0F62: 16 80       ld      d,$80       ; load D with 80, used to reset B in inner loop
0F64: 21 80 62    ld      hl,left_side_rectractable_ladder_6280    ; start of memory to clear
0F67: 42          ld      b,d         ; For B = 1 to #80

0F68: 77          ld      (hl),a      ; clear (HL)
0F69: 23          inc     hl          ; next memory
0F6A: 10 FC       djnz    $0f68       ; Next B

0F6C: 0D          dec     c           ; Next C
0F6D: 20 F8       jr      nz,$0f67    ; loop until done

0F6F: 21 9C 3D    ld      hl,$3d9c    ; source addr. = #3D9C - table data
0F72: 11 80 62    ld      de,left_side_rectractable_ladder_6280    ; Destination = #6280
0F75: 01 40 00    ld      bc,$0040    ; counter = #40 Bytes
0F78: ED B0       ldir                ; copy


;;; values are copied into #6280 through #6280 + #40
;;;     3D9C:                                      00 00 23 68
;;;     3DA0:  01 11 00 00 00 10 DB 68 01 40 00 00 08 01 01 01
;;;     3DB0:  01 01 01 01 01 01 00 00 00 00 00 00 80 01 C0 FF
;;;     3DC0:  01 FF FF 34 C3 39 00 67 80 69 1A 01 00 00 00 00
;;;     3DD0:  00 00 00 00 04 00 10 00 00 00 00 00
;;;

; set up initial timer
; timer is either 5000, 6000, 7000 or 8000 depending on level

0F7A: 3A 29 62    ld      a,(level_number_6229)   ; load level number
0F7D: 47          ld      b,a         ; copy to B
0F7E: A7          and     a           ; clear carry flag
0F7f: 17          rla                 ; rotate A left (double =2x)
0F80: A7          and     a           ; clear carry flag
0F81: 17          rla                 ; rotate A left (double again =4x)
0F82: A7          and     a           ; clear carry flag
0F83: 17          rla                 ; rotate A left (double again = 8x)
0F84: 80          add     a,b         ; add B into A  (add once = 9x)
0F85: 80          add     a,b         ; add B  into A  (add again = 10x)
0F86: C6 28       add     a,$28       ; add #28 (40 decimal) to A
0F88: FE 51       cp      $51         ; < #51 ?
0F8A: 38 02       jr      c,$0f8e     ; yes, skip next step

0F8C: 3E 50       ld      a,$50       ; otherwise load A with #50 (80 decimal)

0F8E: 21 B0 62    ld      hl,initial_clock_value_62b0    ; load HL with start of timers
0F91: 06 03       ld      b,$03       ; For B = 1 to 3

0F93: 77          ld      (hl),a      ; store A into timer memory
0F94: 2C          inc     l           ; next memory
0F95: 10 Fc       djnz    $0f93       ; Next B

0F97: 87          add     a,a         ; add A with A (double a).  A is now #64, #78, #8C, or #A0
0F98: 47          ld      b,a         ; copy to B
0F99: 3E DC       ld      a,$dc       ; A := #DC (220 decimal)
0F9B: 90          sub     b           ; subtract B.  answers are #78, #64, #50, or #3C
0F9C: FE 28       cp      $28         ; is this less than #28 (40 decimal) ?  (will never get this ... ???)
0F9E: 30 02       jr      nc,$0fa2    ; no, skip next step

0FA0: 3E 28       ld      a,$28       ; else load a with #28 (40). minimum value (never get this ... ?????)

0FA2: 77          ld      (hl),a      ; store A into address of HL=#62B3 which controls timers
0FA3: 2C          inc     l           ; HL := #62B4
0FA4: 77          ld      (hl),a      ; store A into the timer control
0FA5: 21 09 62    ld      hl,unknown_6209    ; load HL with #6209
0FA8: 36 04       ld      (hl),$04    ; store 4 into #6209
0FAA: 2C          inc     l           ; HL := #620A
0FAB: 36 08       ld      (hl),$08    ; store 8 into #620A
0FAD: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
0FB0: 4F          ld      c,a         ; copy to C, used at #0FCB
0FB1: CB 57       bit     2,a         ; is this the rivets ?
0FB3: 20 16       jr      nz,$0fcb    ; yes, skip ahead [would be better to jump to #1131, or JR to #0FCC]

; draw 3 black sprites above the top kongs ladder
; effect to erase the 2 girders at the top of kong's ladder

0FB5: 21 00 6A    ld      hl,blank_space_sprite_6a00    ; else load HL sprite RAM - used for blank space sprite
0FB8: 3E 4F       ld      a,$4f       ; A := #4F = X position of this sprite
0FBA: 06 03       ld      b,$03       ; For B = 1 to 3

0FBC: 77          ld      (hl),a      ; set the sprite X position
0FBD: 2C          inc     l           ; next address = sprite type
0FBE: 36 3A       ld      (hl),$3a    ; set sprite type as blank square
0FC0: 2C          inc     l           ; next address = sprite color
0FC1: 36 0F       ld      (hl),$0f    ; set color to black
0FC3: 2C          inc     l           ; next address = sprite Y position
0FC4: 36 18       ld      (hl),$18    ; set sprite Y position to #18
0FC6: 2C          inc     l           ; next memory
0FC7: C6 10       add     a,$10       ; A := A + #10 to adjust for next X position
0FC9: 10 F1       djnz    $0fbc       ; Next B

0FCB: 79          ld      a,c         ; load A with screen number
0FCC: EF          rst     $28         ; jump depending on the screen

; jump table data

0FCD  00 00                             ; unused
0FCF  D7 0F                             ; #0FD7 for girders
0FD1  1F 10                             ; #101F for conveyors
0FD3  87 10                             ; #1087 for elevators
0FD5  31 11                             ; #1131 for rivets

; arrive here when playing girders

0FD7: 21 DC 3D    ld      hl,$3ddc    ; source - has the information about the barrel pile at #3DDC
0FDA: 11 A8 69    ld      de,extra_barrels_sprites_69a8    ; destination = sprites
0FDD: 01 10 00    ld      bc,$0010    ; counter is #10
0FE0: ED B0       ldir                ; draws the barrels pile next to kong

0FE2: 21 EC 3D    ld      hl,$3dec    ; set up a copy job from table in #3DEC
0FE5: 11 07 64    ld      de,unknown_6407    ; destination in memory is #6407
0FE8: 0E 1C       ld      c,$1c       ; #1C is a secondary counter
0FEA: 06 05       ld      b,$05       ; #05 is a secondary counter
0FEC: CD 2A 12    call    $122a       ; copy

0FEF: 21 F4 3D    ld      hl,$3df4    ; load HL with table data start for initial fire locations
0FF2: CD FA 11    call    $11fa       ; ???

0FF5: 21 00 3E    ld      hl,$3e00    ; source table at #3E00 = oil can
0FF8: 11 FC 69    ld      de,unknown_sprite_69fc    ; destination sprite at #69FC
0FFB: 01 04 00    ld      bc,$0004    ; 4 bytes
0FFE: ED B0       ldir                ; draw to screen

1000: 21 0C 3E    ld      hl,$3e0c    ; load HL with table data for hammers on girders
1003: CD A6 11    call    $11a6       ; ???

1006: 21 1B 10    ld      hl,$101b    ; set up copy job from table in #101B
1009: 11 07 67    ld      de,destination_6707    ; set destination ?
100C: 01 1C 08    ld      bc,$081c    ; set counters ?
100F: CD 2A 12    call    $122a       ; copy

1012: 11 07 68    ld      de,destination_6807    ; set destination ?
1015: 06 02       ld      b,$02       ; set counter to 2
1017: CD 2A 12    call    $122a       ; copy
101A: C9          ret                 ; return

; data used in sub at #1006

101B  00
101C  00
101D  02
101E  02

; arrive here when conveyors starts
; draws parts of the screen

101F: 21 EC 3D    ld      hl,$3dec    ; set up a copy job from table in #3DEC
1022: 11 07 64    ld      de,unknown_6407    ; desitnation in memory is #6407
1025: 01 1C 05    ld      bc,$051c    ; counters are #05 and #1C
1028: CD 2A 12    call    $122a       ; copy

102B: CD 86 11    call    $1186

102E: 21 18 3E    ld      hl,$3e18    ; set up copy job from table in #3E18
1031: 11 A7 65    ld      de,destination_is_65a7_65a7    ; destination is #65A7
1034: 01 0C 06    ld      bc,$060c    ; counters are #05 and #0C
1037: CD 2A 12    call    $122a       ; copy

103A: DD 21 A0 65 ld      ix,start_of_pies_65a0    ; load IX with start of pies
103E: 21 B8 69    ld      hl,start_of_pie_sprites_69b8    ; load HL with sprites for pies
1041: 11 10 00    ld      de,$0010    ; DE := #10
1044: 06 06       ld      b,$06       ; B := 6
1046: CD D3 11    call    $11d3

1049: 21 FA 3D    ld      hl,$3dfa    ; load HL with start of table data
104C: CD FA 11    call    $11fa       ; set fireball sprite

104F: 21 04 3E    ld      hl,$3e04    ; set up copy job from table in #3E04 = oil can sprite
1052: 11 FC 69    ld      de,unknown_sprite_69fc    ; destination is #69FC = sprite
1055: 01 04 00    ld      bc,$0004    ; four bytes to copy
1058: ED B0       ldir                ; draw oil can

105A: 21 1C 3E    ld      hl,$3e1c    ; load HL with start of table data
105D: 11 44 69    ld      de,sprite_start_for_moving_ladders_6944    ; load DE with sprite start for moving ladders
1060: 01 08 00    ld      bc,$0008    ; set byte counter to 8
1063: ED B0       ldir                ; draw moving ladders

1065: 21 24 3E    ld      hl,$3e24    ; set source table data
1068: 11 E4 69    ld      de,start_of_pulley_sprites_69e4    ; set destination RAM sprites
106B: 01 18 00    ld      bc,$0018    ; set counter
106E: ED B0       ldir                ; draw pulleys

1070: 21 10 3E    ld      hl,$3e10    ; load HL with table data for hammers on conveyors
1073: CD A6 11    call    $11a6       ; ???

1076: 21 3C 3E    ld      hl,$3e3c    ; load HL with table data for bonus items on conveyors
1079: 11 0C 6A    ld      de,start_of_bonus_items_6a0c    ; load DE with sprite destination
107C: 01 0C 00    ld      bc,$000c    ; 3 items x 4 bytes = 12 bytes (#0C)
107F: ED B0       ldir                ; draw bonus item sprites

1081: 3E 01       ld      a,$01       ; A := 1
1083: 32 B9 62    ld      (fire_release_62b9),a   ; store into fire release
1086: C9          ret                 ; return

; arrive here when elevators starts

1087: 21 EC 3D    ld      hl,$3dec    ; load HL with start of table data
108A: 11 07 64    ld      de,unknown_6407    ; set destination ???
108D: 01 1C 05    ld      bc,$051c    ; set counters
1090: CD 2A 12    call    $122a       ; copy ???

1093: CD 86 11    call    $1186

1096: 21 00 66    ld      hl,elevator_array_start_6600    ; load HL with start of elevator sprites ???
1099: 11 10 00    ld      de,$0010    ; load DE with offset to add
109C: 3E 01       ld      a,$01       ; A := 1
109E: 06 06       ld      b,$06       ; for B = 1 to 6

10A0: 77          ld      (hl),a      ; write value into memory
10A1: 19          add     hl,de       ; add offset for next
10A2: 10 FC       djnz    $10a0       ; next B

10A4: 0E 02       ld      c,$02       ; For C = 1 to 2
10A6: 3E 08       ld      a,$08       ; A := 8
10A8: 06 03       ld      b,$03       ; for B = 1 to 3
10AA: 21 0D 66    ld      hl,unknown_660d    ; load HL with ???

10AD: 77          ld      (hl),a      ; write value into memory
10AE: 19          add     hl,de       ; add offset for next
10AF: 10 FC       djnz    $10ad       ; next B

10B1: 3E 08       ld      a,$08       ; A := 8 [why?  A is already 8]
10B3: 0D          dec     c           ; next C
10B4: C2 A8 10    jp      nz,$10a8    ; loop until done

; used to draw elevator platforms???

; #6600 - 665F  = the 6 elevator values.  6610, 6620, 6630, 6640 ,6650 are starting values
;       + 3 is the X position, + 5 is the Y position

10B7: 21 64 3E    ld      hl,$3e64    ; start of table data
10BA: 11 03 66    ld      de,destination_sprite_?_x_positions_?_6603    ; Destination sprite ? X positions ?
10BD: 01 0E 06    ld      bc,$060e    ; Counter = #06, offset = #0E
10C0: CD EC 11    call    $11ec       ; set items from data table

10C3: 21 60 3E    ld      hl,$3e60    ; start of table data
10C6: 11 07 66    ld      de,destination_sprite_?_6607    ; Destination sprite ?
10C9: 01 0C 06    ld      bc,$060c    ; B = 6 is loop variable, C = offset ?
10CC: CD 2A 12    call    $122a

10CF: DD 21 00 66 ld      ix,elevator_array_start_6600    ; load IX with ???
10D3: 21 58 69    ld      hl,elevator_sprites_6958    ; load HL with elevator sprites start
10D6: 06 06       ld      b,$06       ; B := 6
10D8: 11 10 00    ld      de,$0010    ; load offset with #10
10DB: CD D3 11    call    $11d3       ; ???

10DE: 21 48 3E    ld      hl,$3e48    ; source is data table for bonus items on elevators
10E1: 11 0C 6A    ld      de,start_of_bonus_items_6a0c    ; destination is RAM area for bonus items
10E4: 01 0C 00    ld      bc,$000c    ; counter set for #0C bytes
10E7: ED B0       ldir                ; copy

; set up the 2 fireballs

10E9: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; load IX with start of fire #1
10ED: DD 36 00 01 ld      (ix+$00),$01; set fire active
10F1: DD 36 03 58 ld      (ix+$03),$58; set fire X position
10F5: DD 36 0E 58 ld      (ix+$0e),$58; set fire X position #2
10F9: DD 36 05 80 ld      (ix+$05),$80; set fire Y position
10FD: DD 36 0F 80 ld      (ix+$0f),$80; set fire Y position #2

; set up 2nd fireball

1101: DD 36 20 01 ld      (ix+$20),$01; set fire active
1105: DD 36 23 EB ld      (ix+$23),$eb; set fire X position
1109: DD 36 2E EB ld      (ix+$2e),$eb; set fire X position
110D: DD 36 25 60 ld      (ix+$25),$60; set fire Y position
1111: DD 36 2F 60 ld      (ix+$2f),$60; set fire Y position

1115: 11 70 69    ld      de,sprites_used_at_top_and_bottom_of_elevators_6970    ; destination #6970 (sprites used at top and bottom of elevators)
1118: 21 21 11    ld      hl,$1121    ; source data at table below
111B: 01 10 00    ld      bc,$0010    ; byte counter at #10
111E: ED B0       ldir                ; copy
1120: C9          ret                 ; return

; data used above for top and bottom of elevator shafts

1121  37 45 0F 60                       ; X = #37, color = #45, sprite = #F, Y = #60
1125  37 45 8F F7
1129  77 45 0F 60
112D  77 45 8F F7

; arrive here when rivets starts from #0FCC

1131: 21 F0 3D    ld      hl,$3df0    ; load HL with start of table data
1134: 11 07 64    ld      de,unknown_6407    ; load DE with destination ?
1137: 01 1C 05    ld      bc,$051c    ; set counters

113A: CD 2A 12    call    $122a       ; copy fire location data to screen?

113D: 21 14 3E    ld      hl,$3e14    ; load HL with start of table data for hammer locations
1140: CD A6 11    call    $11a6       ; draw the hammers

1143: 21 54 3E    ld      hl,$3e54    ; load HL with start of bonus items for rivets
1146: 11 0C 6A    ld      de,start_of_bonus_items_6a0c    ; set destination sprite address
1149: 01 0C 00    ld      bc,$000c    ; set counter to #C bytes to copy
114C: ED B0       ldir                ; draw purse, umbrella, hat to screen

114E: 21 82 11    ld      hl,$1182    ; load HL with start of data table
1151: 11 A3 64    ld      de,destination_?_64a3    ; load DE with destination ?
1154: 01 1E 02    ld      bc,$021e    ; set counters
1157: CD EC 11    call    $11ec       ; copy

; draws black squares next to kong???

115A: 21 7E 11    ld      hl,$117e    ; load HL with start of data table
115D: 11 A7 64    ld      de,set_destination_sprites_64a7    ; set destination sprites
1160: 01 1C 02    ld      bc,$021c    ; set counters B := 2, C := #1C
1163: CD 2A 12    call    $122a       ; copy

1166: DD 21 A0 64 ld      ix,address_of_black_square_sprite_start_64a0    ; load IX with address of black square sprite start
116A: DD 36 00 01 ld      (ix+$00),$01; store 1 into #64A0 = turn on first sprite
116E: DD 36 20 01 ld      (ix+$20),$01; store 1 into #64C0 = turn on second sprite

1172: 21 50 69    ld      hl,start_of_hammers_6950    ; load HL with ???
1175: 06 02       ld      b,$02       ; set counter to 2
1177: 11 20 00    ld      de,$0020    ; set offset to #20
117A: CD D3 11    call    $11d3       ; draw items ???

117D: C9          ret                 ; return

; data used above for black space next to kong

117E  3F 0C 08 08                       ; sprite code #3F (invisible square), color = #0C (black), size = 8x8 ???
1182  73 50 8D 50                       ; 1st is at #73,#50 and the 2nd is at #8D,#50

; called from #102B and #1093

1186: 21 A2 11    ld      hl,$11a2    ; load HL with start of data table
1189: 11 07 65    ld      de,destination_6507    ; load DE with destination
118C: 01 0C 0A    ld      bc,$0a0c    ; set counters
118F: CD 2A 12    call    $122a       ; copy

1192: DD 21 00 65 ld      ix,start_of_bouncer_memory_area_6500    ; load IX with ???
1196: 21 80 69    ld      hl,start_of_sprite_memory_for_bouncers_6980    ; load HL with sprite start (???)
1199: 06 0A       ld      b,$0a       ; B := #A
119B: 11 10 00    ld      de,$0010    ; load DE with offset
119E: CD D3 11    call    $11d3       ; copy

11A1: C9          ret                 ; return

; data table used above

11A2  3B 00 02 02

; called from 3 locations with HL preloaded with address of locations to draw to

11A6: 11 83 66    ld      de,sprite_destination_address_unknown_6683    ; load DE with sprite destination address ???
11A9: 01 0E 02    ld      bc,$020e    ; B := 2 for the 2 hammers.  C := #E for ???
11AC: CD EC 11    call    $11ec

11AF: 21 08 3E    ld      hl,$3e08    ; set source
11B2: 11 87 66    ld      de,unknown_6687    ; set destination
11B5: 01 0C 02    ld      bc,$020c    ; set counters
11B8: CD 2A 12    call    $122a       ; copy table data from #3E08 into #6687 with counters #02 and #0C

11BB: DD 21 80 66 ld      ix,software_address_of_hammer_sprite_6680    ; load IX with start of hammer array
11BF: DD 36 00 01 ld      (ix+$00),$01; set hammer 1 active
11C3: DD 36 10 01 ld      (ix+$10),$01; set hammer 2 active
11C7: 21 18 6A    ld      hl,hardware_address_of_hammer_sprite_6a18    ; set destination for hammer sprites ?
11CA: 06 02       ld      b,$02       ; set counter to 2
11CC: 11 10 00    ld      de,$0010    ; set offset to #10
11CF: CD D3 11    call    $11d3       ; draw hammers

11D2: C9          ret                 ; return

; subroutine uses HL, DE, IX
; B used for loop counter (how many times to loop before returning)
; DE used as an offset for the next set of items to copy
; used to draw hammers initially on each level that has them ?
;

11D3: DD 7E 03    ld      a,(ix+$03)  ; Load A with item's X position
11D6: 77          ld      (hl),a      ; store into HL = sprite X position
11D7: 2C          inc     l           ; next HL
11D8: DD 7E 07    ld      a,(ix+$07)  ; load A with item's sprite value
11DB: 77          ld      (hl),a      ; store into sprite value
11DC: 2C          inc     l           ; next HL
11DD: DD 7E 08    ld      a,(ix+$08)  ; load A with item color
11E0: 77          ld      (hl),a      ; store into sprite color
11E1: 2C          inc     l           ; next HL
11E2: DD 7E 05    ld      a,(ix+$05)  ; load A with Y position
11E5: 77          ld      (hl),a      ; store into sprite Y position
11E6: 2C          inc     l           ; next HL
11E7: DD 19       add     ix,de       ; add offset into IX for next set of data
11E9: 10 E8       djnz    $11d3       ; loop until B == 0

11EB: C9          ret                 ; return

; draw umbrella, etc to screen on rivets level?
; also used on elevators, called from #10C0

11EC: 7E          ld      a,(hl)      ; load A with first table data
11ED: 12          ld      (de),a      ; store into (DE) = sprite ?
11EE: 23          inc     hl          ; next table data
11EF: 1C          inc     e
11F0: 1C          inc     e           ; next sprite
11F1: 7E          ld      a,(hl)      ; load next data
11F2: 12          ld      (de),a      ; store
11F3: 23          inc     hl          ; next data
11F4: 7B          ld      a,e         ; load A with E
11F5: 81          add     a,c         ; add C (offset for next sprite) ;  EG #0E
11F6: 5F          ld      e,a         ; store into E
11F7: 10 F3       djnz    $11ec       ; loop until done

11F9: C9          ret                 ; return

;
; called from #104C for conveyors
; called from #0FF2 for girders
; draw stuff in conveyors and girders
; HL is preloaded with #3DFA for conveyors and #3DF4 for girders = table data for intial fire location
; 3DF4:  27 70 01 E0 00 00      ; initial data for fires on girders ?
; 3DFA:  7F 40 01 78 02 00      ; initial data for conveyors to release a fire ?
;

11FA: DD 21 A0 66 ld      ix,oil_can_address_66a0    ; load IX with sprite memory array for fire above the barrel
11FE: 11 28 6A    ld      de,hardware_sprite_memory_for_same_fire_6a28    ; load DE with hardware sprite memory for same fire
1201: DD 36 00 01 ld      (ix+$00),$01; enable the sprite
1205: 7E          ld      a,(hl)      ; load A with table data
1206: DD 77 03    ld      (ix+$03),a  ; store into sprite X position
1209: 12          ld      (de),a      ; store into sprite X position
120A: 1C          inc     e           ; next DE
120B: 23          inc     hl          ; next HL
120C: 7E          ld      a,(hl)      ; load A with table data
120D: DD 77 07    ld      (ix+$07),a  ; store into sprite graphic
1210: 12          ld      (de),a      ; store into sprite graphic
1211: 1C          inc     e           ; next DE
1212: 23          inc     hl          ; next HL
1213: 7E          ld      a,(hl)      ; load A with table data
1214: DD 77 08    ld      (ix+$08),a  ; store into sprite color
1217: 12          ld      (de),a      ; store into sprite color
1218: 1C          inc     e           ; next DE
1219: 23          inc     hl          ; next HL
121A: 7E          ld      a,(hl)      ; load A with table data
121B: DD 77 05    ld      (ix+$05),a  ; store into sprite Y position
121E: 12          ld      (de),a      ; store into sprite Y position
121F: 23          inc     hl          ; next HL
1220: 7E          ld      a,(hl)      ; load A with table data
1221: DD 77 09    ld      (ix+$09),a  ; store into size (width?) ???
1224: 23          inc     hl          ; next HL
1225: 7E          ld      a,(hl)      ; load A with table data
1226: DD 77 0A    ld      (ix+$0a),a  ; store into size? (height?) ??
1229: C9          ret                 ; return


; Subroutine from #10CC
; Copies Data from Table in HL into the Destination at DE in chunks of 4
; B is used for the second loop variable
; C is used to specify the difference between the tables, assumed to be 4 or 5 or 0 ?
; used for example to place the hammers ???

122A: E5          push    hl          ; Save HL
122B: C5          push    bc          ; Save BC
122C: 06 04       ld      b,$04       ; For B = 1 to 4

122E: 7E          ld      a,(hl)      ; load A with the Contents of HL table data
122F: 12          ld      (de),a      ; store data into address DE
1230: 23          inc     hl          ; next table data
1231: 1C          inc     e           ; next destination
1232: 10 FA       djnz    $122e       ; Next B

1234: C1          pop     bc          ; Restore BC - For B = 1 to Initial B value
1235: E1          pop     hl          ; Restore HL
1236: 7B          ld      a,e         ; A := E
1237: 81          add     a,c         ; add C
1238: 5F          ld      e,a         ; store result into E
1239: 10 EF       djnz    $122a       ; Loop again if not zero

123B: C9          ret                 ; Return

; set initial mario sprite position and draw remaining lives and level

123C: DF          rst     $18         ; count down WaitTimerMSB and only continue when 0
123D: 3A 27 62    ld      a,(screen_number_6227)   ; load a with screen number
1240: fe 03       cp      $03         ; is this the elevators?
1242: 01 16 E0    ld      bc,$e016    ; B := #E0, C := #16.  used for X,Y coordinates
1245: cA 4B 12    jp      z,$124b     ; if elevators skip next step

1248: 01 3F F0    ld      bc,$f03f    ; else load alternate coordinates for elevators

124B: DD 21 00 62 ld      ix,mario_array_6200    ; set IX to mario sprite array
124F: 21 4C 69    ld      hl,mario_sprite_x_position_694c    ; load HL with address for mario sprite X value
1252: DD 36 00 01 ld      (ix+$00),$01; turn on sprite
1256: DD 71 03    ld      (ix+$03),c  ; store X position
1259: 71          ld      (hl),c      ; store X position
125A: 2C          inc     l           ; next
125B: DD 36 07 80 ld      (ix+$07),$80; store sprite graphic
125F: 36 80       ld      (hl),$80    ; store sprite graphic
1261: 2C          inc     l           ; next
1262: DD 36 08 02 ld      (ix+$08),$02; store sprite color
1266: 36 02       ld      (hl),$02    ; store sprite color
1268: 2C          inc     l           ; next
1269: DD 70 05    ld      (ix+$05),b  ; store Y position
126C: 70          ld      (hl),b      ; store Y position
126D: DD 36 0F 01 ld      (ix+$0f),$01; turn this on (???)
1271: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode2 address
1274: 34          inc     (hl)        ; increase game mode2 = start game
1275: 11 01 06    ld      de,$0601    ; set task #6, parameter 1 to draw lives-1 and level
1278: CD 9F 30    call    $309f       ; insert task
127B: C9          ret                 ; return

; jump here from #0701 when GameMode2 == #D
; mario died ?

127C: CD BD 1D    call    $1dbd       ; check for bonus items and jumping scores, rivets
127F: 3A 9D 63    ld      a,(death_indicator_639d)   ; load A with this normally 0.  1 while mario dying, 2 when dead
1282: EF          rst     $28         ; jump based on A

1283  8B 12                             ; #128B         ; 0 normal
1285  AC 12                             ; #12AC         ; 1 mario dying
1287  DE 12                             ; #12DE         ; 2 mario dead
1289  00 00                             ; unused ?

128B: DF          rst     $18         ; count down WaitTimerMSB and only continue when 0
128C: 21 4D 69    ld      hl,mario_sprite_value_694d    ; load HL with mario sprite value
128F: 3E F0       ld      a,$f0       ; A := #F0
1291: CB 16       rl      (hl)        ; rotate left (HL)
1293: 1F          rra                 ; rotate right that carry bit into A
1294: 77          ld      (hl),a      ; store result into mario sprite
1295: 21 9D 63    ld      hl,death_indicator_639d    ; load HL with mario death indicator
1298: 34          inc     (hl)        ; increase.  mario is now dying
1299: 3E 0D       ld      a,$0d       ; A := #D (13 decimal)
129B: 32 9E 63    ld      (load_counter_639e),a   ; store into counter for number of times to rotate mario (?)
129E: 3E 08       ld      a,$08       ; load A with 8 frames of delay
12A0: 32 09 60    ld      (waittimermsb_6009),a; store into timer for sound delay
12A3: CD BD 30    call    $30bd       ; clear sprites ?
12A6: 3E 03       ld      a,$03       ; load A with duration of sound
12A8: 32 88 60    ld      (play_death_sound_6088),a   ; play death sound
12AB: C9          ret                 ; return

; arrive here when mario dies
; animates mario

12AC: DF          rst     $18         ; count down WaitTimerMSB and only continue when 0
12AD: 3E 08       ld      a,$08       ; load A with 8 frames of delay
12AF: 32 09 60    ld      (waittimermsb_6009),a; store into timer for sound delays
12B2: 21 9E 63    ld      hl,load_counter_639e    ; load counter
12B5: 35          dec     (hl)        ; decrease.  are we done ?
12B6: CA CB 12    jp      z,$12cb     ; yes, skip ahead

12B9: 21 4D 69    ld      hl,mario_sprite_value_694d    ; load HL with mario sprite value
12BC: 7E          ld      a,(hl)      ; get the value
12BD: 1F          rra                 ; roll right = div 2
12BE: 3E 02       ld      a,$02       ; load A with 2
12C0: 1F          rra                 ; roll right , A now has 1
12C1: 47          ld      b,a         ; copy to B
12C2: AE          xor     (hl)        ; toggle HL rightmost bit
12C3: 77          ld      (hl),a      ; save new sprite value
12C4: 2C          inc     l           ; next HL
12C5: 78          ld      a,b         ; load A with B
12C6: E6 80       and     $80         ; apply mask
12C8: AE          xor     (hl)        ; toggle HL
12C9: 77          ld      (hl),a      ; save new value
12CA: C9          ret                 ; return

; mario done rotating after death

12CB: 21 4D 69    ld      hl,mario_sprite_value_694d    ; load HL with mario sprite value
12CE: 3E F4       ld      a,$f4       ; load A with #F4
12D0: CB 16       rl      (hl)        ; rotate left HL (goes from F8 to F0)
12D2: 1F          rra                 ; roll right A.  A becomes FA
12D3: 77          ld      (hl),a      ; store into sprite value (mario dead)
12D4: 21 9D 63    ld      hl,death_indicator_639d    ; load HL with death indicator
12D7: 34          inc     (hl)        ; increase.  mario now dead
12D8: 3E 80       ld      a,$80       ; load A with delay of 80
12DA: 32 09 60    ld      (waittimermsb_6009),a; store into sound delay counter
12DD: C9          ret                 ; return

; mario is completely dead

12DE: DF          rst     $18         ; count down WaitTimerMSB and only continue when 0
12DF: CD DB 30    call    $30db       ; clear mario and elevator sprites from screen
12E2: 21 0A 60    ld      hl,gamemode2_600a; set HL to game mode2
12E5: 3A 0E 60    ld      a,(playerturnb_600e) ; load A with current player
12E8: A7          and     a           ; is this player 1 ?
12E9: CA ED 12    jp      z,$12ed     ; yes, skip next step

12EC: 34          inc     (hl)        ; increase game mode

12ED: 34          inc     (hl)        ; increase game mode
12EE: 2B          dec     hl          ; load HL with WaitTimerMSB
12EF: 36 01       ld      (hl),$01    ; store 1 into timer
12F1: C9          ret                 ; return

; jump here from #0701
; player 1 died
; clear sounds, decrease life, check for and handle game over

12F2: CD 1C 01    call    $011c       ; clear all sounds
12F5: AF          xor     a           ; A := 0
12F6: 32 2C 62    ld      (game_start_flag_622c),a   ; store into game start flag
12F9: 21 28 62    ld      hl,number_of_lives_remaining_6228    ; load HL with address for number of lives remaining
12FC: 35          dec     (hl)        ; one less life
12FD: 7E          ld      a,(hl)      ; load A with number of lives left
12FE: 11 40 60    ld      de,p1numlives_6040; set destination address
1301: 01 08 00    ld      bc,$0008    ; set counter
1304: ED B0       ldir                ; copy (#6228) to (#6230) into (P1NumLives) to (P2NumLives).  copies data from player area to storage area for player 1
1306: A7          and     a           ; number of lives == 0 ?
1307: C2 34 13    jp      nz,$1334    ; no, skip ahead

; game over for this player [?]

130A: 3E 01       ld      a,$01       ; A := 1
130C: 21 B2 60    ld      hl,player_1_score_address_60b2    ; load HL with player 1 score address
130F: CD CA 13    call    $13ca       ; check for high score entry ???
1312: 21 D4 76    ld      hl,$76d4    ; load HL with screen VRAM address ???
1315: 3A 0F 60    ld      a,(twoplayergame_600f) ; load A with number of players
1318: A7          and     a           ; 1 player game?
1319: 28 07       jr      z,$1322     ; yes, skip next 3 steps

131B: 11 02 03    ld      de,$0302    ; load task data for text #2 "PLAYER <I>"
131E: CD 9F 30    call    $309f       ; insert task to draw text
1321: 2B          dec     hl          ; HL := #76D3

1322: CD 26 18    call    $1826       ; clear an area of the screen
1325: 11 00 03    ld      de,$0300    ; load task data for text #0 "GAME OVER"
1328: CD 9F 30    call    $309f       ; insert task to draw text
132B: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer
132E: 36 C0       ld      (hl),$c0    ; set timer to #C0
1330: 23          inc     hl          ; HL := GameMode2
1331: 36 10       ld      (hl),$10    ; set game mode2 to #10
1333: C9          ret                 ; return

1334: 0E 08       ld      c,$08       ; C := 8
1336: 3A 0F 60    ld      a,(twoplayergame_600f) ; load A with number of players
1339: A7          and     a           ; 1 player game?
133A: CA 3F 13    jp      z,$133f     ; yes, skip next step

133D: 0E 17       ld      c,$17       ; C := #17

133F: 79          ld      a,c         ; A := C
1340: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2
1343: C9          ret                 ; return

; arrive from #0701 when GameMode2 == #F
; clear sounds, clear game start flag, draw game over if needed, set game mode2 accordingly

1344: CD 1C 01    call    $011c       ; clear all sounds
1347: AF          xor     a           ; A := 0
1348: 32 2C 62    ld      (game_start_flag_622c),a   ; store into game start flag
134B: 21 28 62    ld      hl,number_of_lives_remaining_6228    ; load HL with number of lives remaining
134E: 35          dec     (hl)        ; decrease
134F: 7E          ld      a,(hl)      ; load A with the number of lives remaining
1350: 11 48 60    ld      de,p2numlives_6048; load DE with destination address
1353: 01 08 00    ld      bc,$0008    ; set counter to 8
1356: ED B0       ldir                ; copy
1358: A7          and     a           ; any lives left?
1359: C2 7F 13    jp      nz,$137f    ; yes, skip ahead

; game over

135C: 3E 03       ld      a,$03       ; A := 3
135E: 21 B5 60    ld      hl,player_2_score_address_60b5    ; load HL with player 2 score address
1361: CD CA 13    call    $13ca       ; check for high score entry ???
1364: 11 03 03    ld      de,$0303    ; load task data for text #3 "PLAYER <II>"
1367: CD 9F 30    call    $309f       ; insert task to draw text
136A: 11 00 03    ld      de,$0300    ; load task data for text #0 "GAME OVER"
136D: CD 9F 30    call    $309f       ; insert task to draw text
1370: 21 D3 76    ld      hl,$76d3    ; load HL with screen address ???
1373: CD 26 18    call    $1826       ; clear an area of the screen
1376: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer
1379: 36 C0       ld      (hl),$c0    ; set timer to #C0
137B: 23          inc     hl          ; HL := GameMode2
137C: 36 11       ld      (hl),$11    ; set game mode2 to #11
137E: C9          ret                 ; return

137F: 0E 17       ld      c,$17       ; C := #17
1381: 3A 40 60    ld      a,(p1numlives_6040) ; load A with number of lives left for player 1
1384: A7          and     a           ; player 1 has lives remaining?
1385: C2 8A 13    jp      nz,$138a    ; yes, skip next step

1388: 0E 08       ld      c,$08       ; C := 8

138A: 79          ld      a,c         ; A := C
138B: 32 0A 60    ld      (gamemode2_600a),a; store A into game mode2
138E: C9          ret                 ; return

; arrive from #0701 when GameMode2 == #10
; when 2 player game has ended

138F: DF          rst     $18         ; count down timer and only continue here if zero, else RET
1390: 0E 17       ld      c,$17       ; C := #17
1392: 3A 48 60    ld      a,(p2numlives_6048) ; load A with number of lives for player 2

1395: 34          inc     (hl)        ; increase timer ??? [EG HL = WaitTimerMSB]
1396: A7          and     a           ; player has lives remaining ?
1397: C2 9C 13    jp      nz,$139c    ; yes, skip next step

139A: 0E 14       ld      c,$14       ; else C := #14

139C: 79          ld      a,c         ; A := C
139D: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2
13A0: C9          ret                 ; return


; arrive from #0701 when GameMode2 == #11

13A1: DF          rst     $18         ; count down timer and only continue here if zero, else RET
13A2: 0E 17       ld      c,$17       ; C := #17
13A4: 3A 40 60    ld      a,(p1numlives_6040) ; load A with number of lives remaining for player1
13A7: C3 95 13    jp      $1395       ; jump back, rest of this sub is above


; arrive from #0701 when GameMode2 == 12
; flip screen if needed, reset game mode2 to zero, set player 2

13AA: 3A 26 60    ld      a,(uprightcab_6026) ; load A with upright/cocktail
13AD: 32 82 7D    ld      (reg_flipscreen),a; store into hardware screen flip
13B0: AF          xor     a           ; A := 0
13B1: 32 0A 60    ld      (gamemode2_600a),a; set game mode2 to 0
13B4: 21 01 01    ld      hl,$0101    ; HL := #101
13B7: 22 0D 60    ld      (playerturna_600d),hl; store 1 into PlayerTurnA (set player2) and PlayerTurnB (set player2)
13BA: C9          ret                 ; return

; arrive from #0701 when GameMode2 == 13
; set player 1, reset game mode2 to zero, set screen flip to not flipped

13BB: AF          xor     a           ; A := 0
13BC: 32 0D 60    ld      (playerturna_600d),a; set for player 1
13BF: 32 0E 60    ld      (playerturnb_600e),a; store into current player number 1
13C2: 32 0A 60    ld      (gamemode2_600a),a; set game mode2 to 0
13C5: 3C          inc     a           ; A := 1
13C6: 32 82 7D    ld      (reg_flipscreen),a; store into screen flip for no flipping
13C9: C9          ret                 ; return

; causes the player's score to percolate up the high score list
; [but it is never read from ???]

; called from #1361, HL is preloaded with #60B5 = player 2 score address, A is preloaded with 3
; called from #130F, HL is preloaded with #60B2 = player 1 score address, A is preloaded with 1

; this sub copies player score into #61C7-#61C9
; then it breaks the score into component digits and stores them into #61B1 through #61B6
; then it sets #61B7 through #61C4 to #10 (???)
;

13CA: 11 C6 61    ld      de,address_for_unknown_61c6    ; load DE with address for ???
13CD: 12          ld      (de),a      ; store A into it
13CE: CF          rst     $8          ; continue if there are credits or the game is being played, else RET

13CF: 13          inc     de          ; DE := #61C7
13D0: 01 03 00    ld      bc,$0003    ; set counter to 3
13D3: ED B0       ldir                ; copy players score into this area
13D5: 06 03       ld      b,$03       ; for B = 1 to 3
13D7: 21 B1 61    ld      hl,score_and_name_line_61b1    ; load HL with ???

13DA: 1B          dec     de          ; count down DE.  first time it has #61C9 after the DEC
13DB: 1A          ld      a,(de)      ; load A with this
13DC: 0F          rrca
13DD: 0F          rrca
13DE: 0F          rrca
13DF: 0F          rrca                ; rotate right 4 times.  this transposes the 4 low and 4 high bits of the byte
13E0: E6 0F       and     $0f         ; mask bits, now between 0 and #F.  this will give the thousands of the score on the 2nd loop.
13E2: 77          ld      (hl),a      ; store into (HL) ???
13E3: 23          inc     hl          ; next
13E4: 1A          ld      a,(de)      ; load A with this
13E5: E6 0F       and     $0f         ; mask bits.  this will give the hundreds of the score on the 2nd loop
13E7: 77          ld      (hl),a      ; store into (HL)
13E8: 23          inc     hl          ; next
13E9: 10 EF       djnz    $13da       ; next B

; sets #61B7 through #61C4 to #10 (???)

13EB: 06 0E       ld      b,$0e       ; for B = 1 to #E

13ED: 36 10       ld      (hl),$10    ; store #10 into memory at (HL)
13EF: 23          inc     hl          ; next HL
13F0: 10 FB       djnz    $13ed       ; next B

;

13F2: 36 3F       ld      (hl),$3f    ; store #3F into #61C5 = end code ?

13F4: 06 05       ld      b,$05       ; for B = 1 to 5.  Do for each high score in top 5
13F6: 21 A5 61    ld      hl,lowest_high_score_address_61a5    ; load HL with lowest high score address
13F9: 11 C7 61    ld      de,copy_of_player_score_61c7    ; load DE with copy of player score

13FC: 1A          ld      a,(de)      ; load A with a digit of player's score
13FD: 96          sub     (hl)        ; subtract next lowest high score
13FE: 23          inc     hl          ; next
13FF: 13          inc     de          ; next
1400: 1A          ld      a,(de)      ; load A with next digit of player's score
1401: 9E          sbc     a,(hl)      ; subtract with carry next lowest high score
1402: 23          inc     hl          ; next
1403: 13          inc     de          ; next
1404: 1A          ld      a,(de)      ; load A with next digit of player's score
1405: 9E          sbc     a,(hl)      ; subtract with carry next lowest high score
1406: D8          ret     c           ; if player has not made this high score, return

; player has made a high score for entry in top 5

1407: C5          push    bc          ; else save BC

1408: 06 19       ld      b,#$19           ; for B = 1 to #19 (jotd: value was wrong: 19 in decimal!)

        ; exchange the values in (HL) and (DE) for #19 bytes
        ; this causes the high score to percolate up the high score list

140A: 4E          ld      c,(hl)          ; C := (HL)
140B: 1A          ld      a,(de)          ; A := (DE)
140C: 77          ld      (hl),a          ; (HL) := A
140D: 79          ld      a,c             ; A := C
140E: 12          ld      (de),a          ; (DE) := A
140F: 2B          dec     hl              ; next HL
1410: 1B          dec     de              ; next DE
1411: 10 F7       djnz    #140A           ; Next B

1413: 01 F5 FF    ld      bc,$fff5    ; load BC with -#A
1416: 09          add     hl,bc       ; add to HL.  HL now has #A less than before
1417: EB          ex      de,hl       ; DE <> HL
1418: 09          add     hl,bc       ; add to HL, now has #A less than before
1419: EB          ex      de,hl       ; DE <> HL
141A: C1          pop     bc          ; restore BC
141B: 10 DF       djnz    $13fc       ; Next B

141D: C9          ret                 ; return

; jump here from #0701 when GameMode2 == #14 (game is over)
; draw credits on screen, clears screen and sprites, checks for high score, flips screen if necessary

141E: CD 16 06    call    $0616       ; draw credits on screen
1421: DF          rst     $18         ; count down timer and only continue here if zero, else RET

1422: CD 74 08    call    $0874       ; clears the screen and sprites
1425: 3E 00       ld      a,$00       ; A := 0
1427: 32 0E 60    ld      (playerturnb_600e),a; set player number 1
142A: 32 0D 60    ld      (playerturna_600d),a; set player1
142D: 21 1C 61    ld      hl,address_of_high_score_indicator_611c    ; load HL with high score entry indicator
1430: 11 22 00    ld      de,$0022    ; offset to add is #22
1433: 06 05       ld      b,$05       ; for B = 1 to 5
1435: 3E 01       ld      a,$01       ; A := 1 = code for a new high score for player 1

1437: BE          cp      (hl)        ; compare (HL) to 1 .  equal ?
1438: CA 59 14    jp      z,$1459     ; yes, jump to high score entry for player 1

143B: 19          add     hl,de       ; else next HL
143C: 10 F9       djnz    $1437       ; next B

143E: 21 1C 61    ld      hl,address_of_high_score_indicator_611c    ; load HL with high score entry indicator
1441: 06 05       ld      b,$05       ; For B = 1 to 5
1443: 3E 03       ld      a,$03       ; A := 3 = code for a new high score for player 2

1445: BE          cp      (hl)        ; compare.  same?
1446: CA 4F 14    jp      z,$144f     ; yes, skip ahead and being high score entry for pl2

1449: 19          add     hl,de       ; add offset for next
144A: 10 F9       djnz    $1445       ; Next B

144C: C3 75 14    jp      $1475       ; skip ahead, no high score was achieved

; high score achieved ?

144F: 3E 01       ld      a,$01       ; A := 1
1451: 32 0E 60    ld      (playerturnb_600e),a; set player #2
1454: 32 0D 60    ld      (playerturna_600d),a; set player2
1457: 3E 00       ld      a,$00       ; A := 0

1459: 21 26 60    ld      hl,uprightcab_6026; load HL with address for upright/cocktail
145C: B6          or      (hl)        ; mix with A
145D: 32 82 7D    ld      (reg_flipscreen),a; store A into screen flip setting
1460: 3E 00       ld      a,$00       ; A := 0
1462: 32 09 60    ld      (waittimermsb_6009),a; clear timer
1465: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode2 address
1468: 34          inc     (hl)        ; increase game mode2 to #15
1469: 11 0D 03    ld      de,$030d    ; load task data for text #D "NAME REGISTRATION"
146C: 06 0C       ld      b,$0c       ; set counter for #0C items (12 decimal)

146E: CD 9F 30    call    $309f       ; insert task to draw text
1471: 13          inc     de          ; next text set
1472: 10 FA       djnz    $146e       ; next B

1474: C9          ret                 ; return

; jump here from #144C

1475: 3E 01       ld      a,$01       ; A := 1
1477: 32 82 7D    ld      (reg_flipscreen),a; set screen flip setting
147A: 32 05 60    ld      (gamemode1_6005),a; store into game mode1
147D: 32 07 60    ld      (nocredits_6007),a; set indicator for no credits
1480: 3E 00       ld      a,$00       ; A := 0
1482: 32 0A 60    ld      (gamemode2_600a),a; reset game mode2 to 0.  game is now totally over.
1485: C9          ret                 ; return


; jump from #0701 when GameMode2 == #15
; game is over - high score entry


1486: CD 16 06    call    $0616       ; draw credits on screen
1489: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer
148C: 7E          ld      a,(hl)      ; load A with timer value
148D: A7          and     a           ; == 0 ?
148E: C2 DC 14    jp      nz,$14dc    ; no, skip ahead

1491: 32 86 7D    ld      (reg_palette_a),a; set palette bank selector
1494: 32 87 7D    ld      (reg_palette_b),a; set palette bank selector
1497: 36 01       ld      (hl),$01    ; set timer to 1
1499: 21 30 60    ld      hl,hscursordelay_6030; load HL with HSCursorDelay
149C: 36 0A       ld      (hl),$0a
149E: 23          inc     hl          ; HL := HSBlinkToggle
149F: 36 00       ld      (hl),$00
14A1: 23          inc     hl          ; HL := HSBlinkTimer
14A2: 36 10       ld      (hl),$10
14A4: 23          inc     hl          ; HL := HSRegiTime
14A5: 36 1E       ld      (hl),$1e
14A7: 23          inc     hl          ; HL := HSTimer
14A8: 36 3E       ld      (hl),$3e    ; set outer loop timer
14AA: 23          inc     hl          ; HL := HSCursorPos
14AB: 36 00       ld      (hl),$00    ; set high score digit selected
14AD: 21 E8 75    ld      hl,$75e8    ; load HL with screen position for first player initial
14B0: 22 36 60    ld      (hsinitialpos_6036),hl; save into this indicator
14B3: 21 1C 61    ld      hl,address_of_high_score_indicator_611c    ; load HL with address of high score indicator
14B6: 3A 0E 60    ld      a,(playerturnb_600e) ; load A with current player number
14B9: 07          rlca                ; rotate left
14BA: 3C          inc     a           ; increase
14BB: 4F          ld      c,a         ; copy to C.  C now has 1 for player 1, 3 for player 2
14BC: 11 22 00    ld      de,$0022    ; load DE with offset
14BF: 06 04       ld      b,$04       ; for B = 1 to 4

14C1: 7E          ld      a,(hl)      ; load A with high score indicator
14C2: B9          cp      c           ; == current player number ?
14C3: CA C9 14    jp      z,$14c9     ; yes, skip next 2 steps - this is the one

14C6: 19          add     hl,de       ; add offset for next HL
14C7: 10 F8       djnz    $14c1       ; Next B

14C9: 22 38 60    ld      (highscore_entry_address_6038),hl; store HL into Unk6038
14CC: 11 F3 FF    ld      de,$fff3    ; load DE with offset of -#13
14CF: 19          add     hl,de       ; add offset
14D0: 22 3A 60    ld      (unknown_ram_address_603a),hl  ; store result into ???
14D3: 06 00       ld      b,$00       ; B := 0
14D5: 3A 35 60    ld      a,(hscursorpos_6035) ; load A with high score entry digit selected
14D8: 4F          ld      c,a         ; copy to C
14D9: CD FA 15    call    $15fa       ; ???

14DC: 21 34 60    ld      hl,hstimer_6034  ; load HL with outer loop timer
14DF: 35          dec     (hl)        ; count down timer.  at zero?
14E0: C2 FC 14    jp      nz,$14fc    ; no, skip ahead

14E3: 36 3E       ld      (hl),$3e    ; reset outer loop timer
14E5: 2B          dec     hl          ; HL := HSRegiTime
14E6: 35          dec     (hl)        ; decrease.  at zero?
14E7: CA C6 15    jp      z,$15c6     ; yes, skip ahead to handle

14EA: 7E          ld      a,(hl)      ; else load A with time remaining
14EB: 06 FF       ld      b,$ff       ; B := #FF.  used to count 10's

14ED: 04          inc     b           ; increase B
14EE: D6 0A       sub     $0a         ; subtract #0A (10 decimal).  gone under?
14F0: D2 ED 14    jp      nc,$14ed    ; no, loop again.  B will have number of 10's

14F3: C6 0A       add     a,$0a       ; add #0A to make between 0 and 9
14F5: 32 52 75    ld      ($7552),a   ; draw digit to screen
14F8: 78          ld      a,b         ; A := B = 10's of time left
14F9: 32 72 75    ld      ($7572),a   ; draw digit to screen

14FC: 21 30 60    ld      hl,hscursordelay_6030; load HL with HSCursorDelay
14FF: 46          ld      b,(hl)      ; load B with the value
1500: 36 0A       ld      (hl),$0a    ; store #A into it
1502: 3A 10 60    ld      a,(inputstate_6010) ; load A with input
1505: CB 7F       bit     7,a         ; is jump button pressed?
1507: C2 46 15    jp      nz,$1546    ; yes, skip ahead

150A: E6 03       and     $03         ; mask bits.  check for a left or right direction pressed
150C: C2 14 15    jp      nz,$1514    ; if direction, skip next 3 steps

150F: 3C          inc     a           ; else increase A
1510: 77          ld      (hl),a      ; store into HSCursorDelay
1511: C3 8A 15    jp      $158a       ; skip ahead

; left or right pressed while in high score entry

1514: 05          dec     b           ; decrease B.  at zero?
1515: CA 1D 15    jp      z,$151d     ; yes, skip next 3 steps

1518: 78          ld      a,b         ; A := B
1519: 77          ld      (hl),a      ; store into ???
151A: C3 8A 15    jp      $158a       ; skip ahead

151D: CB 4F       bit     1,a         ; is direction == left ?
151F: C2 39 15    jp      nz,$1539    ; yes, skip ahead

1522: 3A 35 60    ld      a,(hscursorpos_6035) ; load A with high score entry digit selected
1525: 3C          inc     a           ; increase
1526: FE 1E       cp      $1e         ; == #1E ?  (have we gone past END ?)
1528: C2 2D 15    jp      nz,$152d    ; no, skip next step

152B: 3E 00       ld      a,$00       ; A := 0 [why this way and not XOR A ?] - reset this counter to "A" in the table

152D: 32 35 60    ld      (hscursorpos_6035),a; store into high score entry digit selected
1530: 4F          ld      c,a         ; C := A
1531: 06 00       ld      b,$00       ; B := 0
1533: CD FA 15    call    $15fa       ; ???
1536: C3 8A 15    jp      $158a       ; skip ahead

1539: 3A 35 60    ld      a,(hscursorpos_6035) ; load A with high score entry digit selected
153C: D6 01       sub     $01         ; decrease [why written this way?  DEC A is standard...]
153E: F2 2D 15    jp      p,$152d     ; if sign positive, loop again

1541: 3E 1D       ld      a,$1d       ; A := #1D
1543: C3 2D 15    jp      $152d       ; jump back

; jump pressed in high score entry

1546: 3A 35 60    ld      a,(hscursorpos_6035) ; load A with high score entry digit selected
1549: FE 1C       cp      $1c         ; == #1C ? = code for backspace ?
154B: CA 6D 15    jp      z,$156d     ; yes, skip ahead to handle

154E: FE 1D       cp      $1d         ; == #1D ? = code for END
1550: CA C6 15    jp      z,$15c6     ; yes, skip ahead to hanlde

1553: 2A 36 60    ld      hl,(hsinitialpos_6036) ; else load HL with VRAM address of the initial being entered
1556: 01 88 75    ld      bc,$7588    ; load BC with screen address
1559: A7          and     a           ; clear carry flag
155A: ED 42       sbc     hl,bc       ; subtract.  equal?
155C: CA 8A 15    jp      z,$158a     ; yes, skip ahead

155F: 09          add     hl,bc       ; else add it back
1560: C6 11       add     a,$11       ; add ascii offset of #11 to A
1562: 77          ld      (hl),a      ; write letter to screen
1563: 01 E0 FF    ld      bc,$ffe0    ; load BC with offset for next column
1566: 09          add     hl,bc       ; set HL to next column

1567: 22 36 60    ld      (hsinitialpos_6036),hl; store HL back into VRAM address of the initial being entered
156A: C3 8A 15    jp      $158a       ; skip ahead

; backspace selected in high score entry

156D: 2A 36 60    ld      hl,(hsinitialpos_6036) ; else load HL with VRAM address of the initial being entered
1570: 01 20 00    ld      bc,$0020    ; load offset of #20
1573: 09          add     hl,bc       ; add offset
1574: A7          and     a           ; clear carry flag
1575: 01 08 76    ld      bc,$7608    ; load BC with screen address
1578: ED 42       sbc     hl,bc       ; subtract.  equal?
157A: C2 86 15    jp      nz,$1586    ; no, skip ahead

157D: 21 E8 75    ld      hl,$75e8    ; else load HL with other screen address

1580: 3E 10       ld      a,$10       ; A := #10 = blank code
1582: 77          ld      (hl),a      ; clear the screen at this position
1583: C3 67 15    jp      $1567       ; jump back

1586: 09          add     hl,bc       ; restore HL back to what it was
1587: C3 80 15    jp      $1580       ; jump back

; jump here from #156A and #155C and #1536 and #151A and #1511

158A: 21 32 60    ld      hl,hsblinktimer_6032; load HL with HSBlinkTimer
158D: 35          dec     (hl)        ; decrease.  at zero ?
158E: C2 F9 15    jp      nz,$15f9    ; no, jump to RET. [RET NZ would be faster and more compact]

; Blink the high score in high score table
1591: 3A 31 60    ld      a,(hsblinktoggle_6031)
1594: A7          and     a           ; Is HSBlinkToggle zero?
1595: C2 B8 15    jp      nz,$15b8    ; no, skip ahead

1598: 3E 01       ld      a,$01       ; A := 1
159A: 32 31 60    ld      (hsblinktoggle_6031),a; store into HSBlinkToggle
159D: 11 BF 01    ld      de,$01bf

15A0: FD 2A 38 60 ld      iy,(highscore_entry_address_6038) ; load IY with Unk6038
15A4: FD 6E 04    ld      l,(iy+$04)
15A7: FD 66 05    ld      h,(iy+$05)
15AA: E5          push    hl
15AB: DD E1       pop     ix          ; load IX with HL
15AD: CD 7C 05    call    $057c       ; ???
15B0: 3E 10       ld      a,$10       ; A := #10
15B2: 32 32 60    ld      (hsblinktimer_6032),a; store into HSBlinkTimer
15B5: C3 F9 15    jp      $15f9       ; jump to RET [RET would be faster and more compact]

15B8: AF          xor     a           ; A := 0
15B9: 32 31 60    ld      (hsblinktoggle_6031),a; store into HSBlinkToggle
15BC: ED 5B 38 60 ld      de,(highscore_entry_address_6038)
15C0: 13          inc     de
15C1: 13          inc     de
15C2: 13          inc     de
15C3: C3 A0 15    jp      $15a0       ; jump back

; arrive here from #14E7
; high score entry complete ???

15C6: ED 5B 38 60 ld      de,(highscore_entry_address_6038) ; load DE with address of high score entry indicator
15CA: AF          xor     a           ; A := 0
15CB: 12          ld      (de),a      ; store.  this clears the high score indicator
15CC: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer
15CF: 36 80       ld      (hl),$80    ; set time to #80
15D1: 23          inc     hl          ; HL := GameMode2
15D2: 35          dec     (hl)        ; decrease game mode2
15D3: 06 0C       ld      b,$0c       ; for B = 1 to #C (12 decimal)
15D5: 21 E8 75    ld      hl,$75e8    ; load HL with screen vram address
15D8: FD 2A 3A 60 ld      iy,(unknown_ram_address_603a)  ; load IY with ???
15DC: 11 E0 FF    ld      de,$ffe0    ; load DE with offset of -#20

15DF: 7E          ld      a,(hl)      ; load A with
15E0: FD 77 00    ld      (iy+$00),a  ; store
15E3: FD 23       inc     iy          ; next
15E5: 19          add     hl,de       ; add offset
15E6: 10 F7       djnz    $15df       ; next B

15E8: 06 05       ld      b,$05       ; For B = 1 to 5
15EA: 11 14 03    ld      de,$0314    ; load task data for text #14 - start of high score table

15ED: CD 9F 30    call    $309f       ; insert task to draw text
15F0: 13          inc     de          ; next high score
15F1: 10 FA       djnz    $15ed       ; next B

15F3: 11 1A 03    ld      de,$031a    ; load task data for text #1A - "YOUR NAME WAS REGISTERED"
15F6: CD 9F 30    call    $309f       ; insert task to draw text
15F9: C9          ret                 ; return

; sets the sprite to the square selector for intials entry
; called from #14D9 and #1533

15FA: D5          push    de          ; save DE
15FB: E5          push    hl          ; save HL
15FC: CB 21       sla     c
15FE: 21 0F 36    ld      hl,$360f    ; start of table data
1601: 09          add     hl,bc
1602: EB          ex      de,hl
1603: 21 74 69    ld      hl,unknown_6974
1606: 1A          ld      a,(de)      ; load A with table data
1607: 13          inc     de          ; next table entry
1608: 77          ld      (hl),a      ; store
1609: 23          inc     hl          ; next location
160A: 36 72       ld      (hl),$72
160C: 23          inc     hl
160D: 36 0C       ld      (hl),$0c
160F: 23          inc     hl
1610: 1A          ld      a,(de)
1611: 77          ld      (hl),a
1612: E1          pop     hl          ; restore HL
1613: D1          pop     de          ; restore DE
1614: C9          ret                 ; return

; arrive when GameMode2 == #16 (level completed).  called from #0701

1615: CD BD 30    call    $30bd       ; clear sprites
1618: 3A 27 62    ld      a,(screen_number_6227)   ; load a with screen number
161B: 0F          rrca                ; roll right with carry.  is this the rivets or the conveyors?
161C: d2 2f 16    jp      nc,$162f    ; yes, skip ahead to #162F

                                        ; handle for girders or elevators, they are same here

161F: 3A 88 63    ld      a,(end_of_level_counter_6388)   ; load A with this counter usually zero, counts from 1 to 5 when the level is complete
1622: EF          rst     $28         ; jump based on A

1623  54 16                             ; #1654         ; 0
1625  70 16                             ; #1670         ; 1
1627  8A 16                             ; #168A         ; 2
1629  32 17                             ; #1732         ; 3
162B  57 17                             ; #1757         ; 4
162D  8E 17                             ; #178E         ; 5

162F: 0F          rrca                ; roll right again.  is this the rivets ?
1630: D2 41 16    jp      nc,$1641    ; yes, skip ahead

; else the conveyors

1633: 3A 88 63    ld      a,(end_of_level_counter_6388)   ; load A with this usually zero, counts from 1 to 5 when the level is complete
1636: EF          rst     $28         ; jump based on A

1637  A3 16                             ; #16A3         ; 0
1639  BB 16                             ; #16BB         ; 1
163B  32 17                             ; #1732         ; 2
163D  57 17                             ; #1757         ; 3
163F  8E 17                             ; #178E         ; 4

; rivets

1641: CD BD 1D    call    $1dbd       ; check for bonus items and jumping scores, rivets
1644: 3A 88 63    ld      a,(end_of_level_counter_6388)   ; load A with usually zero, counts from 1 to 5 when the level is complete

1647: EF          rst     $28         ; jump based on A

1648  B6 17                             ; #17B6         ; 0
164A  69 30                             ; #3069         ; 1
164C  39 18                             ; #1839         ; 2
164E  6F 18                             ; #186F         ; 3
1650  80 18                             ; #1880         ; 4
1652  C6 18                             ; #18C6         ; 5

; jump here from #1622 when girders or elevators is finished.  step 1 of 6

1654: CD 08 17    call    $1708       ; clear all sounds, draw heart sprite, redraw girl sprite, clear "help", play end of level sound
1657: 21 5C 38    ld      hl,$385c    ; load HL with start of kong graphic table data
165A: CD 4E 00    call    $004e       ; update kong's sprites
165D: 3E 20       ld      a,$20       ; A := #20
165F: 32 09 60    ld      (waittimermsb_6009),a; set timer to #20

1662: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
1665: 34          inc     (hl)        ; increase counter
1666: 3E 01       ld      a,$01       ; A := 1 = code for girders
1668: F7          rst     $30         ; if girders, continue below.  else RET

1669: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of kong sprite
166C: 0E FC       ld      c,$fc       ; set movement for -4 pixels
166E: FF          rst     $38         ; move kong
166F: C9          ret                 ; return

; jump here from #1622 when girders or elevators is finished.  step 2 of 6

1670: DF          rst     $18         ; count down timer and only continue here if zero, else RET
1671: 21 32 39    ld      hl,$3932    ; load HL with start of kong's sprites table data
1674: CD 4E 00    call    $004e       ; update kong's sprites
1677: 3E 20       ld      a,$20       ; A := #20
1679: 32 09 60    ld      (waittimermsb_6009),a; set timer to #20
167C: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
167F: 34          inc     (hl)        ; increase counter
1680: 3E 04       ld      a,$04       ; A := 4 = 100 code for elevators
1682: F7          rst     $30         ; only continue here if elevators, else RET

1683: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite
1686: 0E 04       ld      c,$04       ; set to move by 4
1688: FF          rst     $38         ; move kong by +4
1689: C9          ret                 ; return

; jump here from #1622 when girders or elevators is finished.  step 3 of 6

168A: DF          rst     $18         ; count down timer and only continue here if zero, else RET
168B: 21 8C 38    ld      hl,$388c    ; load HL with start of table data for kong
168E: CD 4E 00    call    $004e       ; update kong's sprites
1691: 3E 66       ld      a,$66       ; A := #66
1693: 32 0C 69    ld      (clear_kongs_top_right_sprite_690c),a   ; store into kong's right arm sprite
1696: AF          xor     a           ; A := 0
1697: 32 24 69    ld      (kongs_right_arm_sprite_for_carrying_girl_6924),a   ; clear the other side of kongs arm
169A: 32 2C 69    ld      (girl_being_carried_sprite_692c),a   ; clear the girl sprite that kong is carrying
169D: 32 AF 62    ld      (kong_misc_counter_62af),a   ; clear the kong climbing counter
16A0: C3 62 16    jp      $1662       ; jump back

; jump here from #1622 when conveyors is finished.  step 1 of 5

16A3: CD 08 17    call    $1708       ; clear all sounds, draw heart sprite, redraw girl sprite, clear "help", play end of level sound
16A6: 3A 10 69    ld      a,(kongs_x_position_6910)   ; load A with kong's X position
16A9: D6 3B       sub     $3b         ; subtract #3B
16AB: 21 5C 38    ld      hl,$385c    ; load HL with kong graphic table data
16AE: CD 4E 00    call    $004e       ; update kong's sprites to default kong graphic
16B1: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of Kong sprite
16B4: 4F          ld      c,a         ; load C with offset computed above to move kong back where he was
16B5: FF          rst     $38         ; move Kong
16B6: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
16B9: 34          inc     (hl)        ; increase counter
16BA: C9          ret                 ; return

; jump here from #1622 when conveyors is finished.  step 2 of 5

16BB: AF          xor     a           ; A := 0
16BC: 32 A0 62    ld      (top_conveyor_counter_62a0),a   ; clear top conveyor counter
16BF: 3A A3 63    ld      a,(top_conveyor_direction_vector_63a3)   ; load A with direction vector for top conveyor
16C2: 4F          ld      c,a         ; copy to C
16C3: 3A 10 69    ld      a,(kongs_x_position_6910)   ; load A with kong's X position
16C6: FE 5A       cp      $5a         ; < #5A ?
16C8: D2 E1 16    jp      nc,$16e1    ; yes, skip ahead

16CB: CB 79       bit     7,c
16CD: CA D5 16    jp      z,$16d5     ; yes, skip next 2 steps

16D0: 3E 01       ld      a,$01       ; A := 1
16D2: 32 A0 62    ld      (top_conveyor_counter_62a0),a   ; store into top conveyor counter

16D5: CD 02 26    call    $2602       ; ???
16D8: 3A A3 63    ld      a,(top_conveyor_direction_vector_63a3)   ; load A with direction vector for top conveyor
16DB: 4F          ld      c,a         ; C := 1
16DC: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of Kong sprite
16DF: FF          rst     $38         ; move kong
16E0: C9          ret                 ; return

16E1: FE 5D       cp      $5d         ; < #5D ?
16E3: DA EE 16    jp      c,$16ee     ; no, skip ahead

16E6: CB 79       bit     7,c         ; is bit 7 of C zero?
16E8: CA D0 16    jp      z,$16d0     ; yes, jump back

16EB: C3 D5 16    jp      $16d5       ; jump back

16EE: 21 8C 38    ld      hl,$388c    ; load HL with start of table data for kong
16F1: CD 4E 00    call    $004e       ; update kong's sprites
16F4: 3E 66       ld      a,$66       ; A := #66
16F6: 32 0C 69    ld      (clear_kongs_top_right_sprite_690c),a   ; store into kong's right arm sprite for climbing
16F9: AF          xor     a           ; A := 0
16FA: 32 24 69    ld      (kongs_right_arm_sprite_for_carrying_girl_6924),a   ; clear kong's arm sprite
16FD: 32 2C 69    ld      (girl_being_carried_sprite_692c),a   ; clear girl under kong's arm
1700: 32 AF 62    ld      (kong_misc_counter_62af),a   ; clear kong climbing counter
1703: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
1706: 34          inc     (hl)        ; increase counter
1707: C9          ret                 ; return

; called from #1654 and #16A3
; clears all sounds, draws heart sprite, redraws girl sprite, clear "help", play end of level sound

1708: CD 1C 01    call    $011c       ; clear all sounds
170B: 21 20 6A    ld      hl,heart_sprite_x_position_6a20    ; load HL with heart sprite
170E: 36 80       ld      (hl),$80    ; set heart sprite X position
1710: 23          inc     hl          ; next
1711: 36 76       ld      (hl),$76    ; set heart sprite
1713: 23          inc     hl          ; next
1714: 36 09       ld      (hl),$09    ; set heart sprite color
1716: 23          inc     hl          ; next
1717: 36 20       ld      (hl),$20    ; set heart sprite Y position
1719: 21 05 69    ld      hl,girls_sprite_6905    ; load HL with girl's sprite
171C: 36 13       ld      (hl),$13    ; set girl's sprite
171E: 21 C4 75    ld      hl,$75c4    ; load HL with VRAM screen address
1721: 11 20 00    ld      de,$0020    ; DE := #20
1724: 3E 10       ld      a,$10       ; A := #10
1726: CD 14 05    call    $0514       ; clear "help" that the girl yells
1729: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load sound address
172C: 36 07       ld      (hl),$07    ; play sound for end of level
172E: 23          inc     hl          ; HL now has sound duration
172F: 36 03       ld      (hl),$03    ; set duration to 3
1731: C9          ret                 ; return

; jump here from #1622 when girders or elevators is finished.  step 4 of 6
; jump here from #1622 when conveyors is finished.  step 3 of 5

1732: CD 6F 30    call    $306f       ; animate kong climbing up the ladder with girl under arm
1735: 3A 13 69    ld      a,(kong_sprite_y_position_6913)   ; load A with kong sprite Y position
1738: FE 2C       cp      $2c         ; < #2C ? (level of the girl)
173A: D0          ret     nc          ; yes, return

; else kong has grabbed the girl on the way out

173B: AF          xor     a           ; A := #00
173C: 32 00 69    ld      (girls_head_sprite_6900),a   ; clear girl's head sprite
173F: 32 04 69    ld      (girls_body_sprite_6904),a   ; clear girl's body sprite
1742: 32 0C 69    ld      (clear_kongs_top_right_sprite_690c),a   ; clear kong's top right sprite
1745: 3E 6B       ld      a,$6b       ; A := #6B = code for sprite with kong's arm out
1747: 32 24 69    ld      (kongs_right_arm_sprite_for_carrying_girl_6924),a   ; store into kong's right arm sprite for carrying girl
174A: 3D          dec     a           ; A := #6A = code for sprite with girl being carried
174B: 32 2C 69    ld      (girl_being_carried_sprite_692c),a   ; store into girl being carried sprite
174E: 21 21 6A    ld      hl,heart_sprite_6a21    ; load HL with heart sprite
1751: 34          inc     (hl)        ; change heart to broken
1752: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
1755: 34          inc     (hl)        ; increase counter
1756: C9          ret                 ; return

; jump here from #1622 when girders or elevators is finished.  step 5 of 6
; jump here from #1622 when conveyors is finished.  step 4 of 5

1757: CD 6F 30    call    $306f       ; animate kong climbing up the ladder with girl under arm
175A: CD 6C 17    call    $176c       ; ???
175D: 23          inc     hl
175E: 13          inc     de
175F: CD 83 17    call    $1783       ; ???
1762: 3E 40       ld      a,$40       ; A := #40
1764: 32 09 60    ld      (waittimermsb_6009),a; set timer to #40
1767: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
176A: 34          inc     (hl)        ; increase counter
176B: C9          ret                 ; return

; called from #175A, above

176C: 11 03 00    ld      de,$0003    ; load DE with offset to subtract
176F: 21 2F 69    ld      hl,girl_under_kongs_arm_y_position_692f    ; load HL with girl under kong's arm Y position.  counting down, it will go through all of kong's body
1772: 06 0A       ld      b,$0a       ; for B = 1 to #0A

1774: A7          and     a           ; clear carry flag
1775: 7E          ld      a,(hl)      ; load A with Y position
1776: ED 52       sbc     hl,de       ; next offset
1778: FE 19       cp      $19         ; girl still on screen?
177A: D2 7F 17    jp      nc,$177f    ; yes, skip next step

177D: 36 00       ld      (hl),$00    ; set Y position to 0 = clear from screen ?

177F: 2B          dec     hl          ; previous data
1780: 10 F2       djnz    $1774       ; Next B

1782: C9          ret                 ; return

; called from #175F

1783: 06 0A       ld      b,$0a       ; for B = 1 to #A

1785: 7E          ld      a,(hl)      ; load A with ???
1786: A7          and     a           ; == 0 ?
1787: C2 26 00    jp      nz,$0026    ; no, jump to #0026.  This will effectively RET twice

178A: 19          add     hl,de       ; else add offset for next memory
178B: 10 F8       djnz    $1785       ; next B

178D: C9          ret                 ; return

; jump here from #1622 when girders or elevators is finished.  step 6 of 6
; jump here from #1622 when conveyors is finished.  step 5 of 5

178E: DF          rst     $18         ; count down timer and only continue here if zero, else RET
178F: 2A 2A 62    ld      hl,(store_622a)  ; load HL with address for this screen/level
1792: 23          inc     hl          ; next screen
1793: 7E          ld      a,(hl)      ; load A with the screen for next
1794: FE 7F       cp      $7f         ; at end ?
1796: C2 9D 17    jp      nz,$179d    ; no, skip next 2 steps

1799: 21 73 3A    ld      hl,$3a73    ; load HL with table for screens/levels for level 5+
179C: 7E          ld      a,(hl)      ; load A with the screen

179D: 22 2A 62    ld      (store_622a),hl  ; store screen address lookup for next time
17A0: 32 27 62    ld      (screen_number_6227),a   ; store A into screen number
17A3: 11 00 05    ld      de,$0500    ; load task #5, parameter 0 ; adds bonus to player's score
17A6: CD 9F 30    call    $309f       ; insert task
17A9: AF          xor     a           ; A := 0
17AA: 32 88 63    ld      (end_of_level_counter_6388),a   ; clear end of level counter
17AD: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer addr.
17B0: 36 30       ld      (hl),$30    ; set timer to #30
17B2: 23          inc     hl          ; HL := GameMode2
17B3: 36 08       ld      (hl),$08    ; set game mode2 to 8
17B5: C9          ret                 ; return

17B6: 00          nop

; arrive when rivets is cleared

17B7: CD 1C 01    call    $011c       ; clear all sounds
17BA: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load HL with sound address
17BD: 36 0E       ld      (hl),$0e    ; play sound for rivets falling and kong beating chest
17BF: 23          inc     hl          ; HL := #608B = sound duration
17C0: 36 03       ld      (hl),$03    ; set duration to 3
17C2: 3E 10       ld      a,$10       ; A := #10 = code for clear space
17C4: 11 20 00    ld      de,$0020    ; DE := #20
17C7: 21 23 76    ld      hl,$7623    ; load HL with video RAM location
17CA: CD 14 05    call    $0514       ; clear "help" on left side of girl
17CD: 21 83 75    ld      hl,$7583    ; load HL with video RAM location
17D0: CD 14 05    call    $0514       ; clear "help of right side of girl
17D3: 21 DA 76    ld      hl,$76da    ; load HL with center area of video ram
17D6: CD 26 18    call    $1826       ; clear screen area
17D9: 11 47 3A    ld      de,$3a47    ; load DE with start of table data
17DC: CD A7 0D    call    $0da7       ; draw the screen
17DF: 21 D5 76    ld      hl,$76d5    ; load HL with center area of video ram
17E2: CD 26 18    call    $1826       ; clear screen area
17E5: 11 4D 3A    ld      de,$3a4d    ; load DE with start of table data
17E8: CD A7 0D    call    $0da7       ; draw the screen
17EB: 21 D0 76    ld      hl,$76d0    ; load HL with center area of video ram
17EE: CD 26 18    call    $1826       ; clear screen area
17F1: 11 53 3A    ld      de,$3a53    ; load DE with start of table data
17F4: CD A7 0D    call    $0da7       ; draw the screen
17F7: 21 CB 76    ld      hl,$76cb    ; load HL with center area of video ram
17FA: CD 26 18    call    $1826       ; clear screen area
17FD: 11 59 3A    ld      de,$3a59    ; load DE with start of table data
1800: CD A7 0D    call    $0da7       ; draw the screen
1803: 21 5C 38    ld      hl,$385c    ; load HL with start of kong graphic table data
1806: CD 4E 00    call    $004e       ; update kong's sprites
1809: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of kong sprites
180C: 0E 44       ld      c,$44       ; load offset of #44
180E: FF          rst     $38         ; move kong
180F: 21 05 69    ld      hl,girls_sprite_6905    ; load HL with girl's sprite
1812: 36 13       ld      (hl),$13    ; set girl's sprite
1814: 3E 20       ld      a,$20       ; A := #20
1816: 32 09 60    ld      (waittimermsb_6009),a; set timer to #20
1819: 3E 80       ld      a,$80       ; A := #80
181B: 32 90 63    ld      (timer_unknown_6390),a   ; store into timer ???
181E: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
1821: 34          inc     (hl)        ; increase counter
1822: 22 C0 63    ld      (timer_unknown_63c0),hl  ; store into ???
1825: C9          ret                 ; return

; called from several places with HL preloaded with a video RAM address
; used to clear sections of the rivets screen when it is completed

1826: 11 DB FF    ld      de,$ffdb    ; load DE with offset for each column
1829: 0E 0E       ld      c,$0e       ; for C = 1 to #0E
182B: 3E 10       ld      a,$10       ; A := #10 (clear space on screen)

182D: 06 05       ld      b,$05       ; for B = 1 to 5

182F: 77          ld      (hl),a      ; store A into (HL) - clears the screen element
1830: 23          inc     hl          ; next HL
1831: 10 FC       djnz    $182f       ; next B

1833: 19          add     hl,de       ; add offset to HL
1834: 0D          dec     c           ; next C
1835: C2 2D 18    jp      nz,$182d    ; loop until done

1838: C9          ret                 ; return

; arrive from #1647 when #6388 == 2

1839: 21 90 63    ld      hl,timer_unknown_6390    ; load HL with timer ???
183C: 34          inc     (hl)        ; increase.  at zero?
183D: CA 59 18    jp      z,$1859     ; yes, skip ahead

1840: 7E          ld      a,(hl)      ; load A with the timer value
1841: E6 07       and     $07         ; mask bits, now between 0 and 7.  zero?
1843: C0          ret     nz          ; no, return

; kong is beating his chest after rivets have been cleared

1844: 11 CF 39    ld      de,$39cf    ; load DE with start of table data
1847: CB 5E       bit     3,(hl)      ; test bit 3.  True?
1849: 20 03       jr      nz,$184e    ; Yes, skip next step

184B: 11 F7 39    ld      de,$39f7    ; else load DE with other table start

184E: EB          ex      de,hl       ; DE <> HL
184F: CD 4E 00    call    $004e       ; update kong's sprites
1852: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of Kong sprite
1855: 0E 44       ld      c,$44       ; C := #44
1857: FF          rst     $38         ; move kong
1858: C9          ret                 ; return

1859: 21 5C 38    ld      hl,$385c    ; load HL with start of kong graphic table data
185C: CD 4E 00    call    $004e       ; update kong's sprites
185F: 21 08 69    ld      hl,start_of_kong_sprite_6908    ; load HL with start of Kong sprite
1862: 0E 44       ld      c,$44       ; C := #44
1864: FF          rst     $38         ; move kong
1865: 3E 20       ld      a,$20       ; A := #20
1867: 32 09 60    ld      (waittimermsb_6009),a; store into timer
186A: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
186D: 34          inc     (hl)        ; increase counter
186E: C9          ret                 ; return

; rivets has been cleared and kong is falling upside down
; arrive from #1647

186F: DF          rst     $18         ; count down timer and only continue here if zero, else RET

1870: 21 1F 3A    ld      hl,$3a1f    ; start of table data for kong upside down
1873: CD 4E 00    call    $004e       ; update kong's sprites
1876: 3E 03       ld      a,$03       ; A := 3
1878: 32 84 60    ld      (play_sound_for_falling_bouncer_6084),a   ; play falling sound
187B: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
187E: 34          inc     (hl)        ; increase
187F: C9          ret                 ; return

; arrive from #1647 when #6388 == 4

1880: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with kong start sprite
1883: 0E 01       ld      c,$01       ; load C with 1 pixel to move
1885: FF          rst     $38         ; move kong
1886: 3A 1B 69    ld      a,(unknown_691b)   ; load A with ???
1889: FE D0       cp      $d0         ; == #D0 ?
188B: C0          ret     nz          ; no, return

188C: 3E 20       ld      a,$20       ; A := #20
188E: 32 19 69    ld      (unknown_6919),a   ; store into kong's face sprite - kong is now bigmouthed with crazy eyes
1891: 21 24 6A    ld      hl,sprite_address_used_for_kong_aching_head_lines_6a24    ; load HL with sprite address used for kong's aching head lines
1894: 36 7F       ld      (hl),$7f    ; set sprite X value
1896: 2C          inc     l           ; next
1897: 36 39       ld      (hl),$39    ; set sprite color
1899: 2C          inc     l           ; next
189A: 36 01       ld      (hl),$01    ; set sprite value
189C: 2C          inc     l           ; next
189D: 36 D8       ld      (hl),$d8    ; set sprite Y value
189F: 21 C6 76    ld      hl,$76c6    ; load HL with start of screen location to clear
18A2: CD 26 18    call    $1826       ; clear the top part of rivets
18A5: 11 5F 3A    ld      de,$3a5f    ; load DE with table data for sections to clear after rivets done
18A8: CD A7 0D    call    $0da7       ; draw the top girder where mario and girl meet

18AB: 11 04 00    ld      de,$0004    ; load counters
18AE: 01 28 02    ld      bc,$0228    ; load counters
18B1: 21 03 69    ld      hl,sprite_girl_table_data_y_position_6903    ; set sprite girl table data Y position
18B4: CD 3D 00    call    $003d       ; move the girl down

18B7: 3E 00       ld      a,$00       ; A := 0 [why written this way?]
18B9: 32 AF 62    ld      (kong_misc_counter_62af),a   ; store into kong climbing counter
18BC: 3E 03       ld      a,$03       ; set boom sound duration
18BE: 32 82 60    ld      (boom_sound_address_6082),a   ; play boom sound
18C1: 21 88 63    ld      hl,end_of_level_counter_6388    ; load HL with end of level counter
18C4: 34          inc     (hl)        ; increase counter
18C5: C9          ret                 ; return

; arrive from #1647 when level is complete, last of 5 steps

18C6: 21 AF 62    ld      hl,kong_misc_counter_62af    ; load HL with kong climbing counter address
18C9: 35          dec     (hl)        ; decrease.  zero?
18CA: CA 3D 19    jp      z,$193d     ; yes, skip ahead, handle next level routine

18CD: 7E          ld      a,(hl)      ; load A with kong climbing counter
18CE: E6 07       and     $07         ; mask bits, now between 0 and 7.  zero?
18D0: C0          ret     nz          ; no , return

18D1: 21 25 6A    ld      hl,unknown_6a25    ; load HL with ???
18D4: 7E          ld      a,(hl)      ; get value
18D5: EE 80       xor     $80         ; toggle bit 7
18D7: 77          ld      (hl),a      ; store result

18D8: 21 19 69    ld      hl,unknown_6919    ; load HL with ???
18DB: 46          ld      b,(hl)      ; load B with this value
18DC: CB A8       res     5,b         ; clear bit 5 of B
18DE: AF          xor     a           ; A := 0
18DF: CD 09 30    call    $3009       ; ???
18E2: F6 20       or      $20         ; turn on bit 5
18E4: 77          ld      (hl),a      ; store result

18E5: 21 AF 62    ld      hl,kong_misc_counter_62af    ; load HL with kong climbing counter
18E8: 7E          ld      a,(hl)      ; get value
18E9: FE E0       cp      $e0         ; == #E0 ?
18EB: C2 10 19    jp      nz,$1910    ; no, skip ahead

18EE: 3E 50       ld      a,$50       ; A := #50
18F0: 32 4F 69    ld      (mario_sprite_y_value_694f),a   ; store into mario sprite Y value
18F3: 3E 00       ld      a,$00       ; A := 0
18F5: 32 4D 69    ld      (mario_sprite_value_694d),a   ; store into mario sprite value
18F8: 3E 9F       ld      a,$9f       ; A := #9F
18FA: 32 4C 69    ld      (mario_sprite_x_position_694c),a   ; set mario sprite X value at #9F
18FD: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario X position
1900: FE 80       cp      $80         ; < 80 ?
1902: D2 0F 19    jp      nc,$190f    ; yes, skip next 4 steps

1905: 3E 80       ld      a,$80       ; A := #80
1907: 32 4D 69    ld      (mario_sprite_value_694d),a   ; store into mario sprite value
190A: 3E 5F       ld      a,$5f       ; A := #5F
190C: 32 4C 69    ld      (mario_sprite_x_position_694c),a   ; store into mario sprite X value

190F: 7E          ld      a,(hl)      ; load A with ???

1910: FE C0       cp      $c0         ; == #C0 ?
1912: C0          ret     nz          ; no, return

1913: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load HL with sound address
1916: 36 0C       ld      (hl),$0c    ; play sound for rivets cleared
1918: 3A 29 62    ld      a,(level_number_6229)   ; load A with level #
191B: 0F          rrca                ; roll a right .  is this an odd level ?
191C: 38 02       jr      c,$1920     ; Yes, skip next step

191E: 36 05       ld      (hl),$05    ; else play sound for even numbered rivets

1920: 23          inc     hl          ; HL := #608B = sound duration
1921: 36 03       ld      (hl),$03    ; set duration to 3
1923: 21 23 6A    ld      hl,heart_sprite_6a23    ; load HL with heart sprite
1926: 36 40       ld      (hl),$40    ; set heart sprite Y position
1928: 2B          dec     hl          ; decrement HL
1929: 36 09       ld      (hl),$09    ; set heart sprite color
192B: 2B          dec     hl          ; decrement HL
192C: 36 76       ld      (hl),$76    ; set heart sprite
192E: 2B          dec     hl          ; decrement HL
192f: 36 8f       ld      (hl),$8f    ; set heart sprite X position
1931: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario X position
1934: fe 80       cp      $80         ; is mario on the left side of the screen?
1936: d0          ret     nc          ; yes, return

1937: 3E 6f       ld      a,$6f       ; else A := #6F
1939: 32 20 6A    ld      (heart_sprite_x_position_6a20),a   ; store A into heart sprite X position
193C: c9          ret                 ; return from sub

; kong has climbed off the screen at end of level

193D: 2A 2A 62    ld      hl,(store_622a)  ; load HL with contents of #622A.  this is a pointer to the levels/screens data
1940: 23          inc     hl          ; increase HL.  = next level
1941: 7E          ld      a,(hl)      ; load A with contents of HL = the screen we are going to play next
1942: fe 7f       cp      $7f         ; is this the end code ?
1944: c2 4B 19    jp      nz,$194b    ; no, skip next 2 steps

1947: 21 73 3A    ld      hl,$3a73    ; yes, load HL with #3A73 = start of table data for screens/levels for level 5+
194A: 7E          ld      a,(hl)      ; load A with screen number from table

194B: 22 2A 62    ld      (store_622a),hl  ; store
194E: 32 27 62    ld      (screen_number_6227),a   ; store A into screen number
1951: 21 29 62    ld      hl,level_number_6229    ; load HL with level number address
1954: 34          inc     (hl)        ; increase #6229 by one
1955: 11 00 05    ld      de,$0500    ; load task #5, parameter 0 ; adds bonus to player's score
1958: CD 9F 30    call    $309f       ; insert task
195B: AF          xor     a           ; A := 0
195C: 32 2E 62    ld      (number_of_goofys_to_draw_622e),a   ; store into number of goofys to draw
195F: 32 88 63    ld      (end_of_level_counter_6388),a   ; store into end of level counter
1962: 21 09 60    ld      hl,waittimermsb_6009; load HL with timer
1965: 36 E0       ld      (hl),$e0    ; set timer to #E0
1967: 23          inc     hl          ; increase HL to GameMode2
1968: 36 08       ld      (hl),$08    ; set game mode2 to 8
196A: C9          ret                 ; return

; arrive from jump table at #0701 when GameMode2 == #17

196B: CD 52 08    call    $0852       ; clear screen and all sprites
196E: 3A 0E 60    ld      a,(playerturnb_600e) ; load A with current player number.  0 = player 1, 1 = player 2
1971: C6 12       add     a,$12       ; add #12
1973: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2, now had #12 for player 1 or #13 for player 2
1976: C9          ret                 ; return

; main routine

1977: CD EE 21    call    $21ee       ; used during attract mode only.  sets virtual input.

; arrive here from #0701 when playing

197A: CD BD 1D    call    $1dbd       ; check for bonus items and jumping scores, rivets
197D: CD 8C 1E    call    $1e8c       ; do stuff for items hit with hammer
1980: CD C3 1A    call    $1ac3       ; check for jumping
1983: CD 72 1F    call    $1f72       ; roll barrels
1986: CD 8F 2C    call    $2c8f       ; roll barrels ?
1989: CD 03 2C    call    $2c03       ; do barrel deployment ?
198C: CD ED 30    call    $30ed       ; update fires if needed
198F: CD 04 2E    call    $2e04       ; update bouncers if on elevators
1992: CD EA 24    call    $24ea       ; do stuff for pie factory
1995: CD DB 2D    call    $2ddb       ; deploy fireball/firefoxes for conveyors and rivets
1998: CD D4 2E    call    $2ed4       ; do stuff for hammer
199B: CD 07 22    call    $2207       ; do stuff for conveyors
199E: CD 33 1A    call    $1a33       ; check for and handle running over rivets
19A1: CD 85 2A    call    $2a85       ; check for mario falling
19A4: CD 46 1F    call    $1f46       ; handle mario falling
19A7: CD FA 26    call    $26fa       ; do stuff for elevators
19AA: CD F2 25    call    $25f2       ; handle conveyor directions, adjust Mario's speed based on conveyor directions
19AD: CD DA 19    call    $19da       ; check for mario picking up bonus item
19B0: CD FB 03    call    $03fb       ; check for kong beating chest and animate girl and her screams
19B3: CD 08 28    call    $2808       ; check for collisions with hostile sprites [set to NOPS to make mario invincible to enemy sprites]
19B6: CD 1D 28    call    $281d       ; do stuff for hammers
19B9: CD 57 1E    call    $1e57       ; check for end of level
19BC: CD 07 1A    call    $1a07       ; handle when the bonus timer has run out
19BF: CD CB 2F    call    $2fcb       ; for non-girder levels, checks for bonus timer changes. if the bonus counts down, sets a possible new fire to be released,
                                        ; sets a bouncer to be deployed, updates the bonus timer onscreen, and checks for bonus time running out
19C2: 00          nop
19C3: 00          nop
19C4: 00          nop                 ; no operations.  [a deleted call ?]

19C5: 3A 00 62    ld      a,(mario_array_6200)   ; load A with 0 if mario is dead, 1 if he is alive
19C8: A7          and     a           ; is mario alive?
19C9: C0          ret     nz          ; yes, return to #00D2

; mario died

19CA: CD 1C 01    call    $011c       ; no, mario died.  clear all sounds
19CD: 21 82 60    ld      hl,boom_sound_address_6082    ; load HL with boom sound address
19D0: 36 03       ld      (hl),$03    ; play boom sound for 3 units
19D2: 21 0A 60    ld      hl,gamemode2_600a; load HL with game mode2
19D5: 34          inc     (hl)        ; increase
19D6: 2B          dec     hl          ; HL := WaitTimerMSB (timer used for sound effects)
19D7: 36 40       ld      (hl),$40    ; set timer to wait 40 units
19D9: C9          ret                 ; return to #00D2

; called from #19AD as part of the main routine
; checks for bonus items being picked up

19DA: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with Mario's X position
19DD: 06 03       ld      b,$03       ; for B = 1 to 3
19DF: 21 0C 6A    ld      hl,start_of_bonus_items_6a0c    ; load HL with X position of first bonus

19E2: BE          cp      (hl)        ; are they equal?
19E3: CA ED 19    jp      z,$19ed     ; yes, then test the Y position too

19E6: 2C          inc     l
19E7: 2C          inc     l
19E8: 2C          inc     l
19E9: 2C          inc     l           ; increase 4 times to point to next bonus item position
19EA: 10 F6       djnz    $19e2       ; Loop 3 times, check for the 3 items

19EC: C9          ret                 ; return

19ED: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
19F0: 2C          inc     l
19F1: 2C          inc     l
19F2: 2C          inc     l           ; get HL to point to Y position of bonus item
19F3: BE          cp      (hl)        ; are they equal?
19F4: C0          ret     nz          ; no, return from this test

19F5: 2D          dec     l           ; yes, decrement L 2 times to check if this item has already been picked up
19F6: 2D          dec     l
19F7: CB 5E       bit     3,(hl)      ; test bit 3 of HL, tells whether picked up already or not.  Item not already picked up?
19F9: C0          ret     nz          ; Item picked up already, then return

; bonus item has been picked up

19FA: 2D          dec     l           ; decrease L.  HL now has the starting address of the sprite that was picked up
19FB: 22 43 63    ld      (unknown_for_use_later_6343),hl  ; store into this temp memory.  read from at #1E18
19FE: AF          xor     a           ; A := 0
19FF: 32 42 63    ld      (scoring_indicator_6342),a   ; store into ???.  read from at #1DD6
1A02: 3C          inc     a           ; A := 1
1A03: 32 40 63    ld      (bonus_indicator_6340),a   ; store into #6340 - usually 0, changes when mario picks up bonus item. jumps over item turns to 1 quickly, then 2 until bonus disappears
1A06: C9          ret                 ; return

; called from main routine at #19BC

1A07: 3A 86 63    ld      a,(time_has_run_out_indicator_6386)   ; load A with the location which tells if the timer has run out yet.
1A0A: EF          rst     $28         ; jump based on A

1A0B  1E 1A                             ; #1A1E if zero return immediately, bonus timer has not run out
1A0D  15 1A                             ; #1A15
1A0F  1F 1A                             ; #1A1F
1A11  2A 1A                             ; #1A2A
1A13  00 00                             ; unused

; arrive from #1A0A

1A15: AF          xor     a           ; A := 0
1A16: 32 87 63    ld      (timer_address_6387),a   ; clear timer which counts down when the timer runs out
1A19: 3E 02       ld      a,$02       ; A := 2
1A1B: 32 86 63    ld      (time_has_run_out_indicator_6386),a   ; store into the location which tells if the timer has run out yet.
1A1E: C9          ret                 ; return

; arrive from #1A0A

1A1F: 21 87 63    ld      hl,timer_address_6387    ; load HL with timer address
1A22: 35          dec     (hl)        ; decreases the timer which counts down after time has run out. time out?
1A23: C0          ret     nz          ; no, return

1A24: 3E 03       ld      a,$03       ; A := 3
1A26: 32 86 63    ld      (time_has_run_out_indicator_6386),a   ; store 3 into #6386 - time is up for mario!
1A29: C9          ret                 ; return

; we arrive here when the timer runs out

1A2A: 3A 16 62    ld      a,(jumping_status_6216)   ; load A with jump indicator
1A2D: A7          and     a           ; is mario jumping ?
1A2E: C0          ret     nz          ; yes, return, mario never dies while jumping

1A2F: E1          pop     hl          ; no, pop HL to return to higher subroutine
1A30: C3 D2 19    jp      $19d2       ; jump to mario died and return

; called from main routine
; check for running over rivets ?

1A33: 3E 08       ld      a,$08       ; A := 8 = 1000 binary = code for rivets
1A35: F7          rst     $30         ; continue here only on rivets, else RET

1A36: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
1A39: FE 4B       cp      $4b         ; == #4B = the column the left rivets are on ?
1A3B: CA 4B 1A    jp      z,$1a4b     ; yes, skip ahead and set the indicator

1A3E: FE B3       cp      $b3         ; == #B3 = the column the right rivets are on ?
1A40: CA 4B 1A    jp      z,$1a4b     ; yes, skip ahead and set the indicator

1A43: 3A 91 62    ld      a,(column_indicator_6291)   ; else load A with rivet column indicator
1A46: 3D          dec     a           ; is mario possibly traversing a column?
1A47: CA 51 1A    jp      z,$1a51     ; yes, skip ahead
1A4A: C9          ret                 ; else return

1A4B: 3E 01       ld      a,$01       ; A := 1
1A4D: 32 91 62    ld      (column_indicator_6291),a   ; store into column indicator
1A50: C9          ret                 ; return

1A51: 32 91 62    ld      (column_indicator_6291),a   ; clear the column indicator
1A54: 47          ld      b,a         ; B := 0
1A55: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
1A58: 3D          dec     a           ; decrement
1A59: FE D0       cp      $d0         ; compare with #D0.  is mario too low to go over a rivet?
1A5B: D0          ret     nc          ; yes, return

1A5C: 07          rlca                ; rotate left = mult by 2
1A5D: D2 62 1A    jp      nc,$1a62    ; no carry, skip next step

1A60: CB D0       set     2,b         ; else B := 4

1A62: 07          rlca
1A63: 07          rlca                ; rotate left twice = mult by 4
1A64: D2 69 1A    jp      nc,$1a69    ; no carry, skip next step

1A67: CB C8       set     1,b         ; B := B + 2
1A69: E6 07       and     $07         ; mask bits in A, now between 0 and 7
1A6B: FE 06       cp      $06         ; == 6 ?
1A6D: C2 72 1A    jp      nz,$1a72    ; no, skip next step

1A70: CB C8       set     1,b         ; else set this bit
1A72: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
1A75: 07          rlca                ; rotate left
1A76: D2 7B 1A    jp      nc,$1a7b    ; no carry, skip next step

1A79: CB C0       set     0,b         ; B := B + 1
1A7B: 21 92 62    ld      hl,start_of_array_of_rivets_6292    ; load HL with start of array of rivets
1A7E: 78          ld      a,b         ; A := B
1A7F: 85          add     a,l         ; add #92
1A80: 6F          ld      l,a         ; copy to L
1A81: 7E          ld      a,(hl)      ; get the status of the rivet mario is crossing
1A82: A7          and     a           ; has this rivet already been traversed?
1A83: C8          ret     z           ; yes, return

; a rivet has been traversed

1A84: 36 00       ld      (hl),$00    ; set this rivet as cleared
1A86: 21 90 62    ld      hl,number_of_rivets_left_6290    ; load HL with address of number of rivets remaining
1A89: 35          dec     (hl)        ; decrease number of rivets
1A8A: 78          ld      a,b         ; A := B
1A8B: 01 05 00    ld      bc,$0005    ; load BC with offset of 5
1A8E: 1F          rra                 ; rotate right.  carry?  (is this rivet on right side?)
1A8F: DA BD 1A    jp      c,$1abd     ; yes, skip ahead and load HL with #012B and return to #1A95

1A92: 21 CB 02    ld      hl,$02cb    ; else load HL with master offset for rivets

1A95: A7          and     a           ; A == 0 ?
1A96: CA 9E 1A    jp      z,$1a9e     ; yes, skip next 3 steps

1A99: 09          add     hl,bc       ; add offset to HL
1A9A: 3D          dec     a           ; decrease A.  zero?
1A9B: C2 99 1A    jp      nz,$1a99    ; no, loop again

1A9E: 01 00 74    ld      bc,$7400    ; start of video RAM is #7400
1AA1: 09          add     hl,bc       ; add offset computed based on which rivet is cleared
1AA2: 3E 10       ld      a,$10       ; A := #10 = clear space
1AA4: 77          ld      (hl),a      ; erase the rivet
1AA5: 2D          dec     l           ; next video memory
1AA6: 77          ld      (hl),a      ; erase the top of the rivet
1AA7: 2C          inc     l
1AA8: 2C          inc     l           ; next video memory
1AA9: 77          ld      (hl),a      ; erase underneath the rivet [ not needed , there is nothing there to erase ???]
1AAA: 3E 01       ld      a,$01       ; A := 1
1AAC: 32 40 63    ld      (bonus_indicator_6340),a   ; store into #6340 - usually 0, changes when mario picks up bonus item. jumps over item turns to 1 quickly, then 2 until bonus disappears
1AAF: 32 42 63    ld      (scoring_indicator_6342),a   ; store into scoring indicator
1AB2: 32 25 62    ld      (bonus_sound_indicator_6225),a   ; store into bonus sound indicator
1AB5: 3A 16 62    ld      a,(jumping_status_6216)   ; load A with jump indicator
1AB8: A7          and     a           ; is mario jumping ?
1AB9: CC 95 1D    call    z,$1d95     ; no, play the bonus sound

1ABC: C9          ret                 ; else return

; arrive from #1A8F above

1ABD: 21 2B 01    ld      hl,$012b    ; load HL with alternate master offset for rivets
1AC0: C3 95 1A    jp      $1a95       ; jump back to program and resume

; check for jumping and other movements
; called from main routine at #1980

1AC3: 3A 16 62    ld      a,(jumping_status_6216)   ; load A with jump indicator
1AC6: 3D          dec     a           ; is mario already jumping?
1AC7: CA B2 1B    jp      z,$1bb2     ; yes, jump ahead

1ACA: 3A 1E 62    ld      a,(jump_coming_down_indicator_621e)   ; else load A with jump coming down indicator
1ACD: A7          and     a           ; is the jump almost done ?
1ACE: C2 55 1B    jp      nz,$1b55    ; yes, skip way ahead

1AD1: 3A 17 62    ld      a,(unknown_6217)   ; load A with hammer check
1AD4: 3D          dec     a           ; is hammer active?
1AD5: CA E6 1A    jp      z,$1ae6     ; yes, skip ahead

1AD8: 3A 15 62    ld      a,(ladder_status_6215)   ; else load A with ladder check
1ADB: 3D          dec     a           ; is mario on a ladder?
1ADC: CA 38 1B    jp      z,$1b38     ; yes, skip ahead

1ADF: 3A 10 60    ld      a,(inputstate_6010) ; load A with input
1AE2: 17          rla                 ; is player pressing jump ?
1AE3: DA 6E 1B    jp      c,$1b6e     ; yes, begin jump subroutine

1AE6: CD 1F 24    call    $241f       ; else call this other sub which loads DE with something depending on mario's position.  ladder check?

1AE9: 3A 10 60    ld      a,(inputstate_6010) ; load A with input
1AEC: 1D          dec     e           ; E == 1 ?
1AED: CA F5 1A    jp      z,$1af5     ; yes, jump ahead

1AF0: CB 47       bit     0,a         ; test bit 0 of input.  is player pressing right ?
1AF2: C2 8F 1C    jp      nz,$1c8f    ; yes, skip ahead

1AF5: 15          dec     d           ; else is D == 1 ?
1AF6: CA FE 1A    jp      z,$1afe     ; yes, skip ahead

1AF9: CB 4F       bit     1,a         ; is player pressing left ?
1AFB: C2 AB 1C    jp      nz,$1cab    ; yes, skip ahead

1AFE: 3A 17 62    ld      a,(unknown_6217)   ; else load A with hammer check
1B01: 3D          dec     a           ; is the hammer active?
1B02: C8          ret     z           ; yes, return

1B03: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
1B06: C6 08       add     a,$08       ; Add 8
1B08: 57          ld      d,a         ; copy into D
1B09: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with Mario's X position
1B0C: F6 03       or      $03         ; turn on left 2 bits (0 and 1)
1B0E: CB 97       res     2,a         ; turn off bit 2
1B10: 01 15 00    ld      bc,$0015    ; load BC with #15 = number of ladders to check
1B13: CD 6E 23    call    $236e       ; check for ladders nearby if none, RET to higher sub.  else A := 0 if at bottom of ladder, A := 1 if at top.  C has the ladder number/type?

; mario is near a ladder

1B16: F5          push    af          ; save AF for later
1B17: 21 07 62    ld      hl,mario_movement_indicator_sprite_value_6207    ; load HL with movement indicator
1B1A: 7E          ld      a,(hl)      ; load movement
1B1B: E6 80       and     $80         ; mask bits
1B1D: F6 06       or      $06         ; mask bits
1B1F: 77          ld      (hl),a      ; store movement
1B20: 21 1A 62    ld      hl,moving_ladder_indicator_621a    ; load HL with ladder type address
1B23: 3E 04       ld      a,$04       ; A := 4
1B25: B9          cp      c           ; compare.  is the ladder broken?
1B26: 36 01       ld      (hl),$01    ; store 1 into ladder type = broken ladder by default
1B28: D2 2C 1B    jp      nc,$1b2c    ; if ladder broken, skip next step

1B2B: 35          dec     (hl)        ; set indicator to unbroken ladder

1B2C: F1          pop     af          ; restore AF
1B2D: A7          and     a           ; A == 0 ?  is mario at bottom of ladder?
1B2E: CA 4E 1B    jp      z,$1b4e     ; yes, skip ahead

; else mario at top of ladder

1B31: 7E          ld      a,(hl)      ; load A with broken ladder indicator
1B32: A7          and     a           ; is this ladder broken?
1B33: C0          ret     nz          ; yes, return.  we can't go down broken ladders

; top of unbroken ladder

1B34: 2C          inc     l           ; next HL := #621B
1B35: 72          ld      (hl),d      ; store D
1B36: 2C          inc     l           ; next HL := #621C
1B37: 70          ld      (hl),b      ; store B

; if mario is on a ladder
; jump here from #1ADC

1B38: 3A 10 60    ld      a,(inputstate_6010) ; load A with input
1B3B: CB 5F       bit     3,a         ; is joystick pushed down ?
1B3D: C2 F2 1C    jp      nz,$1cf2    ; yes, skip ahead to handle

1B40: 3A 15 62    ld      a,(ladder_status_6215)   ; load A with ladder status
1B43: A7          and     a           ; is mario on a ladder?
1B44: C8          ret     z           ; no, return

1B45: 3A 10 60    ld      a,(inputstate_6010) ; load A with input
1B48: CB 57       bit     2,a         ; is joystick pushed up ?
1B4A: C2 03 1D    jp      nz,$1d03    ; yes, skip ahead to handle

1B4D: C9          ret                 ; else return

; mario is next to bottom of ladder

1B4E: 2C          inc     l           ; next HL := #621B
1B4F: 70          ld      (hl),b      ; store B
1B50: 2C          inc     l           ; next HL := #621C
1B51: 72          ld      (hl),d      ; store D
1B52: C3 45 1B    jp      $1b45       ; loop back

1B55: 21 1E 62    ld      hl,jump_coming_down_indicator_621e    ; load HL with jump coming down indicator
1B58: 35          dec     (hl)        ; decrease.  is it zero ?
1B59: C0          ret     nz          ; no, return

; arrive here when jump is complete

1B5A: 3A 18 62    ld      a,(mario_is_grabbing_the_hammer_until_he_lands_6218)   ; load A with hammer grabbing indicator
1B5D: 32 17 62    ld      (unknown_6217),a   ; store into hammer indicator
1B60: 21 07 62    ld      hl,mario_movement_indicator_sprite_value_6207    ; load HL with movement indicator address
1B63: 7E          ld      a,(hl)      ; load A with movement indicator
1B64: E6 80       and     $80         ; mask bits.  we only care about bit 7, which we leave as is.  all other bits are now zero
1B66: 77          ld      (hl),a      ; store into movement indicator.  mario is no longer jumping
1B67: AF          xor     a           ; A := 0
1B68: 32 02 62    ld      (put_back_6202),a   ; set mario animation state to 0
1B6B: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; jump initiated.  arrive from #1AE3 when jump pressed and jump not already underway etc.

1B6E: 3E 01       ld      a,$01       ; A := 1
1B70: 32 16 62    ld      (jumping_status_6216),a   ; set jump indicator
1B73: 21 10 62    ld      hl,mario_jump_direction_6210    ; load HL with mario's jump direction address
1B76: 3A 10 60    ld      a,(inputstate_6010) ; load A with copy of input
1B79: 01 80 00    ld      bc,$0080    ; B:= 0, C := #80 = codes for jumping right
1B7C: 1F          rra                 ; rotate input right.  is joystick moved right ?
1B7D: DA 8A 1B    jp      c,$1b8a     ; yes, skip ahead

; jumping left or straight up

1B80: 01 80 FF    ld      bc,$ff80    ; B := #FF, C := #80 = codes for jumping left
1B83: 1F          rra                 ; rotate right again.  jumping to the left ?
1B84: DA 8A 1B    jp      c,$1b8a     ; yes, skip next step

; else jumping straight up

1B87: 01 00 00    ld      bc,$0000    ; B := 0, C := 0 = codes for jumping straight up

1B8A: AF          xor     a           ; A := 0
1B8B: 70          ld      (hl),b      ; store B into #6210 = jump direction (0 = right, #FF = left, 0 = up)
1B8C: 2C          inc     l           ; HL := #6211
1B8D: 71          ld      (hl),c      ; store C into jump direction indicator (#80 for left or right, 0 for up)
1B8E: 2C          inc     l           ; HL := #6212
1B8F: 36 01       ld      (hl),$01    ; store 1 into this indicator ???
1B91: 2C          inc     l           ; HL := #6213
1B92: 36 48       ld      (hl),$48
1B94: 2C          inc     l           ; HL := #6214 (jump counter)
1B95: 77          ld      (hl),a      ; clear jump counter
1B96: 32 04 62    ld      (unknown_6204),a
1B99: 32 06 62    ld      (unknown_6206),a
1B9C: 3A 07 62    ld      a,(mario_movement_indicator_sprite_value_6207)   ; load movement indicator
1B9F: E6 80       and     $80         ; clear right 4 bits and leftmost bit
1BA1: F6 0E       or      $0e         ; set right bits to E = 1110
1BA3: 32 07 62    ld      (mario_movement_indicator_sprite_value_6207),a   ; set jumping bits to indicate a jump in progress
1BA6: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
1BA9: 32 0E 62    ld      (unknown_620e),a   ; save mario's Y position when jump
1BAC: 21 81 60    ld      hl,sound_buffer_address_for_jumping_6081    ; load HL with sound buffer address for jumping
1BAF: 36 03       ld      (hl),$03    ; load sound buffer jumping sound for 3 units (3 frames?)
1BB1: C9          ret                 ; return to main routine (#1983)

; arrive here when mario is already jumping from #1AC7

1BB2: DD 21 00 62 ld      ix,mario_array_6200    ; load IX with start of array for mario
1BB6: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
1BB9: DD 77 0B    ld      (ix+$0b),a  ; store into +B
1BBC: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
1BBF: DD 77 0C    ld      (ix+$0c),a  ; store into +C = #620C = jump height
1BC2: CD 9C 23    call    $239c       ; handle jump stuff ?
1BC5: CD 1F 24    call    $241f       ; loads DE with something depending on mario's position
1BC8: 15          dec     d           ; D == 1 ?
1BC9: C2 F2 1B    jp      nz,$1bf2    ; no, skip ahead

; bounce mario off left side wall ?

1BCC: DD 36 10 00 ld      (ix+$10),$00; clear jump direction
1BD0: DD 36 11 80 ld      (ix+$11),$80; set +11 indicator to #80 (???)
1BD4: DD CB 07 FE set     7,(ix+$07)  ; set bit 7 of +7 = sprite used = make mario face the other way

1BD8: 3A 20 62    ld      a,(falling_too_far_indicator_6220)   ; load A with falling too far indicator
1BDB: 3D          dec     a           ; == 1 ? (falling too far?)
1BDC: CA EC 1B    jp      z,$1bec     ; yes, skip ahead

1BDF: CD 07 24    call    $2407       ; ???
1BE2: DD 74 12    ld      (ix+$12),h
1BE5: DD 75 13    ld      (ix+$13),l
1BE8: DD 36 14 00 ld      (ix+$14),$00; clear the +14 indicator (???)

1BEC: CD 9C 23    call    $239c       ; ???
1BEF: C3 05 1C    jp      $1c05       ; skip ahead

1BF2: 1D          dec     e           ; decrease E.  at zero ?
1BF3: C2 05 1C    jp      nz,$1c05    ; no, skip ahead

; bounce mario off right side wall ?

1BF6: DD 36 10 FF ld      (ix+$10),$ff; set jump direction to left
1BFA: DD 36 11 80 ld      (ix+$11),$80; set +11 indicator to #80
1BFE: DD CB 07 BE res     7,(ix+$07)  ; reset bit 7 of +7 = sprite used = makes mario face the other way
1C02: C3 D8 1B    jp      $1bd8       ; jump back to program

1C05: CD 1C 2B    call    $2b1c       ; do stuff for jumping, load A with landing indicator ?
1C08: 3D          dec     a           ; decrease A.  mario landing ?
1C09: CA 3A 1C    jp      z,$1c3a     ; yes, skip ahead to handle

1C0C: 3A 1F 62    ld      a,(mario_jump_apex_621f)   ; else load A with #621F = 1 when mario is at apex or on way down after jump, 0 otherwise.
1C0F: 3D          dec     a           ; decrease A.  at zero ?  is mario at apex or on way down ?
1C10: CA 76 1C    jp      z,$1c76     ; yes, skip ahead

1C13: 3A 14 62    ld      a,(jump_counter_6214)   ; load A with jump counter
1C16: D6 14       sub     $14         ; == #14 ? (apex of jump)
1C18: C2 33 1C    jp      nz,$1c33    ; no, skip ahead

; mario at apex of jump ?

1C1B: 3E 01       ld      a,$01       ; A := 1
1C1D: 32 1F 62    ld      (mario_jump_apex_621f),a   ; store into #621F = 1 when mario is at apex or on way down after jump, 0 otherwise.
1C20: CD 53 28    call    $2853       ; check for items under mario
1C23: A7          and     a           ; was an item jumped?
1C24: CA A6 1D    jp      z,$1da6     ; no, jump ahead to update mario sprite and RET

; an item was jumped

1C27: 32 42 63    ld      (scoring_indicator_6342),a   ; yes, barrel has been jumped, set for later use
1C2A: 3E 01       ld      a,$01       ; A := 1
1C2C: 32 40 63    ld      (bonus_indicator_6340),a   ; store into #6340 - usually 0, changes when mario picks up bonus item. jumps over item turns to 1 quickly, then 2 until bonus disappears
1C2F: 32 25 62    ld      (bonus_sound_indicator_6225),a   ; store into bonus sound indicator

1C32: 00          nop                 ; No operation [what was here ???]

; can arrive from #1C18

1C33: 3C          inc     a           ; increase A.  Will turn to zero 1 pixel before apex of jump
1C34: CC 54 29    call    z,$2954     ; if zero, call this sub to check for hammer grab

1C37: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; arrive here when mario lands.  B is preloaded with a parameter

1C3A: 05          dec     b           ; B == 1 ?
1C3B: CA 4F 1C    jp      z,$1c4f     ; if so, skip ahead

1C3E: 3C          inc     a           ; increase A
1C3F: 32 1F 62    ld      (mario_jump_apex_621f),a   ; store into #621F = 1 when mario is at apex or on way down after jump, 0 otherwise.
1C42: AF          xor     a           ; A := 0
1C43: 21 10 62    ld      hl,mario_jump_direction_6210    ; load HL with jump direction
1C46: 06 05       ld      b,$05       ; for B := 1 to 5

1C48: 77          ld      (hl),a      ; clear this memory (jump direction, etc)
1C49: 2C          inc     l           ; next HL
1C4A: 10 FC       djnz    $1c48       ; next B

1C4C: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; jump almost complete ...

1C4F: 32 16 62    ld      (jumping_status_6216),a   ; store A into jump indicator
1C52: 3A 20 62    ld      a,(falling_too_far_indicator_6220)   ; load A with falling too far indicator
1C55: EE 01       xor     $01         ; toggle rightmost bit [ change to LD A, #01 to enable infinite falling without death]
1C57: 32 00 62    ld      (mario_array_6200),a   ; store into mario life indicator.  if mario fell too far, he will die.
1C5A: 21 07 62    ld      hl,mario_movement_indicator_sprite_value_6207    ; load HL with address of movement indicator
1C5D: 7E          ld      a,(hl)      ; load A with movement indicator
1C5E: E6 80       and     $80         ; maks bits, leave bit 7 as is.  all other bits are zeroed.
1C60: F6 0F       or      $0f         ; turn on all 4 low bits
1C62: 77          ld      (hl),a      ; store result into movement indicator
1C63: 3E 04       ld      a,$04       ; A := 4
1C65: 32 1E 62    ld      (jump_coming_down_indicator_621e),a   ; store into jump coming down indicator
1C68: AF          xor     a           ; A := 0
1C69: 32 1F 62    ld      (mario_jump_apex_621f),a   ; store into #621F = 1 when mario is at apex or on way down after jump, 0 otherwise.
1C6C: 3A 25 62    ld      a,(bonus_sound_indicator_6225)   ; load A with bonus sound indicator
1C6F: 3D          dec     a           ; was a bonus awarded?
1C70: CC 95 1D    call    z,$1d95     ; yes, call this sub to play bonus sound

1C73: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; mario is on way down from jump or falling

1C76: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
1C79: 21 0E 62    ld      hl,unknown_620e    ; load HL with mario original Y position ?
1C7C: D6 0F       sub     $0f         ; subtract #F
1C7E: BE          cp      (hl)        ; compare.  is mario falling too far ?
1C7F: DA A6 1D    jp      c,$1da6     ; no, jump ahead to update mario sprite and RET

; mario falling too far on a jump

1C82: 3E 01       ld      a,$01       ; A := 1
1C84: 32 20 62    ld      (falling_too_far_indicator_6220),a   ; store into falling too far indicator
1C87: 21 84 60    ld      hl,play_sound_for_falling_bouncer_6084    ; load HL with address for falling sound
1C8A: 36 03       ld      (hl),$03    ; play falling sound for 3 units
1C8C: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; arrive here when joystick is being pressed right

1C8F: 06 01       ld      b,$01       ; B := 1 = movement to right
1C91: 3A 0F 62    ld      a,(address_of_movement_indicator_620f)   ; load A with movement indicator
1C94: A7          and     a           ; time to move mario ?
1C95: C2 D2 1C    jp      nz,$1cd2    ; yes, jump ahead

1C98: 3A 02 62    ld      a,(put_back_6202)   ; varies from 0, 2, 4, 1 when mario is walking left or right
1C9B: 47          ld      b,a         ; copy into B. this is used in sub at #3009 called below
1C9C: 3E 05       ld      a,$05       ; A := 5
1C9E: CD 09 30    call    $3009       ; ??? change A depending on where mario is?
1CA1: 32 02 62    ld      (put_back_6202),a   ; put back
1CA4: E6 03       and     $03         ; mask bits, now between 0 and 3
1CA6: F6 80       or      $80         ; turn on bit 7
1CA8: C3 C2 1C    jp      $1cc2       ; skip ahead

; arrive here when joystick is being pressed left

1CAB: 06 FF       ld      b,$ff       ; B := #FF = -1 (movement to left)
1CAD: 3A 0F 62    ld      a,(address_of_movement_indicator_620f)   ; load A with movement indicator
1CB0: A7          and     a           ; time to move mario?
1CB1: C2 D2 1C    jp      nz,$1cd2    ; yes, skip ahead and move mario

1CB4: 3A 02 62    ld      a,(put_back_6202)   ; varies from 0, 2, 4, 1 when mario is walking left or right
1CB7: 47          ld      b,a         ; copy to B.  this is used in sub at #3009 called below
1CB8: 3E 01       ld      a,$01       ; A := 1
1CBA: CD 09 30    call    $3009       ; ??? change A depending on where mario is?
1CBD: 32 02 62    ld      (put_back_6202),a   ; put back
1CC0: E6 03       and     $03         ; mask bits. now between 0 and 3

1CC2: 21 07 62    ld      hl,mario_movement_indicator_sprite_value_6207    ; load HL with mario movement indicator/sprite value
1CC5: 77          ld      (hl),a      ; store A into this
1CC6: 1F          rra                 ; rotate right.  is A odd?
1CC7: DC 8F 1D    call    c,$1d8f     ; yes , skip ahead to start walking sound and RET

1CCA: 3E 02       ld      a,$02       ; A := 2
1CCC: 32 0F 62    ld      (address_of_movement_indicator_620f),a   ; store into movement indicator (reset)
1CCF: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

1CD2: 21 03 62    ld      hl,jump_if_bit_7_of_mario_x_position_is_set_6203    ; load HL with mario X position address
1CD5: 7E          ld      a,(hl)      ; load A with mario X position
1CD6: 80          add     a,b         ; add movement (either 1 or #FF)
1CD7: 77          ld      (hl),a      ; store new result
1Cd8: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
1Cdb: 3D          dec     a           ; are we on the girders?
1Cdc: c2 Eb 1C    jp      nz,$1ceb    ; no, skip ahead

1Cdf: 66          ld      h,(hl)      ; else load H with mario X position
1Ce0: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario Y position
1Ce3: 6f          ld      l,a         ; copy to L.  HL now has mario X,Y
1Ce4: cd 33 23    call    $2333       ; check for movement up/down a girder, might also change Y position ?
1Ce7: 7D          ld      a,l         ; load A with new Y position
1Ce8: 32 05 62    ld      (return_without_taking_the_ladder_6205),a   ; store into Y position

1CEB: 21 0F 62    ld      hl,address_of_movement_indicator_620f    ; load HL with address of movement indicator
1CEE: 35          dec     (hl)        ; decrease movement indicator
1CEF: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; mario moving down on a ladder
; jump here from #1B3D

1CF2: 3A 0F 62    ld      a,(address_of_movement_indicator_620f)   ; load A with movmement indicator (from 3 to 0)
1CF5: A7          and     a           ; == 0 ?
1CF6: C2 8A 1D    jp      nz,$1d8a    ; no, skip ahead, decrease indicator and return

; ok for mario to move

1CF9: 3E 03       ld      a,$03       ; A := 3
1CFB: 32 0F 62    ld      (address_of_movement_indicator_620f),a   ; reset movement indicator to 3
1CFE: 3E 02       ld      a,$02       ; A := 2 pixels to move down
1D00: C3 11 1D    jp      $1d11       ; skip ahead

; mario moving up on a ladder
; jump here from #1B4A

1D03: 3A 0F 62    ld      a,(address_of_movement_indicator_620f)   ; load A with movement indicator (from 4 to 0)
1D06: A7          and     a           ; time to move mario ?
1D07: C2 76 1D    jp      nz,$1d76    ; no, skip ahead

1D0A: 3E 04       ld      a,$04       ; A := 4
1D0C: 32 0F 62    ld      (address_of_movement_indicator_620f),a   ; reset movement indicator to 4 (slower movement going up)
1D0F: 3E FE       ld      a,$fe       ; A := #FE = -2 pixels movement

1D11: 21 05 62    ld      hl,return_without_taking_the_ladder_6205    ; load HL with mario Y position address
1D14: 86          add     a,(hl)      ; add A to Y position
1D15: 77          ld      (hl),a      ; store result into Y position
1D16: 47          ld      b,a         ; copy to B
1D17: 3A 22 62    ld      a,(ladder_toggle_6222)   ; load A with ladder toggle
1D1A: EE 01       xor     $01         ; toggle the bit
1D1C: 32 22 62    ld      (ladder_toggle_6222),a   ; store.  is it zero?
1D1F: C2 51 1D    jp      nz,$1d51    ; no, skip ahead

1D22: 78          ld      a,b         ; A := B =  mario Y position
1D23: C6 08       add     a,$08       ; add 8 [offset for mario's actual position ???]
1D25: 21 1C 62    ld      hl,y_value_of_top_of_ladder_621c    ; load HL with Y value of top of ladder
1D28: BE          cp      (hl)        ; is mario at top of ladder ?
1D29: CA 67 1D    jp      z,$1d67     ; yes, skip ahead to handle

1D2C: 2D          dec     l           ; HL := #621B = Y value of bottom of ladder
1D2D: 96          sub     (hl)        ; is mario at bottom of ladder ?
1D2E: CA 67 1D    jp      z,$1d67     ; yes, skip ahead to handle

1D31: 06 05       ld      b,$05       ; B := 5
1D33: D6 08       sub     $08         ; subtract 8.  zero?
1D35: CA 3F 1D    jp      z,$1d3f     ; yes, skip next 4 steps

1D38: 05          dec     b           ; B := 4
1D39: D6 04       sub     $04         ; subtract 4.  zero?
1D3B: CA 3F 1D    jp      z,$1d3f     ; yes, skip next step

1D3E: 05          dec     b           ; B := 3

1D3F: 3E 80       ld      a,$80       ; A := #80
1D41: 21 07 62    ld      hl,mario_movement_indicator_sprite_value_6207    ; load HL with address of mario movement indicator/sprite value
1D44: A6          and     (hl)        ; mask bits with movement
1D45: EE 80       xor     $80         ; toggle bit 7
1D47: B0          or      b           ; turn on bits based on ladder position
1D48: 77          ld      (hl),a      ; store into mario movement indicator/sprite value

1D49: 3E 01       ld      a,$01       ; A := 1
1D4B: 32 15 62    ld      (ladder_status_6215),a   ; store into ladder status.  mario is on a ladder now
1D4E: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

1D51: 2D          dec     l
1D52: 2D          dec     l           ; HL := #6203
1D53: 7E          ld      a,(hl)      ; load A with mario sprite value
1D54: F6 03       or      $03         ; turn on bits 0 and 1
1D56: CB 97       res     2,a         ; clear bit 2
1D58: 77          ld      (hl),a      ; store into mario sprite
1D59: 3A 24 62    ld      a,(store_result_6224)   ; load A with sound alternator
1D5C: EE 01       xor     $01         ; toggle bit 0
1D5E: 32 24 62    ld      (store_result_6224),a   ; store result
1D61: CC 8F 1D    call    z,$1d8f     ; if zero, play walking sound for moving on ladder

1D64: C3 49 1D    jp      $1d49       ; jump back

; arrive from #1D29 when mario at top or bottom of ladder

1D67: 3E 06       ld      a,$06       ; A := 6
1D69: 32 07 62    ld      (mario_movement_indicator_sprite_value_6207),a   ; store into mario movement indicator/sprite value
1D6C: AF          xor     a           ; A := 0
1D6D: 32 19 62    ld      (store_1_into_status_indicator_6219),a   ; clear this status indicator
1D70: 32 15 62    ld      (ladder_status_6215),a   ; clear ladder status.  mario no longer on ladder
1D73: C3 A6 1D    jp      $1da6       ; jump ahead to update mario sprite and RET

; jump here from #1D07 when going up a ladder but not actually moving

1D76: 3A 1A 62    ld      a,(moving_ladder_indicator_621a)   ; load A with this indicator.  set when mario is on moving ladder or broken ladder
1D79: A7          and     a           ; is mario boarding or on a retracting or broken ladder?
1D7A: CA 8A 1D    jp      z,$1d8a     ; no, skip ahead

; mario on or moving onto a rectracting or broken ladder

1D7D: 32 19 62    ld      (store_1_into_status_indicator_6219),a   ; store 1 into status indicator
1D80: 3A 1C 62    ld      a,(y_value_of_top_of_ladder_621c)   ; load A with Y value of top of ladder
1D83: D6 13       sub     $13         ; subtract #13
1D85: 21 05 62    ld      hl,return_without_taking_the_ladder_6205    ; load HL with mario Y position address
1D88: BE          cp      (hl)        ; is mario at or above the top of ladder ?
1D89: D0          ret     nc          ; yes, return without changing movement

1D8A: 21 0F 62    ld      hl,address_of_movement_indicator_620f    ; else load HL with address of movement indicator
1D8D: 35          dec     (hl)        ; decrease
1D8E: C9          ret                 ; return

; mario is walking

1D8F: 3E 03       ld      a,$03       ; load sound duration of 3 for walking
1D91: 32 80 60    ld      (walking_sound_buffer_6080),a   ; store into walking sound buffer
1D94: C9          ret                 ; return

; arrive here when walking over a rivet, not jumping.  from #1AB9, or from #1C70

1D95: 32 25 62    ld      (bonus_sound_indicator_6225),a   ; store A into bonus sound indicator.  A is zero so this clears the indicator
1D98: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
1D9B: 3D          dec     a           ; is this the girders?
1D9C: C8          ret     z           ; yes , then return, we don't play this sound for the girders

; play bonus sound

1D9D: 21 8A 60    ld      hl,sound_buffer_address_608a    ; else load HL with sound address
1DA0: 36 0D       ld      (hl),$0d    ; play bonus sound
1DA2: 2C          inc     l           ; HL := #608B = sound duration
1DA3: 36 03       ld      (hl),$03    ; set sound duration to 3
1DA5: C9          ret                 ; return

; update mario sprite

1DA6: 21 4C 69    ld      hl,mario_sprite_x_position_694c    ; load HL with mario sprite X position
1DA9: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
1DAC: 77          ld      (hl),a      ; store into hardware sprite mario X position
1DAD: 3A 07 62    ld      a,(mario_movement_indicator_sprite_value_6207)   ; load A with movement indicator
1DB0: 2C          inc     l           ; HL := #694D = hardware mario sprite
1DB1: 77          ld      (hl),a      ; store into hardware mario sprite value
1DB2: 3A 08 62    ld      a,(mario_color_6208)   ; load A with mario color
1DB5: 2C          inc     l           ; HL := #694E = hardware mario sprite color
1DB6: 77          ld      (hl),a      ; store into mario sprite color
1DB7: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario Y position
1DBA: 2C          inc     l           ; HL := #694F = mario sprite Y position
1DBB: 77          ld      (hl),a      ; store into mario sprite Y position
1DBC: C9          ret                 ; return


; called from main routine at #197A
; also called from other areas


1DBD: 3A 40 63    ld      a,(bonus_indicator_6340)   ; load A with #6340 - usually 0, changes when mario picks up bonus item. jumps over item turns to 1 quickly, then 2 until bonus disappears
1DC0: EF          rst     $28         ; jump based on A

1DC1  49 1E                             ; #1E49 = no item.  returns immediately
1DC3  C9 1D                             ; #1DC9 = item just picked up
1DC5  4A 1E                             ; #1E4A = bonus appears
1DC7  00 00                             ; unused

; an item was just picked up / jumped over / hit with hammer

1DC9: 3E 40       ld      a,$40       ; A := #40
1DCB: 32 41 63    ld      (timer_6341),a   ; store into timer
1DCE: 3E 02       ld      a,$02       ; A := 2
1DD0: 32 40 63    ld      (bonus_indicator_6340),a   ; store into #6340 - usually 0, changes when mario picks up bonus item. jumps over item turns to 1 quickly, then 2 until bonus disappears
1DD3: 3A 42 63    ld      a,(scoring_indicator_6342)   ; load A with scoring indicator
1DD6: 1F          rra                 ; roll right.  is this a jumped item?
1DD7: DA 70 3E    jp      c,$3e70     ; yes, award points for jumping items [ patch ? orig code had JP C,#1E25 ??? ]

1DDA: 1F          rra                 ; else roll right
1DDB: DA 00 1E    jp      c,$1e00     ; award for hitting regular barrel with hammer

1DDE: 1F          rra                 ; roll right.  hit blue barrel with hammer?
1DDF: DA F5 1D    jp      c,$1df5     ; yes, skip ahead to handle

; else it was a bonus item pickup

1DE2: 21 85 60    ld      hl,play_sound_for_bonus_6085    ; else load HL with bonus sound address
1DE5: 36 03       ld      (hl),$03    ; play bonus sound for 3 duration
1DE7: 3A 29 62    ld      a,(level_number_6229)   ; load A with level #
1DEA: 3D          dec     a           ; decrease A.  is this level 1 ?
1DEB: cA 00 1E    jp      z,$1e00     ; yes, jump ahead for 300 pts

1DEE: 3D          dec     a           ; else is this level 2 ?
1DEF: CA 08 1E    jp      z,$1e08     ; yes, award 500 pts

1DF2: C3 10 1E    jp      $1e10       ; else award 800 pts

; blue barrel hit with hammer

1DF5: 3A 18 60    ld      a,(rngtimer1_6018) ; load timer, a psuedo random number
1DF8: 1F          rra                 ; roll right = 50% chance of 500 points
1DF9: DA 08 1E    jp      c,$1e08     ; award 500 points

1DFC: 1F          rra                 ; roll right again, gives overall 25% chance of 800 points
1DFD: DA 10 1E    jp      c,$1e10     ; award 800 points

; else award 300 points

1E00: 06 7D       ld      b,$7d       ; set sprite for 300 points
1E02: 11 03 00    ld      de,$0003    ; set points at 300
1E05: c3 15 1E    jp      $1e15       ; award points

; award 500 pts

1E08: 06 7E       ld      b,$7e       ; set sprite for 500 points
1E0A: 11 05 00    ld      de,$0005    ; set points at 500
1E0D: C3 15 1E    jp      $1e15       ; award points

; award 800 pts

1E10: 06 7f       ld      b,$7f       ; set sprite for 800 points
1E12: 11 08 00    ld      de,$0008    ; set points at 800

1E15: cd 9f 30    call    $309f       ; insert task to add score

; arrive here when bonus item picked up or smashed with hammer

1E18: 2A 43 63    ld      hl,(unknown_for_use_later_6343)  ; load HL with contents of #6343 , this gives the address of the sprite location
1E1B: 7E          ld      a,(hl)      ; load A with the X position of the sprite in question
1E1C: 36 00       ld      (hl),$00    ; clear the sprite from the screen
1E1E: 2C          inc     l           ; increase L 3 times
1E1F: 2C          inc     l
1E20: 2C          inc     l
1E21: 4E          ld      c,(hl)      ; load C with the Y position of the item
1E22: c3 36 1E    jp      $1e36       ; jump ahead


1E25: 11 01 00    ld      de,$0001    ; load task for scoring, 100 pts [ never arrive at this line ??? possibly orig code came from #1DD7 ]

; arrive when barrel has been jumped for points from #3E70 range
; DE is preloaded with task for scoring 100, 300, or 500 pts [bug, should be 800 pts]


        ; award points for jumping a barrels and items
        ; arrive from #1DD7
        ; A is preloaded with 1,3, or 7
        ; patch ?

;        3E70  110100    LD      DE,#0001        ; 100 points
;        3E73  067B      LD      B,#7B           ; sprite for 100
;        3E75  1F        RRA                     ; is the score set for 100 ?
;        3E76  D2281E    JP      NC,#1E28        ; yes, award points
;
;        3E79  1E03      LD      E,#03           ; else set 300 points
;        3E7B  067D      LD      B,#7D           ; sprite for 300
;        3E7D  1F        RRA                     ; is the score set for 300 ?
;        3E7E  D2281E    JP      NC,#1E28        ; yes, award points
;
;        3E81  1E05      LD      E,#05           ; else set 500 points [bug, should be 800]
;        3E83  067F      LD      B,#7F           ; sprite for 800
;        3E85  C3281E    JP      #1E28           ; award points

1E28: CD 9F 30    call    $309f       ; insert task to add score
1E2B: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
1E2E: C6 14       add     a,$14       ; add #14
1E30: 4F          ld      c,a         ; store into C
1E31: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position

1E34: 00          nop
1E35: 00          nop                 ; [ what used to be here?  was it LD B,#7B to set sprite for 100 pts? ]

; draw the bonus score on the screen

1E36: 21 30 6A    ld      hl,unknown_6a30    ; load HL with scoring sprite start
1E39: 77          ld      (hl),a      ; store X position
1E3A: 2C          inc     l           ; next location
1E3B: 70          ld      (hl),b      ; store sprite graphic
1E3C: 2C          inc     l           ; next
1E3D: 36 07       ld      (hl),$07    ; store color code 7
1E3F: 2C          inc     l           ; next
1E40: 71          ld      (hl),c      ; store Y position
1E41: 3E 05       ld      a,$05       ; A := 5 = binary 0101
1E43: F7          rst     $30         ; only allow continue on girders and elevators, others do RET here [no bonus sound for killing firefox with hammer]
1E44: 21 85 60    ld      hl,play_sound_for_bonus_6085    ; load HL with bonus sound address
1E47: 36 03       ld      (hl),$03    ; play bonus sound for 3 duration
1E49: C9          ret                 ; return

; arrive here from #1DC0 when bonus appears

1E4A: 21 41 63    ld      hl,timer_6341    ; load HL with timer
1E4D: 35          dec     (hl)        ; has it run out yet ?
1E4E: C0          ret     nz          ; no, return

1E4F: AF          xor     a           ; else A := 0
1E50: 32 30 6A    ld      (unknown_6a30),a   ; clear this
1E53: 32 40 63    ld      (bonus_indicator_6340),a   ; clear this
1E56: C9          ret                 ; return

; called from main routine at #19B9
; checks for end of level ?

1E57: 3A 27 62    ld      a,(screen_number_6227)   ; load a with screen number
1E5A: cb 57       bit     2,a         ; are we on the rivets?
1E5C: c2 80 1E    jp      nz,$1e80    ; yes, skip ahead to handle

1E5f: 1F          rra                 ; else rotate right with carry
1E60: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with y position of mario
1E63: dA 7A 1E    jp      c,$1e7a     ; skip ahead on girders and elevators

1E66: fe 51       cp      $51         ; else on the conveyors.  is mario high enough to end level?
1E68: d0          ret     nc          ; no, return

1E69: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; else load A with mario's X position
1E6C: 17          rla                 ; on left or right side of screen?

1E6D: 3E 00       ld      a,$00       ; load A with #00.  sprite for facing left
1E6F: DA 74 1E    jp      c,$1e74     ; if on left side, skip next step

1E72: 3E 80       ld      a,$80       ; else load A with sprite facing right
1E74: 32 4D 69    ld      (mario_sprite_value_694d),a   ; set mario sprite
1E77: C3 85 1E    jp      $1e85       ; jump ahead

; check for end of level on girders and elevators

1E7A: FE 31       cp      $31         ; are we on top level (rescued girl?)
1E7C: D0          ret     nc          ; no, return

1E7D: C3 6D 1E    jp      $1e6d       ; level has been fished.  jump to end of level routine.

; arrive here when on rivets

1E80: 3A 90 62    ld      a,(number_of_rivets_left_6290)   ; load A with number of rivets left
1E83: A7          and     a           ; all done with rivets ?
1E84: C0          ret     nz          ; no, return

1E85: 3E 16       ld      a,$16       ; else A := #16
1E87: 32 0A 60    ld      (gamemode2_600a),a; store into game mode2
1E8A: E1          pop     hl          ; pop stack to get higher address
1E8B: C9          ret                 ; return to a higher level [returns to #00D2]

; called from main routine at #197D
; handles items hit with hammer

1E8C: 3A 50 63    ld      a,(item_hit_indicator_unknown_6350)   ; load A with hammer hit item indicator
1E8F: A7          and     a           ; is an item being smashed ?
1E90: C8          ret     z           ; no, return

1E91: CD 96 1E    call    $1e96       ; else call sub below
1E94: E1          pop     hl          ; then return to a higher sub
1E95: C9          ret                 ; returns to #00D2

1E96: 3A 45 63    ld      a,(item_hit_phase_counter_address_6345)   ; load A with this

; #6345 - usually 0.  changes to 1, then 2 when items are hit with the hammer

1E99: EF          rst     $28         ; jump based on A

1E9A  A0 1E                     0       ; #1EA0
1E9C  09 1F                     1       ; #1F09
1E9E  23 1F                     2       ; #1F23

; arrive right when an item is hit

1EA0: 3A 52 63    ld      a,(unknown_6352)   ; load A with ???
1EA3: FE 65       cp      $65         ; == #65 ?
1EA5: 21 B8 69    ld      hl,start_of_pie_sprites_69b8    ; load HL with sprites for pies
1EA8: CA B4 1E    jp      z,$1eb4     ; yes, skip next 3 steps

1EAB: 21 D0 69    ld      hl,start_of_firefox_sprites_69d0    ; load HL with start of fire sprites ???
1EAE: DA B4 1E    jp      c,$1eb4     ; if carry, then skip next step

1EB1: 21 80 69    ld      hl,start_of_sprite_memory_for_bouncers_6980    ; HL is X position of a barrel

1EB4: DD 2A 51 63 ld      ix,(unknown_6351)  ; load IX with start of item array for the item hit
1EB8: 16 00       ld      d,$00       ; D := 0
1EBA: 3A 53 63    ld      a,(unknown_6353)   ; load A with the offset for each item in the array
1EBD: 5F          ld      e,a         ; copy to E.  DE now has the offset
1EBE: 01 04 00    ld      bc,$0004    ; BC := 4
1EC1: 3A 54 63    ld      a,(unknown_6354)   ; load A with the index of the item hit
1EC4: A7          and     a           ; == 0 ?
1EC5: CA CF 1E    jp      z,$1ecf     ; yes, skip ahead, we use the default HL and IX

1EC8: 09          add     hl,bc       ; add offset
1EC9: DD 19       add     ix,de       ; add offset
1ECB: 3D          dec     a           ; decrease counter.  done ?
1ECC: C2 C8 1E    jp      nz,$1ec8    ; no, loop again

1ECF: DD 36 00 00 ld      (ix+$00),$00; set this sprite as no longer active
1ED3: DD 7E 15    ld      a,(ix+$15)  ; load A with +15 (0 = normal barrel,  1 = blue barrel, see next comments)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; It turns out that IX+15 is used by firefoxes and fireballs as a counter for their animation
; This value can be 0, 1, or 2 and is updated every frame
;
; For pies, this value is 0, #7C or #CC, because it grabs the +5 slot of the next pie when one is hit
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

1ED6: A7          and     a           ; ==0 ? is this a regular barrel?  (sometimes fires and pies fall here too)
1ED7: 3E 02       ld      a,$02       ; A := 2, used for 300 pts
1ED9: CA DE 1E    jp      z,$1ede     ; yes, skip next step

1EDC: 3E 04       ld      a,$04       ; else A := 4, used for random points (blue barrel, sometimes fire, sometimes pie)

1EDE: 32 42 63    ld      (scoring_indicator_6342),a   ; store A into scoring indicator
1EE1: 01 2C 6A    ld      bc,location_of_item_hit_6a2c    ; load BC with scoring sprite address
1EE4: 7E          ld      a,(hl)      ; load A with sprite value ?
1EE5: 36 00       ld      (hl),$00    ; clear the sprite that was hit
1EE7: 02          ld      (bc),a      ; store sprite value into the scoring sprite
1EE8: 0C          inc     c           ; next
1EE9: 2C          inc     l           ; next
1EEA: 3E 60       ld      a,$60       ; A := #60 = sprite for large bluewhite circle
1EEC: 02          ld      (bc),a      ; store into sprite graphic
1EED: 0C          inc     c           ; next
1EEE: 2C          inc     l           ; next
1EEF: 3E 0C       ld      a,$0c       ; A := #0C = color code
1EF1: 02          ld      (bc),a      ; store into sprite color
1EF2: 0C          inc     c           ; next
1EF3: 2C          inc     l           ; next
1EF4: 7E          ld      a,(hl)      ; load A with Y value for sprite hit
1EF5: 02          ld      (bc),a      ; store into Y value for scoring sprite
1EF6: 21 45 63    ld      hl,item_hit_phase_counter_address_6345    ; load HL with item hit phase counter address

; #6345 - usually 0.  changes to 1, then 2 when items are hit with the hammer
; item has been hit by hammer

1EF9: 34          inc     (hl)        ; increase the item hit phase counter
1EFA: 2C          inc     l           ; HL := #6346 = a timer used for hammering items?
1EFB: 36 06       ld      (hl),$06    ; set timer to 6
1EFD: 2C          inc     l           ; HL := #6347 = counter for number of times to change between circle and small circle
1EFE: 36 05       ld      (hl),$05    ; set to 5
1F00: 21 8A 60    ld      hl,sound_buffer_address_608a    ; load HL with sound buffer address
1F03: 36 06       ld      (hl),$06    ; play sound for hammering object
1F05: 2C          inc     l           ; HL := 608B = sound duration
1F06: 36 03       ld      (hl),$03    ; set duration to 3
1F08: C9          ret                 ; return

; item has been hit by hammer , phase 2 of 3

1F09: 21 46 63    ld      hl,timer_6346    ; load HL with timer
1F0C: 35          dec     (hl)        ; count down.  zero ?
1F0D: C0          ret     nz          ; no, return

1F0E: 36 06       ld      (hl),$06    ; else reset counter to 6
1F10: 2C          inc     l           ; HL := #6347 = counter for this function
1F11: 35          dec     (hl)        ; decrease counter.  zero?
1F12: CA 1D 1F    jp      z,$1f1d     ; yes, skip ahead

1F15: 21 2D 6A    ld      hl,sprite_graphic_6a2d    ; else load HL with scoring sprite graphic
1F18: 7E          ld      a,(hl)      ; get value
1F19: EE 01       xor     $01         ; toggle bit 0 = change sprite to small circle or back again
1F1B: 77          ld      (hl),a      ; store
1F1C: C9          ret                 ; return

1F1D: 36 04       ld      (hl),$04    ; store 4 into #6347 = timer?
1F1F: 2D          dec     l
1F20: 2D          dec     l           ; HL := #6345
1F21: 34          inc     (hl)        ; increase item hit phase counter
1F22: C9          ret                 ; return

; arrive from jump at #1E99 when an item is hit with hammer (last step of 3)

1F23: 21 46 63    ld      hl,timer_6346    ; load HL with timer?
1F26: 35          dec     (hl)        ; count down.  zero ?
1F27: C0          ret     nz          ; no, return

1F28: 36 0C       ld      (hl),$0c    ; reset counter to #C
1F2A: 2C          inc     l           ; HL := #6347 = counter
1F2B: 35          dec     (hl)        ; decrease counter.  zero?
1F2C: CA 34 1F    jp      z,$1f34     ; yes, skip ahead

1F2F: 21 2D 6A    ld      hl,sprite_graphic_6a2d    ; no, load HL with sprite graphic
1F32: 34          inc     (hl)        ; increase
1F33: C9          ret                 ; return

1F34: 2D          dec     l
1F35: 2D          dec     l           ; HL := 6345
1F36: AF          xor     a           ; A := 0
1F37: 77          ld      (hl),a      ; store into HL.  reset the item being hit with hammer
1F38: 32 50 63    ld      (item_hit_indicator_unknown_6350),a   ; store into item hit indicator
1F3B: 3C          inc     a           ; A := 11:18 AM 6/15/2009
1F3C: 32 40 63    ld      (bonus_indicator_6340),a   ; store into bonus indicator
1F3F: 21 2C 6A    ld      hl,location_of_item_hit_6a2c    ; load HL with location of item hit
1F42: 22 43 63    ld      (unknown_for_use_later_6343),hl  ; store into #6343 for use later
1F45: C9          ret                 ; return

; called from main routine at #19A4

1F46: 3A 21 62    ld      a,(mario_falling_indicator_6221)   ; load A with falling indicator.  also set when mario lands from jumping off elevator
1F49: A7          and     a           ; is mario falling?
1F4A: C8          ret     z           ; no, return

; mario is falling

1F4B: AF          xor     a           ; A := 0
1F4C: 32 04 62    ld      (unknown_6204),a
1F4F: 32 06 62    ld      (unknown_6206),a
1F52: 32 21 62    ld      (mario_falling_indicator_6221),a   ; clear mario falling indicator
1F55: 32 10 62    ld      (mario_jump_direction_6210),a   ; clear jump direction
1F58: 32 11 62    ld      (unknown_6211),a
1F5B: 32 12 62    ld      (this_indicator_6212),a   ; clear this indicator (???)
1F5E: 32 13 62    ld      (unknown_6213),a
1F61: 32 14 62    ld      (jump_counter_6214),a   ; clear jump counter
1F64: 3C          inc     a           ; A := 1
1F65: 32 16 62    ld      (jumping_status_6216),a   ; set jump indicator
1F68: 32 1F 62    ld      (mario_jump_apex_621f),a   ; set #621F = 1 when mario is at apex or on way down after jump, 0 otherwise.
1F6B: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with ???
1F6E: 32 0E 62    ld      (unknown_620e),a   ; store into ???
1F71: C9          ret                 ; return

; called from main routine at #1983
; used to roll barrels

1F72: 3A 27 62    ld      a,(screen_number_6227)   ; load a with screen number
1F75: 3D          dec     a           ; is this the girders ?
1F76: c0          ret     nz          ; no, return

; yes, we are on girders
; this subroutine checks the barrels, if any are rolling it does something, otherwise returns

1F77: DD 21 00 67 ld      ix,start_of_barrel_info_table_6700    ; load IX with start of barrel array
1F7B: 21 80 69    ld      hl,start_of_sprite_memory_for_bouncers_6980    ; load HL with start of sprites used for barrels
1F7E: 11 20 00    ld      de,$0020    ; load DE with offset of #20.  used for checking next barrel
1F81: 06 0A       ld      b,$0a       ; for B = 1 to #0A ( do for each barrel)

1F83: DD 7E 00    ld      a,(ix+$00)  ; Load A with Barrel indicator (0 = no barrel, 2 = being deployed, 1=rolling)
1F86: 3D          dec     a           ; Is this barrel rolling ?
1F87: CA 93 1F    jp      z,$1f93     ; Yes, jump ahead

1F8A: 2C          inc     l           ; otherwise increase L by 4
1F8B: 2C          inc     l
1F8C: 2C          inc     l
1F8D: 2C          inc     l
1F8E: DD 19       add     ix,de       ; Add offset to check for next barrel
1F90: 10 F1       djnz    $1f83       ; Next B

1F92: C9          ret                 ; return

1F93: DD 7E 01    ld      a,(ix+$01)  ; Load Crazy Barrel indicator
1F96: 3D          dec     a           ; is this a crazy barrel?
1F97: CA EC 20    jp      z,$20ec     ; Yes, jump ahead

1F9A: DD 7E 02    ld      a,(ix+$02)  ; no load A with next indicator - determines the direction of the barrel
1F9D: 1F          rra                 ; Is this barrel going down a ladder?
1F9E: DA AC 1F    jp      c,$1fac     ; Yes, jump away to ladder sub.

1FA1: 1F          rra                 ; Is this barrel moving right?
1FA2: DA E5 1F    jp      c,$1fe5     ; yes, jump away to move right sub.

1FA5: 1F          rra                 ; is this barrel moving left?
1FA6: DA EF 1F    jp      c,$1fef     ; yes, jump to moving left sub

1FA9: C3 53 20    jp      $2053       ; else jump ahead

; arrived here because the barrel is going down a ladder from #1F9E

1FAC: D9          exx                 ; exchange HL, DE, and BC with their clones
1FAD: DD 34 05    inc     (ix+$05)    ; increase the barrels Y position ( move it down)
1FB0: DD 7E 17    ld      a,(ix+$17)  ; load A with the bottom Y location of the ladder we are on

; #6717 = bottom position of next ladder it is going down or the ladder it just passed.
; ladders bottoms are at :  70, 6A, 93, 8D, 8B, B3, B0, AC, D1, CD, F3, EE

1FB3: DD BE 05    cp      (ix+$05)    ; check against item's Y position.  are we at the bottom of this ladder?
1FB6: C2 CE 1F    jp      nz,$1fce    ; no, jump ahead

; barrel reached bottom of ladder

1FB9: DD 7E 15    ld      a,(ix+$15)  ; load A with Barrel #15 indicator, zero = normal barrel,  1 = blue barrel
1FBC: 07          rlca                ; roll left twice (multiply by 4)
1FBD: 07          rlca
1FBE: C6 15       add     a,$15       ; add #15
1FC0: DD 77 07    ld      (ix+$07),a  ; store into +7 indicator = sprite used

; #6707 - right 2 bits are 01 when rolling, 10 when being deployed.  bit 7 toggles as it rolls

1FC3: DD 7E 02    ld      a,(ix+$02)  ; load A with direction of barrel
1FC6: EE 07       xor     $07         ; XOR right 3 bits - reverses direction ?
1FC8: DD 77 02    ld      (ix+$02),a  ; store back in direction
1FCB: C3 BA 21    jp      $21ba       ; jump ahead

; we arrived here because we are not at the bottom of the ladder
; animates barrel as it rolls down ladder?

1FCE: DD 7E 0F    ld      a,(ix+$0f)  ; load A with barrel #0F counter (from 4 to 1)
1FD1: 3D          dec     a           ; decrement, has it reached 0?
1FD2: C2 DF 1F    jp      nz,$1fdf    ; No, jump ahead, store into counter and continue on

; else animate the barrel

1FD5: DD 7E 07    ld      a,(ix+$07)  ; yes, Load A with #07 indicator = sprite used
1FD8: EE 01       xor     $01         ; toggle bit 1
1FDA: DD 77 07    ld      (ix+$07),a  ; store back in #07 indicator = toggle sprite
1FDD: 3E 04       ld      a,$04       ; A := 4

1FDF: DD 77 0F    ld      (ix+$0f),a  ; store A into barrel #0F counter (from 4 to 1)
1FE2: C3 BA 21    jp      $21ba       ; jump ahead

; we arrived here because the barrel is moving to the right

1FE5: D9          exx                 ; exchange HL, DE, and BC with their clones
1FE6: 01 00 01    ld      bc,$0100    ; BC := #0100
1FE9: DD 34 03    inc     (ix+$03)    ; Increase Barrel's X posiition
1FEC: C3 F6 1F    jp      $1ff6       ; jump ahead

; we arrived here because the barrel is moving to the left

1FEF: D9          exx                 ; exchange HL, DE, and BC with their clones
1FF0: 01 04 FF    ld      bc,$ff04    ; load BC with #FF04
1FF3: DD 35 03    dec     (ix+$03)    ; decrease barrel's X position

; we are here becuase the barrel is moving either left or right

1FF6: DD 66 03    ld      h,(ix+$03)  ; load H with barrel's X position
1FF9: DD 6E 05    ld      l,(ix+$05)  ; load L with barrel's Y position
1FFC: 7C          ld      a,h         ; load A with barrel's X position
1FFD: E6 07       and     $07         ; mask left 5 bits to zero.  result is between 0 and 7
1FFF: FE 03       cp      $03         ; compare with #03
2001: CA 5F 21    jp      z,$215f     ; equal to #03, jump ahead to check for ladders ?

2004: 2D          dec     l           ; otherwise decrease L 3 times
2005: 2D          dec     l
2006: 2D          dec     l
2007: CD 33 23    call    $2333       ; check for barrel going down a slanted girder ?
200A: 2C          inc     l           ; increase L back to what it was
200B: 2C          inc     l
200C: 2C          inc     l
200D: 7D          ld      a,l         ; Load A with Barrel's Y position
200E: DD 77 05    ld      (ix+$05),a  ; store back into barrel's y position
2011: CD DE 23    call    $23de
2014: CD B4 24    call    $24b4
2017: DD 7E 03    ld      a,(ix+$03)  ; Load A with Barrels' X position
201A: FE 1C       cp      $1c         ; have we arrived at left edge of girder?
201C: DA 2F 20    jp      c,$202f     ; yes, jump ahead to handle

201F: FE E4       cp      $e4         ; else , have we arrived at right edge of girder?
2021: DA BA 21    jp      c,$21ba     ; no, jump way ahead - we're done, store values and try next barrel

; right edge of girder

2024: AF          xor     a           ; A := 0
2025: DD 77 10    ld      (ix+$10),a  ; clear #10 barrel index to 0
2028: DD 36 11 60 ld      (ix+$11),$60; store #60 into barrel +#11  , indicates a roll over the right edge
202C: C3 38 20    jp      $2038       ; skip next 3 steps

; arrive here when barrel at left edge of girder

202F: AF          xor     a           ; A := 0
2030: DD 36 10 FF ld      (ix+$10),$ff; Set Barrel #10 index with #FF
2034: DD 36 11 A0 ld      (ix+$11),$a0; set barrel #11 index with #A0 - indicates a roll over left edge

2038: DD 36 12 FF ld      (ix+$12),$ff
203C: DD 36 13 F0 ld      (ix+$13),$f0
2040: DD 77 14    ld      (ix+$14),a
2043: DD 77 0E    ld      (ix+$0e),a  ; clear the barrel's edge indicator
2046: DD 77 04    ld      (ix+$04),a  ; clear ???
2049: DD 77 06    ld      (ix+$06),a
204C: DD 36 02 08 ld      (ix+$02),$08; load barrel properties with various numbers to indicate edge roll?
2050: C3 BA 21    jp      $21ba       ; jump way ahead - we're done, store values and try next barrel

; jump from #1FA9
; we arrive here because the barrel isn't going left, right, or down a ladder
; could be crazy barrel or barrel going over edge

2053: D9          exx                 ; Exchange DE, HL, BC with counterparts
2054: CD 9C 23    call    $239c       ; update barrel position ?
2057: CD 2F 2A    call    $2a2f       ; ???  set A to zero or 1 depending on ???
205A: A7          and     a           ; iS A == 0 ?
205B: C2 83 20    jp      nz,$2083    ; no, jump ahead

205E: DD 7E 03    ld      a,(ix+$03)  ; load A with barrel X position
2061: C6 08       add     a,$08       ; Add #08
2063: FE 10       cp      $10         ; compare with #10
2065: DA 79 20    jp      c,$2079     ; If carry, jump ahead, clear barrel, (rolled off screen?)

2068: CD B4 24    call    $24b4       ; check for barrel running into oil can?
206B: DD 7E 10    ld      a,(ix+$10)  ; load A with +10 = rolling over edge / direction indicator
206E: E6 01       and     $01         ; mask all bits but 1.  result is 0 or 1
2070: 07          rlca                ; rotate left
2071: 07          rlca                ; rotate left again.  result is 0 or 4
2072: 4F          ld      c,a         ; copy into C
2073: CD DE 23    call    $23de       ; ???
2076: C3 BA 21    jp      $21ba       ; skip ahead

2079: AF          xor     a           ; A := 0
207A: DD 77 00    ld      (ix+$00),a  ; clear barrel active indicator
207D: DD 77 03    ld      (ix+$03),a  ; clear barrel X position
2080: C3 BA 21    jp      $21ba       ; done, store values and try next barrel

; barrel has landed on a new girder after going over edge, or has just done so and is bouncing

2083: DD 34 0E    inc     (ix+$0e)    ; increase +E (???)
2086: DD 7E 0E    ld      a,(ix+$0e)  ; load A with this value
2089: 3D          dec     a           ; decrease.  zero? (did this barrel just land???)
208A: CA A2 20    jp      z,$20a2     ; yes, skip ahead

208D: 3D          dec     a           ; else decrease again.  zero?
208E: CA C3 20    jp      z,$20c3     ; yes, skip ahead

; barrel has finsished its edge maneuever

2091: DD 7E 10    ld      a,(ix+$10)  ; else load A with +10 = rolling over edge/direction indicator
2094: 3D          dec     a           ; decrease.  was this value a 1 ?  (barrel moving right)
2095: 3E 04       ld      a,$04       ; A := 4 = rolling left code
2097: C2 9C 20    jp      nz,$209c    ; no, skip next step

209A: 3E 02       ld      a,$02       ; else A := 2

209C: DD 77 02    ld      (ix+$02),a  ; store into motion indicator.  02 = rolling right, 08 = rolling down, 04 = rolling left, bit 1 set when rolling down ladder
209F: C3 BA 21    jp      $21ba       ; jump ahead

; barrel has landed on a new girder after going over edge

20A2: DD 7E 15    ld      a,(ix+$15)  ; load A with Barrel #15 indicator, zero = normal barrel,  1 = blue barrel
20A5: A7          and     a           ; is this a blue barrel?
20A6: C2 B5 20    jp      nz,$20b5    ; yes, skip ahead, blue barrels always continue all the way down

; normal barrel traversed edge

20A9: 21 05 62    ld      hl,return_without_taking_the_ladder_6205    ; load HL with mario's Y position address
20AC: DD 7E 05    ld      a,(ix+$05)  ; load A with +5 = barrel's Y position
20AF: D6 16       sub     $16         ; subtract #16
20B1: BE          cp      (hl)        ; compare to mario Y position.  is the barrel below mario?
20B2: D2 C3 20    jp      nc,$20c3    ; yes, skip next 5 steps

20B5: DD 7E 10    ld      a,(ix+$10)  ; load A with +10 = rolling over edge/direction indicator
20B8: A7          and     a           ; A == 0 ? is this barrel is rolling right?
20B9: C2 E1 20    jp      nz,$20e1    ; no, skip ahead and set alternate values, continue at #20C3

20BC: DD 77 11    ld      (ix+$11),a  ; else set +11 (???) to zero
20BF: DD 36 10 FF ld      (ix+$10),$ff; set +10 = rolling over edge indicator to #FF for rolling left

; barrel has just finished bouncing after going around ledge

20C3: CD 07 24    call    $2407       ; ???
20C6: CB 3C       srl     h
20C8: CB 1D       rr      l
20CA: CB 3C       srl     h
20CC: CB 1D       rr      l
20CE: DD 74 12    ld      (ix+$12),h  ; store H into +#12 (???)
20D1: DD 75 13    ld      (ix+$13),l  ; store L into +#13 (???)
20D4: AF          xor     a           ; A := 0
20D5: DD 77 14    ld      (ix+$14),a  ; clear +#14 (???)
20D8: DD 77 04    ld      (ix+$04),a  ; clear +#4 (???)
20DB: DD 77 06    ld      (ix+$06),a  ; clear +#6 (???)
20DE: C3 BA 21    jp      $21ba       ; skip ahead

20E1: DD 36 10 01 ld      (ix+$10),$01; set +10 = rolling over edge indicator to 1 for rolling right
20E5: DD 36 11 00 ld      (ix+$11),$00; set +11 = ??? to 0
20E9: C3 C3 20    jp      $20c3       ; jump back

; we arrived here because its a crazy barrel from #1F97
; this is called for every pixel the barrel moves

20EC: D9          exx                 ; exchange BC, DE, and HL with their alternates
20ED: CD 9C 23    call    $239c       ; update Barrel's variables ?. H now has +5 and L has +6
20F0: 7C          ld      a,h         ; Load A with H = +5 = Y position
20F1: D6 1A       sub     $1a         ; Subtract #1A (26 decimal)
20F3: DD 46 19    ld      b,(ix+$19)  ; load B with Barrel status #19 (?)
20F6: B8          cp      b           ; compare A with B
20F7: DA 04 21    jp      c,$2104     ; jump on carry ahead

20FA: CD 2F 2A    call    $2a2f       ; else call this sub (???)
20FD: A7          and     a           ; is A == 0 ?
20FE: C2 18 21    jp      nz,$2118    ; No, jump ahead

2101: CD B4 24    call    $24b4       ; else call this sub (???)

2104: DD 7E 03    ld      a,(ix+$03)  ; load A with barrel X position
2107: C6 08       add     a,$08       ; add 8
2109: FE 10       cp      $10         ; result < #10 ?
210B: D2 CE 1F    jp      nc,$1fce    ; No, jump back and ???

210E: AF          xor     a           ; yes, A := 0
210F: DD 77 00    ld      (ix+$00),a  ; set barrel status indicator #0 to 0 (barrel is gone)
2112: DD 77 03    ld      (ix+$03),a  ; set barrel x position to 0
2115: C3 BA 21    jp      $21ba       ; write to sprites and check next barrel

2118: DD 7E 05    ld      a,(ix+$05)  ; load A with barrel's Y position
211B: FE E0       cp      $e0         ; < #E0 ? - are we at bottom of screen?
211D: DA 46 21    jp      c,$2146     ; no, jump ahead

; else this crazy barrel is no longer crazy

2120: DD 7E 07    ld      a,(ix+$07)  ; else Load A with +7 = sprite used
2123: E6 FC       and     $fc         ; clear right 2 bits
2125: F6 01       or      $01         ; turn on bit 0
2127: DD 77 07    ld      (ix+$07),a  ; store result
212A: AF          xor     a           ; A := 0
212B: DD 77 01    ld      (ix+$01),a  ; barrel is no longer crazy
212E: DD 77 02    ld      (ix+$02),a
2131: DD 36 10 FF ld      (ix+$10),$ff; set velocity to -1 (move left)
2135: DD 77 11    ld      (ix+$11),a
2138: DD 77 12    ld      (ix+$12),a
213B: DD 36 13 B0 ld      (ix+$13),$b0
213F: DD 36 0E 01 ld      (ix+$0e),$01
2143: C3 53 21    jp      $2153       ; jump ahead

; arrive here when crazy barrel hits a girder from #211D

2146: CD 07 24    call    $2407       ; load HL based on +14 status. also uses +11 and +12
2149: CD CB 22    call    $22cb       ; do stuff for crazy barrels ?
214C: DD 7E 05    ld      a,(ix+$05)  ; load A with barrel Y position
214F: DD 77 19    ld      (ix+$19),a  ; store in barrel #19 status.  used for crazy barrels?
2152: AF          xor     a           ; A := 0

2153: DD 77 14    ld      (ix+$14),a  ; clear +#14 (???)
2156: DD 77 04    ld      (ix+$04),a  ; clear +#4 (???)
2159: DD 77 06    ld      (ix+$06),a  ; store 0 in these barrel indicators
215C: C3 BA 21    jp      $21ba       ; jump ahead - we're done, store values and try next barrel

; arrive here every 8 pixels moved by barrel from #2001
; L has barrels Y pos
; H has barrels X pos

215F: 7D          ld      a,l         ; load A with barrels Y position

2160: C6 05       add     a,$05       ; add 5
2162: 57          ld      d,a         ; store into D
2163: 7C          ld      a,h         ; load A with barrels X position
2164: 01 15 00    ld      bc,$0015    ; load BC with #15 to check for all ladders
2167: CD 6D 21    call    $216d       ; check for going down ladder
216A: C3 BA 21    jp      $21ba       ; skip ahead

; called from #2167

216D: CD 6E 23    call    $236e       ; check for ladder.  if no ladders, RET to higher sub.  if at top of ladder, A := 1
2170: 3D          dec     a           ; is there a ladder to go down?
2171: C0          ret     nz          ; no, return

2172: 78          ld      a,b         ; yes, load A with B which has the value of the ladder from the check ??
2173: D6 05       sub     $05         ; subtract 5
2175: DD 77 17    ld      (ix+$17),a  ; store into +17 to indicate which ladder we might be going down ???
2178: 3A 48 63    ld      a,(the_oil_can_is_on_fire_6348)   ; get status of the oil can fire
217B: A7          and     a           ; is the fire lit ?
217C: CA B2 21    jp      z,$21b2     ; no, always take ladders before oil is lit

217F: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; else load A with mario's Y position + 5
2182: D6 04       sub     $04         ; subtract 4
2184: BA          cp      d           ; is the barrel already below mario  ?
2185: D8          ret     c           ; yes, return without taking ladder

2186: 3A 80 63    ld      a,(difficulty_level_6380)   ; else load A with difficulty from 1 to 5.  usually the level but increases during play
2189: 1F          rra                 ; roll right (div 2) .  now can be 0, 1, or 2
218A: 3C          inc     a           ; increment.  result is now 1, 2, or 3 based on skill level
218B: 47          ld      b,a         ; store into B
218C: 3A 18 60    ld      a,(rngtimer1_6018) ; load A with random timer ?
218F: 4F          ld      c,a         ; store into C for later use ?
2190: E6 03       and     $03         ; mask bits.   result now random number between 0 and 3
2192: B8          cp      b           ; compare with value computed above based on skill
2193: D0          ret     nc          ; return if greater.  on highest skill this works 75% of time, only returns on 3

2194: 21 10 60    ld      hl,inputstate_6010; load HL with player input.

; InputState - copy of RawInput, except when jump is pressed, bit 7 is set momentarily
; RawInput - right sets bit 0, left sets bit 1, up sets bit 2, down sets bit 3, jump sets bit 4

2197: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's x position
219A: BB          cp      e           ; compare with barrel's x position
219B: CA B2 21    jp      z,$21b2     ; if equal, then go down ladder

219E: D2 A9 21    jp      nc,$21a9    ; if barrel is to right of mario, then check for moving to left

21A1: CB 46       bit     0,(hl)      ; else is mario trying to move right ?
21A3: CA AE 21    jp      z,$21ae     ; no, skip ahead and return without going down ladder

21A6: C3 B2 21    jp      $21b2       ; yes, make barrel go down ladder

21A9: CB 4E       bit     1,(hl)      ; is mario trying to move left ?
21AB: C2 B2 21    jp      nz,$21b2    ; yes, make barrel go down ladder

21AE: 79          ld      a,c         ; else load A with random timer computed above
21AF: E6 18       and     $18         ; mask with #18.    25% chance of being zero?
21B1: C0          ret     nz          ; else return without going down ladder.  If zero then go down the ladder anyway

21B2: DD 34 07    inc     (ix+$07)    ; increase Barrel's deployment/animation status
21B5: DD CB 02 C6 set     0,(ix+$02)  ; set barrel to go down the ladder
21B9: C9          ret                 ; return

; we arrive here because the barrel is rolling left or right or turning a corner or a crazy barrel
; stores position values, sprite value and colors into sprite values
; arrive from several locations, eg #20DE

21BA: D9          exx                 ; swap DE, HL, and BC with counterparts
21BB: DD 7E 03    ld      a,(ix+$03)  ; load A with Barrels X position
21BE: 77          ld      (hl),a      ; store into sprite X position
21BF: 2C          inc     l           ; HL := HL + 1
21C0: DD 7E 07    ld      a,(ix+$07)  ; load A with Barrels deployment/animation status
21C3: 77          ld      (hl),a      ; store into sprite value
21C4: 2C          inc     l           ; HL := HL + 1
21C5: DD 7E 08    ld      a,(ix+$08)  ; load A with Barrel's color
21C8: 77          ld      (hl),a      ; Store into sprite color
21C9: 2C          inc     l           ; HL := HL + 1
21CA: DD 7E 05    ld      a,(ix+$05)  ; Load A with Barrel's Y position
21CD: 77          ld      (hl),a      ; store into sprite Y position
21CE: C3 8D 1F    jp      $1f8d       ; jump back and check for next barrel

; data used in sub below for attract mode movement
; first byte is movement, second is duration

21D1: 80          fe                  ; jump
21D3: 01          c0                  ; run right
21D5  04 50     ; up = climb ladder
21D7  02 10     ; run left
21D9  82 60     ; jump left
21DB  02 10     ; run left
21DD: 82          ca                  ; jump left
21DF  01 10     ; run right
21E1: 81          ff                  ; jump right (gets hammer)
21E3  02 38     ; run left
21E5  01 80     ; run right - mario dies falling over right edge
21E7: 02          ff                  ; run left
21E9  04 80     ; up
21EB  04 60     ; up
21ED  80        ; ?

; called during attract mode only from #1977

21EE: 11 D1 21    ld      de,$21d1    ; load DE with start of table data
21F1: 21 CC 63    ld      hl,state_of_attract_mode_63cc    ; load HL with state of attract mode
21F4: 7E          ld      a,(hl)      ; load A with state
21F5: 07          rlca                ; rotate left (x2)
21F6: 83          add     a,e         ; add to E to get the movement
21F7: 5F          ld      e,a         ; put back
21F8: 1A          ld      a,(de)      ; load A with data from table
21F9: 32 10 60    ld      (inputstate_6010),a; store into copy of input
21FC: 2C          inc     l           ; HL := #63CD (timer)
21FD: 7E          ld      a,(hl)      ; load timer
21FE: 35          dec     (hl)        ; decrement
21FF: A7          and     a           ; == #00 ?
2200: C0          ret     nz          ; no, return

2201: 1C          inc     e           ; else next movement
2202: 1A          ld      a,(de)      ; load A with timer from table
2203: 77          ld      (hl),a      ; store into timer
2204: 2D          dec     l           ; HL := #63CC (state)
2205: 34          inc     (hl)        ; increase state
2206: C9          ret                 ; return

; arrive here from main routine at #199B

2207: 3E 02       ld      a,$02       ; load A with 2 = 0010 binary
2209: F7          rst     $30         ; only continues here on conveyors, else returns from subroutine

220A: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
220D: 1F          rra                 ; time to do this ?
220E: 21 80 62    ld      hl,left_side_rectractable_ladder_6280    ; load HL with left side rectractable ladder
2211: 7E          ld      a,(hl)      ; load A with ladder status
2212: DA 19 22    jp      c,$2219     ; if clock is odd, skip next 2 steps

2215: 21 88 62    ld      hl,right_side_retractable_ladder_6288    ; load HL with right side retractable ladder
2218: 7E          ld      a,(hl)      ; load A with ladder status

2219: E5          push    hl          ; save HL
221A: EF          rst     $28         ; jump based on A

221B  27 22                             ; #2227         A = 0   ladder is all the way up
221D  59 22                             ; #2259         A = 1   ladder is moving down
221F  99 22                             ; #2299         A = 2   ladder is all the way down
2221  A2 22                             ; #22A2         A = 3   ladder is moving up
2223  00 00 00 00                       ; unused

; ladder is all the way up

2227: E1          pop     hl          ; restore HL - it has the ladder address
2228: 2C          inc     l           ; HL := #6289 or #6281 - timer for movement ???
2229: 35          dec     (hl)        ; decrement.  at zero ?
222A: C2 3A 22    jp      nz,$223a    ; no, skip ahead and check to disable moving ladder indicator

222D: 2D          dec     l           ; put HL back where it was
222E: 34          inc     (hl)        ; increase ladder status.  now it is moving down
222F: 2C          inc     l
2230: 2C          inc     l           ; HL := #628A or #6282
2231: CD 43 22    call    $2243       ; only continue below if mario is on the ladder

2234: 3E 01       ld      a,$01       ; A := 1
2236: 32 1A 62    ld      (moving_ladder_indicator_621a),a   ; store into moving ladder indicator
2239: C9          ret                 ; return

223A: 2C          inc     l           ; HL := #628A or #6282
223B: CD 43 22    call    $2243       ; only continue below if mario is on the ladder, else RET

223E: AF          xor     a           ; A := 0
223F: 32 1A 62    ld      (moving_ladder_indicator_621a),a   ; store into moving ladder indicator
2242: C9          ret                 ; return

; called from #2231 above with HL = #628A
; called from #223B above with HL = #628A
; called from #2276 below

2243: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load mario's Y position
2246: FE 7A       cp      $7a         ; is mario on the top pie tray level or above?
2248: D2 57 22    jp      nc,$2257    ; no, skip ahead and return to higher sub

224B: 3A 16 62    ld      a,(jumping_status_6216)   ; yes, check for a jump in progress ?
224E: A7          and     a           ; is mario jumping ?
224F: C2 57 22    jp      nz,$2257    ; yes, jump ahead and return to higher sub

2252: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; else load A with mario's X position
2255: BE          cp      (hl)        ; is mario on the ladder? (or exactly lined up on it)
2256: C8          ret     z           ; yes, return

2257: E1          pop     hl          ; adjust stack pointer
2258: C9          ret                 ; return to higher subroutine

; arrive from #221A when ladder is moving down

2259: E1          pop     hl          ; restore HL = ladder status
225A: 2C          inc     l
225B: 2C          inc     l
225C: 2C          inc     l
225D: 2C          inc     l           ; HL now has the ladder's ???
225E: 35          dec     (hl)        ; decrease.  at zero?
225F: C0          ret     nz          ; no, return

2260: 3E 04       ld      a,$04       ; A := 4
2262: 77          ld      (hl),a      ; store into the ladder's ???
2263: 2D          dec     l           ; HL now has the ladder's ???
2264: 34          inc     (hl)        ; increase
2265: CD BD 22    call    $22bd       ; ???
2268: 3E 78       ld      a,$78       ; A := #78
226A: BE          cp      (hl)        ; == (HL) ?
226B: C2 75 22    jp      nz,$2275    ; no, skip ahead

226E: 2D          dec     l
226F: 2D          dec     l
2270: 2D          dec     l
2271: 34          inc     (hl)
2272: 2C          inc     l
2273: 2C          inc     l
2274: 2C          inc     l

2275: 2D          dec     l           ; HL now has ???
2276: CD 43 22    call    $2243       ; only continue below if mario is on the ladder, else RET

; ladder is moving down and mario is on it

2279: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario Y position
227C: FE 68       cp      $68         ; is mario already at the low point of the ladder ?
227E: D2 8A 22    jp      nc,$228a    ; yes, skip ahead

2281: 21 05 62    ld      hl,return_without_taking_the_ladder_6205    ; else load HL with Mario's Y position
2284: 34          inc     (hl)        ; increase (move mario down one pixel)
2285: CD C0 3F    call    $3fc0       ; sets mario sprite to on ladder with left hand up and HL to #694F (mario's sprite Y position) [this line seems like a patch ??? orig could be  LD HL,#694F ]
2288: 34          inc     (hl)        ; increase sprite (move mario down one pixel in the hardware .  immediate update)
2289: C9          ret                 ; return

228A: 1F          rra                 ; rotate right A.  is A odd ?
228B: DA 81 22    jp      c,$2281     ; yes, loop back

228E: 1F          rra                 ; else rotate right A again.  is the 2-bit set ?
228F: 3E 01       ld      a,$01       ; A := 1
2291: DA 95 22    jp      c,$2295     ; yes, skip next step

2294: AF          xor     a           ; A := 0
2295: 32 22 62    ld      (ladder_toggle_6222),a   ; store into ladder toggle
2298: C9          ret                 ; return

; arrive from #221A when ladder is all the way down

2299: E1          pop     hl          ; restore HL
229A: 3A 18 60    ld      a,(rngtimer1_6018) ; load A with random timer
229D: E6 3C       and     $3c         ; mask bits.  result zero?
229F: C0          ret     nz          ; no, return

22A0: 34          inc     (hl)        ; else increase (HL) - the ladder is now moving up
22A1: C9          ret                 ; return

; arrive from jump at #221A
; a rectractable ladder is moving up
; HL popped from stack is either 6280 for left ladder or 6288 for right ladder

22A2: E1          pop     hl          ; restore HL
22A3: 2C          inc     l
22A4: 2C          inc     l
22A5: 2C          inc     l
22A6: 2C          inc     l           ; HL := HL + 4
22A7: 35          dec     (hl)        ; decrease (HL).  zero?
22A8: C0          ret     nz          ; no, return

22A9: 36 02       ld      (hl),$02    ; else set (HL) to 2
22AB: 2D          dec     l
22AC: 35          dec     (hl)        ; decrease ladder Y value - makes ladder move up
22AD: CD BD 22    call    $22bd       ; update the sprite
22B0: 3E 68       ld      a,$68       ; A := #68
22B2: BE          cp      (hl)        ; reached top of ladder movement?
22B3: C0          ret     nz          ; no, return

; ladder has moved all the way up

22B4: AF          xor     a           ; A := 0
22B5: 06 80       ld      b,$80       ; B := #80
22B7: 2D          dec     l
22B8: 2D          dec     l
22B9: 70          ld      (hl),b
22BA: 2D          dec     l           ; set HL to ladder status
22BB: 77          ld      (hl),a      ; set ladder status to 0 == all the way up
22BC: C9          ret                 ; return

; called from #22AD above and from #2265
; HL is preloaded with ladder Y position

22BD: 7E          ld      a,(hl)      ; load A with ladder Y value
22BE: CB 5D       bit     3,l         ; test bit 3 of L
22C0: 11 4B 69    ld      de,ladder_sprite_y_value_694b    ; load DE with ladder sprite Y value
22C3: C2 C9 22    jp      nz,$22c9    ; if other ladder, skip next step

22C6: 11 47 69    ld      de,other_ladder_sprite_y_value_6947    ; load DE with other ladder sprite Y value
22C9: 12          ld      (de),a      ; update the sprite Y value
22CA: C9          ret                 ; return

; arrive here when crazy barrel is onscreen
; called when barrel deployed or hits a girder on the way down
; called from #2149

22CB: 3A 48 63    ld      a,(the_oil_can_is_on_fire_6348)   ; load A with oil can status
22CE: A7          and     a           ; is the oil can lit ?
22CF: CA E1 22    jp      z,$22e1     ; no , jump ahead

22D2: 3A 80 63    ld      a,(difficulty_level_6380)   ; else load A with difficulty
22D5: 3D          dec     a           ; decrement.  will be between 0 and 4
22D6: EF          rst     $28         ; jump based on A

22D7  F6 22                             ; #22F6
22D9  F6 22                             ; #22F6
22DB  03 23                             ; #2303
22DD  03 23                             ; #2303
22DF  1A 23                             ; #231A

; arrive here when oil can is not yet lit
; used for initial crazy barrel

22E1: 3A 29 62    ld      a,(level_number_6229)   ; load A with level #
22E4: 47          ld      b,a         ; store into B
22E5: 05          dec     b           ; decrement B
22E6: 3E 01       ld      a,$01       ; load A with 1
22E8: CA F9 22    jp      z,$22f9     ; if level was 1, then jump ahead

22EB: 05          dec     b           ; decrement B again
22EC: 3E B1       ld      a,$b1       ; load A with #B1 - for use with level 2 inital crazy barrel
22EE: CA F9 22    jp      z,$22f9     ; if level 2, then jump ahead

22F1: 3E E9       ld      a,$e9       ; else load A with #E9 - for level 3 and up inital crazy barrel
22F3: C3 F9 22    jp      $22f9       ; jump ahead and store

; check for use with crazy barrels when difficulty is 1 or 2

22F6: 3A 18 60    ld      a,(rngtimer1_6018) ; load A with random timer value

22F9: DD 77 11    ld      (ix+$11),a  ; store into +11
22FC: E6 01       and     $01         ; mask bits, makes into #00 or #01
22FE: 3D          dec     a           ; decrement, now either #00 or #FF
22FF: DD 77 10    ld      (ix+$10),a  ; store into +10
2302: C9          ret                 ; return

; check for use with crazy barrels when difficulty is 3 or 4

2303: 3A 18 60    ld      a,(rngtimer1_6018) ; load A with random timer value
2306: DD 77 11    ld      (ix+$11),a  ; store into +11
2309: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
230C: DD BE 03    cp      (ix+$03)    ; compare barrel's X position
230F: 3E 01       ld      a,$01       ; load A with 1
2311: D2 16 23    jp      nc,$2316    ; if greater then skip ahead

2314: 3D          dec     a           ; else decrement twice
2315: 3D          dec     a           ; makes A := #FF

2316: DD 77 10    ld      (ix+$10),a  ; store into +10
2319: C9          ret                 ; return

; check for use with crazy barrels when difficulty is 5

231A: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
231D: DD 96 03    sub     (ix+$03)    ; subtract the barrel's X position
2320: 0E FF       ld      c,$ff       ; load C with #FF
2322: DA 26 23    jp      c,$2326     ; if barrel is to left of mario, then jump ahead

2325: 0C          inc     c           ; else increase C to 0

2326: 07          rlca                ; rotate left A (doubles A)
2327: CB 11       rl      c           ; rotate left C
2329: 07          rlca                ; rotate left A (doubles A)
232A: CB 11       rl      c           ; rotate left C
232C: DD 71 10    ld      (ix+$10),c  ; store C into +10
232F: DD 77 11    ld      (ix+$11),a  ; store A into +11
2332: C9          ret

; called from #2007 when barrels are rolling
; called from #     when mario is moving left or right on girders
; HL is preloaded with mario X,Y position
; B is preloaded with direction

2333: 3E 0F       ld      a,$0f       ; load A with binary 00001111
2335: A4          and     h           ; and with H.  A now has between 0 and F
2336: 05          dec     b           ; Count down B.  is the direction == 1 ?
2337: CA 42 23    jp      z,$2342     ; yes, then skip ahead 4 steps

233A: FE 0F       cp      $0f         ; else check is A still = #0F ?
233C: D8          ret     c           ; return if Carry ( A < 0F ) most of time it wont?

233D: 06 FF       ld      b,$ff       ; else B := #FF
233F: C3 47 23    jp      $2347       ; skip next 3 steps

2342: FE 01       cp      $01         ; A > 1 ?
2344: D0          ret     nc          ; yes, return

2345: 06 01       ld      b,$01       ; B := 1

2347: 3E F0       ld      a,$f0       ; A := #F0
2349: BD          cp      l           ; is A == L ?
234A: CA 60 23    jp      z,$2360     ; Yes, skip ahead

234D: 3E 4C       ld      a,$4c       ; A := #4C
234F: BD          cp      l           ; == L ?
2350: CA 66 23    jp      z,$2366     ; yes, skip ahead

2353: 7D          ld      a,l
2354: CB 6F       bit     5,a
2356: CA 5C 23    jp      z,$235c

2359: 90          sub     b
235A: 6F          ld      l,a
235B: C9          ret                 ; return

235C: 80          add     a,b         ; A := A + B
235D: C3 5A 23    jp      $235a       ; loop back

2360: CB 7C       bit     7,h
2362: C2 59 23    jp      nz,$2359
2365: C9          ret                 ; return

2366: 7C          ld      a,h         ; A := H
2367: FE 98       cp      $98         ; < #98 ?
2369: D8          ret     c           ; no, return

236A: 7D          ld      a,l         ; A := L
236B: C3 5C 23    jp      $235c       ; loop back

; called from #1B13 when jumping ?
; called from #216D when checking for barrel to go down a ladder?
; A has X position of barrel ?
; BC starts with #15
; called when firefoxs are moving to check for ladders
; if no ladder is nearby , it RETs to a higher subroutine

236E: 21 00 63    ld      hl,ladder_positions_6300    ; load HL with start of table data that has positions of ladders
2371: ED B1       cpir                ; check for ladders ???

CPIR - The contents of the memory location addressed by the HL register pair is
compared with the contents of the Accumulator. In case of a true compare, a
condition bit is set. HL is incremented and the Byte Counter (register pair
BC) is decremented. If decrementing causes BC to go to zero or if A = (HL),
the instruction is terminated. If BC is not zero and A ? (HL), the program
counter is decremented by two and the instruction is repeated. Interrupts are
recognized and two refresh cycles are executed after each data transfer.
If BC is set to zero before instruction execution, the instruction loops
through 64 Kbytes if no match is found.



2373: C2 9A 23    jp      nz,$239a    ; if no match, return to higher sub, no ladder nearby

2376: E5          push    hl          ; else a ladder may be near. save HL
2377: C5          push    bc          ; save BC
2378: 01 14 00    ld      bc,$0014    ; load BC with #14 for offset
237B: 09          add     hl,bc       ; add #14 to HL.  Now HL has the ladder's other value ?
237C: 0C          inc     c           ; C := #15
237D: 5F          ld      e,a         ; save A into E
237E: 7A          ld      a,d         ; load A with D = barrels position ?
237F: BE          cp      (hl)        ; compare with ladder's position
2380: CA 8F 23    jp      z,$238f     ; if equal then jump ahead

2383: 09          add     hl,bc       ; else add #15 into HL
2384: BE          cp      (hl)        ; compare position
2385: CA 95 23    jp      z,$2395     ; if equal then skip ahead

2388: 57          ld      d,a         ; else load D with A
2389: 7B          ld      a,e         ; load A with E
238A: C1          pop     bc          ; restore BC
238B: E1          pop     hl          ; restore HL
238C: C3 71 23    jp      $2371       ; check for next ladder?

; arrive here when a barrel is above a ladder

238F: 09          add     hl,bc       ; add #15 into HL
2390: 3E 01       ld      a,$01       ; load A with 1 = signal that we are at top of ladder
2392: C3 98 23    jp      $2398       ; jump ahead

2395: AF          xor     a           ; else A: = 0 = signal that we are at bottom of ladder
2396: ED 42       sbc     hl,bc       ; subtract BC from HL.  restore HL to original value

2398: C1          pop     bc          ; restore BC
2399: 46          ld      b,(hl)      ; load B with value in HL

239A: E1          pop     hl          ; restore HL
239B: C9          ret                 ; return

; called from #20ED for crazy barrel movement.  for this, BC, DE,and HL have their alternates
; subroutine called from #2054.  used when barrels are rolling.  only called when rolling around edges or mario jumping???
; IX has the start value of barrel sprite.  EG 6700
; IX can have 6200 for mario from #1BC2

239C: DD 7E 04    ld      a,(ix+$04)  ; load modified Y position, used for crazy barrels hitting girders ???
239F: DD 86 11    add     a,(ix+$11)  ; add +11 = vertical speed?
23A2: DD 77 04    ld      (ix+$04),a  ; update position ?

23A5: DD 7E 03    ld      a,(ix+$03)  ; load object's X position
23A8: DD 8E 10    adc     a,(ix+$10)  ; add +10 = rolling over edge/direction indicator.  note this is add with carry
23AB: DD 77 03    ld      (ix+$03),a  ; store into X position

23AE: DD 7E 06    ld      a,(ix+$06)  ; load A with +6 == ??
23B1: DD 96 13    sub     (ix+$13)    ; subtract +13 == ??
23B4: 6F          ld      l,a         ; store into L
23B5: DD 7E 05    ld      a,(ix+$05)  ; load A with barrel Y position
23B8: DD 9E 12    sbc     a,(ix+$12)  ; subtract vertical speed????
23BB: 67          ld      h,a         ; store into H
23BC: DD 7E 14    ld      a,(ix+$14)  ; load +14 = mirror of modified Y position?.  used for jump counter when mario jumps
23BF: A7          and     a           ; clear flags
23C0: 17          rla                 ; rotate left (mult by 2)
23C1: 3C          inc     a           ; add 1
23C2: 06 00       ld      b,$00       ; B := 0
23C4: CB 10       rl      b
23C6: CB 27       sla     a
23C8: CB 10       rl      b
23CA: CB 27       sla     a
23CC: CB 10       rl      b
23CE: CB 27       sla     a
23D0: CB 10       rl      b
23D2: 4F          ld      c,a         ; copy answer (A) to C. BC now has ???
23D3: 09          add     hl,bc       ; add to HL
23D4: DD 74 05    ld      (ix+$05),h  ; update Y position
23D7: DD 75 06    ld      (ix+$06),l  ; update +6
23DA: DD 34 14    inc     (ix+$14)    ; increase +14.  used for 6214 for mario as a jump counter
23DD: C9          ret                 ; return

; called from subs that are moving a barrell left or right
; IX is memory base of the barrel in question (e.g. #6700)
; called from #2073 with C either 0 or 4
; C is preloaded with mask ?


23DE: DD 7E 0F    ld      a,(ix+$0f)  ; Load A with +#F property of barrel (counts from 4 to 1 over and over)
23E1: 3D          dec     a           ; decrease by one.  did counter go to zero?
23E2: C2 03 24    jp      nz,$2403    ; if not, jump ahead, store new timer value and return

23E5: AF          xor     a           ; A := 0
23E6: DD CB 07 26 sla     (ix+$07)    ; shift left the barrel sprite status, push bit 7 into carry flag
23EA: 17          rla                 ; rotate in carry flag into A
23EB: DD CB 08 26 sla     (ix+$08)    ; shift left the other barrel color, push bit 7 into carry flag
23EF: 17          rla                 ; rotate in carry flag into A
23F0: 47          ld      b,a         ; copy result into B
23F1: 3E 03       ld      a,$03       ; A := 3
23F3: B1          or      c           ; bitwise OR with C
23F4: CD 09 30    call    $3009       ; ???
23F7: 1F          rra
23F8: DD CB 08 1E rr      (ix+$08)    ; rotate right the barrel's color
23FC: 1F          rra
23FD: DD CB 07 1E rr      (ix+$07)    ; Roll these values back
2401: 3E 04       ld      a,$04       ; A := 4

2403: DD 77 0F    ld      (ix+$0f),a  ; store A into timer
2406: C9          ret                 ; return

;
; called from #1BDF and #20C3 and #2146
;

2407: DD 7E 14    ld      a,(ix+$14)  ; load A with Barrel +14 status
240A: 07          rlca
240B: 07          rlca
240C: 07          rlca
240D: 07          rlca                ; rotate left 4 times
240E: 4F          ld      c,a         ; save to C for use next 2 steps
240F: E6 0F       and     $0f         ; mask with #0F.  now between #00 and #0F
2411: 67          ld      h,a         ; store into H
2412: 79          ld      a,c         ; restore A to value saved above
2413: E6 F0       and     $f0         ; mask with #F0
2415: 6F          ld      l,a         ; store into L
2416: DD 4E 13    ld      c,(ix+$13)  ; load C with +13
2419: DD 46 12    ld      b,(ix+$12)  ; load B with +12
241C: ED 42       sbc     hl,bc       ; HL := HL - BC
241E: C9          ret                 ; return

; arrive here when jump not pressed ?
; sets DE based on mario's position
; called from #1AE6
; called from #1BC5
; called from #2B09

241F: 11 00 01    ld      de,$0100    ; DE:= #0100
2422: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with Mario's X position
2425: FE 16       cp      $16         ; is this greater than #16 ?
2427: D8          ret     c           ; yes, return

2428: 15          dec     d           ; no,
2429: 1C          inc     e           ; DE := #0001
242A: FE EA       cp      $ea         ; is Mario's position > #EA ?
242C: D0          ret     nc          ; yes, return

242D: 1D          dec     e           ; no, DE:= #0000
242E: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number (01, 10, 11 or 100)
2431: 0F          rrca                ; rotate right with carry.  is this the girders or elevators?
2432: d0          ret     nc          ; no, return

2433: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; otherwise load A with mario's Y position
2436: fe 58       cp      $58         ; is this > #58 ?
2438: d0          ret     nc          ; Yes, return

2439: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; else load A with mario's X position
243C: FE 6C       cp      $6c         ; is this > #6C ?
243E: D0          ret     nc          ; Yes, return

243F: 14          inc     d           ; else DE := #0100
2440: C9          ret                 ; and return

; called from #0D62

; checksum ???

        ; 3F00:  5C 76 49 4A 01 09 08 01 3F 7D 77 1E 19 1E 24 15  .(C)1981...NINTE
        ; 3F10:  1E 14 1F 10 1F 16 10 11 1D 15 22 19 13 11 10 19  NDO.OF.AMERICA.I

; called from #0D62
; 1.  runs checksum on the NINTENDO, breaks if not correct
; 2.

2441: 21 0C 3F    ld      hl,$3f0c    ; load HL with ROM area that has NINTENDO written
2444: 3E 5E       ld      a,$5e       ; A := #5E = constant so the checksum comes to zero
2446: 06 06       ld      b,$06       ; for B = 1 to 6

2448: 86          add     a,(hl)      ; add this letter
2449: 23          inc     hl          ; next letter
244A: 10 FC       djnz    $2448       ; loop until done

244C: FD 21 10 63 ld      iy,unknown_6310
2450: A7          and     a           ; A == 0 ? checksum OK ?
2451: CA 56 24    jp      z,$2456     ; yes, skip next step

2454: FD 23       inc     iy          ; running this step will break the game ?  loops at #2371 forever

2456: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
2459: 3D          dec     a           ; is this the girders?
245A: 21 E4 3A    ld      hl,$3ae4    ; load HL with start of table data for girders
245D: CA 71 24    jp      z,$2471     ; if girders, skip ahead

2460: 3D          dec     a           ; else is this the conveyors?
2461: 21 5D 3B    ld      hl,$3b5d    ; load HL with start of table data for conveyors
2464: CA 71 24    jp      z,$2471     ; if conveyors, skip ahead

2467: 3D          dec     a           ; else is this the elevators?
2468: 21 E5 3B    ld      hl,$3be5    ; load HL with start of table data for elevators
246b: CA 71 24    jp      z,$2471     ; if elevators, skip ahead

246E: 21 8B 3C    ld      hl,$3c8b    ; otherwise we're on rivets.  load HL with table data for rivets

2471: DD 21 00 63 ld      ix,ladder_positions_6300    ; #6300 is used for ladder positions?
2475: 11 05 00    ld      de,$0005    ; DE := 5 = offset

2478: 7E          ld      a,(hl)      ; load A with the next item of data
2479: A7          and     a           ; is this item == 0 ?
247A: CA 88 24    jp      z,$2488     ; yes, jump ahead

247D: 3D          dec     a           ; no, decrease, was this item == 1 ?
247E: CA 9E 24    jp      z,$249e     ; yes, jump down instead

2481: FE A9       cp      $a9         ; was the item == #AA ?
2483: C8          ret     z           ; yes, return, we are done with this.  AA is at the end of each table

2484: 19          add     hl,de       ; if neither then add offset for next HL
2485: C3 78 24    jp      $2478       ; loop again

; data element was #01

2488: 23          inc     hl          ; next HL
2489: 7E          ld      a,(hl)      ; load A with table data (EG #3B12)
248A: DD 77 00    ld      (ix+$00),a  ; store into index
248D: 23          inc     hl          ; next HL
248E: 7E          ld      a,(hl)      ; load A with table data
248F: DD 77 15    ld      (ix+$15),a  ; store into index +#15
2492: 23          inc     hl
2493: 23          inc     hl          ; next HL, next HL
2494: 7E          ld      a,(hl)      ; load A with table data
2495: DD 77 2A    ld      (ix+$2a),a  ; store into index +#2A
2498: DD 23       inc     ix          ; next location
249A: 23          inc     hl          ; next table data
249B: C3 78 24    jp      $2478       ; jump back

; data element was #02
; this sub is same as one above but uses IY instead of IX

249E: 23          inc     hl
249F: 7E          ld      a,(hl)
24A0: FD 77 00    ld      (iy+$00),a
24A3: 23          inc     hl
24A4: 7E          ld      a,(hl)
24A5: FD 77 15    ld      (iy+$15),a
24A8: 23          inc     hl
24A9: 23          inc     hl
24AA: 7E          ld      a,(hl)
24AB: FD 77 2A    ld      (iy+$2a),a
24AE: FD 23       inc     iy
24B0: 23          inc     hl
24B1: C3 78 24    jp      $2478       ; jump back

; called this sub from barrel roll from #2068
; check for barrel collision with the oil can ????

24B4: DD 7E 05    ld      a,(ix+$05)  ; load A with Barrel Y position
24B7: FE E8       cp      $e8         ; Is it near the bottom or lower?
24B9: D8          ret     c           ; if so, return

24BA: DD 7E 03    ld      a,(ix+$03)  ; else load A with Barrel X position
24BD: FE 2A       cp      $2a         ; is X position < #2A ? (rolling oever edge on left side of screen)
24BF: D0          ret     nc          ; no, return

24C0: FE 20       cp      $20         ; is it past the edge of girder?
24C2: D8          ret     c           ; no, return

24C3: DD 7E 15    ld      a,(ix+$15)  ; load A with Barrel #15 indicator, zero = normal barrel,  1 = blue barrel
24C6: A7          and     a           ; is this a normal barrel?
24C7: CA D0 24    jp      z,$24d0     ; yes, jump ahead

24CA: 3E 03       ld      a,$03       ; else blue barrel, A := 3
24CC: 32 B9 62    ld      (fire_release_62b9),a   ; store into #62B9 - used for releasing fires ?
24CF: AF          xor     a           ; A := #00

24D0: DD 77 00    ld      (ix+$00),a  ; clear out the barrel active indicator
24D3: DD 77 03    ld      (ix+$03),a  ; clear out the barrel X position
24D6: 21 82 60    ld      hl,boom_sound_address_6082    ; load HL with boom sound address
24D9: 36 03       ld      (hl),$03    ; play boom sound for 3 units
24DB: E1          pop     hl          ; get HL from stack
24DC: 3A 48 63    ld      a,(the_oil_can_is_on_fire_6348)   ; turns to 1 when the oil can is on fire
24DF: A7          and     a           ; is oil can already on fire ?
24E0: C2 BA 21    jp      nz,$21ba    ; yes, jump back, we are done

24E3: 3C          inc     a           ; else A := 1
24E4: 32 48 63    ld      (the_oil_can_is_on_fire_6348),a   ; set the oil can is on fire
24E7: C3 BA 21    jp      $21ba       ; jump back , we are done.

; called from main routine at #1992
; copies pie buffer to pie sprites

24EA: 3E 02       ld      a,$02       ; check level for conveyors
24EC: F7          rst     $30         ; if not conveyors, RET, else continue
24ED: CD 23 25    call    $2523       ; check for deployment of new pies
24F0: CD 91 25    call    $2591       ; update all pies positions based on direction of trays, remove pies in fire or off edge
24F3: DD 21 A0 65 ld      ix,start_of_pies_65a0    ; load IX with start of pies
24F7: 06 06       ld      b,$06       ; for B = 1 to 6 pies
24F9: 21 B8 69    ld      hl,start_of_pie_sprites_69b8    ; load HL with hardware address for pies

24FC: DD 7E 00    ld      a,(ix+$00)  ; load A with sprite status
24FF: A7          and     a           ; is this sprite active ?
2500: CA 1C 25    jp      z,$251c     ; no, add 4 to L and loop again

2503: DD 7E 03    ld      a,(ix+$03)  ; load A with pie X position
2506: 77          ld      (hl),a      ; store into sprite
2507: 2C          inc     l           ; next address
2508: DD 7E 07    ld      a,(ix+$07)  ; load A with pie sprite value
250B: 77          ld      (hl),a      ; store into sprite
250C: 2C          inc     l           ; next address
250D: DD 7E 08    ld      a,(ix+$08)  ; load A with pie color
2510: 77          ld      (hl),a      ; store into sprite
2511: 2C          inc     l           ; next address
2512: DD 7E 05    ld      a,(ix+$05)  ; load A with pie Y position
2515: 77          ld      (hl),a      ; store into sprite
2516: 2C          inc     l           ; next address

2517: DD 19       add     ix,de       ; add offset for next pie
2519: 10 E1       djnz    $24fc       ; next B

251B: C9          ret                 ; return

251C: 7D          ld      a,l         ; A := L
251D: C6 04       add     a,$04       ; add 4
251F: 6F          ld      l,a         ; store into L
2520: C3 17 25    jp      $2517       ; loop back for next pie

; called from #24ED above

2523: 21 9B 63    ld      hl,pie_timer_for_next_pie_deployment_639b    ; load HL with pie timer
2526: 7E          ld      a,(hl)      ; get timer value
2527: A7          and     a           ; time to release a pie ?
2528: C2 8F 25    jp      nz,$258f    ; no, decrease counter and return

252B: 3A 9A 63    ld      a,(deployment_indicator_639a)   ; load A with fire deployment indicator ???
252E: A7          and     a           ; == 0 ? (are there no fires???)
252F: C8          ret     z           ; yes, return, no pies until fires are released

; look for a pie to deploy

2530: 06 06       ld      b,$06       ; for B = 1 to 6 pies
2532: 11 10 00    ld      de,$0010    ; load DE with offset of #10 (16 decimal)
2535: DD 21 A0 65 ld      ix,start_of_pies_65a0    ; load IX with start of pie sprites table

2539: DD CB 00 46 bit     0,(ix+$00)  ; is this pie already onscreen?
253D: CA 45 25    jp      z,$2545     ; no, jump ahead and deploy this pie

2540: DD 19       add     ix,de       ; else load offset for next pie
2542: 10 F5       djnz    $2539       ; next B

2544: C9          ret                 ; return [no room for more pies, 6 already onscreen]

; deploy a pie

2545: CD 57 00    call    $0057       ; load A with a random number
2548: FE 60       cp      $60         ; < #60 ?
254A: DD 36 05 7C ld      (ix+$05),$7c; store #7C into pie's Y position
254E: DA 58 25    jp      c,$2558     ; yes, skip next 3 steps

2551: 3A A3 62    ld      a,(master_direction_vector_for_upper_left_62a3)   ; load A with master direction for middle conveyor
2554: 3D          dec     a           ; is this tray moving outwards ?
2555: C2 6E 25    jp      nz,$256e    ; no, skip ahead

2558: DD 36 05 CC ld      (ix+$05),$cc; store #CC into pie's Y position
255C: 3A A6 62    ld      a,(master_direction_vector_for_lower_level_62a6)   ; load A with master direction vector for lower conveyor
255F: 07          rlca                ; is this tray moving to the right ?

2560: DD 36 03 07 ld      (ix+$03),$07; set pie X position to 7
2564: D2 76 25    jp      nc,$2576    ; if tray moving right, skip ahead

2567: DD 36 03 F8 ld      (ix+$03),$f8; set pie X position to #F8
256B: C3 76 25    jp      $2576       ; skip ahead

256E: CD 57 00    call    $0057       ; load A with random number
2571: FE 68       cp      $68         ; < #68 ?
2573: C3 60 25    jp      $2560       ; use to decide to put on left or right side

2576: DD 36 00 01 ld      (ix+$00),$01; set pie active
257A: DD 36 07 4B ld      (ix+$07),$4b; set pie sprite value
257E: DD 36 09 08 ld      (ix+$09),$08; set pie size??? (width?)
2582: DD 36 0A 03 ld      (ix+$0a),$03; set pie size??? (height?)
2586: 3E 7C       ld      a,$7c       ; A := #7C
2588: 32 9B 63    ld      (pie_timer_for_next_pie_deployment_639b),a   ; store into pie timer for next pie deployment
258B: AF          xor     a           ; A := 0
258C: 32 9A 63    ld      (deployment_indicator_639a),a   ; store into ???

258F: 35          dec     (hl)        ; decrease pie timer
2590: C9          ret                 ; return

; called from #24F0 above
; updates all pies

2591: DD 21 A0 65 ld      ix,start_of_pies_65a0    ; load IX with pie sprite buffer
2595: 11 10 00    ld      de,$0010    ; load DE with offset
2598: 06 06       ld      b,$06       ; for B = 1 to 6

259A: DD CB 00 46 bit     0,(ix+$00)  ; active ?
259E: CA BB 25    jp      z,$25bb     ; no, skip ahead and loop for next

25A1: DD 7E 03    ld      a,(ix+$03)  ; load A with pie's X position
25A4: 67          ld      h,a         ; copy to H
25A5: C6 07       add     a,$07       ; Add 7
25A7: FE 0E       cp      $0e         ; < #E ? (pie < 6 or pie > #F9)
25A9: DA D6 25    jp      c,$25d6     ; yes, skip ahead to handle

25AC: DD 7E 05    ld      a,(ix+$05)  ; load A with pie Y position
25AF: FE 7C       cp      $7c         ; is this the top level pie?
25B1: CA C0 25    jp      z,$25c0     ; yes, skip ahead

25B4: 3A A6 63    ld      a,(pie_direction_lower_level_63a6)   ; load A with pie direction vector for lower pie level
25B7: 84          add     a,h         ; add vector to original position
25B8: DD 77 03    ld      (ix+$03),a  ; store into pie X position

25BB: DD 19       add     ix,de       ; add offset for next sprite
25BD: 10 DB       djnz    $259a       ; next B

25BF: C9          ret                 ; return

25C0: 7C          ld      a,h         ; load A with pie X position
25C1: FE 80       cp      $80         ; is the pie in the center fire?
25C3: CA D6 25    jp      z,$25d6     ; yes, skip ahead

25C6: 3A A5 63    ld      a,(upper_right_pie_tray_vector_63a5)   ; load A with direction for upper left pie tray
25C9: D2 CF 25    jp      nc,$25cf    ; if pie < #80, use this address and skip next step

25CC: 3A A4 63    ld      a,(upper_left_pie_tray_vector_63a4)   ; else load A with direction for upper right tray

25CF: 84          add     a,h         ; add vector to pie position
25D0: DD 77 03    ld      (ix+$03),a  ; store into pie X position
25D3: C3 BB 25    jp      $25bb       ; loop for next sprite

; pie in center fire or reached edge

25D6: 21 B8 69    ld      hl,start_of_pie_sprites_69b8    ; load HL with start of pie sprites
25D9: 3E 06       ld      a,$06       ; A := 6
25DB: 90          sub     b           ; subtract the pie number that is removed.  zero ?
25DC: CA E7 25    jp      z,$25e7     ; yes, skip ahead

25DF: 2C          inc     l
25E0: 2C          inc     l
25E1: 2C          inc     l
25E2: 2C          inc     l           ; else HL := HL + 4
25E3: 3D          dec     a           ; decrease A
25E4: C3 DC 25    jp      $25dc       ; loop again

25E7: AF          xor     a           ; A := 0
25E8: DD 77 00    ld      (ix+$00),a  ; clear pie active indicator
25EB: DD 77 03    ld      (ix+$03),a  ; clear pie X position
25EE: 77          ld      (hl),a      ; clear sprite from screen
25EF: C3 BB 25    jp      $25bb       ; jump back and continue

; called from main routine at #19AA

25F2: 3E 02       ld      a,$02       ; load A with 2 = 0010 binary
25F4: F7          rst     $30         ; return if not conveyors

25F5: CD 02 26    call    $2602       ; handle top conveyor and pulleys
25F8: CD 2F 26    call    $262f       ; handle middle conveyor and pulleys
25FB: CD 79 26    call    $2679       ; handle lower conveyor and pulleys
25FE: CD D3 2A    call    $2ad3       ; handle mario's different speeds when on a conveyor
2601: C9          ret                 ; return

; called from #16D5, #25F5

2602: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
2605: 0F          rrca                ; is the counter odd?
2606: DA 16 26    jp      c,$2616     ; yes, skip ahead

2609: 21 A0 62    ld      hl,top_conveyor_counter_62a0    ; load HL with top conveyor counter
260C: 35          dec     (hl)        ; decrease.  time to reverse?
260D: C2 16 26    jp      nz,$2616    ; no, skip next 3 steps

2610: 36 80       ld      (hl),$80    ; reset counter
2612: 2C          inc     l           ; HL := #62A1 = master direction vector for top tray
2613: CD DE 26    call    $26de       ; reverse the direction of this tray

2616: 21 A1 62    ld      hl,master_direction_vector_for_top_conveyor_62a1    ; load HL with master direction vector for top conveyor
2619: CD E9 26    call    $26e9       ; load A with direction vector for this frame
261C: 32 A3 63    ld      (top_conveyor_direction_vector_63a3),a   ; store A into direction vector for top conveyor
261F: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
2622: E6 1F       and     $1f         ; mask bits
2624: FE 01       cp      $01         ; == 1 ?
2626: C0          ret     nz          ; no, return

2627: 11 E4 69    ld      de,start_of_pulley_sprites_69e4    ; else load DE with start of pulley sprites
262A: EB          ex      de,hl       ; DE <> HL
262B: CD A6 26    call    $26a6       ; animate the pulleys
262E: C9          ret                 ; return

; called from #25F8 above

262F: 21 A3 62    ld      hl,master_direction_vector_for_upper_left_62a3    ; load HL with address of master direction vector for middle conveyor
2632: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
2635: FE C0       cp      $c0         ; is mario slightly above the lower conveyor?
2637: DA 6F 26    jp      c,$266f     ; yes, skip ahead.  in this case the upper trays don't vary

263A: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
263D: 0F          rrca                ; roll right, is there a carry bit?
263E: DA 4C 26    jp      c,$264c     ; yes, skip ahead

2641: 2D          dec     l           ; load HL with middle conveyor counter
2642: 35          dec     (hl)        ; decrease it.  at zero?
2643: C2 4C 26    jp      nz,$264c    ; no, skip ahead

2646: 36 C0       ld      (hl),$c0    ; yes, reset the counter to #C0
2648: 2C          inc     l           ; HL := #62A3 = master direction vector for middle conveyor
2649: CD DE 26    call    $26de       ; reverse the direction of this tray

264C: 21 A3 62    ld      hl,master_direction_vector_for_upper_left_62a3    ; load HL with master direction vector for upper left
264F: CD E9 26    call    $26e9       ; load A with direction vector for this frame
2652: 32 A5 63    ld      (upper_right_pie_tray_vector_63a5),a   ; store into pie tray vector (upper right)
2655: ED 44       neg                 ; negate.  upper two pie trays move opposite directions
2657: 32 A4 63    ld      (upper_left_pie_tray_vector_63a4),a   ; store into pie tray vector (upper left)
265A: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
265D: E6 1F       and     $1f         ; mask bits, now between 0 and #1F.  zero?
265F: C0          ret     nz          ; no, return

2660: 2D          dec     l           ; HL := #62A2 = middle conveyor counter
2661: 11 EC 69    ld      de,middle_pulley_sprites_69ec    ; load DE with middle pulley sprites
2664: EB          ex      de,hl       ; DE <> HL
2665: CD A6 26    call    $26a6       ; animate the pulleys
2668: E6 7F       and     $7f         ; mask bits, A now betwen #7F and 0 (turns off bit 7)
266A: 21 ED 69    ld      hl,unknown_69ed    ; load HL with ???
266D: 77          ld      (hl),a      ; store A
266E: C9          ret                 ; return

266F: CB 7E       bit     7,(hl)      ; is this tray moving left ?
2671: C2 4C 26    jp      nz,$264c    ; yes, don't change anything

2674: 36 FF       ld      (hl),$ff    ; else change tray so it is moving left
2676: C3 4C 26    jp      $264c       ; loop back to continue

; called from #25FB

2679: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
267C: 0F          rrca                ; rotate right.  is there a carry?
267D: DA 8D 26    jp      c,$268d     ; yes, skip ahead

2680: 21 A5 62    ld      hl,this_counter_62a5    ; no, load HL with this counter
2683: 35          dec     (hl)        ; count it down.  zero?
2684: C2 8D 26    jp      nz,$268d    ; no, skip ahead

2687: 36 FF       ld      (hl),$ff    ; yes, reset counter to #FF
2689: 2C          inc     l           ; HL := #62A6 = master direction vector for lower level
268A: CD DE 26    call    $26de       ; reverse direction of this tray

268D: 21 A6 62    ld      hl,master_direction_vector_for_lower_level_62a6    ; load HL with master direction vector for lower level
2690: CD E9 26    call    $26e9       ; load A with direction vector for this frame
2693: 32 A6 63    ld      (pie_direction_lower_level_63a6),a   ; store A into pie direction for lower level
2696: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
2699: E6 1F       and     $1f         ; mask bits.  now between 0 and #1F
269B: FE 02       cp      $02         ; == 2 ? (1/32 chance?)
269D: C0          ret     nz          ; no, return

269E: 11 F4 69    ld      de,pulley_sprite_start_69f4    ; load DE with pulley sprite start
26A1: EB          ex      de,hl       ; DE <> HL
26A2: CD A6 26    call    $26a6       ; call sub below to animate the pulleys [why?  it should just continue here]
26A5: C9          ret                 ; return

; called from #26A2, above with HL preloaded with pulley sprite address and DE preloaded with conveyor direction
; animates the pulleys

26A6: 2C          inc     l           ; load HL with pulley sprite value
26A7: 1A          ld      a,(de)      ; load A with master conveyor direction
26A8: 17          rla                 ; rotate left.  carry set?
26A9: DA C5 26    jp      c,$26c5     ; yes, skip ahead to handle that direction

26AC: 7E          ld      a,(hl)      ; load A with current sprite
26AD: 3C          inc     a           ; increase it to animate
26AE: FE 53       cp      $53         ; == #53 ? at end of sprite range?
26B0: C2 B5 26    jp      nz,$26b5    ; no, skip next step

26B3: 3E 50       ld      a,$50       ; A := #50 = reset sprite to first

26B5: 77          ld      (hl),a      ; store result sprite
26B6: 7D          ld      a,l         ; A := L = #E5
26B7: C6 04       add     a,$04       ; add 4 = #E9 for next sprite
26B9: 6F          ld      l,a         ; HL now has next sprite
26BA: 7E          ld      a,(hl)      ; load A with sprite value
26BB: 3D          dec     a           ; decrease to animate
26BC: FE CF       cp      $cf         ; == #CF ? end of sprites?
26BE: C2 C3 26    jp      nz,$26c3    ; no, skip next step

26C1: 3E D2       ld      a,$d2       ; A := #D2 = reset sprite to first

26C3: 77          ld      (hl),a      ; store into sprite
26C4: C9          ret                 ; return

; from #26A9 when conveyor direction is other way

26C5: 7E          ld      a,(hl)      ; load A with sprite value
26C6: 3D          dec     a           ; decrease to animate
26C7: FE 4F       cp      $4f         ; == #4F ? end of sprites?
26C9: C2 CE 26    jp      nz,$26ce    ; no, skip next step

26CC: 3E 52       ld      a,$52       ; A := #52 = first sprite

26CE: 77          ld      (hl),a      ; store into sprite
26CF: 7D          ld      a,l         ; A := L
26D0: C6 04       add     a,$04       ; add 4
26D2: 6F          ld      l,a         ; L := A.  HL now has next sprite in set
26D3: 7E          ld      a,(hl)      ; load A with sprite value
26D4: 3C          inc     a           ; increase to animate
26D5: FE D3       cp      $d3         ; == #D3? end of sprites?
26D7: C2 DC 26    jp      nz,$26dc    ; no, skip next step

26DA: 3E D0       ld      a,$d0       ; yes, A := #D0 = reset sprite to first

26DC: 77          ld      (hl),a      ; store sprite
26DD: C9          ret                 ; return

; called from #268A with HL == #62A6 = master direction vector for lower level

26DE: CB 7E       bit     7,(hl)      ; is this direction moving right ?
26E0: CA E6 26    jp      z,$26e6     ; yes, skip next 2 steps

26E3: 36 02       ld      (hl),$02    ; store 2 into (HL) - reverses the pie tray direction (now moving right)
26E5: C9          ret                 ; return

26E6: 36 FE       ld      (hl),$fe    ; store #FE into (HL) - reverses the pie tray direction (now moving left)
26E8: C9          ret                 ; return

; called when deciding which way to switch the pie tray direction vectors
; HL is preloaded with the master direction vector for the tray

26E9: 3A 1A 60    ld      a,(framecounter_601a) ; load with clock counts down from #FF to 00 over and over...
26EC: E6 01       and     $01         ; mask bits.  now either 0 or 1.  zero?
26EE: C8          ret     z           ; yes, return.  every other frame the pie tray is stationary

26EF: CB 7E       bit     7,(hl)      ; check bit 7 of (HL) - this is the master direction for this tray
26F1: 3E FF       ld      a,$ff       ; load A with vector for tray moving to left
26F3: C2 F8 26    jp      nz,$26f8    ; not zero, skip next step

26F6: 3E 01       ld      a,$01       ; load A with vector for tray moving to right
26F8: 77          ld      (hl),a      ; store result
26F9: C9          ret                 ; return

; arrive here from main routine at #19A7

26FA: 3E 04       ld      a,$04       ; A := 4 = 0100 binary
26FC: F7          rst     $30         ; only continue here if elevators, else RET

; elevators only

26FD: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
2700: FE F0       cp      $f0         ; is mario too low ?
2702: D2 7F 27    jp      nc,$277f    ; yes, then mario dead

2705: 3A 29 62    ld      a,(level_number_6229)   ; else load A with level number
2708: 3D          dec     a           ; decrement and check for zero
2709: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
270C: C2 1A 27    jp      nz,$271a    ; if level <> 1 then jump ahead

; slow elevators for level 1, japanese rom only?

270F: E6 03       and     $03         ; mask bits of timer, now between 0 and 3
2711: FE 01       cp      $01         ; == 1 ?
2713: CA 1E 27    jp      z,$271e     ; yes, skip ahead and return

2716: DA 22 27    jp      c,$2722     ; if greater, then jump ahead and move elevators ?

2719: C9          ret                 ; else return

271A: 0F          rrca                ; rotate right the timer
271B: DA 22 27    jp      c,$2722     ; if carry jump ahead and move the elevators (50% of time)

271E: CD 45 27    call    $2745       ; handle if mario is riding elevators
2721: C9          ret                 ; return

2722: CD 97 27    call    $2797       ; move elevators
2725: CD DA 27    call    $27da       ; check for and set elevators that have reset
2728: 06 06       ld      b,$06       ; For B = 1 to 6
272A: 11 10 00    ld      de,$0010    ; load offset
272D: 21 58 69    ld      hl,elevator_sprites_6958    ; load starting value for elevator sprites
2730: DD 21 00 66 ld      ix,elevator_array_start_6600    ; memory where elevator values are stored

; update elevator sprites

2734: DD 7E 03    ld      a,(ix+$03)  ; load X position value for elevator
2737: 77          ld      (hl),a      ; store into sprite value X position
2738: 2C          inc     l
2739: 2C          inc     l
273A: 2C          inc     l           ; HL now has sprite Y value
273B: DD 7E 05    ld      a,(ix+$05)  ; load A with elevator Y position
273E: 77          ld      (hl),a      ; store into sprite Y position
273F: 2C          inc     l           ; next position
2740: DD 19       add     ix,de       ; next elevator
2742: 10 F0       djnz    $2734       ; Next B

2744: C9          ret                 ; return

; called from #271E

2745: 3A 98 63    ld      a,(elevator_status_6398)   ; load A with elevator riding indicator
2748: A7          and     a           ; is mario riding an elevator?
2749: C8          ret     z           ; no, return

274A: 3A 16 62    ld      a,(jumping_status_6216)   ; load A with jumping status
274D: A7          and     a           ; is mario jumping ?
274E: C0          ret     nz          ; yes, return

; arrive here when mario riding on either elevator

274F: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position. eg 37 for first, 75 for second
2752: FE 2C       cp      $2c         ; position < left edge of first elevator ?
2754: DA 66 27    jp      c,$2766     ; yes, jump ahead

2757: FE 43       cp      $43         ; else is position < right edge of first elevator ?
2759: DA 6F 27    jp      c,$276f     ; yes, jump ahead for first elevator checks

275C: FE 6C       cp      $6c         ; else is position < left edge of second elevator?
275E: DA 66 27    jp      c,$2766     ; yes, jump ahead

2761: FE 83       cp      $83         ; else is position < right edge of second elevator ?
2763: DA 87 27    jp      c,$2787     ; yes, jump ahead for second elevator checks

; arrive here when mario jumps off of an elevator ?

2766: AF          xor     a           ; A := 0
2767: 32 98 63    ld      (elevator_status_6398),a   ; clear elevator riding indicator
276A: 3C          inc     a           ; A := 1
276B: 32 21 62    ld      (mario_falling_indicator_6221),a   ; store into mario falling indicator ?
276E: C9          ret                 ; return

; arrive here when mario riding on first elevator

276F: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
2772: FE 71       cp      $71         ; top of elevator ? (death)
2774: DA 7F 27    jp      c,$277f     ; yes, die

2777: 3D          dec     a           ; else decrement (move mario up)
2778: 32 05 62    ld      (return_without_taking_the_ladder_6205),a   ; store into Mario's Y position
277B: 32 4F 69    ld      (mario_sprite_y_value_694f),a   ; store into mario sprite Y value
277E: C9          ret                 ; return

277F: AF          xor     a           ; A := 0
2780: 32 00 62    ld      (mario_array_6200),a   ; Make mario dead
2783: 32 98 63    ld      (elevator_status_6398),a   ; clear elevator riding indicator
2786: C9          ret                 ; return

; riding on second elevator

2787: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
278A: FE E8       cp      $e8         ; at bottom of elevator ? (death)
278C: D2 7F 27    jp      nc,$277f    ; yes, set death and return

278F: 3C          inc     a           ; else increment (move mario down)
2790: 32 05 62    ld      (return_without_taking_the_ladder_6205),a   ; store back into mario's Y position
2793: 32 4F 69    ld      (mario_sprite_y_value_694f),a   ; store into mario sprite Y value
2796: C9          ret                 ; return

; called from #2722
; moves elevators ???

2797: 06 06       ld      b,$06       ; for B = 1 to 6 (for each elevator)
2799: 11 10 00    ld      de,$0010    ; load DE with offset
279C: DD 21 00 66 ld      ix,elevator_array_start_6600    ; load IX with start of sprite addr. for elevators

27A0: DD CB 00 46 bit     0,(ix+$00)  ; is this elevator active?
27A4: CA C2 27    jp      z,$27c2     ; no, skip ahead and loop for next

27A7: DD CB 0D 5E bit     3,(ix+$0d)  ; is this elevator moving down ?
27AB: CA C7 27    jp      z,$27c7     ; yes, skip ahead

; elevator is moving up

27AE: DD 7E 05    ld      a,(ix+$05)  ; load A with elevator Y position
27B1: 3D          dec     a           ; decrement (move up)
27B2: DD 77 05    ld      (ix+$05),a  ; store result
27B5: FE 60       cp      $60         ; at top of elevator ?
27B7: C2 C2 27    jp      nz,$27c2    ; no, skip next 2 steps

27BA: DD 36 03 77 ld      (ix+$03),$77; set X position to right side of elevators
27BE: DD 36 0D 04 ld      (ix+$0d),$04; set direction to down

27C2: DD 19       add     ix,de       ; add offset for next elevator
27C4: 10 DA       djnz    $27a0       ; next B
27C6: C9          ret                 ; return

; elevator is moving down

27C7: DD 7E 05    ld      a,(ix+$05)  ; load A with elevator Y position
27CA: 3C          inc     a           ; increase (move down)
27CB: DD 77 05    ld      (ix+$05),a  ; store result
27CE: FE F8       cp      $f8         ; at bottom of shaft ?
27D0: C2 C2 27    jp      nz,$27c2    ; no, loop for next

27D3: DD 36 00 00 ld      (ix+$00),$00; yes, make this elevator inactive
27D7: C3 C2 27    jp      $27c2       ; jump back and loop for next elevator

; called from #2725

; [IF elevator_counter <> 0 THEN ( elevator_counter--  ; RETURN ) ELSE (

27DA: 21 A7 62    ld      hl,elevator_counter_address_62a7    ; load HL with elevator counter address
27DD: 7E          ld      a,(hl)      ; load A with elevator counter
27DE: A7          and     a           ; == 0 ?
27DF: C2 06 28    jp      nz,$2806    ; no, skip ahead, decrease counter and return

27E2: 06 06       ld      b,$06       ; for B = 1 to 6 elevators
27E4: DD 21 00 66 ld      ix,elevator_array_start_6600    ; load IX with sprite addr. for elevators

27E8: DD CB 00 46 bit     0,(ix+$00)  ; is this elevator active ?
27EC: CA F4 27    jp      z,$27f4     ; no, skip ahead and reset

27EF: DD 19       add     ix,de       ; add offset for next elevator
27F1: 10 F5       djnz    $27e8       ; next B
27F3: C9          ret                 ; return

27F4: DD 36 00 01 ld      (ix+$00),$01; make elevator active
27F8: DD 36 03 37 ld      (ix+$03),$37; set X position to left side shaft
27FC: DD 36 05 F8 ld      (ix+$05),$f8; set Y position to bottom of shaft
2800: DD 36 0D 08 ld      (ix+$0d),$08; set direction to up
2804: 36 34       ld      (hl),$34    ; reset elevator counter to #34

2806: 35          dec     (hl)        ; decrease elevator counter
2807: C9          ret                 ; return

; called from main routine at #19B3
; checks for collisions with hostiles sprites

2808: FD 21 00 62 ld      iy,mario_array_6200    ; load IY with start of mario sprite
280C: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
280F: 4F          ld      c,a         ; copy to C
2810: 21 07 04    ld      hl,$0407    ; H := 4, L := 7
2813: CD 6F 28    call    $286f       ; checks for collisions based on the screen.  A := 1 if collision, otherwise zero
2816: A7          and     a           ; was there a collision ?
2817: C8          ret     z           ; no, return

; mario collided with hostile sprite

2818: 3D          dec     a           ; else A := 0
2819: 32 00 62    ld      (mario_array_6200),a   ; store into mario life indicator, mario is dead
281C: C9          ret                 ; return

; called from main routine at #19B6

281D: 06 02       ld      b,$02       ; for B = 1 to 2 hammers
281F: 11 10 00    ld      de,$0010    ; load DE with counter offset
2822: FD 21 80 66 ld      iy,software_address_of_hammer_sprite_6680    ; load IY with sprite address start ?

2826: FD CB 01 46 bit     0,(iy+$01)  ; is the hammer being used ?
282A: C2 32 28    jp      nz,$2832    ; yes, then do stuff ahead

282D: FD 19       add     iy,de       ; else look at next one
282F: 10 F5       djnz    $2826       ; next B

2831: C9          ret                 ; return

; hammer is active, do stuff for it

2832: FD 4E 05    ld      c,(iy+$05)  ; C := +5 (X position???)
2835: FD 66 09    ld      h,(iy+$09)  ; H := +9 (size?  width?)
2838: FD 6E 0A    ld      l,(iy+$0a)  ; L := +A (size?  height?)
283B: CD 6F 28    call    $286f       ; checks for collisions based on the screen.  A := 1 if collision, otherwise zero
283E: A7          and     a           ; was there a collision?
283F: C8          ret     z           ; no, return

; hammer hit something

2840: 32 50 63    ld      (item_hit_indicator_unknown_6350),a   ; store A into item hit indicator ???
2843: 3A B9 63    ld      a,(counter_for_use_later_63b9)   ; load A with the number of total items checked for collision?
2846: 90          sub     b           ; subract the number of item hit ?
2847: 32 54 63    ld      (unknown_6354),a   ; store into ???
284A: 7B          ld      a,e         ; load A with offset for each item
284B: 32 53 63    ld      (unknown_6353),a   ; store into ???
284E: DD 22 51 63 ld      (unknown_6351),ix  ; store IX into ???
2852: C9          ret                 ; return

; called when mario jumping, checks for items being jumped over
; arrive at apex of jump
; called from #1C20

2853: FD 21 00 62 ld      iy,mario_array_6200    ; load IY with start of mario array
2857: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
285A: C6 0C       add     a,$0c       ; add #0C (12 decimal)
285C: 4F          ld      c,a         ; copy to C
285D: 3A 10 60    ld      a,(inputstate_6010) ; load A with copy of input (see RawInput). except when jump pressed, bit 7 is set momentarily.
2860: E6 03       and     $03         ; mask bits, now between 0 and 3
2862: 21 08 05    ld      hl,$0508    ; H := #05, L := #08.  [H is the left-right window for jumping items, L is the up-down window?]
2865: CA 6B 28    jp      z,$286b     ; if masked input was zero, skip next step

; player moving joystick left or right while jumping

2868: 21 08 13    ld      hl,$1308    ; H := #13 (19 decimal) , L := #08. [ why is L set again ???]  [H is the left-right window, increased if joystick moved left or right]

286B: CD 88 3E    call    $3e88       ; check for items being jumped based on which screen this is [seems like a patch ?  what was original code? CALL #286F ?]
286E: C9          ret                 ; return


        ; 3E88  3A2762    LD      A,(#6227)     ; load A with screen number
        ; 3E8B  E5        PUSH    HL            ; save HL
        ; 3E8C  EF        RST     #28           ; jump to new location based on screen number

        ; data for above:

        ; 3E8D  00 00
        ; 3E8F  99 3E                           ; #3E99 - girders
        ; 3E91  B0 28                           ; #28B0 - pie
        ; 3E93  E0 28                           ; #28E0 - elevator
        ; 3E95  01 29                           ; #2901 - rivets



; called when hammer active from #283B - check for hammer collision with enemy sprites


286F: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
2872: E5          push    hl          ; save HL

2873: EF          rst     $28         ; jump to address below depending on screen:

2874  00 00                             ; unused
2876  80 28                             ; #2880 - girders
2878  B0 28                             ; #28B0 - conveyors
287A  E0 28                             ; #28E0 - elevators
287C  01 29                             ; #2901 - rivets
287E  00 00                             ; unused

; girders - check for collisions with barrels and fires and oil can

2880: E1          pop     hl          ; restore HL
2881: 06 0A       ld      b,$0a       ; B := #0A (10 decimal).  one for each barrel
2883: 78          ld      a,b         ; A := #0A
2884: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
2887: 11 20 00    ld      de,$0020    ; load DE with offset of #20
288A: DD 21 00 67 ld      ix,start_of_barrel_info_table_6700    ; load IX with start of barrels
288E: CD 13 29    call    $2913       ; check for collisions with barrels
2891: 06 05       ld      b,$05       ; B := 5
2893: 78          ld      a,b         ; A := 5
2894: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
2897: 1E 20       ld      e,$20       ; E := #20
2899: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; load IX with start of fires
289D: CD 13 29    call    $2913       ; check for collisions with fires
28A0: 06 01       ld      b,$01       ; B := 1
28A2: 78          ld      a,b         ; A := 1
28A3: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
28A6: 1E 00       ld      e,$00       ; E := #00
28A8: DD 21 A0 66 ld      ix,oil_can_address_66a0    ; load IX with oil can fire location
28AC: CD 13 29    call    $2913       ; check for collision with oil can fire
28AF: C9          ret                 ; return

; jump here from #3E8C when jumping/hammering ? on the pie factory

28B0: E1          pop     hl          ; restore HL
28B1: 06 05       ld      b,$05       ; B := 5 fires
28B3: 78          ld      a,b         ; A := 5 fires
28B4: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
28B7: 11 20 00    ld      de,$0020    ; load DE with offset
28BA: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; load IX with start of fires
28BE: CD 13 29    call    $2913       ; check for collisions with fires
28C1: 06 06       ld      b,$06       ; B := 6
28C3: 78          ld      a,b         ; A := 6
28C4: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
28C7: 1E 10       ld      e,$10       ; E := #10
28C9: DD 21 A0 65 ld      ix,start_of_pies_65a0    ; load IX with start of pies
28CD: CD 13 29    call    $2913       ; check for collisions with pies
28D0: 06 01       ld      b,$01       ; B := 1
28D2: 78          ld      a,b         ; A := 1
28D3: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
28D6: 1E 00       ld      e,$00       ; E := 0
28D8: DD 21 A0 66 ld      ix,oil_can_address_66a0    ; load IX with oil can address
28DC: CD 13 29    call    $2913       ; check for collision with oil can fire
28DF: C9          ret                 ; return

; jump here from #2873 or #3E8C when on the elevators

28E0: E1          pop     hl          ; restore HL
28E1: 06 05       ld      b,$05       ; B := 5
28E3: 78          ld      a,b         ; A := 5
28E4: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
28E7: 11 20 00    ld      de,$0020    ; load offset
28EA: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; load start of addresses for fires
28EE: CD 13 29    call    $2913       ; check for collisions with fires
28F1: 06 0A       ld      b,$0a       ; B := #0A
28F3: 78          ld      a,b         ; A := #0A
28F4: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store counter for use later
28F7: 1E 10       ld      e,$10       ; E := #10
28F9: DD 21 00 65 ld      ix,start_of_bouncer_memory_area_6500    ; load IX with start of addresses for springs
28FD: CD 13 29    call    $2913       ; check for collisions with springs
2900: C9          ret                 ; return

; jump here from #3E8C when on the rivets
; check for collisions with firefoxes and squares next to kong

2901: E1          pop     hl          ; restore HL
2902: 06 07       ld      b,$07       ; B := 7
2904: 78          ld      a,b         ; A := 7
2905: 32 B9 63    ld      (counter_for_use_later_63b9),a   ; store 7 into counter for use later
2908: 11 20 00    ld      de,$0020    ; load DE with offset
290B: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; load IX with start of firefox arrays
290F: CD 13 29    call    $2913       ; check for collisions with firefoxes/squares
2912: C9          ret                 ; return

; core routine gets called a lot
; uses IX and DE and IY
; uses B for loop counter
; uses C for a memory location start
; HL are used
; seems to return a value in A as either 0 or 1
; check for sprite collision ???


2913: DD E5       push    ix          ; push IX to stack

; start of loop

2915: DD CB 00 46 bit     0,(ix+$00)  ; is this sprite active?
2919: CA 4C 29    jp      z,$294c     ; no, add offset in DE and loop again

291C: 79          ld      a,c         ; no, load A with C
291D: DD 96 05    sub     (ix+$05)    ; subtract the Y value of item 2
2920: D2 25 29    jp      nc,$2925    ; if no carry, skip next step

2923: ED 44       neg                 ; A = 0 - A (negate with 2's complement)

2925: 3C          inc     a           ; A := A + 1
2926: 95          sub     l           ; subtract L [???]
2927: DA 30 29    jp      c,$2930     ; on carry, skip next 2 steps

292A: DD 96 0A    sub     (ix+$0a)    ; subtract +#0A value height???
292D: D2 4C 29    jp      nc,$294c    ; if no carry, add offset in DE and loop again

2930: FD 7E 03    ld      a,(iy+$03)  ; load A with X position of item 1
2933: DD 96 03    sub     (ix+$03)    ; subtract X position of item 2.  carry?
2936: D2 3B 29    jp      nc,$293b    ; no, skip next step

2939: ED 44       neg                 ; A = 0 - A (negate with 2's complement)

293B: 94          sub     h           ; subtract H
293C: DA 45 29    jp      c,$2945     ; on carry, skip next 2 steps

293F: DD 96 09    sub     (ix+$09)    ; subtract +#09 value width???
2942: D2 4C 29    jp      nc,$294c    ; if no carry, add offset in DE and loop again

; else a collision

2945: 3E 01       ld      a,$01       ; A := 1 - code for collision
2947: DD E1       pop     ix          ; restore IX
2949: 33          inc     sp
294A: 33          inc     sp          ; adjust SP for higher level subroutine
294B: C9          ret                 ; return to higher subroutine

294C: DD 19       add     ix,de       ; add offset for next sprite
294E: 10 C5       djnz    $2915       ; Next B

2950: AF          xor     a           ; A := 0 - code for no collision
2951: DD E1       pop     ix          ; restore IX
2953: C9          ret                 ; return

; arrive here when jumping at top of jump, check for hammer grab

2954: 3E 0B       ld      a,$0b       ; A := #0B = 1011 binary
2956: F7          rst     $30         ; if level is elevators RET from this sub now.  no hammers on elevators.
2957: CD 74 29    call    $2974       ; load A with 1 if hammer is grabbed, 0 if no grab
295A: 32 18 62    ld      (mario_is_grabbing_the_hammer_until_he_lands_6218),a   ; store into hammer grabbing indicator
295D: 0F          rrca
295E: 0F          rrca                ; rotate right twice.  if hammer grabbed, A is now #40
295F: 32 85 60    ld      (play_sound_for_bonus_6085),a   ; play sound for bonus
2962: 78          ld      a,b         ; A := B .  this indicates which hammer was grabbed if any
2963: A7          and     a           ; was a hammer grabbed?
2964: C8          ret     z           ; no, return

2965: FE 01       cp      $01         ; was lower hammer on girders & conveyors, or upper hammer on rivets, grabbed?
2967: CA 6F 29    jp      z,$296f     ; yes, skip next 2 steps

296A: DD 36 01 01 ld      (ix+$01),$01; set 1st hammer active
296E: C9          ret                 ; return

296F: DD 36 11 01 ld      (ix+$11),$01; set 2nd hammer active
2973: C9          ret                 ; return

; called from #2957 above
; check for hammer grab ?

2974: FD 21 00 62 ld      iy,mario_array_6200    ; load IY with start of mario sprite values
2978: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
297B: 4F          ld      c,a         ; copy to C
297C: 21 08 04    ld      hl,$0408    ; H := 4, L := 8
297F: 06 02       ld      b,$02       ; B := 2 for the 2 hammers (?)
2981: 11 10 00    ld      de,$0010    ; offset for each hammer
2984: DD 21 80 66 ld      ix,software_address_of_hammer_sprite_6680    ; load IX with start of hammer sprites ?
2988: CD 13 29    call    $2913       ; check for collision with hammer
298B: C9          ret                 ; return

; called from #323E
; fire moving.  check for girder edge near fire
; sets A := 0 if fire is free to move
; sets A := 1 if fire is next to edge of girder

298C: 2A C8 63    ld      hl,(address_of_fireball_slot_for_this_fireball_63c8)  ; load HL with address of this fire
298F: 7D          ld      a,l         ; A := L
2990: C6 0E       add     a,$0e       ; add #E
2992: 6F          ld      l,a         ; store result.  HL now has the fire's X position
2993: 56          ld      d,(hl)      ; load D with the fire's X position
2994: 2C          inc     l           ; next HL = fire's Y position
2995: 7E          ld      a,(hl)      ; load A with the fire's Y position
2996: C6 0C       add     a,$0c       ; add #C to offset
2998: 5F          ld      e,a         ; store into E
2999: EB          ex      de,hl       ; DE <> HL
299A: CD F0 2F    call    $2ff0       ; convert HL into VRAM memory location
299D: 7E          ld      a,(hl)      ; load A with the screen element at this location
299E: FE B0       cp      $b0         ; > #B0 ?
29A0: DA AC 29    jp      c,$29ac     ; yes, skip next 5 steps, set A := 1 and return

29A3: E6 0F       and     $0f         ; else mask bits, now between 0 and #F
29A5: FE 08       cp      $08         ; <= 8 ?
29A7: D2 AC 29    jp      nc,$29ac    ; yes, skip next 2 steps, set A := 1 and return

29AA: AF          xor     a           ; A := 0 = clear signal
29AB: C9          ret                 ; return

29AC: 3E 01       ld      a,$01       ; A := 1 = fire near girder edge
29AE: C9          ret                 ; return

; called from #2B23 during a jump

29AF: 3E 04       ld      a,$04       ; A := 4 = 0100
29B1: F7          rst     $30         ; only continue here if we are on the elevators, else RET

29B2: FD 21 00 62 ld      iy,mario_array_6200    ; load IY with mario's array
29B6: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
29B9: 4F          ld      c,a         ; copy to C
29BA: 21 08 04    ld      hl,$0408    ; H := 4, L := 8
29BD: CD 22 2A    call    $2a22       ; check for collision with elevators
29C0: A7          and     a           ; was there a collision?
29C1: CA 20 2A    jp      z,$2a20     ; no, load B with #00 and return

; arrive here when landing near an elevator
; B has the index of the elevator that we hit

29C4: 3E 06       ld      a,$06       ; A := 6
29C6: 90          sub     b           ; subtract B.  zero ?
29C7: CA D0 29    jp      z,$29d0     ; yes, skip ahead

29CA: DD 19       add     ix,de       ; else add offset for next elevator
29CC: 3D          dec     a           ; decrease counter
29CD: C3 C7 29    jp      $29c7       ; loop again

; IX now has the array start for the elevator mario trying to land on

29D0: DD 7E 05    ld      a,(ix+$05)  ; load A with elevator's height Y position
29D3: D6 04       sub     $04         ; subtract 4
29D5: 57          ld      d,a         ; copy to D
29D6: 3A 0C 62    ld      a,(mario_jump_height_620c)   ; load A with mario's jump height ?
29D9: C6 05       add     a,$05       ; add 5
29DB: BA          cp      d           ; compare.  is mario high enough to land ?
29DC: D2 EE 29    jp      nc,$29ee    ; no, skip ahead

29DF: 7A          ld      a,d         ; load A with elevator's height - 4
29E0: D6 08       sub     $08         ; subtract 8
29E2: 32 05 62    ld      (return_without_taking_the_ladder_6205),a   ; store A into Mario's Y position
29E5: 3E 01       ld      a,$01       ; A := 1
29E7: 47          ld      b,a         ; B := 1
29E8: 32 98 63    ld      (elevator_status_6398),a   ; set elevator riding indicator ?
29EB: 33          inc     sp
29EC: 33          inc     sp          ; increase SP twice so the RET skips one level
29ED: C9          ret                 ; returns to higher subroutine (#1C08)

29EE: 3A 0C 62    ld      a,(mario_jump_height_620c)   ; load A with mario's jump height
29F1: D6 0E       sub     $0e         ; subtract #0E (14 decimal)
29F3: BA          cp      d           ; compare to elevator height - 4. is mario hitting his head on the bottom of the elevator ?
29F4: D2 1B 2A    jp      nc,$2a1b    ; if so, mario is dead.  set dead and return.

29F7: 3A 10 62    ld      a,(mario_jump_direction_6210)   ; load A with mario's jump direction.
29FA: A7          and     a           ; == 0 ?  Is mario jumping to the right ?
29FB: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
29FE: CA 08 2A    jp      z,$2a08     ; if jumping to the right then skip ahead

2A01: F6 07       or      $07         ; else mask bits, turn on all 3 lower bits
2A03: D6 04       sub     $04         ; subtract 4
2A05: C3 0E 2A    jp      $2a0e       ; skip next 3 steps

2A08: D6 08       sub     $08         ; subtract 8
2A0A: F6 07       or      $07         ; turn on all 3 lower bits
2A0C: C6 04       add     a,$04       ; add 4

; used when riding an elevator

2A0E: 32 03 62    ld      (jump_if_bit_7_of_mario_x_position_is_set_6203),a   ; set mario's X position
2A11: 32 4C 69    ld      (mario_sprite_x_position_694c),a   ; set mario's sprite X position
2A14: 3E 01       ld      a,$01       ; A := 1
2A16: 06 00       ld      b,$00       ; B := 0
2A18: 33          inc     sp
2A19: 33          inc     sp          ; set stack to next higher subroutine return
2A1A: C9          ret                 ; return to higher level (#1C08)

; arrive from #29F4 when mario dies trying to jump onto elevator

2A1B: AF          xor     a           ; A := 0
2A1C: 32 00 62    ld      (mario_array_6200),a   ; set mario dead
2A1F: C9          ret                 ; return

; arrive from #29C1

2A20: 47          ld      b,a         ; B := 0
2A21: C9          ret                 ; return

; called from #29BD

2A22: 06 06       ld      b,$06       ; B := 6
2A24: 11 10 00    ld      de,$0010    ; load DE with offset
2A27: DD 21 00 66 ld      ix,elevator_array_start_6600    ; load IX with elevator array start
2A2B: CD 13 29    call    $2913       ; check for collision with elevators
2A2E: C9          ret                 ; return

; sub called during a barrel roll from #2057
; only called when barrel going over edge to next girder or for crazy barrel ?
; returns with A loaded with 0 or 1 depending on ???

2A2F: DD 7E 03    ld      a,(ix+$03)  ; load A with Barrel's X position
2A32: 67          ld      h,a         ; Store into H
2A33: DD 7E 05    ld      a,(ix+$05)  ; load A with Barrel's Y position
2A36: C6 04       add     a,$04       ; Add 4
2A38: 6F          ld      l,a         ; Store in L
2A39: E5          push    hl          ; Save HL to stack
2A3A: CD F0 2F    call    $2ff0       ; convert HL into VRAM memory address
2A3D: D1          pop     de          ; load DE with HL = barrel position X,Y
2A3E: 7E          ld      a,(hl)      ; load A with the graphic at this location


B0 = Girder with hole in center used in rivets screen
B6 = white line on top
B7 = wierd icon?
B8 = red line on bottom
C0 - C7 = girder with ladder on bottom going up
D0 - D7 = ladder graphic with girder under going up and out
DD = HE  (help graphic)
DE = EL
DF = P!
E1 - E7 = grider graphic going up and out
EC - E8 = blank ?
EF = P!
EE = EL (part of help graphic)
ED = HE (help graphic)
F6 - F0 = girder graphic in several vertical phases coming up from bottom
F7 = bottom yellow line
FA - F8 = blank ?
FB = ? (actually a question mark)
FC = right red edge
FD = left red edge
FE = X graphic
FF = Extra Mario Icon


2A3F: FE B0       cp      $b0         ; < #B0 ?
2A41: DA 7B 2A    jp      c,$2a7b     ; yes, skip ahead,  clear A to 0 and return - nothing to do.

2A44: E6 0F       and     $0f         ; mask bits.  now between 0 and #F
2A46: FE 08       cp      $08         ; < 8 ?
2A48: D2 7B 2A    jp      nc,$2a7b    ; no, skip ahead, clear A to 0 and return - nothing to do.

2A4B: 7E          ld      a,(hl)      ; load A with graphic at this location
2A4C: FE C0       cp      $c0         ; == girder with ladder on bottom going up ?
2A4E: CA 7B 2A    jp      z,$2a7b     ; yes, clear A to 0 and return - nothing to do.

2A51: DA 69 2A    jp      c,$2a69     ; < this value ?  if so, skip ahead

2A54: FE D0       cp      $d0         ; > ladder graphic with girder under going up and out ?
2A56: DA 6E 2A    jp      c,$2a6e     ; yes, skip ahead to handle

2A59: FE E0       cp      $e0         ; > grider graphic going up and out ?
2A5B: DA 63 2A    jp      c,$2a63     ; yes, skip next 2 steps

2A5E: FE F0       cp      $f0         ; > girder graphic in several vertical phases coming up from bottom ?
2A60: DA 6E 2A    jp      c,$2a6e     ; yes, skip ahaed to handle

; arrive when crazy barrel hitting top of girder ?

2A63: E6 0F       and     $0f         ; mask bits, now between 0 and #F
2A65: 3D          dec     a           ; decrease
2A66: C3 72 2A    jp      $2a72       ; skip ahead

; arrive when ???

2A69: 3E FF       ld      a,$ff       ; A := #FF
2A6B: C3 72 2A    jp      $2a72       ; skip next 2 steps

; arrive when ???

2A6E: E6 0F       and     $0f         ; mask bits, now between 0 and #F
2A70: D6 09       sub     $09         ; subtract 9

; other conditions all arrive here
; A is loaded with a number between #F6 and #E

2A72: 4F          ld      c,a         ; C := A
2A73: 7B          ld      a,e         ; A := E = barrel X position
2A74: E6 F8       and     $f8         ; mask bits.  lower 3 bits are cleared
2A76: 81          add     a,c         ; add C
2A77: BB          cp      e           ; compare to barrel's X position.  less?
2A78: DA 7D 2A    jp      c,$2a7d     ; yes, skip next 2 steps

2A7B: AF          xor     a           ; A := 0
2A7C: C9          ret                 ; return

2A7D: D6 04       sub     $04         ; subtract 4
2A7F: DD 77 05    ld      (ix+$05),a  ; store A into Y position
2A82: 3E 01       ld      a,$01       ; A := 1
2A84: C9          ret                 ; return

; called from main routine at #19A1

2A85: 3A 15 62    ld      a,(ladder_status_6215)   ; load ladder status
2A88: A7          and     a           ; is mario on a ladder ?
2A89: C0          ret     nz          ; yes, return

2A8A: 3A 16 62    ld      a,(jumping_status_6216)   ; load jumping status
2A8D: A7          and     a           ; is mario jumping ?
2A8E: C0          ret     nz          ; yes, return

2A8F: 3A 98 63    ld      a,(elevator_status_6398)   ; load A with elevator status
2A92: FE 01       cp      $01         ; is mario riding an elevator?
2A94: C8          ret     z           ; yes, return

2A95: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
2A98: D6 03       sub     $03         ; subtract 3
2A9A: 67          ld      h,a         ; store into H
2A9B: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with Mario's Y position
2A9E: C6 0C       add     a,$0c       ; add #0C = 13 decimal
2AA0: 6F          ld      l,a         ; store into L
2AA1: E5          push    hl          ; save to stack
2AA2: CD F0 2F    call    $2ff0       ; load HL with screen position of mario's feet
2AA5: D1          pop     de          ; restore , DE now has the sprite X,Y addresses
2AA6: 7E          ld      a,(hl)      ; load A with the screen item at mario's feet
2AA7: FE B0       cp      $b0         ; > #B0 ?
2AA9: DA B4 2A    jp      c,$2ab4     ; yes, skip next 4 steps

2AAC: E6 0F       and     $0f         ; else mask bits, now between 0 and #F
2AAE: FE 08       cp      $08         ; > 8 ?
2AB0: D2 B4 2A    jp      nc,$2ab4    ; no, skip next step

2AB3: C9          ret                 ; else return

; arrive when mario near an [left?] edge

2AB4: 7A          ld      a,d         ; load A with mario's X position
2AB5: E6 07       and     $07         ; mask bits, now between 0 and 7.  zero?
2AB7: CA CD 2A    jp      z,$2acd     ; yes, skip ahead, mario is falling

2ABA: 01 20 00    ld      bc,$0020    ; BC := 20
2ABD: ED 42       sbc     hl,bc       ; subtract from HL.  now HL is the next column?
2ABF: 7E          ld      a,(hl)      ; load A with the screen element of this location
2AC0: FE B0       cp      $b0         ; > #B0 ?
2AC2: DA CD 2A    jp      c,$2acd     ; yes, skip ahead, mario is falling

2AC5: E6 0F       and     $0f         ; else mask bits, now betwen 0 and F
2AC7: FE 08       cp      $08         ; > 8 ?
2AC9: D2 CD 2A    jp      nc,$2acd    ; no, mario is falling, skip ahead
2ACC: C9          ret                 ; return

; mario is falling

2ACD: 3E 01       ld      a,$01       ; A := 1
2ACF: 32 21 62    ld      (mario_falling_indicator_6221),a   ; store into mario falling indicator
2AD2: C9          ret                 ; return

; called from #25FE

2AD3: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
2AD6: 47          ld      b,a         ; copy to B
2AD7: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
2ADA: FE 50       cp      $50         ; is mario on upper level ?
2ADC: CA EA 2A    jp      z,$2aea     ; yes, skip ahead

2ADF: FE 78       cp      $78         ; mario on upper pie tray?
2AE1: CA F6 2A    jp      z,$2af6     ; yes, skip ahead

2AE4: FE C8       cp      $c8         ; mario on lower pie tray ?
2AE6: CA F0 2A    jp      z,$2af0     ; yes, skip ahead

2AE9: C9          ret                 ; else return

2AEA: 3A A3 63    ld      a,(top_conveyor_direction_vector_63a3)   ; load A with top conveyor direction vector [why?  level complete here?]
2AED: C3 02 2B    jp      $2b02       ; skip ahead

2AF0: 3A A6 63    ld      a,(pie_direction_lower_level_63a6)   ; load A with pie direction lower level
2AF3: C3 02 2B    jp      $2b02       ; skip ahead

2AF6: 78          ld      a,b         ; load A with mario X position
2AF7: FE 80       cp      $80         ; is mario on the left side of the fire?
2AF9: 3A A5 63    ld      a,(upper_right_pie_tray_vector_63a5)   ; load A with upper right pie tray vector
2AFC: D2 02 2B    jp      nc,$2b02    ; no, skip next step

2AFF: 3A A4 63    ld      a,(upper_left_pie_tray_vector_63a4)   ; else load A with upper left pie tray vector

2B02: 80          add     a,b         ; add vector to mario's X position
2B03: 32 03 62    ld      (jump_if_bit_7_of_mario_x_position_is_set_6203),a   ; set mario's X position
2B06: 32 4C 69    ld      (mario_sprite_x_position_694c),a   ; set mario's sprite X position
2B09: CD 1F 24    call    $241f       ; loads DE with something depending on mario's position
2B0C: 21 03 62    ld      hl,jump_if_bit_7_of_mario_x_position_is_set_6203    ; load HL with mario's X position
2B0F: 1D          dec     e           ; E == 1 ?
2B10: CA 18 2B    jp      z,$2b18     ; yes, skip ahead

2B13: 15          dec     d           ; else D == 1 ?
2B14: CA 1A 2B    jp      z,$2b1a     ; yes, skip ahead
2B17: C9          ret                 ; return

2B18: 35          dec     (hl)        ; decrease mario's X position
2B19: C9          ret                 ; return

2B1A: 34          inc     (hl)        ; increase
2B1B: C9          ret                 ; return

; called from #1C05

2B1C: DD 21 00 62 ld      ix,mario_array_6200    ; set IX for mario's array
2B20: CD 29 2B    call    $2b29       ; do stuff for jumping.  certain crieria will set A and B and return without the rest of this sub.
2B23: CD AF 29    call    $29af       ; handle jump stuff for elevators
2B26: AF          xor     a           ; A := 0
2B27: 47          ld      b,a         ; B := 0
2B28: C9          ret                 ; return

; arrive here when a jump is in progress
; called from #2B20 above

2B29: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
2B2C: 3D          dec     a           ; are we on the girders?
2B2D: C2 53 2B    jp      nz,$2b53    ; No, skip ahead

; jump on girders

2B30: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's x position
2B33: 67          ld      h,a         ; copy to H
2B34: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's y position
2B37: C6 07       add     a,$07       ; add 7 to y position
2B39: 6F          ld      l,a         ; copy to L
2B3A: CD 9B 2B    call    $2b9b       ; check for ???
2B3D: A7          and     a           ; == 0 ?
2B3E: CA 51 2B    jp      z,$2b51     ; yes, skip ahead and return

2B41: 7B          ld      a,e         ; A := E
2B42: 91          sub     c           ; subtract C (???)
2B43: FE 04       cp      $04         ; < 4 ?
2B45: D2 74 2B    jp      nc,$2b74    ; no, skip ahead, clear A and B, and return

2B48: 79          ld      a,c         ; A := C
2B49: D6 07       sub     $07         ; subtract 7
2B4B: 32 05 62    ld      (return_without_taking_the_ladder_6205),a   ; store A into mario's Y position
2B4E: 3E 01       ld      a,$01       ; A : = 1
2B50: 47          ld      b,a         ; B := 1

2B51: E1          pop     hl          ; move stack pointer back 1 level
2B52: C9          ret                 ; return to higher sub (EG #1C08)

; arrive from #2B2D when jumping, not on girders, via call from #2B20

2B53: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario X position
2B56: D6 03       sub     $03         ; subtract 3
2B58: 67          ld      h,a         ; store into H
2B59: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
2B5C: C6 07       add     a,$07       ; add 7
2B5E: 6F          ld      l,a         ; store into L
2B5F: CD 9B 2B    call    $2b9b       ; check for ???
2B62: FE 02       cp      $02         ; A == 2 ?
2B64: CA 7A 2B    jp      z,$2b7a     ; yes, skip ahead

2B67: 7A          ld      a,d         ; A := D
2B68: C6 07       add     a,$07       ; add 7
2B6A: 67          ld      h,a         ; H := A
2B6B: 6B          ld      l,e         ; L := E
2B6C: CD 9B 2B    call    $2b9b       ; check for ???
2B6F: A7          and     a           ; A == 0 ?
2B70: C8          ret     z           ; yes, return

2B71: C3 7A 2B    jp      $2b7a       ; else skip ahead

2B74: 3E 00       ld      a,$00       ; A := 0
2B76: 06 00       ld      b,$00       ; B := 0
2B78: E1          pop     hl          ; move stack pointer to return to higher sub
2B79: C9          ret                 ; return

2B7A: 3A 10 62    ld      a,(mario_jump_direction_6210)   ; load A with mario's jump direction
2B7D: A7          and     a           ; jumping to the right ?
2B7E: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
2B81: CA 8B 2B    jp      z,$2b8b     ; if jumping right then skip next 3 steps

2B84: F6 07       or      $07         ; mask bits, turn on lower 3 bits
2B86: D6 04       sub     $04         ; subtract 4
2B88: C3 91 2B    jp      $2b91       ; skip ahead

2B8B: D6 08       sub     $08         ; subtract 8
2B8D: F6 07       or      $07         ; mask bits, turn on lower 3 bits
2B8F: C6 04       add     a,$04       ; add 4

2B91: 32 03 62    ld      (jump_if_bit_7_of_mario_x_position_is_set_6203),a   ; set mario's X position
2B94: 32 4C 69    ld      (mario_sprite_x_position_694c),a   ; set mario's sprite X position
2B97: 3E 01       ld      a,$01       ; A := 1
2B99: E1          pop     hl          ; move stack pointer to return to higher sub
2B9A: C9          ret                 ; return

; called from #2B3A and #2B6C and #2B5F above

2B9B: E5          push    hl          ; save HL
2B9C: CD F0 2F    call    $2ff0       ; convert HL into VRAM address
2B9F: D1          pop     de          ; restore into DE
2BA0: 7E          ld      a,(hl)      ; load A with the screen item in VRAM
2BA1: FE B0       cp      $b0         ; > #B0 ? (???)
2BA3: DA D9 2B    jp      c,$2bd9     ; yes, skip ahead, set results to zero and return

2BA6: E6 0F       and     $0f
2BA8: FE 08       cp      $08
2BAA: D2 D9 2B    jp      nc,$2bd9    ; yes, skip ahead, set results to zero and return

2BAD: 7E          ld      a,(hl)      ; load A with the screen item in VRAM
2BAE: FE C0       cp      $c0         ; == #C0 ?
2BB0: CA D9 2B    jp      z,$2bd9     ; yes, skip ahead, set results to zero and return

2BB3: DA DC 2B    jp      c,$2bdc     ; < #C0 ?  Yes, skip ahead to handle

2BB6: FE D0       cp      $d0         ; < #D0 ?
2BB8: DA CB 2B    jp      c,$2bcb     ; yes, skip ahead to handle

2BBB: FE E0       cp      $e0         ; < #E0 ?
2BBD: DA C5 2B    jp      c,$2bc5     ; yes, skip ahead to handle

2BC0: FE F0       cp      $f0         ; < #F0 ?
2BC2: DA CB 2B    jp      c,$2bcb     ; yes, skip ahead to handle (same as < #D0 )

; when landing or jumping from a girder ???

2BC5: E6 0F       and     $0f         ; mask bits, now between 0 and #F
2BC7: 3D          dec     a           ; decrease.  now #FF or between 0 and #E
2BC8: C3 CF 2B    jp      $2bcf       ; skip ahead

; when jumping his head (harmlessly) into a girder above him?

2BCB: E6 0F       and     $0f         ; mask bits, now between 0 and #F
2BCD: D6 09       sub     $09         ; subtract 9.  now between #F7 and 6

2BCF: 4F          ld      c,a         ; C := A
2BD0: 7B          ld      a,e         ; A := E = original Y location
2BD1: E6 F8       and     $f8         ; mask bits.  we dont care about 3 least sig. bits
2BD3: 81          add     a,c         ; add C
2BD4: 4F          ld      c,a         ; C := A
2BD5: BB          cp      e           ; < E (original Y location) ?
2BD6: DA E1 2B    jp      c,$2be1     ; no, skip ahead

; mario is jumping clear, nothing in his way

2BD9: AF          xor     a           ; A := 0
2BDA: 47          ld      b,a         ; B := 0
2BDB: C9          ret                 ; return

; mario is jumping and about to land on a conveyor or a girder on the rivets

2BDC: 7B          ld      a,e         ; A := E = original Y location
2BDD: E6 F8       and     $f8         ; mask bits.  we dont care about 3 least sig. bits
2BDF: 3D          dec     a           ; decrease
2BE0: 4F          ld      c,a         ; copy to C

; mario landing or his head passing through girder above

2BE1: 3A 0C 62    ld      a,(mario_jump_height_620c)   ; load A with mario's jump height
2BE4: DD 96 05    sub     (ix+$05)    ; subtract the item's Y position (???) [EG IX = #6200 , so this is mario's Y position)
2BE7: 83          add     a,e         ; add E (original Y position)
2BE8: B9          cp      c           ; == C ?
2BE9: CA EF 2B    jp      z,$2bef     ; yes, skip next step

; mario head passing or landing on a noneven girder

2BEC: D2 F8 2B    jp      nc,$2bf8    ; < C ?  no, skip next 4 steps

;  arrive when landing

2BEF: 79          ld      a,c         ; A := C = original location masked
2BF0: D6 07       sub     $07         ; subtract 7 to adjust for mario' height
2BF2: 32 05 62    ld      (return_without_taking_the_ladder_6205),a   ; store A into mario's Y position
2BF5: C3 FD 2B    jp      $2bfd       ; skip next 3 steps

; arrive when mario has his head passing through girder above

2BF8: 3E 02       ld      a,$02       ; A := 2
2BFA: 06 00       ld      b,$00       ; B := 0
2BFC: C9          ret                 ; return

; arrive when ?

2BFD: 3E 01       ld      a,$01       ; A := 1
2BFF: 47          ld      b,a         ; B := 1
2C00: E1          pop     hl
2C01: E1          pop     hl          ; set stack pointer to return to higher subs
2C02: C9          ret                 ; return

; called from main routine at #1989

2C03: 3E 01       ld      a,$01       ; \ Return if screen is not barrels
2C05: F7          rst     $30         ; /
2C06: D7          rst     $10         ; Return if Mario is not alive

2C07: 3A 93 63    ld      a,(barrel_deployment_indicator_6393)   ; \  Return if we are already in the process of deploying a barrel, no need to deploy another one
2C0A: 0F          rrca                ;  |
2C0B: D8          ret     c           ; /

2C0C: 3A B1 62    ld      a,(bonus_timer_62b1)   ; \  Return if bonus timer is 0, no more barrels are deployed at this time
2C0F: A7          and     a           ;  |
2C10: C8          ret     z           ; /

2C11: 4f          ld      c,a         ; otherwise load C with current timer value
2C12: 3A b0 62    ld      a,(initial_clock_value_62b0)   ; load a with initial clock value
2C15: d6 02       sub     $02         ; subtract 2
2C17: b9          cp      c           ; compare with C = current timer
2C18: dA 7b 2C    jp      c,$2c7b     ; if carry, jump ahead - we are within first 2 clicks of the round - special barrels for this.

2C1B: 3A 82 63    ld      a,(crazy_blue_barrel_indicator_6382)   ; else load A with crazy / blue barrel indicator
2C1E: cb 4f       bit     1,a         ; test bit 1 - is this the second barrel after the first crazy ?
2C20: c2 86 2C    jp      nz,$2c86    ; if it is, then deploy normal barrel; this barrel is never crazy.

2C23: 3A 80 63    ld      a,(difficulty_level_6380)   ; if not, then load A with difficulty from 1 to 5
2C26: 47          ld      b,a         ; For B = 1 to difficulty
2C27: 3A 1A 60    ld      a,(framecounter_601a) ; load A with timer value.  this clock counts down from #FF to 00 over and over...
2C2A: E6 1F       and     $1f         ; zero out left 3 bits.  the result is between 0 and #1F

2C2C: B8          cp      b           ; compare with Loop counter B (between 1 and 5) ... is higher as time decreases
2C2D: CA 33 2C    jp      z,$2c33     ; if it equal then jump ahead to check for a crazy barrel

2C30: 10 FA       djnz    $2c2c       ; else Next B

2C32: C9          ret                 ; Return without crazy barrel (?)

; chances of arriving here depend on difficulty D/32 chance .  high levels this is 5/32 = 16%

2C33: 3A B0 62    ld      a,(initial_clock_value_62b0)   ; load A with initial clock value
2C36: CB 3F       srl     a           ; Shift Right (div 2)
2C38: B9          cp      c           ; is the current timer value < 1/2 initial clock value ?
2C39: DA 41 2C    jp      c,$2c41     ; NO, skip next 3 steps

2C3C: 3A 19 60    ld      a,(rngtimer2_6019) ; Yes, Load A with this timer value (random)
2C3F: 0F          rrca                ; Test Bit 1 of this
2C40: D0          ret     nc          ; If bit 1 is not set, return . this gives 50% extra chance of no crazy barrel when clock is getting low

2C41: CD 57 00    call    $0057       ; else load A with a random number

;; hack to increase crazy barrels
;; 2C41  3E 00          LD A, #00
;; 2C43  00             NOP

;; hack to increase crazy barrels:
;; 2C44 E600    AND     #00             ; mask all 4 bits to zero
;;

2C44: E6 0F       and     $0f         ; mask out left 4 bits to zero.  A becomes a number between 0 and #F
2C46: C2 86 2C    jp      nz,$2c86    ; If result is not zero, deploy a normal barrel.  this routine sets #6382 to 0,
                                        ; loads A with 3 and returns to #2C4F

; else get a crazy barrel
; can arrive here from #2C7E = first click of round is always crazy barrel

2C49: 3E 01       ld      a,$01       ; else A := 1 = crazy barrel code

; arrive here from second barrel that is not crazy.  A is preloaded with 2.  From #2C83

2C4B: 32 82 63    ld      (crazy_blue_barrel_indicator_6382),a   ; set a barrel in motion for next barrel, bit 1=crazy, 2 = second barrel which is always normal, 0 for normal barrel
2C4E: 3C          inc     a           ; Increment A for the deployment

2C4F: 32 8F 63    ld      (deployment_indicator_638f),a   ; store A into the state of the barrel deployment between 3 and 0
2C52: 3E 01       ld      a,$01       ; A := 1
2C54: 32 92 63    ld      (barrel_deployment_indicator_6392),a   ; set barrel deployment indicator
2C57: 3A b2 62    ld      a,(blue_barrel_counter_62b2)   ; load A with blue barrel counter
2C5A: B9          cp      c           ; compare with current timer
2C5B: C0          ret     nz          ; return if not equal

2C5C: D6 08       sub     $08         ; if equal then this will be a blue barrel.  decrement A by 8
2C5E: 32 B2 62    ld      (blue_barrel_counter_62b2),a   ; put back into blue barrel counter
2C61: 11 20 00    ld      de,$0020    ; now check if all 5 fires are out
2C64: 21 00 64    ld      hl,start_of_fires_table_6400    ; #6400 by 20's contian 1 if these fires exist

2C67: 06 05       ld      b,$05       ; FOR B = 1 to 5

2C69: 7E          ld      a,(hl)      ; get fire status
2C6A: A7          and     a           ; is this fire onscreen?
2C6B: CA 72 2C    jp      z,$2c72     ; no, skip next 3 steps; we don't have 5 fires onscreen and therefore have room for a blue barrel

2C6E: 19          add     hl,de       ; yes, add #20 offset to test next fire and loop again
2C6F: 10 F8       djnz    $2c69       ; next B

2C71: C9          ret                 ; not a blue barrel, return

2C72: 3A 82 63    ld      a,(crazy_blue_barrel_indicator_6382)   ; load A with crazy/blue barrel indicator
2C75: f6 80       or      $80         ; or with #80  - set leftmost bit on to indicate blue barrel is next
2C77: 32 82 63    ld      (crazy_blue_barrel_indicator_6382),a   ; store into crazy/blue barrel indicator
2C7A: c9          ret                 ; return with blue barrel

; we arrive here if timer is within first 2 clicks when deploying a barrel from #2C18

2C7B: C6 02       add     a,$02       ; A := A + 2 (A had the initial clock value -2, now it has the initial clock value)
2C7D: B9          cp      c           ; compare to current timer value - are we starting this round now?
2C7E: CA 49 2C    jp      z,$2c49     ; yes, do a crazy barrel

2C81: 3E 02       ld      a,$02       ; else A := 2 for the second barrel; it is always normal
2C83: C3 4B 2C    jp      $2c4b       ; jump back and continue deployment

; arrive here when the second barrel is being deployed?
; from #2C20

2C86: AF          xor     a           ; A := 0
2C87: 32 82 63    ld      (crazy_blue_barrel_indicator_6382),a   ; barrel indicator to 0 == normal barrel
2C8A: 3E 03       ld      a,$03       ; A := 3 -- use for upcoming deployement indicator == position #3
2C8C: C3 4F 2C    jp      $2c4f       ; Jump back

; called from main routine #1986

2C8F: 3E 01       ld      a,$01       ; A := 1 = code for girders
2C91: F7          rst     $30         ; if screen is girders, continue.  else RET
2C92: D7          rst     $10         ; if mario is alive, continue.  else RET
2C93: 3A 93 63    ld      a,(barrel_deployment_indicator_6393)   ; load A with barrel deployment indicator
2C96: 0F          rrca                ; is a barrel being deployed ?
2C97: DA 15 2D    jp      c,$2d15     ; yes, skip ahead

2C9A: 3A 92 63    ld      a,(barrel_deployment_indicator_6392)   ; else load A with other barrel deployment indicator
2C9D: 0F          rrca                ; deployed ?
2C9E: D0          ret     nc          ; no, return

; else a barrel is being deployed

2C9F: DD 21 00 67 ld      ix,start_of_barrel_info_table_6700    ; load IX with start of barrel memory
2CA3: 11 20 00    ld      de,$0020    ; incrementer gets #20
2CA6: 06 0A       ld      b,$0a       ; For B = 1 to #0A (all 10 barrels)

2CA8: DD 7E 00    ld      a,(ix+$00)  ; load A with +0 indicator
2CAB: 0F          rrca                ; is this barrel already rolling ?
2CAC: DA B3 2C    jp      c,$2cb3     ; yes, then jump ahead and test next barrel

2CAF: 0F          rrca                ; else is this barrel already being deployed ?
2CB0: D2 B8 2C    jp      nc,$2cb8    ; no, then jump ahead

2CB3: DD 19       add     ix,de       ; Increase to next barrel
2CB5: 10 F1       djnz    $2ca8       ; Next B

2CB7: C9          ret                 ; return

; arrive here when a barrel is being deployed

2CB8: DD 22 AA 62 ld      (barrel_start_address_62aa),ix  ; save this barrel indicator into #62AA.  it is recalled at #2D55
2CBC: DD 36 00 02 ld      (ix+$00),$02; set deployement indicator
2CC0: 16 00       ld      d,$00       ; D := 0
2CC2: 3E 0A       ld      a,$0a       ; A := #0A
2CC4: 90          sub     b           ; A = A - B ;  B has the number of the barrel A now will be 0 if this is the first barrel, #0A if the last
2CC5: 87          add     a,a         ; A = A * 2
2CC6: 87          add     a,a         ; A = A * 2 (A is now 4 times what it was)
2CC7: 5F          ld      e,a         ; copy this to E
2CC8: 21 80 69    ld      hl,start_of_sprite_memory_for_bouncers_6980    ; load HL with starting sprite address for the barrels
2CCB: 19          add     hl,de       ; Now add in offset depending on the barrel number ( will vary from 0 to #28 by 4's)
2CCC: 22 AC 62    ld      (sprite_variable_start_62ac),hl  ; store this info in #62AC. will vary from #80 to #A8
2CCF: 3E 01       ld      a,$01       ; A := 1
2CD1: 32 93 63    ld      (barrel_deployment_indicator_6393),a   ; set barrel deployment indicator
2CD4: 11 01 05    ld      de,$0501    ; load DE with task #5, parameter 1 update onscreen bonus timer and play sound & change to red if below 1000
2CD7: CD 9F 30    call    $309f       ; insert task
2CDA: 21 B1 62    ld      hl,bonus_timer_62b1    ; load bonus counter into HL
2CDD: 35          dec     (hl)        ; decrement bonus counter.  Is it zero?
2CDE: c2 E6 2C    jp      nz,$2ce6    ; no, skip next 2 steps

2CE1: 3E 01       ld      a,$01       ; A := 1
2CE3: 32 86 63    ld      (time_has_run_out_indicator_6386),a   ; store into bonus timer out indicator

2CE6: 7E          ld      a,(hl)      ; load A with bonus counter
2CE7: FE 04       cp      $04         ; bonus <= 400 ?
2CE9: D2 f6 2C    jp      nc,$2cf6    ; no, skip ahead

2CEC: 21 A8 69    ld      hl,extra_barrels_sprites_69a8    ; else load HL with extra barrels sprites
2CEF: 87          add     a,a
2CF0: 87          add     a,a         ; A := A * 4
2CF1: 5F          ld      e,a         ; copy to E
2CF2: 16 00       ld      d,$00       ; D := 0.  DE now has offset based on timer
2CF4: 19          add     hl,de       ; compute which sprite to remove based on timer
2CF5: 72          ld      (hl),d      ; clear the sprite

; IX holds 6700 +N*20 = start of barrel N info
; a barrel is being deployed

2CF6: DD 36 07 15 ld      (ix+$07),$15; set barrel sprite value to #15
2CFA: DD 36 08 0B ld      (ix+$08),$0b; set barrel color to #0B
2CFE: DD 36 15 00 ld      (ix+$15),$00; set +15 indicator to 0 = normal barrel,  [1 = blue barrel]
2D02: 3A 82 63    ld      a,(crazy_blue_barrel_indicator_6382)   ; load A with Crazy/Blue barrel indicator
2D05: 07          rlca                ; is this a blue barrel ?
2D06: D2 15 2D    jp      nc,$2d15    ; No blue barrel, then skip next 3 steps

; blue barrel

2D09: DD 36 07 19 ld      (ix+$07),$19; set sprite for blue barrel
2D0D: DD 36 08 0C ld      (ix+$08),$0c; set sprite color to blue
2D11: DD 36 15 01 ld      (ix+$15),$01; set blue barrel indicator

2D15: 21 AF 62    ld      hl,kong_misc_counter_62af    ; load HL with deployment timer
2D18: 35          dec     (hl)        ; count it down.  is the timer expired?
2D19: C0          ret     nz          ; no, return

2D1A: 36 18       ld      (hl),$18    ; else reset the counter back to #18
2D1C: 3A 8F 63    ld      a,(deployment_indicator_638f)   ; load A with the deployment indiacator.  2 = kong grabbing, 1 = kong holding, 0 = deploying, 3 = kong empty
2D1F: A7          and     a           ; is a barrel being deployed right now?
2D20: CA 51 2D    jp      z,$2d51     ; yes, jump ahead

2D23: 4F          ld      c,a         ; else copy A to C
2D24: 21 32 39    ld      hl,$3932    ; load HL with table data start
2D27: 3A 82 63    ld      a,(crazy_blue_barrel_indicator_6382)   ; load A with crazy/blue barrel indicator
2D2A: 0F          rrca                ; Is this a crazy barrel?
2D2B: DA 2F 2D    jp      c,$2d2f     ; yes, skip next step

2D2E: 0D          dec     c           ; no, Decrement C

2D2F: 79          ld      a,c
2D30: 87          add     a,a
2D31: 87          add     a,a
2D32: 87          add     a,a
2D33: 4F          ld      c,a
2D34: 87          add     a,a
2D35: 87          add     a,a
2D36: 81          add     a,c
2D37: 5F          ld      e,a         ; A is #50 when barrel is crazy, #28 when normal
2D38: 16 00       ld      d,$00       ; D: = 0
2D3A: 19          add     hl,de       ; HL becomes #3982 when barrel is crazy, 395A when normal, 3932 when deploying all the way.  this will skip the final animation when dropping crazy barrel (?)
2D3B: CD 4E 00    call    $004e       ; update kong's sprites
2D3E: 21 8F 63    ld      hl,deployment_indicator_638f    ; load HL with deployment indicator
2D41: 35          dec     (hl)        ; Decrease indicator
2D42: C2 51 2D    jp      nz,$2d51    ; if indicator is not zero then jump ahead

2D45: 3E 01       ld      a,$01       ; else A := 1
2D47: 32 AF 62    ld      (kong_misc_counter_62af),a   ; Store into ???
2D4A: 3A 82 63    ld      a,(crazy_blue_barrel_indicator_6382)   ; load A with crazy/blue barrel indicator
2D4D: 0F          rrca                ; Is this a crazy barrel?
2D4E: DA 83 2D    jp      c,$2d83     ; yes, jump ahead and load HL with #39CC and store into #62A8 and #62A9 and resume on #2D54

2D51: 2A A8 62    ld      hl,(unknown_rom_address_62a8)  ; else load HL with (???)

2D54: 7E          ld      a,(hl)      ; load A with value in HL.  crazy barrel this value is #BB
2D55: DD 2A AA 62 ld      ix,(barrel_start_address_62aa)  ; load IX with Barrel start address saved above
2D59: ED 5B AC 62 ld      de,(sprite_variable_start_62ac)  ; load DE with sprite variable start  EG #6980.  set in #2CCC
2D5D: FE 7F       cp      $7f         ; A == #7F ? (time to deploy out of kong's hands ?)
2D5F: CA 8C 2D    jp      z,$2d8c     ; yes, jump ahead

2D62: 4F          ld      c,a         ; else copy A into C
2D63: E6 7F       and     $7f         ; mask out leftmost bit.  result between 0 and  #7F
2D65: 12          ld      (de),a      ; store into sprite X position
2D66: DD 7E 07    ld      a,(ix+$07)  ; load A with barrel sprite value
2D69: CB 79       bit     7,c         ; test bit 7 of C
2D6B: CA 70 2D    jp      z,$2d70     ; yes, skip next step

2D6E: EE 03       xor     $03         ; no, toggle the rightmost 2 bits

2D70: 13          inc     de          ; DE now has sprite value
2D71: 12          ld      (de),a      ; store new sprite
2D72: DD 77 07    ld      (ix+$07),a  ; store into barrel sprite value
2D75: DD 7E 08    ld      a,(ix+$08)  ; load A with barrel color
2D78: 13          inc     de          ; DE now has sprite color value
2D79: 12          ld      (de),a      ; store color into sprite
2D7A: 23          inc     hl          ; increase HL.  EG #39CD for crazy barrel
2D7B: 7E          ld      a,(hl)      ; load A with this value.  EG #4D for crazy barrel
2D7C: 13          inc     de          ; DE now has Y position
2D7D: 12          ld      (de),a      ; store into sprite Y position
2D7E: 23          inc     hl          ; increase HL .  EG #39CE for crazy barrel
2D7F: 22 A8 62    ld      (unknown_rom_address_62a8),hl  ; store into 62A8.  EG 62A8 = CE, 62A9 = 39
2D82: C9          ret                 ; return

; arrive here because this barrel is crazy from #2D4E

2D83: 21 CC 39    ld      hl,$39cc    ; load HL with crazy barrel data

        ; 39CC  BB
        ; 39CD  4D

2D86: 22 A8 62    ld      (unknown_rom_address_62a8),hl  ; Load #62A8 and #62A9 with #39 and #CC
2D89: C3 54 2D    jp      $2d54       ; jump back

; jump here from #2D5F
; kong is releasing a barrel (?)

2D8C: 21 C3 39    ld      hl,$39c3    ; load HL with start of table data address
2D8F: 22 A8 62    ld      (unknown_rom_address_62a8),hl  ; store into ???
2D92: DD 36 01 01 ld      (ix+$01),$01; set crazy barrel indicator
2D96: 3A 82 63    ld      a,(crazy_blue_barrel_indicator_6382)   ; load A with crazy/blue barrel indicator

2D99: 0F          rrca                ; roll right.  is this a crazy barrel?
2D9A: DA A5 2D    jp      c,$2da5     ; yes, skip next 2 steps

2D9D: DD 36 01 00 ld      (ix+$01),$00; no , clear crazy indicator
2DA1: DD 36 02 02 ld      (ix+$02),$02; load motion indicator with 2 (rolling right)

2DA5: DD 36 00 01 ld      (ix+$00),$01; barrel is now active
2DA9: DD 36 0F 01 ld      (ix+$0f),$01
2DAD: AF          xor     a           ; A := 0
2DAE: DD 77 10    ld      (ix+$10),a  ; clear this indicator (???)
2DB1: DD 77 11    ld      (ix+$11),a
2DB4: DD 77 12    ld      (ix+$12),a
2DB7: DD 77 13    ld      (ix+$13),a
2DBA: DD 77 14    ld      (ix+$14),a
2DBD: 32 93 63    ld      (barrel_deployment_indicator_6393),a   ; clear barrel deployment indicator
2DC0: 32 92 63    ld      (barrel_deployment_indicator_6392),a   ; clear barrel deployment indicator
2DC3: 1A          ld      a,(de)      ; load A with kong hand sprite X position
2DC4: DD 77 03    ld      (ix+$03),a  ; store in barrel's X position
2DC7: 13          inc     de
2DC8: 13          inc     de
2DC9: 13          inc     de          ; DE := DE + 3 = DE now has kong hand sprite Y position
2DCA: 1A          ld      a,(de)      ; load A with kong hand Y position
2DCB: DD 77 05    ld      (ix+$05),a  ; store in barrel's Y position
2DCE: 21 5C 38    ld      hl,$385c    ; load HL with table data start
2DD1: CD 4E 00    call    $004e       ; update kong's sprites
2DD4: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with start of Kong sprite
2DD7: 0E FC       ld      c,$fc       ; load c with offset of -4
2DD9: FF          rst     $38         ; move kong
2DDA: C9          ret                 ; return

; deploys fireball/firefoxes
; Arrive here from main routine at #1995

2DDB: 3E 0A       ld      a,$0a       ; A := binary 1010 = code for rivets and conveyors
2DDD: F7          rst     $30         ; returns immediately on girders and elevators, else continue

2DDE: D7          rst     $10         ; only continue if mario alive
2DDF: 3A 80 63    ld      a,(difficulty_level_6380)   ; \  load B with (internal_difficulty+1)/2 (get's value between 1 and 3)
2DE2: 3C          inc     a           ;  |
2DE3: A7          and     a           ;  | clear carry flag
2DE4: 1F          rra                 ;  |
2DE5: 47          ld      b,a         ; /
2De6: 3A 27 62    ld      a,(screen_number_6227)   ; \  Increment B by 1 if we are on conveyors (to get value between 2 and 4)
2De9: fe 02       cp      $02         ;  |
2Deb: 20 01       jr      nz,$2dee    ;  |
2Ded: 04          inc     b           ; /

2DEE: 3E FE       ld      a,$fe       ; \  Load A with #FF>>(B-1) (note the first rotate right doesn't count towards the bit shift because the
2DF0: 37          scf                 ;  | carry flag is set)
2DF1: 1F          rra                 ;  |
2DF2: A7          and     a           ;  | clear carry flag
2DF3: 10 FC       djnz    $2df1       ; /

2DF5: 47          ld      b,a         ; \  The result of the above indicates the interval in frames between deploying successive fires.
2DF6: 3A 1A 60    ld      a,(framecounter_601a) ;  | On rivets we proceed every 256 frames for internal difficulty 1 and 2, 128 frames for internal difficulty
2DF9: A0          and     b           ;  | 3 and 4 and 64 frames for internal difficulty 5. On conveyors these values are cut in half.
2DFA: C0          ret     nz          ; /

2DFB: 3E 01       ld      a,$01       ; Time to deploy a fire. Load A with 1
2DFD: 32 A0 63    ld      (unknown_63a0),a   ; deploy a firefox/fireball
2E00: 32 9A 63    ld      (deployment_indicator_639a),a   ; set deployment indicator ?
2E03: C9          ret                 ; return

; called from main routine at #198F
; called during the elevators.  used to move the bouncers ????

2E04: 3E 04       ld      a,$04       ; A := 4 (0100 binary) to check for elevators screen
2E06: F7          rst     $30         ; if not elevators it will return to program

2E07: D7          rst     $10         ; if mario is alive, continue, else RET

2E08: DD 21 00 65 ld      ix,start_of_bouncer_memory_area_6500    ; load IX with start of bouncer memory area
2E0C: FD 21 80 69 ld      iy,start_of_sprite_memory_for_bouncers_6980    ; start of sprite memory for bouncers
2E10: 06 0A       ld      b,$0a       ; for B = 1 to #0A (ten) .  do for all ten sprites

2E12: DD 7E 00    ld      a,(ix+$00)  ; load A with sprite status
2E15: 0F          rrca                ; is the sprite active ?
2E16: D2 A7 2E    jp      nc,$2ea7    ; no, jump ahead and check to deploy a new one

2E19: 3A 1A 60    ld      a,(framecounter_601a) ; else load A with timer

; FrameCounter - Timer constantly counts down from FF to 00 and then FF to 00 again and again ... 1 count per frame
; result is that each of the boucners have their sprites changed once every 16 clicks, or every 1/16 of sec.?

2E1C: E6 0F       and     $0f         ; mask out left 4 bits.  result between 0 and F
2E1E: C2 29 2E    jp      nz,$2e29    ; if not zero, jump ahead..

2E21: FD 7E 01    ld      a,(iy+$01)  ; load A with sprite value
2E24: EE 07       xor     $07         ; flip the right 3 bits
2E26: FD 77 01    ld      (iy+$01),a  ; store result = change the bouncer fom open to closed

2E29: DD 7E 0D    ld      a,(ix+$0d)  ; load A with +D = either 1 or 4.  1 when going across , 4 when going down.
2E2C: FE 04       cp      $04         ; is it == 4 ? (going down?)
2E2E: CA 84 2E    jp      z,$2e84     ; yes, jump ahead

2E31: DD 34 03    inc     (ix+$03)    ; no, increase X position
2E34: DD 34 03    inc     (ix+$03)    ; increase X position again
2E37: DD 6E 0E    ld      l,(ix+$0e)
2E3A: DD 66 0F    ld      h,(ix+$0f)  ; load HL with table address for bouncer offsets of Y positions for each pixel across
2E3D: 7E          ld      a,(hl)      ; load table data
2E3E: 4F          ld      c,a         ; copy to C
2E3F: FE 7F       cp      $7f         ; == #7F ? (end code ?)
2E41: CA 9C 2E    jp      z,$2e9c     ; yes, jump ahead, reset HL to #39AA, play bouncer sound, and continue at #2E4B

2E44: 23          inc     hl          ; next HL
2E45: DD 86 05    add     a,(ix+$05)  ; add item's Y position
2E48: DD 77 05    ld      (ix+$05),a  ; store into item's Y position

2E4B: DD 75 0E    ld      (ix+$0e),l
2E4E: DD 74 0F    ld      (ix+$0f),h  ; store the updated HL for next time
2E51: DD 7E 03    ld      a,(ix+$03)  ; load A with X position
2E54: FE B7       cp      $b7         ; < #B7 ?
2E56: DA 6C 2E    jp      c,$2e6c     ; no, skip ahead

2E59: 79          ld      a,c         ; yes, A := C
2E5A: FE 7F       cp      $7f         ; == #7F (end code?)
2E5C: C2 6C 2E    jp      nz,$2e6c    ; no, skip ahead

2E5F: DD 36 0D 04 ld      (ix+$0d),$04; set +D to 4 (???)
2E63: AF          xor     a           ; A := 0
2E64: 32 83 60    ld      (play_sound_for_bouncer_6083),a   ; clear sound of bouncer
2E67: 3E 03       ld      a,$03       ; load sound duration of 3
2E69: 32 84 60    ld      (play_sound_for_falling_bouncer_6084),a   ; play sound for falling bouncer

2E6C: DD 7E 03    ld      a,(ix+$03)  ; load A with X position
2E6F: FD 77 00    ld      (iy+$00),a  ; store into sprite
2E72: DD 7E 05    ld      a,(ix+$05)  ; load A with Y position
2E75: FD 77 03    ld      (iy+$03),a  ; store into sprite

2E78: 11 10 00    ld      de,$0010    ; set offset to add
2E7B: DD 19       add     ix,de       ; next sprite (IX)
2E7D: 1E 04       ld      e,$04       ; E := 4
2E7F: FD 19       add     iy,de       ; next sprite (IY)
2E81: 10 8F       djnz    $2e12       ; Next Bouncer

2E83: C9          ret                 ; return

; arrive when bouncer is going straight down
; need to check when falling off bottom of screen

2E84: 3E 03       ld      a,$03       ; A := 3
2E86: DD 86 05    add     a,(ix+$05)  ; add to Sprite's y position (move down 3)
2E89: DD 77 05    ld      (ix+$05),a  ; store result
2E8C: FE F8       cp      $f8         ; are we at the bottom of screen?
2E8E: DA 6C 2E    jp      c,$2e6c     ; No, jump back to program

2E91: DD 36 03 00 ld      (ix+$03),$00; yes, reset the sprite
2E95: DD 36 00 00 ld      (ix+$00),$00; reset
2E99: C3 6C 2E    jp      $2e6c       ; jump back to program

; arrive from #2E41

2E9C: 21 AA 39    ld      hl,$39aa    ; load HL with start of table data
2E9F: 3E 03       ld      a,$03       ; load sound duration of 3
2EA1: 32 83 60    ld      (play_sound_for_bouncer_6083),a   ; play sound for bouncer
2EA4: C3 4B 2E    jp      $2e4b       ; jump back

; jump here from #2E16

2EA7: 3A 96 63    ld      a,(bouncer_release_6396)   ; load A with bouncer release flag
2EAA: 0F          rrca                ; time to deploy a bouncer?
2EAB: D2 78 2E    jp      nc,$2e78    ; no, jump back

; deploy new bouncer

2EAE: AF          xor     a           ; A := 0
2EAF: 32 96 63    ld      (bouncer_release_6396),a   ; reset bouncer release flag
2EB2: DD 36 05 50 ld      (ix+$05),$50; set bouncer's Y position to #50
2EB6: DD 36 0D 01 ld      (ix+$0d),$01; set value to sprite bouncing across, not down
2EBA: CD 57 00    call    $0057       ; load A with random number
2EBD: E6 0F       and     $0f         ; mask bits, result is between 0 and #F
2EBF: C6 F8       add     a,$f8       ; add #F8 = result is now between #F8 and #07
2EC1: DD 77 03    ld      (ix+$03),a  ; store A into initial X position for bouncer sprite
2EC4: DD 36 00 01 ld      (ix+$00),$01; set sprite as active
2EC8: 21 AA 39    ld      hl,$39aa    ; values #39 and #AA to be inserted below.  #39AA is the start of table data for Y offsets to add for each movement
2ECB: DD 75 0E    ld      (ix+$0e),l
2ECE: DD 74 0F    ld      (ix+$0f),h  ; store HL into +E and +F
2ED1: C3 78 2E    jp      $2e78       ; jump back

; arrive from main routine at #1998
; checks for hammer grabs etc ?

2ED4: 3E 0B       ld      a,$0b       ; B = # 1011 binary
2ED6: F7          rst     $30         ; continue here on girders, conveyors, rivets only.  elevators RET from this sub, it has no hammers.
2ED7: D7          rst     $10         ; continue here only if mario is alive, otherwise RET from this sub

2ED8: 11 18 6A    ld      de,hardware_address_of_hammer_sprite_6a18    ; load DE with hardware address of hammer sprite
2EDB: DD 21 80 66 ld      ix,software_address_of_hammer_sprite_6680    ; load IX with software address of hammer sprite
2EDF: DD 7E 01    ld      a,(ix+$01)  ; load A with 1st hammer active indicator
2EE2: 0F          rrca                ; rotate right.  carry set?  (is this hammer active?)
2EE3: DA ED 2E    jp      c,$2eed     ; yes, skip next 2 steps

2EE6: 11 1C 6A    ld      de,hardware_address_of_2nd_hammer_sprite_6a1c    ; else load DE with hardware address of 2nd hammer sprite
2EE9: DD 21 90 66 ld      ix,second_hammer_sprite_6690    ; load IX with 2nd hammer sprite

2EED: DD 36 0E 00 ld      (ix+$0e),$00; store 0 into +#E == ???
2EF1: DD 36 0F F0 ld      (ix+$0f),$f0; store #F0 into +#F (???)
2EF5: 3A 17 62    ld      a,(unknown_6217)   ; load A with hammer indicator
2EF8: 0F          rrca                ; is the hammer already active?
2EF9: D2 97 2F    jp      nc,$2f97    ; no, skip ahead and check for new hammer grab

2EFC: AF          xor     a           ; A := 0
2EFD: 32 18 62    ld      (mario_is_grabbing_the_hammer_until_he_lands_6218),a   ; store into grabbing the hammer indicator. the grab is complete.
2F00: 21 89 60    ld      hl,background_music_value_6089    ; load HL with music address
2F03: 36 04       ld      (hl),$04    ; set music for hammer
2F05: DD 36 09 06 ld      (ix+$09),$06; set width ?
2F09: DD 36 0A 03 ld      (ix+$0a),$03; set height ?
2F0D: 06 1E       ld      b,$1e       ; B := #1E
2F0F: 3A 07 62    ld      a,(mario_movement_indicator_sprite_value_6207)   ; load A with mario movement indicator/sprite value
2F12: CB 27       sla     a           ; shift left.  is bit 7 on?
2F14: D2 1B 2F    jp      nc,$2f1b    ; no, skip next 2 steps

2F17: F6 80       or      $80         ; turn on bit 7 in A
2F19: CB F8       set     7,b         ; turn on bit 7 in B

2F1B: F6 08       or      $08         ; turn on bit 3 in A
2F1D: 4F          ld      c,a         ; copy to C
2F1E: 3A 94 63    ld      a,(hammer_timer_6394)   ; load A with hammer timer
2F21: CB 5F       bit     3,a         ; is bit 3 on in A?
2F23: CA 43 2F    jp      z,$2f43     ; no, skip ahead

; animate the hammer

2F26: CB C0       set     0,b
2F28: CB C1       set     0,c
2F2A: DD 36 09 05 ld      (ix+$09),$05; set width?
2F2E: DD 36 0A 06 ld      (ix+$0a),$06; set height?
2F32: DD 36 0F 00 ld      (ix+$0f),$00
2F36: DD 36 0E F0 ld      (ix+$0e),$f0; set offset for left side of mario (#F0 == -#10)
2F3A: CB 79       bit     7,c         ; is mario facing left?
2F3C: CA 43 2F    jp      z,$2f43     ; yes, skip next step

2F3F: DD 36 0E 10 ld      (ix+$0e),$10; set offset for right side of mario

2F43: 79          ld      a,c         ; A := C
2F44: 32 4D 69    ld      (mario_sprite_value_694d),a   ; store into mario sprite value
2F47: 0E 07       ld      c,$07       ; C := 7
2F49: 21 94 63    ld      hl,hammer_timer_6394    ; load HL with hammer timer
2F4C: 34          inc     (hl)        ; increase.  at zero?
2F4D: C2 B7 2F    jp      nz,$2fb7    ; no skip ahead

; hammer is changing or ending

2F50: 21 95 63    ld      hl,hammer_length_6395    ; load HL with hammer length.
2F53: 34          inc     (hl)        ; increase
2F54: 7E          ld      a,(hl)      ; get the value
2F55: FE 02       cp      $02         ; is the hammer all used up?
2F57: C2 BE 2F    jp      nz,$2fbe    ; no, skip ahead and change its color every 8 frames

; arrive here when hammer runs out

2F5A: AF          xor     a           ; A := 0
2F5B: 32 95 63    ld      (hammer_length_6395),a   ; clear hammer length
2F5E: 32 17 62    ld      (unknown_6217),a   ; store into hammer indicator
2F61: DD 77 01    ld      (ix+$01),a  ; clear hammer active indicator
2F64: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
2F67: ED 44       neg                 ; take negative
2F69: DD 77 0E    ld      (ix+$0e),a  ; store into +E
2F6C: 3A 07 62    ld      a,(mario_movement_indicator_sprite_value_6207)   ; load A with mario movement indicator/sprite value
2F6F: 32 4D 69    ld      (mario_sprite_value_694d),a   ; store into mario sprite value
2F72: DD 36 00 00 ld      (ix+$00),$00; clear hammer active bit
2F76: 3A 89 63    ld      a,(restored_when_hammer_runs_out_6389)   ; load A with previous background music
2F79: 32 89 60    ld      (background_music_value_6089),a   ; set music with what it was before the hammer was grabbed

;

2F7C: EB          ex      de,hl       ; DE <> HL
2F7D: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; load A with mario's X position
2F80: DD 86 0E    add     a,(ix+$0e)  ; add hammer offset
2F83: 77          ld      (hl),a      ; store into Hammer X position
2F84: DD 77 03    ld      (ix+$03),a  ; store into hammer X position
2F87: 23          inc     hl          ; next
2F88: 70          ld      (hl),b      ; store sprite graphic value
2F89: 23          inc     hl          ; next
2F8A: 71          ld      (hl),c      ; store into hammer color
2F8B: 23          inc     hl          ; next
2F8C: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; load A with mario's Y position
2F8F: DD 86 0F    add     a,(ix+$0f)  ; add hammer offset
2F92: 77          ld      (hl),a      ; store into hammer Y position
2F93: DD 77 05    ld      (ix+$05),a  ; store into hammer Y position
2F96: C9          ret                 ; return

; arrive from #2EF9, check for grabbing hammer ?

2F97: 3A 18 62    ld      a,(mario_is_grabbing_the_hammer_until_he_lands_6218)   ; load A with 0, turns to 1 while mario is grabbing the hammer until he lands
2F9A: 0F          rrca                ; is mario grabbing the hammer?
2F9B: D0          ret     nc          ; no, return

; arrive here when hammer is grabbed

2F9C: DD 36 09 06 ld      (ix+$09),$06; set width ?
2FA0: DD 36 0A 03 ld      (ix+$0a),$03; set height ?
2FA4: 3A 07 62    ld      a,(mario_movement_indicator_sprite_value_6207)   ; load A with mario movement indicator/sprite value
2FA7: 07          rlca                ; rotate left the high bit into carry flag
2FA8: 3E 3C       ld      a,$3c       ; A := #3C
2FAA: 1F          rra                 ; rotate right the carry bit back in
2FAB: 47          ld      b,a         ; copy to B
2FAC: 0E 07       ld      c,$07       ; C := 7
2FAE: 3A 89 60    ld      a,(background_music_value_6089)   ; load A with background music value
2FB1: 32 89 63    ld      (restored_when_hammer_runs_out_6389),a   ; save so it can be restored when hammer runs out.  see #2F76
2FB4: C3 7C 2F    jp      $2f7c       ; return to program

; arrive from #2F4D

2FB7: 3A 95 63    ld      a,(hammer_length_6395)   ; load A with hammer length
2FBA: A7          and     a           ; == 0 ?  (full strength)
2FBB: CA 7C 2F    jp      z,$2f7c     ; yes, jump back now

; change hammer color ?
; hammer is half strength

2FBE: 3A 1A 60    ld      a,(framecounter_601a) ; load A with this clock counts down from #FF to 00 over and over...
2FC1: CB 5F       bit     3,a         ; check bit 3 (?).  zero ?  will do this every 8 frames
2FC3: CA 7C 2F    jp      z,$2f7c     ; yes, jump back now

2FC6: 0E 01       ld      c,$01       ; else C := 1 to change hammer color
2FC8: C3 7C 2F    jp      $2f7c       ; jump back

; arrive here from main routine #19BF
; this is the last subroutine from there
; for non-girder levels, this sub
; checks for bonus timer changes
; if the bonus counts down, it also
; sets a possible new fire to be released
; sets a bouncer to be deployed
; updates the bonus timer onscreen
; checks for bonus time running out

2FCB: 3E 0E       ld      a,$0e       ; A := #E = 1110 binary
2FCD: F7          rst     $30         ; is this the girders?  if so, return immediately

2FCE: 21 B4 62    ld      hl,timer_62b4    ; else load HL with timer
2FD1: 35          dec     (hl)        ; count down timer.  at zero?
2FD2: C0          ret     nz          ; no, return

2FD3: 3E 03       ld      a,$03       ; else A := 3
2FD5: 32 B9 62    ld      (fire_release_62b9),a   ; store into fire release - a new fire can be released
2FD8: 32 96 63    ld      (bouncer_release_6396),a   ; store into bouncer release - a new bouncer can be deployed
2FDB: 11 01 05    ld      de,$0501    ; load task #5, parameter #1 = update onscreen bonus timer and play sound & change to red if below 1000
2FDE: CD 9F 30    call    $309f       ; insert task
2FE1: 3A B3 62    ld      a,(intial_timer_value_62b3)   ; load A with intial timer value.
2FE4: 77          ld      (hl),a      ; reset the timer
2fe5: 21 B1 62    ld      hl,bonus_timer_62b1    ; load HL with bonus timer
2fe8: 35          dec     (hl)        ; Decrement.  is the bonus timer zero?
2fe9: c0          ret     nz          ; no, return

2fea: 3E 01       ld      a,$01       ; else time has run out.  A := 1
2fec: 32 86 63    ld      (time_has_run_out_indicator_6386),a   ; set time has run out indicator
2fef: c9          ret                 ; return

; called during a barrel roll
; HL contains the X and Y position of the barrel.  Y has been inflated by 4
; called from #2A3A
; called from #2AA2 with HL preloaded with mario's position offset a bit
; returns with HL modified in some special way
;

2FF0: 7D          ld      a,l         ; load A with Y position (inflated by 4)
2FF1: 0F          rrca                ; Roll right 3 times
2FF2: 0F          rrca
2FF3: 0F          rrca
2FF4: E6 1F       and     $1f         ; mask out left 3 bits to zero (number has been divided by 8)
2FF6: 6F          ld      l,a         ; Load L with this new position
2FF7: 7C          ld      a,h         ; load A with barrel's X position
2FF8: 2F          cpl                 ; A is inverted (1's complement)
2FF9: E6 F8       and     $f8         ; Mask out right 3 bits to zero
2FFB: 5F          ld      e,a         ; load E with result
2FFC: AF          xor     a           ; A := 0
2FFD: 67          ld      h,a         ; H := 0
2FFE: CB 13       rl      e           ; rotate E left
3000: 17          rla                 ; Rotate A left [does nothing?  A is 0]
3001: CB 13       rl      e           ; rotate E left again
3003: 17          rla                 ; rotate A left again ?
3004: C6 74       add     a,$74       ; Add #74 to A.   A = #74 now ?
3006: 57          ld      d,a         ; Store this in D
3007: 19          add     hl,de       ; Add DE into HL
3008: C9          ret                 ; return


;
; called here in the middle of a barrlel being rolled left or right...
; or when mario is moving
; called from four locations
; A is preloaded with ?
;

3009: 57          ld      d,a         ; D := A
300A: 0F          rrca                ; roll right.  is A odd?
300B: DA 22 30    jp      c,$3022     ; yes, skip ahead

; A is even

300E: 0E 93       ld      c,$93       ; C := #93
3010: 0F          rrca
3011: 0F          rrca                ; roll right twice
3012: D2 17 30    jp      nc,$3017    ; no carry, skip next step

3015: 0E 6C       ld      c,$6c       ; C := #6C

3017: 07          rlca                ; roll left
3018: DA 31 30    jp      c,$3031     ; if carry, skip ahead

301B: 79          ld      a,c         ; A := C
301C: E6 F0       and     $f0         ; mask bits, 4 lowest bits set to zero
301E: 4F          ld      c,a         ; store back into C
301F: C3 31 30    jp      $3031       ; skip ahead

; arrive from #300B when A is odd

3022: 0E B4       ld      c,$b4       ; C := #B4
3024: 0F          rrca
3025: 0F          rrca                ; rotate A right twice.  carry set ?
3026: D2 2B 30    jp      nc,$302b    ; no, skip next step

3029: 0E 1E       ld      c,$1e       ; C := #1E

302B: CB 50       bit     2,b         ; is bit 2 on B at zero?
302D: CA 31 30    jp      z,$3031     ; yes, skip next step

3030: 05          dec     b           ; else decrease B

3031: 79          ld      a,c         ; A := C
3032: 0F          rrca
3033: 0F          rrca                ; rotate right twice
3034: 4F          ld      c,a         ; C := A
3035: E6 03       and     $03         ; mask bits, now between 0 and 3
3037: B8          cp      b           ; == B ?
3038: C2 31 30    jp      nz,$3031    ; no, loop again

303B: 79          ld      a,c         ; A := C
303C: 0F          rrca
303D: 0F          rrca                ; rotate right twice
303E: E6 03       and     $03         ; mask bits, now between 0 and 3
3040: FE 03       cp      $03         ; == 3 ?
3042: C0          ret     nz          ; no, return

3043: CB 92       res     2,d         ; clear bit 2 of D (copy of original input A)
3045: 15          dec     d           ; decrease.  zero?
3046: C0          ret     nz          ; no, return

3047: 3E 04       ld      a,$04       ; else A := 4
3049: C9          ret                 ; return

; called from #0AF0 and #0B38
; rolls up kong's ladder during intro

304A: 11 E0 FF    ld      de,$ffe0    ; load DE with offset
304D: 3A 8E 63    ld      a,(kong_ladder_climb_counter_638e)   ; load A with kong ladder climb counter
3050: 4F          ld      c,a         ; copy to C
3051: 06 00       ld      b,$00       ; B := 0
3053: 21 00 76    ld      hl,$7600    ; load HL with screen RAM address
3056: CD 64 30    call    $3064       ; roll up left ladder
3059: 21 C0 75    ld      hl,$75c0    ; load HL with screen RAM address
305C: CD 64 30    call    $3064       ; roll up right ladder
305F: 21 8E 63    ld      hl,kong_ladder_climb_counter_638e    ; load HL with kong ladder climb counter
3062: 35          dec     (hl)        ; decrease
3063: C9          ret                 ; return

; called from #3056 and #305C above

3064: 09          add     hl,bc       ; add offset based on how far up kong is
3065: 7E          ld      a,(hl)      ; get value from screen
3066: 19          add     hl,de       ; add offset
3067: 77          ld      (hl),a      ; store value to screen
3068: C9          ret                 ; return

; arrive from #0A79 when intro screen indicator == 3 or 5

3069: DF          rst     $18         ; count down timer and only continue here if zero, else RET
306A: 2A C0 63    ld      hl,(timer_unknown_63c0)  ; load HL with timer ???
306D: 34          inc     (hl)        ; increase
306E: C9          ret                 ; return

; called from 3 locations

306F: 21 AF 62    ld      hl,kong_misc_counter_62af    ; load HL with kong climbing counter
3072: 34          inc     (hl)        ; increase
3073: 7E          ld      a,(hl)      ; load A with the counter
3074: E6 07       and     $07         ; mask bits.  now between 0 and 7.  zero?
3076: C0          ret     nz          ; no, return

; animate kong climbing up the ladder

3077: 21 0B 69    ld      hl,kong_sprite_array_690b    ; load HL with kong sprite array
307A: 0E FC       ld      c,$fc       ; C := -4
307C: FF          rst     $38         ; move kong
307D: 0E 81       ld      c,$81       ; C := #81
307F: 21 09 69    ld      hl,kongs_right_leg_address_sprite_6909    ; load HL with kong's right leg address sprite
3082: CD 96 30    call    $3096       ; animate kong sprite
3085: 21 1D 69    ld      hl,kongs_right_arm_address_sprite_691d    ; load HL with kong's right arm address sprite
3088: CD 96 30    call    $3096       ; animate kong sprite
308B: CD 57 00    call    $0057       ; load A with random number
308E: E6 80       and     $80         ; mask bits, now either 0 or #80
3090: 21 2D 69    ld      hl,sprite_of_girl_under_kongs_arms_692d    ; load HL with sprite of girl under kong's arms
3093: AE          xor     (hl)        ; toggle the sprite
3094: 77          ld      (hl),a      ; store result - toggles the girl to make her wiggle randomly
3095: C9          ret                 ; return

; called from #3082 and #3088 above

3096: 06 02       ld      b,$02       ; For B = 1 to 2

3098: 79          ld      a,c         ; A := C
3099: AE          xor     (hl)        ; toggle with the bits in this memory location
309A: 77          ld      (hl),a      ; store A into this location
309B: 19          add     hl,de       ; add offset for next location
309C: 10 FA       djnz    $3098       ; Next B

309E: C9          ret                 ; return

; insert task
; DE are loaded with task # and parameter
; tasks are decoded at #02E3
; tasks are pushed into #60C0 through #60FF

309F: E5          push    hl          ; save HL
30A0: 21 C0 60    ld      hl,start_of_task_list_60c0    ; load HL with start of task list [why?  L is set later, only H needs to be loaded here]
30A3: 3A B0 60    ld      a,(task_list_pointer_60b0)   ; load A with task pointer
30A6: 6F          ld      l,a         ; HL now has task pointer full address
30A7: CB 7E       bit     7,(hl)      ; test high bit 7 of the task at this address.  zero?
30A9: CA BB 30    jp      z,$30bb     ; yes, skip ahead, restore HL and return. [when would this happen??? if task list is full???]

30AC: 72          ld      (hl),d      ; else store task number into task list
30AD: 2C          inc     l           ; next HL
30AE: 73          ld      (hl),e      ; store task parameter
30AF: 2C          inc     l           ; next HL
30B0: 7D          ld      a,l         ; load A with low byte of task pointer
30B1: FE C0       cp      $c0         ; is A > #C0 ? (did the task list roll over?)
30B3: D2 B8 30    jp      nc,$30b8    ; no, skip next instruction

30B6: 3E C0       ld      a,$c0       ; yes, reset A to #C0 for start of task list

30B8: 32 B0 60    ld      (task_list_pointer_60b0),a   ; store A into task list pointer

30BB: E1          pop     hl          ; restore HL
30BC: C9          ret                 ; return to program

; arrive here from #1615 when rivets cleared
; clears all sprites for firefoxes, hammers and bonus items

30BD: 21 50 69    ld      hl,start_of_hammers_6950    ; load HL with start of hammers
30C0: 06 02       ld      b,$02       ; B := 2
30C2: CD E4 30    call    $30e4       ; clear hammers ?
30C5: 2E 80       ld      l,$80       ; L := #80
30C7: 06 0A       ld      b,$0a       ; B := #A
30C9: CD E4 30    call    $30e4       ; clear barrels ?
30CC: 2E B8       ld      l,$b8       ; L := #B8
30CE: 06 0B       ld      b,$0b       ; B := #B
30D0: CD E4 30    call    $30e4       ; clear firefoxes ?
30D3: 21 0C 6A    ld      hl,start_of_bonus_items_6a0c    ; load HL with start of bonus items
30D6: 06 05       ld      b,$05       ; B := 5
30D8: C3 E4 30    jp      $30e4       ; clear bonus items

; called from #12DF
; clears mario and elevators from the screen

30DB: 21 4C 69    ld      hl,mario_sprite_x_position_694c    ; load address for mario sprite X position
30DE: 36 00       ld      (hl),$00    ; clear this memory = move mario off screen
30E0: 2E 58       ld      l,$58       ; HL := #6958 = elevator sprite start
30E2: 06 06       ld      b,$06       ; for B = 1 to 6

30E4: 7D          ld      a,l         ; load A with low byte addr

30E5: 36 00       ld      (hl),$00    ; clear this sprite position to zero = move off screen
30E7: C6 04       add     a,$04       ; add 4 for next sprite
30E9: 6F          ld      l,a         ; store into HL
30EA: 10 F9       djnz    $30e5       ; next B

30EC: C9          ret                 ; return

; called from main routine at #198C

30ED: CD FA 30    call    $30fa       ; Check internal difficulty and timers and return here based on difficulty a percentage of the time
30F0: CD 3C 31    call    $313c       ; Deploy fire if fire deployment flag is set
30F3: CD B1 31    call    $31b1       ; Process all movement for all fireballs
30F6: CD F3 34    call    $34f3       ; update all fires and firefoxes
30F9: C9          ret                 ; return

; This routine is used to adjust the fireball speed based on the internal difficulty. It works by forcing the entire fireball movement routine to
; be skipped on certain frames, returning directly back to the main routine in such cases. The higher the internal difficlty, the less often it
; short-circuits back to the main routine, the faster they will move.
; called from #30ED ABOVE

30FA: 3A 80 63    ld      a,(difficulty_level_6380)   ; \  Jump if internal difficulty is less than 6 (Is it possible to not jump here?)
30FD: FE 06       cp      $06         ;  |
30FF: 38 02       jr      c,$3103     ; /

3101: 3E 05       ld      a,$05       ; load A with 5 = max internal difficulty
3103: EF          rst     $28         ; jump to address based on internal difficulty

3104  10 31                     0       ; #3110
3106  10 31                     1       ; #3110
3108  1B 31                     2       ; #311B
310A  26 31                     3       ; #3126
310C  26 31                     4       ; #3126
310E  31 31                     5       ; #3131

; internal difficulty == 0 or 1. In this case, the fireball movement routine is only executed every other frame, so that fireballs move slowly.

3110  3A 1A 60  LD      A,(FrameCounter)       ; load A with this clock counts down from #FF to 00 over and over...
3112: 60          ld      h,b         ; load H with B == ??? from previous subroutine ???? [what is this doing here ?]
3113: E6 01       and     $01         ; \  If lowest bit of timer is 0 Return and continue as normal
3115: FE 01       cp      $01         ;  |
3117: C8          ret     z           ; /

3118: 33          inc     sp          ; \  Else return to #198F instead of #30F0, skipping fireball movement routine
3119: 33          inc     sp          ;  |
311A: C9          ret                 ; /

; internal difficulty == 2. Here the fireball movement routine is executed for 5 consecutive frames out of every 8 frames.

311B: 3A 1A 60    ld      a,(framecounter_601a) ; \  If the lowest 3 bits of timer are less than 5 (equal to 0, 1, 2, 3, or 4) then return and continue as
311E: E6 07       and     $07         ;  | normal
3120: FE 05       cp      $05         ;  |
3122: F8          ret     m           ; /

3123: 33          inc     sp          ; \  Else return to #198F instead of #30F0, skipping fireball movement routine
3124: 33          inc     sp          ;  |
3125: C9          ret                 ; /

; difficulty == 3 or 4. Here the fireball movement routine is executed for 3 out of every 4 frames.

3126: 3A 1A 60    ld      a,(framecounter_601a) ; \  If the lowest 2 bits of the timer are not 11 then return and continue as normal
3129: E6 03       and     $03         ;  |
312B: FE 03       cp      $03         ;  |
312D: F8          ret     m           ; /

312E: 33          inc     sp          ; \  Else return to #198F instead of #30F0, skipping fireball movement routine
312F: 33          inc     sp          ;  |
3130: C9          ret                 ; /

; difficulty == 5. Here the fireball movement routine is executed for 7 out of every 8 frames.

3131: 3A 1A 60    ld      a,(framecounter_601a) ; \  If the lowest 3 bits of the timer are not 111 then return and continue as normal
3134: E6 07       and     $07         ;  |
3136: FE 07       cp      $07         ;  |
3138: F8          ret     m           ; /

3139: 33          inc     sp          ; \  Else return to #198F instead of #30F0, skipping fireball movement routine
313A: 33          inc     sp          ;  |
313B: C9          ret                 ; /

; This routine checks the fire deployment flag and deploys the actual fireball if it is set (as long as there is a free slot). It also keeps an
; updated count of the number of fireballs on screen and sets the color of fireballs based on the hammer status.
; called from #30F0

313C: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; load IX with start of fire address
3140: AF          xor     a           ; \ Reset # of fires onscreen to 0, this routine will count them.
3141: 32 A1 63    ld      (unknown_63a1),a   ; /
3144: 06 05       ld      b,$05       ; For B = 1 to 5 firefoxes
3146: 11 20 00    ld      de,$0020    ; load DE with offset to add for next firefox

3149: DD 7E 00    ld      a,(ix+$00)  ; \  Jump if sprite slot is unused to maybe deploy a fire there.
314C: FE 00       cp      $00         ;  |
314E: CA 7C 31    jp      z,$317c     ; /

3151: 3A A1 63    ld      a,(unknown_63a1)   ; \  This fire slot is active. Increment count for # of fires onscreen
3154: 3C          inc     a           ;  |
3155: 32 A1 63    ld      (unknown_63a1),a   ; /
3158: 3E 01       ld      a,$01       ; \  Set fire color to #01 (normal) if hammer is not active, and #00 (blue) if hammer is active
315A: DD 77 08    ld      (ix+$08),a  ;  |
315D: 3A 17 62    ld      a,(unknown_6217)   ;  |
3160: FE 01       cp      $01         ;  |
3162: C2 6A 31    jp      nz,$316a    ;  |
3165: 3E 00       ld      a,$00       ;  |
3167: DD 77 08    ld      (ix+$08),a  ; /

316A: DD 19       add     ix,de       ; next sprite
316C: 10 DB       djnz    $3149       ; next B

316E: 21 A0 63    ld      hl,unknown_63a0    ; \ Clear fire deployment flag
3171: 36 00       ld      (hl),$00    ; /
3173: 3A A1 63    ld      a,(unknown_63a1)   ; \  Return all the way back to the main routine if no fires are active, otherwise just return.
3176: FE 00       cp      $00         ;  |
3178: C0          ret     nz          ;  |
3179: 33          inc     sp          ;  |
317A: 33          inc     sp          ;  |
317B: C9          ret                 ; /

; arrive here from #314E
317C: 3A A1 63    ld      a,(unknown_63a1)   ; \  Jump back and don't deploy fire if there are already 5 fires active (Can this ever happen here?)
317F: FE 05       cp      $05         ;  |
3181: CA 6A 31    jp      z,$316a     ; /
3184: 3A 27 62    ld      a,(screen_number_6227)   ; \  Jump ahead if screen is not conveyors (i.e., the screen is rivets)
3187: FE 02       cp      $02         ;  |
3189: C2 95 31    jp      nz,$3195    ; /
318C: 3A A1 63    ld      a,(unknown_63a1)   ; \  Return if current count of # of fires == internal difficulty, on conveyors we never have more fireballs
318F: 4F          ld      c,a         ;  | on screen than the internal difficulty
3190: 3A 80 63    ld      a,(difficulty_level_6380)   ;  |
3193: B9          cp      c           ;  |
3194: C8          ret     z           ; /
3195: 3A A0 63    ld      a,(unknown_63a0)   ; \  Jump back and don't deploy fire if fire deployment flag is not set
3198: FE 01       cp      $01         ;  |
319A: C2 6A 31    jp      nz,$316a    ; /

319D: DD 77 00    ld      (ix+$00),a  ; Deploy a fire. Set status indicator to 1 = active
31A0: DD 77 18    ld      (ix+$18),a  ; Set spawning indicator to 1
31A3: AF          xor     a           ; \ Clear fire deployment flag
31A4: 32 A0 63    ld      (unknown_63a0),a   ; /
31A7: 3A A1 63    ld      a,(unknown_63a1)   ; \  Increment count of # of active fires
31AA: 3C          inc     a           ;  |
31AB: 32 A1 63    ld      (unknown_63a1),a   ; /
31AE: C3 6A 31    jp      $316a       ; jump back and loop for next

; This subroutine handles all movement for all fireballs.
; called from #30F3

31B1: CD DD 31    call    $31dd       ; Check if freezers should enter freezer mode
31B4: AF          xor     a           ; \ Index of fireball being processed := 0
31B5: 32 A2 63    ld      (unknown_63a2),a   ; /
31B8: 21 E0 63    ld      hl,current_fireball_data_address_63e0    ; \ Address of fireball data array for current fireball being processed := #63E0 = #6400 - #20
31BB: 22 C8 63    ld      (address_of_fireball_slot_for_this_fireball_63c8),hl  ; / This gets incremented by #20 at the start of the following loop

; Loop start
31BE: 2A C8 63    ld      hl,(address_of_fireball_slot_for_this_fireball_63c8)  ; \  Move on to next fireball by incrementing address of fireball data array for current fireball by #20
31C1: 01 20 00    ld      bc,$0020    ;  |
31C4: 09          add     hl,bc       ;  |
31C5: 22 C8 63    ld      (address_of_fireball_slot_for_this_fireball_63c8),hl  ; /
31C8: 7E          ld      a,(hl)      ; \  Jump if fireball is not active
31C9: A7          and     a           ;  |
31CA: CA D0 31    jp      z,$31d0     ; /

31CD: CD 02 32    call    $3202       ; Handle all movement for this fire

31D0: 3A A2 63    ld      a,(unknown_63a2)   ; \  Increment index of current fireball being processed
31D3: 3C          inc     a           ;  |
31D4: 32 A2 63    ld      (unknown_63a2),a   ; /
31D7: FE 05       cp      $05         ; \ Loop if index is less than 5
31D9: C2 BE 31    jp      nz,$31be    ; /

31DC: C9          ret                 ; return

; This subroutine checks if fires 2 and 4 should enter freezer mode. They always both enter at the same time and they enter with a 25% probability
; every 256 frames (note that this is 256 actual frames, not 256 fireball code execution frames).
; called from #31B1 above

31DD: 3A 80 63    ld      a,(difficulty_level_6380)   ; \  Return if internal difficulty is < 3, no freezers are allowed until difficulty 3.
31E0: FE 03       cp      $03         ;  |
31E2: F8          ret     m           ; /

31E3: CD F6 31    call    $31f6       ; Check if we should enter freezer mode (25% probability every 256 frames of entering freezer mode)
31E6: FE 01       cp      $01         ; \ Return if should not enter freezer mode
31E8: C0          ret     nz          ; /

31E9: 21 39 64    ld      hl,freezer_indicator_of_2nd_fire_6439    ; \  Set freezer indicator of 2nd fire to #02 to enable freezer mode
31EC: 3E 02       ld      a,$02       ;  |
31EE: 77          ld      (hl),a      ; /

31EF: 21 79 64    ld      hl,freezer_indicator_of_4th_fire_6479    ; \  Set freezer indicator of 4th fire to #02 to enable freezer mode
31F2: 3E 02       ld      a,$02       ;  |
31F4: 77          ld      (hl),a      ; /
31F5: C9          ret                 ; return

; Every 256 frames this subroutine has a 25% chance of loading 1 into A. Otherwise a value not equal to 1 is loaded.
; called from #31E3

31F6: 3A 18 60    ld      a,(rngtimer1_6018) ; \  Return with 1 not loaded in A if lowest 2 bits of RNG are not 01. (75% probability of returning)
31F9: E6 03       and     $03         ;  |
31FB: FE 01       cp      $01         ;  |
31FD: C0          ret     nz          ; /

31FE: 3A 1A 60    ld      a,(framecounter_601a) ; \ Else return A with timer that constantly counts down from FF to 00  ... 1 count per frame
3201: C9          ret                 ; /

; This subroutine handles all movement for a single fireball.
; called from #31CD above

3202: DD 2A C8 63 ld      ix,(address_of_fireball_slot_for_this_fireball_63c8)  ; Load IX with address of fireball data array for current fireball
3206: DD 7E 18    ld      a,(ix+$18)  ; \  Jump if fireball is currently in the process of spawning
3209: FE 01       cp      $01         ;  |
320B: CA 7A 32    jp      z,$327a     ; /

320E: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball is currently on a ladder
3211: FE 04       cp      $04         ;  |
3213: F2 30 32    jp      p,$3230     ; /

3216: DD 7E 19    ld      a,(ix+$19)  ; \  Jump if freezer mode is enguaged for this fireball
3219: FE 02       cp      $02         ;  |
321B: CA 7E 32    jp      z,$327e     ; /

321E: CD 0F 33    call    $330f       ; Check if fireball should randomly reverse direction
3221: 3A 18 60    ld      a,(rngtimer1_6018) ; \  Jump and do not climb any ladder with 75% probability, so a ladder is climbed with 25% probability.
3224: E6 03       and     $03         ;  | Note that left moving fireballs always skip the ladder climbing check and instead jump to the end of
3226: C2 33 32    jp      nz,$3233    ; /  this subroutine without updating position.

3229: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump to end of subroutine if fireball is moving left. This is reached with 25% probability so left-moving
322C: A7          and     a           ;  | fireballs skip all movement with 25% probability, so their speed is randomized but averages 25% slower
322D: CA 57 32    jp      z,$3257     ; /  than the speed of right-moving fireballs.

; Fireball is on a ladder or about to mount ladder (as long as doing so is permitted).
3230: CD 3D 33    call    $333d       ; Handle fireball mounting/dismounting of ladders

3233: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball is currently on a ladder
3236: FE 04       cp      $04         ;  |
3238: F2 91 32    jp      p,$3291     ; /

; Fireball is moving left or right
323B: CD AD 33    call    $33ad       ; Handle fire movement left or right, animate fireball, and adjust Y-position for slanted girders
323E: CD 8C 29    call    $298c       ; Load A with 1 if girder edge nearby, 0 otherwise
3241: FE 01       cp      $01         ; \ Jump if we have reached the edge of a girder
3243: CA 97 32    jp      z,$3297     ; /

3246: DD 2A C8 63 ld      ix,(address_of_fireball_slot_for_this_fireball_63c8)  ; Load IX with address of fireball slot for this fireball
324A: DD 7E 0E    ld      a,(ix+$0e)  ; \  Jump if X-position is < #10 (i.e., fireball has reached left edge of screen)
324D: FE 10       cp      $10         ;  |
324F: DA 8C 32    jp      c,$328c     ; /

3252: FE F0       cp      $f0         ; \ Jump if X-position is >= #F0 (i.e., fireball has reached right edge of screen)
3254: D2 84 32    jp      nc,$3284    ; /

3257: DD 7E 13    ld      a,(ix+$13)  ; \  Jump if our index into the Y-position adjustment table hasn't reached 0 yet
325A: FE 00       cp      $00         ;  |
325C: C2 B9 32    jp      nz,$32b9    ; /

325F: 3E 11       ld      a,$11       ; Reset index into Y-position adjustment table

3261: DD 77 13    ld      (ix+$13),a  ; Store updated index into Y-position adjustment table
3264: 16 00       ld      d,$00       ; \  Index the Y-position adjustment table using +#13 to get in A the amount to adjust the Y-position by to
3266: 5F          ld      e,a         ;  | make the fireball bob up and down
3267: 21 7A 3A    ld      hl,$3a7a    ;  |
326A: 19          add     hl,de       ;  |
326B: 7E          ld      a,(hl)      ; /

        ; 3A7A:  FF 00 FF FF FE FE FE FE FE FE FE FE FE FE FE FF FF 00

326C: DD 46 0E    ld      b,(ix+$0e)  ; \ Copy effective X-position into actual X-position (these two are always the same)
326F: DD 70 03    ld      (ix+$03),b  ; /
3272: DD 4E 0F    ld      c,(ix+$0f)  ; \  Compute the actual Y-position by adding the adjustment to the effective Y-position
3275: 81          add     a,c         ;  |
3276: DD 77 05    ld      (ix+$05),a  ; /
3279: C9          ret                 ; return

; Arrive from #320B when fireball is spawning
327A: CD BD 32    call    $32bd       ; Handle fireball movement while spawning
327D: C9          ret                 ; return

; Arrive from #321B when freezer mode is enguaged
327E: CD D6 32    call    $32d6       ; Handle freezing fireball
3281: C3 29 32    jp      $3229       ; Jump back to program

; Arrive from #3254 when fireball has reached right edge of screen
3284: 3E 02       ld      a,$02       ; Set direction to "special" left

3286: DD 77 0D    ld      (ix+$0d),a  ; Store new direction, either 1 for right or 2 for left
3289: C3 57 32    jp      $3257       ; Jump back

; Arrive from #324F when fireball has reached left edge of screen
328C: 3E 01       ld      a,$01       ; Set direction to right
328E: C3 86 32    jp      $3286       ; Jump back

; Fireball is moving up or down a ladder
3291: CD E7 33    call    $33e7       ; Handle fireball movement up/down the ladder and animate the fireball
3294: C3 57 32    jp      $3257       ; Jump back

; Arrived from #3243 when fire is at edge of girder
3297: DD 2A C8 63 ld      ix,(address_of_fireball_slot_for_this_fireball_63c8)  ; Load IX with address of fireball slot for this fireball
329B: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball direction is left
329E: FE 01       cp      $01         ;  |
32A0: C2 B1 32    jp      nz,$32b1    ; /

32A3: 3E 02       ld      a,$02       ; Set direction to "special" left
32A5: DD 35 0E    dec     (ix+$0e)    ; Decrement fireball X-position, make fireball move left

32A8: DD 77 0D    ld      (ix+$0d),a  ; Store new direction, either 1 for right, or 2 for left
32AB: CD C3 33    call    $33c3       ; Since we just moved a pixel, adjust Y-position for slanted girders on barrel screen
32AE: C3 57 32    jp      $3257       ; Jump back

32B1: 3E 01       ld      a,$01       ; Set direction to right
32B3: DD 34 0E    inc     (ix+$0e)    ; Incremement fireball X-position, make fireball move right
32B6: C3 A8 32    jp      $32a8       ; Jump back

; Arrived from #325C
32B9: 3D          dec     a           ; Decrement index into Y-position adjustment table
32BA: C3 61 32    jp      $3261       ; Jump back

; This subroutine is responsible for handling fireball movement while the fireball is spawning. Here the fireball may be following a fixed trajectory
; such as when jumping out of an oil can for example.
; called from #327A

32BD: 3A 27 62    ld      a,(screen_number_6227)   ; \  Jump if we are currently on barrels
32C0: FE 01       cp      $01         ;  |
32C2: CA CE 32    jp      z,$32ce     ; /

32C5: FE 02       cp      $02         ; \ Jump if we are on conveyors
32C7: CA D2 32    jp      z,$32d2     ; /

32CA: CD B9 34    call    $34b9       ; Spawn fireball in proper location on rivets
32CD: C9          ret                 ; return

32CE: CD 2C 34    call    $342c       ; Handle fireball movement while coming out of oilcan on barrels
32D1: C9          ret                 ; return

32D2: CD 78 34    call    $3478       ; Handle fireball movement while coming out of oilcan on conveyors
32D5: C9          ret                 ; return

; This subroutine handles a freezer when freezer mode is activated, including checking when to freeze and when to leave freezer mode.
; Called from #327E

32D6: DD 7E 1C    ld      a,(ix+$1c)  ; \  Jump if fireball freeze timer is non-zero, meaning we are frozen and waiting for the timer to reach 0
32D9: FE 00       cp      $00         ;  | to unfreeze.
32DB: C2 FD 32    jp      nz,$32fd    ; /

32DE: DD 7E 1D    ld      a,(ix+$1d)  ; \  We reach this when a fireball is not frozen, but freezer mode is activated. Jump if the freeze flag is
32E1: FE 01       cp      $01         ;  | not set (This flag is only set when the fireball reaches the top of a ladder).
32E3: C2 0B 33    jp      nz,$330b    ; /

; It is time to maybe freeze the fireball at the top of a ladder.
32E6: DD 36 1D 00 ld      (ix+$1d),$00; Reset the freeze flag to zero
32EA: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; \  Jump if Mario is above fireball, in this case we leave freezer mode immediately without freezing.
32ED: DD 46 0F    ld      b,(ix+$0f)  ;  |
32F0: 90          sub     b           ;  |
32F1: DA 03 33    jp      c,$3303     ; /

32F4: DD 36 1C FF ld      (ix+$1c),$ff; Freeze the fireball for 256 fireball execution frames

32F8: DD 36 0D 00 ld      (ix+$0d),$00; Set direction to "frozen"
32FC: C9          ret                 ; return

; Jump here from #32DB when fireball still frozen
32FD: DD 35 1C    dec     (ix+$1c)    ; Decrement freeze timer
3300: C2 F8 32    jp      nz,$32f8    ; Jump if it is still not time to unfreeze

; It is time to unfreeze
3303: DD 36 19 00 ld      (ix+$19),$00; Clear the freezer mode flag
3307: DD 36 1C 00 ld      (ix+$1c),$00; Clear the freeze timer

330B: CD 0F 33    call    $330f       ; Check if fireball should randomly freeze out in the open (note this is the same as the direction reversal
                                        ; routine for non-freezing fireballs, only now setting direction to 00 indicates "frozen" instead of "left")
330E: C9          ret                 ; return

; This subroutine randomly reversed direction of fire every 43 fireball execution frames. Note that this is not actual frames, the actual number of
; frames will vary based on internal difficulty.
; called from #321E and from #330B

330F: DD 7E 16    ld      a,(ix+$16)  ; \  Jump without reversing if direction reverse timer hasn't reached 0 yet
3312: FE 00       cp      $00         ;  |
3314: C2 32 33    jp      nz,$3332    ; /

3317: DD 36 16 2B ld      (ix+$16),$2b; Reset direction reverse counter to #2B
331B: DD 36 0D 00 ld      (ix+$0d),$00; \  Set fireball direction to be left (or frozen for freezers) and jump with 50% probability
331F: 3A 18 60    ld      a,(rngtimer1_6018) ;  |
3322: 0F          rrca                ;  |
3323: D2 32 33    jp      nc,$3332    ; /

3326: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if direction fireball direction is 1, which is impossible, so this is a NOP.
3329: FE 01       cp      $01         ;  |
332B: CA 36 33    jp      z,$3336     ; /

332E: DD 36 0D 01 ld      (ix+$0d),$01; Else set fireball direction to be right
3332: DD 35 16    dec     (ix+$16)    ; Decrement direction reverse timer
3335: C9          ret                 ; return

; jump here from #332B [never arrive here , buggy software]
3336: DD 36 0D 02 ld      (ix+$0d),$02; Set fireball direction to be "special" left
333A: C3 32 33    jp      $3332       ; jump back

; This subroutine serves two purposes. If a fireball is currently on a ladder it checks to see if the fireball has reached the other end of the ladder
; and if so dismounts the ladder. Otherwise, if the fireball is not on a ladder it checks to see if there are any ladders nearby that can be taken,
; and if so it mounts the ladder.
; called from #3230

333D: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball is climbing up a ladder
3340: FE 08       cp      $08         ;  |
3342: CA 71 33    jp      z,$3371     ; /

3345: FE 04       cp      $04         ; \ Jump if fireball is climbing down a ladder
3347: CA 8A 33    jp      z,$338a     ; /

; Else firefox is not on a ladder, but will mount one if permitted to do so
334A: CD A1 33    call    $33a1       ; Return without taking ladder if fireball is on the top girder and the screen is not rivets
334D: DD 7E 0F    ld      a,(ix+$0f)  ; \  D := Y-position of bottom of fireball
3350: C6 08       add     a,$08       ;  |
3352: 57          ld      d,a         ; /
3353: DD 7E 0E    ld      a,(ix+$0e)  ; A := fireball's X-position
3356: 01 15 00    ld      bc,$0015    ; BC := #0015, the number of ladders to check
3359: CD 6E 23    call    $236e       ; Check for ladders nearby, return if none, else A := 0 if at bottom of ladder, A := 1 if at top
335C: A7          and     a           ; \ Jump if there is a ladder nearby to go up
335D: CA 99 33    jp      z,$3399     ; /

; Else there is a ladder nearby to go down
3360: DD 70 1F    ld      (ix+$1f),b  ; Store B into +#1F = Y-position of bottom of ladder
3363: 3A 05 62    ld      a,(return_without_taking_the_ladder_6205)   ; \  Return without taking the ladder if Mario is at or above the Y-position of the fireball
3366: 47          ld      b,a         ;  |
3367: DD 7E 0F    ld      a,(ix+$0f)  ;  |
336A: 90          sub     b           ;  |
336B: D0          ret     nc          ; /

336C: DD 36 0D 04 ld      (ix+$0d),$04; Else set direction to descending ladder
3370: C9          ret                 ; return

; Arrived because fireball is moving up a ladder
3371: DD 7E 0F    ld      a,(ix+$0f)  ; \  Return if fireball is not at the top of the ladder
3374: C6 08       add     a,$08       ;  |
3376: DD 46 1F    ld      b,(ix+$1f)  ;  |
3379: B8          cp      b           ;  |
337A: C0          ret     nz          ; /

; Fireball at top of ladder
337B: DD 36 0D 00 ld      (ix+$0d),$00; Set fireball direction to left
337F: DD 7E 19    ld      a,(ix+$19)  ; \  If freezer mode is enguaged then set the freeze flag and return, otherwise just return.
3382: FE 02       cp      $02         ;  |
3384: C0          ret     nz          ;  |
3385: DD 36 1D 01 ld      (ix+$1d),$01;  |
3389: C9          ret                 ; /

; Arrive because fireball is moving down a ladder
338A: DD 7E 0F    ld      a,(ix+$0f)  ; \  Return if fireball is not at the bottom of the ladder
338D: C6 08       add     a,$08       ;  |
338F: DD 46 1F    ld      b,(ix+$1f)  ;  |
3392: B8          cp      b           ;  |
3393: C0          ret     nz          ; /

3394: DD 36 0D 00 ld      (ix+$0d),$00; Fireball has reached the bottom, set the direction to left
3398: C9          ret                 ; return

; Arrive because there is a ladder nearby to go up
3399: DD 70 1F    ld      (ix+$1f),b  ; Store B into +#1F = Y-position of top of ladder
339C: DD 36 0D 08 ld      (ix+$0d),$08; Else set direction to ascending ladder
33A0: C9          ret                 ; return

; This subroutine returns to the higher subroutine (causing a ladder to NOT be taken) if a fireball is on the top girder and we are not on rivets.
; called from #334A

33A1: 3E 07       ld      a,$07       ; \ Return if immediately we are on rivets, fireballs do not get stuck on the top in this case
33A3: F7          rst     $30         ; /

33A4: DD 7E 0F    ld      a,(ix+$0f)  ; \ Return if Y-position is >= 59 (i.e., fireball is not on the top girder)
33A7: FE 59       cp      $59         ;  |
33A9: D0          ret     nc          ; /

33AA: 33          inc     sp          ; \  Else return to higher subroutine. This prevents fireballs from coming down on conveyors & girders once
33AB: 33          inc     sp          ;  | they reach the top level.
33AC: C9          ret                 ; /

; This subroutine handles movemnt of a fireball to the left and right. It also animates the fireball and adjusts its Y-position if travelling up/down
; a slanted girder on the barrel screen.
; called from #323B

33AD: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball direction is right
33B0: FE 01       cp      $01         ;  |
33B2: CA D9 33    jp      z,$33d9     ; /

; Fireball is moving left
33B5: DD 7E 07    ld      a,(ix+$07)  ; \  Set direction bit in fireball graphics to face left
33B8: E6 7F       and     $7f         ;  |
33BA: DD 77 07    ld      (ix+$07),a  ; /
33BD: DD 35 0E    dec     (ix+$0e)    ; Decrement X-position

33C0: CD 09 34    call    $3409       ; Animate the fireball
; Fall into below subroutine

; This subroutine adjusts a fireball's Y-position based on movement up/down a slanted girder on the barrel screen.
; called from #32AB

33C3: 3A 27 62    ld      a,(screen_number_6227)   ; \  Return if we are not on barrels
33C6: FE 01       cp      $01         ;  |
33C8: C0          ret     nz          ; /

33C9: DD 66 0E    ld      h,(ix+$0e)  ; Load H with fireball X-position
33CC: DD 6E 0F    ld      l,(ix+$0f)  ; Load L with fireball Y-position
33CF: DD 46 0D    ld      b,(ix+$0d)  ; Load B with fireball direction
33D2: CD 33 23    call    $2333       ; Check for fireball moving up/down a slanted girder ?
33D5: DD 75 0F    ld      (ix+$0f),l  ; Store adjusted Y-position
33D8: C9          ret                 ; return

; Fireball is moving right
33D9: DD 7E 07    ld      a,(ix+$07)  ; \  Set direction bit in fireball graphics to face right
33DC: F6 80       or      $80         ;  |
33DE: DD 77 07    ld      (ix+$07),a  ; /
33E1: DD 34 0E    inc     (ix+$0e)    ; Increment X-position
33E4: C3 C0 33    jp      $33c0       ; Jump back to program

; This subroutine handles fireball movement up and down ladders. Fireball movement up a ladder is 1/3 the speed of movement down a ladder, and
; movement down a ladder is the same speed as movement to the right. The subroutine also animates the fireball as it climbs.
; called from #3291

33E7: CD 09 34    call    $3409       ; Animate the fireball
33EA: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball is moving down the ladder
33ED: FE 08       cp      $08         ;  |
33EF: C2 05 34    jp      nz,$3405    ; /

33F2: DD 7E 14    ld      a,(ix+$14)  ; \  Jump if it is not time to climb one pixel yet
33F5: A7          and     a           ;  |
33F6: C2 01 34    jp      nz,$3401    ; /

33F9: DD 36 14 02 ld      (ix+$14),$02; Reset ladder climb timer to 2
33FD: DD 35 0F    dec     (ix+$0f)    ; Decrement fireball's Y position, move up one pixel
3400: C9          ret                 ; return

3401: DD 35 14    dec     (ix+$14)    ; Decrease ladder climb timer
3404: C9          ret                 ; return

3405: DD 34 0F    inc     (ix+$0f)    ; Increment fireball's Y position, move down one pixel
3408: C9          ret                 ; return

; This subroutine handles fireball animation.
; called from #33E7 and from #33C0

3409: DD 7E 15    ld      a,(ix+$15)  ; \  Jump if it is not time to change animation frames yet
340C: A7          and     a           ;  |
340D: C2 28 34    jp      nz,$3428    ; /

3410: DD 36 15 02 ld      (ix+$15),$02; Reset animation change timer
3414: DD 34 07    inc     (ix+$07)    ; \  Toggles the lowest 4 bits of +#07 between D and E, this toggles between two possible graphics that
3417: DD 7E 07    ld      a,(ix+$07)  ;  | the fireball can use
341A: E6 0F       and     $0f         ;  |
341C: FE 0F       cp      $0f         ;  |
341E: C0          ret     nz          ;  |
341F: DD 7E 07    ld      a,(ix+$07)  ;  |
3422: EE 02       xor     $02         ;  |
3424: DD 77 07    ld      (ix+$07),a  ; /
3427: C9          ret                 ; return

3428: DD 35 15    dec     (ix+$15)    ; Decrement animation change timer
342B: C9          ret                 ; return

; The subroutine handles fireball movement as it spawns out of the oilcan on barrels.
; Called from #32CE

342C: DD 6E 1A    ld      l,(ix+$1a)  ; \ Load HL with address into Y-position table
342F: DD 66 1B    ld      h,(ix+$1b)  ; /
3432: AF          xor     a           ; \  Jump if HL is non-zero (i.e., if this is not the very first spawning frame)
3433: 01 00 00    ld      bc,$0000    ;  |
3436: ED 4A       adc     hl,bc       ;  |
3438: C2 42 34    jp      nz,$3442    ; /

343B: 21 8C 3A    ld      hl,$3a8c    ; We just began to spawn, load HL with address of start of Y-position table
343E: DD 36 03 26 ld      (ix+$03),$26; Initialize X position to #26, the X-position of the oilcan

; This table stores the Y-positions a fireball should have each frame to follow a parabolic arc used when fireballs are coming out of oilcans.
        ; 3A8C:  E8 E5 E3 E2
        ; 3A90:  E1 E0 DF DE DD DD DC DC DC DC DC DC DD DD DE DF
        ; 3AA0:  E0 E1 E2 E3 E4 E5 E7 E9 EB ED F0 AA

3442: DD 34 03    inc     (ix+$03)    ; Increment X-position

3445: 7E          ld      a,(hl)      ; \  Jump if we've reached the end of the Y-position table (marked by #AA)
3446: FE AA       cp      $aa         ;  |
3448: CA 56 34    jp      z,$3456     ; /

344B: DD 77 05    ld      (ix+$05),a  ; Else store table data into fire's Y-position
344E: 23          inc     hl          ; \  Advance to next table entry, for the next frame
344F: DD 75 1A    ld      (ix+$1a),l  ;  |
3452: DD 74 1B    ld      (ix+$1b),h  ; /
3455: C9          ret                 ; return

; Fire has completed its spawning and is now free-floating
3456: AF          xor     a           ; A := 0
3457: DD 77 13    ld      (ix+$13),a  ; Clear fire animation height counter
345A: DD 77 18    ld      (ix+$18),a  ; Clear firefox spawning indicator
345D: DD 77 0D    ld      (ix+$0d),a  ; Set direction to left
3460: DD 77 1C    ld      (ix+$1c),a  ; Clear the still indicator
3463: DD 7E 03    ld      a,(ix+$03)  ; \ Make copy of X-position
3466: DD 77 0E    ld      (ix+$0e),a  ; /
3469: DD 7E 05    ld      a,(ix+$05)  ; \ Make copy of Y-position
346C: DD 77 0F    ld      (ix+$0f),a  ; /
346F: DD 36 1A 00 ld      (ix+$1a),$00; \ Clear address into Y-position spawning table
3473: DD 36 1B 00 ld      (ix+$1b),$00; / [these last two could have been written above with one less byte each]
3477: C9          ret                 ; return

; This subroutine handles fireball movement as it spawns out of the oilcan on conveyors.
; Called from #32D2

3478: DD 6E 1A    ld      l,(ix+$1a)  ; \ Load HL with address into Y-position table
347B: DD 66 1B    ld      h,(ix+$1b)  ; /
347E: AF          xor     a           ; \  Jump if HL is non-zero (i.e., if this is not the very first spawning frame)
347F: 01 00 00    ld      bc,$0000    ;  |
3482: ED 4A       adc     hl,bc       ;  |
3484: C2 9A 34    jp      nz,$349a    ; /

3487: 21 AC 3A    ld      hl,$3aac    ; load HL with start of table data
348A: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; \  Jump if Mario is on left side of the screen, in this case we spawn the fireball on the left
348D: CB 7F       bit     7,a         ;  |
348F: CA A8 34    jp      z,$34a8     ; /

3492: DD 36 0D 01 ld      (ix+$0d),$01; Set fireball direction to "right"
3496: DD 36 03 7E ld      (ix+$03),$7e; Initialize X position to #7E

349A: DD 7E 0D    ld      a,(ix+$0d)  ; \  Jump if fireball moving left
349D: FE 01       cp      $01         ;  |
349F: C2 B3 34    jp      nz,$34b3    ; /

34A2: DD 34 03    inc     (ix+$03)    ; Moving right, Increment X-position
34A5: C3 45 34    jp      $3445       ; Jump back, remainder of subroutine shared with the above subroutine

34A8: DD 36 0D 02 ld      (ix+$0d),$02; Set fireball direction to "special" left (This isn't actually used at all after spawning, since immediately
                                        ; after spawning it will check to reverse rection and receive a direction of either "right" or "left".
34AC: DD 36 03 80 ld      (ix+$03),$80; Initialize X position to #80
34B0: C3 9A 34    jp      $349a       ; Jump back [why there?  after setting direction, we should jump directly to #34B3]

34B3: DD 35 03    dec     (ix+$03)    ; Moving left, Decrement X-position
34B6: C3 45 34    jp      $3445       ; Jump back, remainder of subroutine shared with the above subroutine

; On rivets, this subroutine spawns a fireball on a random platform besides the very top on the side of the screen opposite the the side that Mario
; is on.
; Called from #32CA when screen is elevators or rivets

34B9: 3A 27 62    ld      a,(screen_number_6227)   ; \  Return if current screen is elevators (Can this ever happen?)
34BC: FE 03       cp      $03         ;  |
34BE: C8          ret     z           ; /

34Bf: 3A 03 62    ld      a,(jump_if_bit_7_of_mario_x_position_is_set_6203)   ; \  Jump if bit 7 of Mario's X-position is set (i.e., Mario is on the right half of the screen)
34C2: CB 7F       bit     7,a         ;  |
34C4: C2 ED 34    jp      nz,$34ed    ; /

34C7: 21 C4 3A    ld      hl,$3ac4    ; Load HL with start of table data for spawning fireball on right side

; Possible X and Y positions to spawn a fireball on the right side of the screen
; First value is X position, 2nd value is Y position

; 3AC4:  EE F0  ; bottom, right
; 3AC6:  DB A0  ; middle, right
; 3AC8:  E6 C8  ; 2nd from bottom, right
; 3ACA:  D6 78  ; 2nd from top, right
; 3ACC:  EB F0  ; unused?
; 3ACE:  DB A0  ; unused?
; 3AD0:  E6 C8  ; unused?
; 3AD2:  E6 C8  ; unused?

; Possible X and Y positions to spawn a fireball on the left side of the screen
; First value is X position, 2nd value is Y position

; 3AD4:  1B C8  ; 2nd from bottom, left
; 3AD6:  23 A0  ; middle, left
; 3AD8:  2B 78  ; 2nd from top, left
; 3ADA:  12 F0  ; bottom, left
; 3ADC:  1B C8  ; unused?
; 3ADE:  23 A0  ; unused?
; 3AE0:  12 F0  ; unused?
; 3AE2:  1B C8  ; unused?



34CA: 06 00       ld      b,$00       ; \  Load BC with one of #0000, #0002, #0004, or #0006 randomly
34CC: 3A 19 60    ld      a,(rngtimer2_6019) ;  |
34CF: E6 06       and     $06         ;  |
34D1: 4F          ld      c,a         ; /
34D2: 09          add     hl,bc       ; add this result into HL to get offset into table
34D3: 7E          ld      a,(hl)      ; \  Copy X-position from table into fireball X-position
34D4: DD 77 03    ld      (ix+$03),a  ;  |
34D7: DD 77 0E    ld      (ix+$0e),a  ; /
34DA: 23          inc     hl          ; next table entry
34DB: 7E          ld      a,(hl)      ; \  Copy Y-position from table into fireball Y-position
34DC: DD 77 05    ld      (ix+$05),a  ;  |
34DF: DD 77 0F    ld      (ix+$0f),a  ; /
34E2: AF          xor     a           ; A := 0
34E3: DD 77 0D    ld      (ix+$0d),a  ; Set fireball direction to left
34E6: DD 77 18    ld      (ix+$18),a  ; Clear fireball spawning indicator
34E9: DD 77 1C    ld      (ix+$1c),a  ; Clear +1C = still indicator
34EC: C9          ret                 ; return

34ED: 21 D4 3A    ld      hl,$3ad4    ; Load HL with alternate start of table data for spawning fireball on left side.
34F0: C3 CA 34    jp      $34ca       ; Jump back

; update fires or firefoxes to hardware
; called from #30F6

34F3: 21 00 64    ld      hl,start_of_fires_table_6400    ; start of fire/firefox data
34F6: 11 D0 69    ld      de,start_of_firefox_sprites_69d0    ; start of firefox sprites (hardware)
34F9: 06 05       ld      b,$05       ; For B = 1 to 5

34FB: 7E          ld      a,(hl)      ; get firefox data
34FC: A7          and     a           ; is this sprite active ?
34FD: CA 1E 35    jp      z,$351e     ; no, jump away and set for next sprite

3500: 2C          inc     l
3501: 2C          inc     l
3502: 2C          inc     l           ; HL now points to firefox's X position (IX + #03)
3503: 7E          ld      a,(hl)      ; load A with firefox X position
3504: 12          ld      (de),a      ; store into sprite X position
3505: 3E 04       ld      a,$04       ; A := 4
3507: 85          add     a,l         ; add to L
3508: 6F          ld      l,a         ; HL now points to firefox's Y position (IX + #07)
3509: 1C          inc     e           ; next DE, now it has sprite Y position
350A: 7E          ld      a,(hl)      ; load A with firefox Y position
350B: 12          ld      (de),a      ; store into hardaware sprite Y position
350C: 2C          inc     l           ; next HL
350D: 1C          inc     e           ; next DE
350E: 7E          ld      a,(hl)      ; load A with firefox sprite color value
350F: 12          ld      (de),a      ; store sprite color
3510: 2D          dec     l
3511: 2D          dec     l
3512: 2D          dec     l           ; decrease HL by 3.  now it points to sprite value
3513: 1C          inc     e           ; next DE
3514: 7E          ld      a,(hl)      ; load A with sprite value
3515: 12          ld      (de),a      ; store sprite value to hardware
3516: 13          inc     de          ; next DE

3517: 3E 1B       ld      a,$1b       ; A := #1B
3519: 85          add     a,l         ; add to L
351A: 6F          ld      l,a         ; store into L.  HL how has #1B more.  The next sprite is referenced
351B: 10 DE       djnz    $34fb       ; Next Firefox

351D: C9          ret                 ; return

; arrive here when firefox is not being used, sets pointer for next sprite

351E: 3E 05       ld      a,$05       ; A := 5
3520: 85          add     a,l         ; add to L
3521: 6F          ld      l,a         ; store into L.  HL is now 5 more than before
3522: 3E 04       ld      a,$04       ; A := 4
3524: 83          add     a,e         ; add to E
3525: 5F          ld      e,a         ; store into E.  DE is now 4 more than before.  next sprite
3526: C3 17 35    jp      $3517       ; jump back

; table data
; used for item scoring :  100, 200 , 300 etc
; called from #0525


3529:  00 00 00
352C:  00 01 00
352F:  00 02 00
3532:  00 03 00
3535:  00 04 00
3538:  00 05 00
353B:  00 06 00
353E:  00 07 00
3541:  00 08 00
3544:  00 09 00
3547:  00 00 00
354A:  00 10 00
354D:  00 20 00
3550:  00 30 00
3553:  00 40 00
3556:  00 50 00
3559:  00 60 00
355C:  00 70 00
355F:  00 80 00
3562:  00 90 00

;  table data .. loaded at #025A when game is powered on or reset
; transferred into #6100 to #61AA
; high score table

; first 2 bytes form a VRAM address. EG #7794 through #779C
; 3rd byte is the place.  1 through 5
; 4th and 5th bytes are either "ST" or "ND" or "RD" or "TH"
; 6th and 7th bytes are #10 for blank spaces
; 8th through 13th bytes are teh score digits
; 14 through end are #10 for blank spaces, ended by #3F end code
; after this is the actual score
; the last 2 bytes are ???

3565:  94 77 01 23 24 10 10 00 00 07 06 05 00 10 10 10 10 10 10 10 10 10 10 10 10 10 10 3F 00 50 76 00 F4 76
3587:  96 77 02 1E 14 10 10 00 00 06 01 00 00 10 10 10 10 10 10 10 10 10 10 10 10 10 10 3F 00 00 61 00 F6 76
35A9:  98 77 03 22 14 10 10 00 00 05 09 05 00 10 10 10 10 10 10 10 10 10 10 10 10 10 10 3F 00 50 59 00 F8 76
35CB:  9A 77 04 24 18 10 10 00 00 05 00 05 00 10 10 10 10 10 10 10 10 10 10 10 10 10 10 3F 00 50 50 00 FA 76
35EE:  9C 77 05 24 18 10 10 00 00 04 03 00 00 10 10 10 10 10 10 10 10 10 10 10 10 10 10 3F 00 00 43 00 FC 76

; data read at #1611
; used for high score entry ???

360F:                                               3B
3610:  5C 4B 5C 5B 5C 6B 5C 7B 5C 8B 5C 9B 5C AB 5C BB
3620:  5C CB 5C 3B 6C 4B 6C 5B 6C 6B 6C 7B 6C 8B 6C 9B
3630:  6C AB 6C BB 6C CB 6C 3B 7C 4B 7C 5B 7C 6B 7C 7B
3640:  7C 8B 7C 9B 7C AB 7C BB 7C CB 7C

; #364B is used from #05E9

364B:  8B 36            0       ; #368B "GAME OVER"
364D:  01 00            1       ; unused ?
364F:  98 36            2       ; #3698 "PLAYER <I>"
3651:  A5 36            3       ; #36A5 "PLAYER <II>"
3653:  B2 36            4       ; #36B2 "HIGH SCORE"
3655:  BF 36            5       ; #36BF "CREDIT"
3657:  06 00            6       ; unused ?
3659:  CC 36            7       ; #36CC "HOW HIGH CAN YOU GET?"
                                        "IT'S ON LIKE KONKEY DONG!"
365B:  08 00            8       ; unused ?
365D:  E6 36            9       ; #36E6 "ONLY 1 PLAYER BUTTON"
365F:  FD 36            A       ; #36FD "1 OR 2 PLAYERS BUTTON"
3661:  0B 00            B       ; unused ?
3663:  15 37            C       ; #3715 "PUSH"
3665:  1C 37            D       ; #371C "NAME REGISTRATION"
3667:  30 37            E       ; #3730 "NAME:"
3669:  38 37            F       ; #3738 "---"
366B:  47 37            10      ; #3747 "A" through "J"
366D:  5D 37            11      ; #375D "K through "T"
366F:  73 37            12      ; #3773 "U" through "Z" and "RUBEND"
3671:  8B 37            13      ; #378B "REGI TIME"
3673:  00 61            14      ; #6100 High score entry 1 ?
3675:  22 61            15      ; #6122 High score entry 2 ?
3677:  44 61            16      ; #6144 High score entry 3 ?
3679:  66 61            17      ; #6166 High score entry 4 ?
367B:  88 61            18      ; #6188 High score entry 5?
367D:  9E 37            19      ; #379E "RANK SCORE NAME"
367F:  B6 37            1A      ; #37B6 "YOUR NAME WAS REGISTERED"
3681:  D2 37            1B      ; #37D2 "INSERT COIN"
3683:  E1 37            1C      ; #37E1 "PLAYER    COIN"
3685:  1D 00            1D      ; unused ?
3687:  00 3F            1E      ; #3F00 "(C) 1981"
3689:  09 3F            1F      ; #3F09 "NINTENDO OF AMERICA"

368A:                                   96 76 17 11 1D             ..GAM
3690:  15 10 10 1F 26 15 22 3F 94 76 20 1C 11 29 15 22  E..OVER...PLAYER
36A0:  10 30 32 31 3F 94 76 20 1C 11 29 15 22 10 30 33  .<I>...PLAYER.<2
36B0:  31 3F 80 76 18 19 17 18 10 23 13 1F 22 15 3F 9F  >...HIGH.SCORE..
36C0:  75 13 22 15 14 19 24 10 10 10 10 3F 5E 77 18 1F  .CREDIT.......HO
36D0:  27 10 18 19 17 18 10 13 11 1E 10 29 1F 25 10 17  W.HIGH.CAN.YOU.G
36E0:  15 24 10 FB 10 3F 29 77 1F 1E 1C 29 10 01 10 20  ET.?....ONLY.1.P
36F0:  1C 11 29 15 22 10 12 25 24 24 1F 1E 3F 29 77 01  LAYER.BUTTON...1
3700:  10 1F 22 10 02 10 20 1C 11 29 15 22 23 10 12 25  .OR.2.PLAYERS.BU
3710:  24 24 1F 1E 3F 27 76 20 25 23 18 3F 06 77 1E 11  TTON...PUSH...NA
3720:  1D 15 10 22 15 17 19 23 24 22 11 24 19 1F 1E 3F  ME.REGISTRATION.
3730:  88 76 1E 11 1D 15 2E 3F E9 75 2D 2D 2D 10 10 10  ..NAME:...---...
3740:  10 10 10 10 10 10 3F 0B 77 11 10 12 10 13 10 14  .........A.B.C.D
3750:  10 15 10 16 10 17 10 18 10 19 10 1A 3F 0D 77 1B  .E.F.G.H.I.J...K
3760:  10 1C 10 1D 10 1E 10 1F 10 20 10 21 10 22 10 23  .L.M.N.O.P.Q.R.S
3770:  10 24 3F 0F 77 25 10 26 10 27 10 28 10 29 10 2A  .T...U.V.W.X.Y.Z
3780:  10 2B 10 2C 44 45 46 47 48 10 3F F2 76 22 15 17  ...-RUBEND...REG
3790:  19 10 24 19 1D 15 10 10 30 03 00 31 10 3F 92 77  I.TIME..........
37A0:  22 11 1E 1B 10 10 23 13 1F 22 15 10 10 1E 11 1D  RANK..SCORE..NAM
37B0:  15 10 10 10 10 3F 72 77 29 1F 25 22 10 1E 11 1D  E.......YOUR.NAM
37C0:  15 10 27 11 23 10 22 15 17 19 23 24 15 22 15 14  E.WAS.REGISTERED
37D0:  42 3F A7 76 19 1E 23 15 22 24 10 13 1F 19 1E 10  ....INSERT.COIN.
37E0:  3F 0A 77 10 10 20 1C 11 29 15 22 10 10 10 10 13  .....PLAYER....C
37F0:  1F 19 1E 3F FC 76 49 4A 10 1E 19 1E 24 15 1E 14  OIN......NINTEND
3800:  1F 10 10 10 10 3F                                O.....

; ???

3806:  7C 75 01 09 08 01 3F

; table data used for game intro

380D:  02 97 38 68 38   ; top level where girl sits
3812:  02 DF 54 10 54   ; kongs level girder
3817:  02 EF 6D 20 6D   ; 2nd girder down
381C:  02 DF 8E 10 8E   ; 3rd girder down
3821:  02 EF AF 20 AF   ; 4th girder down
3826:  02 DF D0 10 D0   ; 5th girder down
382B:  02 EF F1 10 F1   ; bottom girder
3830:  00 53 18 53 54   ; kong's ladder (left)
3835:  00 63 18 63 54   ; kong's ladder (right)
383A:  00 93 38 93 54   ; ladder to reach girl
383F:  00 83 54 83 F1   ; long ladder (left)
3834:  00 93 54 93 F1   ; long ladder (right)
3849:  AA               ; end of data code

; table data
; used for timer graphic and zero score inside

384A:  8D 7D 8C
384D:  6F 00 7C
3850:  6E 00 7C
3853:  6D 00 7C
3856:  6C 00 7C
3859:  8F 7F 8E

; table data
; used for antimation of kong

385C:  47 27 08 50
3860:  2F A7 08 50
3864:  3B 25 08 50
3868:  00 70 08 48
386C:  3B 23 07 40
3870:  46 A9 08 44
3874:  00 70 08 48
3878:  30 29 08 44
387C:  00 70 08 48
3880:  00 70 0A 48

; table data used to draw the girl from #0D7A and #0B2A

3884:  6F 10 09 23
3888:  6F 11 0A 33

; used for animation of kong

388C:  50 34 08 3C
3890:  00 35 08 3C
3894:  53 32 08 40
3898:  63 33 08 40
389C:  00 70 08 48
38A0:  53 36 08 50
38A4:  63 37 08 50
38A8:  6B 31 08 41
38AC:  00 70 08 48
38B0:  6A 14 0A 48

; used when kong jump at end of intro

38B4:              FD FD FD FD FD FD FD FE FE FE FE FE
38C0:  FE FF FF FF FF 00 00 01 01 01
38CA:  7F                       ; end code


; used when kong jumps to left during intro at #0B70

38CB:                                   FF FF FF FF FF
38D0:  00 FF 00 00 01 00 01 01 01 01 01 7F

; used after kong has jumped
; used in #0DA7.  end code is #AA

38DC:  04 7F F0 10 F0
38E1:  02 DF F2 70 F8
38E6:  02 6F F8 10 F8
38EB:  AA

38EC:  04 DF D0 90 D0
38F1:  02 DF DC 20 D1
38F6:  AA

38F7:  FF FF FF FF FF   ; unused ?

38FC:  04 DF A8 20 A8
3901:  04 5F B0 20 B0
3906:  02 DF B0 20 BB
390B:  AA

390C:  04 DF 88 30 88
3911:  04 DF 90 B0 90
3916:  02 DF 9A 20 8F
391B:  AA

391C:  04 BF 68 20 68
3921:  04 3F 70 20 70
3926:  02 DF 6E 20 79
3927:  AA

392C:  02 DF 58 A0 55   ; top right ledge angled down
3931:  AA

; this is table data
; used for animation of kong
; used from #2D24

3932:  00 70 08 44
3936:  2B AC 08 4C
393A:  3B AE 08 4C
393E:  3B AF 08 3C
3942:  4B B0 07 3C
3946:  4B AD 08 4C
394A:  00 70 08 44
394E:  00 70 08 44
3952:  00 70 08 44
3956:  00 70 0A 44

; used to animate kong

395A:  47 27 08 4C
395E:  2F A7 08 4C
3962:  3B 25 08 4C
3966:  00 70 08 44
396A:  3B 23 07 3C
396E:  4B 2A 08 3C
3972:  4B 2B 08 4C
3976:  2B AA 08 3C
397A:  2B AB 08 4C
397E:  00 70 0A 44

; used for kong's middle deploy

3982:  00 70 08 44
3986:  4B 2C 08 4C
398A:  3B 2E 08 4C
398E:  3B 2F 08 3C
3992:  2B 30 07 3C
3996:  2B 2D 08 4C
399A:  00 70 08 44
399E:  00 70 08 44
39A2:  00 70 08 44
39A6:  00 70 0A 44

; used in #2E3D on elevators
; used for bouncers; each is an offset that is added to the Y position as it moves

39AA:  FD FD FD FE FE FE FE FF FF 00 FF 00 00 01 00 01 01 02 02 02 02 03 03 03
39C2:  7F       ; end code

; used in #2D8C for barrel release

39C3:  1E 4E BB 4C D8 4E 59 4E 7F

; table data having to do with crazy barrels.
; used in #2D83

39CC  BB                ; for crazy barrels
39CD  4D                ;
39CE  7F                ; deployed when #7F

; table data
; kong is beating his chest

39CF:  47 27 08 50
39D3:  2D 26 08 50
39D7:  3B 25 08 50
39DA:  00 70 08 48
39DF:  3B 24 07 40
39E3:  4B 28 08 40
39E7:  00 70 08 48
39EA:  30 29 08 44
39EF:  00 70 08 48
39F3:  00 70 0A 48

; table data for animation of kong #28 bytes (40 decimal)
; used in #0445
; the kong is beating his chest with right leg lifted

39F7:  49 A6 08 50 2F A7 08 50 3B 25 08 50 00 70 08 48
3A07:  3B 24 07 40 46 A9 08 44 00 70 08 48 2B A8 08 40
3A17:  00 70 08 48 00 70 0A 48

; table data for upside down kong after rivets cleared
; used in #1870
; #28 bytes = 40 bytes decimal

3A1F:  73 A7 88 60
3A23:  8B 27 88 60
3A27:  7F 25 88 60
3A2B:  00 70 88 68
3A2F:  7F 24 87 70
3A33:  74 29 88 6C
3A37:  00 70 88 68
3A3B:  8A A9 88 6C
3A3F:  00 70 88 68
3A43:  00 70 8A 68

; table data
; used when rivets are cleared

3A47:  05 AF F0 50 F0 AA
3A4D:  05 AF E8 50 E8 AA
3A53:  05 AF E0 50 E0 AA
3A59:  05 AF D8 50 D8 AA
3A5F:  05 B7 58 48 58 AA

; this table is used for the various screen patterns for the levels
; code 1 = girders, 4 = rivets, 2 = pies, 3 = elevators
; used from #1947 and from #1799 and from #09BA

3A65:  01 04                    ; level 1
3A67:  01 03 04                 ; level 2
3A6A:  01 02 03 04              ; level 3
3A6E:  01 02 01 03 04           ; level 4
3A73:  01 02 01 03 01 04        ; level 5 +
3A79:  7F                       ; end code

; table data referenced in #3267

3A7A:  FF 00 FF FF FE FE FE FE FE FE FE FE FE FE FE FF FF 00

; table data referenced in #343B

3A8C:  E8 E5 E3 E2
3A90:  E1 E0 DF DE DD DD DC DC DC DC DC DC DD DD DE DF
3AA0:  E0 E1 E2 E3 E4 E5 E7 E9 EB ED F0 AA

; table data refeernced in #
; controls the positions of fires coming out of the oil can on the conveyors

3AAC:  80 7B 78 76 74 73 72 71 70 70 6F 6F 6F 70 70 71 72 73 74 75 76 77 78
3AC3:  AA               ; end code

; table data referenced in #34C7

3AC4:  EE F0 DB A0 E6 C8 D6 78 EB F0 DB A0 E6 C8 E6 C8

; table data referenced in #34ED

3AD4:  1B C8 23 A0 2B 78 12 F0 1B C8 23 A0 12 F0 1B C8

; start of table data
; used for screen 1 (girders)
; 120 bytes long
; 1st byte is the code [6 = X character, 5 = circle girder used in rivets, 3 = conveyor, 2 = girder, 1 = broken ladder, 0 = ladder]
; 2nd and 3rd bytes are the X,Y locations to start drawing
; data used for #6300


3AE4:  02 97 38 68 38   ; top girder where girl sits
3AE9:  02 9F 54 10 54   ; girder where kong sits
3AED:  02 DF 58 A0 55   ; 1st slanted girder at top right
3AF3:  02 EF 6D 20 79   ; 2nd slanted girder (has hammer at left side)
3AF8:  02 DF 9A 10 8E   ; 3rd slanted girder
3AFD:  02 EF AF 20 BB   ; 4th slanted girder
3B02:  02 DF DC 10 D0   ; 5th slanted girder (has hammer at right side)
3B07:  02 FF F0 80 F7   ; bottom slanted girder
3B0C:  02 7F F8 00 F8   ; bottom flat girder where mario starts
3B11:  00 CB 57 CB 6F   ; short ladder at top right
3B16:  00 CB 99 CB B1   ; short ladder at center right
3B1B:  00 CB DB CB F3   ; short ladder at bottom right
3B20:  00 63 18 63 54   ; kong's ladder (right)
3B25:  01 63 D5 63 F8   ; bottom broken ladder
3B2A:  00 33 78 33 90   ; short ladder at left side under top hammer
3B2F:  00 33 BA 33 D2   ; short ladder at left side above oil can
3B34:  00 53 18 53 54   ; kong's ladder (left)
3B39:  01 53 92 53 B8   ; second broken ladder from bottom, on 3rd girder
3B3E:  00 5B 76 5B 92   ; longer ladder under the top left hammer
3B43:  00 73 B6 73 D6   ; longer ladder to left of bottom hammer
3B48:  00 83 95 83 B5   ; center longer ladder
3B4D:  00 93 38 93 54   ; ladder leading to girl
3B52:  01 BB 70 BB 98   ; third broken ladder on right side near top
3B57:  01 6B 54 6B 75   ; fourth broken ladder near kong
3B5C:  AA               ; AA code signals end of data

; table data for screen 2 conveyors
; 135 bytes long

3B5D:  06 8F 90 70 90   ; central patch of XXX's
3B62:  06 8F 98 70 98   ; central patch of XXX's
3B67:  06 8F A0 70 A0   ; central patch of XXX's
3B6C:  00 63 18 63 58   ; kong's ladder (right)
3B71:  00 63 80 63 A8   ; center ladder to left of oil can fire
3B76:  00 63 D0 63 F8   ; bottom level ladder #2 of 4
3B7B:  00 53 18 53 58   ; kong's ladder (left)
3B80:  00 53 A8 53 D0   ; ladder under the hat
3B85:  00 9B 80 9B A8   ; center ladder to right of oil can fire
3B8A:  00 9B D0 9B F8   ; bottom level ladder #3 of 4
3B8F:  01 23 58 23 80   ; top broken ladder left side
3B94:  01 DB 58 DB 80   ; top broken ladder right side
3B99:  00 2B 80 2B A8   ; ladder on left platform with hammer
3B9E:  00 D3 80 D3 A8   ; ladder on right plantform with umbrella
3BA3:  00 A3 A8 A3 D0   ; ladder to right of bottom hammer
3BA8:  00 2B D0 2B F8   ; bottom level ladder #1 of 4
3BAD:  00 D3 D0 D3 F8   ; bottom level ladder #4 of 4
3BB2:  00 93 38 93 58   ; ladder leading to girl
3BB7:  02 97 38 68 38   ; girder where girl sits
3BBC:  03 EF 58 10 58   ; top conveyor girder
3BC1:  03 F7 80 88 80   ; top right conveyor next to oil can
3BC6:  03 77 80 08 80   ; top left conveyor next to oil can
3BCB:  02 A7 A8 50 A8   ; center ledge
3BD0:  02 E7 A8 B8 A8   ; right center ledge
3BD5:  02 3F A8 18 A8   ; left center ledge (has hammer)
3BDA:  03 EF D0 10 D0   ; main lower conveyor girder (has hammer)
3BDF:  02 EF F8 10 F8   ; bottom level girder
3BE4:  AA               ; end code

; table data for the elevators
; 165 bytes long

3BE5:  00 63 18 63 58   ; kong's ladder (right)
3BEA:  00 63 88 63 D0   ; center ladder right
3BEF:  00 53 18 53 58   ; long's ladder (left)
3BF4:  00 53 88 53 D0   ; center ladder left
3BF9:  00 E3 68 E3 90   ; far top right ladder leading to purse
3BFE:  00 E3 B8 E3 D0   ; far bottom right ladder
3C03:  00 CB 90 CB B0   ; ladder leading to purse (lower level)
3C08:  00 B3 58 B3 78   ; ladder leading to kong's level
3C0D:  00 9B 80 9B A0   ; ladder to right of top right elevator
3C12:  00 93 38 93 58   ; ladder leading up to girl
3C17:  00 23 88 23 C0   ; long ladder on left side
3C1C:  00 1B C0 1B E8   ; bottom left ladder
3C21:  02 97 38 68 38   ; girder girl is on
3C26:  02 B7 58 10 58   ; kong's girder
3C2B:  02 EF 68 E0 68   ; girder where purse is
3C30:  02 D7 70 C8 70   ; girder to left of purse
3C35:  02 BF 78 B0 78   ; girder holding ladder that leads up to kong's level
3C3A:  02 A7 80 90 80   ; girder to right of top right elevator
3C3F:  02 67 88 48 88   ; top girder for central ladder section between elevators
3C34:  02 27 88 10 88   ; girder that holds the umbrella
3C39:  02 EF 90 C8 90   ; girder under the girder that has the purse
3C4E:  02 A7 A0 98 A0   ; bottom girder for section to right of top right elevator
3C53:  02 BF A8 B0 A8   ; small floating girder
3C58:  02 D7 B0 C8 B0   ; small girder
3C5D:  02 EF B8 E0 B8   ; small girder
3C62:  02 27 C0 10 C0   ; girder just above mario start
3C67:  02 EF D0 D8 D0   ; small girder on far right bottom
3C6C:  02 67 D0 50 D0   ; bottom girder for central ladder section between elevators
3C71:  02 CF D8 C0 D8   ; small girder
3C76:  02 B7 E0 A8 E0   ; small girder
3C7B:  02 9F E8 88 E8   ; floating girder where the right side elevator gets off
3C80:  02 27 E8 10 E8   ; girder where mario starts
3C85:  02 EF F8 10 F8   ; long bottom girder (mario dies if he gets that low)
3C8A:  AA               ; end code

; table data for the rivets

3C8B:  00 7B 80 7B A8   ; center ladder level 3
3C90:  00 7B D0 7B F8   ; bottom center ladder
3C95:  00 33 58 33 80   ; top left ladder
3C9A:  00 53 58 53 80   ; top left ladder (right side)
3C9F:  00 AB 58 AB 80   ; top right ladder (left side)
3CA4:  00 CB 58 CB 80   ; top right ladder
3CA9:  00 2B 80 2B A8   ; level 3 ladder left side
3CAE:  00 D3 80 D3 A8   ; level 3 ladder right side
3CB3:  00 23 A8 23 D0   ; level 2 ladder left side
3CB8:  00 5B A8 5B D0   ; level 2 ladder #2 of 4
3CBD:  00 A3 A8 A3 D0   ; level 2 ladder #3 of 4
3CC2:  00 DB A8 DB D0   ; level 2 ladder right side
3CC7:  00 1B D0 1B F8   ; bottom left ladder
3CCC:  00 E3 D0 E3 F8   ; bottom right ladder
3CD1:  05 B7 30 48 30   ; girder above kong
3CD6:  05 CF 58 30 58   ; girder kong stands on
3CDB:  05 D7 80 28 80   ; level 4 girder
3CE0:  05 DF A8 20 A8   ; level 3 girder
3CE5:  05 E7 D0 18 D0   ; level 2 girder
3CEA:  05 EF F8 10 F8   ; bottom level girder
3CEF:  AA               ; end code

;

3CF0:  10 82 85 8B 10 85 80 8B 10 87 85 8B 81 80 80 8B  .25m.50m.75m100m
3D00:  81 82 85 8B 81 85 80 8B                          125m150m

; used to draw the game logo in attract mode
; data called from #07F7
; data grouped in 3's
; first byte is a loop counter - how many things to draw, going down
; 2nd and 3rd bytes are coordinates to start

3D08:  05 88 77 01 68 77 01 6C 77 03 49 77              ; D
3D14:  05 08 77 01 E8 76 01 EC 76 05 C8 76              ; O
3D20:  05 88 76 02 69 76 02 4A 76 05 28 76              ; N
3D2C:  05 E8 75 01 CA 75 03 A9 75 01 88 75 01 8C 75     ; K
3D3B:  05 48 75 01 28 75 01 2A 75                       ; E (part 1)
3D44:  01 2C 75 01 08 75 01 0A 75 01 0C 75              ; E (part 2)
3D50:  03 C8 74 03 AA 74 03 88 74                       ; Y
3D59:  05 2F 77 05 0F 77 02 F0 76 02 CF 76 02 D2 76     ; K
3D68:  05 8F 76 05 6F 76 01 4F 76 01 53 76 05 2F 76     ; O
3D77:  05 EF 75 02 D0 75 02 B1 75 05 8F 75              ; N
3D83:  03 50 75 05 2F 75 01 0F 75 01 13 75              ; G (part 1)
3D8F:  01 EF 74 01 F1 74 01 F3 74 02 D1 74              ; G (part 2)
3D9B:  00                                               ; end code

; table code reference from #0F6F
; values are copied into #6280 through #6280 + #40

3D9C:                                      00 00 23 68
3DA0:  01 11 00 00 00 10 DB 68 01 40 00 00 08 01 01 01
3DB0:  01 01 01 01 01 01 00 00 00 00 00 00 80 01 C0 FF
3DC0:  01 FF FF 34 C3 39 00 67 80 69 1A 01 00 00 00 00
3DD0:  00 00 00 00 04 00 10 00 00 00 00 00

; data used for the barrel pile next to kong
; called from #0FD7

3DDC  1E 18 0B 4B       ; first barrel
3DE0  14 18 0B 4B       ; second barrel
3DE4  1E 18 0B 3B       ; third barrel
3DE8  14 18 0B 3B       ; fourth barrel

; the following is table data that gets copied to #6407 - location and other data of the fires?
; 05 is a loop varialbe
; 1C loops value corresponds to total length of table

3DEC  3D 01 03 02

; table data that also gets called from #1138
; DE is #6407 - Fire # 1 y value
; B is 05 and C is 1C

3DF0:  4D 01 04 01

3DF4:  27 70 01 E0 00 00        ; initial data for fires on girders ?
3DFA:  7F 40 01 78 02 00        ; initial data for conveyors to release a fire ?

; table data called from #0FF5.  4 bytes

3E00  27 49 0C F0               ; oil can for girders
3E04  7F 49 0C 88               ; oil can for conveyors ?

; another table called and copied into #6687-668A an #6697-#669A - has to do with the hammers
; B counter is #02 and C is #0C
; called from #122E
; 3E0C is called also from #1000

3E08:  1E 07            ; 1E is the hammer sprite value.  07 is hammer color
3E0A:  03 09            ; ???
3E0C:  24 64            ; position of top hammer for girders.  24 is X, 64 is Y
3E0E:  BB C0            ; bottom hammer for girders at BB, C0

3E10:  23 8D 7B B4      ; for conveyors

3E14:  1B 8C 7C 64      ; for rivets
3E18:  4B 0E 04 02      ; ???

; 2 ladder sprites for conveyors
; 46 = ladder

3E1C:  23 46 03 68              ; ladder at 23, 68
3E20:  DB 46 03 68              ; ladder at DB, 68

; the 6 conveyor pulleys

3E24:  17 50 00 5C              ; 50 = edge of conveyor pulley
3E28:  E7 D0 00 5C              ; D0 = edge of conveyor pulley inverted
3E2C:  8C 50 00 84
3E30:  73 D0 00 84
3E34:  17 50 00 D4
3E38:  E7 D0 00 D4

; bonus items on conveyors

3E3C  53 73 0A A0               ; position of hat on pies is 53,A0
3E40  8B 74 0A F0               ; position of purse on pies is 8B,F0
3E44  DB 75 0A A0               ; umbrella on the pies is at DB,A0

; bonus items for elevators

3E48  5B 73 0A C8               ;  hat at 5B,C8
3E4C  E3 74 0A 60               ;  purse at E3,60
3E50  1B 75 0A 80               ;  umbrella on elevator is 80,1B

; bonus items for rivets

3E54  DB 73 0A C8               ; hat on rivets at DB,C8
3E58  93 74 0A F0               ; purse on rivets at 93,F0
3E5C  33 75 0A 50               ; umbrella on rivets at 33,50

; used in elevators - called from #10CC

3E60:  44 03 08 04

; used in elevators, called from #11EC
; used for elevator sprites

3E64:  37 F4
3E66:  37 C0
3E68:  37 8C                    ; elevators on left all have X value of 37

3E6A:  77 70
3E6C:  77 A4
3E6E:  77 D8                    ; elevators on right all have X value of 77

; award points for jumping a barrels and items
; arrive from #1DD7
; A is preloaded with 1,3, or 7
; patch ?

3E70: 11 01 00    ld      de,$0001    ; 100 points
3E73: 06 7B       ld      b,$7b       ; sprite for 100
3E75: 1F          rra                 ; is the score set for 100 ?
3E76: D2 28 1E    jp      nc,$1e28    ; yes, award points

3E79: 1E 03       ld      e,$03       ; else set 300 points
3E7B: 06 7D       ld      b,$7d       ; sprite for 300
3E7D: 1F          rra                 ; is the score set for 300 ?
3E7E: D2 28 1E    jp      nc,$1e28    ; yes, award points

3E81: 1E 05       ld      e,$05       ; else set 500 points [bug, should be 800]
3E83: 06 7F       ld      b,$7f       ; sprite for 800
3E85: C3 28 1E    jp      $1e28       ; award points


; called from #286B
; a patch ?

3E88: 3A 27 62    ld      a,(screen_number_6227)   ; load A with screen number
3E8B: E5          push    hl          ; save HL
3E8C: EF          rst     $28         ; jump to new location based on screen number

; data for above:

3E8D  00 00                             ; unused
3E8F  99 3E                             ; #3E99 - girders
3E91  B0 28                             ; #28B0 - pie
3E93  E0 28                             ; #28E0 - elevator
3E95  01 29                             ; #2901 - rivets
3E97  00 00                             ; unused

; checks for jumps over items on girders

3E99: E1          pop     hl          ; restore HL
3E9A: AF          xor     a           ; A := 0
3E9B: 32 60 60    ld      (numobstaclesjumped_6060),a; clear counter for barrels jumped
3E9E: 06 0A       ld      b,$0a       ; For B = 1 to #A barrels
3EA0: 11 20 00    ld      de,$0020    ; load DE with offset
3EA3: DD 21 00 67 ld      ix,start_of_barrel_info_table_6700    ; load IX with start of barrel info table
3EA7: CD C3 3E    call    $3ec3       ; call sub below.  check for barrels under jump

3EAA: 06 05       ld      b,$05       ; for B = 1 to 5 fires
3EAC: DD 21 00 64 ld      ix,start_of_fires_table_6400    ; start of fires table
3EB0: CD C3 3E    call    $3ec3       ; check for fires being jumped

3EB3: 3A 60 60    ld      a,(numobstaclesjumped_6060) ; load A with counter for items jumped
3EB6: A7          and     a           ; nothing jumped ?
3EB7: C8          ret     z           ; yes, return

3EB8: FE 01       cp      $01         ; was 1 item jumped?
3EBA: C8          ret     z           ; yes, return; 1 is the code for 100 pts

3EBB: FE 03       cp      $03         ; were less than 3 items jumped ?
3EBD: 3E 03       ld      a,$03       ; A := 3  = code for 2 items, 300 pts score
3EBF: D8          ret     c           ; yes, return

3EC0: 3E 07       ld      a,$07       ; else A := 7 = code for 3+ items, awards 800 points
3EC2: C9          ret                 ; return

; subroutine called from #3EA7 above
; checks for mario jumping over barrels or fires
; H is preloaded with either 5 or #13 (19 decimal) for the area under mario ?
; C is preloaded with mario's Y position + #C (12 decimal)
; IX preloaded with start of array for fires or barrels, EG #6700 or #6400
; L is preloaded with height window value ?
; DE is preloaded with offset to add for next sprite

3EC3: DD CB 00 46 bit     0,(ix+$00)  ; is this barrel/fire active?
3EC7: CA FA 3E    jp      z,$3efa     ; no, jump ahead to try next one

3ECA: 79          ld      a,c         ; load A with mario's adjusted Y position
3ECB: DD 96 05    sub     (ix+$05)    ; subtract the fire/barrel Y position.  did the result go negative?
3ECE: D2 D3 3E    jp      nc,$3ed3    ; no, skip next step

3ED1: ED 44       neg                 ; Negate A (A := 0 - A)

3ED3: 3C          inc     a           ; increment A
3ED4: 95          sub     l           ; subtract L (height window?)  Is there a carry ?
3ED5: DA DE 3E    jp      c,$3ede     ; yes, skip next two steps

3ED8: DD 96 0A    sub     (ix+$0a)    ; else subtract the items' height???
3EDB: D2 FA 3E    jp      nc,$3efa    ; if out of range, jump ahead to try next one

; we are within the Y range, test X range next

3EDE: FD 7E 03    ld      a,(iy+$03)  ; load A with mario's X position
3EE1: DD 96 03    sub     (ix+$03)    ; subtract the item's X position
3EE4: D2 E9 3E    jp      nc,$3ee9    ; if no carry, skip next step

3EE7: ED 44       neg                 ; negate A

3EE9: 94          sub     h           ; subtract the horizontal window (5 or 19 pixels)
3EEA: DA F3 3E    jp      c,$3ef3     ; if out of range, skip next 2 steps

3EED: DD 96 09    sub     (ix+$09)    ; subtract the item's width???
3EF0: D2 FA 3E    jp      nc,$3efa    ; if out of range, skip ahead to try next one

; item was jumped

3EF3: 3A 60 60    ld      a,(numobstaclesjumped_6060) ; load A with counter of how many barrels/fires jumped
3EF6: 3C          inc     a           ; increase it
3EF7: 32 60 60    ld      (numobstaclesjumped_6060),a; store

3EFA: DD 19       add     ix,de       ; add offset for next barrel or fire
3EFC: 10 C5       djnz    $3ec3       ; Next B

3EFE: C9          ret                 ; return

; ... overwrites the message from game creators...

3EFF:  00
3F00:  5C 76 49 4A 01 09 08 01 3F 7D 77 1E 19 1E 24 15  .(C)1981...NINTE
3F10:  1E 14 1F 10 1F 16 10 11 1D 15 22 19 13 11 10 19  NDO.OF.AMERICA.I
3F20:  1E 13 2B 3F                                      NC..

; called from #081C : patch to draw the TM logo on attract screen

3F24: 21 AF 74    ld      hl,$74af    ; load HL with screen VRAM address
3F27: 11 E0 FF    ld      de,$ffe0    ; load offset
3F2A: 36 9F       ld      (hl),$9f    ; draw first part of TM logo to screen
3F2C: 19          add     hl,de       ; next screen location
3F2D: 36 9E       ld      (hl),$9e    ; draw second part of TM logo to screen
3F2F: C9          ret                 ; return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Original Dkong code, taken from mame set dkongj
;
;3F00:  43 4F 4E 47 52 41 54 55 4C 41 54 49 4F 4E 20 21  CONGRATULATION !
;3F10:  49 46 20 59 4F 55 20 41 4E 41 4C 59 53 45 20 20  IF YOU ANALYSE
;3F20:  44 49 46 46 49 43 55 4C 54 20 54 48 49 53 20 20  DIFFICULT THIS
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


3F30:  50 52 4F 47 52 41 4D 2C 57 45 20 57 4F 55 4C 44  ;PROGRAM,WE WOULD
3F40:  20 54 45 41 43 48 20 59 4F 55 2E 2A 2A 2A 2A 2A  ; TEACH YOU.*****
3F50:  54 45 4C 2E 54 4F 4B 59 4F 2D 4A 41 50 41 4E 20  ;TEL.TOKYO-JAPAN
3F60:  30 34 34 28 32 34 34 29 32 31 35 31 20 20 20 20  ;044(244)2151
3F70:  45 58 54 45 4E 54 49 4F 4E 20 33 30 34 20 20 20  ;EXTENTION 304
3F80:  53 59 53 54 45 4D 20 44 45 53 49 47 4E 20 20 20  ;SYSTEM DESIGN
3F90:  49 4B 45 47 41 4D 49 20 43 4F 2E 20 4C 49 4D 2E  ;IKEGAMI CO. LIM.


; jump here from #0CD1
; a patch ?

3FA0: CD A6 3F    call    $3fa6       ; call sub below
3FA3: C3 5F 0D    jp      $0d5f       ; return to program [this was original line wiped by patch ?]

; called from #3FA0 above

3FA6: 3E 02       ld      a,$02       ; A := 2
3FA8: F7          rst     $30         ; check to see if the level is pie factory.  If not, RET to #3FA3 [then jump to #0D5F]

3FA9: 06 02       ld      b,$02       ; for B = 1 to 2
3FAB: 21 6C 77    ld      hl,$776c    ; load HL with video RAM address for top rectractable ladder

3FAE: 36 10       ld      (hl),$10    ; clear the top of the ladder
3FB0: 23          inc     hl
3FB1: 23          inc     hl          ; next address
3FB2: 36 C0       ld      (hl),$c0    ; draw a ladder 2 rows down
3FB4: 21 8C 74    ld      hl,$748c    ; set HL for next loop - does the other side of the screen ; [sloppy?  this instruction not needed on 2nd loop]
3FB7: 10 F5       djnz    $3fae       ; Next B

3FB9: C9          ret                 ; return [to #3FA3, then jump to #0D5F]

3FBA:  00 00 00 00 00 00                ; unused

; called from #2285
; [seems like a patch ? - resets mario sprite when ladder descends]

3FC0: 21 4D 69    ld      hl,mario_sprite_value_694d    ; load HL with mario sprite value
3FC3: 36 03       ld      (hl),$03    ; store 3 = mario on ladder with left hand up
3FC5: 2C          inc     l
3FC6: 2C          inc     l           ; HL := #694F = mario sprite Y value
3FC7: C9          ret                 ; return

; unknown
; unused ???

3FC8:  00 00 41 7F 7F 41 00 00
3FD0:  00 7F 7F 18 3C 76 63 41
3FD8:  00 00 7F 7F 49 49 49 41
3FE0:  00 1C 3E 63 41 49 79 79
3FE8:  00 7C 7E 13 11 13 7E 7C
3FF0:  00 7F 7F 0E 1C 0E 7F 7F
3FF8:  00 00 41 7F 7F 41 00 00



;0000 0000 0100 0001 0111 1111 0111 1111 0100 0001 0000 0000 0000 0000
;0111 1111 0111 1111 0001 1000 0011 1100 0111 0110 0110 0011 0100 0001
;0000 0000 0111 1111 0111 1111 0100 1001 0100 1001 0100 1001 0100 0001
;0001 1100 0011 1110 0110 0011 0100 0001 0100 1001 0111 1001 0111 1001
;0111 1100
;
;
;
;
;
;
;
;
;http://www.brasington.org/arcade/tech/dk/
;
;
;
;
;Function Chip Type 2-Board location 4-Board location
;Color Maps 256x4 prom 2E (CPU) 2K (CPU)
;Color Maps 256x4 prom 2F (CPU) 2J (CPU)
;Character Colors 256x4 prom 2N (VIDEO) 5F (VIDEO)
;Fixed Characters 2716 3N (VIDEO) 5H (VIDEO)
;Fixed Characters 2716 3P (VIDEO) 5K (VIDEO)
;Code 0x3000-0x3fff 2532 5A (CPU) 5K (CPU)
;Code 0x2000-0x2fff 2532 5B (CPU) 5H (CPU)
;Code 0x1000-0x1Fff 2532 5C (CPU) 5G (CPU)
;Code 0x0000-0x0Fff 2532 5E (CPU) 5F (CPU)
;Not used - vacant     5L (CPU)
;Moving Objects 2716 7C (VIDEO) 4M (CLK)
;Moving Objects 2716 7D (VIDEO) 4N (CLK)
;Moving Objects 2716 7E (VIDEO) 4R (CLK)
;Moving Objects 2716 7F (VIDEO) 4S (CLK)
;Digital Sound 2716 3F (CPU) 3J (SOU)
;Digital Sound 2716 3H (CPU) 3I (SOU)
;Z80 CPU  Z80 7C (CPU) 5C (CPU)
;8035 MPU (music) 8035 7H (CPU) 3H (SOU)
;CPU RAM 2114 3A (CPU) XX (CPU)
;CPU RAM 2114 4A (CPU) XX (CPU)
;CPU RAM 2114 3B (CPU) XX (CPU)
;CPU RAM 2114 4B (CPU) XX (CPU)
;CPU RAM 2114 3C (CPU) XX (CPU)
;CPU RAM 2114 4C (CPU) XX (CPU)
;Character RAM 2114 2P (VIDEO) XX (VIDEO)
;Character RAM 2114 2R (VIDEO) XX (VIDEO)
;Object RAM 2148 6P (VIDEO) XX (VIDEO)
;Object RAM 2148 6R (VIDEO) XX (VIDEO)



3D08:  05 88 77 01 68 77 01 6C 77 03 49 77              ; D
3D14:  05 08 77 01 E8 76 01 EC 76 05 C8 76              ; O
3D20:  05 88 76 02 69 76 02 4A 76 05 28 76              ; N
3D2C:  05 E8 75 01 CA 75 03 A9 75 01 88 75 01 8C 75     ; K
3D3B:  05 48 75 01 28 75 01 2A 75                       ; E (part 1)
3D44:  01 2C 75 01 08 75 01 0A 75 01 0C 75              ; E (part 2)
3D50:  03 C8 74 03 AA 74 03 88 74                       ; Y
3D59:  05 2F 77 05 0F 77 02 F0 76 02 CF 76 02 D2 76     ; K
3D68:  05 8F 76 05 6F 76 01 4F 76 01 53 76 05 2F 76     ; O
3D77:  05 EF 75 02 D0 75 02 B1 75 05 8F 75              ; N
3D83:  03 50 75 05 2F 75 01 0F 75 01 13 75              ; G (part 1)
3D8F:  01 EF 74 01 F1 74 01 F3 74 02 D1 74              ; G (part 2)
3D9B:  00                                               ; end code



;change to konkey dong:

3D08:  05 0F 77 01 EF 76 01 F3 76 03 D0 76              ; D transposed to where K is

3D59:  05 2F 77 05 88 77 02 69 77 02 48 77 02 4B 77     ; K transposed to where D is


;:dkong:20500000:3D66:00004B77:0000FFFF:konkey dong
;:dkong:20710000:3D61:77024877:FFFFFFFF:konkey dong (2/6)
;:dkong:20710000:3D5D:88770269:FFFFFFFF:konkey dong (3/6)
;:dkong:20510000:3D12:0000D076:00FFFFFF:konkey dong (4/6)
;:dkong:20710000:3D0D:7601F376:FFFFFFFF:konkey dong (5/6)
;:dkong:20710000:3D09:0F7701EF:FFFFFFFF:konkey dong (6/6)

c_5At_g.bin:

0D09: 0F 77 01 EF 76 01 F3 76 03 D0 76
0D6D: 88 77 02 69 77 02 48 77 02 4B 77
