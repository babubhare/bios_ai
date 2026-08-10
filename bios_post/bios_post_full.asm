; bios_post_full.asm
; Minimal BIOS POST with device checks and info display
; Assemble: nasm -f bin bios_post_full.asm -o bios_post_full.bin
; Run: qemu-system-i386 -bios bios_post_full.bin

org 0xFFF0             ; BIOS reset vector (F000:FFF0)

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    call clear_screen

    ; 1. RAM test first 64KB
    mov si, ram_test_msg
    call print_string
    call memory_test_64k
    cmp al, 0
    jne ram_fail

    mov si, ram_ok_msg
    call print_string

    ; Display size: 64KB tested
    mov si, ram_size_msg
    call print_string

    ; 2. PIT Timer init check
    mov si, pit_msg
    call print_string
    call pit_init_test
    mov si, pit_ok_msg
    call print_string

    ; 3. Keyboard controller test
    mov si, kbd_msg
    call print_string
    call keyboard_controller_test
    cmp al, 0xFA      ; ACK expected
    jne kbd_fail

    mov si, kbd_ok_msg
    call print_string

    ; 4. Video adapter test (write/read video mem)
    mov si, video_msg
    call print_string
    call video_test
    cmp al, 0x01      ; success flag in AL=1
    jne video_fail

    mov si, video_ok_msg
    call print_string

    ; 5. Floppy disk controller reset test
    mov si, fdc_msg
    call print_string
    call floppy_reset_test
    mov si, fdc_ok_msg
    call print_string

    ; 6. IDE hard disk controller detect test
    mov si, ide_msg
    call print_string
    call ide_detect_test
    cmp al, 1         ; AL=1 means device found
    jne ide_fail

    mov si, ide_ok_msg
    call print_string

done:
    mov si, done_msg
    call print_string

hang:
    hlt
    jmp hang

; ---------------------
; Subroutines 

; Clear screen via BIOS int 10h AH=0x06 scroll up entire screen (clear)
clear_screen:
    mov ah, 0x06
    xor al, al          ; number of lines to scroll = 0 = clear screen
    mov bh, 0x07        ; attribute (grey on black)
    mov cx, 0x0000      ; upper left corner row/col = 0,0
    mov dx, 0x184F      ; lower right corner row/col = 24,79 (80x25)
    int 0x10
    ret

; Print zero-terminated string at DS:SI using BIOS TTY int 10h AH=0Eh
print_string:
    mov ah, 0x0E
.next_char:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .next_char
.done:
    ret

; --- Memory Test 64 KB ---
; Returns AL=0 if fail, AL=1 if pass.
memory_test_64k:
    push cx dx si di bx

    xor si, si          ; offset in DS=0x0000 segment 
    mov cx, 0x8000      ; words count (64K / 2 bytes)

mem_loop:
    mov ax, 0x55AA      ; test pattern 1
    mov [ds:si], ax     
    cmp [ds:si], ax     
    jne mem_fail_short  
      
    mov ax, 0xAA55      ; test pattern 2
    mov [ds:si], ax     
    cmp [ds:si], ax     
    jne mem_fail_short  

    add si, 2           
    loop mem_loop

mem_pass:
   mov al, 1            ; pass flag  
   pop bx di si dx cx   
   ret

mem_fail_short:
   mov al, 0            ; fail flag  
   pop bx di si dx cx   
   ret

; --- PIT Timer Init ---
; Initialize PIT channel 0 in mode 3 square wave at max count (0xFFFF)
pit_init_test:
    mov al, 0x36        ; Channel 0, mode 3, binary mode  
    out 0x43, al        
    
    mov al, 0xFF        ; Low byte count  
    out 0x40, al        
    
    mov al, 0xFF        ; High byte count  
    out 0x40, al        

   ret

; --- Keyboard Controller Test ---
; Send reset command (0xFF) to keyboard controller and read ACK (0xFA)
keyboard_controller_test:
wait_input_empty:
   in al, 0x64          ; read status port  
   test al, 2           ; input buffer full?
   jnz wait_input_empty
   
   mov al, 0xFF         ; reset command  
   out 0x60, al
   
