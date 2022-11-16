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
scrn_ptr	ds 2  ; pointer for screen memory (X or Y register not enough to sweep all screen)
i			ds 1  ; generic temp. variable
j			ds 1  ; generic temp. variable
k			ds 1  ; generic temp. variable
goto_lev	ds 1  ; target random level to load
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


; tape buffer area, 192 bytes (maybe some more before and after)
		seg.u tapebuffer
		org 828

;
tpbuflimit
		; check safe limit of allocated area
		IF tpbuflimit > 1020
			ERR
		ENDIF

; ----------------------------------------------------------------------

; start of code

		seg code
		org ramstart+1

		; basic stub to launch binary program
		byte 11,16,10,0,158,sysaddr,0,0,0  ; 10 SYSxxxx

start
		; we don't return to basic, so use the full stack
		ldx #255
		txs

		jsr level_ptr_reset
		; start with level 1 loaded
		jsr level_ptr_next
start_level
		jsr draw_level
wait_input
		jsr getchar
		cmp #'N
		beq go_next
		cmp #29
		beq go_next
		cmp #'P
		beq go_prev
		cmp #157
		beq go_prev
		jmp wait_input
go_next
		lda level
		cmp #LEV_NUM
		beq wait_input
		sta goto_lev
		inc goto_lev
		jsr level_find
		jmp start_level
go_prev
		lda level
		beq wait_input
		sta goto_lev
		dec goto_lev
		jsr level_find
		jmp start_level


;l1		jsr level_ptr_next
;		jsr draw_level
;		jsr getchar
;		lda level
;		cmp #153
;		bne l1

hang	jmp hang


;map_char	dc 32, 102, 46, 63, 36, 63, 42, 63, 0, 63, 43

map_char4	dc 32, 32, 32, 32  ; empty
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


level_ptr_reset
		SUBROUTINE
		lda #<level_data
		sta level_ptr
		lda #>level_data
		sta level_ptr+1
		lda #0
		sta level  ; invalid level
		rts


level_find
		SUBROUTINE
		jsr level_ptr_reset
.loop	jsr level_ptr_next
		lda level
		cmp goto_lev
		bne .loop
		rts


level_ptr_next
		; level must be < LEV_NUM
		SUBROUTINE
		inc level
		ldy #0
		lda (level_ptr),y
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
		; set man at proper position
		ldx man
		lda level_map,x
		ora #bMAN
		sta level_map,x
		; update level_ptr with offset y
		tya
		clc
		adc level_ptr
		sta level_ptr
		bcc .l6a
		inc level_ptr+1
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


draw_level
		SUBROUTINE
		jsr clearscreen
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
		lda map_char4,x  ; character for this cell value
		sta (scrn_ptr),y  ; first char
		iny
		inx
		lda map_char4,x
		sta (scrn_ptr),y  ; second char
		tya
		clc
		adc #21
		tay
		inx
		lda map_char4,x
		sta (scrn_ptr),y  ; third char
		iny
		inx
		lda map_char4,x
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
; space character
		lda #32+CHAR_OFF
		ldy #253
.loop1	dey
		sta video,y
		sta video+253,y
		bne .loop1
; color
		lda #6
		ldy #253
.loop3	dey
		sta vcolor,y
		sta vcolor+253,y
		bne .loop3
		rts


; format for each level:
; [tot][rows][cols][man][wall bitmap]...[num_stones][stone]...[goal]...


