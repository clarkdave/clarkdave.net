---
title: "Save bandwidth by serving either Retina OR normal images using Javascript"
created_at: 2012-06-15 14:40:15 +0100
kind: article
published: true
---

Most solutions for providing Retina, or Hi-DPI, images to a client involve media queries or a bit of Javascript to replace standard images with Retina ones when appropriate. Both of these solutions result in the standard images being downloaded by every client (and with media queries, they also often involve the Retina images being downloaded by every client too!)

If you're willing to require Javascript (which may already be the case, especially for mobile apps) you can avoid the multi-download problem and serve exactly which images are required, saving both you and your users bandwidth.

<!-- more -->

### Use Javascript to attach your CSS to the DOM

The trick is to delay the loading your CSS (specifically, the CSS which includes your images) and let your Javascript add it after it's had a chance to determine the device's retina capability.

In its simplest form, it would look a little something like this:

    #!html
    <head>
      <!-- this is your main CSS - no images in here! -->
      <link rel='stylesheet' type='text/css' href='base.css'>
      <script>
        var pixel_ratio = window.devicePixelRatio || 1;
        var css_url;

        // set the url to the images CSS file based on the pixel ratio
        switch (pixel_ratio) {
          case 2:
            css_url = 'images@2x.css';
            break;
          default:
            css_url = 'images.css';
        }

        // create a new <link> tag and attach it to the dom
        var link = document.createElement('link');
        link.type = 'text/css';
        link.rel = 'stylesheet';
        link.href = css_url;
        var l = document.getElementsByTagName('link')[0];
        l.parentNode.appendChild(link);
      </script>
    </head>

This has the advantage of only loading the correct set of images. If the browser doesn't provide a pixel ratio, it'll default to standard images, otherwise it'll use the Retina images if the browser's pixel ratio is 2 (in practice, you may want to use an if statement and check if it's above 1.5 as some devices might report their Hi-DPI status differently).

The downside? If the user doesn't have Javascript enabled, they will never see any images.

In the future, I'd be surprised if browsers didn't start offering some kind of built-in support for this Retina song-and-dance. If Retina-capable browsers sent a specific header, we could just just use that to determine which resolution images to send. Maybe one day?
