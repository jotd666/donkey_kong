	.ifndef	BREAKPOINT_INCLUDED
BREAKPOINT_INCLUDED = 1

	.ifdef	RELEASE
	.macro	BREAKPOINT comment
	.endm

	.else
	.ifdef	__amiga__
LOG_BUFFER_SIZE = 0x80000
	* amiga specific
	.macro	BREAKPOINT comment
	move.l	a0,-(a7)
	lea		comment\@(pc),a0
	jbsr	osd_break
	move.l	(a7)+,a0
	jra		next\@
comment\@:
	.asciz	"\comment"
	.align	2
next\@:
	.endm
	.else
	.macro	BREAKPOINT comment
	.endm
	.endif
	
	.macro	INFINITE_LOOP
	.word	0x60FE
	.endm

	* to trace at some virtual PCs, insert this macro
	
	.macro	LOG_REGS	the_pc
	move.w	sr,-(a7)
	move.w	#0x\the_pc,-(a7)
	move.w	#0,-(a7)
	jbsr	osd_log_cpu
	addq.w	#4,a7
	move.w	(a7)+,sr
	.endm
	
	.macro	ENABLE_LOG_REGS
	moveq	#1,d6		| enable
	jbsr	osd_cpu_logging_control	
	.endm
	.macro	DISABLE_LOG_REGS
	moveq	#0,d6		| disable
	jbsr	osd_cpu_logging_control	
	.endm	
	.endif
	
	.endif  | BREAKPOINT_INCLUDED
	