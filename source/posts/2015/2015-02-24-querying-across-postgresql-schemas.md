---
title: Working with and querying across PostgreSQL schemas
slug: working-with-and-querying-across-postgresql-schemas
date: 2015-02-24 17:48:39 +0000
tags: databases postgresql
published: false
---

[Schemas](http://www.postgresql.org/docs/9.4/static/ddl-schemas.html) are a useful (if confusingly named) feature in PostgreSQL which can be used for the design of a multi-tenancy system. Using schemas you could, for example, have one schema for each user of your application. Inside this schema the user has their own copy of all your tables, views etc, and the data within them is completely separate from any other schemas.

Conceptually, this approach is very similar to having a separate database per user, but in fact all schemas live inside the same database and can therefore be queried across within the same session. This also simplifies using them with your application, as all schemas can use the same database connection details.

<!-- more -->

### The use case

Let's suppose we're building an ecommerce platform. People will sign up to our platform and then create their own ecommerce stores which are hosted by us. We've decided to create a schema for each person that signs up. Inside their schema will live all their customers, inventory, etc.

So far so good. If 100 people sign up we'll have 100 schemas, perhaps named `user_1`, `user_2`, etc. We can easily query within a particular schema by either setting the search path, or qualifying our queries with schemas, e.g.

``` sql
SELECT * FROM user_3.customers WHERE customer_id = 5;
```

There'll most likely come a point where you want to take advantage of the fact that all the schemas live inside the same database, and query across them. If you were using a shared table multi-tenacy, this would be as simple as:

``` sql
SELECT count(*) FROM customers;
```

But of course, we're using schemas. Things aren't quite so simple, there are still plenty of methods available to you. Some of these methods involve, for example, using triggers to copy all inserts/updates/deletes into a giant aggregate table in the public schema. This article is instead going to discuss querying across schemas, i.e. no changes to your database model rquired.

### The application generated union query

At the heart of the matter is that we need to pull all the tables in all schemas together to run our query. The most obvious way to do this is by generating a `UNION ALL` statement with our application and then running it.

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

### The union view

The application generated union works fine, but it's one heck of a query and can't really be used outside of your application. You might need to run some ad-hoc queries against your database by hand. To facilitate this, you can create a view to work with. This view could be created within your code:

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

### Keeping the view updated

Because the view is static, as soon as you create a new user and schema it'll be out of date. Additionally, if you ever delete schemas (i.e. when a user deletes their account) you'll need to account for this, or the view will throw an error. You have a few options to keep the view in sync:

#### Refresh the view in your application

For example, if you were using Rails you might add the `create_customers_view` method above to the relevant callbacks in your `User` model:

``` ruby
after_create :refresh_all_views
after_destroy :refresh_all_views
```

As elaborated below, creating the views this way will slow down the entire transaction, as creating the view is not free. You could instead schedule a background worker to refresh the views, which would allow this to happen asynchronously. For example, if you were using Rails with ActiveJob this might be done like so:

``` ruby
def refresh_all_views
  RefreshUnionViewsJob.perform_later
end
```

This does of course mean that any user created outside of your application would not be included in the union view (at least until the next time the above job is run).

#### Use a database trigger

A application-agnostic option might be to a trigger to the `users` table which will refresh the view everytime a record is inserted/deleted.

Because a trigger can only execute one function, we'll create a `refresh_union_views` function first which will update them all. It'd be your responsibility (e.g. with your DB migration tool) to keep this function up to date with a list of tables, but at least the trigger only needs to be created once.

``` sql
CREATE OR REPLACE FUNCTION refresh_union_views() RETURNS trigger AS $$
BEGIN
  EXECUTE refresh_union_view('customers');
  EXECUTE refresh_union_view('orders');
  EXECUTE refresh_union_view('products');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;
```

Now for the trigger:

``` sql
CREATE TRIGGER refresh_union_views
  BEFORE INSERT OR DELETE ON users
  EXECUTE PROCEDURE refresh_union_views();
```

Although this will ensure all new or deleted users will trigger an update of your views, as explained below, this option will delay any `INSERT/DELETE` operation on the users table, as it will refresh the view every time.

#### Update it on demand, or on a schedule

The above two options carry a performance penalty: creating each view is not "free". If you have a considerable amount of schemas, this penalty may be significant. In my experience, creating a union view for ~1000 schemas takes roughly 500ms. If your users are creating their own accounts, this will therefore add several seconds or more to the transaction as the it waits for the trigger to complete.

If you don't want to shift this additional time onto the user, you could instead update the views on demand - as in, prior to starting an aggregate query. If queries of this nature are not too common, this would work well. `CREATE OR REPLACE VIEW` is an idempotent operation so it's safe to run it prior to any aggregate queries, but it will add additional time to each query. Though, if your aggregate queries are already taking 10s of seconds this extra time may not be a problem.

Alternatively you could set up a schedule job, e.g. cron or a background worker, to routinely update the view once an hour or so. If you don't mind some aggregate queries being less than real time, this might be a suitable option.

### Using dynamic SQL

There is another option which doesn't involve views, and that is to use the dynamic SQL features provided by PL/pgSQL. We've already explored part of this with our functions above used to create views, but it's possible to avoid the view altogether, though it will with a cost to performance.

#### Dynamic union

We'll start with an extension to the `refresh_union_view` function we created earlier. Where before this function created a view, now it will simply execute the generated union query:

``` sql
CREATE OR REPLACE FUNCTION all_customers() RETURNS SETOF customers AS $$
DECLARE
  schema RECORD;
  query TEXT := '';
BEGIN
  FOR schema IN EXECUTE
    format(
      'SELECT schema_name FROM information_schema.schemata WHERE left(schema_name, 4) = %L',
      'user'
    )
  LOOP
    query := query || format('SELECT * FROM %I.customers UNION ALL ', schema.schema_name);
  END LOOP;

  RETURN QUERY EXECUTE left(query, -11);
END;
$$ LANGUAGE plpgsql;
```

The convenient thing about this function is once you've created it, you can use it to perform an aggregate query on any table you want. If you add a new schema it'll include that automatically. It can be used like so:

``` sql
SELECT count(*) FROM customers_all();
```

Alas, this function carries a significant performance penalty. Here's what I get with ~1000 schemas containing a total of ~600k records:

``` sql
SELECT count(*) FROM all_customers;
Time: 2411.999 ms

SELECT count(*) FROM all_customers();
Time: 5720.671 ms
```

As you can see, generating the union query on-the-fly has a cost. By the way, you can even create an even more generic function which doesn't even need to know the type of the table ahead of time:

``` sql
CREATE OR REPLACE FUNCTION user_all(_table anyelement) RETURNS SETOF anyelement AS $$
DECLARE
  schema RECORD;
  table_name TEXT := _table::regclass;
  query TEXT := '';
BEGIN
  FOR schema IN EXECUTE
    format(
      'SELECT schema_name FROM information_schema.schemata WHERE left(schema_name, 4) = %L',
      'user'
    )
  LOOP
    query := query || format('SELECT * FROM %I.%I UNION ALL ', schema.schema_name, table_name);
  END LOOP;

  RETURN QUERY EXECUTE left(query, -11);
END;
$$ LANGUAGE plpgsql;

-- can be used like this:
SELECT * FROM user_all('customers');
```

But this is even slower, likely because of the additional work Postgres has to do to figure out the actual return type. It's really cool though!

### Dynamic queries without union

There is a second option for the dynamic query, which is to eschew the `union` entirely. PL/pgSQL functions can execute multiple statements and return all the results.

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

In my experience there is no discernable difference in performance between this and the dynamic union function.