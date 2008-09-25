#!/bin/bash
if [ -r ./restore-image-lib.sh ]; then
	. ./restore-image-lib.sh
elif [ -r /usr/lib/restore-image-lib.sh ]; then
	. /usr/lib/restore-image-lib.sh
fi

export PATH="/sbin:/bin:/usr/sbin:/usr/bin"

images_dir="/tmp/media/images"
images="$images_dir/list"
image=""

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
	        dev=$(sed '/\/tmp\/media/!d;s/[0-9] .*$//;s/^.*\///' /proc/mounts)
	        devices=$(grep "^ .*[^0-9]$" < /proc/partitions | grep -v ${dev} | awk '{ print $4,$3 }')

		if [ ! -z ${dev} ]; then
			opcao=$(dialog --backtitle "$BACKTITLE" --title "$TITLE" --stdout --menu 'Choose one of the detected devices to restore to (check the blocks size column first):' 8 50 0 $devices )
			if [ "$?" != "0" ]; then
				_yesno "\nInterrupt installation?\n "
				if [ "$?" = "0" ]; then
					_shutdown
				fi
			else
				root=$opcao
			fi

			echo "$root"
		else
	                _msgbox "\nError writing image: disk device not detected\n"
		fi
}

function write_image()
{
	root=$(detect_root)
	bzcat $images_dir/$image | dd of=/dev/$root bs=4096 > /tmp/backup.out 2>&1 &

	sleep 3
	pid=$(ps ax | grep 'dd of' | grep -v grep | awk '{ print $1 }')
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

# installation steps
welcome
install_warning
write_image

# all done!
_msgbox "\nInstallation process finished.\nPress ENTER to shutdown.\n "

_shutdown

