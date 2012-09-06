---
title: "PostgreSQL error:  type 'hstore' does not exist"
created_at: 2012-09-06 12:39:29 +0200
kind: article
published: true
---

While playing around with PostgreSQL's hstore in Rails, I kept running into this error despite having run `CREATE EXTENSION hstore;`

Closer inspection of `CREATE EXTENSION` shows that it installs an extension into the current database. I ran it as my superuser (postgres) in the main postgres database, which meant Rails and its application database couldn't see it.

Rather than manually install hstore in the application databases, you can install hstore in the `template1` database. Postgres copies this database when creating a new one, so every new database will have hstore installed by default.

    psql template1 -c 'create extension hstore;'

When any of your application databases are created, hstore will now be installed by default. To install it in your existing databases, use psql as a superuser:

    psql application_db -c 'create extension hstore;'

These methods avoid giving your application user `superuser` permissions, which would be required if you wanted to install hstore as part of your migrations.