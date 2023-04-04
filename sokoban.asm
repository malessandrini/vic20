	processor 6502

	IFCONST EXP3k
		;ECHO "*** 3k"
	ELSE
		IFCONST EXP8k
			;ECHO "*** 8k"
MUSIC	equ
		ELSE
			ECHO "ERROR: no expansion type declared"
			ERR
		ENDIF
	ENDIF

; configuration for 3k expansion:
;  $0400 - $1bff(max): code + level data, 6144 bytes (level data = 3675 bytes)
;  $1c00: user-defined characters (convenient because falls back to character ROM by adding 128)
;   (possibly moved in place at startup if final binary is shorter)
;  end-of-chars - $1dff: extra memory area
;  $1e00: video memory
;
; configuration for 8k expansion:
;  $1000: video memory
;  $1200 - $1bff: code (first chunk), 2560 bytes
;  $1c00 - $nnnn: user-defined characters (see note above)
;  $nnnn+1 - $3fff(or more for bigger expansions): code and level data (second chunk)


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; constants

	IFCONST EXP3k
ramstart	equ $0400
ramend		equ $1e00
video		equ $1e00   ; video memory
vcolor		equ $9600  ; color memory
sysaddr		equ	"1037"
	ENDIF
	IFCONST EXP8k
ramstart	equ $1200
ramend		equ $4000
video		equ $1000   ; video memory
vcolor		equ $9400  ; color memory
sysaddr		equ	"4621"
	ENDIF
charmem		equ $1c00
GETIN		equ $ffe4  ; kernal, read keyboard input from queue

LEV_NUM			equ 153
MAX_LEV_SIZE	equ 220
MAX_LEV_BMP		equ [220 + 7] / 8
MAX_LEV_ROUND	equ MAX_LEV_BMP * 8
UNDO_MAX		equ 192

bEMPTY		equ 0
bWALL		equ 1
bGOAL		equ 2
bSTONE		equ 4
bMAN		equ 8
; extra bits for graphical variations of wall,
; only used together with bWALL
bWALL1		equ 16  ; terminal left edge
bWALL2		equ 32  ; terminal right edge

CHAR_OFF	equ 128  ; added to character code to switch to default character ROM

; possible values of a cell: 0 (empty), 1 (wall), 2 (goal), 3 (NO), 4 (stone), 5 (NO), 6 (stone+goal),
;  7 (NO), 8 (man), 9 (NO), 10 (man+goal)


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; variables in zero page
;
; we overwrite the Basic variable area, but leave kernal area untouched
; because the kernal is always executing through interrupts (e.g. keyboard
; reading). This gives us 144 bytes.

		seg.u zpvars
		org 0
level_ptr	ds 2  ; pointer to encoded level data
level		ds 1  ; number of current level
rows		ds 1  ; rows of current level
cols		ds 1  ; columns of current level
man			ds 1  ; position of man
lev_size	ds 1  ; number of total cells of level
lev_code	ds 6  ; secret code for level (0..15 for every byte)
usr_code	ds 6  ; code entered by user
scrn_ptr	ds 2  ; pointer for screen memory (X or Y register not enough to sweep all screen)
extra_ptr	ds 2  ; pointer for different uses (color memory, strings, ...)
i			ds 1  ; generic temp. variable
j			ds 1  ; generic temp. variable
k			ds 1  ; generic temp. variable
joy_prev	ds 1  ; previous value of joystick for repetition
joy_filter  ds 1  ; filter bits for joystick reading
joy_rep		ds 2  ; manage joystick repetition rate (16 bit)
lev_unlock	ds 1  ; maximum level that's been unlocked
; for every level, the following variables tell how to draw the map
; in a 11x11 logical screen (2x2 chars for every cell), with possible
; scrolling for maps larger than 11 rows or columns
scr_r		ds 1  ; screen position where to draw map
scr_c		ds 1
map_r		ds 1  ; map cell drawn at origin (0..delta_r)
map_c		ds 1
draw_r		ds 1  ; how many cells to draw
draw_c		ds 1
delta_r		ds 1  ; max value for map_r (scrolling)
delta_c		ds 1
; variables depending on game progress
undo_ptr	ds 1
undo_tot	ds 1
move_count	ds 2  ; 2 bytes in BCD format (4 decimal digits)
; variables for music
music_ptr	ds 2
music_dur	ds 1
music_on	ds 1  ; bit 0: enabled, bit 1: play

;
zplimit
		; check safe limit of allocated area
		IF zplimit > 144
			ERR
		ENDIF


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; tape buffer area, 192 bytes (maybe some more before and after)

		seg.u tapebuffer
		org 828

; undo information are stored in a circular stack, where older entries are overwritten
undo_stack	ds UNDO_MAX

;
tpbuflimit
		; check safe limit of allocated area
		IF tpbuflimit > 1020
			ERR
		ENDIF


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; start of code

		seg code
		org ramstart+1

		; basic stub to launch binary program
		byte 11,16,10,0,158,sysaddr,0,0,0  ; 10 SYSxxxx

start
		; we don't return to basic, so use the full stack
		ldx #255
		txs

		; initial setup
		lda #255
		sta joy_filter
		; enable repeat for all keys
		lda #128
		sta 650
		; disable shift+commodore character switch
		lda 657
		ora #128
		sta 657

	IFCONST COPY_CHARACTERS
		; copy user defined chars to proper address
		ldx #[udcend-udcstart]
		ldy #0
.l1		lda udcstart,y
		sta charmem,y
		iny
		dex
		bne .l1
	ENDIF

	IFCONST MUSIC
		lda #<music_data
		sta music_ptr
		lda #>music_data
		sta music_ptr+1
		lda #1
		sta music_on  ; enabled
		jsr music_stop
		; install irq routine
		sei
		lda #<music_irq
		sta $0314
		lda #>music_irq
		sta $0315
		cli
	ENDIF

		; auxiliary color (green) for 4-color chars (high nibble) + audio volume (low nibble)
		lda #5*16+8
		sta 36878

		; activate user defined chars
		lda #$0F
		ora 36869
		sta 36869

		; start with level 1
		lda #1
		sta level
		sta lev_unlock

		jmp main_menu


; ----------------------------------------------------------------------

main_menu
		jsr music_stop
		jsr clearscreen
		prn_str video+22*1+5, str_main1
main0	jsr getchar_joy
		cmp #32
		beq start_level
		cmp #7  ; joystick fire
		beq start_level
		cmp #'H
		beq help_menu1
		cmp #'C
		beq enter_code
		jmp main0


; ----------------------------------------------------------------------

help_menu
		jsr clearscreen
		prn_str video+22*1+3, str_help1
		jsr getchar
		rts
help_menu1
		jsr help_menu
mmenu	jmp main_menu
help_menu2
		jsr help_menu
		jsr clearscreen
		jmp redraw_level


; ----------------------------------------------------------------------

enter_code
		jsr clearscreen
		prn_str video+22*10+5, str_enter_code
		lda #0
		sta i
lkey	jsr getchar
		cmp #'A
		bcc lkey
		cmp #['Z]+1
		bcs lkey
		sec
		sbc #'A
		ldx i
		sta usr_code,x  ; starting from 0
		clc
		adc #[1+CHAR_OFF]  ; printable code (starting from 'A')
		sta [video+22*13+7],x
		inx
		stx i  ; x will be modified by getchar
		cpx #6
		bne lkey
		lda #10
		jsr delay_jiffy
		jmp check_code


; ----------------------------------------------------------------------

start_level
		jsr clearscreen
		jsr music_start
reload_level
		jsr load_level  ; also clears game-progress variables
redraw_level
		jsr draw_level
wait_input
		jsr getchar_joy
		cmp #145
		beq move_up
		cmp #17
		beq move_down
		cmp #157
		beq move_left
		cmp #29
		beq move_right
		cmp #133  ; f1
		beq mmenu
		cmp #'H
		beq help_menu2
		cmp #'N
		beq go_next_trmpl
		cmp #'P
		beq go_prev
		cmp #'W
		beq scroll_up
		cmp #'A
		beq scroll_left
		cmp #'S
		beq scroll_right
		cmp #'Z
		beq scroll_down
		cmp #136  ; f7
		beq reload_level
		cmp #'U
		beq undo_move
		cmp #7  ; joystick fire
		beq undo_move
		cmp #'M
		beq toggle_music
		jmp wait_input
move_up
		lda #0
		sta j  ; undo info
		lda #0
		sec
		sbc cols  ; -cols
		jmp move_n
move_down
		lda #1
		sta j  ; undo info
		lda cols
		jmp move_n
move_left
		lda #2
		sta j  ; undo info
		lda #-1
		jmp move_n
move_right
		lda #3
		sta j  ; undo info
		lda #1
		jmp move_n
go_next_trmpl
		jmp go_next
go_prev
		lda level
		cmp #1
		beq trmpl1
		dec level
		jmp start_level

trmpl1	jmp wait_input

scroll_up
		lda map_r
		beq trmpl1
		dec map_r
		jmp redraw_level
scroll_down
		lda map_r
		cmp delta_r
		beq trmpl1
		inc map_r
		jmp redraw_level
scroll_left
		lda map_c
		beq trmpl1
		dec map_c
		jmp redraw_level
scroll_right
		lda map_c
		cmp delta_c
		beq trmpl1
		inc map_c
		jmp redraw_level
undo_move
		jsr undo_revert_move
		jmp redraw_level
toggle_music
		jsr music_mute
		lda #1
		eor music_on
		sta music_on
		jmp wait_input
go_next
		lda level
		cmp #LEV_NUM  ; test we're not at last level
		beq trmpl1
		cmp lev_unlock  ; test we unlocked next level
		bcc ok_next
		lda #<str_level_locked
		sta extra_ptr
		lda #>str_level_locked
		sta extra_ptr+1
		jsr popup_screen
		jmp redraw_level
ok_next
		inc level
		jmp start_level
move_n
		; j is the byte for undo, except stone information
		sta i  ; save increment in case of stone push
		clc
		adc man
		tax  ; x = new wanted position
		lda #0
		sta k  ; flag: level completed
		lda level_map,x
		and #bWALL
		bne trmpl1
		lda level_map,x
		and #bSTONE
		beq only_man
		; check if we can move the stone
		txa
		clc
		adc i
		tay  ; y = new wanted position for stone
		lda level_map,y
		and #[bWALL|bSTONE]
		bne trmpl1
		; move stone
		lda j
		ora #8
		sta j  ; undo information
		jsr inc_move_count
		lda level_map,y
		ora #bSTONE
		sta level_map,y  ; y is now free
		lda level_map,x
		and #~bSTONE
		sta level_map,x
		; check if level completed: if one cell == stone -> not completed
		ldy lev_size
lwin	lda [level_map-1],y
		cmp #bSTONE
		beq	only_man  ; not completed
		dey
		bne lwin
		; completed!
		inc k
only_man
		; move man
		lda level_map,x
		ora #bMAN
		sta level_map,x
		ldy man  ; current position
		lda level_map,y
		and #~bMAN
		sta level_map,y
		stx man  ; new position
		; save undo information (from j)
		lda j
		jsr undo_add_move  ; must not change k
		lda k  ; completed?
		bne level_complete
		jmp redraw_level


; ----------------------------------------------------------------------

level_complete
		SUBROUTINE
		jsr draw_level  ; draw with last (winning) move
		; end-of-level animation
		ldy #12
.la		ldx man
		lda level_map,x
		eor #bMAN
		sta level_map,x
		tya
		pha
		jsr draw_level
		lda #3
		jsr delay_jiffy
		pla
		tay
		dey
		bne .la
		jsr getchar_or_fire
		; increment level and load new level, including secret code
		lda level
		cmp #LEV_NUM
		beq .l1
		inc level
		lda lev_unlock
		cmp level
		bcs .l1
		lda level
		sta lev_unlock
		; TODO: different thing after last level
.l1		jsr load_level
		; show screen with secret code
		jsr clearscreen
		prn_str video+22*10+1, str_lev_code
		lda #<[video+22*10+16]
		sta scrn_ptr
		lda #>[video+22*10+16]
		sta scrn_ptr+1
		lda level
		jsr print_decimal
		; write code
		ldx #6
.l2		lda [lev_code-1],x
		clc
		adc #'A
		jsr ascii2vic
		sta [video+22*13+6],x
		dex
		bne .l2
		lda #90
		jsr delay_jiffy
		jsr getchar_or_fire
		jmp start_level


; ----------------------------------------------------------------------

check_code
		SUBROUTINE
		lda level
		pha  ; save current level if code not valid
		; iterate for all values of level (loading level every time)
		lda #LEV_NUM
		sta level  ; loop from LEV_NUM to 1
.l1		jsr load_level  ; set code for this level
		ldx #6
.l2		lda [lev_code-1],x
		cmp [usr_code-1],x
		bne .wrong
		dex
		bne .l2
		jmp .right
.wrong	dec level
		bne .l1
		pla  ; not found, restore level
		sta level
		jmp main_menu
.right
		pla
		lda lev_unlock
		cmp level
		bcs .end
		lda level
		sta lev_unlock
.end	jmp start_level


; ----------------------------------------------------------------------

inc_move_count
		SUBROUTINE
		sed
		clc
		lda #1
		adc move_count  ; decimal
		sta move_count
		lda #0
		adc move_count+1  ; decimal with carry
		sta move_count+1
		cld
		rts


; ----------------------------------------------------------------------

dec_move_count
		SUBROUTINE
		sed
		sec
		lda move_count
		sbc #1  ; decimal
		sta move_count
		lda move_count+1
		sbc #0  ; decimal with borrow
		sta move_count+1
		cld
		rts


; ----------------------------------------------------------------------

undo_add_move
		; input: A
		SUBROUTINE
		; undo_ptr must be in a valid position (0 .. UNDO_MAX-1)
		ldx undo_ptr
		sta undo_stack,x
		; inc pointer, rolling back to 0
		inx
		cpx #UNDO_MAX
		bne .l1
		ldx #0
