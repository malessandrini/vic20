	processor 6502

	IFCONST EXP3k
		;ECHO "*** 3k"
	ELSE
		IFCONST EXP8k
			;ECHO "*** 8k"
		ELSE
			ECHO "ERROR: no expansion type declared"
			ERR
		ENDIF
	ENDIF

; configuration for 3k expansion:
;  $0400 - $1bff(max): code + level data, 6144 bytes (level data = 3675 bytes)
;  $1c00: user-defined characters (convenient because falls back to character ROM by adding 128)
;   (possibly moved in place at startup if final binary is shorter)
;  $1e00: video memory
;
; configuration for 8k expansion:
;  $1000: video memory
;  $1200 - $1bff: code, 2560 bytes
;  $1c00 - $nnnn: user-defined characters (see note above)
;  $nnnn+1 - $3fff(or more for bigger expansions): level data + extra code
;  (user-defined chars and level data may be moved in place at startup if final binary is shorter)


;=======================================================================
; ----------------------------------------------------------------------
;=======================================================================
; constants

	IFCONST EXP3k
ramstart	equ $0400
video		equ $1e00   ; video memory
vcolor		equ $9600  ; color memory
sysaddr		equ	"1037"
	ENDIF
	IFCONST EXP8k
ramstart	equ $1200
video		equ $1000   ; video memory
vcolor		equ $9400  ; color memory
sysaddr		equ	"4621"
	ENDIF
GETIN		equ $ffe4  ; kernal, read keyboard input from queue

LEV_NUM			equ 153
MAX_LEV_SIZE	equ 220
MAX_LEV_BMP		equ [220 + 7] / 8
MAX_LEV_ROUND	equ MAX_LEV_BMP * 8

bEMPTY		equ 0
bWALL		equ 1
bGOAL		equ 2
bSTONE		equ 4
bMAN		equ 8

CHAR_OFF	equ 0  ; added to character code to switch to default character ROM

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
		; enable repeat for all keys
		lda #128
		sta 650
		; disable shift+commodore character switch
		lda 657
		ora #128
		sta 657

		; start with level 1
		lda #1
		sta level

		jmp main_menu


; ----------------------------------------------------------------------

main_menu
		jsr clearscreen
		prn_str video+22*1+5, str_main1
main0	jsr getchar
		cmp #32
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
		adc #1  ; printable code (starting from 'A')
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
		jsr load_level
		; TODO: clear game variables
redraw_level
		jsr draw_level
wait_input
		jsr getchar
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
		beq go_next
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
		beq start_level
		jmp wait_input
move_up
		lda #0
		sec
		sbc cols  ; -cols
		jmp move_n
move_down
		lda cols
		jmp move_n
move_left
		lda #-1
		jmp move_n
move_right
		lda #1
		jmp move_n
go_next
		lda level
		cmp #LEV_NUM
		beq wait_input
		inc level
		jmp start_level
go_prev
		lda level
		cmp #1
		beq wait_input
		dec level
		jmp start_level

trmpl1	jmp wait_input

scroll_up
		lda map_r
		beq wait_input
		dec map_r
		jmp redraw_level
scroll_down
		lda map_r
		cmp delta_r
		beq wait_input
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
move_n
		sta i  ; save increment in case of stone push
		clc
		adc man
		tax  ; x = new wanted position
		lda #0
		sta k  ; flag: level completed
		lda level_map,x
		cmp #bWALL
		beq trmpl1
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
		lda k  ; completed?
		bne level_complete
		jmp redraw_level


; ----------------------------------------------------------------------

level_complete
		SUBROUTINE
		jsr draw_level  ; draw with last (winning) move
		lda #90
		jsr delay_jiffy
		; increment level and load new level, including secret code
		lda level
		cmp #LEV_NUM
		beq .l1
		inc level
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
		jsr getchar
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
		jmp start_level


; ----------------------------------------------------------------------

map_char
		dc 32, 32, 32, 32  ; empty
		dc 102, 102, 102, 102  ; wall
		dc 85, 73, 74, 75  ; goal
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 78, 77, 77, 78  ; stone
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 78, 77, 95, 105  ; stone + goal
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 87, 32, 89, 77  ; man
		dc 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF, 63+CHAR_OFF  ; invalid
		dc 81, 73, 89, 75  ; man + goal
