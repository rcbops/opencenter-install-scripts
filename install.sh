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
SERVER_PORT="8443"
USAGE="Usage: ./install-server.sh [server | agent | dashboard] <Server-IP> [password]"

if [ $# -ge 1 ]; then
    if [ $1 != "server" ] && [ $1 != "agent" ] && [ $1 != "dashboard" ]; then
        echo "Invalid Role specified - Defaulting to 'server' Role"
        echo $USAGE
    else
        ROLE=$1
    fi
    if [ $# -ge 2 ]; then
        if ( echo $2 | egrep -q "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" ); then
            OPENCENTER_SERVER=$2
        else
            echo "Invalid IP specified - Defaulting to 0.0.0.0"
            echo $USAGE
        fi
        if [[ $3 ]]; then
            PASSWORD=$3
        fi
    fi
fi

VERSION="1.0.0"
PASSWORD=${PASSWORD:-password}

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
      echo "skipping epel installation for Fedora"
  else
      if (! rpm -q epel-release 2>&1>/dev/null ); then
          rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-8.noarch.rpm
          if [[ $? -ne 0 ]]; then
            echo "Unable to add the EPEL repository."
            exit 1
          fi
      fi
  fi
 }

function install_opencenter_apt_repo() {
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


function install_ubuntu() {
  local aptget=$(which apt-get)

  # Install apt repo
  install_opencenter_apt_repo

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

  if [ "${ROLE}" == "server" ]; then
      echo "Installing Opencenter-Server"
      cat <<EOF | debconf-set-selections
opencenter-agent opencenter/server string ${OPENCENTER_SERVER}
opencenter-agent opencenter/port string ${SERVER_PORT}
EOF
      if [[ ${PASSWORD} ]]; then
          cat <<EOF | debconf-set-selections
opencenter opencenter/password string ${PASSWORD}
EOF
      fi
      if ! ( ${aptget} install -y -q ${server_pkgs} ); then
          echo "Failed to install opencenter"
          exit 1
      fi
  fi

  if [ "${ROLE}" != "dashboard" ]; then
      echo "Installing Opencenter-Agent"
      cat <<EOF | debconf-set-selections
opencenter-agent opencenter/server string ${OPENCENTER_SERVER}
opencenter-agent opencenter/port string ${SERVER_PORT}
EOF
      if [[ ${PASSWORD} ]]; then
          cat <<EOF | debconf-set-selections
opencenter-agent opencenter/password string ${PASSWORD}
EOF
      fi
      if ! ( ${aptget} install -y -q ${agent_pkgs} ); then
          echo "Failed to install opencenter-agent"
          exit 1
      fi

      echo ""
      echo "Installing Agent Plugins"
      if ! ( ${aptget} install -y -q ${agent_plugins} ); then
          echo "Failed to install opencenter-agent"
          exit 1
      fi
      /etc/init.d/opencenter-agent restart
  fi

  if [ "${ROLE}" == "dashboard" ]; then
      ${aptget} install -y -q debconf-utils
      echo "Installing Opencenter Dashboard"
      cat << EOF | debconf-set-selections
opencenter-dashboard    opencenter/server_port  string ${SERVER_PORT}
opencenter-dashboard    opencenter/server_ip    string ${OPENCENTER_SERVER}
EOF
      if ! ( ${aptget} install -y -q ${dashboard_pkgs} ); then
          echo "Failed to install Opencentre Dashboard"
          exit 1
      fi
  fi

  echo ""
  echo "Verifying packages installed successfully"
  pkg_list=( ${agent_pkgs} ${agent_plugins} )
  if [ "${ROLE}" == "server" ]; then
      pkg_list=( ${server_pkgs} ${agent_pkgs} ${agent_plugins} )
  fi
  if [ "${ROLE}" == "dashboard" ]; then
      pkg_list=( ${dashboard_pkgs} )
  fi
  for x in ${pkg_list[@]}; do
    if ! verify_apt_package_exists ${x};
    then
      echo "Package ${x} was not installed successfully"
      echo ".. please run dpkg -i ${x} for more information"
      exit 1
    fi
  done
}


function install_rpm() {

  if [ "${ROLE}" == "server" ]; then
      echo "Installing Opencenter-Server"
      if ! ( yum install -y -q ${server_pkgs} ); then
          echo "Failed to install opencenter"
          exit 1
      fi
      stop opencenter || :
      start opencenter
  fi

  if [ "${ROLE}" != "dashboard" ]; then
      echo "Installing Opencenter-Agent"
      if ! ( yum install -y -q ${agent_pkgs} ); then
          echo "Failed to install opencenter-agent"
          exit 1
      fi

      echo ""
      echo "Installing Agent Plugins"
      if ! ( yum install -y -q ${agent_plugins} ); then
          echo "Failed to install opencenter-agent"
          exit 1
      fi
      sed -i "s/admin:password/admin:${PASSWORD}/g" /etc/opencenter/agent.conf.d/opencenter-agent-endpoints.conf
      stop opencenter-agent || :
      start opencenter-agent
  fi

  if [ "${ROLE}" == "dashboard" ]; then
      echo "Installing Opencenter Dashboard"
      if ! ( yum install -y -q ${dashboard_pkgs} ); then
          echo "Failed to install Opencentre Dashboard"
          exit 1
      fi
      # the opencenter-dashboard package restarts httpd, so this is
      # here for safety
      sleep 15s
      chkconfig httpd on
      current_IP=$( cat /etc/httpd/conf.d/opencenter-dashboard.conf | egrep -o -m 1 "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" )
      sed -i "s/${current_IP}/${OPENCENTER_SERVER}/" /etc/httpd/conf.d/opencenter-dashboard.conf
      service httpd restart
  fi

  if [ "${ROLE}" == "agent" ]; then
      current_IP=$( cat /etc/opencenter/agent.conf.d/opencenter-agent-endpoints.conf | egrep -o -m 1 "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" )
      sed -i "s/${current_IP}/${OPENCENTER_SERVER}/" /etc/opencenter/agent.conf.d/opencenter-agent-endpoints.conf
      stop opencenter-agent || :
      start opencenter-agent
  elif [ "${ROLE}" == "server" ]; then
      current_IP=$( cat /etc/opencenter/agent.conf.d/opencenter-agent-endpoints.conf | egrep -o -m 1 "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" )
      sed -i "s/${current_IP}/0.0.0.0/" /etc/opencenter/agent.conf.d/opencenter-agent-endpoints.conf
      sed -i "s/^admin_pass = password/admin_pass = ${PASSWORD}/g" /etc/opencenter/opencenter.conf
      stop opencenter-agent || :
      start opencenter-agent
      stop opencenter
      start opencenter
  fi
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
server_pkgs="opencenter-server python-opencenter opencenter-client opencenter-agent-output-adventurator"
agent_pkgs="opencenter-agent"
agent_plugins="opencenter-agent-input-task opencenter-agent-output-chef opencenter-agent-output-service opencenter-agent-output-packages opencenter-agent-output-openstack opencenter-agent-output-update-actions"
dashboard_pkgs="opencenter-dashboard"
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
else
  echo "Your platform is not supported.  Please email RPCFeedback@rackspace.com and let us know."
  exit 1
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
                   install_rpm
                   ;;
  "centos") install_opencenter_yum_repo "CentOS"
                   install_rpm
                   ;;
  "fedoraproject") install_opencenter_yum_repo "Fedora"
                   install_rpm
                   ;;
esac

echo ""
echo "
OpenCenter(TM) is Copyright 2013 by Rackspace US, Inc.
OpenCenter is licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.  This version of OpenCenter includes Rackspace trademarks and logos, and in accordance with Section 6 of the License, the provision of commercial support services in conjunction with a version of OpenCenter which includes Rackspace trademarks and logos is prohibited.  OpenCenter source code and details are available at: https://github.com/rcbops/opencenter/ or upon written request.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 and a copy, including this notice, is available in the LICENSE.TXT file accompanying this software.
Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
"
echo "You have installed Opencenter. WooHoo!!"

if [[ "${ROLE}" = "dashboard" ]]; then
      my_ip=$(ip a show dev `ip route | grep default | awk '{print $5}'` | grep "inet " | awk '{print $2}' | cut -d "/" -f 1)
      cat <<EOF

Your OpenCenter dashboard is available at https://${my_ip}

EOF
fi

if [[ "${ROLE}" = "agent" ]]; then
    echo ""
    echo "Agent username and password configurations are stored in"
    echo "/etc/opencenter/agent.conf.d/opencenter-agent-endpoints.conf"
    echo "  root = https://<username>:<password>@<opencenter-server-ip>:8443"
    echo "  admin = https://<username>:<password>@<opencenter-server-ip>:8443/admin"
    echo ""
    echo "If you change this you must also update the agent endpoint"
    echo "configurations."
    echo ""
fi
if [[ "${ROLE}" = "server" ]]; then
    echo ""
    echo "Server username and password configurations are stored in"
    echo "/etc/opencenter/opencenter.conf"
    echo "  admin_user = <admin username>"
    echo "  admin_pass = <admin password>"
    echo ""
    echo "If you change this you must also update the agent endpoint"
    echo "configurations."
    echo ""
fi

exit