.l1		stx undo_ptr
		; inc total, but only if < UNDO_MAX (otherwise will overwrite older entries)
		lda #UNDO_MAX
		cmp undo_tot
		beq .l2
		inc undo_tot
.l2		rts


; ----------------------------------------------------------------------

undo_revert_move
		SUBROUTINE
		lda undo_tot
		beq .end
		dec undo_tot
		; dec undo_ptr, rolling back to last position
		ldx undo_ptr
		bne .l1
		ldx #UNDO_MAX
.l1		dex
		stx undo_ptr
		lda undo_stack,x
		and #8
		sta k  ; k = whether a stone has been moved
		lda undo_stack,x
		and #0x03
		beq undo_up
		cmp #1
		beq undo_down
		cmp #2
		beq undo_left
undo_right
		lda #1
		jmp undo_n
undo_up
		lda #0
		sec
		sbc cols  ; -cols
		jmp undo_n
undo_down
		lda cols
		jmp undo_n
undo_left
		lda #-1
undo_n
		sta i  ; original movement
		lda man
		sec
		sbc i
		tax  ; x = new man position
		; was the stone moved?
		lda k  ; k is now free
		beq undo_man
		; must undo stone too
		lda i
		clc
		adc man
		tay  ; y = current stone position
		; undo stone
		lda level_map,y
		and #~bSTONE
		sta level_map,y
		ldy man
		lda level_map,y
		ora #bSTONE
		sta level_map,y
		jsr dec_move_count
undo_man
		ldy man
		lda level_map,y
		and #~bMAN
		sta level_map,y
		lda level_map,x
		ora #bMAN
		sta level_map,x
		stx man
.end	rts


; ----------------------------------------------------------------------

map_char
		dc 32+CHAR_OFF, 32+CHAR_OFF, 32+CHAR_OFF, 32+CHAR_OFF  ; empty
		dc 0, 1, 2, 3  ; wall
		dc 8, 9, 10, 11  ; goal
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 4, 5, 6, 7  ; stone
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 12, 13, 14, 15  ; stone + goal
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 16, 17, 18, 19  ; man
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 20, 21, 22, 23  ; man + goal
		dc 24, 1, 2, 3  ; wall variant
		dc 0, 25, 2, 3  ; wall variant
		dc 24, 25, 2, 3  ; wall variant
map_color
		dc 1, 1, 1, 1
		dc 1, 1, 1, 1
		dc 5, 5, 5, 5
		dc 6, 6, 6, 6
		dc 2, 2, 2, 2
		dc 6, 6, 6, 6
		dc 2+8, 2+8, 2+8, 2+8
		dc 6, 6, 6, 6
		dc 7+8, 7+8, 7+8, 7+8
		dc 6, 6, 6, 6
		dc 7+8, 7+8, 7+8, 7+8
		dc 1, 1, 1, 1
		dc 1, 1, 1, 1
		dc 1, 1, 1, 1
str_main1
		dc 176, 128, 128, 128, 128, 128, 128, 128, 128, 128, 174, 10
		dc 157, 8, 157, 10
		dc 157, " SOKOBAN ", 157, 10
		dc 157, 8, 157, 10
		dc 173, 128, 128, 128, 128, 128, 128, 128, 128, 128, 189, 30, 30, 9
		dc "SPACE,FIRE: START", 26
		dc "C: ENTER LEVEL CODE", 24
		dc "H: HELP", 0
str_help1
		dc "IN-GAME CONTROLS", 22, 22, 22
		dc "ARROWS,JOYSTICK: MOVE ", 21
		dc "W,A,S,Z: SCROLL VIEW", 23
		dc "N,P: NEXT/PREV. LEVEL", 22
		dc "U,FIRE: UNDO MOVE", 26
		dc "F1: EXIT TO MENU", 27
		dc "F7: RESET LEVEL", 28
		dc "H: THIS HELP"
	IFCONST MUSIC
		dc 31, "M: MUSIC ON/OFF"
	ENDIF
		dc 0
str_lev_code
		dc "CODE FOR LEVEL    :", 0
str_enter_code
		dc "ENTER CODE:", 22, 24, 30, "------", 0
str_press_h
		dc "PRESS ", 34, "H", 34, " FOR HELP", 0
str_header
		dc "LEVEL:", 5, "MOVES:", 0
str_popup_frame
		dc 176, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 174, 3
		dc 157, 15, 157, 3
		dc 157, 15, 157, 3
		dc 157, 15, 157, 3
		dc 173, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 189, 0
str_level_locked
		dc " LEVEL LOCKED ", 0


; ----------------------------------------------------------------------

popup_screen
		; input: extra_ptr (string, 14 characters)
		SUBROUTINE
		; set space character for the popup area
		lda #32+CHAR_OFF
		ldy #18
.loop1	dey
		sta [video+9*22+2],y
		sta [video+10*22+2],y
		sta [video+11*22+2],y
		sta [video+12*22+2],y
		sta [video+13*22+2],y
		bne .loop1
		; set character color to red for the popup area
		lda #2  ; red
		ldy #18
.loop2	dey
		sta [vcolor+9*22+2],y
		sta [vcolor+10*22+2],y
		sta [vcolor+11*22+2],y
		sta [vcolor+12*22+2],y
		sta [vcolor+13*22+2],y
		bne .loop2
		; print string set by caller
		lda #<[video+11*22+4]
		sta scrn_ptr
		lda #>[video+11*22+4]
		sta scrn_ptr+1
		jsr print_string
		; print frame
		prn_str video+9*22+2, str_popup_frame
		lda #30
		jsr delay_jiffy
		jsr getchar_or_fire
		jsr clearscreen
		rts


; ----------------------------------------------------------------------

load_level
		; input: level (must be in range 1..LEV_NUM)
		SUBROUTINE
		; clear variables associated with a running level, so we don't risk them being incoherent
		lda #0
		sta undo_ptr
		sta undo_tot
		sta move_count
		sta move_count+1
		; reset level pointer
		lda #<level_data
		sta level_ptr
		lda #>level_data
		sta level_ptr+1
		lda #0
		sta i  ; current level
.loopl	ldy #0
		lda (level_ptr),y
		iny
		sta k
		inc i
		lda i
		cmp level
		beq .ok
		; move pointer by k (skip level)
		lda k
		clc
		adc level_ptr
		sta level_ptr
		bcc .lp
		inc level_ptr+1
.lp		jmp .loopl
		; load actual level
.ok		lda (level_ptr),y
		iny
		sta rows
		lda (level_ptr),y
		iny
		sta cols
		lda (level_ptr),y
		iny
		sta man
		; compute number of cells: lev_size = rows * cols
		lda #0
		sta lev_size
		ldx cols
		clc
