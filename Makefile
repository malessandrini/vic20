all: connect4.d64

%.d64: %.prg
	c1541 -format "$(basename $(notdir $@))," d64 $@ -attach $@ -write $< $(basename $(notdir $@))

%.prg: %.asm
	dasm $< -f1 -S -o$@ -l$(basename $@).lst -s$(basename $@).sym

.SECONDARY:

