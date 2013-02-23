---
title: "Send deploy keys to Bitbucket in a Chef recipe"
created_at: 2013-02-22 23:36:54 +0100
kind: article
published: true
---

A common thing to do with Chef and app server configuration is to create a 'deploy' user. This user will be involved with the deployment of code and often needs read-only access to the source repository. In my case, this was Bitbucket, but this procedure should copy across with a few tweaks for GitHub or most other providers too.

In the case of Bitbucket (and GitHub) a deploy user is given read-only access to a repository through their ssh key. Because we're creating our deploy user through Chef anyway, along with their ssh key, it makes a lot of sense to send this off to Bitbucket and that's what this little recipe does:

    #!ruby
    # create the deploy user
    user "deploy" do
      shell "/bin/bash"
      home "/home/deploy"
      supports :manage_home => true
    end

    chef_gem 'httparty'

    # create their ssh key
    execute 'generate ssh key for deploy' do
      user 'deploy'
      creates '/home/deploy/.ssh/id_rsa'
      command 'ssh-keygen -t rsa -q -f /home/deploy/.ssh/id_rsa.pub -P ""'
      notifies :create, "ruby_block[add_ssh_key_to_bitbucket]"
    end

    # send id_rsa.pub over to Bitbucket as a new deploy key
    ruby_block "add_ssh_key_to_bitbucket" do
      action :nothing # only run when ssh key is created
      block do
        require 'httparty'
        url = "https://api.bitbucket.org/1.0/repositories/#{node['bitbucket_user']}/repo-name/deploy-keys"
        response = HTTParty.post(url, {
          :basic_auth => {
            :username => node['bitbucket_user'],
            :password => node['bitbucket_pass']
          },
          :body => {
            :label => 'deploy@' + node['fqdn'],
            :key => File.read('/home/deploy/.ssh/id_rsa.pub')
          }
        })

        unless response.code == 200 or response.code == 201
          Chef::Log.warn("Could not add deploy key to Bitbucket, response: #{response.body}")
          Chef::Log.warn("Add the key manually:")
          Chef::Log.info(File.read('/home/deploy/.ssh/id_rsa.pub'))
        end
      end
    end

The `bitbucket_user` and `bitbucket_pass` attributes should be set somewhere, and in the url you'll want to change `repo-name` to the actual repo you're deploying to. Bitbucket only lets you add deploy keys per repository, so if this user will be deploying from multiple repositories this is a good place to do it - just update the Ruby block so it loops through all your repositories and sends a deploy key off for each one.

You'll most likely want to run this only on production or staging environments, otherwise you could end up adding dozens of junk deploy keys to Bitbucket while you're spinning up all those Vagrant VMs!