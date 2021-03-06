/*
 *  FreeLoader
 *  Copyright (C) 1998-2002  Brian Palmer  <brianp@sginet.com>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <asm.inc>
#include <arch/pc/x86common.h>
#include <multiboot.h>

/* Multiboot support
 *
 * Allows freeldr to be loaded as a "multiboot kernel" by
 * other boot loaders like GRUB.
 * This code is not referenced from anywhere. GRUB searches for
 * the header signature and uses the header to load it.
 */

#define MB_INFO_SIZE                60   /* sizeof(multiboot_info_t) */
#define MB_INFO_FLAGS_OFFSET        0
#define MB_INFO_BOOT_DEVICE_OFFSET  12
#define MB_INFO_COMMAND_LINE_OFFSET 16
#define MB_INFO_MMAP_LEN_OFFSET     44
#define MB_INFO_MMAP_ADDR_OFFSET    48
#define MB_MMAP_SIZE                480  /* 20 * sizeof(memory_map_t) - up to 20 entries */
#define CMDLINE_SIZE                256

/*
 * We want to execute at FREELDR_BASE (to be compatible with
 * bootsector loading), but GRUB only allows loading of
 * multiboot kernels above 1MB. So we let GRUB load us
 * there and then relocate ourself to FREELDR_BASE.
 */
#define INITIAL_BASE HEX(200000)


#ifdef _USE_ML
EXTERN __bss_start__:DWORD
EXTERN __bss_end__:DWORD
#endif


#ifdef _USE_ML
.MBDATA SEGMENT PUBLIC 'DATA'
//ASSUME nothing
#endif

    /* Align to 32 bits boundary */
    .align 4

    /* Multiboot header */
MultibootHeader:
    /* magic */
    .long MULTIBOOT_HEADER_MAGIC
    /* flags */
    .long MULTIBOOT_HEADER_FLAGS
    /* checksum */
    .long -(MULTIBOOT_HEADER_MAGIC + MULTIBOOT_HEADER_FLAGS)
    /* header_addr */
    .long MultibootHeader + INITIAL_BASE - FREELDR_BASE
    /* load_addr */
    .long INITIAL_BASE
    /* load_end_addr */
    .long 0
    /* bss_end_addr */
    .long 0
    /* entry_addr */
    .long MultibootEntry + INITIAL_BASE - FREELDR_BASE

#ifdef _USE_ML
.MBDATA ENDS
#endif


.code32
ASSUME ES:NOTHING, FS:NOTHING, GS:NOTHING

MultibootEntry:
    cld

    /* Check for valid multiboot signature */
    cmp eax, MULTIBOOT_BOOTLOADER_MAGIC
    jne mbfail

    /* Save multiboot info structure */
    mov esi, ebx
    mov edi, offset MultibootInfo + INITIAL_BASE - FREELDR_BASE
    mov ecx, (MB_INFO_SIZE / 4)
    rep movsd
    mov dword ptr ds:[MultibootInfo + INITIAL_BASE - FREELDR_BASE + MB_INFO_MMAP_ADDR_OFFSET], 0
    mov dword ptr ds:[_MultibootInfoPtr + INITIAL_BASE - FREELDR_BASE], offset MultibootInfo

    /* See if the memory map was passed in */
    test dword ptr ds:[ebx + MB_INFO_FLAGS_OFFSET], MB_INFO_FLAG_MEMORY_MAP
    jz mbchk_command_line
    /* Check memory map length */
    mov ecx, dword ptr ds:[ebx + MB_INFO_MMAP_LEN_OFFSET]
    test ecx, ecx
    jz mbchk_command_line
    cmp ecx, MB_MMAP_SIZE
    jg mbchk_command_line
    /* Check memory map address */
    mov esi, dword ptr ds:[ebx + MB_INFO_MMAP_ADDR_OFFSET]
    test esi, esi
    jz mbchk_command_line
    /* Save memory map structure */
    mov edi, offset MultibootMemoryMap + INITIAL_BASE - FREELDR_BASE
    shr ecx, 2
    rep movsd
    /* Relocate memory map address */
    mov dword ptr ds:[MultibootInfo + INITIAL_BASE - FREELDR_BASE + MB_INFO_MMAP_ADDR_OFFSET], offset MultibootMemoryMap

mbchk_command_line:
    /* Save command line */
    test dword ptr ds:[ebx + MB_INFO_FLAGS_OFFSET], MB_INFO_FLAG_COMMAND_LINE
    jz mb2
    mov esi, dword ptr ds:[ebx + MB_INFO_COMMAND_LINE_OFFSET]
    mov edi, offset cmdline + INITIAL_BASE - FREELDR_BASE
    mov ecx, CMDLINE_SIZE - 1
mb1:
    lodsb
    stosb
    test al, al
    jz mb2
    dec ecx
    jnz mb1

mb2:
    /* See if the boot device was passed in */
    test dword ptr ds:[ebx + MB_INFO_FLAGS_OFFSET], MB_INFO_FLAG_BOOT_DEVICE

    /* If no boot device known, assume first partition of first harddisk */
    mov dx, HEX(0180)
    jz mb3

    /* Load boot drive into DL, boot partition into DH */
    mov edx, dword ptr ds:[ebx + MB_INFO_BOOT_DEVICE_OFFSET]
    bswap edx
    inc dh

mb3:
    /* Relocate itself to lower address */
    mov esi, INITIAL_BASE
    mov edi, FREELDR_BASE
    mov ecx, offset __bss_start__ - FREELDR_BASE
    shr ecx, 2
    rep movsd

    /* Load segment registers for real-address mode */
#ifdef _USE_ML
    lgdt fword ptr ds:[gdtptr]
#else
    lgdt ds:[gdtptr]
#endif
    mov ax, HEX(10)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    /* Jump to relocated code */
    ljmp HEX(08), mb4

mbfail:
    int 3
mbstop:
    jmp short mbstop  /* We should never get here */

.code16
mb4:
    /* Disable protected mode */
    mov eax, cr0
    and eax, CR0_PE_CLR
    mov cr0, eax

    /* Jump to real entry point */
    ljmp16 0, FREELDR_BASE
.endcode16


    /* Force 8-byte alignment */
    .align 8
gdt:
    .word HEX(0000), HEX(0000), HEX(0000), HEX(0000) /* 00: NULL descriptor */
    .word HEX(FFFF), HEX(0000), HEX(9B00), HEX(008F) /* 08: 16-bit flat CS (!) */
    .word HEX(FFFF), HEX(0000), HEX(9300), HEX(0000) /* 10: 16-bit real mode DS */

/* GDT table pointer */
gdtptr:
    .word HEX(17)   /* Limit */
    .long gdt       /* Base Address */

PUBLIC _MultibootInfoPtr
_MultibootInfoPtr:
    .long 0

MultibootInfo:
    .space MB_INFO_SIZE

MultibootMemoryMap:
    .space MB_MMAP_SIZE

PUBLIC cmdline
cmdline:
    .space CMDLINE_SIZE

END
