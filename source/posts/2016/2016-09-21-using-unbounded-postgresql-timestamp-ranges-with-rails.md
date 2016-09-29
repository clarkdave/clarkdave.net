---
title: Using unbounded PostgreSQL timestamp ranges with Rails
slug: using-unbounded-postgresql-timestamp-ranges-with-rails
date: 2016-09-21 12:16:03 +0000
tags:
published: false
---

Native PostgreSQL timestamp ranges (`tsrange` or `tstzrange`) have a few attributes which the Ruby (and therefore Rails) Range type don't support:

- either end can be exclusive. Ruby's `Range` only allows inclusive/inclusive or inclusive/exclusive ranges
- either end can be unbounded, i.e. infinity

There have been a [few PRs](https://github.com/rails/rails/pull/17365) aimed at bringing support for this into Rails, but as of writing there's still no native support.

Note: this problem is specific to *timestamp* ranges. If all you need is unbounded *date* ranges via the `daterange` type, you can do that already. `Range` will let you do the following, which is exactly what Rails will do internally when given an unbounded `daterange` from a Postgres record:

```ruby
range = Date.today..Float::INFINITY
range.cover?(Date.today + 100.days) # true
```

You cannot, however, do this...

```ruby
range = DateTime.now..Float::INFINITY
# ArgumentError: bad value for range
```

<!-- more -->

### Replacing Range with PGRange

Lucky for us, the [Sequel](https://github.com/jeremyevans/sequel) library already has a `PGRange` class it uses internally to represent Postgres ranges. So with a bit of monkey patching, we can pull this class into a Rails application and use it when dealing with a time range.

First, add the latest version of the [Sequel gem](https://rubygems.org/gems/sequel) into your Rails application.

Next, add a new initialize called `config/initializers/pg_range.rb`. In here