.l1		lda rows
		adc lev_size
		sta lev_size
		dex
		bne .l1
		; compute number of bitmap bytes (walls) to be read = (lev_size + 7) / 8
		lda lev_size
		clc
		adc #7  ; A = lev_size + 7
		lsr
		lsr
		lsr   ; A = (lev_size + 7) / 8
		sta i
		; read i bytes, for each generate 8 bytes empty/wall
		ldx #0  ; index for level_map (generated bytes)
.l2		lda (level_ptr),y
		iny
		sta k
		lda #8
		sta j
.l3		; read 1 bit
		asl k
		lda #bEMPTY
		bcc .l4
		lda #bWALL
.l4		sta level_map,x
		inx
		dec j
		bne .l3
		dec i
		bne .l2
		; read number of stones and goals
		lda (level_ptr),y
		iny
		sta j
		sta k
		; read stones
.l5		lda (level_ptr),y
		iny
		tax
		lda level_map,x
		ora #bSTONE
		sta level_map,x
		dec j
		bne .l5
		; read goals
.l6		lda (level_ptr),y
		iny
		tax
		lda level_map,x
		ora #bGOAL
		sta level_map,x
		dec k
		bne .l6
		; compute code for this level, from last 6 bytes (going backward with y)
		ldx #6
.lcode	dey
		lda (level_ptr),y
		and #%00111100
		lsr
		lsr
		sta [lev_code-1],x
		dex
		bne .lcode
		; set man at proper position
		ldx man
		lda level_map,x
		ora #bMAN
		sta level_map,x
		; compute parameters for drawing
		; rows
.l6a	lda #0
		sta map_r
		lda #11
		sec
		sbc rows  ; 11 - rows
		bcc .rge11  ;  if rows > 11
		; otherwise rows <= 11
		clc
		adc #1
		lsr  ; now A = (11 - rows + 1) / 2
		sta scr_r
		lda rows
		sta draw_r  ; draw all rows
		lda #0
		sta delta_r  ; scrolling
		jmp .l7
.rge11	lda #0
		sta scr_r
		lda #11
		sta draw_r
		lda rows
		sec
		sbc #11
		sta delta_r
.l7		; columns
		lda #0
		sta map_c
		lda #11
		sec
		sbc cols  ; 11 - cols
		bcc .cge11  ;  if cols > 11
		; otherwise cols <= 11
		lsr  ; now A = (11 - cols) / 2
		sta scr_c
		lda cols
		sta draw_c  ; draw all cols
		lda #0
		sta delta_c  ; scrolling
		jmp .l8
.cge11	lda #0
		sta scr_c
		lda #11
		sta draw_c
		lda cols
		sec
		sbc #11
		sta delta_c
.l8		; adjust bWALL flags for graphical variations of walls
		ldx #0  ; pointer in level_map
		lda #0
		sta i  ; row
.l9r	ldy #0  ; column
.l9c	lda level_map,x
		and #bWALL
		beq	.nochange
		; it's a wall. First, test if no wall at left
		cpy #0
		beq .eleft
		dex
		lda level_map,x
		inx
		and #bWALL
		bne .l10
.eleft	; wall must be modified for terminal left edge
		lda level_map,x
		ora #bWALL1
		sta level_map,x
.l10	; second, test if no wall at right
		iny
		tya
		dey
		cmp cols  ; test if y == columns - 1
		beq .eright
		inx
		lda level_map,x
		dex
		and #bWALL
		bne .nochange
.eright	; wall must be modified for terminal right edge
		lda level_map,x
		ora #bWALL2
		sta level_map,x
.nochange	; continue loop
		inx
		iny
		cpy cols
		bne .l9c
		inc i
		lda i
		cmp rows
		bne .l9r

		rts


; ----------------------------------------------------------------------

draw_level
		SUBROUTINE
		;jsr clearscreen
		lda #<[video+22]
		sta scrn_ptr
		lda #>[video+22]
		sta scrn_ptr+1
		lda #<[vcolor+22]
		sta extra_ptr
		lda #>[vcolor+22]
		sta extra_ptr+1
		; increment row according to scr_r
		ldx scr_r
		beq .l1a
.l1		lda #44
		clc
		adc scrn_ptr
		sta scrn_ptr
		bcc .l1p
		inc scrn_ptr+1
.l1p	lda #44
		clc
		adc extra_ptr
		sta extra_ptr
		bcc .l1pp
		inc extra_ptr+1
.l1pp	dex
		bne .l1
		; increment column according to scr_c
.l1a	lda scr_c
		asl
		clc
		adc scrn_ptr
		sta scrn_ptr
		bcc .l1q
		inc scrn_ptr+1
.l1q	lda scr_c
		asl
		clc
		adc extra_ptr
		sta extra_ptr
		bcc .l1qq
		inc extra_ptr+1
.l1qq
		lda draw_r
		sta i  ; loop for row
		lda #0
		sta k  ; pointer in level_map
		; increment k according to map_r
		ldx map_r
		beq .l2a
.l2		lda cols
		clc
		adc k
		sta k
		dex
		bne .l2
		; increment k according to map_c
.l2a	lda map_c
		clc
		adc k
		sta k
.lr		; row loop
		ldy #0  ; offset (column) for scrn_ptr
		lda draw_c
		sta j  ; loop for cols
.lc		; column loop
		ldx k
		inc k
		lda level_map,x  ; next cell value
		; if a wall, can be of different types
		cmp #(bWALL|bWALL1)
		bne .lz1
		lda #11
.lz1	cmp #(bWALL|bWALL2)
		bne .lz2
		lda #12
.lz2	cmp #(bWALL|bWALL1|bWALL2)
		bne .lz3
		lda #13
.lz3	asl
		asl
		tax
		lda map_char,x  ; character for this cell value
		sta (scrn_ptr),y  ; first char
		lda map_color,x
		sta (extra_ptr),y  ; first char color
		iny
		inx
		lda map_char,x
		sta (scrn_ptr),y  ; second char
		lda map_color,x
		sta (extra_ptr),y  ; second char color
		tya
		clc
		adc #21
		tay
		inx
		lda map_char,x
		sta (scrn_ptr),y  ; third char
		lda map_color,x
		sta (extra_ptr),y  ; third char color
		iny
		inx
		lda map_char,x
		sta (scrn_ptr),y  ; fourth char
		lda map_color,x
		sta (extra_ptr),y  ; fourth char color
		tya
		sec
		sbc #21
		tay
		dec j
		bne .lc
		; update k for (possible) remainder cols-11 (= delta_c)
		lda delta_c
		clc
		adc k
		sta k
		; update scrn_ptr and extra_ptr on next line
		lda #44
		clc
		adc scrn_ptr
		sta scrn_ptr
		lda #0
		adc scrn_ptr+1
		sta scrn_ptr+1
		lda #44
		clc
		adc extra_ptr
		sta extra_ptr
		lda #0
		adc extra_ptr+1
		sta extra_ptr+1
		dec i
		beq .l25
		jmp .lr
		; print level number
