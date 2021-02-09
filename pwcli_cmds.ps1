#
# Prerequisites
# -------------
#
### 1. Download the PowerCLI Module from VMWare Website
### 2. Download the Community Module for extending Datastores
#
# git clone https://github.com/lucdekens/VMFSIncrease
#
### -->  Creates directory "VMFSIncrease"
###  [root@lxwhtkvm10 workdir]# ls -lR VMFSIncrease/
###  VMFSIncrease/:
###  total 24
###  drwxr-xr-x. 2 root root   75 Sep  8 09:26 en-US
###  -rw-r--r--. 1 root root  245 Sep  8 09:26 LICENSE.txt.URL
###  -rw-r--r--. 1 root root  122 Sep  8 09:26 README.md
###  -rw-r--r--. 1 root root  630 Sep  8 09:26 VMFSIncrease.psd1
###  -rw-r--r--. 1 root root 9100 Sep  8 09:26 VMFSIncrease.psm1
###  
###  VMFSIncrease/en-US:
###  total 28
###  -rw-r--r--. 1 root root   414 Sep  8 09:26 about_VMFSIncrease.help.txt
###  -rw-r--r--. 1 root root 20547 Sep  8 09:26 VMFSIncrease.psm1-Help.xml
###  
###
#
# pwsh
# ps> import-module VMWare.PowerCLI
# ps> $env:PSModuePath -split ":"
# ps> cd <one of the module paths, i.e. /opt/....>
# ps> import-module ~/VMFSIncrease/*psd1
# ps> import-module ~/VMFSIncrease/*psm1
# ps> get-help New-VMFSDatastoreIncrease
#

#############################################
#
# Validate argument list
#
#############################################
write-host "** VALIDATING ARGUMENT LIST"

if ( $args.count -ne 5 ) 
  {
    write-host "Error - Usage: configure_import_esxi <server_IP_address> <username> <password> <prefix> <no_of_perimeters>"
    exit 9
  }

#############################################
#
# Display connection details
#
#############################################
$ESXiHost = $args[0]
$UserName = $args[1]
$Password = $args[2]
$VMPrefix = $args[3]
$NoofPers = $args[4]
Write-Host "Target ESXi Host = $ESXiHost"
Write-Host "  Connecting with username = $UserName"
Write-Host "  Connecting with password = $Password"
Write-Host "  VM Name prefix           = $VMPrefix"
Write-Host "  No.of Perimeter VMs      = $NoofPers"

#############################################
#
# Global Variables
#
#############################################
$VMhdd  = 30
$VMmem  = 2
$VMcpus = 1

#############################################
#
# Connect to the ESXi host
#
#############################################
write-host "** CONNECTING TO ESXi HOST"

$RES = Connect-VIServer -Server $ESXiHost -User $UserName -Password $Password
Write-Host $RES

#############################################
#
# Install ESXi License Key
#
# Unable to use PowerCLI to install License Key - Only available via a vCenter server (?!)
#
#############################################

#############################################
#
# Creating the datastore
#
# NOTE: Creating the Datastore is done in two parts. Its is created with the first available LUN, 
#       and then extended to its full size using all remaining LUNs
#
#############################################
write-host "** CREATING THE DATASTORE - Part 1 of 2"

$HBA = Get-vmhosthba | grep Block | grep -v USB | awk '{ print $1 }'
$LUNs = Get-scsilun -hba $HBA -luntype disk
New-Datastore -Name "MyDatastore" -VMFS -Path $LUNs[0]

write-host "** CREATING THE DATASTORE - Part 2 of 2"

foreach ( $DISK in $LUNs[1..50] ) {
  New-VMFSDataStoreIncrease -Datastore MyDatastore -CanonicalName $DISK -Extend
}
Get-datastore

#############################################
#
# Creating the vSwitchs
#
# 1. Without an uplink
#  New-VirtualSwitch -Name "vswitch9"   -mtu 1500  -Confirm:$false
# 2. With an uplink (if external connectivity required)
#  New-VirtualSwitch -Name "vswitch9"  -Nic <PhysicalNic[]> -mtu 1500  -Confirm:$false
#
#############################################
write-host "** CREATING THE vSWITCHES"

