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
GETIN		equ $ffe4  ; kernal, read keyboard input from queue


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
subseq		ds 4
incr		ds 1
ptr			ds 1
tot			ds 1  ; number of moves
i			ds 1
sound		ds 1

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
		; warning: not sure if it works with negative row!
		mac getptr  ; 16 * row + column + #boardstart
			lda row
			asl
			asl
			asl
			asl
			clc
			adc column
			adc #boardstart
			tax
		endm


		; macro to set x and y to correct values to call printstring
		; warning: only works for the first 255 characters (due to offset in x)
		mac prints  ; off, str
			ldx #{1}
			ldy #{2}-strings
			jsr printstring
		endm


; ----------------------------------------------------------------------

; start of code

		seg code
		org 4097

		; basic stub to launch binary program
		byte 11,16,10,0,158,"4","1","0","9",0,0,0  ; 10 SYS4109

start
		; we don't return to basic, so use the full stack
		ldx #255
		txs

		jsr initonce

optionscreen
		SUBROUTINE
		jsr clearscreen
		prints 22*3+1, strhumanstarts
		prints 22*5+1, strhumancolor
		prints 22*7+1, strsound
		prints 22*10+1, strspacestart
		ldx #'Y+64
		lda manstart
		bne .l1
		ldx #'N+64
.l1		stx video+22*3+20
		lda #81+128
		sta video+22*5+20
		lda clrs+1  ; human color
		sta vcolor+22*5+20
		ldx #'Y+64
		lda sound
		bne .l2
		ldx #'N+64
.l2		stx video+22*7+20
		jsr getchar
		cmp #'H
		beq optstart
		cmp #'C
		beq optcolor
		cmp #'S
		beq optsound
		cmp #32
		beq startgame
		jmp optionscreen
optstart
		lda #1
		eor manstart
		sta manstart
		jmp optionscreen
optcolor
		ldx clrs+1
		ldy clrs+2
		stx clrs+2
		sty clrs+1
		jmp optionscreen
optsound
		lda #1
		eor sound
		sta sound
		lda #15
		eor 36878
		sta 36878
		jmp optionscreen

startgame
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

		lda manstart
		bne userturn
		jmp cputurn

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
		bcc userturn
		cmp #56  ; '8'
		bcs userturn
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
		jmp endgame
wrongcol
		lda 36879
		eor #7
		sta 36879  ; flash border color
		lda #150
		sta 36876 ; sound
		ldx #64
		jsr delay
		lda 36879
		eor #7
		sta 36879
		lda #0
		sta 36876  ; stop sound
		jmp userturn

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

		;jsr debuginfo
		; compute max of column scores
		lda colscores+6
		sta tmp1  ; start with last value
		ldx #5  ; loop through other values
.loop1	lda colscores,x
		cmp tmp1
		bcc .l2
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
		sta row  ; update matching row

		getptr
		stx ptr  ; save for animation
		lda #2
		sta board,x  ; write 2 (cpu) in that position
		ldx column
		dec freerow,x  ; update freerow
		inc tot
		jsr drawarrow
		; animate new move
		lda #4
		sta i
		lda #0
		sta 36875  ; audio
.l4		ldx ptr
		lda board,x
		eor #2
		sta board,x
		jsr drawSlot
		lda 36875
		eor #240
		sta 36875
		ldx #92
		jsr delay
		dec i
		bne .l4
		lda #0
		sta 36875

		jsr checkfinish
		beq endgame
		jmp userturn

endgame
		SUBROUTINE
		lda 36879
		eor #1
		sta 36879  ; border color
.l1		jsr getchar
		cmp #32
		bne .l1
		jmp optionscreen


; ----------------------------------------------------------------------

recursion
		; input: column, depth, color (1 or 2)
		; output: score for that column
		; uses: row, color, depth, score2, tmp1
		; note: scores have an offset of 128 (zero at 128) to avoid signed comparison problems
		SUBROUTINE
		ldx column
		lda freerow,x
		sta row  ; row matching this column
		bpl .l1
		lda  #128+scoreImpossible  ; if row negative, column is full
		sta score
		rts
.l1
		getptr
		lda color
		sta board,x  ; set position to color
		ldx column
		dec freerow,x  ; update freerow
		jsr computescore  ; compute score for this position
		;jsr animatewait
		lda score
		cmp #128+scoreRow4
		bne .l2
		clc
		adc depth  ; if score is 4 in a row, add depth to prefer earlier ones
		sta score
		; if depth == 1 or score >= scoreRow4, return with this score
