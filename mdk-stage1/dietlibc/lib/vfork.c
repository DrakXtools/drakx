#include <linux/types.h>
#include <unistd.h>

pid_t vfork(void) {
  return fork();
}
