
	* I think only 77 are used (last one is score sprite)
	NB_HARDWARE_SPRITES = 78
	
***    
*** BUILD OPTIONS
***

	.ifdef	RELEASE
    OPT_DISABLE_BG_LAYER=0            | LEAVE AT 0!!!
    OPT_DISABLE_SPRITES=0             | LEAVE AT 0!!!
    OPT_START_SCORE=0                 | LEAVE AT 0!!!
	OPT_SKIP_INTRO_SCREEN=0           | LEAVE AT 0!!!
	OPT_SKIP_GAME_DEMO=0              | LEAVE AT 0!!!
	OPT_START_WITH_CONVEYORS=0			| LEAVE AT 0!!!
	OPT_START_WITH_ELEVATORS=0			| LEAVE AT 0!!!
	OPT_START_LEVEL=1              | LEAVE AT 1!!!
	.else
	
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
	OPT_START_WITH_CONVEYORS=0
	OPT_START_WITH_ELEVATORS=1

	.endif
	
***
*** end of BUILD OPTIONS
***




* sound ordinals



	.equ	BOOM_SND,                     0
	.equ	CREDIT_SND,                          1
	.equ	DEAD_SND,                     2
	.equ	JUMPED_OVER_SND,                      3
	.equ	KILL_ENEMY_SND,               4
	.equ	START_SND,                      5



    
