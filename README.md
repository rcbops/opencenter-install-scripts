Opencenter Cluster Install
-----------------------

This will setup a cluster containing an Opencenter Server, 2 Opencenter Clients and an Opencenter Dashboard server.
You can use the individual scripts to install the components on servers rather than creating the whole cluster.

Installing Opencenter Cluster
-----------------------

    ./opencenter-cluster.sh

    OPTIONS:
      -h --help  Show this message
      -v --verbose  Verbose output
      -V --version  Output the version of this script

    ARGUMENTS:
      -p= --prefix=<Cluster Prefix>
          Specify the name prefix for the cluster - default "c1"
      -s= --suffix=<Cluster Suffix>
          Specify a cluster suffix - default ".opencenter.com"
          Specifying "None" will use short name, e.g. just <Prefix>-opencenter-sever
      -c= --clients=<Number of Clients>
          Specify the number of clients to install, in conjunction with a server & dashboard - default 2
      -pass= --password=<Opencenter Server Password>
          Specify the Opencenter Server Password - only used for package installs - default "opencenter"
      -pkg --packages
          Install using packages
      -a --add-clients
          Add clients to existing cluster specified by --prefix
          NB - If password was used for original cluster, password must be the same as existing cluster's password
          Can't be used in conjunction with --rerun/-rr
      -n= --network=<CIDR>|<Existing network name>|<Existing network uuid>
          Setup a private cloud networks, will require "nova network-create" command - default 192.168.0.0/24
          You can specify an existing network name or network uuid
      -o= --os=[redhat | centos | ubuntu | fedora ]
          Specify the OS to install on the servers - default ubuntu
      -pk= --public-key=[location of key file]
          Specify the location of the key file to inject onto the cloud servers
      -rr --rerun
          Re-run the install scripts on the servers, rather than spin up new servers
          Can't be used in conjunction with --add-clients/-a
      -gb= --git-branch=<Git Branch>
          This will only work with non-package installs, specifies the git-branch to use.
          Defaults to "sprint"
      -gu= --git-user=<Git Branch>
          This will only work with non-package installs, specifies the user's repo to use.
          Defaults to "rcbops"

* If you are using opencenter-client locally you can set your endpoint:
export OPENCENTER_ENDPOINT=http://<ip of server>:8080
* --packages will install from packages instead of github repos, not for Dev work.
* --network will require nova with "network-create" functionality

Prerequisities For Installing Opencenter Cluster
-----------------------

* Nova client installed and working with cloud, specifically returning network information, for Rackspace cloud see:
    http://www.rackspace.com/knowledge_center/article/installing-python-novaclient-on-linux-and-mac-os
  * NB: You may need an updated version of nova-client, to ensure network information is appropriately returned.
* Either of these:
  * supernova configured and an environment variable exported NOVA="supernova your-env"
  * nova env variables set in ~/csrc.
  * nova env variables already sourced
* Up to date versions of bash & sed - this may require updating on OSX
* Either of these:
  * ~/.ssh/authorized_keys file exists, containing your key.
  * Use -pk= or --public-key= to set the location of your key file.

Installing individual servers
-----------------------

    curl -s -L http://sh.opencenter.rackspace.com/install.sh | bash -s - <options/arguments>

    OPTIONS:
      -h --help  Show this message
      -v --verbose  Verbose output
      -V --version  Output the version of this script

    ARGUMENTS:
      -r --role=[agent | server | dashboard]
             Specify the role of the node - defaults to "agent"
      -i --ip=<Opencenter Server IP>
             Specify the Opencenter Server IP - defaults to "0.0.0.0"
      -p --password=<Opencenter Server IP>
             Specify the Opencenter Server Password - defaults to "password"
      -rr --rerun
             Removes packages and reinstalls them
             Can be used to adjust IP/password information

Wiping the Cluster 
-----------------------

    ./utils/wipe.sh

    This script will delete an OpenCenter Cluster.

    OPTIONS:
      -h --help  Show this message
      -v --verbose  Verbose output
      -V --version  Output the version of this script

    ARGUMENTS:
      -p --prefix=<Cluster Prefix>
            Specify the name prefix for the cluster - default "c1"
      -s --suffix=<Cluster Suffix>
            Specify a cluster suffix - defaults ".opencenter.com"
            Specifying "None" will use short name, e.g. just <Prefix>-opencenter-sever


This will remove all cloud servers in the cluster and delete the specific logs in /tmp
Simply using ./utils/wipe.sh <Cluster-Prefix> will attempt to wipe that cluster prefix

Pushing updates to the Cluster
-----------------------

From within "opencenter", "opencenter-agent", "opencenter-client", "opencenter-dashboard" directories on your local laptop/desktop
you can push updates and have the services restart automaticallyL

    ./utils/push.sh <arguments/options>

    OPTIONS:
       -h --help  Show this message
       -v --verbose  Verbose output
       -V --version  Output the version of this script

    ARGUMENTS:
       -p --prefix=<Cluster Prefix>
            Specify the name prefix for the cluster - default "c1"
       -s --suffix=<Cluster Suffix>
            Specify a cluster suffix - default ".opencenter.com"
            Specifying "None" will use short name, e.g. just <Prefix>-opencenter-sever
       -proj --project=[opencenter-all | opencenter | opencenter-agent | opencenter-client | dashboard]
            Specify the projects to push - defaults to opencenter-all
       -r --repo-path=<Local path to repositories>
            Specify the local path to your repositories
       -rs --rsync
            Use rsync instead of git to push the repos
       -f --force
            Use "git push -f" to force the push

 Tailing Task Logs on Opencenter servers:
-----------------------

This should show the last 1K of the task logs, updating every 10 seconds.
    ./utils/logtail.py <task_id>
 
Creating DNS records
--------------------

    ./utils/syncdns.py <cloud dns domain> <path to pyrax config file> <opencenter cluster prefix>

The DNS names execlude the cluster prefixes so that they stay consistent when you build a new cluster.

For example:

    (default27)MK63HADV33:utils hugh3869$ python syncdns.py uk.rs.wherenow.org ~/.pyrax.cfg dev1
    uk.rs.wherenow.org
      opencenter-dashboard.uk.rs.wherenow.org A 95.138.169.97
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
