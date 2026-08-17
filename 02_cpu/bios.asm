; ============================================================================
; Custom 16-bit x86 BIOS for Emulators (QEMU / Bochs)
; Target Memory: 64KB ROM mapped to top of 1MB space (Physical: 0xF0000 - 0xFFFFF)
; ============================================================================

org 0000h               ; Base offset inside the 64KB segment

section .text
start:
    cli                 ; Clear interrupts during early hardware setup
    mov ax, 0xF000      ; Set code segment to upper ROM region
    mov ds, ax
    mov es, ax

    ; Setup a safe real-mode stack
    mov ss, ax
    mov sp, 0xFFFE      ; Point stack pointer near the top of the segment

    ; 1. Initialize Serial Port (COM1 at I/O Port 0x3F8)
    call init_serial

    ; 2. Send Greeting Banner over Serial
    mov si, msg_banner
    call print_string

    ; 3. Execute CPUID to retrieve CPU Vendor String
    mov eax, 0          ; Function 0: Get Vendor ID
    cpuid               ; Triggers CPUID instruction
    
    ; Store registers into buffer
    mov [vendor_buf + 0], ebx
    mov [vendor_buf + 4], edx
    mov [vendor_buf + 8], ecx
    mov byte [vendor_buf + 12], 0

    ; Print Vendor ID label & string
    mov si, msg_cpu_lbl
    call print_string
    mov si, vendor_buf
    call print_string
    mov si, newline
    call print_string

    ; 4. Infinite Halt Loop (End of BIOS tasks, ready for bootloader scan)
halt_loop:
    hlt
    jmp halt_loop

; ============================================================================
; SUBROUTINES
; ============================================================================

init_serial:
    ; Configure COM1 (0x3F8) to 9600 baud, 8 data bits, no parity, 1 stop bit
    mov dx, 0x3F9       ; Interrupt Enable Register
    mov al, 0x00
    out dx, al

    mov dx, 0x3FB       ; Line Control Register (Set DLAB = 1)
    mov al, 0x80
    out dx, al

    mov dx, 0x3F8       ; Divisor Latch Low Byte (9600 baud -> 12)
    mov al, 12
    out dx, al

    mov dx, 0x3F9       ; Divisor Latch High Byte
    mov al, 0
    out dx, al

    mov dx, 0x3FB       ; Line Control Register (8 bits, no parity, 1 stop)
    mov al, 0x03
    out dx, al
    ret

print_string:
    lodsb               ; Load next byte from DS:SI into AL
    cmp al, 0
    je print_done
    call print_char
    jmp print_string
print_done:
    ret

print_char:
    push dx
    mov dx, 0x3F8       ; COM1 Data Register
    out dx, al          ; Transmit character via Port I/O
    pop dx
    ret

; ============================================================================
; DATA STRINGS
; ============================================================================
msg_banner    db 13, 10, "=== CUSTOM X86 BIOS INITIALIZED ===", 13, 10, 0
msg_cpu_lbl   db ">> CPU Vendor ID : ", 0
newline       db 13, 10, 0

section .data
vendor_buf    times 13 db 0

; ============================================================================
; RESET VECTOR PADDING
; ============================================================================
; Pad the binary file up to exactly 64KB (65536 bytes) minus 16 bytes for vector
times (65536 - 16 - ($ - start)) db 0

; The Hardware Reset Vector at physical address 0xFFFF0 (CS:IP = F000:FFF0)
reset_vector:
    jmp 0xF000:start
    times (65536 - ($ - start)) db 0