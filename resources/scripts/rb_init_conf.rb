#!/usr/bin/env ruby

# Run initial server configuration from /etc/redborder/rb_init_conf.yml
# 1. Set hostname + cdomain
# 2. Configure network (on-premise only)
# 3. Configure dns (on-premise only)
# 4. Create serf configuration files
#
# note: Don't calculate encrypt_key

require 'yaml'
require 'ipaddr'
require 'netaddr'
require 'system/getifaddrs'
require 'json'
require "getopt/std"
require File.join(ENV['RBLIB'].nil? ? '/usr/lib/redborder/lib' : ENV['RBLIB'],'rb_config_utils.rb')

RBETC = ENV['RBETC'].nil? ? '/etc/redborder' : ENV['RBETC']
INITCONF="#{RBETC}/rb_init_conf.yml"

def local_tty_warning_wizard
  puts "[!] Error: This device must be configured under local tty"
  exit 1
end

opt = Getopt::Std.getopts("hrf")
if opt["h"]
  printf "rb_init_conf [-r] \n"
  printf "    -r                -> register sensor with manager\n"
  printf "    -f                -> force configure in non local tty\n"
  exit 1
end

# Run the wizard only in local tty
local_tty_warning_wizard unless Config_utils.is_local_tty or opt["f"]

init_conf = YAML.load_file(INITCONF)

registration_mode = init_conf['registration_mode']

if registration_mode == "proxy"
  cloud_address = init_conf['cloud_address']
else
  webui_host = init_conf['webui_host']

  webui_user = init_conf['webui_user']

  webui_pass = init_conf['webui_pass']

  gateway_node_name = init_conf['gateway_node_name']
end
cdomain = init_conf['cdomain']

network = init_conf['network']

management_interface = init_conf['network']['management_interface'] if init_conf['network'] && init_conf['network']['management_interface']

# Create file with bash env variables
open("/etc/redborder/rb_init_conf.conf", "w") { |f|
  f.puts "#REBORDER ENV VARIABLES"
}

# Set cdomain file
File.open("/etc/redborder/cdomain", "w") { |f| f.puts "#{cdomain}" }

####################
# Set NETWORK      #
####################

unless network.nil? # network will not be defined in cloud deployments

  # Disable and stop NetworkManager
  system('systemctl disable NetworkManager &> /dev/null')
  system('systemctl stop NetworkManager &> /dev/null')

  # Enable network service
  system('systemctl enable network &> /dev/null')
  system('systemctl start network &> /dev/null')

  # Configure DNS
  unless network['dns'].nil?
    dns = network['dns']
    open("/etc/sysconfig/network", "w") { |f|
      dns.each_with_index do |dns_ip, i|
        if Config_utils.check_ipv4({:ip => dns_ip})
          f.puts "DNS#{i+1}=#{dns_ip}"
        else
          p err_msg = "Invalid DNS Address. Please review #{INITCONF} file"
          exit 1
        end
      end
      #f.puts "SEARCH=#{cdomain}" TODO: check if this is needed.
    }
  end

  # Delete old segmetns
  files_to_delete = []

  #
  # Construct files_to_delete array
  #
  list_net_conf = Dir.entries("/etc/sysconfig/network-scripts/").select {|f| !File.directory? f}
  list_net_conf.each do |netconf|
    next unless netconf.start_with?"ifcfg-b" # We only need the bridges
    bridge = netconf.gsub("ifcfg-","")
  end

  #
  # Remove bridges and delete related files
  #
  files_to_delete.each do |iface_path_file|
    # Get the interface name from the file path
    iface = iface_path_file.split("/").last.gsub("ifcfg-","")
    # Put the interface down
    puts "Stopping dev #{iface} .."
    system("ip link set dev #{iface} down")

    # If the interface is also a bridge we delete with ip link del
    # TODO: Check if with checking that start with b is enough to know if is a bridge
    if iface.start_with?"b"
      puts "Deleting dev bridge #{iface}"
      system("ip link del #{iface}")
    end

    # Remove the files from /etc/sysconfig/network-scripts directory
    File.delete(iface_path_file) if File.exist?(iface_path_file)
  end

  # Configure NETWORK
  network['interfaces'].each do |iface|
    dev = iface['device']
    iface_mode = iface['mode']

    open("/etc/sysconfig/network-scripts/ifcfg-#{dev}", 'w') { |f|
      # Commom configuration to all interfaces
      f.puts "BOOTPROTO=#{iface_mode}"
      f.puts "DEVICE=#{dev}"
      f.puts "ONBOOT=yes"
      dev_uuid = File.read("/proc/sys/kernel/random/uuid").chomp
      f.puts "UUID=#{dev_uuid}"

      if iface_mode != 'dhcp'
        # Specific handling for static and management interfaces
        if dev == management_interface || Config_utils.check_ipv4(ip: iface['ip'], netmask: iface['netmask'], gateway: iface['gateway'])
          f.puts "IPADDR=#{iface['ip']}" if iface['ip']
          f.puts "NETMASK=#{iface['netmask']}" if iface['netmask']
          f.puts "GATEWAY=#{iface['gateway']}" if iface['gateway']
          if dev == management_interface
            f.puts "DEFROUTE=yes"
          else
            f.puts "DEFROUTE=no"
          end
        else
          p err_msg = "Invalid network configuration for device #{dev}. Please review #{INITCONF} file"
          exit 1
        end
      else
        # Specific settings for DHCP
        f.puts "PEERDNS=no"
        f.puts "DEFROUTE=no" unless dev == management_interface
      end
    }
  end

  # Restart NetworkManager
  system('pkill dhclient &> /dev/null')
  puts "Restarting the network.."
  system('service network restart &> /dev/null')
  sleep 10
