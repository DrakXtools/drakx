#ifndef _STDLIB_H
#define _STDLIB_H

#include <sys/cdefs.h>
#include <sys/types.h>

void *calloc(size_t nmemb, size_t size) __THROW;
void *malloc(size_t size) __THROW;
void free(void *ptr) __THROW;
void *realloc(void *ptr, size_t size) __THROW;

void *alloca(size_t size);

char *getenv(const char *name) __pure__;

int atexit(void (*function)(void)) __THROW;

double strtod(const char *nptr, char **endptr) __THROW;
long int strtol(const char *nptr, char **endptr, int base);
unsigned long int strtoul(const char *nptr, char **endptr, int base);

int __ltostr(char *s, int size, unsigned long i, int base, char UpCase);
#ifdef __GNUC__
long long int strtoll(const char *nptr, char **endptr, int base);
unsigned long long int strtoull(const char *nptr, char **endptr, int base);
int __lltostr(char *s, int size, unsigned long long i, int base, char UpCase);
#endif

int atoi(const char *nptr);

void abort(void);
void exit(int);

extern char **environ;

#define	WIFSTOPPED(status)	(((status) & 0xff) == 0x7f)
#define	WIFSIGNALED(status)	(!WIFSTOPPED(status) && !WIFEXITED(status))
#define	WEXITSTATUS(status)	(((status) & 0xff00) >> 8)
#define	WTERMSIG(status)	((status) & 0x7f)
#define	WSTOPSIG(status)	WEXITSTATUS(status)
#define	WIFEXITED(status)	(WTERMSIG(status) == 0)


#endif
