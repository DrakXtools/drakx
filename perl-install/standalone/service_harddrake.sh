#!/bin/bash
#
# harddrake		This scripts runs the harddrake hardware probe.
#
# chkconfig: 345 05 95
# description: 	This runs the hardware probe, and optionally configures \
#		changed hardware.

# This is an interactive program, we need the current locale

[[ -f /etc/profile.d/lang.sh ]] && . /etc/profile.d/lang.sh

# Source function library.
. /etc/rc.d/init.d/functions


SUBSYS=/var/lock/subsys/harddrake

case "$1" in
 start)
# We (mdk) don't support updfstab (yet)
#	action "Updating /etc/fstab" /usr/sbin/updfstab

	gprintf "Checking for new hardware"
 	/usr/share/harddrake/service_harddrake 2>/dev/null
	RETVAL=$?
	if [ "$RETVAL" -eq 0 ]; then
  	   action "" /bin/true
	else
	   action "" /bin/false
	fi
	# We don't want to run this on random runlevel changes.
	touch $SUBSYS
#	[ /etc/modules.conf -nt /lib/modules/$(uname -r)/modules.dep ] && touch /lib/modules/$(uname -r)/modules.dep 2>/dev/null >/dev/null || : &
	exit $RETVAL
	;;
 status)
	   if [ -f $SUBSYS ]; then
		   gprintf "Harddrake service was runned at boot time"
	   else gprintf "Harddrake service was not runned at boot time"
	   fi
	;;
 reload)
        ;;
 stop)
	# dummy
 	rm -f $SUBSYS
 	;;
 *)
 	gprintf "Usage: %s {start|stop}\n" "$0"
	exit 1
	;;
esac
