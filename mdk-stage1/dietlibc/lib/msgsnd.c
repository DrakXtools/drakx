#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#include <asm/ipc.h>

extern int __ipc();

int msgsnd (int msqid, const void *msgp, size_t msgsz, int msgflg) {
  return __ipc(MSGSND,msqid, msgsz, msgflg, msgp);
}
