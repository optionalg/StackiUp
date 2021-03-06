#!/bin/bash

# check if args were passed

usage="Usage: $0 <number of virtual machines to create>"

if [ -z "$1" ]; then
	echo $usage
	exit 1
elif [[ "$1" == "-h" ]]; then
	echo $usage
	exit 1
elif [[ ! $1 =~ ^[0-9]+ ]]; then
	echo $usage
	exit 1
elif [[ $1 -lt 1 ]]; then
	echo $usage
	exit 1
fi

count=$1

make_vm() {
	vm_number=$1
	NAME=backend-$vm_number
	MEMSIZE=3072

	VBoxManage createvm --name $NAME --register
	if [ $? -ne 0 ]; then
		echo "Unable to create virtual machine"
		return 1
	fi

	# configure the 'hardware'
	VBoxManage modifyvm $NAME --memory $MEMSIZE
	VBoxManage modifyvm $NAME --ostype RedHat_64
	VBoxManage modifyvm $NAME --boot1 net
	VBoxManage modifyvm $NAME --boot2 disk
	VBoxManage modifyvm $NAME --boot3 none
	VBoxManage modifyvm $NAME --ioapic on
	VBoxManage modifyvm $NAME --rtcuseutc on
	VBoxManage modifyvm $NAME --nic1 hostonly
	VBoxManage modifyvm $NAME --nictype1 82540EM
	VBoxManage modifyvm $NAME --hostonlyadapter1 $VAGRANT_BACKEND_NETWORK

	# vbox outputs mac addresses without colons, but stacki wants the colons
	# heinous sed thing to put the colons back in
	macaddress=`VBoxManage showvminfo $NAME --machinereadable | grep macaddress1`
	macaddress=`echo $macaddress | sed -n -E "s/macaddress1=\"(.*)\"/\1/p" | sed -e 's/\([0-9A-Fa-f]\{2\}\)/\1:/g' -e 's/\(.*\):$/\1/'`

	# make a reasonable guess about the IP address
	ip_address=${VAGRANT_BACKEND_NETWORK_IP}.$((vm_number+100))

	# add the line to the hostfile
	echo ${NAME},backend,0,${i},${ip_address},${macaddress},eth0,private,True >> hostfile.csv

	# storage settings
	VBoxManage storagectl $NAME --name SATA --add sata --controller IntelAhci \
		--portcount 1 --bootable on

	# we want to put the disk in the same directory as the machine config file
	vbox_cfg_file=`VBoxManage showvminfo $NAME --machinereadable | sed -n -E "s/CfgFile=\"(.*)\"/\1/p"`
	vm_dirname=`dirname "${vbox_cfg_file}"`
	VBoxManage createhd --filename "${vm_dirname}"/$NAME.vdi \
		--size 100000

	VBoxManage storageattach $NAME --storagectl SATA \
		--port 0 \
		--device 0 \
		--type hdd \
		--medium "${vm_dirname}"/$NAME.vdi
}

if [[ ! -f ./.vagrant/machines/default/virtualbox/id ]]; then
	echo "Please run vagrant up before creating backend nodes"
	exit 1
fi

VAGRANT_VM_UUID=`cat ./.vagrant/machines/default/virtualbox/id`
VAGRANT_BACKEND_NETWORK=`VBoxManage showvminfo ${VAGRANT_VM_UUID} --machinereadable | sed -n -E "s/hostonlyadapter.*=\"(.*)\"/\1/p" `

# TODO only applies if /24...
VAGRANT_BACKEND_NETWORK_IP=`VBoxManage list --long hostonlyifs | tr -d ' ' | grep -A4 "Name:${VAGRANT_BACKEND_NETWORK}" | grep IPAddress: | cut -d":" -f2 | cut -d"." -f1-3`


rm -f hostfile.csv
echo Name,Appliance,Rack,Rank,IP,MAC,Interface,Network,Default >> hostfile.csv

for i in `seq 0 $((count-1))`; do
	make_vm $i
done

echo
echo "Virtual machines created and information stored in hostfile.csv"
