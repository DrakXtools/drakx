#!/bin/sh

rm -rf .tmp ; mkdir .tmp ; cd .tmp
tar xfj ../locales-skeleton.tar.bz2

# locale utf-8
for i in LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME LC_MESSAGES/SYS_LC_MESSAGES ; do
    install -D -m 644 /usr/share/locale/UTF-8/$i usr/share/locale/en_US.UTF-8/$i
done

perl -I../.. ../gen_locales.pl || exit 1

for i in C en_US.UTF-8 iso8859-1 ; do
    cp -a /usr/X11R6/lib/X11/locale/$i usr/X11R6/lib/X11/locale
done

tar cfj ../locales.tar.bz2 usr

cd .. ; rm -rf .tmp