end

# TODO: check network connectivity. Try to resolve repo.redborder.com

unless Config_utils.has_internet?
  puts "[!] Error: Trying to resolv repo.redborder.com failed. Please check your network settings or contact your system administrator."
  exit 1
end

##############################
# Accept chef-client license #
##############################
system('chef-client --chef-license accept &>/dev/null')

####################
# Set UTC timezone #
####################

system("timedatectl set-timezone UTC")
# TODO
#system("ntpdate pool.ntp.org")

#Firewall rules
if !network.nil? #Firewall rules are not needed in cloud environments

  # Add rules here

  # Reload firewalld configuration
  #system("firewall-cmd --reload &>/dev/null")

end

# Upgrade system
system('yum install systemd -y')

#system('systemctl start chef-client &>/dev/null') unless opt["r"]
#TODO: check if needed: rm -f /boot/initrd*kdump.*
system('service kdump start')

###########################
# Configure cloud address #
###########################
if opt["r"]
  Config_utils.update_chef_roles registration_mode
  if registration_mode == "proxy"
    if Config_utils.check_cloud_address(cloud_address)
      GATEWAYOPTS="-t gateway -i -d -f"
      system("/usr/lib/redborder/bin/rb_register_url.sh -u #{cloud_address} -c #{cdomain} #{GATEWAYOPTS}")
    else
      p err_msg = "Invalid cloud address. Please review #{INITCONF} file"
      exit 1
    end
  else
    system("sudo hostnamectl set-hostname #{gateway_node_name}")
    Config_utils.ensure_log_file_exists
    system("echo 'Sensor #{gateway_node_name} association in progress...' > #{Config_utils.log_file}")
    system("/usr/lib/redborder/scripts/rb_associate_sensor.rb -u #{webui_user} -p #{webui_pass} -i #{Config_utils.get_ip_address} -m #{webui_host} >> #{Config_utils.log_file} 2>&1")
    if $?.exitstatus == 0
      Config_utils.hook_hosts(webui_host, cdomain)
      Config_utils.replace_chef_server_url(cdomain)
      
      system("sed -i '/webui_pass/d' #{INITCONF}")
      puts "Sensor registered to the manager, please wait..."
      puts "You can see logs in #{Config_utils.log_file}"
      system("/usr/lib/redborder/bin/rb_register_finish.sh >> #{Config_utils.log_file} 2>&1")
      puts "Registration and configuration finished!"
    else
      
      puts "Error: Sensor association failed with exit status #{$?.exitstatus}."
      puts "Please review #{INITCONF} file or network configuration..."
      puts "See \"#{Config_utils.log_file}\" for more details."
    end
  end
end
