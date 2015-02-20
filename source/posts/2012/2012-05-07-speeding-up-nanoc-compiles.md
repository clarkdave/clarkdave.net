---
title: "Speeding up nanoc compiles"
slug: speeding-up-nanoc-compiles
date: 2012-05-06 20:02:48 +0100
kind: article
published: true
---

Although nanoc's great, when you have a bunch of gems all doing their thing and you're just trying to fix a CSS bug or tweak some markup the compile times can be unmanageable.

This may seem like a no-brainer, but a simple trick for this is to use conditionals in your `Rules` file tied to an environment variable. Something like this works a treat:

``` ruby
if ENV['NANOC_ENV'] == 'production'
  filter :colorize_syntax, :default_colorizer => :pygmentize
end
```

For normal development, just continue to run `nanoc compile` and those slow filters will be ignored (seriously, pygmentize is great but it's unbelievably slow for me). When you're ready to see what it looks like for real, run `NANOC_ENV=production nanoc compile` and wait it out.