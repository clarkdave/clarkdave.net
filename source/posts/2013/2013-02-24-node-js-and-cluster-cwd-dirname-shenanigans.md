---
title: "Node.js Cluster and working directory shenanigans"
slug: node-js-and-cluster-cwd-dirname-shenanigans
date: 2013-02-24 07:17:03 +0100
kind: article
published: true
---

[Cluster](https://nodejs.org/api/cluster.html) is a excellent built-in Node.js module which lets you run a master node process which spawns, balances and maintains multiple child processes. One nice advantage of this is you can reload the worker processes independently, so you can get zero-downtime deploys by deploying the new code, and asking the master to reload its workers.

Let's say we have the following master setup:

```ruby
cluster.setupMaster({
  exec: '/app/current/worker.js'
});
```

On start, and when asked to reload, the cluster master forks `node /app/current/worker.js` processes. My problem came about due to my deploy process, with Capistrano. On a deploy, Capistrano adds the application code into a timestamped `/app/releases` directory, and then creates a symlink from `/app/releases/timestamp -> /app/current`.

Following the deploy, the cluster master happily reloads its workers. The problem is, the _working directory_ of the cluster master is an _old_ release (specifically, whatever the `/app/current` symlink pointed at when the master was last started). When Cluster forks a child process, that child process has the same working directory as the master.

What ended up occuring was the `node /app/current/worker.js` would run, and correctly load the `worker.js` file from the current symlink of `/app/current` (so, the latest release). However, anything inside `worker.js` which references process.cwd(), such as `require('./lib/something')`, would actually be resolved to an old file.

The special `__dirname` variable would, however, show the real directly, as `__dirname` shows the directory the current script is executed from. So, knowing that, the fix was simple - at the top of `worker.js`, make sure the cwd is the same as `__dirname` and change it if not.

```ruby
if (__dirname !== process.cwd()) {
  process.chdir(__dirname);
}
```
