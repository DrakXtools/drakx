#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <asm/ipc.h>

extern int __ipc();

int shmctl(int shmid, int cmd, struct shmid_ds *buf) {
  return __ipc(SHMCTL,shmid,cmd,0,buf);
}
