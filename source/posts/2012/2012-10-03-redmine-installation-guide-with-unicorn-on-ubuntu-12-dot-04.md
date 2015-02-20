---
title: "Redmine manual installation guide on Ubuntu 12.04"
slug: redmine-installation-guide-with-unicorn-on-ubuntu-12-dot-04
date: 2012-10-03 00:41:08 +0200
kind: article
published: false
---

I'm quite fond of [Redmine](http://redmine.org), which is an open-source project and task management system. Although the [installation guide](http://www.redmine.org/projects/redmine/wiki/RedmineInstall) is good (and certainly better than it used to be), I felt it's not always detailed enough, particularly when it comes to deploying the thing.

And so I present this guide, where I will explain how to:

* set up a complete installation on Ubuntu 12.04, using [RVM](http://rvm.io)
* run it on the [Unicorn](http://unicorn.bogomips.org/) webserver, underneath nginx
* configure it to auto-start

Although there are various plug-and-play methods of getting Redmine working, running it this way will net you a really fast Redmine installation which uses a minimum of memory. And if you don't know anything about Ruby, Unicorn and nginx, it'll teach you a thing or two about those too.

<!-- more -->

### Starting up

The first thing we'll want to do is create a *redmine* user.

    $ sudo adduser --disabled-login redmine

This user will run the web server (Unicorn, not nginx) which keeps everything nice and tidy. Next, we need to grab and extract a copy of Redmine. You can find links over at [Rubyforge](http://rubyforge.org/frs/?group_id=1850). For example, for version 2.1.2:

    $ cd ~/Downloads
    $ wget http://rubyforge.org/frs/download.php/76495/redmine-2.1.2.tar.gz
    $ tar -xvzf redmine-2.1.2.tar.gz

Once you've got it extracted, let's copy it to `/opt` and then create an `/opt/redmine` symlink:

    $ sudo cp -r redmine-2.1.2 /opt/redmine-2.1.2
    $ sudo ln -s redmine-2.1.2/ redmine

And change the ownership to our new redmine user:

    $ sudo chown -R redmine:redmine redmine-2.1.2

### Ubuntu Dependencies

Now we need to install a few things from apt-get. First up: imagemagick. Redmine allows the creation of PNG images for gantt charts but to do this you'll need to have quite a few dependencies. You can install all of these for Ubuntu 12.04 with the following command (it'll be different for other distributions), but you only need to this if you plan on exporting PNGs.

    $ sudo apt-get install imagemagick graphicsmagick-libmagick-dev-compat libmagickwand-dev

Next up, install MySQL if you haven't got it already. You need `libmysqlclient-dev` so Ruby can connect to your MySQL server.

    $ sudo apt-get install mysql-server libmysqlclient-dev

That's all the apt-getting we need to do right now.

### Installing Ruby

Redmine is a Ruby application, which means you'll need a version of Ruby installed. Although it's possible to use the version of Ruby bundled with Ubuntu, I strongly recommend using [RVM](http://rvm.io) instead. This allows you to easily install the latest version of Ruby locally for a specific user.

So, before you install RVM, log in to the *redmine* account:

    $ sudo su - redmine

and now follow the simple instructions on the [RVM installation docs](https://rvm.io/rvm/install/) and come back here when you're done.

...

Back? OK! By now you should 1) be logged in as the redmine user, and 2) have RVM installed. Let's install Ruby:

    $ rvm install 1.9.3



### Setting up Redmine

Start by logging into the *redmine* account and go to the redmine directory:

    $ sudo su - redmine
    $ cd /opt/redmine

Time to install the Ruby gems. If you want PNG-export support (as mentioned earlier), type this:

    $ bundle install --without development test postgresql sqlite

Otherwise, this:

    $ bundle install --without development test postgresql sqlite rmagick

Next, we need to create a MySQL database for Redmine:

    $ mysql -u root -p
    mysql> create database redmine character set utf8;
    mysql> create user 'redmine'@'localhost' identified by 'redmine56789';
    mysql> grant all privileges on redmine.* to 'redmine'@'localhost';

You can use your own database name, username and password. Now we'll configure Redmine to use this database. Copy the file `config/database.yml.example` to `config/database.yml` and edit it. Inside, change the `production` section so it looks something like this, substituting the database, username and password for your own:

    #!yaml
    production:
      adapter: mysql2
      database: redmine
      host: localhost
      username: redmine
      password: redmine56789
      encoding: utf8

Generate a session store token for Redmine:

    $ rake generate_secret_token

And now run the database migrations, which will insert all the Redmine tables into your new database, and load the default Redmine data:

    $ RAILS_ENV=production rake db:migrate
    $ RAILS_ENV=production rake redmine:load_default_data

That should get us a working Redmine installation. Test it with this:

    $ rails s -e production

This will spin up the built-in WEBrick server, which is very slow and not how you'll want to run Redmine (though you could). Once it has spun up, hit the following URL and you should be greeted with the Redmine landing page. You can log in with *admin/admin*, which is the default account.

    http://localhost:3000

If everything looks OK, kill the WEBRick server and we'll set up a proper deployment using Unicorn and nginx.

### Running Redmine on Unicorn

Unicorn is a great webserver for Ruby. It's fast, uses small amounts of memory and works great with nginx. Start by creating the file `Gemfile.local` and inside put:

    gem 'unicorn'

Now run `bundle install` again and, when it's finished, Unicorn should be installed. Create the Unicorn configuration file at `config/unicorn.rb` and stick the following inside:

    #!ruby
    env = ENV[‘RAILS_ENV’] || 'production'
    socket = '/tmp/redmine.socket'
    worker_processes 2
    listen socket, :backlog => 64
    preload_app true
    timeout 45
    pid '/opt/redmine/config/unicorn.pid'

    working_directory '/opt/redmine'
    user 'redmine'