.l25	prn_str video,str_header
		lda #<[video+6]
		sta scrn_ptr
		lda #>[video+6]
		sta scrn_ptr+1
		lda level
		jsr print_decimal
		; print moves (BCD variable)
		clc
		lda move_count+1
		and #$F0
		lsr
		lsr
		lsr
		lsr
		adc #48+CHAR_OFF
		sta video+18
		lda move_count+1
		and #$0F
		adc #48+CHAR_OFF
		sta video+19
		lda move_count
		and #$F0
		lsr
		lsr
		lsr
		lsr
		adc #48+CHAR_OFF
		sta video+20
		lda move_count
		and #$0F
		adc #48+CHAR_OFF
		sta video+21
		lda level
		cmp #4
		bcs .l3
		prn_str [video+22*22+2],str_press_h
.l3		rts


; ----------------------------------------------------------------------

ascii2vic
		SUBROUTINE
		; input: A (ascii)
		; only works for ascii codes in range 32..90 (except '@')
		cmp #65
		bcc .ok
		sbc #64
		clc
.ok		adc #CHAR_OFF
		rts


; ----------------------------------------------------------------------

print_string
		; input: scrn_ptr, extra_ptr (0-terminated string, ascii in range 32..90 except '@')
		;  bytes in range 1..31 are interpreted as space skip
		SUBROUTINE
		ldy #0
.l1		lda (extra_ptr),y
		beq .end
		cmp #32
		bcc .skip
		jsr ascii2vic
		sta (scrn_ptr),y
.l2		iny
		bne .l1
		inc extra_ptr+1
		inc scrn_ptr+1
		jmp .l1
.skip	adc scrn_ptr  ; C is 0
		sta scrn_ptr
		bcc .l2
		inc scrn_ptr+1
		jmp .l2
.end	rts


; ----------------------------------------------------------------------
; convenience macro to call print_string

	mac prn_str
		lda #<[{1}]
		sta scrn_ptr
		lda #>[{1}]
		sta scrn_ptr+1
		lda #<[{2}]
		sta extra_ptr
		lda #>[{2}]
		sta extra_ptr+1
		jsr print_string
	endm


; ----------------------------------------------------------------------

print_decimal
		; input: scrn_ptr, A
		SUBROUTINE
		; first, divide by 100 to find first digit
		ldx #100
		jsr divide
		pha  ; save remainder
		txa
		clc
		adc #48+CHAR_OFF
		ldy #0
		sta (scrn_ptr),y  ; first digit
		; second, divide by 10 to find second and third digit
		pla
		ldx #10
		jsr divide
		ldy #2
		clc
		adc #48+CHAR_OFF
		sta (scrn_ptr),y  ; third digit
		txa
		;clc
		adc #48+CHAR_OFF
		dey
		sta (scrn_ptr),y  ; second digit
		rts


; ----------------------------------------------------------------------

divide
		; input: A, X ; output: X = result (A/X), A = remainder
		; uses: i
		SUBROUTINE
		stx i
		ldx #0  ; result, incremented at every subtraction
		sec
.l1		sbc i
		bcc .l2  ; if negative, stop subctracting
		inx
		jmp .l1
.l2		adc i  ; an extra subtraction was performed; C is clear here (but becomes set)
		rts


; ----------------------------------------------------------------------

delay_jiffy
		; input: A = 1/60 seconds
		SUBROUTINE
		clc
		adc 162  ; jiffy clock
.loop1	cmp 162
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

getjoystick
		; output: A (bits from 0: E, N, S, W, fire)
		SUBROUTINE
		lda $911f
		eor #$ff
		and #$3c
		ldx #$7f
		sei
		stx $9122
		ldx $9120
		bmi .l1
		ora #$02
.l1		ldx #$ff
		stx $9122
		cli
		lsr
		rts


; ----------------------------------------------------------------------

getchar_joy
		; output: A
		; empty keyboard buffer, than wait for new char or joystick
		SUBROUTINE
.l1		jsr GETIN
		cmp #0
		bne .l1
.l2		jsr GETIN
		cmp #0
		beq .l3
		rts  ; keyboard
.l3		jsr getjoystick
		and joy_filter
		cmp joy_prev
		bne .joy_first  ; first command different from previous ones
		; manage joystick repetition (from second repetition)
		cmp #0
		beq .l2
		dec joy_rep
		bne .l2
		dec joy_rep+1
		bne .l2
		; delay for repetition has passed
		ldx #255
		stx joy_rep
		ldx #3
		stx joy_rep+1
		jmp .joy_read
.joy_first  ; repetition delay is longer for first time
		ldx #255
		stx joy_rep
		ldx #12
		stx joy_rep+1
.joy_read
		; joystick reading, for directions return simulated key: 29, 145, 17, 157,
		; for fire return pseudo-value 7 to distinguish from keyboard
		sta joy_prev
		cmp #0
		beq .l2  ; new state is no-joystick
		cmp #1
		bne .l4a
		lda #29
		rts
.l4a	cmp #2
		bne .l4b
		lda #145
		rts
.l4b	cmp #4
		bne .l4c
		lda #17
		rts
.l4c	cmp #8
		bne .l4d
		lda #157
		rts
.l4d	cmp #16
		bne .l2
		lda #7
		rts


; ----------------------------------------------------------------------

getchar_or_fire
		; output: A
		; wait for keyboard or joystick (fire button only)
		SUBROUTINE
		lda #16
		sta joy_filter
		jsr getchar_joy
		tax
		lda #255
		sta joy_filter
		txa
		rts


	IFCONST MUSIC

; ----------------------------------------------------------------------

music_mute
		lda #0
		sta $900a
		sta $900b
		sta $900c
		rts


; ----------------------------------------------------------------------

music_stop
		lda #~2
		and music_on
		sta music_on
		jmp music_mute


; ----------------------------------------------------------------------

music_start
		SUBROUTINE
		lda #2
		and music_on
		bne .end
		lda #2
		ora music_on
		sta music_on
		lda #1
		sta music_dur  ; irq will decrement it
.end	rts


; ----------------------------------------------------------------------

music_irq
		SUBROUTINE
		lda music_on
		cmp #3
		bne .end
		dec music_dur
		bne .end
		ldy #255
		; fetch new note
.fetch	iny
		lda (music_ptr),y
		cmp #$ff
		bne .l1
		; end of music data, rewind
		lda #<music_data
		sta music_ptr
		lda #>music_data
		sta music_ptr+1
		jmp .end
.l1		; A and flags are still set on the note
		clc
		bmi .ch1
.ch0	adc #127
		sta $900b
		jmp .duration
.ch1	and #127
		adc #127
		sta $900c
.duration
		iny
		lda (music_ptr),y
		beq .fetch  ; new event is at the same time
		sta music_dur
		; update music_ptr
		iny
		tya
		clc
		adc music_ptr
		sta music_ptr
		bcc .end
		inc music_ptr+1
.end	jmp $eabf  ; kernal irq routine

	ELSE

music_start
music_stop
music_mute
		rts

	ENDIF


; ----------------------------------------------------------------------

	IFCONST EXP8k
hole	equ	charmem-.
		ALLOCATE_CHARACTERS
	ENDIF


