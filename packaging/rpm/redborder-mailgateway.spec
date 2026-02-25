%undefine __brp_mangle_shebangs

Name: redborder-mailgateway
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Main package for redborder mailgateway

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-mailgateway
Source0: %{name}-%{version}.tar.gz

Requires: bash dialog dmidecode rsync nc telnet redborder-common redborder-chef-client redborder-rubyrvm redborder-cli rb-register dhclient
Requires: alternatives java-1.8.0-openjdk java-1.8.0-openjdk-devel
Requires: network-scripts network-scripts-teamd
Requires: chef-workstation
Requires: redborder-cgroups
Requires: ipmitool

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/etc/redborder
mkdir -p %{buildroot}/usr/lib/redborder/bin
mkdir -p %{buildroot}/usr/lib/redborder/scripts
mkdir -p %{buildroot}/usr/lib/redborder/lib
mkdir -p %{buildroot}/etc/profile.d
mkdir -p %{buildroot}/var/chef/cookbooks
mkdir -p %{buildroot}/etc/chef/
install -D -m 0644 resources/redborder-mailgateway.sh %{buildroot}/etc/profile.d
install -D -m 0644 resources/dialogrc %{buildroot}/etc/redborder
cp resources/bin/* %{buildroot}/usr/lib/redborder/bin
cp resources/scripts/* %{buildroot}/usr/lib/redborder/scripts
cp -r resources/etc/chef %{buildroot}/etc/
chmod 0755 %{buildroot}/usr/lib/redborder/bin/*
chmod 0755 %{buildroot}/usr/lib/redborder/scripts/*
install -D -m 0644 resources/lib/rb_wiz_lib.rb %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/lib/rb_config_utils.rb %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/lib/rb_functions.sh %{buildroot}/usr/lib/redborder/lib
install -D -m 0644 resources/systemd/rb-init-conf.service %{buildroot}/usr/lib/systemd/system/rb-init-conf.service
install -D -m 0755 resources/lib/dhclient-enter-hooks %{buildroot}/usr/lib/redborder/lib/dhclient-enter-hooks

%pre

%post
if ls /opt/chef-workstation/embedded/lib/ruby/gems/3.1.0/specifications/default/openssl-3.0.1.* 1> /dev/null 2>&1; then
  rm -f /opt/chef-workstation/embedded/lib/ruby/gems/3.1.0/specifications/default/openssl-3.0.1.*
fi
MARKER_FILE="/var/lib/redborder/upgrade_etc_hosts_patch_done"
case "$1" in
  1)
    # This is an initial install.
    :
  ;;
  2)
    # This is an upgrade.
    if [ -f "$MARKER_FILE" ]; then
      echo "Post-install patch already applied, skipping."
      exit 0
    fi

    CDOMAIN_FILE="/etc/redborder/cdomain"
    if [ -f "$CDOMAIN_FILE" ]; then
      SUFFIX=$(cat "$CDOMAIN_FILE")
    else
      SUFFIX="redborder.cluster"
    fi

    NEW_DOMAIN_ERCHEF="erchef.service.${SUFFIX}"
    NEW_DOMAIN_WEBUI="webui.${SUFFIX}"
    NEW_DOMAIN_S3="s3.service.${SUFFIX}"

    grep -qE '\berchef\.service[[:space:]]' /etc/hosts && \
    sed -i -E "s/\berchef\.service\b/${NEW_DOMAIN_ERCHEF}/" /etc/hosts

    grep -qE '\bs3\.service[[:space:]]' /etc/hosts && \
    sed -i -E "s/\bs3\.service\b/${NEW_DOMAIN_S3}/" /etc/hosts

    grep -qE '\bwebui\.service[[:space:]]' /etc/hosts && \
    sed -i -E "s/\bwebui\.service\b/${NEW_DOMAIN_WEBUI}/" /etc/hosts

    CHEF_FILES=(
      "/etc/chef/client.rb.default"
      "/etc/chef/client.rb"
      "/etc/chef/knife.rb.default"
      "/etc/chef/knife.rb"
      "/root/.chef/knife.rb"
    )

    for f in "${CHEF_FILES[@]}"; do
      if [ -f "$f" ]; then
        if grep -q 'https://erchef\.service/' "$f"; then
          sed -i "s|https://erchef\.service/|https://${NEW_DOMAIN_ERCHEF}/|" "$f"
          echo "Updated: $f"
        fi
      fi
    done

    mkdir -p "/var/lib/redborder"
    touch "$MARKER_FILE"
  ;;
esac

/usr/lib/redborder/bin/rb_rubywrapper.sh -c
# adjust kernel printk settings for the console
echo "kernel.printk = 1 4 1 7" > /usr/lib/sysctl.d/99-redborder-printk.conf
/sbin/sysctl --system > /dev/null 2>&1

%posttrans
update-alternatives --set java $(find /usr/lib/jvm/*java-1.8.0-openjdk* -name "java"|head -n 1)

%files
%defattr(0755,root,root)
/usr/lib/redborder/bin
/usr/lib/redborder/scripts
%defattr(0755,root,root)
/etc/profile.d/redborder-mailgateway.sh
/usr/lib/redborder/lib/dhclient-enter-hooks
%defattr(0644,root,root)
/etc/chef
/etc/redborder
/usr/lib/redborder/lib/rb_wiz_lib.rb
/usr/lib/redborder/lib/rb_config_utils.rb
/usr/lib/redborder/lib/rb_functions.sh
/usr/lib/systemd/system/rb-init-conf.service
%doc

%changelog
* Mon Feb 23 2026 Vicente Mesa <vimesa@redborder.com>
- first spec version
