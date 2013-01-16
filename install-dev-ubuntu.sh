#!/bin/bash
# Riding the trunk
# Only tested on a 12.04 cloud server.
# Only "tested" by wilk.
# Use at your own risk
# Requires interaction
# Patches happily accepted.

apt-get install -y git python-setuptools python-cliapp gcc python-dev libevent-dev screen emacs23-nox

# or use the ssh links if you have your keys on said box
git clone https://github.com/rcbops/roush.git
git clone https://github.com/rcbops/roush-agent.git
git clone https://github.com/rcbops/roush-client.git

# setup roush
cd roush
./run_tests.sh  # say yes to the venv
mkdir -p /etc/roush
cp roush.conf /etc/roush/roush.conf
echo 'database_uri = sqlite:////etc/roush/roush.db' >>/etc/roush/roush.conf
tools/with_venv.sh python manage.py -c /etc/roush/roush.conf version_control
tools/with_venv.sh python manage.py -c /etc/roush/roush.conf upgrade
screen -d -m tools/with_venv.sh python roush.py  -c /etc/roush/roush.conf
cd ..

# setup roush-agent
cd roush-agent
cp roush-agent.conf.sample roush-agent.conf
./run_tests.sh # say yes
source .venv/bin/activate
cd ../roush-client
python setup.py install
cd ../roush
python setup.py install
cd ../roush-agent
# Get python-apt into venv for the 'packages' plugin
cp -a /usr/share/pyshared/python_apt-0.8.3ubuntu7.egg-info /usr/share/pyshared/apt* .venv/lib/python2.7/site-packages/
cp /usr/lib/pyshared/python2.7/apt_pkg.so ~/roush-agent/.venv/lib/python2.7/
python roush-agent.py -c roush-agent.conf -v
