
	* I think only 77 are used (last one is score sprite)
	NB_HARDWARE_SPRITES = 78

	NB_BARRELS = 10		| normal value is 10, use less to test
	NB_FIRES = 2		| normal value is 5, use less to test
	NB_PIES = 6			| normal value is 6, use less to test
	
***    
*** BUILD OPTIONS
***

	.ifdef	RELEASE
    OPT_DISABLE_BG_LAYER=0            | LEAVE AT 0!!!
    OPT_DISABLE_SPRITES=0             | LEAVE AT 0!!!
    OPT_LEAVE_RIVETS=0                 | LEAVE AT 0!!!
    OPT_START_SCORE=0                 | LEAVE AT 0!!!
	OPT_SKIP_INTRO_SCREEN=0           | LEAVE AT 0!!!
	OPT_SKIP_GAME_DEMO=0              | LEAVE AT 0!!!
	OPT_START_WITH_CONVEYORS=0			| LEAVE AT 0!!!
	OPT_START_WITH_ELEVATORS=0			| LEAVE AT 0!!!
	OPT_START_LEVEL=1              | LEAVE AT 1!!!
	OPT_START_SCREEN=1              | LEAVE AT 1!!!

	NB_BARRELS = 10		| DON'T CHANGE!
	NB_FIRES = 5		| DON'T CHANGE!
	NB_PIES = 6			| DON'T CHANGE!

	.else

	NB_BARRELS = 10
	NB_FIRES = 2
	NB_PIES = 6
	* don't remove rivets, allows to chase fires more efficiently
    OPT_LEAVE_RIVETS=1
	
    * hardware options
    OPT_DISABLE_BG_LAYER=0
    OPT_DISABLE_SPRITES=0
   
	* permanent cheats/hacks to test game
    * score is BCD format
	* all options are zeroed for release
    OPT_START_SCORE=0x0
	OPT_SKIP_INTRO_SCREEN=0
	OPT_SKIP_GAME_DEMO=0
	OPT_START_LEVEL=1
	* 1: normal, 2, pie factory, 3: elevators, 4: rivets
	OPT_START_SCREEN=4

	.endif
	
***
*** end of BUILD OPTIONS
***




* sound ordinals



	.equ	BOOM_SND,                     0+0x10
	.equ	CREDIT_SND,                   1+0x10
	.equ	DEAD_SND,                     2+0x10
	.equ	JUMPED_OVER_SND,              3+0x10
	.equ	KILL_ENEMY_SND,               4+0x10
	.equ	START_SND,                    5+0x10
	.equ	JUMPING_SND,                  6+0x10
	.equ	WALKING_SND,                  7+0x10
	.equ	BOUNCER_SND,                  8+0x10



    
