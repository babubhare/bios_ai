; Minimal BIOS POST Example for IBM PC (8086 real mode)
; Assemble: nasm -f bin bios_post.asm -o bios_post.bin
; Run with QEMU: qemu-system-i386 -bios bios_post.bin

org 0xFFF0               ; Reset vector at F000:FFF0 (physical 0xFFFF0)

start:
    cli                 ; Disable interrupts
    xor ax, ax
    mov ds, ax          ; DS=0 for memory test
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00      ; Stack pointer setup

    call memory_test_64k

    call display_post_ok

hang:
    hlt                 ; Halt CPU
    jmp hang

; ----------------------------------------------------
; Simple memory test: write/read pattern in first 64KB RAM (0x00000-0x0FFFF)
; This is only demonstration, real BIOS tests much more.

memory_test_64k:
    mov si, 0x0000          ; Offset in segment DS=0x0000
    mov cx, 0x8000          ; Number of words = 64K / 2 (word size)
mem_loop:
    mov ax, 0x55AA          ; Test pattern
    mov [si], ax            ; Write pattern
    cmp [si], ax            ; Read back and compare
    jne mem_fail
    add si, 2
    loop mem_loop
    ret

mem_fail:
    ; Display error message on screen directly (simple)
    mov si, err_msg
    call print_string
    jmp hang

; ----------------------------------------------------
; Display "POST OK" message on screen at row 10 col 30 using BIOS int 10h

display_post_ok:
    mov si, post_ok_msg
    mov ah, 0x0E            ; Teletype output (TTY) BIOS function
print_char:
    lodsb                   ; Load byte from [SI] into AL, increment SI
    cmp al, 0
    je done_print
    int 0x10                ; BIOS video interrupt to print character
    jmp print_char
done_print:
    ret

; ----------------------------------------------------
; Print string pointed by SI using BIOS TTY output (int 10h AH=0Eh)

print_string:
    mov ah, 0x0E
next_char:
    lodsb
    cmp al, 0
    je done_print_string
    int 0x10
    jmp next_char
done_print_string:
    ret

; ----------------------------------------------------
; Data Strings

post_ok_msg db 'POST OK', 0

err_msg db 'MEMORY ERROR', 0