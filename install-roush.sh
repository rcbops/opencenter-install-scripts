#!/bin/bash

function verify_apt_package_exists() {
  # $1 - name of package to test

  dpkg -s $1 >/dev/null 2>&1
  if [ $? -ne 0 ];
  then
    return 1
  else
    return 0
  fi
}


function install_roush_apt_repo() {
  local aptkey=$(which apt-key)
  local keyserver="keyserver.ubuntu.com"

  echo "Adding Roush apt repository"

  if [ -e ${apt_file_path} ];
  then
    # TODO(shep): Need to do some sort of checking here
    /bin/true
  else
    echo "deb ${uri}/${pkg_path} ${platform_name} ${repo_name}" > $apt_file_path
  fi

  if ! ( ${aptkey} adv --keyserver ${keyserver} --recv-keys ${apt_key} >/dev/null 2>&1 ); then
    echo "Unable to add apt-key."
    exit 1
  fi
}


function install_ubuntu() {
  local aptget=$(which apt-get)

  # Install apt repo 
  install_roush_apt_repo
  
  # Run an apt-get update to make sure sources are up to date
  if ! ( ${aptget} -q update >/dev/null ); then
    echo "apt-get update failed to execute successfully."
    exit 1
  fi

  echo "Installing Roush-Server"
  if ! ( ${aptget} install -y -q ${roush_pkgs} ); then
    echo "Failed to install roush"
    exit 1
  fi

  echo ""
  echo "Verifying packages installed successfully"
  pkg_list=( ${roush_pkgs} )
  for x in ${pkg_list[@]}; do
    if ! verify_apt_package_exists ${x};
    then
      echo "Package ${x} was not installed successfully"
      echo ".. please run dpkg -i ${x} for more information"
      exit 1
    fi
  done
}


function install_rhel() {
  echo "Installing on RHEL"
}

#####################

arch=$(uname -m)
if [ -f "/etc/lsb-release" ];
then
  platform=$(grep "DISTRIB_ID" /etc/lsb-release | cut -d"=" -f2 | tr "[:upper:]" "[:lower:]")
  platform_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d"=" -f2)
elif [ -f "/etc/system-release" ];
then
  platform="rhel"
  platform_version=$(cat /etc/redhat-release | awk '{print $3}')
fi

case $platform_version in
  "12.04") platform_name="precise" ;;
esac

uri="http://build.monkeypuppetlabs.com"
pkg_path="/proposed-packages"
repo_name="rcb-utils"
roush_pkgs="roush-simple roush"

# APT Specific variables
apt_key="765C5E49F87CBDE0"
apt_file_name="${repo_name}.list"
apt_file_path="/etc/apt/sources.list.d/${apt_file_name}"

# echo "Arch: ${arch}"
# echo "Platform: ${platform}"
# echo "Version: ${platform_version}"

case $platform in
  "ubuntu") install_ubuntu ;;
  "rhel") install_rhel ;;
esac

echo ""
echo "You have installed Roush. WooHoo!!"
