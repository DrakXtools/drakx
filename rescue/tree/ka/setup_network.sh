#!/bin/bash

# this script setups the network on the cloned system
# puts a correct hostname
# changes the IP if static -- for only ONE device (dunno what will happen with multiple NICs)
# needs the file /ka/hostnames


curdir=`pwd`


ip=`/sbin/ifconfig | /bin/grep -v 127.0.0.1 | /bin/grep "inet addr" | /bin/sed 's/^.*inet addr:\([^ ]*\) .*$/\1/g'`
oldip=$ip
ip=`echo $ip | sed -e 's/\./_/g'`
echo -n "Setting hostname: "
/bin/hostname $ip


# current hostname has been set up in rc.sysinit
ip=$oldip
echo My IP is $ip
cd /ka

# the sed command will remove unwanted spaces
##########################
# HOSTNMAE already set on NODE
############################
#if test -f hostnames ; then
#	myname=`/bin/cat hostnames | /bin/sed -e 's/  / /g' -e 's/ *$//' | /bin/grep " $ip\$" | /bin/cut -d ' ' -f 1`
#	nbfound=`echo "$myname" |/usr/bin/wc -l`
#fi##
#
#if [ $nbfound -ne 1 ] || [ -z "$myname" ]; then
#	# try DNS
#	echo IP not found in /ka/hostnames, Trying DNS
#	myname=`/usr/bin/host $ip | /bin/grep "domain name"  | /bin/cut -d " " -f 5 | /bin/sed 's/\.$//g' `
#	myname=`nslookup $ip | grep ^Name: | tail -n +2 | head -n 1 | sed 's/Name: *//'`
#fi
#
#if [ -z "$myname" ]; then
#	myname=`/bin/hostname`
#	echo WARNING:HOSTNAME NOT FOUND
#fi
#
#echo My hostname is $myname

# change hostname in the network file
#old=/mnt/disk/etc/sysconfig/network.beforeka
#new=/mnt/disk/etc/sysconfig/network

#rm -f "$old"
#mv "$new" "$old"
#/bin/cat "$old" | /bin/grep -v ^HOSTNAME= > "$new"
#echo "HOSTNAME=$myname" >> "$new"
######################
##
######################




# assume first NIC is the gatewaydev (right ? wrong ?)
#firstnic=`grep ^GATEWAYDEV "$new" | cut -d = -f 2 | tr -d \"`
#echo GATEWAYDEV=$firstnic

# see if IP has to be written
#proto=`grep ^BOOTPROTO /mnt/disk/etc/sysconfig/network-scripts/ifcfg-$firstnic | cut -d = -f 2 | tr -d \"`
#echo PROTO=$proto
#if [ "$proto" != "dhcp" ]; then
#	# proto is static, write the new IP in the config file
#	old=/mnt/disk/etc/sysconfig/network-scripts/ifcfg-$firstnic.beforeka
#	new=/mnt/disk/etc/sysconfig/network-scripts/ifcfg-$firstnic
#
#	rm -f "$old"
#	mv "$new" "$old"
#	cat "$old" | grep -v ^IPADDR= > "$new"
#	echo IPADDR=$ip >> "$new"
#fi

cd $curdir
