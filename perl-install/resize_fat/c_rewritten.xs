#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* set by scan_fat, used by next */
short *fat = NULL;
char *fat_flag_map = NULL;
unsigned int *fat_remap = NULL;
int fat_remap_size;
int type_size, nb_clusters, bad_cluster_value;

void free_all() {
#define FREE(p) if (p) free(p), p = NULL;
  FREE(fat);
  FREE(fat_flag_map);
  FREE(fat_remap);
#undef FREE
}

unsigned int next(unsigned int cluster) {
  short *p = fat + type_size * cluster;
  if (!fat) {
    free_all();
    croak("fat::next: trying to use null pointer");
  }
  if (cluster >= nb_clusters + 2) {
    free_all();
    croak("fat::next: cluster %d outside filesystem", cluster);
  }
  return type_size == 1 ? *p : *((unsigned int *) p);
}

void set_next(unsigned int cluster, unsigned int val) {
  short *p = fat + type_size * cluster;
  if (!fat) {
    free_all();
    croak("fat::set_next: trying to use null pointer");
  }
  if (cluster >= nb_clusters + 2) {
    free_all();
    croak("fat::set_next: cluster %d outside filesystem", cluster);
  }
  type_size == 1 ? *p : *((unsigned int *) p) = val;
}

MODULE = resize_fat::c_rewritten PACKAGE = resize_fat::c_rewritten

PROTOTYPES: DISABLE


void 
read_fat(fd, offset, size, magic)
  int fd
  int offset
  int size
  unsigned char magic
  PPCODE:
{
  fat = (short *) malloc(size);
  if (!fat) {
    free_all();
    croak("read_fat: not enough memory");
  }
  if (lseek(fd, offset, SEEK_SET) != offset ||
      read(fd, fat, size) != size) {
    free_all();
    croak("read_fat: reading FAT failed");
  }
  if (magic != *(unsigned char *) fat) {
    free_all();
    croak("read_fat: FAT has invalid signature");
  }
}

void
write_fat(fd, size)
  int fd
  int size
  PPCODE:
{
  if (write(fd, fat, size) != size) {
    free_all();
    croak("write_fat: write failed");
  }
}

void
free_all()
  PPCODE:
  free_all();

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
  bad_cluster_value = type_size == 32 ? 0x0ffffff7 : 0xfff7;

  if (type_size % 16) {
    free_all();
    croak("scan_fat: unable to handle FAT%d", type_size);
  }
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
  fat_flag_map = calloc(size, 1);
  if (!fat_flag_map) {
    free_all();
    croak("allocate_fat_flag: not enough memory");
  }

int
checkFat(cluster, type, name)
  unsigned int cluster
  int type
  char *name
  CODE:
  int nb = 0;

  if (!fat_flag_map) {
    free_all();
    croak("Bad FAT: trying to use null pointer");
  }
  for (; cluster < bad_cluster_value; cluster = next(cluster)) {
    if (cluster == 0) {
      free_all();
      croak("Bad FAT: unterminated chain for %s\n", name);
    }
    if (cluster >= nb_clusters + 2) {
      free_all();
      croak("Bad FAT: chain outside filesystem for %s\n", name);
    }
    if (fat_flag_map[cluster]) {
      free_all();
      croak("Bad FAT: cluster %d is cross-linked for %s\n", cluster, name);
    }
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
  if (!fat_flag_map) {
    free_all();
    croak("Bad FAT: trying to use null pointer");
  }
  if (cluster >= nb_clusters + 2) {
    free_all();
    croak("Bad FAT: going outside filesystem");
  }
  RETVAL = fat_flag_map[cluster];
  OUTPUT:
  RETVAL

void
set_flag(cluster, flag)
  unsigned int cluster
  int flag
  CODE:
  if (!fat_flag_map) {
    free_all();
    croak("Bad FAT: trying to use null pointer");
  }
  if (cluster >= nb_clusters + 2) {
    free_all();
    croak("Bad FAT: going outside filesystem");
  }
  fat_flag_map[cluster] = flag;

void
allocate_fat_remap(size)
  int size
  CODE:
  fat_remap_size = size;
  fat_remap = (unsigned int *) calloc(size, sizeof(unsigned int *));
  if (!fat_remap) {
    free_all();
    croak("allocate_fat_remap: not enough memory");
  }

unsigned int
fat_remap(cluster)
  unsigned int cluster
  CODE:
  if (!fat_remap) {
    free_all();
    croak("fat_remap: trying to use null pointer");
  }
  if (cluster >= bad_cluster_value) {
    RETVAL = cluster; /* special cases */
  } else {
    if (cluster >= fat_remap_size) {
      free_all();
      croak("fat_remap: cluster %d >= %d in fat_remap", cluster, fat_remap_size);
    }
    RETVAL = fat_remap[cluster];
  }
  OUTPUT:
  RETVAL

void
set_fat_remap(cluster, val)
  unsigned int cluster
  unsigned int val
  CODE:
  if (!fat_remap) {
    free_all();
    croak("set_fat_remap: trying to use null pointer");
  }
  if (cluster >= fat_remap_size) {
    free_all();
    croak("set_fat_remap: cluster %d >= %d in set_fat_remap", cluster, fat_remap_size);
  }
  if (val < bad_cluster_value && val >= fat_remap_size) {
    free_all();
    croak("set_fat_remap: remapping cluster %d to cluster %d >= %d in set_fat_remap", cluster, val, fat_remap_size);
  }
  fat_remap[cluster] = val;
