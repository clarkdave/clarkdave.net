---
title: "Ganglia and Chef"
created_at: 2013-06-17 16:51:41 +0100
kind: article
published: false
---

[Ganglia](http://ganglia.sourceforge.net/) is a scalable distributed monitoring system. If you have lots of servers, it's an excellent tool to keep track of them. For example, it's [in use at Wikimedia](http://ganglia.wikimedia.org/), monitoring almost 1,000 servers.

You might not need to monitor thousands of hosts (I sure don't), but that shouldn't stop you using it! This sort of tool is, of course, well suited to Chef, and in this guide I'll show you how to set up a Ganglia implementation using Chef.

<!-- more -->

### Quick introduction to Ganglia

Before we dig into the Chef configuration, it's worth having a brief understanding of how Ganglia works. It comprises two key parts:

**gmond**: the daemon which sits on every node, gathers statistics and sends them on. It can also be used to aggregate statistics from other hosts (for cluster support with minimal configuration).

**gmetad**: this daemon polls `gmonds` to get information. This will often run on the same server as the `ganglia-web` component, which provides the Ganglia web interface.

This guide will set up a single-cluster Ganglia implementation, using unicast. This is suitable for deploying on to Amazon EC2, which does not support multicast. Multi-cluster setups are fully supported by Ganglia, but setting them up without multicast support is a bit of a headache and there currently isn't an ideal solution.

Instead, what we'll do is dedicated one `gmond` node to act as our receiver, and have all other nodes send data to it. We'll do this using Chef search so the sending nodes can dynamically find the receiver node.

### Getting started

There are a handful of Ganglia cookbooks floating around, but there isn't an Opscode-supported one, nor is there one that seems to have large community support. The two most complete cookbooks I found are [Heavy Water's](https://github.com/hw-cookbooks/ganglia) and [GoSquared's](https://github.com/gosquared/ganglia-cookbook).

I've opted to use the one maintained by GoSquared, as is more up to date and (somewhat) actively developed. It's also highly customisable which is handy.

So ahead and install the GoSquared `ganglia-cookbook` from GitHub (it's not on the Chef site). I like to do this using the [Knife Github plugin](https://github.com/websterclay/knife-github-cookbooks):

    knife cookbook github install gosquared/ganglia-cookbook

This cookbook doesn't do any searching - it has nodes specified in the `ganglia:gmetad:clusters` attribute. This isn't really appropriate for our needs, as we only have one cluster, and so will dedicate one node to act as the receiver.

Instead, what we'll do is create a new attribute, `node[:ganglia][:gmond][:receiver]`, which we'll set on the node designated as the receiver. Bear in mind that *all* nodes will be running `gmond`, but they will all be sending the information to just *one* of them. Then, the node running `gmetad` will contact that designated `gmond` node to collect all the data. If this seems a little weird, it's because it is. Ganglia works best in a multicast environment, where `gmonds` can talk to each other and the single `gmetad` can get all data from any one `gmond`, but we'll make do.

Let's start by adding Ganglia to a run_list in a `base` role - this is a role you apply to every node:

    #!ruby
    name 'base'
    description 'base role for servers'

    # this will install gmond 
    run_list(
      'recipe[ganglia]'
    )

    # we're only using one cluster, so we'll name it here. I call it 'ec2' as all my
    # machines are on ec2. This is different from the grid name, which is set on the
    # gmetad node and is usually the name of your organisation/app
    default_attributes(
      :ganglia => {
        :gmond => {
          :cluster_name => 'ec2'
        }
      }
    )

With this, each node will have `gmond` installed and it'll start gathering statistics. But before it'll work, we need to adjust the Ganglia cookbook so that our `gmonds` are sending to the receiver. Let's start by creating a *receiver* role - this is for the node designated to receive data from `gmonds`. Because this role will be applied to a node that **already** has the `base` role, we don't need to run the Ganglia recipe again. Instead, we'll just use this role to set an attribute that denotes this node as a receiver:

    #!ruby
    name 'ganglia_receiver'
    description 'Ganglia gmond receiver node'

    override_attributes(
      :ganglia => {
        :gmond => {
          :receiver => true
        }
      }
    )

Now we'll make some adjustments to the Ganglia cookbook so that `gmonds` use Chef search to find the designated receiver node and send data to it.

**show code on github?**

