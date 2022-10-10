%.d64: %.bin
	c1541 -format "$(basename $(notdir $@))," d64 $@ -attach $@ -write $< $(basename $(notdir $@))

%.bin: %.asm
	dasm $< -f1 -o$@ -l$(basename $@).lst

.SECONDARY:

