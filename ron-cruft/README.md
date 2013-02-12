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

    * Nova client installed and working with cloud, for Rackspace cloud see:
    http://www.rackspace.com/knowledge_center/article/installing-python-novaclient-on-linux-and-mac-os
    * Either supernova configured and an environment variable exported NOVA="supernova your-env" or nova env variables set in ~/csrc. 
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

    From within "roush", "roush-agent", "roush-client" directories on your local laptop/desktop
    you can push updates and have the services restart automaticallyL

    ./push.sh <Cluster-Name>

Tailing Task Logs on Roush servers:
-----------------------

    This should show the last 1K of the task logs, updating every 10 seconds.
    ./logtail.py <task_id>

TODO/Issues:
-----------------------

    nTrapy installs, but doesn't start - so you may need to manually log onto the nTrapy server and start it.
    push.sh doesn't currently work with nTrapy
