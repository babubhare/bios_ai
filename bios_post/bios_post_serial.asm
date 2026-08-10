; minimal_serial_test.asm
; Minimal BIOS that repeatedly sends 'A' over COM1 serial port (0x3F8)
; Assemble with:
; nasm -f bin minimal_serial_test.asm -o minimal_serial_test.bin
; Run with QEMU:
; qemu-system-i386 -bios minimal_serial_test.bin -nographics -serial mon:stdio

org 0xFFF0

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    call serial_init

.loop:
    mov bl, 'A'
    call serial_write_char
    jmp .loop

; Initialize COM1 serial port 0x3F8, 38400 baud, 8N1

serial_init:
    mov dx, 0x3F8
    mov al, 0x00
    out dx, al              ; Disable all interrupts

    mov dx, 0x3FB           ; Line Control Register (COM1 + 3)
    mov al, 0x80
    out dx, al              ; Enable DLAB

    mov dx, 0x3F8           ; Divisor latch low byte (38400 baud)
    mov al, 0x03
    out dx, al

    mov dx, 0x3F9           ; Divisor latch high byte
    mov al, 0x00
    out dx, al

    mov dx, 0x3FB           ; Line Control Register
    mov al, 0x03            ; 8 bits, no parity, one stop bit
    out dx, al

    mov dx, 0x3FA           ; FIFO Control Register
    mov al, 0xC7            ; Enable FIFO, clear them, 14-byte threshold
    out dx, al

    mov dx, 0x3FC           ; Modem Control Register
    mov al, 0x0B            ; IRQs enabled, RTS/DSR set
    out dx, al

    ret

; Send character in BL to COM1 serial port (wait for transmit buffer empty)

serial_write_char:
    push ax
    push dx

.wait_transmit_empty:
    mov dx, 0x3F8+5
    
    in al, dx             ; Line Status Register
    test al, 0x20           ; Transmitter Holding Register Empty bit?
    jz .wait_transmit_empty

    mov al, bl
    mov dx, 0x3F8              ; Character to send
    out dx, al

    pop dx
    pop ax
    ret

times 65536 - ($ - $$) db 0   ; pad to 64 KB for BIOS image