---
title: "Managing EBS volumes with Chef"
description: How to use the opscode-aws cookbook to manage EBS volumes on Chef nodes, with configurable attributes for different roles and environments
created_at: 2013-04-10 14:25:15 +0100
kind: article
published: true
---

Chef works great for creating and attaching Amazon EBS volumes to instances, and there's an Opscode `chef-aws` cookbook which has providers for working with single EBS volumes and also for creating RAID arrays from multiple volumes.

The `chef-aws` cookbook is fairly straightforward on its own, but requires a little DIY to get it fully working. I'll explain here how to use this cookbook to effectively create single or RAID EBS volumes and allow these to be customised using attributes in roles or environments (so you could have your staging DB use a single 20GB volume, and your production DB use a 200GB RAID).

<!-- more -->

### Getting started

We'll start by grabbing the `aws` cookbook. The version released in Opscode community is `0.100.6` and does not have the `ebs_raid` provider which is present in the master on GitHub. The cookbook doesn't see a huge amount of development, so it should be fine to grab a copy from master. You can get it yourself, or use the nifty [Knife Github plugin](https://github.com/websterclay/knife-github-cookbooks) which will let you run:

    knife cookbook github install opscode-cookbooks/aws 

which will install the master from GitHub and track changes as a branch.

### Recipes and roles

For the sake of these examples, I'll assume you have a cookbook called `app`.

You'll probably have a specific use-case in mind for your EBS volumes - for example, you may be using them for a database. So, let's create a `database` recipe in the `app` cookbook and add this inside it:

    #!ruby
    # The database recipe should be included by any server running a DB. It creates
    # a /data directory and, if on EC2, will mount an EBS volume here

    directory '/data' do
      mode '0755'
    end

`recipe[app::database]` should be added to any of your database server roles, e.g. PostgreSQL or MongoDB. These databases would be configured to use the `/data` directory provided by the `app::database` recipe, like so:

    #!ruby
    name 'mongodb_server'
    description 'MongoDB server'

    run_list 'recipe[app::database]', 'recipe[mongodb]'

    default_attributes(
      :mongodb => { :dbpath => '/data/mongodb' }
    )

### Configuration and attributes

I suggest using attributes to determine our EBS configuration, which will allow you to change the EBS parameters in roles and environments. I use this to create smaller EBS volumes on staging instances, and larger, RAIDed volumes in production. If you run different DB servers, you can also override these attributes in their respective roles (perhaps you want smaller volumes for PostgreSQL, and larger for MongoDB).

Start by creating some default attributes in the `app` cookbook (so in `cookbooks/app/attributes/default.rb`):

    #!ruby
    default[:app][:ec2] = false
    default[:app][:ebs] = {
      :raid => false,
      :size => 20 # size is in GB
    }

As you can see, our roles/environments can now selectively dictate the size of their EBS volume, and if it should be a RAID.

We've also set one other default, `[:app][:ec2]`, which is set to false. The idea is you set this to true in those environments which will be running on EC2, so you can avoid running any EC2-related stuff on nodes that aren't on AWS (e.g. local machines, vagrant test runs, etc).

Alternatively, you could use Ohai's `cloud` attributes to determine if the current node is running on EC2. If this works reliably for you, feel free to use that and eschew the [:app][:ec2] attribute entirely.

### Creating the EBS volumes

Now, back to our `recipes/database.rb` file. Before we add the code for creating the volumes, make sure you've added your AWS credentials to a data bag, as explained on [aws cookbook's GitHub page](https://github.com/opscode-cookbooks/aws#aws-credentials).

    #!ruby
    if node[:app][:ec2] || node[:cloud][:provider] == 'ec2' # the latter check uses Ohai's cloud detection

      # get AWS credentials from the aws data_bag
      aws = data_bag_item('aws', 'main')

      include_recipe 'aws'

      if node[:app][:ebs][:raid]

        # use the aws_ebs_raid provider to create and mount a RAID volume. This provider 
        # basically does everything for us, so there's nothing more to do!
        aws_ebs_raid 'data_volume_raid' do
          mount_point '/data'
          disk_count 2
          disk_size node[:app][:ebs][:size]
          level 10
          filesystem 'ext4'
          action :auto_attach
        end
      else
        # create a single EBS volume
        ## TODO
      end
    end

There are several other options for a RAID disk: the number of disks, the level and filesystem. If you need these to change across roles/environments, you should add these as attributes in `[:app][:ebs]` too.

Now let's fill in the `## TODO` section and create single EBS volumes. The provider for this does not mount or create a filesystem for single volumes, so we'll have to do that by hand:

    #!ruby
    # get an unused device ID for the EBS volume
    devices = Dir.glob('/dev/xvd?')
    devices = ['/dev/xvdf'] if devices.empty?
    devid = devices.sort.last[-1,1].succ

    # save the device used for data_volume on this node -- this volume will now always
    # be attached to this device
    node.set_unless[:aws][:ebs_volume][:data_volume][:device] = "/dev/xvd#{devid}"

    device_id = node[:aws][:ebs_volume][:data_volume][:device]

    # create and attach the volume to the device determined above
    aws_ebs_volume 'data_volume' do
      aws_access_key aws['aws_access_key_id']
      aws_secret_access_key aws['aws_secret_access_key']
      size node[:app][:ebs][:size]
      device device_id.gsub('xvd', 'sd') # aws uses sdx instead of xvdx
      action [:create, :attach]
    end

    # wait for the drive to attach, before making a filesystem
    ruby_block "sleeping_data_volume" do
      block do
        timeout = 0
        until File.blockdev?(device_id) || timeout == 1000
          Chef::Log.debug("device #{device_id} not ready - sleeping 10s")
          timeout += 10
          sleep 10
        end
      end
    end

    mount_point = '/data'

    # create a filesystem
    execute 'mkfs' do
      command "mkfs -t ext4 #{device_id}"
      # only if it's not mounted already
      not_if "grep -qs #{mount_point} /proc/mounts"
    end

    # now we can enable and mount it and we're done!
    mount "#{mount_point}" do
      device device_id
      fstype 'ext4'
      options 'noatime,nobootwait'
      action [:enable, :mount]
    end

And that's pretty much it. The `ebs` providers will save attributes on the node (in `[:aws][:ebs_volume]` and `[:aws][:raid]`) so they remember which volumes are associated with it. This means that if the volumes are detached, the next `chef-client` run should reattach them correctly. It is also possible, using the same providers, to attach existing volumes instead of creating them on demand.

All you need to do now is adjust your database server configurations to use the `/data` directory, and configure your roles and environments with suitable EBS settings.

You can see the entire `app::database` recipe [on GitHub](https://gist.github.com/clarkdave/5477434).

**Updated 2014-05-14:** added `sleeping_data_volume` improvements by Joshua Timberman