all: locales.tar.bz2

# /usr/lib/libc.a to depend on the current glibc
# /usr/share/i18n/locale/en_US to ensure we have glibc-localedata
locales.tar.bz2: locales-skeleton.tar.bz2 gen_locales.sh /usr/lib/libc.a /usr/share/i18n/locales/en_US
	./gen_locales.sh
