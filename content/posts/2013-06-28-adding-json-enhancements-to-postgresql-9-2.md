---
title: "Adding json_enhancements to PostgreSQL 9.2"
description: How to install json_enhancements into PostgreSQL 9.2 on Mac OSX and others
created_at: 2013-06-28 17:38:06 +0100
kind: article
published: true
---

If you keep up with PostgreSQL developments there's no way you've missed the `JSON` datatype introduced in `9.2`, and the upcoming JSON functions in `9.3`. The biggest change here is that in 9.3 it'll be possible to query your JSON columns without needing to use [plv8](https://code.google.com/p/plv8js/wiki/PLV8), which embeds V8 into Postgres.

That said, the JSON functions in 9.3 have been [backported](http://www.pgxn.org/dist/json_enhancements/doc/json_enhancements.html) to 9.2, and can be used *right now* with 9.2. Before deciding if this is for you, you'll probably want to play around with it on your development machine. If so, this guide might help!

<!-- more -->

### Get PostgreSQL 9.2

If you haven't already.

If you're on a Mac, and using [Postgres.app](http://postgresapp.com/), you may have to figure out how to install extensions yourself, and in fact the extension may not build at all. I recommend using the compiled version of PostgreSQL via Homebrew.

### Build json_enhancements

Don't bother trying to install this using the `pgxnclient` -- it'll probably fail (but feel free to try). Instead, we'll build it from scratch.

First up, make sure you have all the tools you need to compile (`make` and friends, XCode on a Mac - if you're already using Homebrew successfully, you're probably good to go). 

Now clone the `json_enhancements` git repo and build it:

    $ git clone https://bitbucket.org/IVC-Inc/json_enhancements
    $ cd json_enhancements
    $ make

If you hit an error like `ld: can't link with bundle (MH_BUNDLE) only dylibs (MH_DYLIB) for architecture x86_64`, this is probably because of some weirdness regarding the `hstore` library on OSX. This extension depends on this library to provide a couple of functions for converting `hstore` values into `JSON`.

If you don't need these functions, you can add a variable into the Makefile to disable building against `hstore`. Add this to the top of the `Makefile`:

    NOHSTORE=1

Before you run make again, remove the built files, to avoid any weirdness:

    $ rm json_enhancements.control json_enhancements.so sql/json_enhancements.sql
    $ make

If there are no errors, follow it up with:

    $ make install

*Note: you may need to run `sudo make install`, depending on how you installed Postgres.*

### Install the json_enhancements extension

You should now be able to install this extension like any other. The easiest way to do this is, as the Postgres superuser (you, probably, if you installed via Homebrew), run:

    $ psql template1 -c 'create extension json_enhancements;'
    CREATE EXTENSION

This will install the extension into the `template1` database, which is cloned whenever a new DB is created (so every new DB you create will have the extension installed).

If you have an existing DB you'd like to add the extension to, do:

    $ psql db_name -c 'create extension json_enhancements;'

If, when installing the extension here, you get an error about not having `hstore` installed, you probably `make installed` before you added `HSTORE=1` to the Makefile. Nuke the extension files from PostgreSQL, do a fresh `git clone` and start again from above, e.g:

    $ rm /usr/local/Cellar/postgresql/9.2.4/lib/json_enhancements.so /usr/local/Cellar/postgresql/9.2.4/share/postgresql/extension/json_enhancements.control /usr/local/Cellar/postgresql/9.2.4/share/postgresql/extension/json_enhancements--1.0.0.sql

### Check it works

See my post: [What can you do with PostgreSQL and JSON?](/2013/06/what-can-you-do-with-postgresql-and-json)