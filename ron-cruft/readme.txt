I don't like your fancy markup readmes.

This is the stuff I've been using.  It probably won't work
for you.  If it doesn't, I'm not really that concerned.  You
should abstract it to the point that it works for you and
push it up to the repo.  It would be nice if it didn't change
default behavior.

But do what you have to do.

Prereqs:

 - Nova client installed and working with cloud servers
 - A posixy environment.  I've only tested on OSX.  might not work on
   teh loonix.

Assumptions:

 - This is set up for cloud servers - it uses file injection to
   set up ssh keys.  This isn't the way to go on a real nova cluster.

 - This assumes you have stuff set up like me.  Your authorized_keys
   includes your own key, as it will be copied to /root/.ssh/authorized_keys

 - (this one likely doens't work for you) you have a key in .ssh named
   "id_github" that's a unpassworded github-only rsa key for your
   github user.  This key gets copied up and used to bootstrap the
   repos, then is removed from the box.  After this happens, use
   push.sh to push your repos to the cluster.

 - Might collide with other users if you are using a shared account.

Usage:

  ./roush-dev.sh c1

  makes a "cluster" called c1, with nodes "c1-roush-server",
  "c1-roush-client1" and "c1-roush-client2".  the cluster name
  defaults to c1, and it's up to you not to collide with an existing
  cluster.  If you do, stuff breaks.  Don't do that.

  Once the cluster is up, it will install roush client and server,
  configure them, and you are off to the races.  set your endpoint:

  export ROUSH_ENDPOINT=http://<ip of server>:8080

  then you can r2 away.

Wiping the cluster:

  ./wipe.sh c1

  wipes all machines in cluster c1.

Updating the cluster:

  This assumes you have roush, roush-agent, and roush-client in peer
  directories.  From one of these directories, run push.sh <cluster>
  and it will push your current versions of everything to all the
  nodes in the cluster and restart everything.

  This fits my use case, as I mess with stuff on my laptop, then
  push to the cluster.  You may want something else -- like to
  dev on the roush server itself and push horizontally.

  that would be nice.  this doesn't do that.  sorry.

Tailing logs of tasks:

  You should be able to run ./logtail.py <task_id> and have it show
  the last 1K of the task logs, updating every 10 seconds.

  This is recent and requires the clients can connect to any arbitrary
  port on the server.  So it might not work for you.  If it doesn't,
  fix roush/webapp/tasks.py.


If you find this useful, please help make it better.  If you find it
almost useful, please help make it better.  If you find it useless,
write something better and let me know where it is so I can use it
too.

 -- Ron
