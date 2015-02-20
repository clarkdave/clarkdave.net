---
title: "PostgreSQL quick start for people who know MySQL"
slug: postgres-quick-start-for-people-who-know-mysql
description: A quick start guide for PostgreSQL, especially if you're used to MySQL
date: 2012-08-26 11:41:58 +0200
kind: article
published: true
---

A long term MySQL user, I've recently taken to using PostgreSQL on a few projects. From a MySQL background, Postgres can seem a little confusing. I decided to write down exactly how the basic stuff works, alongside the way you might do it in MySQL for comparison.

You don't actually need to grok MySQL for this guide to be of use, but it'll probably help. I'm also using PostgreSQL 9.1, so older versions may not match up with my instructions.

<!-- more -->

### Installing PostgreSQL

#### On OS X

One of the tidiest ways to do this is using [homebrew](http://mxcl.github.com/homebrew/): `brew install postgres`

The homebrew post-install documentation will tell you to run `initdb /usr/local/var/postgres`. This is a quick way to get started, and if you run this as your normal user you'll be able to admin your Postgres server from this account, which is convenient for development. In production, you'd have a separate postgres user to do this.

So, run `initdb /usr/local/var/postgres` and once it has worked you can start the server. The homebrew instructions explain how to have the server auto-start, or you can run

    pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start

Once you're sure the server is up, type `psql postgres`. You should end up at a postgres terminal that looks like this 'postgres=#'. The hash # indicates that you're a superuser as far as postgres is concerned.

#### On Ubuntu

Super simple. A quick `sudo apt-get install postgresql` will get you going. This will create a `postgres` user and automatically create a new cluster, so you won't need to do an `initdb`.

To run administration commands on your server, you'll need to log in as the postgres user. Start by setting a password for this user:

    sudo passwd postgres

Now you can do a `su - postgres` to become this user and continue with the instructions below. You can make sure this is working by typing `psql postgres` and confirming that the prompt looks like this: 'postgres=#', which indicates you're a superuser.

### Creating a user and a database

Let's assume we have a typical scenario: a Rails application which needs a development and test DB. We'll also want a user specifically for this application. I'll explain how this would be done in MySQL, for comparison, and then PostgreSQL.

#### In MySQL

In MySQL, you'd probably do something like this:

    $ mysql -u root -p

    mysql> CREATE DATABASE blog_dev;
    Query OK, 1 row affected (0.03 sec)

    mysql> CREATE USER 'rails'@'localhost' IDENTIFIED BY 'railspassword';
    Query OK, 0 rows affected (0.11 sec)

    mysql> GRANT ALL ON blog_dev.* TO 'rails'@'localhost';
    Query OK, 0 rows affected (0.01 sec)

In MySQL, we've now got a user ('rails') who has full access to the 'blog_dev' database.

#### In PostgreSQL

Let's do this in PostgreSQL. We'll be using the terminal commands, so this will need to be done as your postgres superuser (on OSX, this might just be your normal user; on Linux, it's probably the *postgres* user):

    $ createuser rails --pwprompt
    Enter password for new role: <enter password>
    Enter it again: <enter password>
    Shall the new role be a superuser? (y/n) n
    Shall the new role be allowed to create databases? (y/n) y
    Shall the new role be allowed to create more new roles? (y/n) n

    $ createdb -O rails blog_dev

Now we've created a user ('rails') who is *not* a superuser, but does have permission to create databases. This user will be allowed to drop and create its own databases (a similar set of permissions to our MySQL example above). We then use the createdb command, creating a new database called *blog* and setting its owner to *rails*.

You'll now be able to use `psql` to log in as the new user and create another database:

    $ psql postgres rails

    postgres=> CREATE DATABASE blog_test;
    CREATE DATABASE

This is a suitable level of access for Rails, which will DROP and CREATE your databases for you. The next thing for you to do is just plug the username and password you just created into your application.

### What next?

Take a read through the [PostgreSQL 9.1 documentation](http://www.postgresql.org/docs/9.1/interactive/index.html) and, for tweaking a production PostgreSQL server, [this article](http://reinout.vanrees.org/weblog/2012/06/04/djangocon-postgres.html) is pretty good too.


