	.include "custom.i"

	
* how to use in double buffering mode with a "drawn" and a "displayed" buffer
*
* - set OPT_BLITTER_MODE to 0 or 1: 0 classic blit+waitblit, 1 blit in interrupts
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
* - on level 3 (blitter) interrupt:
*   - ack blitter interrupt
*   - call PROCESS_ONE_BLIT to process next blit
*
*   that's it. PROCESS_BLITS started the chain reaction, and there are not blitwaits
*   anymore in the code
*
*   this can be used only if there isn't in-place mirroring. The code has been developed
*   for a test on US Champ VBall but cannot apply here else there isn't enough memory
*   to store all static frames, so we use in-place mirroring, which only works with
*   option 0. If used anyway, there will be strange artifacts because of concurrent
*   mirroring with CPU & blitting at times.
*
*   it's however ideal on games that need a lot of blitting and exclusively use
*   static source data. Interleaved mode would trigger less interrupts too.
*
*   most macros do nothing in mode 0, so it allows to lay them out and compare speed
*   with mode 0 or 1 without changing the code
*   only the screen switch order and location changes (in double buffered mode, if
*   you race the beam, there's nothing to do)
*
******************
* blitter macros *
******************

	.macro	CHECK_A5_IS_CUSTOM
	.ifndef	RELEASE
	cmp.l	#_custom,a5
	jeq		s0\@
	BREAKPOINT	"custom should be set in A5"
s0\@:
	.endif		
	.endm

	.macro	REALLY_WAIT_BLIT
	CHECK_A5_IS_CUSTOM
	move.w	#0x8400,(dmacon,a5)		| blitter high priority
wait\@:
	BTST	#6,(dmaconr,a5)
	BNE.S	wait\@
	move.w	#0x0400,(dmacon,a5)		| blitter normal priority
	.endm


********************
* classic handling *
********************

	.if		OPT_BLITTER_MODE==0
	.macro	WAIT_BLIT
	REALLY_WAIT_BLIT
	.endm
	
	.macro	NEW_BLITLIST
	.endm
	
	.macro	PROCESS_ONE_BLIT
	.endm
	
	.macro	PROCESS_BLITS
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
	
	.macro	DECL_BLITLISTS	size
	.endm
	
	.endif
	
******************
* queue handling *
******************

	.if		OPT_BLITTER_MODE==1
	.macro	WAIT_BLIT
	* do nothing!
	.endm
	
	.macro	NEW_BLITLIST
sw\@:
	* if blitter isn't finished, then we wait
	* this is called from level 1 interrupt so
	* blitter interrupts can interrupt
	lea		blitter_list_1,a0
	lea		blitter_list_2,a1


	tst.b	blitter_chain_running
	jne		sw\@


	* blitter chain has completed: we can switch lists
	cmp.l	drawn_blitter_list_start,a0
	jeq		s0\@
	move.l	a0,drawn_blitter_list_start
	move.l	a0,drawn_blitter_list_ptr
	move.l	a1,filled_blitter_list_ptr
	jra		s1\@
s0\@:
	move.l	a1,drawn_blitter_list_start
	move.l	a1,drawn_blitter_list_ptr
	move.l	a0,filled_blitter_list_ptr
s1\@:
	.endm
	
	.macro	PROCESS_BLITS
	tst.b	size_command_issued
	jeq		s\@		| empty list or no bltsize command in the current command list: skip
	* signal that the blitter chain is now running
	st.b	blitter_chain_running
	* start first blit from outside the blitter interrupt to
	* start the chain reaction reading from drawn_blitter_list_ptr
	PROCESS_ONE_BLIT
s\@:
	* clear size command issued for next blitlist creation
	clr.b	size_command_issued
	.endm

	.macro	DECL_BLITLISTS	size
drawn_blitter_list_start:	
	.long	0
drawn_blitter_list_ptr:
	.long	0
filled_blitter_list_ptr:
	.long	0
blitter_list_1:
	.word	-2
	.skip	\size
	.long	0xdeaddead
	.long	0xdeaddead
blitter_list_2:
	.word	-2
	.skip	\size
	.long	0xdeaddead
	.long	0xdeaddead
blitter_chain_running:
	.byte	0
size_command_issued:
	.byte	0
	.endm
	
	.macro	COMMIT_BLITLIST
	* complete filled list
	move.l	filled_blitter_list_ptr,a0
	move.w	#0xFFFE,(a0)
	.endm

	.macro	PROCESS_ONE_BLIT
	* process blit command, first one (outside blitter int)
	* or others (inside blitter int)
	CHECK_A5_IS_CUSTOM
	move.l	drawn_blitter_list_ptr,a0

	move.w	#-1,d2
b0\@:
	move.w	(a0)+,d0		| blitter register
	jmi		b1\@			| end of command or end of list

	bclr	#14,d0
	jne		b2\@

	.ifndef	RELEASE
	cmp.w	#bltcon0,d0		| sanity check for commands!
	jcc		f1\@
f0\@:
	lea		(-2,a0),a1
	move.l		drawn_blitter_list_start,a2
	BREAKPOINT	"word command: not a blitter register (in A1), start in A2!!"
	illegal
f1\@:
	cmp.w	#deniseid,d0
	jcc		f0\@
	.endif
	
	* bit not set: word command
	move.w	(a0)+,d1		| word value
	
	
	move.w	d1,(a5,d0.w)
	jra		b0\@		| not size: continue parsing list
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

	
	move.l	d1,(a5,d0.w)
	jra		b0\@		| not size: continue parsing list
b1\@:
	cmp.w	d2,d0
	jeq		b3\@		| -1: end of command
	* -2: end of list: nothing to do, we're done for that frame
	clr.b	blitter_chain_running
b3\@:
	move.l	a0,drawn_blitter_list_ptr
	.endm
	
	.macro	LOAD_FILLED_LIST
	move.l	filled_blitter_list_ptr,a5
	.ifndef	RELEASE
	cmp.w	#0xdead,(a5)
	jne		c0\@
	BREAKPOINT	"Blitter list overflow"
c0\@:
	.endif
	.endm
	
	.macro	STORE_FILLED_LIST
	move.l	a5,filled_blitter_list_ptr
	.endm
	
	.macro	WRITE_BLITTER_REG_LONG	value,offset
	move.l	a5,-(a7)
	move.w	d6,-(a7)
	LOAD_FILLED_LIST
	move.w	#\offset,d6
	bset	#14,d6
	move.w 	d6,(a5)+
	move.l	\value,(a5)+
	STORE_FILLED_LIST
	move.w	(a7)+,d6
	move.l	(a7)+,a5
	.endm
	
	.macro	WRITE_BLITTER_REG_WORD	value,offset
	move.l	a5,-(a7)
	move.w	d6,-(a7)
	LOAD_FILLED_LIST
	move.w	#\offset,d6
	move.w 	d6,(a5)+
	move.w	\value,(a5)+
	STORE_FILLED_LIST
	move.w	(a7)+,d6
	move.l	(a7)+,a5
	.endm
	
	.macro	WRITE_BLITTER_REG_SIZE	value
	move.l	a5,-(a7)
	move.w	d6,-(a7)
	LOAD_FILLED_LIST
	move.w	#bltsize,d6
	move.w 	d6,(a5)+
	move.w	\value,(a5)+
	st.b	size_command_issued
	move.w	#-1,(a5)+		| end of command
	STORE_FILLED_LIST
	move.w	(a7)+,d6
	move.l	(a7)+,a5
	.endm
	.endif
	