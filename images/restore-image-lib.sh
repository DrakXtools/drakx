#!/bin/sh

TITLE="Moondrake Installer"
BACKTITLE="Moondrake"
MIN_DISKSIZE=5000000

debug="/dev/null"

function _msgbox()
{
	dialog --timeout 60 --backtitle "$BACKTITLE" --title "$TITLE" --msgbox \
		"$1" 0 0

	return $?
}

function _infobox()
{
	dialog --backtitle "$BACKTITLE" --title "$TITLE" --sleep 2 \
		--infobox "$1" 0 0

	return $?
}

function _yesno()
{
	dialog --backtitle "$BACKTITLE" --title "$TITLE" \
		--yes-label "Yes" --no-label "No" --yesno "$1" 0 0

	return $?
}

function _mount()
{
	mount $1 $2 > $debug 2>&1

	return $?
}

function _umount()
{
	umount $1 > $debug 2>&1

	return $?
}

function _bind()
{
	mount --bind $1 $2 > $debug 2>&1

	return $?
}

function _eject()
{
	eject $1 > $debug 2>&1

	return $?
}

function _shutdown()
{
	[ -e /tmp/no-shutdown ] && exit
	clear
	sync
	echo s > /proc/sysrq-trigger
	echo o > /proc/sysrq-trigger
	exit
}

function _reboot()
{
	[ -e /tmp/no-shutdown ] && exit
	clear
	sync
	echo s > /proc/sysrq-trigger
	echo b > /proc/sysrq-trigger
	exit
}

