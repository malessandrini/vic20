		processor 6502

; constants
video	equ 7680   ; video memory
vcolor	equ 38400  ; color memory
off		equ 22*7+4  ; offset for drawing board
boardsize	equ 16*12-3  ; memory size for board
boardstart	equ 3*16+3   ; actual start of board
maxdepth	equ	4  ; recursion depth (cpu-human-cpu-human)
scoreImpossible	equ -100
scoreRow2	equ 1
scoreRow3 	equ 5
scoreRow4 	equ 21
GETIN		equ $ffe4  ; kernal, read keyboard input


; variables in zero page
;
; we overwrite the Basic variable area, but leave kernal area untouched
; because the kernal is always executing through interrupts (e.g. keyboard
; reading). This gives us 144 bytes.

		seg.u zpvars
		org 0
row			ds 1
column		ds 1
color		ds 1  ; 0 (empty), 1 (human), 2 (cpu)
manstart	ds 1
freerow		ds 7  ; free row for each column (0..5, or -1 for full)
clrs		ds 3  ; color values for 0, 1, 2
depth		ds 1
score		ds 1
score2		ds 1
tmp1		ds 1
colscores	ds 7
maxgroup	ds 1
incr		ds 1
ptr			ds 1
tot			ds 1  ; number of moves
i			ds 1

;
zplimit
		; check safe limit of allocated area
		IF zplimit > 144
			ERR
		ENDIF


; memory area for board data (tape buffer area)
; board is allocated as 16*12 (6 rows, 7 columns, plus 3 guard positions at
; every side to compute sequences). 16 is to better multiplicate rows.
;
; ****************
; ****************
; ****************
; ***       ******
; ***       ******
; ***       ******
; ***       ******
; ***       ******
; ***       ******
; ****************
; ****************
; *************

		seg.u tapebuffer
		org 828
board		ds boardsize


		; macro to set x to correct offset in board, given row and column
		mac getptr  ; 16 * row + column + #boardstart
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


		; macro to set x and y to correct values to call printstring
		; warning: only works for the first 255 characters (due to offset in x)
		mac print  ; r, c, str
			ldx #22*{1}+{2}
			ldy #{3}-strings
			jsr printstring
		endm


; code area

		seg code
		org 4097

		; basic stub to launch binary program
		byte 11,16,10,0,158,"4","1","0","9",0,0,0  ; 10 SYS4109

start
		; we don't return to basic, so use the full stack
		ldx #255
		txs

		jsr initonce
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

		lda #3
		sta column  ; start position for arrow

; user's turn
userturn
		SUBROUTINE
		jsr drawarrow
; get key pressed
		jsr getchar

		cmp #$1d  ; right
		beq moveright
		cmp #$9d  ; left
		beq moveleft
		cmp #$11  ; down, use as left too
		beq moveleft
		cmp #$20  ; space
		beq setmove
		; if not one of the previous, must be a digit (1..7)
		cmp #49  ; '1'
		bmi userturn
		cmp #56  ; '8'
		bpl userturn
		sec
		sbc #49  ; convert to 0..6
		sta column
		jmp setmove
moveright
		lda column
		cmp #6
		beq userturn
		inc column
		jmp userturn
moveleft
		lda column
		beq userturn
		dec column
		jmp userturn
setmove
		ldx column
		lda freerow,x  ; free row for that column
		sta row
		bmi wrongcol  ; if row is negative, column is full
		getptr
		lda #1
		sta board,x  ; write 1 (human) in that position
		ldx column
		dec freerow,x  ; update freerow
		inc tot
		jsr drawSlot   ; draw new position

		jsr checkfinish
		bne cputurn
		jmp hang
wrongcol
		lda 36879
		eor #7
		sta 36879  ; flash border color
		ldx #32
		jsr delay
		lda 36879
		eor #7
		sta 36879
trampln	jmp userturn



; cpu's turn
cputurn
		SUBROUTINE
		; compute move, final effect is setting row, column
		jsr drawwait
		lda #maxdepth
		sta depth  ; recursion depth
		lda #6
		sta column  ; loop column from 6 to 0
