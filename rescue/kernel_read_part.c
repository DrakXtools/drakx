#include <stdio.h>
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
  if ((fd = open(dev, O_RDONLY)) == -1) die("can't open device");
  ioctl(fd, BLKRRPART, 0);
  close(fd);
}

int main(int argc, char **argv) 
{
  if (argc != 2) {
    fprintf(stderr, "usage: kernel_read_part <hard drive device>\n");
    exit(1);
  }
  kernel_read(argv[1]);
}