map_color
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6
		dc 6, 6, 6, 6

str_main1	dc "***********", 10
			dc "*", 8,   "*", 10
			dc "* SOKOBAN *", 10
			dc "*", 8,   "*", 10
			dc "***********", 30, 30, 9
			dc "SPACE: START LEVEL", 25
			dc "C: ENTER LEVEL CODE", 24
			dc "H: HELP", 0

str_help1	dc "IN-GAME CONTROLS", 22, 22, 22
			dc "ARROWS,JOYSTICK: MOVE ", 21
			dc "W,A,S,Z: SCROLL VIEW", 23
			dc "N,P: NEXT/PREV. LEVEL", 22
			dc "U,FIRE: UNDO MOVE", 26
			dc "R: REDO MOVE", 31
			dc "F1: EXIT TO MENU", 27
			dc "F7: RESET LEVEL", 28
			dc "H: THIS HELP", 0

str_lev_code
			dc "CODE FOR LEVEL    :", 0

str_enter_code
			dc "ENTER CODE:", 22, 24, 30, "------", 0


; ----------------------------------------------------------------------

load_level
		; input: level (must be in range 1..LEV_NUM)
		SUBROUTINE
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
.l8		rts


; ----------------------------------------------------------------------

draw_level
		SUBROUTINE
		;jsr clearscreen
		lda #<[video+22]
		sta scrn_ptr
		lda #>[video+22]
		sta scrn_ptr+1
		; increment row according to scr_r
		ldx scr_r
		beq .l1a
.l1		lda #44
		clc
		adc scrn_ptr
		sta scrn_ptr
		bcc .l1p
		inc scrn_ptr+1
.l1p	dex
		bne .l1
		; increment column according to scr_c
.l1a	lda scr_c
		asl
		clc
		adc scrn_ptr
		sta scrn_ptr
		bcc .l1q
		inc scrn_ptr+1
.l1q
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
		asl
		asl
		tax
		lda map_char,x  ; character for this cell value
		sta (scrn_ptr),y  ; first char
		iny
		inx
		lda map_char,x
		sta (scrn_ptr),y  ; second char
		tya
		clc
		adc #21
		tay
		inx
		lda map_char,x
		sta (scrn_ptr),y  ; third char
		iny
		inx
		lda map_char,x
		sta (scrn_ptr),y  ; fourth char
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
		; update scrn_ptr on next line
		lda #44
		clc
		adc scrn_ptr
		sta scrn_ptr
		lda #0
		adc scrn_ptr+1
		sta scrn_ptr+1
		dec i
		bne .lr
		; print level number
		lda #12+CHAR_OFF  ; 'L'
		sta video
		lda #<[video+1]
		sta scrn_ptr
		lda #>[video+1]
		sta scrn_ptr+1
		lda level
		jsr print_decimal
		rts


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
		sta i
		ldx #0  ; remainder
		; first, divide by 100 to find first digit
.hundr	lda i
		sec
		sbc #100
		bcc .l1  ; if negative, stop subtracting
		sta i
		inx
		jmp .hundr
.l1		txa
		adc #48+CHAR_OFF  ; C is already clear
		ldy #0
		sta (scrn_ptr),y  ; first digit
		ldx #0
.tenth	lda i
		sec
		sbc #10
		bcc .l2  ; if negative, stop subtracting
		sta i
		inx
		jmp .tenth
.l2		txa
		adc #48+CHAR_OFF  ; C is already clear
		iny
		sta (scrn_ptr),y  ; second digit
		lda i  ; remainder, third digit
		adc #48+CHAR_OFF
		iny
		sta (scrn_ptr),y  ; third digit
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

clearscreen
		SUBROUTINE
		; screen and border color
		lda #11
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
; memory area for uncompressed level

lvl_unpack
		seg.u level_unpack
		org lvl_unpack
level_map	ds MAX_LEV_ROUND  ; max size of levels, rounded to bitmap size
levmaplimit
