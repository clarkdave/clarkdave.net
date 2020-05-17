---
title: "Munin and PostgreSQL monitoring"
slug: munin-and-postgresql-monitoring
date: 2012-11-13 20:46:01 +0100
kind: article
published: true
---

I ran into a little hiccup when trying to configure [Munin](https://munin-monitoring.org/) to monitor PostgreSQL. After linking the 'postgres\_' plugins and restarting munin-node, no Postgres stats were appearing and I was seeing error messages in the munin-node.log like this:

    Service 'postgres_size_ALL' exited with status 1/0
    Service 'postgres_locks_ALL' exited with status 1/0
    Service 'postgres_cache_ALL' exited with status 1/0

Not very helpful but, it turns out, easy to fix. The Munin Postgres plugins use Perl and the `DBD::Pg` module to talk to your PostgreSQL database so if either of these are missing, you'll get these errors.

The solution is to install the `DBD::Pg` module from CPAN. If you're using Chef, add the `perl` cookbook and then run `cpan_module 'DBD::Pg` in a recipe somewhere.
