.text
.align 2
.globl _QDRInvokeSwiftVoidClosure
_QDRInvokeSwiftVoidClosure:
    stp x20, x19, [sp, #-32]!
    stp x29, x30, [sp, #16]
    add x29, sp, #16
    mov x19, x0
    mov x20, x1
    blr x19
    ldp x29, x30, [sp, #16]
    ldp x20, x19, [sp], #32
    ret
