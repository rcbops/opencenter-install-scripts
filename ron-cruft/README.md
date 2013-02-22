Opencenter Cluster Install
-----------------------

This will setup a cluster containing an Opencenter Server, 2 Opencenter Clients and a nTrapy server.

Installing Opencenter Cluster
-----------------------

    ./opencenter-cluster.sh <Cluster-Name> <Number of Clients> {--packages}

* Number of Clients defaults to 2 if left unspecified
* If you are using opencenter-client locally you can set your endpoint:
export OPENCENTER_ENDPOINT=http://<ip of server>:8080
* --packages will install from packages instead of github repos, not for Dev work.

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

From within "opencenter", "opencenter-agent", "opencenter-client", "ntrapy" directories on your local laptop/desktop
you can push updates and have the services restart automaticallyL

    ./push.sh <Cluster-Name> <repo> <repo path>
    <repo> defaults to "opencenter-all" which will include opencenter/opencenter-agent/opencenter-client
    <repo> possible options: {opencenter-all | opencenter | opencenter-client | opencenter-agent | ntrapy}
    <repo path> can be left blank if you are within one of the directories, otherwise specify the path

Tailing Task Logs on Opencenter servers:
-----------------------

This should show the last 1K of the task logs, updating every 10 seconds.
    ./logtail.py <task_id>

Rerunning Setup Script on the 4 nodes.
-----------------------

If something failed during the setup of the node and you want to re-run the setup
script without waiting for new instances to spin up, then set RERUN=true before running
opencenter-cluster.sh with the same prefix as used initially.

    export RERUN=true
    ./opencenter-cluster.sh <Cluster-Name>

Creating DNS records
--------------------

    ./syncdns.py <cloud dns domain> <path to pyrax config file> <opencenter cluster prefix>

The DNS names execlude the cluster prefixes so that they stay consistent when you build a new cluster.

For example:

    (default27)MK63HADV33:ron-cruft hugh3869$ python syncdns.py uk.rs.wherenow.org ~/.pyrax.cfg dev1
    uk.rs.wherenow.org
      ntrapy.uk.rs.wherenow.org A 95.138.169.97
      opencenter-client2.uk.rs.wherenow.org A 95.138.170.102
      opencenter-client1.uk.rs.wherenow.org A 95.138.169.61
      opencenter-server.uk.rs.wherenow.org A 95.138.169.55

[Pyrax](https://github.com/rackspace/pyrax/blob/master/docs/pyrax_doc.md) config file example:

    [settings]
    identity_type = rackspace
    region = LON

    [rackspace_cloud]
    username = <your username>
    api_key = <your api key>