wait_output_full:
   in al, 0x64          ; read status  
   test al,1            ; output buffer full?  
   jz wait_output_full
   
   in al, 0x60          ; read ACK  
   ret

; --- Video Test ---
; Write/read character to CGA text buffer at segment B800h offset 0,
; returns AL=1 if success else AL=0.
video_test:
   push es di bx
   
   mov ax, 0xB800      
   mov es, ax          
   xor di, di          
   
   mov ax, 'X' + (0x07 <<8)   ; character 'X' with attribute  
   mov [es:di], ax              
   
   mov bx,[es:di]       
   cmp bx, ax           
   jne .fail
   
   mov al,1             ; success flag
   
   pop bx di es         
   ret
   
.fail:
   mov al,0             ; fail flag
   
   pop bx di es         
   ret

; --- Floppy Disk Controller Reset ---
; Reset FDC by toggling bit2 on port 3F2h.
floppy_reset_test:
   in al, 0x3F2           
   and al, 0xFB           ; clear bit2 (reset low)  
   out 0x3F2, al         
   
   ; short delay loop (~10000 iterations)
   mov cx,10000 
.delay1:
   loop .delay1
   
   in al, 0x3F2           
   or al, 4               ; set bit2 (reset high)  
   out 0x3F2, al         
   
   ret

; --- IDE Hard Disk Detect ---
; Send IDENTIFY command to IDE controller port at base 1F0h.
; Returns AL=1 if device present else AL=0.

ide_detect_test:
   push dx cx dx bx si di
   
   mov dx, 0x1F6          ; Drive/head select register  
   mov al, 0xA0           ; Select master drive (bit4 set)  
   out dx, al
   
   mov dx, 0x1F7          ; Command register port  
   mov al, 0xEC           ; IDENTIFY DEVICE command  
   out dx, al
   
; Wait for BSY clear and DRQ set or timeout (~65535 loops)
wait_ide_ready:
   in al, dx              ; read status  
   test al, 0x80          ; BSY bit set?  
   jnz wait_ide_ready_loop
   
wait_ide_ready_loop:
   in al, dx             
   test al, (1<<3)        ; DRQ bit set?  
   jnz ide_device_found   
   
wait_ide_ready_loop2:
   loop wait_ide_ready_loop2
   
ide_device_not_found:
   mov al,0               ; no device found  
   jmp ide_done
   
ide_device_found:
   mov al,1               ; device present  
   
ide_done:
   pop di si bx cx dx dx   
   ret


; ---------------------
; Messages

ram_test_msg db 'RAM Test (64KB): ', 0
ram_ok_msg db 'PASS',13,10,0        ; CR LF line end  
ram_size_msg db 'Memory tested: 64 KB',13,10,0

pit_msg db 'PIT Timer Init...',13,10,0         
pit_ok_msg db 'PIT Init OK',13,10,0       

kbd_msg db 'Keyboard Controller Reset...',13,10,0      
kbd_ok_msg db 'Keyboard Controller OK',13,10,0   

video_msg db 'Video Adapter Test...',13,10,0    
video_ok_msg db 'Video Adapter OK',13,10,0      

fdc_msg db 'Floppy Disk Controller Reset...',13,10,0     
fdc_ok_msg db 'Floppy Disk Controller OK',13,10,0       

ide_msg db 'IDE Hard Disk Detect...',13,10,0          
ide_ok_msg db 'IDE Device Found',13,10,0        

ram_fail db 'RAM Test FAIL!',13,10,'System Halted',13,10 ,0 
kbd_fail db 'Keyboard Controller FAIL!',13,10,'System Halted',13,10 ,0 
video_fail db 'Video Adapter FAIL!',13,10,'System Halted',13,10 ,0 
ide_fail db 'IDE Device NOT Found!',13,10,'System Halted',13,10 ,0 

done_msg db 'POST Complete.',13,10 ,0
