---
title: Streetvite mobile
snippet: Mobile development with Backbone.js &amp; Rails
url: http://m.streetvite.com
created_at: 2012-03-01
kind: portfolio
technologies: ['ruby', 'rails', 'javascript', 'backbone.js', 'postgresql', 'mongodb']
image_id: streetvite_mobile
---

I opted to develop the mobile version of Streetvite using a Backbone.js frontend combined with a Rails backend. The tiny footprint of Backbone.js and its dependencies makes it well suited to a mobile site and the fairly consistent support of HTML5 and CSS3 features among mobile browsers made this approach a more attractive preposition than a widget framework like jQuery Mobile or Sencha Touch.

The whole site is Retina-display-friendly - high DPI images are only served to users with a high pixel density display (thus avoiding sending both types of images to each user). All images are embedded inside the CSS to minimise download times, and all Javascript is stitched together using a CommonJS architecture and [Stitch](https://github.com/sstephenson/stitch).