; ----------------------------------------------------------------------

clearscreen
		SUBROUTINE
		; screen and border color
		lda #14
		sta 36879
; space character
		lda #32+CHAR_OFF
		ldy #253
.loop1	dey
		sta video,y
		sta video+253,y
		bne .loop1
; color
		lda #1
		ldy #253
.loop3	dey
		sta vcolor,y
		sta vcolor+253,y
		bne .loop3
		rts


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; level data

; format for each level:
; [tot][rows][cols][man][wall bitmap]...[num_stones][stone]...[goal]...

level_data
        hex 0F070614F249E1867F0002131B08131107060FFE1A61861FC00314151B151A1B
        hex 1006092A3C73E034984FFC021821262811060816FF818181F90F031314151213
        hex 141407081C7F4141C18181FF04141B1D241315232514060C22FDF8718058818F
        hex FF80031A1B26292A2B1808072DFF060C183060FF061117191F25271012181E20
        hex 26150C080E3F2121371414F486A28AE23E0214150C0D0F07060DFA387164D1C0
        hex 020E0F072216080B2E03E0440AFF580355E027FC03303234121D28120809183F
        hex 108B7D188C067FE002212A262712080928F8462118F70914827F02141E293213
        hex 090710F132244CE850A77803181E26080F160F06071AFF06AC18FF0002181916
        hex 191107090F077EE0311FA8443E021829171815080A2E7813C41B6288E21887FF
        hex 032F3839292B3F11070608FA28A3861FC0031314150D0E0F1109072DFF060DB8
        hex 5C89123C021F260F1111080813FF8181FB1212121E0214150C0D12080915FE41
        hex E03ED2093C907802161718190F06071AF13E0C5C2FC0021718101211090725F9
        hex 1E0C5D2850A7780226270F111007071FFF060EB4489F00020A1E0A2010070713
        hex BE478C78307F8002111225271207071F789D0E1831FE00031112201718191108
        hex 06097D1479861E4F031520211A1B1C1007071AFD0ADC1A31FE000218190B2410
        hex 070710F912247C285F800217181E2016090B3D07C08C10BF1C1300EFD402FFC0
        hex 02393B344A1107061AF27861863F80030E0F1B131415120707103CCB1C183C4F
        hex 8003111718121E201207071A799E0C18F91E00031718191617181207071AFF26
        hex 0C58327F800311181F0816241406091C3C73E030180FFC041D1E1F201E1F2021
        hex 180A07363CC912244891A1627C0512181F262E10171E252C19050F2AF0013FFE
        hex 000C001FFFE00520222426282F303132331408093203FD63B0580FD4221F031F
        hex 262910192214070A2CFFE01B7681837E10FC0322232D18252A15090A37F823CA
        hex 9207E8621AFE20F80002232D1A2E1106071F7C8B1C183FC0031718191E1F2011
        hex 060811FE828391C37E031213141C1D1E120807121E244F983461FE031920271A
        hex 2128160909100782413F980C261FC83C0003283031222B3409030506FC7E0107
        hex 0811070621FE186B861FC0030F151B070809100807277F866D183AD13E02191F
        hex 1F2113070B2E3F9C12025DF8031C7EF802181A30321308080BFC8496938191F1
        hex 1F032324251A222A150A080AFC8494848CEF4941417F03121A223A3B3C12070A
        hex 1A3C39F80605EF4813FC0217201B1C1007081DF09C8781E5213F021B1C1C2413
        hex 08060A3F9861861E4F040F151B2115161B1C140707267D8E0C9838DF00041012
        hex 1E20090B101219080C3E03F0213E1E71803822C3E7E00432353F40202C384413
        hex 080A0CFF224813E409DA169C3C022337393A0F060721F91E0E142FC002111717
        hex 19120908133C242424EF8181F90F022D332D3D1207071FF13E0C5C28DF000310
        hex 11180F10171A090D24FFF400AFE7401A04C3E79427A101F8033943445758591A
        hex 0A0A167FD01DF6459066DD960589FFC0042F373E4A303A444E190A0921FF40AF
        hex 542BBD0603E3170E000429393A3C1E1F204C17060D251FFF8660030398F7FC00
        hex 041D1E1F242021222318061349F8F011F202007FF3C01249E279E7C0022E441D
        hex 4319090A397E30882208E7CD11044F1E0004182122432C36404A1809093C3F10
        hex 884F2C142E03917F8004172027292E2F30311B0E090D1C0A1DD8394D168B4594
        hex E0D8C44221F0031654561F5D5F12080716F91A943C29589F0317182618192014
        hex 070A357813FC064197E10FC0031A232C202A3416080B38F3D3CA494838233460
        hex 8FFF0329333F2F3146170A080AF88F8181D98F82C2721E041A1C1D2232333A3B
        hex 18090D1DFFE411E0836EDA02D116FFB001FFF8021C1E2225190B0A1B3C19F405
        hex 11F7E44812248F260F0003182241484953150A082DF09F8181DB8ABB8191FF03
        hex 121315292A2B18080B1A7809FD10E8183317F881F0041825262F1F2A34351607
        hex 0A267F3068FE01E04E10FC0422242D2F0D0E0F10190B0A297C31087E51946538
        hex 4B326089E3C0032F4C4D222C3617070B0DFFD00A3DE814028FDF00041E27292F
        hex 0F1011121A080B397F183202404DDE805839FC05191B2325273C3D3E3F401306
        hex 0A247FD09CA601887FF00317192221232B1B0B0A4AF027F86641DA5097A48721
        hex 0843F004204B5455171C2630120906217D14718E3C517C03151B270F151B1308
        hex 082AF88E83D1919B82FE031A1C25121A22170A083BFC8683C1515B41414F7804
        hex 12141B1C34363C3E1A0A0C34FF08109D8908D085085DF4014717DF032935410F
        hex 10111B0B0B5001EFE500A015FFA125240CD50821FC00031926283C5268160809
        hex 260F1CD838590C1E39F004161E28292F303839190A094C07FE60301DFC221D82
        hex 611F8004262F3A431E1F20221C0C0B65078B9142294528A554A895F2B01626FF
        hex 800330465C33495F19090A1AFFE31817D114D52509421F8004161925392C3640
        hex 4A16070A0E7F90240BB780601FFC04171A2B2E2C2D363714050B1AFFF06600C6
        hex 1FFE0418191D1E101B1C271E0A0F743C00487C90893F5F00305D6228FFD30024
        hex 007803424F50384756250B0B3C7FD88E10C21803E3E00C2184388DFF00082428
        hex 3032464850543031323B3D4647481408090BFFC4603BB80C47F20F0314161D27
        hex 28291D080809FF818181818181FF0813141A1D22252B2C12151B1C23242A2D1B
        hex 0B0B3C3F0420847C88BF007E88DB1042387C00033B3D5F314760210A0E391E00
        hex 4FFF00603FBB820808A034804201F8000521232E49562425262728230A106DF8
        hex 008DE087208020CFAF85398521E5013D8300FE0523323643522939495969290A
        hex 165B0001F000044FE7F520920483C83E4037987D807F1001004FFC01E0000492
        hex 939597767778791508080AFE928293919191FF04121D222D11192129250D0D61
        hex 3E01100AFE4113629047AAF104A364413FA804403E00052C4A5E607C2C4A5E61
        hex 7C18080B24FFF08640C19833F841083F041D1E343F0C0D0E0F1508081E3E23E1
        hex 85A187C47C04141C232B0C1A2533160909220FFC60315E8904E6120F0003171E
        hex 20313233250B0B3C7BD9CE28C01E0E80B83C018A39CDEF000824282F33454950
        hex 5424252728505153541B090A167F90240B7281E01FD41107C0051A243436382A
        hex 2B2C2D2E23080836FF818181818181FF0B121314151A1D22252A2B2C1314151A
        hex 1D22252A2B2C2D1C080F3FF07D388E110CBE98083200F1FF3E0004282A46482E
        hex 2F4C4D1E0D091F3FD06AA41EEC761B8560D976BD1EF8052138424C563D464F58
        hex 61180909443C1209FC188C1FC8241E000416262A3A1E2030321F0C0943FC43E0
        hex 301FC924864120994423F0063A3B444C4D56171819202122200D0A5D7C31E80A
        hex 8286F91245F745902409127F8005171819242C385E5F6061240D0E591F00C40E
        hex 5020409BE204C901FE410F04063009802400F0045B6C7A882F494B671E090B26
        hex FC10E244408DBF20600E3F7C00061B244446484A3B3C3D3E3F401B080C400F8F
        hex 8F821901CD740441C7F0053E3F41424328292A2B2C18070A2007C71F060182FE
        hex 20F805212223242518191A1B1C1D0A0B1E7BC9CD00E71813116C0C07F383C005
        hex 3C47484A50232438393A1A0A0A497C31883206E8CA16C503449FE0041720222B
        hex 2E38424C170A09273F10DB28542A17D303837F00031E1F284243441D0B0B2F03
        hex DFCA01CF9893B0647C389C1203C0000418234F5A3C3D47481F0B0B5C7E084328
        hex 4108E197F68CF5803905FF80051824395E600E19242E2F200C0B45F811C28841
        hex 0821242386FF803007FC80F00519232E30395F60617677240B0F33FF01020207
        hex FFCC10882110C2B5040209CC12F03C0005202223415F36384654561B090E1FFF
        hex FE04181076ED50154455FF50017FFC031E20212527281A080D3103E0118085FE
        hex B840C0163E3F1F04223B3D4A364F50511E070C217FFC018018ABA828FEF80007
        hex 1A1B1C1D1E1F200E0F101112131419090A3EDE3CF407418DE0288A7EF0000417
        hex 1925351A242E3818080B3B3FFC4600C1BF448391C3E004181A2530181C1E301A
        hex 080B0F3FFC4600C11F4E8311C3E005181A1C2530181C1D1E3018070C34F9F8F1
        hex 801841E4D2613FF0041A1B1C2814152C2D170B0717F912247D3060E14E91E004
        hex 262C33341016181E17080A0CF027087E41C055947DF0041622232515161F2019
        hex 080A2B7F107407BD80601F1C7C052C2F3536390E1017191B1C0A0C5800FFF98C
        hex 1819E8B28B28920127F3C0041F27455A3537414317070B1BFE107E2CD01853E0
        hex 47F80418192F3C1E1F3F40160809217F20B770184D861FF804181D2A331C2627
        hex 2E1E0A0D4801E019FC833C1828C81F4B8B504083FC0004232F313D3839525320
        hex 0B0C323C0E40870A1081EAA3881F810CB04207E0054E4F5B5D66282A34353629
        hex 0C10557800CF00810081008B0089EFF83909811C0110C710FC1F800666797B8B
        hex 8C952425263435361D090E2EFF7E47181868C3A21A80C9BE30807E0004263340
        hex 4D2B3947551D090A4A3FC9120491F6E018C611FFC0061B252C393E43111A1B1C
        hex 252F180909283C1209FC180C1FC8241E00041E2030321F272931220F0967F04F
        hex 2092496423D0287720B570188F1CF8061426555E65691D2F6E6F7172370C0C65
        hex 1E073E422403421E81817842C024427CE078101B1C272C2D3941424D4E566263
        hex 687374292B3334374142444B4D4E585B5C64662D0B0B101F0220C67078030860
        hex 0F073182207C000C2526272F333A3E454951525324283031323B3D4647485054
        hex 280909287F60E030180C0603837F000C1516171D21262A2F33393A3B0D14181E
        hex 20252B3032383C431A0A0C2001FFF18059C1C2141F4906902303E003333F4B19
        hex 1D221B070F24FFE10442808497FCC02C004FFF800443444648122131321C0C0A
        hex 1578338823884FD014BDA84A1084E1E004162236533738393A1E080F460780F9
        hex 0103FEC41820300E7F9781E005253E404143333438393A1C0A0C5A1E0120720C
        hex 208A0A3FA21801E793CF04283F4057525E696A1E090F6CFDE10422CB244128B9
        hex 34096BCAC001FFFE04253D71731F6A73752A0A0D11FFFD246823491A49D24A92
        hex 50828497FF800A1D1E242E383E485258620E1B2835424F5C5D696A
