#!/bin/bash

setterm -powersave off
setterm -blank 0

if [ -r ./restore-image-lib.sh ]; then
	. ./restore-image-lib.sh
elif [ -r /usr/lib/restore-image-lib.sh ]; then
	. /usr/lib/restore-image-lib.sh
fi

export PATH="/sbin:/bin:/usr/sbin:/usr/bin"

mnt_dir="/tmp/mnt"
restore_media="/tmp/media"
images_dir="$restore_media/images"
images="$images_dir/list"
images_config="$images_dir/config"
image=""

function read_config()
{
    if [ -r "$images_config" ]; then
        . $images_config
    fi
}

function image_list()
{
	list=$(cat $images | awk -F',' \
		'{ print $1 " " $2 " " $4 }')

	echo $list
}

function image_file()
{
	country="$1"

	file=$(grep ^$country $images | awk -F',' '{ print $3 }')

	echo $file
}

function welcome()
{
	while true; do
		clear
		msg="\n       Welcome to $TITLE\n\
\nThe following images were found, select one:\n "
		opcao=$(dialog --backtitle "$BACKTITLE" --title "$TITLE" \
				--stdout --radiolist "$msg" 0 0 0 \
				$(image_list))

		if [ "$?" != "0" ]; then
			_yesno "\nInterrupt installation?\n "
			if [ "$?" = "0" ]; then
				_shutdown
			fi
		else
			if [ -z "$opcao" ]; then
				continue
			else
				image=$(image_file $opcao)
				break
			fi
		fi
	done

	# disable kernel messages in the console
	echo "1 4 1 7" > /proc/sys/kernel/printk
}

function install_warning()
{
	clear
	_yesno "\nWARNING: This process will erase all data in this machine, \
do you want to continue?\n "
	if [ "$?" != "0" ]; then
		_shutdown
	fi
}

function detect_root()
{
		dev=$(sed '\|'$restore_media'|!d;s/[0-9] .*$//;s/^.*\///' /proc/mounts)
		devices=$(grep "^ .*[^0-9]$" < /proc/partitions | grep -v ${dev} | awk '$3 > '$MIN_DISKSIZE' { print $4,$3 }')

		devs_found=$(echo $devices | wc -w)
		# we might use it later again
		fdisk -l | grep "^/dev/" | grep -v ${dev} > /tmp/fdisk.log

		if ! grep -qe "FAT\|NTFS\|HPFS" /tmp/fdisk.log; then
			rm -rf /tmp/fdisk.log
			if [ "$devs_found" -gt "2" ]; then
	 			if [ ! -z ${dev} ]; then
	 				opcao=$(dialog --backtitle "$BACKTITLE" --title "$TITLE" --stdout --menu 'Choose one of the detected devices to restore to (check the blocks size column first):' 8 50 0 $devices )
	 				if [ "$?" != "0" ]; then
	 					_yesno "\nInterrupt installation?\n "
	 					if [ "$?" = "0" ]; then
	 						_shutdown
	 					fi
	 				else
	 					root=${opcao}
	 				fi 
	 			fi
			else
			    root=$(echo ${devices} | cut -d ' ' -f 1)
			fi
		else
			root=$(resize_win32 $(echo ${devices} | cut -d ' ' -f 1))
		fi
		
		echo "${root}"
}

function resize_win32()
{
	# from detect_root()
	disk=${1}

	# won't handle complex layouts
	if [ ! $(grep "^/dev" /tmp/fdisk.log | wc -l) -gt 1 ]; then
		set -f
		# get the last created windows partition information
		partition=$(grep -e "FAT\|NTFS\|HPFS" /tmp/fdisk.log | tail -1)
		device=$(echo ${partition} | sed 's/ .*$//')
		set +f

		# it might be needed, for safety
		device_type=$(vol_id --type ${device})
		modprobe ${device_type}

		# get the next partition integer
		number=$(echo ${device} | sed 's@/dev/...@@g')
		let number++
	
		case ${device_type} in
			vfat) device_id=b  ;;
			ntfs) device_id=7  ;;
			hpfs) device_id=87 ;;
		esac

		# df for that partition
		mount ${device} /mnt
		size=$(df ${device} | tail -1) 
		umount /mnt

		# its diskspace
		used=$(echo ${size} | awk '{ print $3 }')
		left=$(echo ${size} | awk '{ print $4 }')
		avail=$((${left}/2))

		if [ ! ${avail} -lt ${MIN_DISKSIZE} ]; then
			# wrapper around libdrakx by blino (it takes half of 'left')
			diskdrake-resize ${device} ${device_type} $(($((${used}+${avail}))*2)) &>/dev/null

			# we need some free sector here, rebuilding layout
			fdisk /dev/${disk} &>/dev/null <<EOF
d
n
p
$((${number}-1))

+$((${used}+${avail}))K
t
${device_id}
a
$((${number}-1))
w
EOF
			# adds linux partition to the end of the working disk
			fdisk /dev/${disk} &>/dev/null <<EOF
n
p
${number}

+${MIN_DISKSIZE}K
t
${number}
83
w
EOF
		else
			rm -f /tmp/fdisk.log
		fi
	else
		rm -f /tmp/fdisk.log
	fi

	echo "${disk}${number}"
}

