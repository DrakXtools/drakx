#!/bin/sh

echo "Starting Udev\n"
perl -I/usr/lib/libDrakX -Minstall::install2 -e "install::install2::start_udev()"
echo "You can start the installer by running install2"
echo "You can run it in GDB by running gdb-inst"
/usr/bin/busybox sh
exec install2