New-VirtualSwitch -Name "vswitch1"   -mtu 1500  -Confirm:$false
New-VirtualSwitch -Name "vswitch2"   -mtu 1500  -Confirm:$false
New-VirtualSwitch -Name "vswitch3"   -mtu 1500  -Confirm:$false

#############################################
#
# Create Port Groups
#
# 1. Create Port Group/Associate with vswitch
# New-VirtualPortGroup -Name "VM-to-VM" -VirtualSwitch vswitch9 -Confirm:$false
#
#############################################
write-host "** CREATING THE PORTGROUPS"

New-VirtualPortGroup -Name "Ext - Per"  -VirtualSwitch vswitch1 -Confirm:$false
New-VirtualPortGroup -Name "Per - TX"   -VirtualSwitch vswitch2 -Confirm:$false
New-VirtualPortGroup -Name "TX - RX"    -VirtualSwitch vswitch3 -Confirm:$false
New-VirtualPortGroup -Name "VM Network" -VirtualSwitch vswitch0 -Confirm:$false

#############################################
#
# Creating VMs
#
# new-vm -Datastore MyDatastore -DiskGB 30  -MemoryGB 2 -Name "MyFifthVM"  -networkname "VM-to-VM","VM-to-VM 2","VM-to-VM 3" -numcpu 1  -vmhost $ESXiHost -CD -guestid "centos64Guest"
# get-vm MyFifthVM | get-networkadapter | set-networkadapter -Type e1000 
# new-vm -Datastore MyDatastore -DiskGB 30  -MemoryGB 2 -Name "MyFifthVM"   -numcpu 1  -vmhost $ESXiHost -CD -guestid "centos64Guest"
# get-vm MyFifthVM | get-networkadapter | remove-networkadapter
# new-networkadapter -VM MyFifthVM -Networkname "VM-to-VM 3" -Type e1000 -startconnected
# new-networkadapter -VM MysixthVM -Networkname "VM-to-VM" -Type e1000 -startconnected
#
#############################################

#############################################
#
# Creating the Perimeter VM(s)
#
#############################################
foreach ( $VMSuffix in 1..$NoofPers ) {
  write-host "** CREATING PERIMETER VM $VMSuffix"

  $VMName = "${VMPrefix}impper0${VMSuffix}"
  new-vm -Datastore MyDatastore -DiskGB $VMhdd -MemoryGB $VMmem -Name $VMName -numcpu $VMcpus -vmhost $ESXiHost  -CD -guestid "centos64Guest"
  get-vm $VMName | get-networkadapter
  get-vm $VMName | get-networkadapter  | remove-networkadapter -confirm:$false
  new-networkadapter -VM $VMName -Networkname "Ext - Per" -Type e1000 -startconnected
  new-networkadapter -VM $VMName -Networkname "Per - TX" -Type e1000 -startconnected
  new-networkadapter -VM $VMName -Networkname "VM Network" -Type e1000 -startconnected
  get-vm $VMName | get-networkadapter
}

#############################################
#
# Creating the TX VM
#
#############################################
write-host "** CREATING THE TX DIODE VM"

$VMName = "${VMPrefix}imptx01"
new-vm -Datastore MyDatastore -DiskGB $VMhdd -MemoryGB $VMmem -Name $VMName -numcpu $VMcpus -vmhost $ESXiHost -CD -guestid "centos64Guest"
get-vm $VMName | get-networkadapter
get-vm $VMName | get-networkadapter  | remove-networkadapter -confirm:$false
new-networkadapter -VM $VMName -Networkname "Per - TX" -Type e1000 -startconnected
new-networkadapter -VM $VMName -Networkname "TX - RX" -Type e1000 -startconnected
get-vm $VMName | get-networkadapter

#############################################
#
# Disconnect fromESXi host
#
#############################################
write-host "** DISCONNECTING FROM THE ESXi HOST"

Disconnect-VIServer -Server $ESXiHost -Force -confirm:$false
