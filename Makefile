all: connect4.d64

%.d64: %.bin
	c1541 -format "$(basename $(notdir $@))," d64 $@ -attach $@ -write $< $(basename $(notdir $@))

%.bin: %.asm
	dasm $< -f1 -S -o$@ -l$(basename $@).lst

.SECONDARY:

