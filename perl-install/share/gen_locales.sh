#!/bin/sh

rm -rf .tmp ; mkdir .tmp ; cd .tmp
tar xfj ../locales-skeleton.tar.bz2

# locale utf-8
for i in LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME LC_MESSAGES/SYS_LC_MESSAGES ; do
    install -D -m 644 /usr/share/locale/UTF-8/$i usr/share/locale/UTF-8/$i
done

# lc_ctype for non common encodings
rm -rf .tmp2 ; mkdir .tmp2 ; cd .tmp2
for i in ja ko ; do
    ii=locales-`echo $i | sed 's/\(..\).*/\1/'`
    rpm2cpio /RPMS/$ii-*.rpm | cpio -id --quiet
    f=usr/share/locale/$i/LC_CTYPE
    [ -e $f ] || { echo missing $f in package $ii ; exit 1 ; }
    install -D -m 644 $f ../$f
    (cd ../usr/share/locale/$i ; ln -s ../UTF-8/* . 2>/dev/null)
    rm -rf *
done
cd .. ; rm -rf .tmp2

# special case for chineese (why is it needed?)
rm -rf .tmp2 ; mkdir .tmp2 ; cd .tmp2
for i in zh_CN.GB2312 zh_TW.Big5 ; do
    ii=locales-`echo $i | sed 's/\(..\).*/\1/'`
    rpm2cpio /RPMS/$ii-*.rpm | cpio -id --quiet
    for f in LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME LC_MESSAGES/SYS_LC_MESSAGES ; do
	f=usr/share/locale/$i/$f
	[ -e $f ] || { echo missing $f in package $ii ; exit 1 ; }
	install -D -m 644 $f ../$f
    done
    rm -rf *
done
cd .. ; rm -rf .tmp2

(cd usr/share/locale ; mv zh_CN.GB2312 GB2312 ; mv zh_TW.Big5 BIG5)

perl -I../.. ../gen_locales.pl || exit 1


for i in common C en_US.UTF-8 iso8859-1 ja ko tscii-0 zh_CN zh_TW.big5 ; do
    cp -a /usr/X11R6/lib/X11/locale/$i usr/X11R6/lib/X11/locale
done

tar cfj ../locales.tar.bz2 usr

cd .. ; rm -rf .tmp
