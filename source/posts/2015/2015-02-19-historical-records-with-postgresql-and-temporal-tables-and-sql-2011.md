---
title: "Historical records with PostgreSQL, temporal tables and SQL:2011"
slug: historical-records-with-postgresql-and-temporal-tables-and-sql-2011
date: 2015-02-19 09:16:00 +0000
kind: article
published: true
---

Sometimes you need to find out what a record looked like at some point in the past. This is known as the [Slowly Changing Dimension](https://en.wikipedia.org/wiki/Slowly_changing_dimension) problem. Most database models - by design - don't keep the history of a record when it's updated. But there are plenty of reasons why you might need to do this, such as:

* audit/security purposes
* implementing an undo functionality
* showing a model's change over time for stats or comparison

There are a few ways to do this in PostgreSQL, but this article is going to focus on the implementation provided by the [SQL:2011](https://en.wikipedia.org/wiki/SQL:2011) standard, which added support for temporal databases. It's also going to focus on actually querying that historical data, with some real-life use cases.

PostgreSQL doesn't support these features natively, but this [temporal tables](https://github.com/arkhipov/temporal_tables) extension does the trick. This requires PostgreSQL 9.2 or higher, as that was the first version with support for a timestamp range data type.

Before you dig in, it's important to note that this extension does not provide **complete** support for the 2011 standard. Specifically, there is no support for the new syntaxes provided for querying across historical tables, such as the `AS OF SYSTEM TIME` keyword.

These are generally conveniences though - the `temporal tables` extension takes care of the updating, and you'll at least be adopting a standard used by other databases, as opposed to rolling your own solution or using something application-specific.

<!-- more -->

### Install the temporal tables extension

Available here: [https://github.com/arkhipov/temporal_tables](https://github.com/arkhipov/temporal_tables)

Make sure you have all the tools you need to build & compile from source (make, XCode, etc) and then it should be as simple as:

    $ git clone https://github.com/arkhipov/temporal_tables
    $ cd temporal_tables
    $ make
    $ make installcheck
    $ make install

If you have any issues, follow the [installation steps](https://github.com/arkhipov/temporal_tables) on the extension repo.

### Get started

I find the best way to learn something is with a real-world example, so let's create a `subscriptions` table. Our subscriptions will have a few fields, and will generally undergo multiple state changes throughout their lifecycle.

The use cases we'll cover:

- what state was a particular subscription on `X` date
- which subscriptions were in each state on `X` date, or across a range of dates
- which subscriptions changed from state `X -> Y` on `Z` date, or across a range of dates

First up, let's create a database to play about with:

    $ createdb temporal_test
    $ psql temporal_test

Enable the extension like so:

    temporal_test=# CREATE EXTENSION temporal_tables;

Next, we'll create a subscriptions table:

``` sql
CREATE TABLE subscriptions
(
  id SERIAL PRIMARY KEY,
  state text NOT NULL CHECK (state IN ('trial', 'expired', 'active', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT current_timestamp
);
```

For the temporal functions to work, we also need to add a column to this table which stores the "system period". This is a range showing when this record is valid from - to. You can name it however you want; the extension's convention is to call it `sys_period`, so we'll go with that.

``` sql
ALTER TABLE subscriptions
  ADD COLUMN sys_period tstzrange NOT NULL DEFAULT tstzrange(current_timestamp, null);
```

Note that the type here is a "timestamp with time zone range", which was only introduced in PostgreSQL 9.2, hence the version requirement.

#### Create the history table

The history table can be a full or partial copy of the original table. Additional discourse on the options available here (including `INHERITS`) can be found towards the end of this post, but for now we'll copy everything:

``` sql
CREATE TABLE subscriptions_history (LIKE subscriptions INCLUDING INDEXES);
```

Finally, we need to add the `versioning_trigger` to our original table. This will ensure that records are copied in to the history table as needed:

``` sql
CREATE TRIGGER versioning_trigger
BEFORE INSERT OR UPDATE OR DELETE ON subscriptions
FOR EACH ROW EXECUTE PROCEDURE versioning(
  'sys_period', 'subscriptions_history', true
);
```

If you changed the `sys_period` column to something else, make sure to adjust the SQL above.

### Trying it out

It's actually kind of weird to test this, because we're working with system time. That is, in order to test it with data "in the past" (which we don't have yet) we need to manually add in some history for us to play with.

Let's start by inserting some subscriptions:

``` sql
INSERT INTO subscriptions (state, created_at) VALUES ('cancelled', '2015-01-05 12:00:00');
INSERT INTO subscriptions (state, created_at) VALUES ('active', '2015-01-10 12:00:00');
```

You'll notice that we've set the `created_at` values in the past. That's because we are going to "fill in" the history between then and now, so we can test our history table.

If you query the `subscriptions` table now, you should see your rows and their `sys_period` should be populated automatically. They'll look something like this:

    ["2015-02-19 10:58:24.305634+00",)

This was calculated and filled in automatically, and shows that this record is valid from a few moments ago to "infinity".

The mismatched brackets may be causing you some discomfort, but they actually tell you if the upper/lower bounds are inclusive or exclusive. With the range above, the lower bound is `[` and thus inclusive. The upper bound (infinity in this case) is `)` which means it is exclusive.

#### Filling in our history

Right now our subscriptions_history table will be empty, because we've only inserted rows. We're going to manually enter some records in this table now so we can play around. Obviously, in a production environment, it's unlikely you would ever want to do this, except perhaps to backfill at the beginning. In fact, its a good idea to lock your history tables down so that they can't be written to except by the trigger.

This first history entry shows that the subscription changed from `trial` to something else on 2015-01-15:

``` sql
INSERT INTO subscriptions_history (id, state, created_at, sys_period)
  VALUES (1, 'trial', '2015-01-05 12:00:00',
    tstzrange('2015-01-05 12:00:00', '2015-01-15 15:00:00')
  );
```

The next entry shows that it changed from `active` on 2015-02-05. This is the most recent change, so its upper bound has to match the lower bound of the subscription as it is in the `subscriptions` table or there'd be a weird gap.

``` sql
INSERT INTO subscriptions_history (id, state, created_at, sys_period)
  VALUES (1, 'active', '2015-01-05 12:00:00',
    tstzrange('2015-01-15 15:00:00', (SELECT lower(sys_period) FROM subscriptions WHERE id = 1))
  );
```

Finally, we'll add one entry for the second subscription, which indicates it started life as `trial` and remained that way until just now, when it became active.

``` sql
INSERT INTO subscriptions_history (id, state, created_at, sys_period)
  VALUES (2, 'trial', '2015-01-10 12:00:00',
    tstzrange('2015-01-10 15:00:00', (SELECT lower(sys_period) FROM subscriptions WHERE id = 2))
  );
```

In all of the above inserts, we're providing ranges with an inclusive `[` lower bound, and exclusive `)` upper bound. This is essential (we'll see why in a moment) and mimics the functionality of the versioning trigger. **Note:** by default, without specifying the inclusive/exclusive characters, Postgres will create inclusive lower and exclusive upper bounds.

You should now have a `subscriptions_history` table looking something like this:

     id | state  |       created_at       |                         sys_period
    ----+--------+------------------------+------------------------------------------------------------
      1 | trial  | 2015-01-05 12:00:00+00 | ["2015-01-05 12:00:00+00","2015-01-15 15:00:00+00")
      1 | active | 2015-01-05 12:00:00+00 | ["2015-01-15 15:00:00+00","2015-02-19 18:21:22.548028+00")
      2 | trial  | 2015-01-10 12:00:00+00 | ["2015-01-10 15:00:00+00","2015-02-19 18:21:22.992536+00")

What we can infer from this table is:

- subscription #1 had the 'trial' state between 2015-01-05 -> 2015-01-15
- then it had the 'active' state between 2015-01-15 -> now
- subscription #2 was trialing from its created_at -> now

Now we can try out some simple historical queries!

### What state was a particular subscription on `X` date

As I mentioned at the beginning, neither PostgreSQL or the temporal extension support the SQL:2011 querying syntax, such as `AS OF SYSTEM TIME`.

If it did, we'd be able to do this:

``` sql
SELECT * FROM subscriptions AS OF SYSTEM TIME '2014-01-10' WHERE id = 1;
```

But it's not all bad news. We can still construct a query to do this manually, and because we're otherwise still using the SQL:2011 standard, if PostgreSQL or an extension ever adds support for the correct syntax, we can just start using that - there's a good chance our database structure can stay as-is.

So here's a query to get the subscription on a particular date, without the new fancy syntax:

``` sql
  SELECT id, state FROM subscriptions
    WHERE id = 1 AND sys_period @> '2015-01-10'::timestamptz
UNION ALL
  SELECT id, state from subscriptions_history
    WHERE id = 1 AND sys_period @> '2015-01-10'::timestamptz;
```

The result:

     id | state
    ----+--------
      1 | active

I know - it's not as pleasant to look at (or write), but it works. The `@>` is the 'containment' operator which will find records whose sys_period contain the given timestamp.

You might now be thinking: "OK, but what if my given date happens to be the upper boundary of one history record, and the lower boundary of another?"

When this happens it'll always return the most recent record. That's because our sys_periods have an inclusive lower bound and exclusive upper bound. You can try it now:

``` sql
SELECT * from subscriptions_history
  WHERE id = 1 AND sys_period @> '2015-01-15 15:00:00'::timestamptz;
```

This exact timestamp appears in two history records, but you'll only get the most recent one back. The `@>` operator handily takes this into account for you.

### How many subscriptions were in each state on `X` date

This is a similar query to the above, but with some aggregation thrown in:

``` sql
  SELECT state, count(*) FROM subscriptions
    WHERE lower(sys_period) <= '2015-01-10'::timestamptz
    GROUP BY state
UNION ALL
  SELECT state, count(*) from subscriptions_history
    WHERE sys_period @> '2015-01-10'::timestamptz
    GROUP BY state;
```

Result:

    state | count
    -------+-------
     trial |     1

#### Across a date range

With a bit more effort we can get a count of subscription states across a date range too. The key is to stick the `subscriptions` and `subscriptions_history` tables together and then filter them based on their system period.

``` sql
WITH dates AS (
  SELECT * FROM generate_series('2015-01-10'::timestamptz, '2015-01-20', '1 day') date
),
subscriptions_with_history AS (
    SELECT state, sys_period FROM subscriptions
  UNION ALL
    SELECT state, sys_period from subscriptions_history
)
SELECT date,
  count(trials.*) as trial,
  count(actives.*) as active,
  count(cancels.*) as cancelled
FROM dates
LEFT JOIN subscriptions_with_history trials
  ON trials.state = 'trial' AND trials.sys_period @> dates.date::timestamptz
LEFT JOIN subscriptions_with_history actives
  ON actives.state = 'active' AND actives.sys_period @> dates.date::timestamptz
LEFT JOIN subscriptions_with_history cancels
  ON cancels.state = 'cancelled' AND cancels.sys_period @> dates.date::timestamptz
GROUP BY date
ORDER BY date;
```

Result:

              date          | trial | active | cancelled
    ------------------------+-------+--------+-----------
     2015-01-10 00:00:00+00 |     1 |      0 |         0
     2015-01-11 00:00:00+00 |     2 |      0 |         0
     2015-01-12 00:00:00+00 |     2 |      0 |         0
     2015-01-13 00:00:00+00 |     2 |      0 |         0
     2015-01-14 00:00:00+00 |     2 |      0 |         0
     2015-01-15 00:00:00+00 |     2 |      0 |         0
     2015-01-16 00:00:00+00 |     1 |      1 |         0
     2015-01-17 00:00:00+00 |     1 |      1 |         0
     2015-01-18 00:00:00+00 |     1 |      1 |         0
     2015-01-19 00:00:00+00 |     1 |      1 |         0
     2015-01-20 00:00:00+00 |     1 |      1 |         0

Note that this query works on days, specifically dates at midnight, e.g. `2015-01-10 00:00:00`. This means you might get some unexpected results if you have history records whose lower bound is something like `2015-01-10 03:00:00` - they won't be included for `2015-01-10`, but may be included for `2015-01-11`.

You could potentially use the overlap operator `&&` to instead match on subscription records which overlap the start and end of each "date", e.g. like this:

``` sql
WITH dates AS (
  SELECT start, lead(start, 1, '2015-01-20') OVER (ORDER BY start) AS end
  FROM generate_series('2015-01-10'::timestamptz, '2015-01-19', '1 day') start
)
--- stuff
LEFT JOIN subscriptions_with_history trials
  ON trials.state = 'trial'
    AND tstzrange(dates.start, dates.end) && trials.sys_period
```

Although this works, you now have a different problem: you'll count the same subscription multiple times. This is because there'll be one record whose period ends at, e.g. `2015-01-15 15:00:00` and another whose period begins at `2015-01-15 15:00:00`, Which record should be counted? Technically, the subscription was in two states on the same day.

You could have some logic in place to get rid of duplicates, e.g. pick the most recent record in the case of multiples, but it's probably easier to stick with the `@>` operator which can only ever return one record for a given timestamp.

### How many subscriptions changed from state X -> Y on Z date

To start with, let's say we want a list of subscriptions which converted from `trial -> active` in 2015-01.

Specifically, what we're looking for is subscriptions which, for a particular month, have been both `trial` and `active` (we're making an assumption for simplicity here that you can't go backwards from `active -> trial`).

This is fairly easy to figure out using PostgreSQL's [overlap operator](http://www.postgresql.org/docs/9.2/static/functions-range.html), `&&` and a liberal dose of [CTEs](http://www.postgresql.org/docs/9.2/static/queries-with.html). For 2015-01, this would be:

``` sql
WITH timeboxed_subscriptions AS (
    SELECT * FROM subscriptions
      WHERE tstzrange('[2015-01-01, 2015-02-01)') && sys_period
  UNION ALL
    SELECT * from subscriptions_history
      WHERE tstzrange('[2015-01-01, 2015-02-01)') && sys_period
),
trial_subscriptions AS (
  SELECT id FROM timeboxed_subscriptions s
    WHERE s.state = 'trial'
),
active_subscriptions AS (
  SELECT id FROM timeboxed_subscriptions s
    WHERE s.state = 'active'
),
converted_subscriptions AS (
  SELECT DISTINCT ON (id) *
  FROM timeboxed_subscriptions s
  WHERE
    EXISTS(SELECT * FROM trial_subscriptions WHERE id = s.id)
    AND EXISTS(SELECT * FROM active_subscriptions WHERE id = s.id)
)
SELECT count(*)
FROM converted_subscriptions;
```

Result:

     count
    -------
         1

#### Across a date range

We're using months in this example, but the resolution could be anything:

``` sql
WITH dates AS (
  SELECT start, lead(start, 1, '2015-03-01') OVER (ORDER BY start) AS end
  FROM generate_series('2014-11-01'::timestamptz, '2015-02-01', '1 month') start
),
timeboxed_subscriptions AS (
    SELECT * FROM subscriptions
      WHERE tstzrange('[2014-11-01, 2015-02-01)') && sys_period
  UNION ALL
    SELECT * from subscriptions_history
      WHERE tstzrange('[2014-11-01, 2015-02-01)') && sys_period
),
trial_subscriptions AS (
  SELECT id FROM timeboxed_subscriptions s
    WHERE s.state = 'trial'
),
active_subscriptions AS (
  SELECT id FROM timeboxed_subscriptions s
    WHERE s.state = 'active'
),
converted_subscriptions AS (
  SELECT DISTINCT ON (id) *
  FROM timeboxed_subscriptions s
  WHERE
    EXISTS(SELECT * FROM trial_subscriptions WHERE id = s.id)
    AND EXISTS(SELECT * FROM active_subscriptions WHERE id = s.id)
)
SELECT dates.start, count(s.*)
FROM dates
LEFT JOIN converted_subscriptions s
  ON tstzrange(dates.start, dates.end) && sys_period
GROUP BY dates.start
ORDER BY dates.start;
```

Result:

             start          | count
    ------------------------+-------
     2014-11-01 00:00:00+00 |     0
     2014-12-01 00:00:00+00 |     0
     2015-01-01 00:00:00+00 |     1
     2015-02-01 00:00:00+00 |     0

The additional step here is generating a `months` sequence and joining to it. However, because we're using ranges and the overlap operator, our months sequence needs to have `start` and `end` fields. We generate the `end` date for each month using the handy `lead` window function, which - for each "row" - gets the next one in the sequence, or uses a default if it's at the end of the sequence.

### Creating the history table

#### Duplication

At the beginning of this post we created the `subscriptions_history` table using the `LIKE` clause:

``` sql
CREATE TABLE subscriptions_history (LIKE subscriptions INCLUDING INDEXES);
```

This will create a complete but **static** copy of the `subscriptions` table, including any indexes it might have.

* Both tables are completely separate, which simplifies querying and updating
* You have the option to only store the history of certain columns, by excluding the ones you don't care about

**Caveats**

It's up to you to keep the history table in sync using your database migration tool of choice, or perhaps with some creative use of [event triggers](http://www.postgresql.org/docs/9.3/static/sql-createeventtrigger.html), which can hook into DDL changes (9.3+ only).

In particular, if you add new columns (or alter existing columns) with a default value to the source table, you'll need to make sure these defaults are also added to the history table, or you'll end up grabbing records from the history table which have unexpected NULL values.

#### Inheritance

Your other option for the history table is using [table inheritance](http://www.postgresql.org/docs/9.2/static/ddl-inherit.html). For example:

``` sql
CREATE TABLE subscriptions_history () INHERITS (subscriptions);
```

This has some considerable advantages:

* You no longer need to worry about keeping both tables in sync. DDL updates to the parent table will be applied automatically to the history table
* Because both tables are linked, new columns with default values will be propagated to the history table

**Caveats**

By default, queries to the parent table will operate on the parent and all child tables, which would break simple queries like `SELECT * FROM subscriptions WHERE id = 1` and be **especially catastrophic** with a query like `UPDATE subscriptions SET state = 'active' WHERE id = 2` (it would clobber the entire history table!)

You can disable this for the whole database by setting `sql_inheritance = false`, but [this is deprecated](http://www.postgresql.org/docs/9.2/static/runtime-config-compatible.html#GUC-SQL-INHERITANCE).

You can, alternatively, disable it for individually queries like so: `SELECT * FROM ONLY ...` or `UPDATE ONLY ...`. This might be a reasonable trade-off considering the advantages, especially if you're using a framework which can reliably support these kind of queries.

#### Indexing

If you'll be doing a lot of historical queries you'll most likely want to index the `sys_period` columns. You can do this with a `GIST` index which will speed up all the range functions such as `@>` and `&&`:

``` sql
CREATE INDEX ON subscriptions USING gist (sys_period);
CREATE INDEX ON subscriptions_history USING gist (sys_period);
```

### Wrap up

Hopefully you've found something in here useful! There are plenty of other approaches to this problem, all with varying degrees of complexity and flexibility. An interesting option might be to have a 'schemaless' history table which logs change deltas as a JSON blob. But that's another post...!

Temporal tables are, of course, not exactly new, but using them with PostgreSQL still seems to be somewhat of a niche topic. If you have any other insights or corrections, please comment below!

