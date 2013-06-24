---
title: "Multi-cluster Ganglia on EC2 or unicast networks"
description: How to set up multiple clusters with Ganglia on Amazon EC2 or unicast networks, with examples in Chef
created_at: 2013-06-21 14:55:18 +0100
kind: article
published: true
---

[Ganglia](http://ganglia.sourceforge.net/) is a scalable distributed monitoring system, and is excellent for keeping tabs on 10s or 1,000s of servers.

It works best on multicast-capable networks, where its army of `gmonds` will chat to one another with minimal configuration, and the `gmetad` federator is able to ask any of them for data, but it's fairly simple to set up a single cluster implementation on a unicast network too.

However, one of Ganglia's awesome features - multiple clusters - is considerably more complicated to set up on a unicast network. There are a few options to do it:

* Dedicate one `gmond` in each cluster as the *receiver*, and have all the others in that cluster send to it. This is OK, but if that one server goes down, there'll be no stats for that cluster.
* Run one receiving `gmond` per cluster on a dedicated *reporting* machine (e.g. same as `gmetad` is on). Works, but annoying to configure as you've got a big stack of `gmonds` running on one server.
* Emulate multicast support by having each `gmond` in each cluster send/receive to all or some of the others. A central `gmetad` is configured to point at one or more of these `gmonds` for each `data_source` (cluster).

None of these are as elegant as the default multicast configuration, but we'll have to make do. I've opted to use the third option as I believe it strikes the best balance between reliability and ease of maintenance, and to avoid having 100s of nodes spamming all the others constantly, you can designate a handful of *receiver* nodes in each cluster and have all the others report to those.

**Note:** doing this by hand will *not* be fun. Combine this guide with your server automation tool of choice - I'll be using Chef, so you'll need to translate the instructions yourself if you're using something else.

<!-- more -->

### Installing Ganglia

First you'll want to have a basic Ganglia set up with your chosen automation tool. I'm using [Heavy Water's Ganglia cookbook](https://github.com/hw-cookbooks/ganglia) as a base. Although it'll need heavy tweaking for this use case, it's a good place to start.

Once you have `gmonds` installed on each node you want to monitor, and `gmetad` (and, optionally, `ganglia-web`) installed on a designated monitoring server, we can get started with the configuration.

### Cluster attributes

In Chef, you can use your roles to describe the cluster for each node. For example, I have roles like `app server`, `mongodb server` etc and I'd like each of these to be a cluster. So, in my `roles/app_server.rb` file, I have the following attributes, which will be used later:

    #!ruby
    override_attributes(
      :ganglia => {
        :gmond => {
          :cluster_name => 'app servers'
        }
      }
    )

You'll probably also want to add some defaults into a `base` role which is applied to every monitored node:

    #!ruby
    default_attributes(
      :ganglia => {
        :gmond => {
          :cluster_name => 'generic server',
          :cluster_owner => 'Your Organisation'
        }
      }
    )

### gmond configuration

`gmond.conf` is the main configuration file for `gmond`. Unless a gmond is configured to be `deaf` it will open up a UDP server on the specified port and allow other `gmonds` to send data to it. On a multicast network, these `gmonds` would all join the same multicast group and share information automatically, but we'll need to specifically tell each `gmond` which hosts to send data to.

You have a choice here - if your clusters are fairly small (I'd say, 10 servers or less), you can tell each `gmond` in a cluster to spread data to every other `gmond` in the same cluster. This will be simpler to configure; however, if your clusters are quite large, this would involve a *lot* of connections on every server, which doesn't strike me as the best idea. Instead, you could nominate a handful of servers in each cluster to be the *receivers*, and have all the others send to those. So long as one of those receivers is online, all the other servers in that cluster can continue to share data.

#### Get the list of nodes in the same cluster

In Chef, this can be done with a search. So, in your recipe where you create the `gmond.conf`, add something like:

    #!ruby
    this_cluster = node[:ganglia][:gmond][:cluster_name]
    gmonds_in_cluster = []

    search(:node, "ganglia_gmond_cluster_name:\"#{this_cluster}\" AND chef_environment:#{node.chef_environment}") do |n|
      gmonds_in_cluster << n[:ipaddress]
    end

Then pass this into your `gmond.conf` template and do:

    #!ruby
    <% @gmonds_in_cluster.each do |host| %>
    udp_send_channel {
      host = <%= host %>
      port = 8659
      ttl = 1
    }
    <% end %>

    udp_recv_channel {
      port = 8659
    }

Once Chef has converged on all the nodes in that cluster, each `gmond.conf` will have a list of other `gmonds` to send to.

If you wanted to limit how many receivers you have (so, instead of every `gmond` talking to every other `gmond`, you designate only a few, and set the others to be deaf) you could adjust the search logic we used above. You could sort the list of nodes in the cluster, and attach an attribute to the first 2, e.g. `node.set_unless[:ganglia][:gmond][:receiver] = true`.

Then all your search logic only searches for nodes where `ganglia_gmond_receiver:true` and, when you configure the `gmetad`, you restrict the `data_source` to use only these nodes too. This should reduce network activity whilst still maintaining redundancy.

### gmetad configuration

The `gmetad` daemon provides federation across all your `gmonds`. Each cluster is represented in `/etc/gmetad.conf` by a `data_source` option, e.g. `data_source "app servers" host1 host2`

When the `gmetad` looks for a host for a particular data source, it tries the first one and uses the others for redundancy. This is the reason we couldn't have a far simpler configuration where each `gmond` is independent and the `gmetad` is configured to ask all of them for data - it would only ever get data from one, and ignore the rest.

#### Get the list of clusters and gmond hosts

Configuring `gmetad` is fairly straightforward: we just use search to get a list of all known clusters along with their `gmond` hosts:

    #!ruby
    # find all nodes running ganglia so we can collect clusters
    clusters = {}

    # all my nodes with ganglia have the ganglia recipe - adjust as needed
    search(:node, "recipes:ganglia AND chef_environment:#{node.chef_environment}") do |n|
      name = n[:ganglia][:gmond][:cluster_name]
      clusters[name] 
        ? clusters[name] << n[:ipaddress]
        : clusters[name] = [n[:ipaddress]]
    end

If only a limited subset of your `gmonds` are acting as receivers, make sure you're only feeding these nodes into `gmetad`, for example:

    search(:node, "recipes:ganglia AND ganglia_gmond_receiver:true AND chef_environment:#{node.chef_environment}") do |n|
      name = n[:ganglia][:gmond][:cluster_name]
      clusters[name] 
        ? clusters[name] << n[:ipaddress]
        : clusters[name] = [n[:ipaddress]]
    end

Then pass the list of clusters and hosts into your `gmetad.conf` template:

    #!ruby
    <% @clusters.each do |name, hosts| %>
    data_source "<%= name %>" <%= hosts.join(' ') %>
    <% end %>

### Testing it and debugging

That should do it for the configuration. If everything has worked, you'll be able to turn it all on, set up your monitoring server with a `gmetad` and the Ganglia web UI, and see all your clusters and data appear.

If you run into problems, it's easiest to start debugging at a cluster level. Turn off your `gmetad` and all the `gmonds` in a single cluster and then start up two `gmonds` on two machines in that cluster.

On one of them, use `nc localhost 8649`. This should splurge out some XML. Inside the `<CLUSTER>` tag you should, if the `gmonds` are talking to each other, have at least two `<HOST>` entries, one for each node running `gmond`.

Common things to check:

* Firewall configuration (or security groups on AWS):
  * `gmonds` all communicate via a UDP port (`8649` by default), so this needs to be open for in/out connections on nodes
  * `gmetad` gets data from `gmonds` via TCP port `8649` (default), so this should be open on any nodes running `gmond` that are marked as receivers
* Each `gmond` should be configured to list *itself* as a `udp_send_channel`, even if it's the only node in a cluster. Not listing this will probably result in weird issues.

I have this implementation running in production at [LoyaltyLion](http://loyaltylion.com) and it's working great. If you run in to any issues, feel free to comment and I'll see if I can help.