.loopcol
		lda #2
		sta color  ; set color to 2 (cpu)
		jsr recursion  ; start recursive routine, output = score
		ldx column
		lda score
		sta colscores,x  ; set score of this column
		dec column
		bpl .loopcol

		; compute max of column scores
		lda colscores+6
		sta tmp1  ; start with last value
		ldx #5  ; loop through other values
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
		sta row  ; update mathing row

		getptr
		lda #2
		sta board,x  ; write 2 (cpu) in that position
		ldx column
		dec freerow,x  ; update freerow
		inc tot
		jsr drawarrow
		jsr drawSlot  ; draw new position

		jsr checkfinish
		bne trampln
		jmp hang



; ----------------------------------------------------------------------


recursion
		; input: column, depth, color (1 or 2)
		; output: score for that column
		; uses: row, color, depth, score, score2, tmp1
		SUBROUTINE
		ldx column
		lda freerow,x
		sta row  ; row matching this column
		bpl .l1
		lda  #scoreImpossible  ; if row negative, column is full
		sta score
		rts
.l1
		getptr
		lda color
		sta board,x  ; set position to color
		ldx column
		dec freerow,x  ; update freerow
		jsr computescore  ; compute score for this position
		jsr animatewait
		lda score
		cmp #scoreRow4
		bne .l2
		clc
		adc depth  ; if score is 4 in a row, add depth to prefer earlier ones
		sta score
		; if depth == 1 or score >= scoreRow4, return with this score
.l2		lda depth
		cmp #1
		beq .trampoline  ; -> .end
		lda score
		cmp scoreRow4
		bpl .trampoline  ; -> .end
		lda #scoreImpossible
		sta score2  ; init score2 with scoreImpossible
		ldy #6  ; iterate all columns to continue recursion
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
		tya
		pha
		; call recursion with new data
		sty column  ; current column
		dec depth  ; depth - 1
		lda #3
		sec
		sbc color
		sta color  ; color = 3 - color (switch 1, 2)
		jsr recursion
		lda score
		sta tmp1  ; temporarily save score from deeper recursion
		; restore local variables
		pla
		tay
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

		lda score2  ; update score2 if tmp1 (new score) > score2
		cmp tmp1
		bpl .l3
		lda tmp1
		sta score2
.l3		dey
		bpl .loopcol

		lda score2
		cmp #scoreImpossible
		beq .end  ; if new score is impossible, return current score
		; check if score >= scoreRow4 or <= -scoreRow4, in that case return -score2
		lda score2
		bmi .l3a  ; if score2 negative, test <=-scoreRow4
		cmp #scoreRow4
		bpl .l3b  ; first case
		jmp .l4  ; continue normally
.l3a	lda #0  ; compute -score2
		sec
		sbc score2  ; -score2
		cmp #scoreRow4
		bpl .l3b  ; second case
		jmp .l4  ; continue normally
.trampoline	jmp .end
.l3b
		; score = -score2, then return
		lda #0
		sec
		sbc score2  ; -score2
		sta score  ; score = -score2
		jmp .end
		; score -= score2
.l4		lda score
		sec
		sbc score2
		sta score
.end
		getptr
		lda #0
		sta board,x  ; restore empty position
		ldx column
		inc freerow,x  ; restore freerow
		rts


; ----------------------------------------------------------------------

computescore
		; input: row, column, color (1 or 2)
		; output: score for that position
		; uses: score2
		SUBROUTINE
		lda #0
		sta score   ; will contain score for sequences of 2
		sta score2  ; will contain score for sequences of 3
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
		jsr computesequencesub  ; compute maxgroup
		lda maxgroup
		cmp #4
		bne .l1a
		lda #scoreRow4
		sta score  ; if 4 in a row, don't try other directions
		jmp .end
.l1a	cmp #3  ; else if maxgroup==3, add its value to score2
		bne .l2a
		lda score2
		clc
		adc #scoreRow3
		sta score2
		jmp .l3a
.l2a	cmp #2  ; else if maxgroup==2, add its value to score
		bne .l3a
		lda score
		clc
		adc #scoreRow2
		sta score
.l3a
		; diagonal 1
		lda row
		sec
		sbc #3
		sta row
		lda #17
		sta incr
		jsr computesequencesub
		lda maxgroup
		cmp #4
		bne .l1b
		lda #scoreRow4
		sta score
		jmp .end
.l1b	cmp #3
		bne .l2b
		lda score2
		clc
		adc #scoreRow3
		sta score2
		jmp .l3b
