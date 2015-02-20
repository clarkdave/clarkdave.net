---
title: "Guide to setting up Nagios with Chef"
slug: guide-to-setting-up-nagios-with-chef
description: A comprehensive guide to installing and configuring Nagios using Chef
date: 2013-06-11 15:38:00 +0100
kind: article
published: true
---

Nagios is an awesome open source tool for monitoring servers and applications, and, being such a mission to install and configure, it's a perfect use case for Chef. Opscode have a nice [Nagios cookbook](https://github.com/opscode-cookbooks/nagios) but it's still not the most straightforward thing to get running.

To make things easier, I'll explain here how to use this cookbook to set up a Nagios server and have it monitor multiple client servers and applications such as PostgreSQL, MongoDB and nginx.

<!-- more -->

### Configure the Nagios server

Start off by installing the Nagios cookbook:

    knife cookbook site install nagios

Now you'll want to create a role for your Nagios server. You can call this role `monitoring`, like the Nagios cookbook expects, or use something else (like `nagios_server`).

In your new role (e.g. `roles/monitoring.rb`), add the following:

``` ruby
name 'monitoring'
description 'Monitoring server'

run_list(
  'recipe[nagios::server]'
)

default_attributes(
  :nagios => {
    :server_auth_method => 'htauth',
    :url => 'nagios.tools.example.com'
  }
)
```

The Nagios cookbook supports serving the Nagios web UI on nginx, but I recommend sticking with the default, Apache. I initially tried using nginx but it didn't work out of the box and required a bit of fiddling. 

The `nagios:url` property above is used as a URL for Apache and nginx to listen on, which is helpful you are hosting other websites on the same server. You can leave it out and it will default to the server's fqdn.

#### Add a Nagios user

Nagios looks for users in various data bags. In particular, it looks in:

* the `users` data bag, for users in the `sysadmin` group, and gives them access to the Nagios web UI and will notify them on their `nagios:email` attribute
* the `nagios_contacts` and `nagios_contactgroup` data bags for more granular notifications

If you haven't already, create a `users` data bag and add yourself in. For example, in `data_bags/users/clarkdave.json`:

``` json
{
  "id": "clarkdave",
  "password": "...",
  "groups": [
    "sysadmin"
  ],
  "shell": "/bin/bash",
  "htpasswd": "...",
  "nagios": {
    "email": "you@example.com"
  }
}
```

The `htpasswd` attribute should be a password hash, and will be used for this user to log in to the web UI. You can generate one with the `htpasswd` command, e.g: `htpasswd -nb username badpassword`.

Don't forget to add this item once you're done: `knife data bag from file users data_bags/users/clarkdave.json`

