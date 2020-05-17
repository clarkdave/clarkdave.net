---
title: Null-safety with JSON and PostgreSQL
slug: navigating-null-safety-with-json-and-postgresql
date: 2015-03-03 01:16:58 +0000
tags:
published: true
---

If you're using the native JSON support in PostgreSQL you may, from time to time, come across the issue of null safety. For example, if you're trying to query a nested JSON object which contains null values. Attempting to use one of the JSON operators on a null will result in an error like this:

```
ERROR:  cannot extract element from a scalar
```

PostgreSQL's `->` operator is generally pretty good at soaking up null references. You can chain it on a nested object and it'll always return null if it encounters a key which doesn't exist. However, if it encounters a key whose value is actually `null`. you'll get the above error.

The easiest way to avoid this is to make sure you never set a JSON key to `null` if you're ever going to treat that key as an object. If you can't make that guarantee though, you've got a few other options to navigate safely around the null.

<!-- more -->

### Test table

We'll use this little table for testing:

```sql
CREATE TABLE books (id int, author json);
INSERT INTO books VALUES (1, null),
  (2, '{ "first_name": "Mary" }'),
  (3, '{ "address": { "street_name": "19 Red Avenue" } }'),
  (4, '{ "address": null }');
```

With the behaviour of the `->` operator, we are able to do this without an error (it'll return null):

```sql
SELECT author->'address'->'street_name' FROM books where id = 1;
```

But if we do this, we'll get an error:

```sql
SELECT author->'address'->'street_name' FROM books where id = 4;
ERROR:  cannot extract element from a scalar
```

### Using a CASE expression

We can use a `case` expression to bail out in case the field turns out to be a null:

```sql
SELECT id,
  coalesce(
    case
      when (author->>'address') IS NULL then null
      else (author->'address'->>'street_name')
    end,
  'No street name') AS author_street_name
FROM books
WHERE id = 4;
```

Note that we're using the `->>` operator to check for the null. This coerces the return value as text, which responds appropriately to the `IS NULL` check. We've also used the `coalesce` function to provide a default value. The result:

```
 id | author_street_name
----+--------------------
  4 | No street name
```

This technique will work for any level of nesting, because when used in this way the `case` expression essentially 'short circuits' and will stop evaulating when it has a match. There are [some caveats](https://www.postgresql.org/docs/9.2/static/sql-expressions.html#SYNTAX-EXPRESS-EVAL) around this with regards to constant expressions, but these shouldn't apply in most cases.

### Using a function

Alternatively, you may find it more convenient (and less verbose) to create your own function. The function below, `json_fetch`, is a simple implementation which will safely traverse and return a nested object without errors.

```sql
CREATE OR REPLACE FUNCTION json_fetch(object json, variadic nodes text[])
RETURNS json AS $$
DECLARE
  result json := object;
  k text;
BEGIN
  foreach k in array nodes loop
    if (result ->> k) is null then
      result := null;
      exit;
    end if;

    result := result -> k;
  end loop;

  return result;
END;
$$ LANGUAGE plpgsql;
```

To use it, you pass it the object you're working with (i.e. the `author` field) and then one parameter for each nested field. Note that the function will return the found object (unless it's null) as a `json` type, so you'll usually need to cast it to `text` or another suitable type when you use it.

```sql
SELECT id,
  coalesce(
    json_fetch(author, 'address', 'street_name')::text, 'No address'
  ) AS street_name
FROM books;
```

```
 id |   street_name
----+-----------------
  1 | No address
  2 | No address
  3 | "19 Red Avenue"
  4 | No address
```

Hope that helps!
