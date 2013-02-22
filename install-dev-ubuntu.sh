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
# Riding the trunk
# Only tested on a 12.04 cloud server.
# Only "tested" by wilk.
# Use at your own risk
# Requires interaction
# Patches happily accepted.

apt-get install -y git python-setuptools python-cliapp gcc python-dev libevent-dev screen

# or use the ssh links if you have your keys on said box
git clone https://github.com/rcbops/opencenter.git
git clone https://github.com/rcbops/opencenter-agent.git
git clone https://github.com/rcbops/opencenter-client.git

# setup opencenter
cd opencenter
./run_tests.sh -V # say yes to the venv
mkdir -p /etc/opencenter
cp opencenter.conf /etc/opencenter/opencenter.conf
echo 'database_uri = sqlite:////etc/opencenter/opencenter.db' >>/etc/opencenter/opencenter.conf
screen -d -m tools/with_venv.sh python opencenter.py  -v -c /etc/opencenter/opencenter.conf
cd ..

# setup opencenter-agent
cd opencenter-agent
cp opencenter-agent.conf.sample opencenter-agent.conf
./run_tests.sh # say yes
source .venv/bin/activate
cd ../opencenter-client
python setup.py install
cd ../opencenter
python setup.py install
cd ../opencenter-agent
# Get python-apt into venv for the 'packages' plugin
cp -a /usr/share/pyshared/python_apt-0.8.3ubuntu7.egg-info /usr/share/pyshared/apt* .venv/lib/python2.7/site-packages/
cp /usr/lib/pyshared/python2.7/apt_pkg.so ~/opencenter-agent/.venv/lib/python2.7/
python opencenter-agent.py -c opencenter-agent.conf -v