level_data_end


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; music data
; this is supposed to be Beethoven's moonlight sonata

		IFCONST MUSIC
music_data
        hex 001DB31E8000631E681EB300001E8000631E681EB300001E8000631E681E8100
        hex 5C1E631E681E5C1E631E681D800181005C1E651D00026A1E5C1E651E6A1D8001
        hex B300001E8000611E6A1EB300001E8000631E681EB300001E8000631E661EAA00
        hex 001E8000611E661E9F00001EB31E8000631EB300001E8000631E681EB300001E
        hex 8000631E681EB3006D1E8000631E68086D17B3006D1E8000661E6A1EB300001E
        hex 8000661E6A1EB300001E8000661E6A1D0001B3006D1E8000661E6A086D17B300
        hex 6D1E8000631E681EB300001E8000631E681D000181006E1E6301001D6A1E5C1E
        hex 631E6A1D80000001B3006D1E8000601E681EB300001E8000601E681D6A010001
        hex 81005C1E6007001766175C070001701E601E661D80000001B300681E8000601E
        hex 681D0001B31E8000601E681EB300001E8000601E681EB300001E8000601E681E
        hex AE00001E8000601E681EAE00001E8000601E681EAE00001E8000601E681EAE00
        hex 6C1E8000601E68086C17AE006C1E8000601E691EAE00001E8000601E691EAE00
        hex 001E8000601E691D0001AE006C1E8000601E69086C17AE006C1E8000611E681E
        hex AE00001E8000601E681EAE00001E8000631E681D0001AA006A1E8000631E681D
        hex 0001AA006A1E8000601E651EAA00001E8000601E651D0001AE006C1E8000601E
        hex 631D00019F00681E8000601E631D0001AA006A1E8000601E651EAA00001E601E
        hex 651D80000001AA006A1E80005E1E631EAA00001E80005E1E631E81006001001D
        hex 651E6A1E601E651E6A1E601E661E6A1E701E661E6A1760070001711D0001681E
        hex 6C1D80019F00601D681E00026C0B00138001AE00601E681E6C1D800000019F00
        hex 6F1E681E6C1D800000018100701E661E6A1E601E661E6A1E601E661E6A1D0001
        hex 701E661E6A06001160070001711E8000681E6C1E9F00601E681E6C1D8001AE00
        hex 601E681E6C1D800000019F006F1E681E6C1D800000018100701E661E6A1E601E
        hex 661E6A1D800000018100701E651E691E601E651E691D800000018100701E631E
        hex 6D1E601E631E6D1D8000000181006E1E631E6A1E5C1E631E6A1D80000001AE00
        hex 6C1E8000601E651EAE00001E8000601E651D0001AA006A1E80005C1E661EAA00
        hex 001E80005C1E661D00018D00631EAA1E80005C1E8D00001EAA1E80005C1D0001
        hex 8D00631EAA1EB31D800000018D00631EA41EB31D0001AA1E80005C1E631E5C1E
        hex 631E6A1E631E6A1E6E1E721E6A1E6E087217A400721E6D01001D701E631E6D1E
        hex 701D0001631E6D1E701E721E6D1E700872168001AA00721E6A1E6E1E631E6A1E
        hex 6E1D800000019900711E6A1E6E1D800000018D00721E6A1E6E1D800000018600
        hex 731E6A1E6D1E661E6A1E6D1E661E6A1E6D1D800000018600731E6A1E6D1D8000
        hex 00018D00741E6D1E721E681E6D1E721D80018100731E6A1E6E1D800000018100
        hex 721E681E6F1D800000018100711E611E661D00016D1E611E661D00016E1D611E
        hex 0002661D00016A1D611E0002661D80000001811E861E991EB31E861E991D8001
        hex 5C1D861E8002991D0001AA1E861E991D80019F1E8000681D6D02001E721E681E
        hex 6D1D0001741E681E6D1D0001721D681E00026D1D0001811E9F1EB31E8000631E
        hex 9F1EB31D00018000681E9F1EB31D00018000631E9F1EB31D80000001991E8000
        hex 5C1EAA00001E8000611E5C1E661E611E6A1E661E6E1E6A1E711E9F00001E8000
        hex 631EB300001E8000681E631E6D1E681E721E6D1E741E721E6D1E8100631E6C1E
        hex 681E6F1E6C1E721E6F1E741E721E761E741E771D800181006A1E711E6E1E731E
        hex 711E751E731E771E751E781E004B804BFF
