#ifndef __GETOPT_H__
#define __GETOPT_H__

extern int optind,opterr;
extern char *optarg;
int getopt(int argc, char *argv[], char *options);

/* the following was taken from GNU getopt, it's not actually supported
 * by the diet libc! */
extern int optopt;

struct option {
  const char* name;
  int has_arg;
  int* flag;
  int val;
};

#define no_argument             0
#define required_argument       1
#define optional_argument       2

extern int getopt_long(int argc, char *const *argv,
		       const char *shortopts, const struct option *longopts,
		       int *longind);

extern int getopt_long_only(int argc, char *const *argv,
			    const char *shortopts, const struct option *longopts,
			    int *longind);


#endif
