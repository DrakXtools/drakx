#!/bin/bash

# this script is run by at startup on the nfs_root system, and runs the ka-deploy client 
# it also updates the 'step file' on the tftp server

# $Revision$
# $Author$
# $Date$
# $Header$
# $Id$
# $Log$
# Revision 1.4  2005/08/28 21:38:32  oblin
# ka support (initially from Antoine Ginies and Erwan Velu)
#
# Revision 1.1.2.5  2003/06/17 06:34:33  erwan
# Removing remaining dchp cache for KA
#
# Revision 1.1.2.4  2003/06/11 18:04:28  erwan
# Fixing mkreiserfs call
#
# Revision 1.1.2.3  2002/11/07 15:10:52  erwan
# SCSI support now activated
#
# Revision 1.1.2.2  2002/11/05 15:49:13  erwan
# added some files
#
# Revision 1.1.2.1  2002/11/05 11:16:54  erwan
# added ka tools in rescue
#
# Revision 1.6  2001/12/03 16:28:02  sderr
# Completely new install script
#
# Revision 1.5  2001/10/10 13:55:04  sderr
# Updates in documentation
#
# Revision 1.4  2001/06/29 09:31:45  sderr
# *** empty log message ***
#
# Revision 1.3  2001/05/31 08:51:43  sderr
# scripts/doc update to match new command-line syntax
#
# Revision 1.2  2001/05/03 12:34:41  sderr
# Added CVS Keywords to most files. Mostly useless.
#
# $State$

# This script is provided as an exmaple and should probably not be run as is


unset LANG
unset LANGUAGE

# needed for some for i in foo* loops
shopt -s nullglob

bash < /dev/tty2 >/dev/tty2 2>&1 &

# IDEA : maybe this option could be overriden by a kaopt= in the kernel command line ?
KA_SESSION_BASE="-s kainstall"

ka_call_num=0

inc_ka_session()
{
	(( ka_call_num++ ))
	cur_ka_session=$KA_SESSION_BASE$ka_call_num
}


# testing ? -- NOT FULLY IMPLEMENTED !!!!!!!!!!!!!!!!!!!!
#DONTWRITE=yes
DONTWRITE=no

# Let's find out what our IP is
ip=`/sbin/ifconfig | grep -v 127.0.0.1 | grep "inet addr" | sed 's/^.*inet addr:\([^ ]*\) .*$/\1/g' | head -n 1`

# the file tftpserver should contain the name of the .. tftpserver
server=`cat tftpserver`


# reverse a file
tac()
{
	awk '{ x[NR] = $0 } END { for (i = NR; i >= 1; i--) print x[i] }'
}

# run a command, hide its output and print OK if it suceeds, print FAILED and show the output otherwise.
runcom()
{
		echo -n "$1..." 1>&2
		shift;
		out=`"$@" 2>&1` 
		ret=$?
		if [ $ret -eq 0 ]; then
				echo $C_S"OK"$C_N 1>&2
		else
				echo $C_F"Failed"$C_N 1>&2
				echo $C_W"$out"$C_N 1>&2
		fi
		return $ret

}

# 5 4 3 2 1 zero ignition
countdown()
{
        t=$1
        while [ "$t" -ne 0 ]; do
                echo -n "$t "
                sleep 1
		# move the cursor back
		# I use now tr instead of sed because busybox's sed adds a non-wanted carriage return
		# busybox's tr does not seem to know about the [: :] stuff (?)
                echo -n "$t " | tr " 0-9" $'\x08'
		(( t-- ))
        done
	# backspace only moves the cursor back, so at this point there's still a "1" to erase
	if [ "$1" -ne 0 ] ;then
        	echo -n "  "$'\x08\x08'
	fi
}


int_shell()
{
	echo $C_H"starting an interactive shell"$C_N
	exec /bin/bash
}

fail()
{
		echo $*
		echo $C_F"--- The installation program FAILED ---"$C_N
		echo "Check your configuration -- try to read previous error messages"
		echo "This machine is going to reboot (Ctrl-S to block it) (Ctrl-C for an interactive shell)"
		trap int_shell SIGINT
		countdown 30
		do_reboot
}

do_reboot()
{
		reboot
		sleep 1234567 # do not continue the install script (/sbin/reboot does not block)
}


	
# ahem this LILO function should be fixed someday
# right now this function assumes there is a properly configured lilo on the duplicated linux system
do_lilo()
{		

	
chroot /mnt/disk << EOF
lilo
EOF


}		


