CC      = gcc
CFLAGS  = -m32 -ffreestanding -nostdlib -nostartfiles -fno-pie -Wall -Wextra -O2
LDFLAGS = -m32 -nostdlib -nostartfiles -no-pie
TARGET  = chipset_init

all: $(TARGET).bin

$(TARGET).elf: chipset_init_qemu.c linker.ld
	$(CC) $(CFLAGS) -T linker.ld chipset_init_qemu.c -o $@

$(TARGET).bin: $(TARGET).elf
	objcopy -O binary $< $@

run: $(TARGET).bin
	qemu-system-x86_64 \
		-M q35 \
		-m 128 \
		-bios $(TARGET).bin \
		-nographic \
		-serial mon:stdio

clean:
	rm -f $(TARGET).elf $(TARGET).bin

.PHONY: all run clean