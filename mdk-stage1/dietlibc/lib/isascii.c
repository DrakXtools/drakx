#include <ctype.h>

int isascii(int c) {
  return (c & 0x80) == 0;
}

