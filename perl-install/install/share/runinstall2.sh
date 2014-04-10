#!/bin/sh

echo "You can start the installer by running install2"
echo "You can run it in GDB by running gdb-inst"
sh
exec install2 $@
