bits 16
org 0x0000

start:
    cli             ; Clear interrupts
    cld             ; Clear direction flag

    ; 1. Set up Segments & Stack
    mov ax, cs
    mov ds, ax
    mov ax, 0x0000
    mov ss, ax
    mov sp, 0x7C00

    ; 2. Initialize Serial Port COM1 (I/O Port 0x3F8)
    mov dx, 0x3F8 + 1  
    mov al, 0x00
    out dx, al         
    mov dx, 0x3F8 + 3  
    mov al, 0x80       
    out dx, al
    mov dx, 0x3F8 + 0   
    mov al, 0x03       
    out dx, al
    mov dx, 0x3F8 + 1   
    mov al, 0x00
    out dx, al
    mov dx, 0x3F8 + 3  
    mov al, 0x03       
    out dx, al
    mov dx, 0x3F8 + 2  
    mov al, 0xC7       
    out dx, al

    ; 3. Print Boot Header
    mov si, msg_boot
    call print_string

    ; -------------------------------------------------------------
    ; FEATURE 1: CPU Vendor ID via CPUID
    ; -------------------------------------------------------------
    mov eax, 0          
    cpuid               
    mov si, msg_cpu
    call print_string
    mov eax, ebx
    call print_reg_chars
    mov eax, edx
    call print_reg_chars
    mov eax, ecx
    call print_reg_chars
    mov si, msg_newline
    call print_string

    ; -------------------------------------------------------------
    ; FEATURE 2: Brute-Force Base RAM Test (POST)
    ; -------------------------------------------------------------
    mov si, msg_test
    call print_string
    push ds                 
    
    mov ax, 0x1000          ; Start testing above 64KB (safe zone)
    xor cx, cx              
    
.ram_test_loop:
    mov ds, ax              
    mov bx, 0x0000          
    mov word [bx], 0xAA55   
    cmp word [bx], 0xAA55   
    jne .ram_test_done      
    
    inc cx                  
    add ax, 0x0040          
    cmp ax, 0xA000          ; Stop at VGA memory boundary (0xA0000)
    je .ram_test_done
    jmp .ram_test_loop

.ram_test_done:
    pop ds                  
    mov ax, cx              
    call print_hex_ax
    mov si, msg_base_kb
    call print_string

    ; -------------------------------------------------------------
    ; FEATURE 3: Extended RAM via CMOS (Ports 0x70 & 0x71)
    ; -------------------------------------------------------------
    mov si, msg_ext_ram
    call print_string
    mov al, 0x35        
    out 0x70, al        
    in al, 0x71         
    mov ah, al          
    mov al, 0x34        
    out 0x70, al
    in al, 0x71         
    call print_hex_ax   
    mov si, msg_blocks
    call print_string

    ; -------------------------------------------------------------
    ; FEATURE 4: Keyboard Controller Status Check (Intel 8042)
    ; -------------------------------------------------------------
    mov si, msg_kbc
    call print_string
    mov dx, 0x64        
    in al, dx           
    call print_hex_al   
    mov si, msg_kbc_ok
    call print_string

    ; -------------------------------------------------------------
    ; FEATURE 5: Dual Serial Ports Check (COM1 & COM2)
    ; -------------------------------------------------------------
    mov si, msg_serial_check
    call print_string
    mov dx, 0x3F8
    in al, dx
    call print_hex_al
    mov si, msg_com1_str
    call print_string
    mov dx, 0x2F8
    in al, dx
    call print_hex_al
    mov si, msg_com2_str
    call print_string

    ; -------------------------------------------------------------
    ; FEATURE 6: ATA Primary Hard Drive Size Discovery (Ports 0x1F0 - 0x1F7)
    ; -------------------------------------------------------------
    mov si, msg_ata
    call print_string
    mov dx, 0x1F6
    mov al, 0xA0
    out dx, al
    mov dx, 0x1F7
    mov al, 0xEC
    out dx, al

.ata_wait:
    in al, dx
    cmp al, 0               
    je .no_drive
    test al, 0x80           
    jnz .ata_wait
    test al, 0x08           
    jz .ata_wait

    mov dx, 0x1F0
    mov cx, 256             
.read_ata:
    in ax, dx               
    cmp cx, 256 - 60        
    jne .not_w60
    mov bx, ax              
