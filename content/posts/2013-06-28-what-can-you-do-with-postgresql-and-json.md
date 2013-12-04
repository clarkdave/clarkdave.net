---
title: "What can you do with PostgreSQL and JSON?"
description: An overview of querying JSON data in a PostgreSQL database, using the official JSON operators and functions
created_at: 2013-06-28 22:13:26 +0100
kind: article
published: true
---

PostgreSQL 9.2 added a native `JSON` data type, but didn't add much else. You've got three options if you actually want to do something with it:

1. Wait for PostgreSQL 9.3 (or use the beta)
2. Use the [plv8](https://code.google.com/p/plv8js/wiki/PLV8) extension. Valid option, but more DIY (you'll have to define your own functions)
3. Use the `json_enhancements` extension, which backports the new JSON functionality in 9.3 to 9.2

I wanted to use this stuff *now*, and I opted to go with option 3. I wrote a blog post which should help you get going if you want to go this route: [adding json_enhancements to PostgreSQL 9.2](/2013/06/adding-json-enhancements-to-postgresql-9-2).

So let's assume you're on either 9.3, or 9.2 with `json_enhancements`. What can you do? **Lots!** All the new JSON operators and functions are in the [9.3 documentation](http://www.postgresql.org/docs/9.3/static/functions-json.html), so I'm going to run through some of the more fun things you can do along with a real-world use case.

<!-- more -->

### Get started

Create a database to play about in:

    createdb json_test
    psql json_test

With some sample data:

    #!sql
    CREATE TABLE books ( id integer, data json );

    INSERT INTO books VALUES (1, 
      '{ "name": "Book the First", "author": { "first_name": "Bob", "last_name": "White" } }');
    INSERT INTO books VALUES (2, 
      '{ "name": "Book the Second", "author": { "first_name": "Charles", "last_name": "Xavier" } }');
    INSERT INTO books VALUES (3, 
      '{ "name": "Book the Third", "author": { "first_name": "Jim", "last_name": "Brown" } }');

#### Selecting

You can use the JSON operators to pull values out of JSON columns:
    
    #!sql
    SELECT id, data->>'name' AS name FROM books;

     id |      name
    ----+-----------------
      1 | Book the First
      2 | Book the Second
      3 | Book the Third

The `->` operator returns the original JSON type (which might be an object), whereas `->>` returns text. You can use the `->` to return a nested object and thus chain the operators:

    #!sql
    SELECT id, data->'author'->>'first_name' as author_first_name FROM books;

     id | author_first_name
    ----+-------------------
      1 | Bob
      2 | Charles
      3 | Jim

How cool is that?

#### Filtering

Of course, you can also select rows based on a value inside your JSON:

    #!sql
    SELECT * FROM books WHERE data->>'name' = 'Book the First';

     id |                                         data
    ----+---------------------------------------------------------------------------------------
      1 | '{ "name": "Book the First", "author": { "first_name": "Bob", "last_name": "White" } }'

You can also find rows based on the value of a nested JSON object:

    #!sql
    SELECT * FROM books WHERE data->'author'->>'first_name' = 'Charles';

     id |                                            data
    ----+---------------------------------------------------------------------------------------------
      2 | '{ "name": "Book the Second", "author": { "first_name": "Charles", "last_name": "Xavier" } }'

#### Indexing

You can add indexes on any of these using PostgreSQL's [expression indexes](http://www.postgresql.org/docs/9.2/static/indexes-expressional.html), which means you can even add unique constraints based on your nested JSON data:

    #!sql
    CREATE UNIQUE INDEX books_author_first_name ON books ((data->'author'->>'first_name'));

    INSERT INTO books VALUES (4, 
      '{ "name": "Book the Fourth", "author": { "first_name": "Charles", "last_name": "Davis" } }');
    ERROR:  duplicate key value violates unique constraint "books_author_first_name"
    DETAIL:  Key (((data -> 'author'::text) ->> 'first_name'::text))=(Charles) already exists.

Expression indexes are somewhat expensive to create, but once in place will make querying on any JSON property very fast.

### A real world example

OK, let's give this a go with a real life use case. Let's say we're tracking analytics, so we have an `events` table:

    #!sql
    CREATE TABLE events (
      name varchar(200),
      visitor_id varchar(200),
      properties json,
      browser json
    );

We're going to store events in this table, like pageviews. Each event has properties, which could be anything (e.g. current page) and also sends information about the browser (like OS, screen resolution, etc). Both of these are completely free form and could change over time (as we think of extra stuff to track).

Let's insert a couple of events:

    #!sql
    INSERT INTO events VALUES (
      'pageview', '1',
      '{ "page": "/" }',
      '{ "name": "Chrome", "os": "Mac", "resolution": { "x": 1440, "y": 900 } }'
    );
    INSERT INTO events VALUES (
      'pageview', '2',
      '{ "page": "/" }',
      '{ "name": "Firefox", "os": "Windows", "resolution": { "x": 1920, "y": 1200 } }'
    );
    INSERT INTO events VALUES (
      'pageview', '1',
      '{ "page": "/account" }',
      '{ "name": "Chrome", "os": "Mac", "resolution": { "x": 1440, "y": 900 } }'
    );
    INSERT INTO events VALUES (
      'purchase', '5',
      '{ "amount": 10 }',
      '{ "name": "Firefox", "os": "Windows", "resolution": { "x": 1024, "y": 768 } }'
    );
    INSERT INTO events VALUES (
      'purchase', '15',
      '{ "amount": 200 }',
      '{ "name": "Firefox", "os": "Windows", "resolution": { "x": 1280, "y": 800 } }'
    );
    INSERT INTO events VALUES (
      'purchase', '15',
      '{ "amount": 500 }',
      '{ "name": "Firefox", "os": "Windows", "resolution": { "x": 1280, "y": 800 } }'
    );

Hm, this is starting to remind me of MongoDB!

#### Collect some stats

Using the JSON operators, combined with traditional PostgreSQL [aggregate functions](http://www.postgresql.org/docs/9.2/static/functions-aggregate.html), we can pull out whatever we want. You have the full might of an RDBMS at your disposal.

**Browser usage?**

    #!sql
    SELECT browser->>'name' AS browser, count(browser)
    FROM events
    GROUP BY browser->>'name';

     browser | count
    ---------+-------
     Firefox |     3
     Chrome  |     2

**Total revenue per visitor?**

    #!sql
    SELECT visitor_id, SUM(CAST(properties->>'amount' AS integer)) AS total 
    FROM events 
    WHERE CAST(properties->>'amount' AS integer) > 0 
    GROUP BY visitor_id;

     visitor_id | total
    ------------+-------
     5          |    10
     15         |   700

**Average screen resolution?**

    #!sql
    SELECT AVG(CAST(browser->'resolution'->>'x' AS integer)) AS width,
      AVG(CAST(browser->'resolution'->>'y' AS integer)) AS height
    FROM events;

             width         |        height
    -----------------------+----------------------
     1397.3333333333333333 | 894.6666666666666667

You've probably got the idea, so I'll leave it here.

### Is this better than MongoDB?

Haha, just kidding. I'm not going to answer that!

There's a whole lot of other JSON operators and functions I didn't cover here, for example to work with JSON arrays too. I recommend you check out the [official documentation](http://www.postgresql.org/docs/9.3/static/functions-json.html) to see what other cool stuff is possible.