music_data_end
		ENDIF


; ----------------------------------------------------------------------

	IFCONST EXP3k
hole	equ	charmem-.
		ALLOCATE_CHARACTERS
	ENDIF

;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; memory area for uncompressed level
; it it's the last section it does not increase binary size (uninitialized memory)

lvl_unpack
		seg.u level_unpack
		org lvl_unpack
level_map	ds MAX_LEV_ROUND  ; max size of levels, rounded to bitmap size


;
fulllimit
		; check safe limit of full code
		IF fulllimit > ramend
			ERR
		ENDIF


; TODO
; autoscrolling
; annotate all routines



;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; macro to allocate user-defined characters at different points in code

	mac ALLOCATE_CHARACTERS
chunk1end  ; end of previous code

; for 3k expansion: characters allocated at $1c00 (program too large to
;  copy them at run-time from another position); code must be all before characters,
;  plus another usable memory area between character and video memory.
; for 8k expansion: characters allocated at $1c00, code must be split
;  in 2 chunks, before and after user characters

	; test previous code does not overlap characters
	IF chunk1end > charmem
		ERR
	ENDIF
	org charmem

udcstart
		; wall 0,1,2,3
		dc %11111100,%11111110,%11111110,%11111110,%10111110,%11111110,%11111100,%00000000
		dc %01111111,%11101111,%11111111,%11111111,%11111111,%11111111,%01111111,%00000000
		dc %01111111,%11111111,%11111111,%11111011,%11111111,%11111111,%01111111,%00000000
		dc %11111100,%11111110,%11111110,%11111110,%11110110,%11111110,%11111100,%00000000
		; stone 4,5,6,7
		dc %00000000,%00000011,%00001111,%00011111,%00011111,%00111111,%00111111,%00111111
		dc %00000000,%11000000,%11110000,%10011000,%11001000,%11001100,%11101100,%11111100
		dc %00111111,%00111111,%00111111,%00010111,%00011011,%00001111,%00000011,%00000000
		dc %11111100,%11111100,%11111100,%11111000,%11111000,%11110000,%11000000,%00000000
		; goal 8,9,10,11
		dc %00000000,%00000000,%00100000,%00010000,%00001011,%00000100,%00001001,%00001011
		dc %00000000,%00000000,%00000100,%00001000,%11010000,%00100000,%10010000,%11010000
		dc %00001011,%00001001,%00000100,%00001011,%00010000,%00100000,%00000000,%00000000
		dc %11010000,%10010000,%00100000,%11010000,%00001000,%00000100,%00000000,%00000000
		; goal+stone 12, 13, 14, 15 (multicolor)
		dc %00000000,%00000010,%11001010,%00111010,%00111010,%00101010,%00101010,%00101010
		dc %00000000,%10000000,%10100011,%10101100,%00101100,%10001000,%10001000,%10101000
		dc %00101010,%00101010,%00101010,%00110010,%00111010,%11001010,%00000010,%00000000
		dc %10101000,%10101000,%10101000,%10101100,%10101100,%10100011,%10000000,%00000000
		; man 16,17,18,19 (multicolor)
		dc %00001010,%00001000,%00001000,%00000010,%00001010,%00101010,%10101010,%10001010
		dc %10100000,%00100000,%00100000,%10000000,%10100000,%10101000,%10101010,%10100010
		dc %10001010,%10000101,%10000101,%00000101,%00000101,%00000101,%00000101,%00000101
		dc %10100010,%00010010,%00010110,%00010100,%00010100,%00010100,%00010100,%00010100
		; man+goal 20,21,22,23 (multicolor)
		dc %00001010,%00001000,%00111000,%00110010,%00001010,%00101010,%10101010,%10001010
		dc %10100000,%00100000,%00101100,%10001100,%10100000,%10101000,%10101010,%10100010
		dc %10001010,%10000101,%10000101,%00000101,%00110101,%00110101,%00000101,%00000101
		dc %10100010,%00010010,%00010110,%11010100,%11010100,%00010100,%00010100,%00010100
		; 24: wall, variant1
		dc %01111100,%11111110,%11111110,%11111110,%11111110,%11111110,%01111100,%00000000
		; 25: wall, variant2
		dc %01111100,%11101110,%11111110,%11111110,%11111110,%11111110,%01111100,%00000000
udcend
	endm
