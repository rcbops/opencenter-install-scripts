#!/bin/bash
# set -x
set -e

VERSION="1.0.0"

function verify_apt_package_exists() {
  # $1 - name of package to test
  if [[ -z $VERBOSE ]]; then
    dpkg -s $1 >/dev/null 2>&1
  else
    dpkg -s $1
  fi

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
    echo "deb ${uri}/${pkg_path} ${platform_name} ${apt_repo}" > $apt_file_path
  fi

  if [[ -z $VERBOSE ]]; then
    ${aptkey} adv --keyserver ${keyserver} --recv-keys ${apt_key} >/dev/null 2>&1
  else
    ${aptkey} adv --keyserver ${keyserver} --recv-keys ${apt_key}
  fi

  if [[ $? -ne 0 ]]; then
    echo "Unable to add apt-key."
    exit 1
  fi
}


function install_ubuntu() {
  local aptget=$(which apt-get)

  # Install apt repo
  install_roush_apt_repo

  # Run an apt-get update to make sure sources are up to date
  echo "Refreshing package list"
  if [[ -z $VERBOSE ]]; then
    ${aptget} -q update >/dev/null
  else
    ${aptget} update
  fi

  if [[ $? -ne 0 ]];
  then
    echo "apt-get update failed to execute successfully."
    exit 1
  fi

  echo "Installing Roush-Server"
  if ! ( ${aptget} install -y -q ${server_pkgs} ); then
    echo "Failed to install roush"
    exit 1
  fi

  echo "Installing Roush-Agent"
  if ! ( ${aptget} install -y -q ${agent_pkgs} ); then
    echo "Failed to install roush-agent"
    exit 1
  fi

  echo ""
  echo "Installing Agent Plugins"
  if ! ( ${aptget} install -y -q ${agent_plugins} ); then
    echo "Failed to install roush-agent"
    exit 1
  fi

  echo ""
  echo "Verifying packages installed successfully"
  pkg_list=( ${server_pkgs} ${agent_pkgs} ${agent_plugins} )
  for x in ${pkg_list[@]}; do
    if ! verify_apt_package_exists ${x};
    then
      echo "Package ${x} was not installed successfully"
      echo ".. please run dpkg -i ${x} for more information"
      exit 1
    fi
  done

  ROUSH_SERVER=${ROUSH_SERVER:-0.0.0.0}
  if ! [[ -z $ROUSH_SERVER ]];then
    # FIXME(shep): This should really be debconf hackery instead
    sed -i "s/127.0.0.1/0.0.0.0/" /etc/roush/agent.conf.d/roush-agent-task.conf
    sed -i "s/127.0.0.1/0.0.0.0/" /etc/roush/agent.conf.d/roush-agent-adventurator.conf
    /etc/init.d/roush-agent restart
  fi
}


function install_rhel() {
  echo "Installing on RHEL"
}

function usage() {
cat <<EOF
usage: $0 options

This script will install roush packages.

OPTIONS:
  -h  Show this message
  -v  Verbose output
EOF
}


function display_version() {
cat <<EOF
$0 (version: $VERSION)
EOF
}


################################################
# -*-*-*-*-*-*-*-*-*- MAIN -*-*-*-*-*-*-*-*-*- #
################################################

####################
# Global Variables
VERBOSE=
####################

####################
# Package Variables
uri="http://build.monkeypuppetlabs.com"
pkg_path="/proposed-packages"
server_pkgs="roush-simple python-roush roush-client"
agent_pkgs="roush-agent"
agent_plugins="roush-agent-input-task roush-agent-output-chef roush-agent-output-service roush-agent-output-adventurator roush-agent-output-packages"
####################

####################
# APT Specific variables
apt_repo="rcb-utils"
apt_key="765C5E49F87CBDE0"
apt_file_name="${apt_repo}.list"
apt_file_path="/etc/apt/sources.list.d/${apt_file_name}"
####################

# Parse options
while getopts "hvV" option
do
  case $option in
    h)
      usage
      exit 1
      ;;
    v) VERBOSE=1 ;;
    V)
      display_version
      exit 1
      ;;
    ?)
      usage
      exit 1
      ;;
  esac
done

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

# On ubuntu the version number needs to be mapped to a name
case $platform_version in
  "12.04") platform_name="precise" ;;
esac

# echo "Arch: ${arch}"
# echo "Platform: ${platform}"
# echo "Version: ${platform_version}"

# Run os dependent install functions
case $platform in
  "ubuntu") install_ubuntu ;;
  "rhel") install_rhel ;;
esac

echo ""
echo "You have installed Roush. WooHoo!!"
