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
set -e

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
  # $1 yum distro (Fedora/CentOS/RedHat)
  releasever="6"
  releasedir="Fedora"
  case $1 in
    "Fedora") releasever="17"; releasedir="Fedora" ;;
    "CentOS") releasever="6"; releasedir="RedHat" ;;
    "RedHat") releasever="6"; releasedir="RedHat" ;;
  esac
  echo "Adding OpenCenter yum repository $releasedir/$releasever"
  if ![ -e ${yum_file_path} ] || !( grep -q "baseurl=$uri/$yum_pkg_path/$releasedir/$releasever/\$basearch/" $yum_file_path > /dev/null 2>&1 ); then
  cat > $yum_file_path <<EOF
[$yum_repo]
name=RCB Utility packages for OpenCenter $1
baseurl=$uri/$yum_pkg_path/$releasedir/$releasever/\$basearch/
enabled=1
gpgcheck=1
gpgkey=$uri/$yum_pkg_path/$yum_key
EOF
  fi
  rpm --import $uri/$yum_pkg_path/$yum_key &>/dev/null || :
  if [[ $1 = "Fedora" ]]; then
      yum_opencenter_pkgs="$yum_opencenter_pkgs python-sqlalchemy"
      echo "skipping epel installation for Fedora"
  else
      yum_opencenter_pkgs="$yum_opencenter_pkgs python-sqlalchemy0.7"
      if (! rpm -q epel-release 2>&1>/dev/null ); then
          rpm -Uvh $epel_release
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
    if ! ( grep "deb ${uri}/${apt_pkg_path} ${platform_name} ${apt_repo}" $apt_file_path ); then
        echo "deb ${uri}/${apt_pkg_path} ${platform_name} ${apt_repo}" > $apt_file_path
    fi
  else
    echo "deb ${uri}/${apt_pkg_path} ${platform_name} ${apt_repo}" > $apt_file_path
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

function adjust_iptables() {
    if [ "${ROLE}" == "server" ]; then
        iptables -I INPUT 1 -p tcp --dport 8080 -j ACCEPT
        iptables-save > /etc/sysconfig/iptables
    elif [ "${ROLE}" == "dashboard" ]; then
        iptables -I INPUT 1 -p tcp --dport 3000 -j ACCEPT
        iptables-save > /etc/sysconfig/iptables
    fi
}

function setup_aliases() {
    # server and dashboard roles presumably aren't running chef-client, so
    # should be safe to make local modification here
    if [ "${ROLE}" != "agent" ]; then
        echo -e "\nalias occ='opencentercli'" >> /root/.bashrc
    fi
}

function do_git_update() {
    # $1 = repo name
    repo=$1
    if [ -d ${repo} ]; then
        pushd ${repo}
        git checkout ${git_branch}
        git pull origin ${git_branch}
        popd
    else
        git clone https://github.com/${git_user}/${repo} -b ${git_branch}
    fi

    # Apply patch if one was specified - useful for testing a pull request
    pushd $repo
    if [ ! -z ${PATCH_URLS[$repo]} ]; then
        echo "Applying the following patch to $repo"
        curl -s -n -L ${PATCH_URLS[$repo]}
        if ! ( curl -s -n -L ${PATCH_URLS[$repo]} | git apply ); then
            echo "Unable to apply patch ${PATCH_URLS[$repo]} to $repo."
            exit 1
        fi
    fi
    popd
}

function do_git_remove() {
    # $1 = repo name
    repo=$1
    if [ -d ${repo} ]; then
        pushd ${repo}
        git reset --hard origin/sprint
        popd
    fi
}


