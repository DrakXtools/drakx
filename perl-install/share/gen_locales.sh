#!/bin/sh

rm -rf .tmp ; mkdir .tmp ; cd .tmp
tar xfj ../locales-skeleton.tar.bz2

# locale utf-8
for i in LC_ADDRESS LC_COLLATE LC_CTYPE LC_IDENTIFICATION LC_MEASUREMENT LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER LC_TELEPHONE LC_TIME LC_MESSAGES/SYS_LC_MESSAGES ; do
    install -D -m 644 /usr/share/locale/UTF-8/$i usr/share/locale/UTF-8/$i
done

# lc_ctype for common encoding
for i in CP1251 ISO-8859-13 ISO-8859-14 ISO-8859-15 ISO-8859-2 ISO-8859-3 ISO-8859-7 ISO-8859-9 ISO-8859-9E ; do
    f=usr/share/locale/$i/LC_CTYPE
    [ -e /$f ] || { echo missing /$f ; exit 1 ; }
    install -D -m 644 /$f $f
    (cd usr/share/locale/$i ; ln -s ../UTF-8/* . 2>/dev/null)
done

az ka vi
# for non common encodings, build them locally to ensure they are present
for i in ISO-8859-9E ARMSCII-8 GEORGIAN-ACADEMY KOI8-K TCVN-5712
do
    /usr/bin/localedef -c -i en_US -f $i ./$i

    f=usr/share/locale/$i/LC_CTYPE
    [ -e ./$i/LC_CTYPE ] || { echo missing ./$i/LC_CTYPE ; exit 1 ; }
    install -D -m 644 ./$i/LC_CTYPE $f
    (cd usr/share/locale/$i ; ln -s ../UTF-8/* . 2>/dev/null)
done

# lc_ctype for non common encodings
rm -rf .tmp2 ; mkdir .tmp2 ; cd .tmp2
for i in ja ko ta th ; do
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


for i in common C armscii-8 en_US.UTF-8 georgian-ps iso8859-1 iso8859-13 iso8859-14 iso8859-15 iso8859-2 iso8859-3 iso8859-5 iso8859-7 iso8859-9 iso8859-9e ja ko koi8-r koi8-u koi8-k microsoft-cp1251 microsoft-cp1255 microsoft-cp1256 th_TH tscii-0 vi_VN.tcvn zh_CN zh_TW.big5 ; do
    cp -a /usr/X11R6/lib/X11/locale/$i usr/X11R6/lib/X11/locale
done

tar cfj ../locales.tar.bz2 usr

cd .. ; rm -rf .tmp