Add more users as needed, and refer to the [Contacts and Contact Groups](https://github.com/opscode-cookbooks/nagios#contacts-and-contact-groups) documentation on the cookbook if you need more granular notifications.

### Configure Nagios clients

We can use the Nagios cookbook to install `NRPE` clients on each server we'd like to monitor. If you're not familiar with Nagios, the *Nagios Remote Plugin Executer* (NRPE) lets you execute Nagios plugins on other nodes, and have these metrics sent back to the Nagios server.

You can install the NRPE client with the `nagios::client` recipe. You'll typically want to add this to a `base` role, which is applied to all servers. For example, in `roles/base.rb`:

``` ruby
name 'base'
description 'base role for servers'

run_list(
  # this adds NRPE support
  'recipe[nagios::client]',
  # this installs base NRPE checks (see below)
  'recipe[example::base_monitoring]'
)

default_attributes(
  :nagios => {
    # you only need this if your nagios server uses a role other than 'monitoring'
    :server_role => 'monitoring'
  }
)
```

**Important:** NRPE uses port `5666`, so make sure to allow connections on this port from the Nagios server on each client node you'll be monitoring.

#### Adding an NRPE check

When the `nagios::client` recipe has been applied to a node, that node can use the `nagios_nrpecheck` provider to set up checks to run, such as load, memory usage or anything else (database stats, etc).

You'll probably want to have two sets of recipes to set up the NRPE checks. One recipe for base monitoring (checks to be applied to all servers, like load, memory usage, etc) and other recipes for specific types of server. So, if you have a recipe for setting up your PostgreSQL server, you'll use `nagios_nrpecheck` in that recipe to monitor the PostgreSQL install.

Here's an example of a *base monitoring* recipe, in `recipes/example/base_monitoring.rb`. We'll start with the `check_load` plugin, which is bundled with Nagios and reports the current system load average:

``` ruby
# test the current system load average
nagios_nrpecheck "check_load" do
  command "#{node['nagios']['plugin_dir']}/check_load"
  warning_condition "6"
  critical_condition "10"
  action :add
end
```

This is all we need to do for the client node, but we still need to let our Nagios server node know about this check. We do this using the `nagios_services` data bag. This is explained in more detail in the [cookbook documentation](https://github.com/opscode-cookbooks/nagios#services), but it involves having an item in the `nagios_services` data bag for each check we want the server to register. This means we don't need to manually edit the Nagios services config by hand.

We'll create a service for our `check_load` NRPE above. Create a new data bag item: `data_bags/nagios_services/load.json`. The service will be named with the data bag item ID prepended with `check`, so in this case `check_load`. Inside, add:

``` json
{
  "id": "load",
  "hostgroup_name": "all",
  "command_line": "$USER1$/check_nrpe -H $HOSTADDRESS$ -c check_load -t 20"
}
```

This service definition tells the Nagios server to run the `check_nrpe` command against `$HOSTADDRESS$` (which is populated for you), telling it to run the `check_load` command and gives the whole thing a timeout of 20 seconds. The `hostgroup_name` tells Nagios which hostgroups should run this check. The Nagios cookbook automatically groups your nodes into hostgroups based on their role, so you can leave this as `all` to run the check everywhere, or enter a role name to only run the check on nodes with a particular role (e.g. `app_server`).

Make sure to create the `nagios_services` data bag and add this new item: `data bag create nagios_services && data bag from file nagios_services data_bags/nagios_services/load.json`.

### Testing it out

You should try out what you've got so far before adding more checks. Unfortunately, because the Nagios cookbook is so heavily reliant on search, it's probably not possible to test this using Chef Solo and Vagrant. It **might** be possible to use the [chef-solo-search](https://github.com/edelight/chef-solo-search) library to make some of it work with Chef Solo, but because of the client/server aspect you'll need to test it out against a real Chef Server.

Upload your Chef config to your server and then run `chef-client` on the node you've given the `monitoring` role to. Once the run completes, access the Nagios web UI with either the `node[:nagios][:url]` attribute (if set) or the node's FQDN. You should be presented with an auth dialog, where you should log in as one of the users in the `sysadmin` group, using that user's `htpasswd`.

If all worked well, you should be presented with the beautiful Nagios web interface. If you have multiple nodes, it may already be detecting your other machines and potentially reporting them as down if it can't ping them. If this is the case, you'll want to adjust your firewall rules to allow ICMP access to these servers from the Nagios server.

You should have a few services up already -- the `load` service we added earlier, and a `Nagios` service on the Nagios server node. These should all be green. If any are red, it's probably due to one of the following:

* misconfigured firewalls between nodes (NRPE needs port `5666` to be open on clients)
* missing nagios_services data bag
* the `nagios:server_role` attribute on your client nodes is incorrect 

Hopefully everything's green, and so we can move on adding some additional checks.

### Monitoring additional services

You'll probably have a whole bunch of specific services you need to monitor, so the following examples may not apply directly, but you can use them as a guide.

#### Installing custom plugins

Nagios bundles quite a few plugins (see [Nagios Plugins](http://nagiosplugins.org/node/2) for a list) but there are even more available at the [Nagios Exchange](http://exchange.nagios.org/directory/Plugins) or on GitHub.

Plugins are generally just single file scripts, and so they're easy to install on your nodes. The approach that has worked well for me is to place the plugin file in the `files` directory of my cookbook, and then use the `cookbook_file` provider to copy it into place.

For example, to install the plugin at `cookbook/example/files/default/nagios/check_nginx.py`:

``` ruby
cookbook_file "#{node['nagios']['plugin_dir']}/check_nginx" do
  source 'nagios/check_nginx.py'
  mode '0755'
end
```

#### Monitoring nginx

For a basic *up* check, you can use the `check_http` plugin to simply make a request to nginx, but I use the [check_nginx](http://exchange.nagios.org/directory/Plugins/Web-Servers/nginx/check_nginx/details) plugin for this which also sends back some connection stats.

To use this plugin, you'll need to have the nginx `status_module` enabled. This is easy to do using the `nginx::http_stub_status_module` recipe, which sets up an endpoint at `localhost:8090/nginx_status` (accessible by localhost only).

Now in a recipe you can do:

``` ruby
nagios_nrpecheck "check_nginx" do
  # make sure to install the check_nginx plugin
  command "#{node['nagios']['plugin_dir']}/check_nginx"
  # adjust parameters as needed
  parameters '--url localhost:8090 --path /nginx_status'
  action :add
end
```

And create a data bag item in `nagios_services`, `data_bags/nagios_services/nginx.json`:

``` json
{
  "id": "nginx",
  "hostgroup_name": "app_server",
  "command_line": "$USER1$/check_nrpe -H $HOSTADDRESS$ -c check_nginx -t 10"
}
```

I've set the `hostgroup_name` to `app_server`, as that's the only role I have which uses nginx.

#### Monitoring MongoDB

I use this excellent [mongodb plugin](https://github.com/mzupan/nagios-plugin-mongodb) to run checks on MongoDB. In addition to a basic connection check, this plugin supports checking all sorts of other nice things, like open connections, replication lag, memory usage and more.

Add the following to a recipe to be executed on your MongoDB server:

``` ruby
# the plugin requires pymongo, so install it - this requires the python cookbook
include_recipe 'python'
python_pip 'pymongo' do
  action :install
end

# a basic connection health check
nagios_nrpecheck "check_mongodb" do
  command "#{node['nagios']['plugin_dir']}/check_mongodb"
  # if your MongoDB doesn't bind to node[:ipaddress], adjust accordingly
  parameters "--host #{node[:ipaddress]} --port 27017 --action connect --warning 2 --critical 5"
  # warn if connection takes over 2 seconds, error if it's over 5
  warning_condition '2'
  critical_condition '5'
  action :add
end
```

And add the corresponding service data bag item in `data_bags/nagios_services/mongodb.json`:

``` json
{
  "id": "mongodb",
  "hostgroup_name": "mongo_server",
  "command_line": "$USER1$/check_nrpe -H $HOSTADDRESS$ -c check_mongodb -t 10"
}
```

There are a *lot* more potential checks you can do on MongoDB with this plugin - check out the [GitHub repo](https://github.com/mzupan/nagios-plugin-mongodb) for more information.

#### Monitoring PostgreSQL

Nagios bundles the `check_pgsql` plugin which is effective at confirming if a PG database is accepting connections. Add the following to a recipe:

``` ruby
# the check_pgsql plugin needs a nagios user in PG to connect as. My PG requires passwords,
# so I set a nagios password for this. This user should not have any permissions
bash 'create_nagios_user' do
  user 'postgres'
  code "psql -c \"CREATE USER nagios WITH PASSWORD 'nagios'\""
  # not if the nagios user has already been created
  not_if "psql postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='nagios'\" | grep 1", :user => 'postgres'
end

nagios_nrpecheck "check_postgresql" do
  command "#{node['nagios']['plugin_dir']}/check_pgsql"
  # if you don't require passwords, you can skip the --password option
  parameters "--hostname #{node[:ipaddress]} --password nagios --warning 2 --critical 5"
  action :add
end
```

And the service data bag item,

``` json
{
  "id": "postgresql",
  "hostgroup_name": "postgresql_server",
  "command_line": "$USER1$/check_nrpe -H $HOSTADDRESS$ -c check_postgresql -t 10"
}
```

That should do it.

### Enabling notifications

Once everything is set up, you should consider enabling notifications, so Nagios can send emails when things go down. This is straightforward: add the `postfix` cookbook and then add a few attributes to your monitoring role. It should look something like this:

``` ruby
run_list(
  'recipe[nagios::server]',
  'recipe[postfix]'
)

default_attributes(
  :nagios => {
    :server_auth_method => 'htauth',
    :url => 'nagios.example.com',
    :notifications_enabled => '1'
  }
)

override_attributes(
  :postfix => {
    :myhostname => 'nagios.example.com',
    :mydomain => 'example.com'
  }
)
```

Once notifications are enabled, you should start getting emails from `nagios@nagios.example.com` - you can adjust the hostname if needed. The users who will be emailed will depend on how you set up your users data bag earlier.

We're pretty much done. You should continue adding more services as you need, and refer to the [Nagios cookbook documentation](https://github.com/opscode-cookbooks/nagios) for more information, such as how to group your services and set up more granular notifications. 

### (Optional) Use nginx as a reverse proxy

If you're serving the Nagios web UI from Apache, but have nginx listening on port 80, you may want to proxy requests to Nagios over to Apache.

I'll assume you've already got the nginx cookbook and have it installed and working on your Nagios server, so now create a new recipe in your main cookbook, `cookbooks/example/recipes/nagios_server.rb` and add:

    #!ruby
template "#{node['nginx']['dir']}/sites-available/nagios" do
  source 'nginx/nagios.erb'
  notifies :reload, 'service[nginx]'
end

nginx_site 'default' do
  enable false
end

nginx_site 'nagios' do
  enable true
end

Next, create a template, `cookbooks/example/templates/default/nginx/nagios.erb`:

    server {
      listen 80;
      server_name <%= node['nagios']['url'] %>;

      client_max_body_size 10M;

      root <%= node['nagios']['docroot'] %>;

      access_log off;

      location / {
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_http_version 1.1;

        proxy_pass http://127.0.0.1:<%= node['nagios']['http_port'] %>;
      }
    }

Finally, update your `monitoring.rb` role:

``` ruby
# add the new recipe to the run_list
run_list(
  'recipe[nagios::server]',
  'recipe[example::nagios_server]'
)

# use an appropriate port for Apache to listen on for Nagios
default_attributes(
  :nagios => {
    :server_auth_method => 'htauth',
    :url => 'nagios.example.com',
    :http_port => '8765'
  }
)

# override the apache listen_ports attribute, so it won't try to use port 80
# and will instead listen on the one we need
override_attributes(
  :apache => {
    :listen_ports => ['8765']
  }
)
```

That should do it. Once you run `chef-client` on your Nagios server you should now be able to go to `nagios.example.com` and it'll be served by Apache, through nginx.