run_chroot_command()
{		

	/usr/sbin/chroot /mnt/disk $*

}		


log()
{
	echo $* 1>&2
	echo $* >> /tmp/ginstlog
}

# version for the standard tftp client
std_tftp_put_file()
{
	remotef=$2
	localf=$1
	err=`echo put $localf $remotef | tftp $server 2>&1`
	err=`echo $err | grep Sent`
	if [ -z "$err" ]; then
		log tftp error: could not get/put file 
		return 1
	fi
	return 0
}

# version for the tftp client built in busybox
busybox_tftp_put_file()
{
	remotef=$2
	localf=$1
	err=`tftp -p -l $localf -r $remotef $server 2>&1`
	if [ $? -ne 0 ]; then
		log tftp error: could not get/put file $err
		return 1
	fi
	return 0
}


busybox_tftp_get_file()
{
	remotef=$1
	localf=$2
	err=`tftp -g -l $localf -r $remotef $server 2>&1`
	if [ $? -ne 0 ]; then
		log tftp error: could not get/put file $err
		return 1
	fi
	return 0
}


std_tftp_get_file()
{
	remotef=$1
	localf=$2
	err=`echo get $remotef $localf | tftp $server 2>&1`
	err=`echo $err | grep Received`
	if [ -z "$err" ]; then
		echo tftp error: could not get/put file 
		return 1
	fi
	return 0
}

tftp_get_file()
{
		busybox_tftp_get_file "$@"
}

tftp_put_file()
{
		busybox_tftp_put_file "$@"
}

# write a string ($2) in a remote file ($1)
tftp_put_in()
{
	echo "$2" > $temp
	err=`echo put $temp "$1" | tftp $server 2>&1`
	rm -f $temp
	err=`echo $err | grep Sent`
	if [ -z "$err" ]; then
		log tftp error: could not get/put file 
		return 1
	fi
	return 0
}

get_var_bis()
{
		while read a; do
			echo "$a" | grep -s -q "^ *#.*"
			if [ $? -eq 0 ]; then 
					continue 
			fi
			val=`echo "$a" | sed 's/[^"]*"\(.*[^\\]\)".*/\1/'`
			var=`echo "$a" | sed 's/[^"]*".*[^\\]" *\$\([^ ]*\)/\1/'`
			if [ "$var" = "$1" ]; then
					echo $val
					return 0
			fi
		done
		return 1
}

# fetch variable $2 from file $1
get_var()
{
		(cat $1; echo) | get_var_bis $2
}

# find the current step in the kernel command line
get_step()
{
	step=install
#	step=`cat /proc/cmdline | sed 's/.*kastep=\([^ ]*\).*/\1/'`
	if [ "$step" ]; then
		echo $step > /tmp/step
		return 0
	fi
	return 1
}


# write a new file on the tftp server
# this file is a pxelinux config file
# do this by getting the 'template file' and adding a DEFAULT at the beginning
set_step()
{
	step=$1
	
	
	runcom "Getting template file" tftp_get_file "ka/pxelinux.cfg/template" /tmp/template || return 1
	
	echo DEFAULT $step > /tmp/newcfg
	cat /tmp/template >> /tmp/newcfg
	
	runcom "Sending back new pxelinux config file" tftp_put_file /tmp/newcfg "ka/pxelinux.cfg/IP/$ip" || return 1
	
	return 0
}



# the mount_partition calls must be done in the same shell (NOT a subshell) because the global variable below has to be updated
# idea : maybe use a file instead of this variable (and since the tac function now exists, why not ?)
mounted_fs=""

# mount a partition UNDER /disk !!! (/disk is prepended to $2)
mount_partition()
{
	dev=$1
	point=$2
	
	echo -n "Mounting $C_H$1$C_N as /mnt/disk$C_H$point$C_N" 
	mkdir -p /mnt/disk$point
	test -d /mnt/disk$point || return 1
	runcom "..." mount $dev /mnt/disk/$point || return 1
	mounted_fs="$dev $mounted_fs"
	return 0
}

# umount all mounted partitions under /disk, in the reverse order
umount_partitions()
{
	for dev in $mounted_fs; do
		retries=0
		while ! runcom "Umounting $dev" umount $dev ; do
			sleep 3
			(( retries++ ))
			if [ $retries -gt 3 ]; then
				echo Failed too many times. giving up.
				break
			fi
		done
	done
}


