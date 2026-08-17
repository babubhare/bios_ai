qemu-system-i386 -bios bios_post_full.bin

 qemu-system-x86_64 -bios bios.bin -m 128 -drive file=disk.img,format=raw,index=0,media=disk -nographic -netdev user,id=net0 -device e1000,netdev=net0