		processor 6502

video	equ 7680
vcolor	equ 38400
off		equ 22*7+4
boardsize	equ 16*12-3
boardstart	equ 3*16+3
maxdepth	equ	4
scoreImpossible	equ -100
scoreRow2	equ 1
scoreRow3 	equ 5
scoreRow4 	equ 21


		; variables in zero page
		seg.u zpvars
		org 0
row			ds 1
column		ds 1
color		ds 1  ; 0 (empty), 1 (human), 2 (cpu)
manstart	ds 1
freerow		ds 7  ; free row for each column (0..5, or -1 for full)
clrs		ds 3
depth		ds 1
score		ds 1
score2		ds 1
tmp1		ds 1
i			ds 1
colscores	ds 7

;
zplimit

		IF zplimit > 144
			ERR
		ENDIF


		seg.u tapebuffer
		org 828
board		ds boardsize


		mac getptr
			lda row
			clc
			rol
			rol
			rol
			rol
			adc column
			adc #boardstart
			tax
		endm


		seg code
		org 4097
		byte 11,16,10,0,158,"4","1","0","9",0,0,0  ; 10 SYS4109

start

		ldx #255
		txs

		jsr initvars
		jsr clearscreen

; draw all the board

		lda #5
		sta row
loopR
		lda #6
		sta column
loopC
		jsr drawSlot
		dec column
		bpl loopC
		dec row
		bpl loopR

; user's turn

userturn


; get key pressed
waitkey	jsr $ffe4
		cmp #0
		beq waitkey

		cmp #49
		bmi wrongkey
		cmp #56
		bpl wrongkey
		sec
		sbc #49
		sta column
		tax
		lda freerow,x
		sta row
		bmi wrongkey
		getptr
		lda #1
		sta board,x
		ldx column
		dec freerow,x
		jsr drawSlot
		jmp cputurn
wrongkey
		lda 36879
		eor #7
		sta 36879
		ldx #32
		jsr delay
		lda 36879
		eor #7
		sta 36879
		jmp userturn




cputurn
		; compute move
		SUBROUTINE
		lda #maxdepth
		sta depth
		lda #6
		sta column
loopcol
		lda #2
		sta color
		jsr recursion
		ldx column
		lda score
		sta colscores,x
		dec column
		bpl loopcol

		; compute max
		lda colscores
		sta tmp1
		ldx #6
.loop1	lda colscores,x
		cmp tmp1
		bmi .l2
		sta tmp1
.l2		dex
		bpl .loop1
		; pick a column == max
		ldx #6
.loop2	lda colscores,x
		cmp tmp1
		bne .l3
		stx column
.l3		dex
		bpl .loop2

		ldx column
		lda freerow,x
		sta row

		getptr
		lda #2
		sta board,x
		ldx column
		dec freerow,x
		jsr drawSlot


		jmp userturn


		jmp hang



; ----------------------------------------------------------------------


recursion
		SUBROUTINE
		ldx column
		lda freerow,x
		sta row
		bpl .l1
		lda  #scoreImpossible
		sta score
		rts
.l1
		getptr
		lda color
		sta board,x
		ldx column
		dec freerow,x
		jsr computescore
		lda score
		cmp #scoreRow4
		bne .l2
		clc
		adc depth
		sta score
.l2		lda depth
		cmp #1
		beq .end
		lda score
		cmp scoreRow4
		bpl .end
		lda #scoreImpossible
		sta score2
		lda #6
		sta i
.loopcol
		; recursion
		; save local variables
		lda row
		pha
		lda column
		pha
		lda color
		pha
		lda score
		pha
		lda score2
		pha
		lda depth
		pha
		lda i
		pha
		; call recursion
		lda i
		sta column
		dec depth
		lda #3
		clc
		sbc color
		sta color
		jsr recursion
		lda score
		sta tmp1
		; restore local variables
		pla
		sta i
		pla
		sta depth
		pla
		sta score2
		pla
		sta score
		pla
		sta color
		pla
		sta column
		pla
		sta row

		lda score2
		cmp tmp1
		bpl .l3
		lda tmp1
		sta score2
.l3		dec i
		bpl .loopcol

		lda score2
		cmp #scoreImpossible
		beq .end
		cmp #scoreRow4
		bmi .l4
		lda score2
		bpl .l4
		;bxxxx  ; TODO, signed comparison
		lda #0
		sec
		sbc score2  ; -score2, positive
		cmp #scoreRow4
		bmi .l4
		sta score  ; score = -score2
		jmp .end
.l4		lda score
		sec
		sbc score2
		sta score
.end
		getptr
		lda #0
		sta board,x
		ldx column
		inc freerow,x
		rts


; ----------------------------------------------------------------------

computescore
		SUBROUTINE
		lda #scoreImpossible
		sta score
		rts
		; TODO
		lda #0
		sta score
		sta score2
		lda row
		pha
		lda column
		pha
		; horizontal
		lda column
		sec
		sbc #3
		sta column
		lda #1
		sta incr
		jsr computesequencesub
		lda maxgroup
		cmp #4
		bne .l1a
		lda #scoreRow4
		sta score
		jmp end
.l1a	cmp #3
		bne .l2a
		lda score2
		clc
		adc #scoreRow3
		sta score2
.l2a	cmp #2
		bne .l3a
		lda score
		clc
		adc #scoreRow2
		sta score
.l3a

.end
		pla
		sta column
		pla
		sta row
		rts


; ----------------------------------------------------------------------

drawSlot
		SUBROUTINE
		; input: row, column
		getptr
		lda board,x
		tax
		lda clrs,x
		sta color
		lda #0
		clc
		ldx row
.draw1
		beq .draw1a
		adc #44
		dex
		jmp .draw1
.draw1a	ldx column
.draw2	beq .drawOk
		adc #2
		dex
		jmp .draw2
.drawOk	tay
		lda #85
		sta video+off,y
		lda color
		sta vcolor+off,y
		iny
		lda #73
		sta video+off,y
		lda color
		sta vcolor+off,y
		tya
		adc #21
		tay
		lda #74
		sta video+off,y
		lda color
		sta vcolor+off,y
		iny
		lda #75
		sta video+off,y
		lda color
		sta vcolor+off,y
		rts


; ----------------------------------------------------------------------

delay
		SUBROUTINE
		; input : x
.loop1	ldy #255
.loop2	dey
		bne .loop2
		dex
		bne .loop1
		rts


; ----------------------------------------------------------------------

clearscreen
		SUBROUTINE
;  space character
		lda #32

		ldy #253
.loop1	dey
		sta video,y
		bne .loop1

		ldy #253
.loop2	dey
		sta video+253,y
		bne .loop2

; color
		lda #5

		ldy #253
.loop3	dey
		sta vcolor,y
		bne .loop3

		ldy #253
.loop4	dey
		sta vcolor+253,y
		bne .loop4
		rts


; ----------------------------------------------------------------------

initvars
		SUBROUTINE
		clc
		lda #1
		sta manstart
		lda #0  ; black
		sta clrs
		lda #2  ; red
		sta clrs+1
		lda #7  ; yellow
		sta clrs+2

		; setup board
		lda #$ff
		ldy #boardsize
.loop1	dey
		sta board,y
		bne .loop1
		; inner, actual slots
		ldx #boardstart
		lda #6
		sta row
.loop3	ldy #7
		lda #0
.loop4	sta board,x
		inx
		dey
		bne .loop4
		txa
		adc #9
		tax
		dec row
		bne .loop3
		; init freerow
		lda #5
		ldy #7
.loop5	dey
		sta freerow,y
		bne .loop5

		rts


hang	jmp hang

