#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <fcntl.h>


void die(char *msg)
{
  perror(msg);
  exit(1);
}

void kernel_read(char *dev)
{
  int fd;

  sync();
  if ((fd = open(dev, O_RDONLY)) == -1) die("can't open device");
  sync(); 
  sleep(1);
  ioctl(fd, BLKRRPART, 0);
  sync();
  close(fd);
  sync();
}

int main(int argc, char **argv) 
{
  if (argc != 2) {
    fprintf(stderr, "usage: kernel_read_part <hard drive device>\n");
    exit(1);
  }
  kernel_read(argv[1]);
}