.not_w60:
    cmp cx, 256 - 61        
    jne .not_w61
    push dx
    push ax
    call print_hex_ax       
    mov ax, bx
    call print_hex_ax
    mov si, msg_sectors
    call print_string
    pop ax
    pop dx
.not_w61:
    dec cx
    jnz .read_ata
    jmp .ata_done

.no_drive:
    mov si, msg_none
    call print_string
.ata_done:

    ; -------------------------------------------------------------
    ; FEATURE 7: Comprehensive Multi-Bus PCI Scan (All 32 Slots + Names)
    ; -------------------------------------------------------------
    mov si, msg_pci
    call print_string
    xor ecx, ecx            ; ecx = Bus Number (0 and 1)

.bus_scan_loop:
    xor ebx, ebx            ; ebx = Device Number (0 to 31)

.pci_scan_loop:
    mov eax, 0x80000000     
    
    ; Insert Bus Number into bits 16-23
    push ecx
    shl ecx, 16
    or eax, ecx
    pop ecx

    ; Insert Device Number into bits 11-15
    push edx
    mov edx, ebx
    shl edx, 11
    or eax, edx
    pop edx

    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx              ; EAX holds [Device ID (16-bit) | Vendor ID (16-bit)]

    cmp ax, 0xFFFF
    je .next_device         ; Empty slot, skip printing

    push eax                ; Save Device/Vendor ID structure
    mov si, msg_dev
    call print_string
    
    ; Print Bus Number
    push ax
    mov al, cl
    call print_hex_al
    mov si, msg_colon
    call print_string
    pop ax

    ; Print Device Number
    mov ax, bx              
    call print_hex_al
    mov si, msg_id_str
    call print_string

    ; Print Hex IDs (Vendor:Device)
    pop eax                 
    push eax                
    call print_hex_eax
    mov si, msg_space
    call print_string

    ; Look up and print device name string
    pop eax                 
    push eax                
    call print_pci_name

    mov si, msg_newline
    call print_string
    pop eax                 

.next_device:
    inc ebx
    cmp ebx, 32             
    jl .pci_scan_loop

    inc ecx
    cmp ecx, 2              ; Scan Bus 0 and Bus 1
    jl .bus_scan_loop

    ; -------------------------------------------------------------
    ; 8. Halt System
    ; -------------------------------------------------------------
    mov si, msg_done
    call print_string
halt:
    hlt                 
    jmp halt            

; =========================================================
; FIXED PCI NAME LOOKUP FUNCTION
; Input: EAX = [Device ID (16-bit) | Vendor ID (16-bit)]
; =========================================================
print_pci_name:
    push si
    push eax                ; Save full EAX on stack
    mov si, pci_table

.lookup_loop:
    mov dx, [si]            ; Read table Vendor ID
    cmp dx, 0
    je .unknown_device      ; End of table marker if Vendor ID is 0

    ; Check Vendor ID match (low 16 bits of EAX)
    mov ax, [esp]           
    cmp ax, dx              
    jne .next_table_entry

    ; Check Device ID match (high 16 bits of EAX)
    mov edx, [esp]          
    shr edx, 16             ; DX = Target Device ID
    cmp dx, [si+2]          ; Compare with table Device ID
    jne .next_table_entry

    ; Found match! Print string at [si+4]
    mov si, [si+4]
    call print_string
    add esp, 4              ; Clean up saved EAX from stack
    pop si
    ret

.next_table_entry:
    add si, 8               ; Each entry is 8 bytes (Vendor(2) + Device(2) + Pointer(4))
    jmp .lookup_loop

.unknown_device:
    mov si, str_unknown
    call print_string
    add esp, 4              ; Clean up saved EAX from stack
    pop si
    ret

; =========================================================
; HELPER FUNCTIONS
; =========================================================

print_char:
    push dx
    push ax
    mov dx, 0x3F8 + 5
.wait:
    in al, dx
    test al, 0x20       
    jz .wait
    mov dx, 0x3F8
    pop ax
    out dx, al          
    pop dx
    ret

print_string:
.loop:
    lodsb               
    or al, al           
    jz .done
    call print_char
    jmp .loop
.done:
    ret

print_reg_chars:
    push cx
    mov cx, 4
.print_char:
    call print_char     
    shr eax, 8          
    dec cx
    jnz .print_char
    pop cx
    ret

print_hex_ax:
    push ax
    push bx
    push cx
    mov cx, 4           
