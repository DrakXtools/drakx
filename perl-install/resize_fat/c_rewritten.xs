#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* set by scan_fat, used by next */
short *fat = NULL;
char *fat_flag_map = NULL;
unsigned int *fat_remap = NULL;
int fat_remap_size;
int type_size, nb_clusters, bad_cluster_value;

unsigned int next(unsigned int cluster) {
  short *p = fat + type_size * cluster;
  if (cluster > nb_clusters + 2) croak("fat::next: cluster %d outside filesystem", cluster);
  return type_size == 1 ? *p : *((unsigned int *) p);
}

void set_next(unsigned int cluster, unsigned int val) {
  short *p = fat + type_size * cluster;
  if (cluster > nb_clusters + 2) croak("fat::set_next: cluster %d outside filesystem", cluster);
  type_size == 1 ? *p : *((unsigned int *) p) = val;
}

MODULE = resize_fat::c_rewritten PACKAGE = resize_fat::c_rewritten

void 
read_fat(fd, offset, size, magic)
  int fd
  int offset
  int size
  unsigned char magic
  PPCODE:
{
  fat = (short *) malloc(size);
  if (lseek(fd, offset, SEEK_SET) != offset ||
      read(fd, fat, size) != size) {
    free(fat); fat = NULL;
    croak("reading FAT failed");
  }
  if (magic != *(unsigned char *) fat) {
    free(fat); fat = NULL;
    croak("FAT has invalid signature");
  }
}

void
write_fat(fd, size)
  int fd
  int size
  PPCODE:
{
  if (write(fd, fat, size) != size) croak("write_fat: write failed");
}

void
free_all()
  PPCODE:
#define FREE(p) if (p) free(p), p = NULL;
  FREE(fat);
  FREE(fat_flag_map);
  FREE(fat_remap);
#undef FREE

void
scan_fat(nb_clusters_, type_size_)
  int nb_clusters_
  int type_size_
  PPCODE:
{
  unsigned int v;  
  int free = 0, bad = 0, used = 0;
  short *p;
  
  type_size = type_size_; nb_clusters = nb_clusters_;
  bad_cluster_value = type_size ? 0xffffff7 : 0xfff7;

  if (type_size % 16) fprintf(stderr, "unable to handle type_size"), exit(1);
  type_size /= 16;

  for (p = fat + 2 * type_size; p < fat + type_size * (nb_clusters + 2); p += type_size) {
    v = type_size == 1 ? *p : *((unsigned int *) p);

    if (v == 0) free++;
    else if (v == bad_cluster_value) bad++;
  }
  used = nb_clusters - free - bad;
  EXTEND(SP, 3);
  PUSHs(sv_2mortal(newSViv(free)));
  PUSHs(sv_2mortal(newSViv(bad)));
  PUSHs(sv_2mortal(newSViv(used)));
}

unsigned int
next(unused, cluster)
  void *unused
  unsigned int cluster
  CODE:
  RETVAL = next(cluster);
  OUTPUT:
  RETVAL

void
set_next(unused, cluster, val)
  void *unused
  unsigned int cluster
  unsigned int val
  CODE:
  set_next(cluster, val);

void
allocate_fat_flag(size)
  int size
  CODE:
  fat_flag_map = malloc(size);

int
checkFat(cluster, type, name)
  unsigned int cluster
  int type
  char *name
  CODE:
  int nb = 0;

  for (; cluster < bad_cluster_value; cluster = next(cluster)) {
    if (cluster == 0) croak("Bad FAT: unterminated chain for %s\n", name);

    if (fat_flag_map[cluster]) croak("Bad FAT: cluster %d is cross-linked for %s\n", cluster, name);
    fat_flag_map[cluster] = type;
    nb++;
  }
  RETVAL = nb;
  OUTPUT:
  RETVAL

unsigned int
flag(cluster)
  unsigned int cluster
  CODE:
  RETVAL = fat_flag_map[cluster];
  OUTPUT:
  RETVAL

void
set_flag(cluster, flag)
  unsigned int cluster
  int flag
  CODE:
  fat_flag_map[cluster] = flag;

void
allocate_fat_remap(size)
  int size
  CODE:
  fat_remap_size = size / 4;
  fat_remap = (unsigned int *) malloc(size);

unsigned int
fat_remap(cluster)
  unsigned int cluster
  CODE:
  if (cluster >= bad_cluster_value) {
    RETVAL = cluster; /* special cases */
  } else {
    if (fat_remap == NULL) croak("fat_remap NULL in fat_remap");
    if (cluster >= fat_remap_size) croak("cluster %d >= %d in fat_remap", cluster, fat_remap_size);
    RETVAL = fat_remap[cluster];
  }
  OUTPUT:
  RETVAL

void
set_fat_remap(cluster, val)
  unsigned int cluster
  unsigned int val
  CODE:
  fat_remap[cluster] = val;