function git_setup() {
  if [ "${ROLE}" != "dashboard" ]; then
      if ( $RERUN ); then
         do_git_remove opencenter
         do_git_remove opencenter-agent
         do_git_remove opencenter-client
      fi
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
      if [ "${ROLE}" == "agent" ]; then
          pushd opencenteragent/plugins/output
          if [ -f "plugin_adventurator.py" ]; then
              rm plugin_adventurator.py
          fi
          popd
      fi
      PYTHONPATH=../opencenter screen -S opencenter-agent -d -m python ./opencenter-agent.py -v -c ./local.conf
      popd
  fi

  if [ "${ROLE}" == "dashboard" ]; then
      if ( $RERUN ); then
          do_git_remove opencenter-dashboard
      fi
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
  for pkg in ${pkg_list[@]}; do
    if ! verify_apt_package_exists ${pkg};
    then
      echo "Package ${pkg} was not installed successfully"
      echo ".. please run dpkg -i ${pkg} for more information"
      exit 1
    fi
  done

  git_setup
  setup_aliases
}


function install_rhel() {
  # $1 - Distro Fedora/RedHat/CentOS

  distro=$1
  # Redhat repo's aren't added quickly enough - adding a sleep
  if [ "$distro" == "RedHat" ]; then
      sleep 10
  fi

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
  for pkg in ${pkg_list[@]}; do
    if ! verify_yum_package_exists ${pkg};
    then
      echo "Package ${pkg} was not installed successfully"
      echo ".. please run a manual yum install ${pkg} for more information"
      exit 1
    fi
  done

  git_setup
  adjust_iptables
  setup_aliases
}

function usage() {
cat <<EOF
usage: $0 options

This script will install opencenter packages.

OPTIONS:
  -h --help  Show this message
  -v --verbose  Verbose output
  -V --version  Display script version

ARGUMENTS:
  -r= --role=[server | agent | dashboard]
         Specify the role of the node - defaults to "agent"
  -i= --ip=<Opencenter Server IP>
         Specify the Opencenter Server IP - defaults to "0.0.0.0"
  -rr --rerun
         Rerun the script without having to create a new server
         Can be used to adjust IP information
  -gb= --git-branch=<Git Branch>
         Specify the git branch to use, defaults to "sprint"
  -gu= --git-user=<Git User>
         Specify the git user to use, defaults to "rcbops"
  --server-patch-url=<URL>
  --agent-patch-url=<URL>
  --client-patch-url=<URL>
         Retrieve and apply a patch to the project specified after cloning.
         This can be useful for testing a proposed change.
EOF
}


function display_version() {
cat <<EOF
$0 (version: $VERSION)
EOF
}

function get_platform() {
    arch=$(uname -m)
    if [ -f "/etc/system-release-cpe" ];
    then
        platform=$(cat /etc/system-release-cpe | cut -d ":" -f 3)
        platform_version=$(cat /etc/system-release-cpe | cut -d ":" -f 5)
    elif [ -f "/etc/lsb-release" ];
    then
        platform=$(grep "DISTRIB_ID" /etc/lsb-release | cut -d"=" -f2 | tr "[:upper:]" "[:lower:]")
        platform_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d"=" -f2)    
    else
        echo "Your platform is not supported.  Please email RPCFeedback@rackspace.com and let us know."
        exit 1
    fi

    # On ubuntu the version number needs to be mapped to a name
    case $platform_version in
        "12.04") platform_name="precise" ;;
        *) echo "Unsupported/unknown version $platform_version" 
           exit 1
           ;;
    esac
}

function licensing() {
    echo ""
    echo "
OpenCenter™ is Copyright 2013 by Rackspace US, Inc.
OpenCenter is licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.  This version of OpenCenter includes Rackspace trademarks and logos, and in accordance with Section 6 of the License, the provision of commercial support services in conjunction with a version of OpenCenter which includes Rackspace trademarks and logos is prohibited.  OpenCenter source code and details are available at:  <OpenCenter Source Repository> or upon written request.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this notice, is available in the LICENSE.TXT file accompanying this software.
Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
"
}


function display_info() {
    echo "You have installed Opencenter. WooHoo!!"
    if [[ "${ROLE}" = "dashboard" ]]; then
        my_ip=$(ip a show dev `ip route | grep default | awk '{print $5}'` | grep "inet " | awk '{print $2}' | cut -d "/" -f 1)
        cat <<EOF

Your OpenCenter dashboard is available at http://${my_ip}

EOF
    fi
}

