// riscv_cpu.S - PicoRV32 custom-instruction helpers
// Uses the picorv32_maskirq instruction (opcode 0x0001011):  rd = previous
// irq mask ; irq mask = rs1  (bit n = 1 disables irq line n).
// encodings:  (0x03<<25) | (rs1<<15) | (0x06<<12) | (rd<<7) | 0x0B
//   maskirq zero, a0 -> 0x0605600b   (set mask, discard old)
//   maskirq a0,  a0 -> 0x0605650b   (read mask, keep it unchanged)
        .section .text

// void picorv32_irq_mask(uint32_t mask)
        .global picorv32_irq_mask
picorv32_irq_mask:
        .word 0x0605600b
        ret

// uint32_t picorv32_irq_get_mask(void)
        .global picorv32_irq_get_mask
picorv32_irq_get_mask:
        .word 0x0605650b
        ret
