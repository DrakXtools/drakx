#!/bin/sh

rm -rf .tmp ; mkdir .tmp ; cd .tmp
tar xfj ../locales-skeleton.tar.bz2

# locale utf-8
for i in LC_ADDRESS LC_COLLATE LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME LC_MESSAGES/SYS_LC_MESSAGES ; do
    cp -f /usr/share/locale/UTF-8/$i usr/share/locale/UTF-8/$i
done

# lc_ctype for common encoding
for i in CP1251 ISO-8859-13 ISO-8859-14 ISO-8859-15 ISO-8859-2 ISO-8859-3 ISO-8859-7 ISO-8859-9 ISO-8859-9E ; do
    f=usr/share/locale/$i/LC_CTYPE
    [ -e /$f ] || { echo missing /$f ; exit 1 ; }
    cp -f /$f $f
done

rm -rf .tmp2 ; mkdir .tmp2 ; cd .tmp2
for i in hy ja ko th vi ; do
    ii=locales-`echo $i | sed 's/\(..\).*/\1/'`
    rpm2cpio /RPMS/$ii-*.rpm | cpio -id --quiet
    f=usr/share/locale/$i/LC_CTYPE
    [ -e $f ] || { echo missing $f in package $ii ; exit 1 ; }
    cp -f $f ../$f
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
	cp -f $f ../$f
    done
    rm -rf *
done
cd .. ; rm -rf .tmp2


tar cfj ../locales.tar.bz2 usr

cd .. ; rm -rf .tmp
