#!/bin/bash

# this script setups the network on the cloned system
# puts a correct hostname
# changes the IP if static -- for only ONE device (dunno what will happen with multiple NICs)
# needs the file /ka/hostnames


curdir=`pwd`


# current hostname has been set up in rc.sysinit
ip=`hostname | tr _ .`

echo My IP is $ip
cd /ka

# the sed command will remove unwanted spaces
if test -f hostnames ; then
	myname=`cat hostnames | sed -e 's/  / /g' -e 's/ *$//' | grep " $ip\$" | cut -d ' ' -f 1`
	nbfound=`echo "$myname" | wc -l`
fi

if [ $nbfound -ne 1 ] || [ -z "$myname" ]; then
	# try DNS
	echo IP not found in /ka/hostnames, Trying DNS
	myname=`host $ip | grep "domain name"  | cut -d " " -f 5`
#	myname=`nslookup $ip | grep ^Name: | tail -n +2 | head -n 1 | sed 's/Name: *//'`
fi

if [ -z "$myname" ]; then
	myname=`hostname`
	echo WARNING:HOSTNAME NOT FOUND
fi

echo My hostname is $myname

# change hostname in the network file
old=/disk/etc/sysconfig/network.beforeka
new=/disk/etc/sysconfig/network

rm -f "$old"
mv "$new" "$old"
cat "$old" | grep -v ^HOSTNAME= > "$new"
echo "HOSTNAME=$myname" >> "$new"

# assume first NIC is the gatewaydev (right ? wrong ?)
firstnic=`grep ^GATEWAYDEV "$new" | cut -d = -f 2 | tr -d \"`
echo GATEWAYDEV=$firstnic

# see if IP has to be written
proto=`grep ^BOOTPROTO /disk/etc/sysconfig/network-scripts/ifcfg-$firstnic | cut -d = -f 2 | tr -d \"`
echo PROTO=$proto
if [ $proto != dhcp ]; then
	# proto is static, write the new IP in the config file
	old=/disk/etc/sysconfig/network-scripts/ifcfg-$firstnic.beforeka
	new=/disk/etc/sysconfig/network-scripts/ifcfg-$firstnic

	rm -f "$old"
	mv "$new" "$old"
	cat "$old" | grep -v ^IPADDR= > "$new"
	echo IPADDR=$ip >> "$new"
fi

cd $curdir
