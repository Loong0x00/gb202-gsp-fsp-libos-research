Fact: the constructor calls descriptor-copy with `rcx=this+8` at 0x18006866a–0x18006866e, making copied descriptor +0x70/+0x74 land at runtime +0x78/+0x7c.

Status: complete. REPORT.md contains the bounded current-static result, table bounds/order, conditional historical block-49 association, and no live-runtime claim.
