#!/bin/bash
#
# Copyright 2012, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
set -e
set -x

echo INSTALLING AS ${1} against server IP of ${2}

export DEBIAN_FRONTEND=noninteractive

echo "Getting key"
until apt-key adv --keyserver=keyserver.ubuntu.com --recv-keys 765C5E49F87CBDE0
do
    sleep 3
    echo -n .
done

apt-get update
apt-get install -y python-software-properties

add-apt-repository -y ppa:cassou/emacs

cat > /etc/apt/sources.list.d/rcb-utils.list <<EOF
deb http://build.monkeypuppetlabs.com/proposed-packages precise rcb-utils
EOF

apt-get update
apt-get -y upgrade

apt-get install -y git-core python-setuptools python-cliapp gcc python-dev libevent-dev screen emacs24-nox
apt-get install -y python-all python-support python-requests python-flask python-sqlalchemy python-migrate
apt-get install -y python-daemon python-chef python-gevent python-mako python-virtualenv python-netifaces

cat > /root/.screenrc <<EOF
hardstatus on
hardstatus alwayslastline
hardstatus string "%{.bW}%-w%{.rW}%n %t%{-}%+w %=%{..G} %H %{..Y} %d/%m %C%a"

# fix up 256color
attrcolor b ".I"
termcapinfo xterm-256color 'Co#256:AB=\E[48;5;%dm:AF=\E[38;5;%dm'

escape '\`q'

defscrollback 1024

vbell off
startup_message off
EOF

cat > /root/.ssh/config <<EOF
Host *github.com
    StrictHostKeyChecking no
EOF

function do_git_update() {
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

do_git_update roush
do_git_update roush-agent
do_git_update roush-client

pushd roush-client
sudo python ./setup.py install
popd

if [ "$1" == "server" ]; then
    pushd roush
    cat > local.conf <<EOF
[main]
bind_address = 0.0.0.0
bind_port = 8080
database_uri = sqlite:///roush.db
[logging]
roush.webapp.ast=INFO
roush.webapp.db=INFO
roush.webapp.solver=DEBUG
EOF
    screen -S roush-server -d -m python ./roush.py  -v -c ./local.conf
    popd
fi

pushd roush-agent
sed "s/127.0.0.1/${2}/g" roush-agent.conf.sample > local.conf
sed "s/NOTSET/DEBUG/g" log.cfg > local-log.cfg
PYTHONPATH=../roush screen -S roush-agent -d -m python ./roush-agent.py -v -c ./local.conf
popd

exit
