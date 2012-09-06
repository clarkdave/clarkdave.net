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

When you drop and recreate your application databases, hstore will be installed by default. If you can't drop them (say you're running in production, and have just decided to use hstore) you can still install hstore by hand, but you'll need to be a superuser to do it.
