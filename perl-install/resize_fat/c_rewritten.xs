#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* set by scan_fat, used by next */
short *fat = NULL;
int type_size, nb_clusters, bad_cluster_value;
char *fat_flag_map;

unsigned int next(unsigned int cluster) {
  short *p = fat + type_size * cluster;
  if (cluster > nb_clusters + 2) croak("fat::next: cluster %d outside filesystem", cluster);
  return type_size == 1 ? *p : *((unsigned int *) p);
}

MODULE = resize_fat::c_rewritten PACKAGE = resize_fat::c_rewritten

void
scan_fat(fat_, nb_clusters_, type_size_)
  char *fat_
  int nb_clusters_
  int type_size_
  PPCODE:
  unsigned int v;  
  int free = 0, bad = 0, used = 0;
  short *p;
  
  fat = (short*) fat_; type_size = type_size_; nb_clusters = nb_clusters_;
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

unsigned int
next(unused, cluster)
  void *unused
  unsigned int cluster
  CODE:
  RETVAL = next(cluster);
  OUTPUT:
  RETVAL

int
checkFat(fat_flag_map_, cluster, type, name)
  char *fat_flag_map_
  unsigned int cluster
  int type
  char *name
  CODE:
  int nb = 0;
  fat_flag_map = fat_flag_map_;

  for (; cluster < bad_cluster_value; cluster = next(cluster)) {
    if (cluster == 0) croak("Bad FAT: unterminated chain for %s\n", name);

    if (fat_flag_map[cluster]) croak("Bad FAT: cluster $cluster is cross-linked for %s\n", name);
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

