	.include "custom.i"

* how to use in double buffering mode with a "drawn" and a "displayed" buffer
*
* - set OPT_BLIT_CHAIN_MODE to 0 or 1: 0 classic blit+waitblit, 1 blit in interrupts
* - replace all blit writes by WRITE_BLITTER_REG_xxx macros. When writing bltsize
*   use WRITE_BLITTER_REG_SIZE instead of WRITE_BLITTER_REG_WORD
*
* mode 0: classic mode. WAIT_BLIT is active, all operations are synchronous so
* in vblank (top of frame) or copper interrupt (set at bottom of frame):
* - blit in "drawn" buffer 
* - switch buffer pointers
* - show "displayed" buffer in copperlist
*
* mode 1: with blitter interrupt chain.
* - use DECL_BLITLISTS with an arbitrary size. Error will trigger if too small
* - setup level 1 interrupt at end of copperlist (instead of copper interrupt)
*   so it can be interrupted by blitter
* - setup level 3 interrupt with vblank and blitter (copper isn't useful)
* - on level 1 interrupt:
*   - call NEW_BLITLIST
*   - set bitplanes
*   - switch screen pointers (note the reversed order vs synchronous mode!)
*   - call PROCESS_BLITS to process the previous blits
*   - call the routine to perform the "blits" (fake blits now, fills filled_blitter_list instead)
*   - call COMMIT_BLITLIST to end the list (by setting -2 in it)
*
*   that's it. PROCESS_BLITS started the chain reaction, and there are not blitwaits
*   anymore in the code
*
*   In most games, for memory considerations, we use in-place mirroring, so no problem with
*   option 0. But option 1 needs more work. So we introduce a new virtual blitter command if OPT_VBLIT_MIRROR_MODE=1
*   in the WRITE_VIRTUAL_MIRROR_COMMAND, mirror_function expects the bitplane data in A2 and the height minus 1 in D1
*
*   Game that scroll and that can't use dual playfield for sprites also need a command to store the current scroll value
*   else if the screen moves a lot, the scroll offset added to the bobs doesn't match the current scroll offset
*
*   it's however ideal on games that need a lot of blitting and exclusively use
*   static source data. Interleaved mode would trigger less interrupts too.
*
*   most macros do nothing in mode 0, so it allows to lay them out and compare speed
*   with mode 0 or 1 without changing the code
*   only the screen switch order and location changes (in double buffered mode, if
*   you race the beam, there's nothing to do)
*
*
* the 4 variables to configure, here or in your main code
* values 0/1
*
*OPT_BLIT_CHAIN_MODE = 0
*OPT_VBLIT_SCROLL_MODE = 0
*OPT_VBLIT_MIRROR_MODE = 0
*OPT_BLIT_WAIT_DEBUG = 0


******************
* blitter macros *
******************

*DEBUG_BLIT_WAIT = 1

	.macro	CHECK_A5_IS_CUSTOM
	.ifndef	RELEASE
	cmp.l	#_custom,a5
	jeq		s0\@
	BREAKPOINT	"custom should be set in A5"
s0\@:
	.endif		
	.endm



********************
* classic handling *
********************

	.if		OPT_BLIT_CHAIN_MODE==0
	
	.macro	REALLY_WAIT_BLIT
	CHECK_A5_IS_CUSTOM
	move.w	#0x8400,(dmacon,a5)		| blitter high priority
wait\@:
	BTST	#6,(dmaconr,a5)
	BNE.S	wait\@
	move.w	#0x0400,(dmacon,a5)		| blitter normal priority
	.endm
	
	.macro	WAIT_BLIT
	REALLY_WAIT_BLIT
	.endm
	
	.macro	NEW_BLITLIST
	.endm
	
	.macro	PROCESS_ONE_BLIT
	.endm
	
	.macro	PROCESS_BLITS
	.endm
	
	.macro	FORCE_PROCESS_BLITS
	.endm
	
	.macro	COMMIT_BLITLIST
	.endm
	
	.macro	WRITE_BLITTER_REG_LONG	value,offset
	CHECK_A5_IS_CUSTOM
	move.l	\value,\offset(a5)
	.endm
	.macro	WRITE_BLITTER_REG_WORD	value,offset
	CHECK_A5_IS_CUSTOM
	move.w	\value,\offset(a5)
	.endm
	.macro	WRITE_BLITTER_REG_SIZE	value
	WRITE_BLITTER_REG_WORD	\value,bltsize
	.endm
	
	.if		OPT_VBLIT_MIRROR_MODE==1
	.macro	WRITE_BLITTER_VIRTUAL_MIRROR	height,mirror_function,bitplane
	move.w	\height,d1		| height
	subq	#1,d1		| minus one for dbf
	jsr		(\mirror_function)	  | in: A2 bitplane (parameter is ignored it is already a2), D1: height-1
	.endm
	.endif
	
	.if		OPT_VBLIT_SCROLL_MODE==1
	.macro	WRITE_BLITTER_SCROLL_VALUES	scroll_x,scroll_y
	* the blits are synchronous, the scrolling is updated at the same time
	move.l	\scroll_x,blitter_scroll_x
	move.w	\scroll_y,blitter_scroll_y
	.endm
	.endif
	
	* no blitlists, empty
	.macro	DECL_BLITLISTS	size
	.endm
	
	.endif
	
******************
* queue handling *
******************

	.if		OPT_BLIT_CHAIN_MODE==1
	.macro	WAIT_BLIT
	* do nothing!
	.endm
	
	.macro	REALLY_WAIT_BLIT
	.if	OPT_BLIT_WAIT_DEBUG
sw\@:
	* if blitter isn't finished, then we wait
	* this is called from level 1 interrupt so
	* blitter interrupts can interrupt
	tst.b	blitter_chain_running
	jeq		snw\@
	COLOR0_FLASH	0xF00
	jra		sw\@
snw\@:
	.else
sw\@:
	* if blitter isn't finished, then we wait
	* this is called from level 1 interrupt so
	* blitter interrupts can interrupt
	tst.b	blitter_chain_running
	jne		sw\@	
	.endif
	.endm
	
	.macro	NEW_BLITLIST
	lea		blitter_list_1,a0
	lea		blitter_list_2,a1
	REALLY_WAIT_BLIT
	
	* blitter chain has completed: we can switch lists
	eor.b	#1,blitter_list_toggle
	jne		s0\@
	move.l	a1,drawn_blitter_list_ptr
	move.l	a0,filled_blitter_list_ptr
	jra		s1\@
s0\@:
	move.l	a0,drawn_blitter_list_ptr
	move.l	a1,filled_blitter_list_ptr
s1\@:
	.endm
	
	.macro	PROCESS_BLITS
	.ifndef	RELEASE
	tst.b	blitter_chain_running
	jeq		nob\@
	BREAKPOINT	"PROCESS_BLITS called while blitter chain is running"
nob\@:
	.endif
	tst.b	size_command_issued
	jeq		s\@		| empty list or no bltsize command in the current command list: skip
	* signal that the blitter chain is now running
	st.b	blitter_chain_running
	* start first blit from outside the blitter interrupt to
	* start the chain reaction reading from drawn_blitter_list_ptr
	* clear size command issued for next blitlist creation
	clr.b	size_command_issued
	.ifndef	RELEASE
	* cheap sanity check
	move.l	drawn_blitter_list_ptr,a0
	tst.w	(a0)
	jne		okay\@
	BREAKPOINT	"zero in drawn blitter list when starting blits" 
okay\@:
	.endif
	* turn off blitter interrupts to make sure that the first
	* blit is atomic and not interrupted by the blitter interrupt!
	move.w	#0x0040,(intena,a5)
	PROCESS_ONE_BLIT
	* turn on blitter interrupts again
	move.w	#0x8040,(intena,a5)
s\@:
	.endm

*	* we know that size_command_issued is set
*	.macro	FORCE_PROCESS_BLITS
*	* signal that the blitter chain is now running
*	st.b	blitter_chain_running
*	* start first blit from outside the blitter interrupt to
*	* start the chain reaction reading from drawn_blitter_list_ptr
*	* turn off blitter interrupts to make sure that the first
*	* blit is atomic and not interrupted by the blitter interrupt!
*	move.w	#0x0040,(intena,a5)
*	PROCESS_ONE_BLIT
*	* turn on blitter interrupts again
*	move.w	#0x8040,(intena,a5)
*	* clear size command issued for next blitlist creation
*	clr.b	size_command_issued
*	.endm

	.macro	DECL_BLITLISTS	size
blitter_scroll_x:
	.long	0
blitter_scroll_y:
	.word	0
drawn_blitter_list_ptr:
	.long	0
filled_blitter_list_ptr:
	.long	0
blitter_list_1:
	.word	-2
	.skip	\size
	.long	0xdeaddead
	.long	0xdeaddead
	.long	0xdeaddead
blitter_list_2:
	.word	-2
	.skip	\size
	.long	0xdeaddead
	.long	0xdeaddead
	.long	0xdeaddead
blitter_chain_running:
	.byte	0
size_command_issued:
	.byte	0
blitter_list_toggle:	
	.byte	0
	.align	2
	.endm
	
	.macro	CHECK_BLITTER_IDLE
	.ifndef RELEASE
	BTST	#6,(dmaconr,a5)
	jeq		idle\@
	BREAKPOINT	"PROCESS_ONE_BLIT called while blitter is busy!"
idle\@:
	.endif
	.endm
	
	.macro	COMMIT_BLITLIST
	* complete filled list
	move.l	filled_blitter_list_ptr,a0
	move.w	#-1,(a0)
	.endm

	.macro	PROCESS_ONE_BLIT

	* process blit command, first one (outside blitter int)
	* or others (inside blitter int)
	CHECK_A5_IS_CUSTOM
	
	move.l	drawn_blitter_list_ptr,a0
	* loop on commands until we find bltsize or end of command list
b0\@:
	move.w	(a0)+,d0		| blitter register
	jmi		b1\@			| end of list

	bclr	#14,d0
	jne		b2\@
	* word or virtual mirror command
	.if	OPT_VBLIT_MIRROR_MODE==1
	cmp.w	#deniseid,d0
	jne		nv0\@
	* mirror command
	movem.l	d0-d2/a0-a2,-(a7)
	lea		mirror_table,a1
	move.w	(a0)+,d1
	subq	#1,d1			| height minus one
	.ifndef	RELEASE
	jpl		pos\@
	BREAKPOINT	"zero height for mirror"
pos\@:
	.endif
	move.l	(a0)+,a2
	.ifndef	MC68020
	move.l	(a0),a0
	jsr		(a0)
	.else
	jsr		([a0])
	.endif
	movem.l	(a7)+,d0-d2/a0-a2
	add.w	#10,a0		| advance to next command
	jra		b0\@		| not size: continue parsing list
nv0\@:
	.endif
	.if		OPT_VBLIT_SCROLL_MODE==1
	cmp.w	#dsksync,d0
	jne		nv1\@
	* store scrolling command
	move.l	(a0)+,blitter_scroll_x
	move.w	(a0)+,blitter_scroll_y
	jra		b0\@		| not size: continue parsing list
nv1\@:
	.endif
	* word command, check bounds
	.ifndef	RELEASE
	cmp.w	#bltcon0,d0		| sanity check for commands!
	jcc		f1\@
f0\@:
	lea		(-2,a0),a1
	BREAKPOINT	"word command: not a blitter register (in A1)"
	illegal
f1\@:
	cmp.w	#deniseid,d0
	jcc		f0\@
	.endif
	
	* bit not set: word command
	move.w	(a0)+,d1		| word value
	CHECK_BLITTER_IDLE
	move.w	d1,(a5,d0.w)	| word blitter command
	cmp.w	#bltsize,d0
	jne		b0\@		| not size: continue parsing list
	jra		b3\@		| size: stop processing the list, let the blitter perform that blit
	* long write command
b2\@:
	.ifndef	RELEASE
	cmp.w	#bltcon0,d0		| sanity check for commands!
	jcc		g1\@
g0\@:
	BREAKPOINT	"long command: not a blitter register !!"
	illegal
g1\@:
	cmp.w	#deniseid,d0
	jcc		g0\@
	.endif


	* bit 14 set: long command
	move.l	(a0)+,d1		| long value

	CHECK_BLITTER_IDLE
	move.l	d1,(a5,d0.w)	| long blitter command
	jra		b0\@		| not size: continue parsing list
b1\@:
	* -1: end of list: nothing to do, we're done for that frame
	clr.b	blitter_chain_running
	jra		b4\@		| no need to update pointer, the list is done
b3\@:
	move.l	a0,drawn_blitter_list_ptr
b4\@:
	.endm
	
	.macro	LOAD_FILLED_LIST
	move.l	filled_blitter_list_ptr,a5
	.ifndef	RELEASE
	cmp.w	#0xdead,(a5)
	jne		c0\@
	BREAKPOINT	"Blitter list overflow"
c0\@:
	cmp.l	#0,a5
	jne		c1\@
	BREAKPOINT	"null pointer on blitter list"
c1\@:
	.endif
	.endm
	
	.macro	STORE_FILLED_LIST
	move.l	a5,filled_blitter_list_ptr
	.endm
	
	.if		OPT_VBLIT_MIRROR_MODE==1
	.macro	WRITE_BLITTER_VIRTUAL_MIRROR	height,mirror_function,bitplane
	move.l	a5,-(a7)
	LOAD_FILLED_LIST
	move.w	#deniseid,(a5)+		| fake custom reg,(a5)+
	move.w	\height,(a5)+
	move.l	\bitplane,(a5)+
	move.l	\mirror_function,(a5)+
	STORE_FILLED_LIST
	move.l	(a7)+,a5
	.endm
	.endif

	.if		OPT_VBLIT_SCROLL_MODE==1
	.macro	WRITE_BLITTER_SCROLL_VALUES	scroll_x,scroll_y
	move.l	a5,-(a7)
	LOAD_FILLED_LIST
	move.w	#dsksync,(a5)+		| fake custom reg,(a5)+
	move.l	\scroll_x,(a5)+		| here we adapted to long for convenience (HI/LO)
	move.w	\scroll_y,(a5)+
	STORE_FILLED_LIST
	move.l	(a7)+,a5
	.endm
	.endif

	.macro	WRITE_BLITTER_REG_LONG	value,offset
	move.l	a5,-(a7)
	move.w	d6,-(a7)
	LOAD_FILLED_LIST
	move.w	#\offset,d6
	bset	#14,d6		| bit set to tell it's a long command
	move.w 	d6,(a5)+
	move.w	(a7)+,d6
	move.l	\value,(a5)+
	STORE_FILLED_LIST
	move.l	(a7)+,a5
	.endm
	
	.macro	WRITE_BLITTER_REG_WORD	value,offset
	move.l	a5,-(a7)
	LOAD_FILLED_LIST
	.if	\offset==bltsize
	.error  "WRITE_BLITTER_REG_WORD doesn't accept bltsize arg, use WRITE_BLITTER_REG_SIZE"
	.endif
	move.w	#\offset,(a5)+
	move.w	\value,(a5)+
	STORE_FILLED_LIST
	move.l	(a7)+,a5
	.endm
	
	.macro	WRITE_BLITTER_REG_SIZE	value
	move.l	a5,-(a7)
	LOAD_FILLED_LIST
	move.w	#bltsize,(a5)+
	move.w	\value,(a5)+
	st.b	size_command_issued
	STORE_FILLED_LIST
	move.l	(a7)+,a5
	.endm
	.endif
	