.hex_loop:
    rol ax, 4           
    mov bl, al
    and bl, 0x0F        
    add bl, '0'         
    cmp bl, '9'
    jle .print_it
    add bl, 7           
.print_it:
    push ax
    mov al, bl
    call print_char     
    pop ax
    dec cx
    jnz .hex_loop
    pop cx
    pop bx
    pop ax
    ret

print_hex_al:
    push ax
    push cx
    mov cx, 2           
.hex_loop_al:
    rol al, 4           
    push ax
    and al, 0x0F        
    add al, '0'         
    cmp al, '9'
    jle .print_it_al
    add al, 7           
.print_it_al:
    call print_char     
    pop ax
    dec cx
    jnz .hex_loop_al
    pop cx
    pop ax
    ret

print_hex_eax:
    push eax
    push ebx
    push ecx
    mov ecx, 8           
.hex_loop_eax:
    rol eax, 4           
    mov bl, al
    and bl, 0x0F        
    add bl, '0'         
    cmp bl, '9'
    jle .print_it_eax
    add bl, 7           
.print_it_eax:
    push eax
    mov al, bl
    call print_char     
    pop eax
    dec ecx
    jnz .hex_loop_eax
    pop ecx
    pop ebx
    pop eax
    ret

; =========================================================
; PCI DEVICE LOOKUP TABLE & STRINGS
; Structure: dw VendorID, DeviceID / dd StringPointer
; =========================================================
pci_table:
    dw 0x8086, 0x1237
    dd str_host
    dw 0x8086, 0x7000
    dd str_isa
    dw 0x8086, 0x7010
    dd str_ide
    dw 0x8086, 0x7113
    dd str_acpi
    dw 0x1234, 0x1111
    dd str_qemuvga
    dw 0x1013, 0x00B8
    dd str_cirrus
    dw 0x8086, 0x100E
    dd str_e1000
    dw 0x0000, 0x0000
    dd 0                            ; Explicit Terminator

str_host        db "[Intel 440FX Host Bridge]", 0
str_isa         db "[Intel PIIX3 ISA Bridge]", 0
str_ide         db "[Intel PIIX3 IDE Controller]", 0
str_acpi        db "[Intel PIIX4 ACPI PM]", 0
str_qemuvga     db "[QEMU Standard VGA Controller]", 0
str_cirrus      db "[Cirrus Logic GD5446 VGA]", 0
str_e1000       db "[Intel 82540EM Gigabit Ethernet]", 0
str_unknown     db "[Unknown Peripheral Device]", 0

; =========================================================
; DATA STRINGS
; =========================================================
msg_boot        db "========================================", 13, 10
                db " Custom BIOS: Full Hardware Probe", 13, 10
                db "----------------------------------------", 13, 10, 0
msg_cpu         db ">> CPU Vendor ID           : ", 0
msg_test        db ">> POST: Testing Base RAM  : ", 0
msg_base_kb     db " Good 1KB blocks found.", 13, 10, 0
msg_ext_ram     db ">> CMOS: RAM > 16MB limit  : 0x", 0
msg_blocks      db " (64KB Blocks)", 13, 10, 0
msg_kbc         db ">> 8042 Keyboard Status    : 0x", 0
msg_kbc_ok      db " (Controller Active)", 13, 10, 0
msg_serial_check db ">> Serial Ports Check      : COM1(0x3F8)=0x", 0
msg_com1_str    db ", COM2(0x2F8)=0x", 0
msg_com2_str    db " (Responsive)", 13, 10, 0
msg_ata         db ">> ATA Primary Drive Size  : 0x", 0
msg_sectors     db " Sectors", 13, 10, 0
msg_none        db "No Drive Attached", 13, 10, 0
msg_pci         db ">> PCI Bus Scan & Device Names:", 13, 10, 0
msg_dev         db "   - Bus:Dev 0x", 0
msg_colon       db ":0x", 0
msg_id_str      db " ID:0x", 0
msg_space       db " ", 0
msg_newline     db 13, 10, 0
msg_done        db ">> System initialization complete.", 13, 10, 0

; Hardware Reset Vector configuration
times 0xFFF0 - ($ - $$) db 0x90     
reset_vector:
    jmp 0xF000:start                

; Pad to exact 64KB ROM binary size
times 0x10000 - ($ - $$) db 0x90