.l2		lda depth
		cmp #1
		beq .trampoline  ; -> .end
		cmp #3
		bne .l2a
		jsr animatewait
.l2a	lda score
		cmp #128+scoreRow4
		bcs .trampoline  ; -> .end
		lda #128+scoreImpossible
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
		bcs .l3
		lda tmp1
		sta score2
.l3		dey
		bpl .loopcol

		lda score2
		cmp #128+scoreImpossible
		beq .end  ; if new score is impossible, return current score
		; check if score2 >= scoreRow4 or <= -scoreRow4, in that case return -score2
		lda score2
		cmp #128+scoreRow4
		bcs .l3b  ; first case
.l3a	lda #128-scoreRow4
		cmp score2
		bcs .l3b  ; second case
		jmp .l4  ; continue normally
.trampoline	jmp .end
.l3b
		; score = -score2, then return
		lda #0
		sec
		sbc score2  ; -score2, still works with 128 offset
		sta score  ; score = -score2
		jmp .end
		; score -= score2
.l4		lda score
		sec
		sbc score2
		clc
		adc #128
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
		; output: score for that position (positive)
		; uses: score2
		; note: scores have an offset of 128 (zero at 128) to avoid signed comparison problems
		SUBROUTINE
		lda #128
		sta score   ; will contain score for sequences of 2
		sta score2  ; will contain score for sequences of 3
		; horizontal
		getptr
		txa
		sec
		sbc #3
		sta ptr
		lda #1
		sta incr
		jsr computesequencesub  ; compute maxgroup
		lda maxgroup
		;sta $20  ; debug
		cmp #4
		bne .l1a
		lda #128+scoreRow4
		sta score  ; if 4 in a row, don't try other directions
		rts
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
		getptr
		txa
		sec
		sbc #51
		sta ptr
		lda #17
		sta incr
		jsr computesequencesub
		lda maxgroup
		;sta $21  ; debug
		cmp #4
		bne .l1b
		lda #128+scoreRow4
		sta score
		rts
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
		getptr
		txa
		sec
		sbc #48
		sta ptr
		lda #16
		sta incr
		jsr computesequencesub
		lda maxgroup
		;sta $22  ; debug
		cmp #4
		bne .l1c
		lda #128+scoreRow4
		sta score
		rts
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
		getptr
		txa
		sec
		sbc #45
		sta ptr
		lda #15
		sta incr
		jsr computesequencesub
		lda maxgroup
		;sta $23  ; debug
		cmp #4
		bne .l1d
		lda #128+scoreRow4
		sta score
		rts
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
.l3d
		; final: if score2 != 0, assign it to score
		lda score2
		cmp #128
		beq .end
		sta score
.end
		rts


; ----------------------------------------------------------------------

computesequencesub
		; input: ptr (offset in board), color (1 or 2), incr
		; output: maxgroup: max sequence of color and 0 for that position and direction
		; uses: tmp1, i, ptr
		SUBROUTINE
		lda #0
		sta maxgroup
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
		bcc .l3
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

computesequencesublut
		; input: ptr (offset in board), color (1 or 2), incr
		; output: maxgroup: max sequence of color and 0 for that position and direction
		; uses: subseq
		SUBROUTINE
		clc  ; should never be set in following steps
		ldx ptr  ; TODO: pass x directly?
		; 0
		lda board,x
		sta subseq+0
		asl subseq+0
		txa
		adc incr
		tax
		; 1
		lda board,x
		sta subseq+1
		ora subseq+0
		sta subseq+0
		asl subseq+0
		asl subseq+1
		txa
		adc incr
		tax
		; 2
		lda board,x
		sta subseq+2
		ora subseq+0
		sta subseq+0
		lda subseq+2
		ora subseq+1
		sta subseq+1
		asl subseq+0
		asl subseq+1
		asl subseq+2
		txa
		adc incr
		tax
		; 3
		lda board,x
		sta subseq+3
		ora subseq+0
		sta subseq+0
		lda subseq+3
		ora subseq+1
		sta subseq+1
		lda subseq+3
		ora subseq+2
		sta subseq+2
		asl subseq+1
		asl subseq+2
		asl subseq+3
		txa
		adc incr
		tax
		; 4
		lda board,x
		ora subseq+1
		sta subseq+1
		lda board,x
		ora subseq+2
		sta subseq+2
		lda board,x
		ora subseq+3
		sta subseq+3
		asl subseq+2
		asl subseq+3
		txa
		adc incr
		tax
		; 5
		lda board,x
		ora subseq+2
		sta subseq+2
		lda board,x
		ora subseq+3
		sta subseq+3
		asl subseq+3
		txa
		adc incr
		tax
		; 6
		lda board,x
		ora subseq+3
		sta subseq+3
		; now we have the 4 subsequences coded in 8 bit
		lda color
		cmp #2
		beq .c2
		ldx subseq+0
		lda lutseq1,x
		sta subseq+0
		ldx subseq+1
		lda lutseq1,x
		sta subseq+1
		ldx subseq+2
		lda lutseq1,x
		sta subseq+2
		ldx subseq+3
		lda lutseq1,x
		sta subseq+3
		jmp .l1