.l2b	cmp #2
		bne .l3b
		lda score
		clc
		adc #scoreRow2
		sta score
.l3b
		; vertical
		lda column
		clc
		adc #3
		sta column
		lda #16
		sta incr
		jsr computesequencesub
		lda maxgroup
		cmp #4
		bne .l1c
		lda #scoreRow4
		sta score
		jmp .end
.l1c	cmp #3
		bne .l2c
		lda score2
		clc
		adc #scoreRow3
		sta score2
		jmp .l3c
.l2c	cmp #2
		bne .l3c
		lda score
		clc
		adc #scoreRow2
		sta score
.l3c
		; diagonal 2
		lda column
		clc
		adc #3
		sta column
		lda #15
		sta incr
		jsr computesequencesub
		lda maxgroup
		cmp #4
		bne .l1d
		lda #scoreRow4
		sta score
		jmp .end
.l1d	cmp #3
		bne .l2d
		lda score2
		clc
		adc #scoreRow3
		sta score2
		jmp .l3d
.l2d	cmp #2
		bne .l3d
		lda score
		clc
		adc #scoreRow2
		sta score
.l3d	; final: if score2 != 0, assign it to score
		lda score2
		beq .end
		sta score
.end
		pla
		sta column
		pla
		sta row
		rts


; ----------------------------------------------------------------------

computesequencesub
		; input: row, column, color (1 or 2), incr
		; output: maxgroup: max sequence of color and 0 for that position and direction
		; uses: tmp1, i
		SUBROUTINE
		lda #0
		sta maxgroup
		getptr
		stx ptr  ; save start position
		lda #3
		sta i  ; loop i: 3..0 (search for 4 sequences)
.loop1	lda #0
		sta tmp1
		ldx ptr  ; starting position
		ldy #3  ; loop y: 3..0 (search 4-position sequence)
.loop2	lda board,x
		cmp color  ; if position == color
		bne .l1
		inc tmp1
		jmp .l2
.l1		cmp #0  ; else if not 0 reset counter
		beq	.l2
		lda #0
		sta tmp1
		jmp .endl2  ; exit inner loop
.l2		txa
		clc
		adc incr
		tax  ; add incr to x

		dey
		bpl .loop2
.endl2
		lda tmp1
		cmp maxgroup
		bmi .l3
		sta maxgroup  ; if tmp1 > maxgroup, update maxgroup
.l3		lda maxgroup
		cmp #4
		bne .l4
		rts  ; if maxgroup == 4, return
.l4		lda ptr
		clc
		adc incr
		sta ptr  ; update start position

		dec i
		bpl .loop1
		rts


; ----------------------------------------------------------------------

checkfinish
		; input: row, column
		; output: Z=1 if finished
		; uses: color
		SUBROUTINE
		lda #1
		sta color
		jsr victory
		bne .l1
		lda #0
		rts
.l1		inc color
		jsr victory
		bne .l2
		lda #0
		rts
.l2		lda tot
		cmp #42  ; board full?
		bne .l3
		lda #0
		rts
.l3
		lda #1  ; Z = 0
		rts


; ----------------------------------------------------------------------

victory
		; input: row, column, color
		; output: Z=1 if victory
		SUBROUTINE
		jsr computescore
		lda score
		cmp #scoreRow4
		bpl .l1
		lda #1  ; Z = 0
		rts
.l1		lda #0
		rts


; ----------------------------------------------------------------------

drawSlot
		; input: row, column
		SUBROUTINE
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
		lda #0 ;#85
		sta video+off,y
		lda color
		ora #8  ; 4-color mode
		sta vcolor+off,y
		iny
		lda #1 ;#73
		sta video+off,y
		lda color
		ora #8
		sta vcolor+off,y
		tya
		adc #21
		tay
		lda #2 ;#74
		sta video+off,y
		lda color
		ora #8
		sta vcolor+off,y
		iny
		lda #3 ;#75
		sta video+off,y
		lda color
		ora #8
		sta vcolor+off,y
		rts


; ----------------------------------------------------------------------

drawarrow
		; input: column (negative for no arrow)
		SUBROUTINE
		; delete row
		lda #32+128
		ldx #0
		ldy #14
