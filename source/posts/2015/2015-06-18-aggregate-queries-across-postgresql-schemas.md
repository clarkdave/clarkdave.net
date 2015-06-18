---
title: Aggregate queries across PostgreSQL schemas
slug: aggregate-queries-across-postgresql-schemas
date: 2015-06-18 06:28:39 +0000
tags: databases postgresql
published: false
---

[Schemas](http://www.postgresql.org/docs/9.4/static/ddl-schemas.html) are a useful feature in PostgreSQL which can be used for the design of a multi-tenancy system. Using schemas you could, for example, have one schema for each user of your application. Inside this schema the user has their own copy of all your tables, views etc, and the data within them is completely separate from any other schemas.

Conceptually, this approach is very similar to having a separate database per user, but in fact all schemas live inside the same database and can therefore be queried across within the same session. This also simplifies using them with your application, as all schemas can use the same database connection details.

<!-- more -->

### The use case

Let's suppose we're building an ecommerce platform. People will sign up to our platform and then create their own ecommerce stores which are hosted by us. We've decided to create a schema for each person that signs up. Inside their schema will live all their customers, inventory, etc.

So far so good. If 100 people sign up we'll have 100 schemas - we'll name them `user_1`, `user_2`, etc. We can easily query within a particular schema by either setting the search path, or qualifying our queries with schemas, e.g.

``` sql
-- set the search path
SET search_path TO 'user_1';
SELECT * FROM customers WHERE customer_id = 5;

-- or specify the schema
SELECT * FROM user_3.customers WHERE customer_id = 5;
```

### The problem

There'll most likely come a point where you want to take advantage of the fact that all the schemas live inside the same database, and query across them. If you were using a shared table multi-tenacy, this would be as simple as:

``` sql
SELECT count(*) FROM customers;
```

This sort of query is not as simple with schemas, but there are still plenty of methods available to you.

I've encounted a lot of different strategies to approach this problem, and I'll explain various potential options in this article. Some approaches will be more suitable for your data than others. In brief:

* The application-generated union query
* The union view
* The aggregate table
* Dynamic SQL

### The application generated union query

First up, a notice: large `union` queries can put immense pressure on your database. In my experience, using union queries to stitch tables from schemas together is only suitable if you have a relatively low number of schemas. The exact number will depend on your database hardware and server settings. As a rule of thumb, if you have more than 500 you'll probably start encountering issues (`max_locks_per_transaction` will need to be unusually high, etc). If you get to this point, consider using a non-union approach, such as those described later on in the article.

The application-generated union query is exactly as it sounds: you generate your SQL within your application and have it create a `UNION ALL` query which returns the all rows from a particular table across all schemas.

If you have a small, fixed number of schemas this could be written by hand, e.g.

``` sql
SELECT count(*) FROM (
    SELECT * FROM user_1.customers
  UNION ALL
    SELECT * FROM user_2.customers
) c;

-- or, using a CTE

WITH all_customers AS (
    SELECT * FROM user_1.customers
  UNION ALL
    SELECT * FROM user_2.customers
)
SELECT count(*) FROM all_customers;
```

If you have a larger number, you might instead generate this query in your application. For example, to do this in Rails using the [postgres_ext](https://github.com/dockyard/postgres_ext) gem, which adds CTE support to ActiveRecord:

``` ruby
Customer.from_cte('all_customers',
  User.pluck('id').
    map { |id| "SELECT * FROM user_#{id}.customers" }.
    join(' UNION ALL '),
).count('*')
```

This will generate a query similar to this:

``` sql
WITH "all_customers" AS (SELECT * FROM user_1.customers UNION ALL SELECT * FROM user_2.customers ... )
SELECT COUNT(*) FROM all_customers;
```

If you have a small number of schemas, and don't need to reliably run these kind of queries outside of your application, this approach is simple and works well.

### The union view

If you need to run some ad-hoc queries against your database by hand. To facilitate this, you can create a view to work with. This view could be created within your code:

``` ruby
def create_customers_view
  statement =
    User.pluck('id').
      reject { |id| [174].include?(id) }.
      map { |id| "SELECT * FROM user_#{id}.customers" }.
      join(' UNION ALL ')
  ActiveRecord::Base.connection.execute(<<-SQL)
    CREATE OR REPLACE VIEW all_customers AS #{statement}
  SQL
end
```

Or you could generate it dynamically with a PL/pgSQL function:

``` sql
CREATE OR REPLACE FUNCTION refresh_union_view(table_name text) RETURNS void AS $$
DECLARE
  schema RECORD;
  result RECORD;
  sql TEXT := '';
BEGIN
  FOR schema IN EXECUTE
    format(
      'SELECT schema_name FROM information_schema.schemata WHERE left(schema_name, 4) = %L',
      'user'
    )
  LOOP
    sql := sql || format('SELECT * FROM %I.%I UNION ALL ', schema.schema_name, table_name);
  END LOOP;

  EXECUTE
    format('CREATE OR REPLACE VIEW %I AS ', 'all_' || table_name) || left(sql, -11);
END
$$ LANGUAGE plpgsql;
```

This function gets a list of all user schemas we have (in this example, all our application schemas start with `user_`), then uses this to construct the `UNION ALL` query. It then dynamically executes a `CREATE OR REPLACE VIEW` function. You'd call it like so:

``` sql
SELECT refresh_union_view('customers');
SELECT refresh_union_view('orders');
```

The advantage of using a function here is that you can now refresh this view from anywhere, not just your application. However you create the view, once you have it querying across all your schemas is now as simple as:

``` sql
SELECT count(*) FROM all_customers;
```

Using a view this way is a suitable method for smaller databases. The most significant penalty imposed with this strategy is that the view must be run every time it's used. If you have hundreds of schemas and a lot of data, this can take a while. It's also not possible to use indexes on this view, which could hinder large queries.

Note: if you're using PostgreSQL 9.3+, you can opt to use a materialized view instead. This removes the performance penalty when using the view (as it doesn't run the query again each time). However, for databases with lots of schemas the bottleneck is usually the `UNION ALL` query itself, so a materialized view won't help if this is the case.

### The aggregate table

This approach is similar to using a view, but involves creating an actual table and populating it with data in a way that won't cause PostgreSQL to cry with a gigantic `UNION ALL` query.

The basic idea is as follows. For each "aggregate table":

* create the aggregate table, e.g. `all_customers`
* loop through all schemas
* for each schema, select all rows in the target table and insert them into the aggregate table
* add any indexes you might need for aggregate queries

You can do all of the above in your application, but it's relatively straightforward to use a PL/pgSQL function. Here's a function to do this, which assumes your schemas are named as `user_1`, `user_2`, etc. It also adds a `schema_name` field to each "aggregate table", which can be handy for complicated aggregate queries later.

```sql
CREATE OR REPLACE FUNCTION refresh_aggregate_table(table_name text) RETURNS void AS $$
DECLARE
  schema RECORD;
  result RECORD;
  sql TEXT := '';
  aggregate_table_name TEXT := 'all_' || table_name;
  i INTEGER;
  created boolean := false;
BEGIN
  EXECUTE format('DROP TABLE IF EXISTS %I', aggregate_table_name);

  FOR schema IN EXECUTE
    format(
      'SELECT schema_name FROM information_schema.schemata WHERE left(schema_name, 4) = %L',
      'user'
    )
  LOOP
    IF NOT created THEN
      -- Create the aggregate table if we haven't already
      EXECUTE format(
        'CREATE TABLE %I (LIKE %I.%I)',
        aggregate_table_name,
        schema.schema_name, table_name
      );
      -- Add a special `schema_name` column, which we'll populate with the name of the schema
      -- each row originated from
      EXECUTE format(
        'ALTER TABLE %I ADD COLUMN schema_name text', aggregate_table_name
      );
      created := true;
    END IF;

    -- Finally, we'll select everything from this schema's target table, plus the schema's name,
    -- and insert them into our new aggregate table
    EXECUTE format(
      'INSERT INTO %I (SELECT *, ''%s'' AS schema_name FROM %I.%I)',
      aggregate_table_name,
      schema.schema_name,
      schema.schema_name, table_name
    );
  END LOOP;

  EXECUTE
    format('CREATE INDEX ON %I (schema_name)', aggregate_table_name);

  -- The aggregate table won't carry over any of the indexes the schema tables have, so if those
  -- are important for your aggregate queries, make sure to add them here

  -- There are lots of ways to do this: you could hardcode the indexes in the function, look them
  -- up on-the-fly for the target table, or do something like the below which just checks if the
  -- target table has a `user_id` column and adds an index if so

  EXECUTE format(
    'SELECT 1 FROM information_schema.columns WHERE table_name = ''%s'' AND column_name = ''user_id''',
    aggregate_table_name
  );
  GET DIAGNOSTICS i = ROW_COUNT;

  IF i THEN
    EXECUTE
      format('CREATE INDEX ON %I (user_id)', aggregate_table_name);
  END IF;
END
$$ LANGUAGE plpgsql;
SQL
```

Now you can simply run the `refresh_aggregate_table()` function to recreate an aggregate table and fill it with the latest data from all schemas:

```sql
SELECT refresh_aggregate_table('customers');
```

This can be a bit slower than the `UNION ALL` approach, because it has to run one insert and select operation for each schema, but it has numerous advantages:

* it's a more scalable solution for tables with a large number of schemas (compared to the union strategy)
* it won't error if a schema is deleted - it'll just return stale data until it's updated
* you can add indexes to the aggregate table

### How to keep the aggregate table or view up-to-date

Whether you use a view or an aggregate table, you'll need to keep it up to date somehow or it'll start returning stale data. Particularly for a view, if you don't update it when you've deleted a schema, the view will error when you use it (it'll try to query a schema that no longer exists).

#### Refresh the view in your application

For example, if you were using Rails you might add the `create_customers_view` method above to the relevant callbacks in your `User` model:

``` ruby
after_create :refresh_aggregate_tables
after_destroy :refresh_aggregate_tables

def refresh_aggregate_tables
  self.class.connection.execute("SELECT refresh_aggregate_table('customers')")
  self.class.connection.execute("SELECT refresh_aggregate_table('orders')")
end
```

If you have a large number of schemas, any method you use to create the view or aggregate table will be relatively slow. For this reason it's inadvisable to do the update within the same transaction. Instead, you could schedule a background worker to do the update. For example, with Rails and ActiveJob:

``` ruby
def refresh_aggregate_tables
  RefreshAggregateTablesJob.perform_later
end
```

#### Use a database trigger

A more generic option involves a trigger on the `users` table which will refresh the aggregate table whenever a record is inserted/deleted. You'll need to create a "meta" refresh function, which will run the refresh function for all of your required aggregate tables:

``` sql
CREATE OR REPLACE FUNCTION refresh_aggregate_tables() RETURNS trigger AS $$
BEGIN
  EXECUTE refresh_aggregate_table('customers');
  EXECUTE refresh_aggregate_table('orders');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;
```

Now for the trigger:

``` sql
CREATE TRIGGER refresh_aggregate_tables
  BEFORE INSERT OR DELETE ON users
  EXECUTE PROCEDURE refresh_aggregate_tables();
```

This will guarantee that a new or deleted user will refresh your aggregate table or view. However, triggers execute in the same transaction, and as mentioned above, the refresh operation can be extremely slow. For that reason, I'd advise against the trigger approach for most use cases.

Neither of the above two methods will trigger updates to the aggregate table when the actual data inside schemas changes, so even if you use them, you'll need to combine them with another approach below.

#### Lazy updating

Be lazy and trigger a refresh before you execute aggregate queries.

```sql
SELECT refresh_aggregate_table('customers');
SELECT count(*) FROM all_customers;
```

This will slow down your aggregate queries, but provide you the most "real time" aggregate data.

#### Scheduled updates

If it's OK for your aggregate data to be slightly out of date, a reasonable compromise is to update your schemas on a schedule. For example, you could have a cron job or application worker to update the aggregate tables or views hourly, daily, etc.

```ruby
class RefreshAggregateTables
  recurrence do
    daily.hour_of_day(3)
  end

  def perform
    self.class.connection.execute("SELECT refresh_aggregate_table('customers')")
    self.class.connection.execute("SELECT refresh_aggregate_table('orders')")
  end
end
```

### Using dynamic SQL

There is another option which doesn't involve aggregate tables or refresh worries, and that is to use the dynamic SQL features provided by PL/pgSQL.

The following function takes advantage of PL/pgSQL's ability to return one big result set when running multiple queries. It loops through all schemas, runs the same `SELECT *` query in each, and then the function returns them all as a dynamic result set.

``` sql
CREATE OR REPLACE FUNCTION all_customers_dynamic() RETURNS SETOF customers AS $$
DECLARE
  schema RECORD;
BEGIN
  FOR schema IN EXECUTE
    format(
      'SELECT schema_name FROM information_schema.schemata WHERE left(schema_name, 4) = %L',
      'user'
    )
  LOOP
    RETURN QUERY EXECUTE
      format('SELECT * FROM %I.customers', schema.schema_name);
  END LOOP;
END;
$$ LANGUAGE plpgsql;
```

You can use this like so:

```sql
SELECT count(*) FROM all_customers_dynamic();
```

The cool thing here is that you don't need to create a table or ensure it's up to date. If you run a query using that function, it'll return the freshest data possible from all schemas.

This feels somewhat like an abuse of Postgres, so I have no idea how healthy this is for your database. But in my experience it does work, and is fairly quick too. You obviously can't add indexes to the returned "table", so it's not going to be practical for all cases, but it's an option and a useful thing to know I think!

### Conclusion

Deciding a strategy for aggregate queries across schemas really comes down to how fresh you need the data. If it's OK for the data to be a little stale, you can get by with aggregate tables and scheduled updates. If it needs to be real time, the absolute best you'll get is refreshing your aggregate tables immediately before running your queries, or using one of the dynamic SQL options above.

If you need absolute 100% real time, well, you're not going to get that with schemas and aggregate tables. Your best option would be to create `INSERT/DELETE/UPDATE` on absolutely everything and attempt to create a to-the-second copy of your schema data in a single table.

At [LoyaltyLion](https://loyaltylion.com/) we use schemas a lot but decided we don't need super fresh data, so we're using aggregate tables and refresh them a few times a day and it works great. By the way, [we're hiring](https://loyaltylion.com/jobs), so if you like things like this, come take a look!

Hope that helps!