.c2		ldx subseq+0
		lda lutseq2,x
		sta subseq+0
		ldx subseq+1
		lda lutseq2,x
		sta subseq+1
		ldx subseq+2
		lda lutseq2,x
		sta subseq+2
		ldx subseq+3
		lda lutseq2,x
		sta subseq+3
.l1		; compute max, A contains subseq+3
		sta maxgroup
		cmp subseq+2
		bcs .l2
		lda subseq+2
		sta maxgroup
.l2		cmp subseq+1
		bcs .l3
		lda subseq+1
		sta maxgroup
.l3		cmp subseq+0
		bcs .l4
		lda subseq+0
		sta maxgroup
.l4		rts


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
		prints off-66+3, stryouwin
		lda #0
		rts
.l1		inc color
		jsr victory
		bne .l2
		prints off-66+4, striwin
		lda #0
		rts
.l2		lda tot
		cmp #42  ; board full?
		bne .l3
		prints off-66+5, strdraw
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
		cmp #128+scoreRow4
		bcs .l1
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
		bmi .end
		clc
		rol  ; column*2
		tax
		lda #4
		sta video+off-22,x
		inx
		lda #5
		sta video+off-22,x
.end	rts


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
		; screen and border color
		lda #27
		sta 36879
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
		lda #3
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
		; auxiliary color (blue) for 4-color chars (high nibble) + audio volume (low nibble)
		lda #6*16+15
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
		sta sound
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
striwin		dc 9+128, 32+128, 23+128,9+128, 14+128, 33+128, 0
stryouwin	dc 25+128, 15+128, 21+128, 32+128, 23+128, 9+128, 14+128, 33+128, 0
strdraw		dc 4+128, 18+128, 1+128, 23+128, 0
strhumanstarts	dc 'H+64, 32+128, 45+128, 32+128, 'H+64, 'U+64, 'M+64, 'A+64, 'N+64, 32+128, 'S+64, 'T+64, 'A+64, 'R+64, 'T+64, 'S+64, 58+128, 0
strhumancolor	dc  'C+64, 32+128, 45+128, 32+128,'H+64, 'U+64, 'M+64, 'A+64, 'N+64, 32+128, 'C+64, 'O+64, 'L+64, 'O+64, 'R+64, 58+128, 0
strsound		dc	'S+64, 32+128, 45+128, 32+128, 'S+64, 'O+64, 'U+64, 'N+64, 'D+64, 58+128, 0
strspacestart	dc 'S+64, 'P+64, 'A+64, 'C+64, 'E+64, 32+128, 45+128, 32+128, 'S+64, 'T+64, 'A+64, 'R+64, 'T+64, 0
;hexdigits	dc 48+128, 49+128, 50+128, 51+128, 52+128, 53+128, 54+128, 55+128, 56+128, 57+128, 1+128, 2+128, 3+128, 4+128, 5+128, 6+128


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

		IF 0
debuginfo
		SUBROUTINE
		ldy #0
		sty i
.ld		lda colscores,y
		lsr
		lsr
		lsr
		lsr
		tax
		lda hexdigits,x
		ldx i
		sta video,x
		inx
		stx i
		lda colscores,y
		and #$0f
		tax
		lda hexdigits,x
		ldx i
		sta video,x
		inx
		stx i
		iny
		cpy #7
		bne .ld
		rts
		ENDIF


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


lutseq1
        hex 0001000001020000000000000000000001020000020300000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0102000002030000000000000000000002030000030400000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
lutseq2
        hex 0000010000000000010002000000000000000000000000000000000000000000
        hex 0100020000000000020003000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0100020000000000020003000000000000000000000000000000000000000000
        hex 0200030000000000030004000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000
        hex 0000000000000000000000000000000000000000000000000000000000000000


;
codelimit
		; check safe limit of code area
		IF codelimit > 7168
			ERR
		ENDIF