################################################
# -*-*-*-*-*-*-*-*-*- MAIN -*-*-*-*-*-*-*-*-*- #
################################################
####################
# Global Variables #
ROLE="agent"
OPENCENTER_SERVER=${OPENCENTER_SERVER:-"0.0.0.0"}
SERVER_PORT="8080"
VERSION=1.0.0
VERBOSE=
git_branch=sprint
git_user=rcbops
####################

####################
# Package Variables
uri="http://build.monkeypuppetlabs.com"
repo_path="repo-testing"
apt_opencenter_pkgs="git-core python-setuptools python-cliapp gcc python-dev libevent-dev screen emacs24-nox python-all python-support python-requests python-flask python-sqlalchemy python-migrate python-daemon python-chef python-gevent python-mako python-virtualenv python-netifaces python-psutil"
apt_dashboard_pkgs="build-essential git"
yum_opencenter_pkgs="git openssl-devel python-setuptools python-cliapp gcc screen python-requests python-flask python-migrate python-daemon python-chef python-gevent python-mako python-virtualenv python-netifaces python-psutil"
yum_dashboard_pkgs="gcc gcc-c++ make kernel-devel git"
####################

####################
# APT Specific Variables #
apt_pkg_path="proposed-packages/"
apt_repo="rcb-utils"
apt_key="765C5E49F87CBDE0"
apt_file_name="${apt_repo}.list"
apt_file_path="/etc/apt/sources.list.d/${apt_file_name}"
####################

####################
# YUM Specific Variables #
yum_repo="rcb-utils"
yum_pkg_path="repo-testing"
yum_key="RPM-GPG-RCB.key"
yum_file_name="${yum_repo}.repo"
yum_file_path="/etc/yum.repos.d/${yum_file_name}"
epel_release="http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm"
####################

#URLs for patches that should be applied after each repo is cloned.
declare -A PATCH_URLS

for arg in $@; do
    flag=$(echo $arg | cut -d "=" -f1)
    value=$(echo $arg | cut -d "=" -f2)
    case $flag in
        "--role" | "-r")
            if [ $value != "server" ] && [ $value != "agent" ] && [ $value != "dashboard" ]; then
                echo "Invalid Role specified - defaulting to agent"
                usage
            else
                ROLE=$value
            fi
            ;;
        "--ip" | "-i")
            if ( echo $value | egrep -q "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" ); then
                OPENCENTER_SERVER=$value
            else
                echo "Invalid IP specified - exiting"
                usage
                exit 1
            fi
            ;;
        "--rerun" | "-rr")
            RERUN=true
            ;;
        "--git-branch" | "-gb")
            if [ "$value" != "--git-branch" ] && [ "$value" != "-gb" ]; then
                git_branch=$value
            fi
            ;;
        "--git-user" | "-gu")
            if [ "$value" != "--git-user" ] && [ "$value" != "-gu" ]; then
                git_user=$value
            fi
            ;;
        "--help" | "-h")
            usage
            exit 0
            ;;
        "--verbose" | "-v")
            VERBOSE=1
            set -x
            ;;
        "--version" | "-V")
            display_version
            exit 0
            ;;
        "--server-patch-url") PATCH_URLS['opencenter']="$value" ;;
        "--agent-patch-url") PATCH_URLS['opencenter-agent']="$value" ;;
        "--client-patch-url") PATCH_URLS['opencenter-client']="$value" ;;
        *)
            echo "Invalid Option $flag"
            usage
            exit 1
            ;;
    esac
done

export DEBIAN_FRONTEND=noninteractive

get_platform


# echo "Arch: ${arch}"
# echo "Platform: ${platform}"
# echo "Version: ${platform_version}"

# Run os dependent install functions
case $platform in
  "ubuntu") install_ubuntu ;;
  "redhat") install_opencenter_yum_repo "RedHat"
                   install_rhel "RedHat"
                   ;;
  "centos") install_opencenter_yum_repo "CentOS" 
                   install_rhel "CentOS"
                   ;;
  "fedoraproject") install_opencenter_yum_repo "Fedora"
                   install_rhel "Fedora"
                   ;;
esac

licensing
display_info

exit
