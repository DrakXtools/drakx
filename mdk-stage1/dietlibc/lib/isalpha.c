#include <ctype.h>

inline int isalpha(int c) {
  return (c>='a' && c<='z') || (c>='A' && c<='Z');
}

