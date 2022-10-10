		processor 6502

video	equ 7680
vcolor	equ 38400
off		equ 22*7+4


		; variables in zero page
row		equ 0
column	equ	1
color	equ 2


board	equ $1f00

		org 4097
		byte 11,16,10,0,158,"4","1","0","9",0,0,0  ; 10 SYS4109

start

;  clear screen: space character
		lda #32

		ldy #253
loop1	dey
		sta video,y
		bne loop1

		ldy #253
loop2	dey
		sta video+253,y
		bne loop2

; clear screen: color
		lda #5

		ldy #253
loop3	dey
		sta vcolor,y
		bne loop3

		ldy #253
loop4	dey
		sta vcolor+253,y
		bne loop4

; draw all the board

		lda #5
		sta row
loopR
		lda #6
		sta column
loopC
		lda #0
		sta color
		jsr drawSlot
		ldx #64
		jsr delay
		lda #4
		sta color
		jsr drawSlot
		ldx #64
		jsr delay
		lda #0
		sta color
		jsr drawSlot
		ldx #64
		jsr delay
		lda #4
		sta color
		jsr drawSlot
		ldx #64
		jsr delay
		dec column
		bpl loopC
		dec row
		bpl loopR




		jmp hang

; ----------------------------------------------------------------------

drawSlot
		SUBROUTINE
		; input: row, column, color
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



hang	jmp hang

