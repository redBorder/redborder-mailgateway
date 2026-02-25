#!/bin/bash

FORCE=0
RET=0
DELETE="/etc/chef/validation.pem /etc/chef/client.pem /etc/chef/client.rb /etc/motd /etc/sudoers.d/redBorder /etc/sysconfig/iptables /etc/chef/role.json /etc/chef/role-once.json /etc/chef/rb-register.db /var/log/rb-register/finish.log /share/bulkstats.tar.gz"

source /usr/lib/redborder/lib/rb_functions.sh

function usage(){
	echo "ERROR: $0 [-f] [-h] "
  	echo "    -f -> force delete (not ask)"
  	echo "    -h -> print this help"
	exit 2
}

logger -t "rb_disassociate_sensor" "Deleting mailgateway"

while getopts "fh" opt; do
  case $opt in
    f) FORCE=1;;
    h) usage;;
  esac
done

VAR="y"

if [ $FORCE -eq 0 ]; then
  echo -n "Are you sure you want to disassociate this mailgateway from the manager? (y/N) "
  read VAR
fi

if [ "x$VAR" == "xy" -o "x$VAR" == "xY" ]; then
  e_title "Stopping services"
  ds_services_stop="chef-client redborder-monitor rb-register" #rb-register should be restarted on rb_setup_wizard
  systemctl stop $ds_services_stop

  e_title "Deleting files"
  for n in $DELETE; do
    echo "Deleting $n"
    rm -rf $n
  done
  touch /etc/sysconfig/iptables

  e_title "Generating new uuid"
  sqlite3 /etc/rb-register.db "DELETE FROM Devices;"
  cat /proc/sys/kernel/random/uuid > /etc/rb-uuid


  e_title "Starting registration daemons"
  rm /etc/sysconfig/rb-register
  cp /etc/sysconfig/rb-register.default /etc/sysconfig/rb-register

  e_title "Pushing hash from rb-uuid to rb-register"
  echo HASH=\"$(cat /etc/rb-uuid)\" >> /etc/sysconfig/rb-register 

  #In order to enable the asossiation of the mailgateway again
  e_title "Restarting Network configuration"
  > "/etc/sysconfig/network"  #empty file

  e_title "Disassociate finished. Please use rb_setup_wizard to register this machine again"
fi

exit $RET