level_data
        hex 070614F249E1867F0002131B081307060FFE1A61861FC00314151B151A1B0609
        hex 2A3C73E034984FFC0218212628060816FF818181F90F0313141512131407081C
        hex 7F4141C18181FF04141B1D2413152325060C22FDF8718058818FFF80031A1B26
        hex 292A2B08072DFF060C183060FF061117191F25271012181E20260C080E3F2121
        hex 371414F486A28AE23E0214150C0D07060DFA387164D1C0020E0F0722080B2E03
        hex E0440AFF580355E027FC03303234121D280809183F108B7D188C067FE002212A
        hex 2627080928F8462118F70914827F02141E2932090710F132244CE850A7780318
        hex 1E26080F1606071AFF06AC18FF00021819161907090F077EE0311FA8443E0218
        hex 291718080A2E7813C41B6288E21887FF032F3839292B3F070608FA28A3861FC0
        hex 031314150D0E0F09072DFF060DB85C89123C021F260F11080813FF8181FB1212
        hex 121E0214150C0D080915FE41E03ED2093C9078021617181906071AF13E0C5C2F
        hex C00217181012090725F91E0C5D2850A7780226270F1107071FFF060EB4489F00
        hex 020A1E0A20070713BE478C78307F80021112252707071F789D0E1831FE000311
        hex 12201718190806097D1479861E4F031520211A1B1C07071AFD0ADC1A31FE0002
        hex 18190B24070710F912247C285F800217181E20090B3D07C08C10BF1C1300EFD4
        hex 02FFC002393B344A07061AF27861863F80030E0F1B1314150707103CCB1C183C
        hex 4F8003111718121E2007071A799E0C18F91E000317181916171807071AFF260C
        hex 58327F800311181F08162406091C3C73E030180FFC041D1E1F201E1F20210A07
        hex 363CC912244891A1627C0512181F262E10171E252C050F2AF0013FFE000C001F
        hex FFE00520222426282F3031323308093203FD63B0580FD4221F031F2629101922
        hex 070A2CFFE01B7681837E10FC0322232D18252A090A37F823CA9207E8621AFE20
        hex F80002232D1A2E06071F7C8B1C183FC0031718191E1F20060811FE828391C37E
        hex 031213141C1D1E0807121E244F983461FE031920271A21280909100782413F98
        hex 0C261FC83C0003283031222B34030506FC7E010708070621FE186B861FC0030F
        hex 151B0708090807277F866D183AD13E02191F1F21070B2E3F9C12025DF8031C7E
        hex F802181A303208080BFC8496938191F11F032324251A222A0A080AFC8494848C
        hex EF4941417F03121A223A3B3C070A1A3C39F80605EF4813FC0217201B1C07081D
        hex F09C8781E5213F021B1C1C2408060A3F9861861E4F040F151B2115161B1C0707
        hex 267D8E0C9838DF000410121E20090B1012080C3E03F0213E1E71803822C3E7E0
        hex 0432353F40202C3844080A0CFF224813E409DA169C3C022337393A060721F91E
        hex 0E142FC002111717190908133C242424EF8181F90F022D332D3D07071FF13E0C
        hex 5C28DF00031011180F1017090D24FFF400AFE7401A04C3E79427A101F8033943
        hex 445758590A0A167FD01DF6459066DD960589FFC0042F373E4A303A444E0A0921
        hex FF40AF542BBD0603E3170E000429393A3C1E1F204C060D251FFF8660030398F7
        hex FC00041D1E1F2420212223061349F8F011F202007FF3C01249E279E7C0022E44
        hex 1D43090A397E30882208E7CD11044F1E0004182122432C36404A09093C3F1088
        hex 4F2C142E03917F8004172027292E2F30310E090D1C0A1DD8394D168B4594E0D8
        hex C44221F0031654561F5D5F080716F91A943C29589F03171826181920070A3578
        hex 13FC064197E10FC0031A232C202A34080B38F3D3CA4948382334608FFF032933
        hex 3F2F31460A080AF88F8181D98F82C2721E041A1C1D2232333A3B090D1DFFE411
        hex E0836EDA02D116FFB001FFF8021C1E22250B0A1B3C19F40511F7E44812248F26
        hex 0F00031822414849530A082DF09F8181DB8ABB8191FF03121315292A2B080B1A
        hex 7809FD10E8183317F881F0041825262F1F2A3435070A267F3068FE01E04E10FC
        hex 0422242D2F0D0E0F100B0A297C31087E519465384B326089E3C0032F4C4D222C
        hex 36070B0DFFD00A3DE814028FDF00041E27292F0F101112080B397F183202404D
        hex DE805839FC05191B2325273C3D3E3F40060A247FD09CA601887FF00317192221
        hex 232B0B0A4AF027F86641DA5097A487210843F004204B5455171C26300906217D
        hex 14718E3C517C03151B270F151B08082AF88E83D1919B82FE031A1C25121A220A
        hex 083BFC8683C1515B41414F780412141B1C34363C3E0A0C34FF08109D8908D085
        hex 085DF4014717DF032935410F10110B0B5001EFE500A015FFA125240CD50821FC
        hex 00031926283C52680809260F1CD838590C1E39F004161E28292F3038390A094C
        hex 07FE60301DFC221D82611F8004262F3A431E1F20220C0B65078B9142294528A5
        hex 54A895F2B01626FF800330465C33495F090A1AFFE31817D114D52509421F8004
        hex 161925392C36404A070A0E7F90240BB780601FFC04171A2B2E2C2D3637050B1A
        hex FFF06600C61FFE0418191D1E101B1C270A0F743C00487C90893F5F00305D6228
        hex FFD30024007803424F503847560B0B3C7FD88E10C21803E3E00C2184388DFF00
        hex 0824283032464850543031323B3D46474808090BFFC4603BB80C47F20F031416
        hex 1D272829080809FF818181818181FF0813141A1D22252B2C12151B1C23242A2D
        hex 0B0B3C3F0420847C88BF007E88DB1042387C00033B3D5F3147600A0E391E004F
        hex FF00603FBB820808A034804201F8000521232E495624252627280A106DF8008D
        hex E087208020CFAF85398521E5013D8300FE05233236435229394959690A165B00
        hex 01F000044FE7F520920483C83E4037987D807F1001004FFC01E0000492939597
        hex 7677787908080AFE928293919191FF04121D222D111921290D0D613E01100AFE
        hex 4113629047AAF104A364413FA804403E00052C4A5E607C2C4A5E617C080B24FF
        hex F08640C19833F841083F041D1E343F0C0D0E0F08081E3E23E185A187C47C0414
        hex 1C232B0C1A25330909220FFC60315E8904E6120F0003171E203132330B0B3C7B
        hex D9CE28C01E0E80B83C018A39CDEF000824282F33454950542425272850515354
        hex 090A167F90240B7281E01FD41107C0051A243436382A2B2C2D2E080836FF8181
        hex 81818181FF0B121314151A1D22252A2B2C1314151A1D22252A2B2C2D080F3FF0
        hex 7D388E110CBE98083200F1FF3E0004282A46482E2F4C4D0D091F3FD06AA41EEC
        hex 761B8560D976BD1EF8052138424C563D464F58610909443C1209FC188C1FC824
        hex 1E000416262A3A1E2030320C0943FC43E0301FC924864120994423F0063A3B44
        hex 4C4D561718192021220D0A5D7C31E80A8286F91245F745902409127F80051718
        hex 19242C385E5F60610D0E591F00C40E5020409BE204C901FE410F040630098024
        hex 00F0045B6C7A882F494B67090B26FC10E244408DBF20600E3F7C00061B244446
        hex 484A3B3C3D3E3F40080C400F8F8F821901CD740441C7F0053E3F41424328292A
        hex 2B2C070A2007C71F060182FE20F805212223242518191A1B1C0A0B1E7BC9CD00
        hex E71813116C0C07F383C0053C47484A50232438393A0A0A497C31883206E8CA16
        hex C503449FE0041720222B2E38424C0A09273F10DB28542A17D303837F00031E1F
        hex 284243440B0B2F03DFCA01CF9893B0647C389C1203C0000418234F5A3C3D4748
        hex 0B0B5C7E0843284108E197F68CF5803905FF80051824395E600E19242E2F0C0B
        hex 45F811C288410821242386FF803007FC80F00519232E30395F606176770B0F33
        hex FF01020207FFCC10882110C2B5040209CC12F03C0005202223415F3638465456
        hex 090E1FFFFE04181076ED50154455FF50017FFC031E2021252728080D3103E011
        hex 8085FEB840C0163E3F1F04223B3D4A364F5051070C217FFC018018ABA828FEF8
        hex 00071A1B1C1D1E1F200E0F1011121314090A3EDE3CF407418DE0288A7EF00004
        hex 171925351A242E38080B3B3FFC4600C1BF448391C3E004181A2530181C1E3008
        hex 0B0F3FFC4600C11F4E8311C3E005181A1C2530181C1D1E30070C34F9F8F18018
        hex 41E4D2613FF0041A1B1C2814152C2D0B0717F912247D3060E14E91E004262C33
        hex 341016181E080A0CF027087E41C055947DF0041622232515161F20080A2B7F10
        hex 7407BD80601F1C7C052C2F3536390E1017191B0A0C5800FFF98C1819E8B28B28
        hex 920127F3C0041F27455A35374143070B1BFE107E2CD01853E047F80418192F3C
        hex 1E1F3F400809217F20B770184D861FF804181D2A331C26272E0A0D4801E019FC
        hex 833C1828C81F4B8B504083FC0004232F313D383952530B0C323C0E40870A1081
        hex EAA3881F810CB04207E0054E4F5B5D66282A3435360C10557800CF0081008100
        hex 8B0089EFF83909811C0110C710FC1F800666797B8B8C95242526343536090E2E
        hex FF7E47181868C3A21A80C9BE30807E00042633404D2B394755090A4A3FC91204
        hex 91F6E018C611FFC0061B252C393E43111A1B1C252F0909283C1209FC180C1FC8
        hex 241E00041E2030321F2729310F0967F04F2092496423D0287720B570188F1CF8
        hex 061426555E65691D2F6E6F71720C0C651E073E422403421E81817842C024427C
        hex E078101B1C272C2D3941424D4E566263687374292B3334374142444B4D4E585B
        hex 5C64660B0B101F0220C670780308600F073182207C000C2526272F333A3E4549
        hex 51525324283031323B3D46474850540909287F60E030180C0603837F000C1516
        hex 171D21262A2F33393A3B0D14181E20252B3032383C430A0C2001FFF18059C1C2
        hex 141F4906902303E003333F4B191D22070F24FFE10442808497FCC02C004FFF80
        hex 0443444648122131320C0A1578338823884FD014BDA84A1084E1E00416223653
        hex 3738393A080F460780F90103FEC41820300E7F9781E005253E40414333343839
        hex 3A0A0C5A1E0120720C208A0A3FA21801E793CF04283F4057525E696A090F6CFD
        hex E10422CB244128B934096BCAC001FFFE04253D71731F6A73750A0D11FFFD2468
        hex 23491A49D24A9250828497FF800A1D1E242E383E485258620E1B2835424F5C5D
        hex 696A
level_data_end


lvl_unpack
		seg.u level_unpack
		org lvl_unpack
level_map	ds MAX_LEV_ROUND  ; max size of levels, rounded to bitmap size
levmaplimit
