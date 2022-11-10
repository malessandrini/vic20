	processor 6502

	IFCONST EXP3k
		ECHO "*** 3k"
	ELSE
		IFCONST EXP8k
			ECHO "*** 8k"
		ELSE
			ECHO "ERROR: no expansion type declared"
			ERR
		ENDIF
	ENDIF

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


; variables in zero page
;
; we overwrite the Basic variable area, but leave kernal area untouched
; because the kernal is always executing through interrupts (e.g. keyboard
; reading). This gives us 144 bytes.

		seg.u zpvars
		org 0
i			ds 1

;
zplimit
		; check safe limit of allocated area
		IF zplimit > 144
			ERR
		ENDIF


; tape buffer area
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

