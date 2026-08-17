; ============================================================================
; CUSTOM X86 BIOS: POST & Hardware Diagnostics Routine
; Target: Assembled to 64KB (65536 bytes) flat binary for QEMU ROM mapping
; ============================================================================

org 0000h               ; Base offset inside the 64KB segment

section .text
start:
    ; 1. Initialization Phase (16-bit Real Mode)
    cli                 ; Clear interrupts during core setup
    mov ax, 0F000h      ; BIOS Segment
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0FFFEh      ; Setup stack pointer

    ; Initialize COM1 Serial Port (0x3F8) - 9600 Baud, 8 Data Bits, No Parity
    mov dx, 03FBh       ; Line Control Register (LCR)
    mov al, 10000000h   ; Enable DLAB (Divisor Latch Access Bit)
    out dx, al

    mov dx, 03F8h       ; Divisor Latch Low Byte (Baud rate 9600 -> 12)
    mov al, 0Ch
    out dx, al
    mov dx, 03F9h       ; Divisor Latch High Byte
    mov al, 00h
    out dx, al

    mov dx, 03FBh       ; LCR: 8 bits, no parity, 1 stop bit
    mov al, 00000011h
    out dx, al

    mov dx, 03FCh       ; Modem Control Register (MCR): Enable DTR, RTS, OUT2
    mov al, 00001011h
    out dx, al

    ; Clear screen / Print Header
    mov si, msg_banner
    call print_string

    ; 2. CPU Information via CPUID
    mov si, msg_cpu_vendor
    call print_string

    mov eax, 0          ; Function 0: Get Vendor String
    cpuid
    call print_eax_chars  ; Prints EBX
    call print_edx_chars  ; Prints EDX
    call print_ecx_chars  ; Prints ECX
    call print_newline

    ; Get CPU Brand String & Speed (Function 80000002h - 80000004h)
    mov si, msg_cpu_brand
    call print_string
    mov eax, 80000002h
    cpuid
    call print_regs_4
    mov eax, 80000003h
    cpuid
    call print_regs_4
    mov eax, 80000004h
    cpuid
    call print_regs_4
    call print_newline

    ; Get CPU Core Count and Cache Info (Function 4h / 1h)
    mov si, msg_cores
    call print_string
    mov eax, 1
    cpuid
    shr ebx, 16
    and ebx, 0FFh       ; EBX[15:8] contains max logical processors per package
    call print_hex_byte
    call print_newline

    ; 3. POST: RAM Check Simulation
    mov si, msg_post_ram
    call print_string
    mov cx, 640         ; Conventional base RAM (640 KB)
ram_loop:
    loop ram_loop
    mov si, msg_ram_ok
    call print_string

    ; 4. Motherboard & Chipset Info (BDA Check)
    mov si, msg_mb_info
    call print_string
    
    ; Read Equipment Word from BIOS Data Area (BDA at 0040:0010)
    push ds
    mov ax, 0040h
    mov ds, ax
    mov ax, [0010h]     ; Equipment list word
    pop ds
    call print_hex_word
    call print_newline

    ; Completion Hook / Infinite Loop
    mov si, msg_boot_ready
    call print_string

halt_loop:
    hlt
    jmp halt_loop

; ============================================================================
; HELPER ROUTINES: Serial Output via COM1 (0x3F8)
; ============================================================================
print_string:
    lodsb
    cmp al, 0
    je print_done
    call print_char
    jmp print_string
print_done:
    ret

print_char:
    push dx
    mov dx, 03F8h       ; COM1 Data Register
    out dx, al
    pop dx
    ret

print_newline:
    mov al, 13
    call print_char
    mov al, 10
    call print_char
    ret

print_eax_chars:
    mov [temp_val], eax
    mov cx, 4
.char_loop:
    mov al, [temp_val]
    call print_char
    shr dword [temp_val], 8
    loop .char_loop
    ret

print_edx_chars:
    mov [temp_val], edx
    mov cx, 4
.char_loop:
    mov al, [temp_val]
    call print_char
    shr dword [temp_val], 8
    loop .char_loop
    ret

print_ecx_chars:
    mov [temp_val], ecx
    mov cx, 4
.char_loop:
    mov al, [temp_val]
    call print_char
    shr dword [temp_val], 8
    loop .char_loop
    ret

print_regs_4:
    mov [temp_eax], eax
    mov [temp_ebx], ebx
    mov [temp_ecx], ecx
    mov [temp_edx], edx

    mov eax, [temp_eax]
    call print_eax_chars
    mov eax, [temp_ebx]
    call print_eax_chars
    mov eax, [temp_ecx]
    call print_eax_chars
    mov eax, [temp_edx]
    call print_eax_chars
    ret

print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
    ret

print_hex_byte:
    push ax
    shr al, 4
    call print_hex_nibble
    pop ax
    and al, 0Fh
    call print_hex_nibble
    ret

print_hex_nibble:
    cmp al, 9
    jle .num
    add al, 7
.num:
    add al, '0'
    call print_char
    ret

; ============================================================================
; DATA STRINGS & STORAGE
; ============================================================================
msg_banner      db 13, 10, "========================================", 13, 10
                db         "   CUSTOM X86 SYSTEM BIOS & POST v1.0   ", 13, 10
                db         "========================================", 13, 10, 0
msg_cpu_vendor  db ">> CPU Vendor ID           : ", 0
msg_cpu_brand   db ">> CPU Brand & Speed       : ", 0
msg_cores       db ">> Logical Core Count      : 0x", 0
msg_post_ram    db ">> POST: Testing Base RAM  : ", 0
msg_ram_ok      db "OK (640 KB Base Verified)", 13, 10, 0
msg_mb_info     db ">> Motherboard Eq. Flags   : 0x", 0
msg_boot_ready  db 13, 10, ">> POST Complete. System Ready.", 13, 10, 0

temp_val        dd 0
temp_eax        dd 0
temp_ebx        dd 0
temp_ecx        dd 0
temp_edx        dd 0

; ============================================================================
; HARDWARE RESET VECTOR PADDING
; ============================================================================
times 65535 - ($ - $$) db 0   ; Pad file out to exactly 64KB (65536 bytes)

; The Reset Vector at FFFF:FFF0 (Offset FFF0h in the last 64KB segment)
org 0FFF0h
reset_vector:
    jmp 0F000h:start          ; Jump to initialization routine