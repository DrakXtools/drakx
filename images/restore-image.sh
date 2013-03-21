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
win32_part_dev=
win32_part_type=
win32_part_new_size=

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
	if [ -n "${win32_part_dev}" ]; then
	    warn_msg="Windows installation detected.\nWe will set it up as dual boot. \
You may lose some data.\nPlease backup before proceeding."
	else
	    warn_msg="WARNING: This process will erase all data in this machine, \
do you want to continue?"
	fi

	clear
	_yesno "\n$warn_msg\n"
	if [ "$?" != "0" ]; then
		_shutdown
	fi
}

function detect_root()
{
	inst_source_dev=$(awk "\$2 == \"$restore_media\" { print \$1 }" /proc/mounts | sed -e 's/[0-9]$//')
	inst_source_dev=${inst_source_dev#/dev/}
	devices=$(grep "^ .*[^0-9]$" < /proc/partitions | grep -v ${inst_source_dev} | awk '$3 > '$MIN_DISKSIZE' { print $4,$3 }')

	if [ -z "${devices}" ]; then
		exit 1
	fi

	devs_found=$(($(echo $devices | wc -w)/2))

	root_data=$(detect_win32 ${inst_source_dev})

	if [ -z "${root_data}" ]; then
		if [ "$devs_found" -gt "1" ]; then
 			if [ -n "${inst_source_dev}" ]; then
 				opcao=$(dialog --backtitle "$BACKTITLE" --title "$TITLE" --stdout --menu 'Choose one of the detected devices to restore to (check the blocks size column first):' 8 50 0 $devices )
 				if [ "$?" != "0" ]; then
 					_yesno "\nInterrupt installation?\n "
 					if [ "$?" = "0" ]; then
 						_shutdown
 					fi
 				else
 					root_data=${opcao}
 				fi 
 			fi
		else
		    root_data=$(echo ${devices} | cut -d ' ' -f 1)
		fi
	fi
	
	echo ${root_data}
}

function detect_win32()
{
	# from detect_root()
	skip_dev=${1}

	# win32 detection won't handle complex layouts
	if [ $(fdisk -l | grep "^/dev/" | grep -v ${skip_dev} | wc -l) -gt 1 ]; then
		exit
	fi

	# get the last created windows partition information
	set -f
	device=$(fdisk -l | grep "^/dev/" | grep -v ${skip_dev} | grep -e "FAT\|NTFS\|HPFS" | tail -1 | sed 's/ .*$//')
	set +f

	if [ -z "${device}" ]; then
		exit
	fi

	# it might be needed, for safety
	device_type=$(blkid -o value -s TYPE ${device})
	modprobe ${device_type}

	# df for that partition
	mount ${device} /mnt
	size=$(df ${device} | tail -1) 
	umount /mnt

	# its diskspace
	used=$(echo ${size} | awk '{ print $3 }')
	left=$(echo ${size} | awk '{ print $4 }')
	avail=$((${left}/2))

	if [ ! ${avail} -lt ${MIN_DISKSIZE} ]; then
		win32_part_dev=${device}
		win32_part_type=${device_type}
		# our install takes half of 'left'
		win32_part_new_size=$((${used}+${avail}))

		dev=${win32_part_dev#/dev/}
		disk=${dev%[0-9]}
		number=${dev#[a-w][a-w][a-w]}
		let number++
		echo ${disk}${number} ${win32_part_dev} ${win32_part_type} ${win32_part_new_size}
	fi
}

function resize_win32()
{
	device=${1}
	device_type=${2}
	new_win32_size=${3}

	dialog --backtitle "$BACKTITLE" --title "$TITLE" --infobox "\nResizing Windows partition...\n" 4 55

	dev=${device#/dev/}
	disk=${dev%[0-9]}
	win32_number=${dev#[a-w][a-w][a-w]}

	case ${device_type} in
		vfat) device_id=b  ;;
		ntfs) device_id=7  ;;
		hpfs) device_id=87 ;;
	esac

	# wrapper around libdrakx by blino
	diskdrake-resize ${device} ${device_type} $((${new_win32_size}*2)) &>/dev/null

	# we need some free sector here, rebuilding layout
	fdisk /dev/${disk} &>/dev/null <<EOF
d
n
p
${win32_number}

+${new_win32_size}K
t
${device_id}
a
${win32_number}
w
EOF
	# adds linux partition to the end of the working disk
	fdisk /dev/${disk} &>/dev/null <<EOF
n
p
$((${win32_number}+1))

+${MIN_DISKSIZE}K
t
$((${win32_number}+1))
83
w
EOF
}

function detect_device()
{
	dialog --backtitle "$BACKTITLE" --title "$TITLE" --infobox "\nTrying to detect your root partition and disk...\n" 4 55

	root_data=$(detect_root)
	if [ -z "${root_data}" ]; then
        	_msgbox "\nError writing image: disk device not detected.\n"
		# so that netbooks using USB sticks as disks can retry (like Gdium)
		welcome
		root_data=$(detect_root)
	fi
	set ${root_data}
	root=$1
	win32_part_dev=$2
	win32_part_type=$3
	win32_part_new_size=$4
}

function write_image()
{
	if [ -n "${win32_part_dev}" ]; then
		resize_win32 ${win32_part_dev} ${win32_part_type} ${win32_part_new_size}
	fi
	
	image=$(cat $images_dir/list | cut -d ',' -f 3)
	extension=${image/*./}
	imagesize=$(ls -l $images_dir/$image | awk '{ print $5 }')
	case $extension in
		gz)
			uncomp=zcat
			total=$(gzip -l $images_dir/$image | tail -n 1 | awk '{ print $2 }')
			;;
		bz2)
			uncomp=bzcat
			total=$((imagesize * 3))
			;;
		*)
			uncomp=cat
			total=$imagesize
			;;
	esac

	skipstart=/bin/true
	if [ -n "$win32_part_dev" ]; then
		skipstart='dd of=/dev/null bs=1 count=32256'
	fi

	# the actual dumping command, from image to disk
	${uncomp} ${images_dir}/${image} | (${skipstart} &>/dev/null; dd bs=4M of=/dev/${root} >/tmp/backup.out 2>&1>>/tmp/log) &

	sleep 3
	pid=$(ps ax | grep 'dd bs=4M of' | grep -v grep | awk '{ print $1 }')

	while [ true ]; do
		ps | grep -q $pid
		if [ $? -eq 0 ]; then
			/bin/kill -SIGUSR1 $pid
			complete=$(tail -n 1 /tmp/backup.out | awk '{ print $1 }')
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

	# Now re-read the partition table because 'dd' might have changed it
    	sfdisk -R /dev/${root}
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
	if [ -z "$win32_part_dev" ]; then
		if [ -n "$MAIN_PART_NUMBER" ]; then
			part_number=$MAIN_PART_NUMBER
		else
			part_number=1
		fi
		root=${root%[0-9]}$part_number
	fi
	filesystem_type=$(dumpe2fs -h /dev/${root} 2>/dev/null| grep "Filesystem OS type" | awk '{ print $4 }')
	if [ "${filesystem_type}" = "Linux" ]; then
                dialog --backtitle "$BACKTITLE" --title "$TITLE" --infobox "Finishing Install... Expanding ${root}" 3 40
		disk=/dev/${root%[0-9]}
		main_part=/dev/${root}

		# FIXME: absurdly dirty hack
		main_part_num=${root:3}
		swap_part_num=$((main_part_num+1))
		swap_part=${disk}${swap_part_num}

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
		    e2fsck -fy $main_part
		    fdisk $disk << EOF
d
$main_part_num
n
p
$main_part_num


a
$main_part_num
w
EOF
		    sfdisk -R $disk
		    e2fsck -fy $main_part
		    resize2fs $main_part
		fi
		mkdir -p $mnt_dir
		mount $main_part $mnt_dir
		grub_dir="$mnt_dir/boot/grub"
		if [ -d "$grub_dir" ]; then
		    echo "(hd0) $disk" > "$grub_dir/device.map"
		    if [ -n "$win32_part_dev" ]; then
   	                grub_setup ${root} ${grub_dir}
                    fi
		fi
		if [ -n "$MKINITRD" ]; then
		    mount -t sysfs none "$mnt_dir/sys"
		    mount -t proc none "$mnt_dir/proc"
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
detect_device
install_warning
write_image
expand_fs

# all done!
_msgbox "\nInstallation process finished.\nPress ENTER to shutdown.\n "

_shutdown

