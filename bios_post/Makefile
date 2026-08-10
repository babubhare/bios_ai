# Makefile for assembling BIOS POST assembly code using NASM

ASM = nasm
ASM_FLAGS = -f bin
SRC = bios_post_full.asm
OUT = bios_post_full.bin

all: $(OUT)

$(OUT): $(SRC)
	$(ASM) $(ASM_FLAGS) $< -o $@

clean:
	rm -f $(OUT)

.PHONY: all clean