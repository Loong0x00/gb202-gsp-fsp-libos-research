/* Host-only compile-time checks against the matching official NVIDIA ABI. */
#include <stddef.h>
#include <stdio.h>
#include "gpu/gsp/gsp_init_args.h"
#include "msgq/msgq_priv.h"
#include "libos_init_args.h"
_Static_assert(sizeof(LibosMemoryRegionInitArgument) == 32, "init arg layout");
_Static_assert(sizeof(GSP_ARGUMENTS_CACHED) == 152, "RM args size");
_Static_assert(offsetof(GSP_ARGUMENTS_CACHED, bDmemStack) == 80, "stack flag");
_Static_assert(sizeof(MESSAGE_QUEUE_INIT_ARGUMENTS) == 64, "message queue args");
_Static_assert(offsetof(MESSAGE_QUEUE_INIT_ARGUMENTS, cmdQueueOffset) == 16, "cmd offset");
_Static_assert(offsetof(MESSAGE_QUEUE_INIT_ARGUMENTS, queueHeaderAlign) == 56, "alignment field");
_Static_assert(sizeof(msgqTxHeader) == 32, "queue TX header");
_Static_assert(offsetof(msgqTxHeader, entryOff) == 28, "queue entry offset");
_Static_assert(MSGQ_FLAGS_SWAP_RX == 1, "queue swap flag");
int main(void)
{
    puts("PASS NVIDIA 610.57.04 host ABI sizes and queue-header field offsets");
    return 0;
}
