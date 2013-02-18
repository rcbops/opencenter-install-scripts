Dev Roush - Roush Cluster Setup
-----------------------

This will setup a cluster containing a Roush Server, 2 Roush Clients and a nTrapy server.

Installing Roush Cluster
-----------------------

    ./roush-dev.sh <Cluster-Name>

If you are using Roush-client locally you can set your endpoint:
export ROUSH_ENDPOINT=http://<ip of server>:8080

Prerequisities
-----------------------

* Nova client installed and working with cloud, specifically returning network information, for Rackspace cloud see:
    http://www.rackspace.com/knowledge_center/article/installing-python-novaclient-on-linux-and-mac-os
  * NB: You may need an updated version of nova-client, to ensure network information is appropriately returned.
* Either of these:
  * supernova configured and an environment variable exported NOVA="supernova your-env"
  * nova env variables set in ~/csrc.
* Up to date versions of bash & sed - this may require updating on OSX
* ~/.ssh/authorized_keys file exists, containing your key.
* ~/.ssh/id_github file exists, containing your github key:
    https://help.github.com/articles/generating-ssh-keys

Wiping the Cluster
-----------------------

    ./wipe.sh <Cluster-Name>

This will remove all cloud servers in the cluster and delete the specific logs in /tmp

Pushing updates to the Cluster
-----------------------

From within "roush", "roush-agent", "roush-client", "ntrapy" directories on your local laptop/desktop
you can push updates and have the services restart automaticallyL

    ./push.sh <Cluster-Name> <repo>
    <repo> defaults to "roush-all" which will include roush/roush-agent/roush-client
    <repo> possible options: {roush-all | roush | roush-client | roush-agent | ntrapy}

Tailing Task Logs on Roush servers:
-----------------------

This should show the last 1K of the task logs, updating every 10 seconds.
    ./logtail.py <task_id>

Rerunning Setup Script on the 4 nodes.
-----------------------

If something failed during the setup of the node and you want to re-run the setup
script without waiting for new instances to spin up, then set RERUN=true before running
roush-dev.sh with the same prefix as used initially.

    export RERUN=true
    ./roush-dev.sh <Cluster-Name>