# recreate excluded directories
# read stdin like this : u=rwx g=rwx o=rwx uid gid filename
recreate_dirs()
{
	while read line; do
		declare -a fields
		fields=( $line )
		file=/mnt/disk/${fields[5]}
#		echo $file
# note : it is possible that the directory exists already, if it was a mount point
# we need to set the permissions/users anyway
		mkdir -p $file
#		echo chmod ${fields[0]},${fields[1]},${fields[2]}  $file
		chmod ${fields[0]},${fields[1]},${fields[2]}  $file
		# argl !! chmod o+t does not work with busybox's chmod !
		# we have to handle it alone
		if echo ${fields[2]} | grep -q t; then
			chmod +t $file
		fi
		chown ${fields[3]}.${fields[4]} $file
	done
}

make_partitions()
{
	# we must be in the partfiles directory
	for file in partition_tab*; do
		drive=`echo $file | sed 's/partition_tab//'`
		cat $file | runcom "Writing partition table for $drive using sfdisk" /sbin/sfdisk /dev/$drive -uS --force || fail "error with sfdisk"
	done

	for file in fdisk_commands*; do
		drive=`echo $file | sed 's/fdisk_commands//'`
		runcom "Cleaning hard drive" dd if=/dev/zero of=/dev/$drive bs=1M count=5 || fail "Can t clean drive$drive"
		cat $file | runcom "Writing partition table for $drive using fdisk" fdisk /dev/$drive || fail "error with fdisk"
	done

}
checkDevEntries()
{ 
	if ! test -r /mnt/disk/dev/hda ; then
  		(cd /dev && tar c *) | (cd /mnt/disk/dev && tar x)
	fi
}

write_MBRs()
{
# we must be in the partfiles directory also
	for file in MBR*; do
		drive=`echo $file | sed 's/MBR//'`
		runcom "Writing new MBR for $drive" dd if=$file of=/dev/$drive bs=1 count=446
	done
}


# Colors
# Success
C_S=$'\033[1;32m'
# Failure
C_F=$'\033[1;31m'
# Warning
C_W=$'\033[1;33m'
# Normal
C_N=$'\033[0;39m'
# Hilight
C_H=$'\033[1;39m'


# Clear screen, fancy startup message.
echo $'\033'[2J$'\033'[H
echo "------| $C_H"Ka"$C_N |---- Install starting..."

temp=/tmp/ginst

# activate dma ? -- obsolete stuff I think		
# runcom "Setting HD optimizations" hdparm -c1 -d1 -K1 $HD	
		
delay=0

if ! runcom "Getting step name" get_step; then
		echo "Error: Could not get current step "
		fail
else
		step=`cat /tmp/step`
fi

echo Next Server is `cat /ka/tftpserver`

echo Current step for $ip is : \"$C_H$step$C_N\"

echo -n "Finding install type :  "
case $step in
	shell)
		echo No install, but interactive shell
		## drop the user to an interactive shell 
		exec /bin/bash
		;;
	install) 
		install_type=install
		nextstep=ready
		echo Install Linux
		;;
	test_install) 
		install_type=test_install
		nextstep=ready
		echo TEST TEST TEST
		countdown 10
		echo Install Linux TEST
		;;
esac


if [ -z "$install_type" ]; then
		echo FATAL : Could not recognize this step name
		echo "Aborting... "
		fail
fi



# receive the partition table, fstab, etc from the source node
mkdir /tmp/partfiles
inc_ka_session
echo Current session is $cur_ka_session
runcom "Receiving partitions information" /ka/ka-d-client -w $cur_ka_session -e "( cd /tmp/partfiles && tar xvf - )"	|| fail




cd /tmp/partfiles 
make_partitions


test -f /tmp/partfiles/streams || fail "Missing streams file"
first_stream=`cat /tmp/partfiles/streams | head -n 1`

if [ "$first_stream" = linux ]; then
	rcv_linux=yes
else
	rcv_linux=no
fi