function write_image()
{
	dialog --backtitle "$BACKTITLE" --title "$TITLE" --infobox "\nTrying to detect your root partition and disk...\n" 4 55

	root=$(detect_root)
	if [ -z ${root} ]; then
        	_msgbox "\nError writing image: disk device not detected.\n"
		# so that netbooks using USB sticks as disks can retry (like Gdium)
		welcome
		root=$(detect_root)
	fi
	
	image=$(cat $images_dir/list | cut -d ',' -f 3)
	extension=$(echo $image | cut -d '.' -f 3)
	case $extension in
		gz) uncomp=zcat ;;
		bz2) uncomp=bzcat ;;
		*) uncomp=cat ;;
	esac

	# the actual dumping command, from image to disk
	${uncomp} ${images_dir}/${image} | (dd of=/dev/null bs=1 count=32256 &>/dev/null; dd bs=4M of=/dev/${root} >/tmp/backup.out) &

	sleep 3
	pid=$(ps ax | grep 'dd bs=4M of' | grep -v grep | awk '{ print $1 }')
	total=1000

	while [ true ]; do
		ps | grep -q $pid
		if [ $? -eq 0 ]; then
			/bin/kill -SIGUSR1 $pid
			unit=$(tail -n 1 /tmp/backup.out | \
				cut -d'(' -f2 | cut -d')' -f1 |\
				awk '{ print $2 }')

			complete=$(tail -n 1 /tmp/backup.out | \
				cut -d'(' -f2 | cut -d')' -f1 | \
				awk '{ print $1 }' | cut -d'.' -f1)
			if [ x"$unit" = x"GB" ]; then
				complete=$((complete*1000))
			fi
			echo $((complete*100/total))
			sleep 1
		else
			break
		fi
	done | dialog --backtitle "$BACKTITLE" --title "$TITLE" --gauge "\nWriting image..." 8 45

	in=$(tail -n 3 /tmp/backup.out | grep 'in$' | cut -d' ' -f1)
	out=$(tail -n 3 /tmp/backup.out | grep 'out$' | cut -d' ' -f1)

	if [ x"$in" != x"$out" ]; then
		_msgbox "\nError writing image!\n"
		sleep 24h
	fi
}

function grub_setup()
{
		root=${1}
		grub_dir=${2}

		# install the bootloader
		grub <<EOF
device (hd0) /dev/${root%[0-9]}
root (hd0,1)
setup (hd0)
quit
EOF
		# change the partition order and boot timeout accordingly
		sed -i 's/(hd0,0)/(hd0,1)/g;/^timeout/s/$/0/' ${grub_dir}/menu.lst

		# dualboot configuration for grub
		cat >> ${grub_dir}/menu.lst <<EOF
title Microsoft Windows
root (hd0,0)
makeactive
rootnoverify(hd0,0)
chainloader +1
EOF
}

function expand_fs()
{
	if [ ! -s /tmp/fdisk.log ]; then
		root=${root%[0-9]}1
	fi
	filesystem_type=$(dumpe2fs -h /dev/${root} 2>/dev/null| grep "Filesystem OS type" | awk '{ print $4 }')
	if [ "${filesystem_type}" = "Linux" ]; then
                dialog --backtitle "$BACKTITLE" --title "$TITLE" --infobox "Finishing Install... Expanding ${root}" 3 40
		disk=/dev/${root%[0-9]}
		main_part=/dev/${root}

		# FIXME: absurdly dirty hack
                num=${root##sda}
		let num++
		swap_part=/dev/${root%[0-9]}${num}

		main_part_sectors=
		if [ -n "$SWAP_BLOCKS" ]; then
		    if [ -n "$EXPAND_FS" ]; then
			total_blocks=$(sfdisk -s $disk)
			main_part_blocks=$((total_blocks-SWAP_BLOCKS))
			main_part_sectors=$((main_part_blocks*2))
		    else
	                main_part_sectors=$(sfdisk -d $disk | perl -lne 'm|^'$main_part'\b.*,\s*size\s*=\s*(\d+)\b| and print($1), exit')
		    fi
		fi
		if [ -n "$SWAP_BLOCKS" ]; then
		    parted $disk -- mkpartfs primary linux-swap ${main_part_sectors}s -1s yes
		    mkswap -L swap $swap_part
		fi
		if [ -n "$EXPAND_FS" ]; then
		    sfdisk -d $disk | sed -e "\|$main_part|  s/size=.*,/size= ,/" | sfdisk -f $disk
		    e2fsck -fy $main_part
		    resize2fs $main_part
		fi
		mkdir -p $mnt_dir
		mount $main_part $mnt_dir
		grub_dir="$mnt_dir/boot/grub"
		if [ -d "$grub_dir" ]; then
		    echo "(hd0) $disk" > "$grub_dir/device.map"
		    if [ -s /tmp/fdisk.log ]; then
   	                grub_setup ${root} ${grub_dir}
                    fi
		fi
		if [ -n "$MKINITRD" ]; then
		    mount -t sysfs none "$mnt_dir/sys"
		    mount -t proc none "$mnt_dir/proc"
		    echo > /proc/sys/kernel/modprobe # rescue's modprobe does not handle modprobe -q and aliases
		    chroot $mnt_dir bootloader-config --action rebuild-initrds
		    umount "$mnt_dir/sys"
		    umount "$mnt_dir/proc"
		fi
		umount $mnt_dir
	fi
}

# installation steps
welcome
read_config
install_warning
write_image
expand_fs

# all done!
_msgbox "\nInstallation process finished.\nPress ENTER to shutdown.\n "

_shutdown

