# Makefile for assembling BIOS POST assembly code using NASM

ASM = nasm
ASM_FLAGS = -f bin
#SRC = bios_post_serial.asm
SRC = bios_post_full.asm
#OUT = bios_post_serial.bin
OUT = bios.bin
all: $(OUT)

$(OUT): $(SRC)
	$(ASM) $(ASM_FLAGS) $< -o $@

clean:
	rm -f $(OUT)

.PHONY: all clean