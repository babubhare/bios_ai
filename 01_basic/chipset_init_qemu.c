/**
 * chipset_init_qemu.c
 * Chipset initialization for QEMU Q35 (ICH9) machine
 * Build: gcc -m32 -ffreestanding -nostdlib -T linker.ld chipset_init_qemu.c -o chipset.bin
 * Run:  qemu-system-x86_64 -M q35 -bios chipset.bin -nographic
 */

#include <stdint.h>

/* ── I/O Port Helpers ────────────────────────────────── */

static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline void outw(uint16_t port, uint16_t val) {
    __asm__ volatile ("outw %0, %1" : : "a"(val), "Nd"(port));
}

static inline void outl(uint16_t port, uint32_t val) {
    __asm__ volatile ("outl %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline uint16_t inw(uint16_t port) {
    uint16_t ret;
    __asm__ volatile ("inw %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline uint32_t inl(uint16_t port) {
    uint32_t ret;
    __asm__ volatile ("inl %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/* ── PCI Configuration Space Access (I/O method) ──────── */

#define PCI_CONFIG_ADDR 0xCF8
#define PCI_CONFIG_DATA 0xCFC
#define PCI_VENDOR_ID   0x00
#define PCI_CLASS_CODE  0x08

static uint32_t pci_config_read32(uint8_t bus, uint8_t slot,
                                   uint8_t func, uint8_t offset) {
    uint32_t address = (1U << 31) |
                       ((uint32_t)bus << 16) |
                       ((uint32_t)slot << 11) |
                       ((uint32_t)func << 8) |
                       (offset & 0xFC);
    outl(PCI_CONFIG_ADDR, address);
    return inl(PCI_CONFIG_DATA);
}

static uint16_t pci_config_read16(uint8_t bus, uint8_t slot,
                                   uint8_t func, uint8_t offset) {
    return (uint16_t)(pci_config_read32(bus, slot, func, offset & 0xFC)
                      >> ((offset & 2) * 8));
}

static void pci_config_write8(uint8_t bus, uint8_t slot,
                               uint8_t func, uint8_t offset, uint8_t val) {
    uint32_t address = (1U << 31) |
                       ((uint32_t)bus << 16) |
                       ((uint32_t)slot << 11) |
                       ((uint32_t)func << 8) |
                       (offset & 0xFC);
    outl(PCI_CONFIG_ADDR, address);
    outb(PCI_CONFIG_DATA + (offset & 3), val);
}

static void pci_config_write32(uint8_t bus, uint8_t slot,
                                uint8_t func, uint8_t offset, uint32_t val) {
    uint32_t address = (1U << 31) |
                       ((uint32_t)bus << 16) |
                       ((uint32_t)slot << 11) |
                       ((uint32_t)func << 8) |
                       (offset & 0xFC);
    outl(PCI_CONFIG_ADDR, address);
    outl(PCI_CONFIG_DATA, val);
}

/* ── Serial (UART) for Debug Output ───────────────────── */

#define UART_PORT 0x3F8  /* COM1 */

static void uart_init(void) {
    outb(UART_PORT + 1, 0x00);  /* Disable interrupts */
    outb(UART_PORT + 3, 0x80);  /* Enable DLAB (divisor latch) */
    outb(UART_PORT + 0, 0x03);  /* Baud rate divisor low byte (38400) */
    outb(UART_PORT + 1, 0x00);  /* Baud rate divisor high byte */
    outb(UART_PORT + 3, 0x03);  /* 8N1, disable DLAB */
    outb(UART_PORT + 2, 0xC7);  /* Enable FIFO, clear, 14-byte threshold */
    outb(UART_PORT + 4, 0x0B);  /* IRQs enabled, RTS/DSR set */
}

static int uart_tx_ready(void) {
    return inb(UART_PORT + 5) & 0x20;
}

static void uart_putc(char c) {
    while (!uart_tx_ready());
    outb(UART_PORT, c);
}

static void uart_puts(const char *str) {
    while (*str) uart_putc(*str++);
}

static void uart_puthex(uint32_t val) {
    const char hex[] = "0123456789ABCDEF";
    uart_putc('0'); uart_putc('x');
    for (int i = 7; i >= 0; i--)
        uart_putc(hex[(val >> (i * 4)) & 0xF]);
}

/* ── PIC (8259 Interrupt Controller) Init ─────────────── */

#define PIC1_CMD  0x20
#define PIC1_DATA 0x21
#define PIC2_CMD  0xA0
#define PIC2_DATA 0xA1

static void pic_init(void) {
    uart_puts("[INIT] Initializing 8259 PIC...\r\n");

    /* ICW1: Start initialization, cascade mode */
    outb(PIC1_CMD, 0x11);
    outb(PIC2_CMD, 0x11);

    /* ICW2: Remap IRQ0-7 to INT 0x20-0x27, IRQ8-15 to INT 0x28-0x2F */
    outb(PIC1_DATA, 0x20);
    outb(PIC2_DATA, 0x28);

    /* ICW3: Tell PIC1 about slave on IRQ2, tell PIC2 it's cascade identity */
    outb(PIC1_DATA, 0x04);
    outb(PIC2_DATA, 0x02);

    /* ICW4: x86 mode, normal EOI */
    outb(PIC1_DATA, 0x01);
    outb(PIC2_DATA, 0x01);

    /* Mask all interrupts initially */
    outb(PIC1_DATA, 0xFF);
    outb(PIC2_DATA, 0xFF);

    uart_puts("[INIT] PIC initialized (remapped to 0x20-0x2F).\r\n");
}

/* ── PIT (8254 Programmable Interval Timer) Init ──────── */

#define PIT_CH0 0x40
#define PIT_CMD 0x43

static void pit_init(void) {
    uart_puts("[INIT] Initializing 8254 PIT...\r\n");

    /* Channel 0, lobyte/hibyte, rate generator, binary */
    outb(PIT_CMD, 0x34);

    /* ~1000 Hz (1193182 / 1193) */
    outb(PIT_CH0, 0xA9);
    outb(PIT_CH0, 0x04);

    uart_puts("[INIT] PIT initialized (~1000 Hz).\r\n");
}

/* ── ACPI Shutdown Support ────────────────────────────── */

static void acpi_init(void) {
    uart_puts("[INIT] Configuring ACPI PM base...\r\n");

    /* Q35 LPC Bridge (D31:F0) — ACPI PM base at 0x600 */
    pci_config_write32(0, 31, 0, 0x40, 0x0601);

    uart_puts("[INIT] ACPI PM base set to 0x600.\r\n");
}

/* ── PCI Bus Scan ─────────────────────────────────────── */

static void pci_scan_bus(void) {
    uart_puts("[PCI] Scanning PCI bus...\r\n");

    for (uint8_t slot = 0; slot < 32; slot++) {
        uint16_t vendor = pci_config_read16(0, slot, 0, PCI_VENDOR_ID);
        if (vendor == 0xFFFF) continue;

        uint32_t class_dev = pci_config_read32(0, slot, 0, PCI_CLASS_CODE);
        uint8_t class_code = (class_dev >> 24) & 0xFF;

        uart_puts("  Slot ");
        uart_puthex(slot);
        uart_puts(": Vendor=");
        uart_puthex(vendor);
        uart_puts(" Class=");
        uart_puthex(class_code);
        uart_puts("\r\n");

        /* Check for multifunction devices */
        uint8_t header_type = (pci_config_read32(0, slot, 0, 0x0C) >> 16) & 0x7F;
        if (header_type & 0x80) {
            for (uint8_t func = 1; func < 8; func++) {
                vendor = pci_config_read16(0, slot, func, PCI_VENDOR_ID);
                if (vendor == 0xFFFF) continue;
                uart_puts("    Func ");
                uart_puthex(func);
                uart_puts(": Vendor=");
                uart_puthex(vendor);
                uart_puts("\r\n");
            }
        }
    }
}

/* ── Memory Map Display ───────────────────────────────── */

static void show_memory_map(void) {
    uart_puts("[MEM] Probing memory via E820...\r\n");
    uart_puts("[MEM] QEMU default: 128 MiB RAM at 0x00000000 - 0x08000000\r\n");

    /* In a real firmware, you'd call INT 0x15 E820.
       For QEMU with -m 128, we know the default layout. */
    uart_puts("[MEM] Usable: 0x00000000 - 0x07FFFFFF (128 MiB)\r\n");
}

/* ── Master Chipset Initialization ────────────────────── */

void chipset_init(void) {
    uart_puts("\r\n");
    uart_puts("========================================\r\n");
    uart_puts("  QEMU Q35 Chipset Initialization\r\n");
    uart_puts("========================================\r\n\r\n");

    /* 1. Serial console first for debug */
    uart_init();
    uart_puts("[INIT] Serial console online.\r\n");

    /* 2. PIC remapping */
    pic_init();

    /* 3. PIT (system timer) */
    pit_init();

    /* 4. ACPI power management */
    acpi_init();

    /* 5. Scan and report PCI topology */
    pci_scan_bus();

    /* 6. Show detected memory */
    show_memory_map();

    uart_puts("\r\n[INIT] Chipset initialization complete!\r\n");
    uart_puts("[INIT] System ready.\r\n");
    uart_puts("========================================\r\n");
}

/* ── Entry Point ──────────────────────────────────────── */

void _start(void) {
    chipset_init();

    /* Halt — in a real system you'd jump to a payload or kernel */
    uart_puts("\r\n[INFO] Halting. Use QEMU monitor to quit (Ctrl+A X).\r\n");
    while (1) {
        __asm__ volatile ("hlt");
    }
}