#if we must receive a linux system, we need to format and mount the partitions
if [ $rcv_linux = yes ]; then	
	# format partitions
	format_partitions()
	{
		while read line; do
			declare -a fields
			fields=( $line )

			case ${fields[2]} in
				reiserfs )
					runcom "Formatting ${fields[0]} as reiserfs" mkreiserfs -f ${fields[0]} || fail
					;;
				jfs )
					runcom "Formatting ${fields[0]} as jfs" mkfs.jfs ${fields[0]} || fail
					;;
				
				xfs )
					runcom "Formatting ${fields[0]}	as xfs" mkfs.xfs -f ${fields[0]} || fail
					;;
				ext3 )
					runcom "Formatting ${fields[0]}	as ext3" mkfs.ext2 -j ${fields[0]} || fail
					;;
				ext2 )
					runcom "Formatting ${fields[0]} as ext2" mkfs.ext2 ${fields[0]} || fail
					;;
				swap ) 
					runcom "Formatting ${fields[0]} as swap" mkswap ${fields[0]} || fail
					;;
			esac
		done
	}

	format_partitions < /tmp/partfiles/pfstab	
		

	# mount the partitions

	mount_partitions()
	{
		while read line; do
			declare -a fields
			fields=( $line )

			case ${fields[2]} in
				reiserfs )
					mount_partition ${fields[0]} ${fields[1]} || fail
					;;
				xfs )
					mount_partition ${fields[0]} ${fields[1]} || fail
					;;
				jfs )
					mount_partition ${fields[0]} ${fields[1]} || fail
					;;
				ext3 )
					mount_partition ${fields[0]} ${fields[1]} || fail
					;;
				ext2 )
					mount_partition ${fields[0]} ${fields[1]} || fail
					;;
			esac
		done
	}

	# NOTE
	# I replaced cat truc | mount_partitions by mount_partitions < truc
	# because in the former case mount_partitions runs in a subshell and the $mounted_fs value is lost
	mount_partitions < /tmp/partfiles/pfstab

	echo ++++++++++++++++++++++++++
	mount
	echo ++++++++++++++++++++++++++

	delay=0
else
	delay=10
fi

if [ $DONTWRITE != yes ]; then
	for stream in `cat /tmp/partfiles/streams`; do
		if [ "$stream" = "linux" ]; then
			# partitions already formatted/mounted, just copy now
			# untar data from the master 'on the fly'
			echo -n "Linux copy is about to start "
			countdown $delay
			echo
			inc_ka_session
			/ka/ka-d-client -w $cur_ka_session -e "(cd /mnt/disk; tar --extract  --read-full-records --same-permissions --numeric-owner --sparse --file - ) 2>/dev/null" || fail

			runcom "Syncing disks" sync 
			echo Linux copy done.
			echo Creating excluded directories
			cat /tmp/partfiles/excluded | recreate_dirs
			#echo Setting up networking
			#/ka/setup_network.sh
			#delay=10
		else
			# maybe receive some raw partition dumps
			echo Raw copy of $stream is about to start
			countdown $delay
			inc_ka_session
			/ka/ka-d-client -w $cur_ka_session -e "dd of=$stream bs=65536" || fail
			delay=10
		fi
	done

	echo "Removing computing interfaces"
	rm -f /mnt/disk/etc/sysconfig/network-scripts/ifcfg-eth1 >/dev/null 2>&1

	echo "Removing duplicated dhcp cache"
	rm -f /mnt/disk/etc/dhcpc/* >/dev/null 2>&1

	echo "Writing modules.conf" 
	/usr/bin/perl /ka/gen_modules_conf.pl >/mnt/disk/etc/modules.conf

	echo "Writing modprobe.conf"
	chroot /mnt/disk/ /sbin/generate-modprobe.conf >/mnt/disk/etc/modprobe.conf
	
	echo "Running mkinitrd"
	/ka/make_initrd

	cd /tmp/partfiles
	write_MBRs

	
	if test -f /tmp/partfiles/command; then
		checkDevEntries
		command_to_run=`cat /tmp/partfiles/command`
		runcom "Running $command_to_run" run_chroot_command "$command_to_run"
	fi

else
	echo " I would run ka-deploy(s) and then lilo/mbr  "
	sleep 1
fi

# maybe there is a last dummy ka-deploy for synchronization
if test -f /tmp/partfiles/delay; then
	sleep 1
	inc_ka_session
	runcom "Waiting source node signal to end installation"	/ka/ka-d-client -w $cur_ka_session -e "cat" || fail
fi

umount_partitions

	
# Update the step file on the tftp server
#runcom 'Sending back new $step' set_step $nextstep || fail

echo -n Rebooting...
countdown 3
do_reboot