.l1		sta video+off-22,x
		inx
		dey
		bne .l1
		; draw arrow
		lda column
		clc
		rol  ; column*2
		tax
		lda #4
		sta video+off-22,x
		inx
		lda #5
		sta video+off-22,x
		rts


; ----------------------------------------------------------------------

drawwait
		SUBROUTINE
		lda #69+128
		ldx #0
		ldy #14
.l1		sta video+off-22,x
		inx
		eor #3
		dey
		bne .l1
		rts


; ----------------------------------------------------------------------

animatewait
		SUBROUTINE
		ldx #0
		ldy #14
.l1		lda video+off-22,x
		eor #3
		sta video+off-22,x
		inx
		dey
		bne .l1
		rts


; ----------------------------------------------------------------------

delay
		; input : x
		SUBROUTINE
.loop1	ldy #255
.loop2	dey
		bne .loop2
		dex
		bne .loop1
		rts


; ----------------------------------------------------------------------

getchar
		; output: A
		; empty keyboard buffer, than wait for new char
		SUBROUTINE
.l1		jsr GETIN
		cmp #0
		bne .l1
.l2		jsr GETIN
		cmp #0
		beq .l2
		rts


; ----------------------------------------------------------------------

clearscreen
		SUBROUTINE
;  space character
		lda #32+128

		ldy #253
.loop1	dey
		sta video,y
		bne .loop1

		ldy #253
.loop2	dey
		sta video+253,y
		bne .loop2

; color
		lda #6

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
		lda #0
		sta tot
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
		ldx #7
.loop5	dex
		sta freerow,x
		bne .loop5

		rts


; ----------------------------------------------------------------------

initonce
		SUBROUTINE
		; copy user defined chars to proper address
		ldx #[udcend-udcstart]
		ldy #0
.l1		lda udcstart,y
		sta 7168,y
		iny
		dex
		bne .l1
		; screen and border color
		lda #27
		sta 36879
		; auxiliary color (blue) for 4-color chars (high nibble) + audio volume (low nibble)
		lda #6*16
		sta 36878
		; disable shift+commodore character switch
		lda 657
		ora #128
		sta 657
		; activate user defined chars
		lda #255
		sta 36869
		; other variables
		lda #1
		sta manstart
		lda #1  ; white
		sta clrs
		lda #2  ; red
		sta clrs+1
		lda #7  ; yellow
		sta clrs+2
		rts


; ----------------------------------------------------------------------

hang	lda 36879
		eor #1
		sta 36879  ; border color
		jmp .


; ----------------------------------------------------------------------

strings
strhello	dc 8+128, 5+128, 12+128, 12+128, 15+128, 4, 5, 0
			dc 0


; ----------------------------------------------------------------------

printstring
		; input: x=offset to video memory, y=offset to strings
		SUBROUTINE
.l1		lda strings,y
		beq .end
		sta video,x
		inx
		iny
		jmp .l1
.end	rts



; ----------------------------------------------------------------------
; user defined chars

udcstart

; characters for board positions are in 4-color mode,
; with double-width pixels. Colors are:
; 00 = screen, 01 = border, 10 = char, 11 = aux (blue)

		; 0, top-left
		dc %11111111
		dc %11111111
		dc %11111010
		dc %11111010
		dc %11101010
		dc %11101010
		dc %11101010
		dc %11101010

		; 1, top-right
		dc %11111111
		dc %11111111
		dc %10101111
		dc %10101111
		dc %10101011
		dc %10101011
		dc %10101011
		dc %10101011

		; 2, bottom-left
		dc %11101010
		dc %11101010
		dc %11101010
		dc %11101010
		dc %11111010
		dc %11111010
		dc %11111111
		dc %11111111

		; 3, bottom-right
		dc %10101011
		dc %10101011
		dc %10101011
		dc %10101011
		dc %10101111
		dc %10101111
		dc %11111111
		dc %11111111

; normal characters (8x8)

		; 4, down arrow, left half
		dc %00000001
		dc %00000001
		dc %00000001
		dc %00000001
		dc %00000111
		dc %00000011
		dc %00000001
		dc %00000000

		; 5, down arrow, right half
		dc %10000000
		dc %10000000
		dc %10000000
		dc %10000000
		dc %11100000
		dc %11000000
		dc %10000000
		dc %00000000

udcend


;
codelimit
		; check safe limit of code area
		IF codelimit > 7168
			ERR
		ENDIF
