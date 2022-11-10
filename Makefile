all: connect4.d64 sokoban_exp3k.d64 sokoban_exp8k.d64

ASM_OPT = -f1 -S -l$(basename $@).lst -s$(basename $@).sym

%.d64: %.prg
	c1541 -format "$(basename $(notdir $@))," d64 $@ -attach $@ -write $< $(basename $(notdir $@))

%.prg: %.asm
	dasm $< $(ASM_OPT) -o$@

%_exp3k.prg: %.asm
	dasm $< $(ASM_OPT) -o$@ -DEXP3k

%_exp8k.prg: %.asm
	dasm $< $(ASM_OPT) -o$@ -DEXP8k

.SECONDARY:
