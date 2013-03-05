#!/bin/bash
#               OpenCenter(TM) is Copyright 2013 by Rackspace US, Inc.
##############################################################################
#
# OpenCenter is licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.  This
# version of OpenCenter includes Rackspace trademarks and logos, and in
# accordance with Section 6 of the License, the provision of commercial
# support services in conjunction with a version of OpenCenter which includes
# Rackspace trademarks and logos is prohibited.  OpenCenter source code and
# details are available at: # https://github.com/rcbops/opencenter or upon
# written request.
#
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this
# notice, is available in the LICENSE file accompanying this software.
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the # specific language governing permissions and limitations
# under the License.
#
##############################################################################
#
#
# set -x
set -e

ROLE="agent"
OPENCENTER_SERVER=${OPENCENTER_SERVER:-"0.0.0.0"}
SERVER_PORT="8080"
USAGE="Usage: ./install-server.sh [server | agent | dashboard] <Server-IP>"

if [ $# -ge 1 ]; then
    if [ $1 != "server" ] && [ $1 != "agent" ] && [ $1 != "dashboard" ]; then
        echo "Invalid Role specified - Defaulting to 'server' Role"
        echo $USAGE
    else
        ROLE=$1
    fi
    if [ $# -ge 2 ]; then
        if ( echo $2 | egrep -q "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" ); then
            if [ $ROLE != "server" ]; then
                OPENCENTER_SERVER=$2
            fi
        else
            echo "Invalid IP specified - Defaulting to 0.0.0.0"
            echo $USAGE
        fi
    fi
fi

VERSION="1.0.0"

echo "INSTALLING AS ${ROLE} against server IP of ${OPENCENTER_SERVER}"
export DEBIAN_FRONTEND=noninteractive

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

function verify_yum_package_exists() {
   # $1 - name of package to testing
   if [[ -z $VERBOSE ]]; then
     rpm -q $1 > /dev/null 2>&1
   else
     rpm -q $1
   fi

   if [ $? -ne 0 ];
   then
     return 1
   else
     return 0
   fi
}


function install_opencenter_yum_repo() {
  releasever="6"
  releasedir="Fedora"
  case $1 in
    "Fedora") releasever="17"; releasedir="Fedora" ;;
    "CentOS") releasever="6"; releasedir="RedHat" ;;
    "RedHat") releasever="6"; releasedir="RedHat" ;;
  esac
  echo "Adding OpenCenter yum repository $releasedir/$releasever"
  cat > /etc/yum.repos.d/rcb-utils.repo <<EOF
[rcb-utils]
name=RCB Utility packages for OpenCenter $1
baseurl=$uri/stable/rpm/$releasedir/$releasever/\$basearch/
enabled=1
gpgcheck=1
gpgkey=$uri/stable/rpm/RPM-GPG-RCB.key
EOF
  rpm --import $uri/stable/rpm/RPM-GPG-RCB.key &>/dev/null || :
  if [[ $1 = "Fedora" ]]; then
      yum_opencenter_pkgs="$yum_opencenter_pkgs python-sqlalchemy"
      echo "skipping epel installation for Fedora"
  else
      yum_opencenter_pkgs="$yum_opencenter_pkgs python-sqlalchemy0.7"
      if (! rpm -q epel-release 2>&1>/dev/null ); then
          rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
          if [[ $? -ne 0 ]]; then
            echo "Unable to add the EPEL repository."
            exit 1
          fi
      fi
  fi
}

function install_apt_repo() {
  local aptkey=$(which apt-key)
  local keyserver="keyserver.ubuntu.com"

  echo "Adding Opencenter apt repository"

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

function do_git_update() {
    # $1 = repo name
    repo=$1
    if [ -d ${repo} ]; then
        pushd ${repo}
        git checkout master
        git pull origin master
        popd
    else
        git clone git@github.com:rcbops/${repo}
    fi
}


function git_setup() {
  cat > /root/.ssh/config <<EOF
Host *github.com
    StrictHostKeyChecking no
EOF
  if [ "${ROLE}" != "dashboard" ]; then
      do_git_update opencenter
      do_git_update opencenter-agent
      do_git_update opencenter-client

      pushd opencenter-client
      python ./setup.py install
      popd

      if [ "${ROLE}" == "server" ]; then
          pushd opencenter
          cat > local.conf <<EOF
[main]
bind_address = 0.0.0.0
bind_port = 8080
database_uri = sqlite:///opencenter.db
[logging]
opencenter.webapp.ast=INFO
opencenter.webapp.db=INFO
opencenter.webapp.solver=DEBUG
EOF
          screen -S opencenter-server -d -m python ./opencenter.py  -v -c ./local.conf
          popd
      fi
      pushd opencenter-agent
      sed "s/127.0.0.1/${OPENCENTER_SERVER}/g" opencenter-agent.conf.sample > local.conf
      sed "s/NOTSET/DEBUG/g" log.cfg > local-log.cfg
      PYTHONPATH=../opencenter screen -S opencenter-agent -d -m python ./opencenter-agent.py -v -c ./local.conf
      popd
  fi

  if [ "${ROLE}" == "dashboard" ]; then
      nvmVersion=0.8.18
      rm -rf .nvm .bower .anvil* .npm
      curl https://raw.github.com/creationix/nvm/master/install.sh | sh
      . ~/.nvm/nvm.sh
      nvm install ${nvmVersion}
      nvm alias default ${nvmVersion}

      do_git_update opencenter-dashboard
      pushd opencenter-dashboard
      sed "s/127.0.0.1/${OPENCENTER_SERVER}/g" config.json.sample > config.json
      make
      bash dashboard
      popd
  fi
}


function install_ubuntu() {
  local aptget=$(which apt-get)

  # Install apt repo
  install_apt_repo

  if [ "${ROLE}" != "dashboard" ]; then
      ${aptget} update
      ${aptget} install -y python-software-properties
      add-apt-repository -y ppa:cassou/emacs
  fi
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

  if [ "${ROLE}" != "dashboard" ]; then
      echo "Installing Required Packages"
      if ! ( ${aptget} install -y -q ${apt_opencenter_pkgs} ); then
          echo "Failed to install opencenter-agent"
          exit 1
      fi
  fi

  if [ "${ROLE}" == "dashboard" ]; then
      if ! ( ${aptget} install -y -q ${apt_dashboard_pkgs} ); then
          echo "Failed to install Required Packages"
          exit 1
      fi
  fi

  echo ""
  echo "Verifying packages installed successfully"
  pkg_list=( ${apt_opencenter_pkgs} )
  if [ "${ROLE}" == "dashboard" ]; then
      pkg_list=( ${apt_dashboard_pkgs} )
  fi
  for x in ${pkg_list[@]}; do
    if ! verify_apt_package_exists ${x};
    then
      echo "Package ${x} was not installed successfully"
      echo ".. please run dpkg -i ${x} for more information"
      exit 1
    fi
  done
  git_setup
}


function install_rhel() {
  echo "Installing on RHEL/CentOS"
  local yum=$(which yum)

  if [ "${ROLE}" != "dashboard" ]; then
      echo "Installing Required Packages"
      if ! ( ${yum} install -y -q ${yum_opencenter_pkgs} ); then
          echo "Failed to install opencenter-agent"
          exit 1
      fi
  fi

  if [ "${ROLE}" == "dashboard" ]; then
      if ! ( ${yum} install -y -q ${yum_dashboard_pkgs} ); then
          echo "Failed to install Required Packages"
          exit 1
      fi
  fi

  echo ""
  echo "Verifying packages installed successfully"
  pkg_list=( ${yum_opencenter_pkgs} )
  if [ "${ROLE}" == "dashboard" ]; then
      pkg_list=( ${yum_dashboard_pkgs} )
  fi
  for x in ${pkg_list[@]}; do
    if ! verify_yum_package_exists ${x};
    then
      echo "Package ${x} was not installed successfully"
      echo ".. please run rpm -q ${x} for more information"
      exit 1
    fi
  done

  git_setup
  iptables -F
}

function usage() {
cat <<EOF
usage: $0 options

This script will install opencenter packages.

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
uri="http://packages.opencenter.rackspace.com"
pkg_path="/stable/deb/rcb-utils/"
apt_opencenter_pkgs="git-core python-setuptools python-cliapp gcc python-dev libevent-dev screen emacs24-nox python-all python-support python-requests python-flask python-sqlalchemy python-migrate python-daemon python-chef python-gevent python-mako python-virtualenv python-netifaces python-psutil"
apt_dashboard_pkgs="build-essential git"
yum_opencenter_pkgs="git openssl-devel python-setuptools python-cliapp gcc screen python-requests python-flask python-migrate python-daemon python-chef python-gevent python-mako python-virtualenv python-netifaces python-psutil"
yum_dashboard_pkgs="gcc gcc-c++ make kernel-devel git"
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
elif [ -f "/etc/system-release-cpe" ];
then
  platform=$(cat /etc/system-release-cpe | cut -d ":" -f 3)
  platform_version=$(cat /etc/system-release-cpe | cut -d ":" -f 5)
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
  "redhat") install_opencenter_yum_repo "RedHat"
                   install_rhel
                   ;;
  "centos") install_opencenter_yum_repo "CentOS" 
                   install_rhel
                   ;;
  "fedoraproject") install_opencenter_yum_repo "Fedora"
                   install_rhel
                   ;;
esac

echo ""
echo "
OpenCenter™ is Copyright 2013 by Rackspace US, Inc.
OpenCenter is licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.  This version of OpenCenter includes Rackspace trademarks and logos, and in accordance with Section 6 of the License, the provision of commercial support services in conjunction with a version of OpenCenter which includes Rackspace trademarks and logos is prohibited.  OpenCenter source code and details are available at:  <OpenCenter Source Repository> or upon written request.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this notice, is available in the LICENSE.TXT file accompanying this software.
Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
"
echo "You have installed Opencenter. WooHoo!!"
exit
