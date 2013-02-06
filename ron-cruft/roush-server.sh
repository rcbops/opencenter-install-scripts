#!/bin/bash

set -e
set -x

echo INSTALLING AS ${1} against server IP of ${2}

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y python-software-properties

add-apt-repository ppa:cassou/emacs

cat > /etc/apt/sources.list.d/rcb-utils.list <<EOF
deb http://build.monkeypuppetlabs.com/proposed-packages precise rcb-utils
EOF

apt-key adv --keyserver=pgp.mit.edu --recv-keys 765C5E49F87CBDE0

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

function do_git_update {
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
cat > local.conf <<EOF
[main]
plugin_dir = %(base_dir)s/roushagent/plugins
input_handlers = %(plugin_dir)s/input/task_input.py
output_handlers = %(plugin_dir)s/output

log_config = local-log.cfg
trans_log_dir = trans_logs
bash_path = roushagent/plugins/lib/bash

[taskerator]
endpoint = http://${2}:8080/admin

[chef]
script_path = roushagent/plugins/lib/chef

[adventurator]
endpoint = http://${2}:8080/admin

EOF

cat > local-log.cfg <<EOF
[loggers]
keys=root

[handlers]
keys=stderr

[formatters]
keys=default

[logger_root]
level=DEBUG
handlers=stderr

[handler_stderr]
class=StreamHandler
level=DEBUG
#formatter=default
args=(sys.stderr,)

[handler_syslog]
class=logging.handlers.SysLogHandler
level=NOTSET
#formatter=default
args=("/dev/log",)

[handler_file]
class=FileHandler
level=NOTSET
#formatter=default
args=('roush-agent.log')

[formatter_default]
format=%(asctime)s - %(name)s - %(levelname)s - %(message)s
class=logging.Formatter
datefmt=%Y-%m-%d %H:%M:%S

EOF
PYTHONPATH=../roush screen -S roush-agent -d -m python ./roush-agent.py -v -c ./local.conf
popd

exit
