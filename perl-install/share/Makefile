all: locales.tar.bz2

# /usr/lib/libc.a to depend on the current glibc
locales.tar.bz2: locales-skeleton.tar.bz2 gen_locales.sh /usr/lib/libc.a
	./gen_locales.sh
