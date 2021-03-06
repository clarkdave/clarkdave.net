---
title: Scraping your data from First Direct
slug: scaping-your-data-from-first-direct
description: Using Node.js and Zombie to scrape data from your bank
date: 2012-02-01 21:06:01 +0000
tags:
published: true
---

Like most people, I'm a routine user of internet banking. Although my bank, First Direct, do have an banking web application, I want to get at my financial data on my own terms so I can use it for more interesting projects. Since First Direct don't offer any sort of API I decided to use NodeJS and <a href='https://zombie.labnotes.org/'>Zombie</a> (a headless web browser) to do the job instead.

So, if you're a First Direct customer and a programmer, and want to get your data out too, this might help. If you're a member of a different bank, you might still find this helpful as the advice should be fairly generic (although, if your banking website is very Javascript-heavy, it'll be harder).

<!-- more -->

### Investigation

Before we start, just a disclaimer: there's nothing suspicious going on here. We're not reverse-engineering anything, we're simply telling a headless web browser how to access the website. There's nothing here that you couldn't do yourself using your web browser.

As far as I can tell, accessing your online bank using a headless web browser does not fall foul of the First Direct terms and conditions. That said, it would probably seem suspicious if you started checking your balance every minute of every day, so if you do this, keep your usage sensible!

The FD online banking landing page is here: `http://www2.firstdirect.com/1/2/pib-service`, but following a bit of redirection we end up here: `https://www1.firstdirect.com/1/2/idv.Logoff?nextPage=fsdtBalances`. This appears to be where the session is actually bootstrapped, as the redirect has a jsessionid in the path, so let's start scripting from here.

### Scraping the site with Zombie

Let’s plug that url into a NodeJS script using Zombie:

```javascript
var Browser = require("zombie");
var browser = new Browser();
browser.runScripts = false;

browser.visit(
  "https://www1.firstdirect.com/1/2/idv.Logoff?nextPage=fsdtBalances",
  function () {
    browser.dump();
  }
);
```

This works - the (fairly horrific) use of Javascript on the main page seems too much for Zombie/JSDOM to cope with, so I had to turn off the running of scripts to get it to parse the DOM. Fortunately, despite the initial reliance on JS for redirects, this page actually functions without it just fine.

The forms actually contain little anchor links inserted via Javascript which are used to submit them:

```javascript
document.write('<a class="fdLogonLink_2" href="javascript:PC_7_2_2C0_submitData()"
title="proceed with log on" onmouseover="noStatus(); return true;" onmousedown="noStatus();
return true;" onfocus="noStatus(); return true;">proceed</a>');
```

But if you have Javascript turned off, the page thoughtfully provides a standard `<input type="submit" />` button. Odd, since (without a bit of URL tinkering) you can't even _get_ to this page without Javascript. Still, there's no reason to complain, as it makes life easier.

With runScripts turned off, Zombie is happy to parse the page which means we can fill in and submit the form using the nice Zombie API:

```javascript
browser.visit(
  "https://www1.firstdirect.com/1/2/idv.Logoff?nextPage=fsdtBalances",
  function () {
    browser.fill("userid", "<username>").pressButton("proceed", function () {
      browser.dump();
      console.log(browser.html());
    });
  }
);
```

Substituting `<username>` for your FD username, this should POST the form successfully and return the next form, which asks for a few characters from your password along with the answer to your security question.

Zombie again managed to parse the HTML of this page fine, so we can use it to find out which characters it wants from our password. The bit of markup we're looking for is here:

```html
<label for="password" class="light"
  >Please enter the <strong>1st</strong>, <strong>2nd</strong> and
  <strong>last</strong> characters from your
  <strong>electronic password</strong>, and the answer to your question.</label
>
```

Of course, the three characters it wants will vary between requests, but we can figure them out fairly easily:

```javascript
var characters = browser
  .queryAll('label[for="password"] strong')
  .slice(0, 3)
  .map(function (elem) {
    var value = elem.childNodes[0].nodeValue;
    if (value == "last") return -1;
    else return parseInt(value);
  });
```

This is tied very closely to the markup, so if they do change it this could break fairly easily. That said, banks tend not to make front-end changes too often, so I'm not too concerned.

Now that we've got the required characters, we need to enter them in. For obvious reasons, if you're storing them alongside your script, be extra careful no one has access to them. For some reason, First Direct, unlike many other banks, have a single login to their online banking which is completely unrestricted (so, if someone did get your credentials, they could easily wipe out your account).

I'm not too comfortable with this setup. I used to bank with Barclays, who basically provided read-only access to your account if you logged in without using a security device (a PIN Sentry). In any case - I **strongly advise** against storing your credentials. Either enter them yourself every time you run the script, or at least store them encrypted and unlock them with a password when you do need them.

It's pretty simple from this point: without Javascript, the form on this page has two input fields: one of the requested password characters and another for the entire security answer. Once you've got your password into the script, you can do something like this to make the string the server's expecting:

```javascript
var indexes = browser
  .queryAll('label[for="password"] strong')
  .slice(0, 3)
  .map(function (elem) {
    var value = elem.childNodes[0].nodeValue;
    if (value == "last") return -1;
    else return parseInt(value);
  });

var characters = indexes
  .map(function (i) {
    if (i == -1) return password[password.length - 1];
    else return password[i - 1];
  })
  .join("");
```

And now you can use Zombie to send them off:

```javascript
browser
  .fill("password", characters)
  .fill("memorableAnswer", memorable_answer)
  .pressButton("proceed", function () {
    browser.dump();
    console.log(browser.html());
  });
```

That last `browser.html()` output should be your main account page. For some reason, the First Direct developers chose this point to reinstigate that Javascript requirement! Every single link on the page actually calls a function which sets `window.location` to change the page. This is probably to avoid people opening pages in tabs or something.

The finished script, from beginning to end, is:

```javascript
var Browser = require("zombie");

var browser = new Browser();
browser.runScripts = false;

browser.visit(
  "https://www1.firstdirect.com/1/2/idv.Logoff?nextPage=fsdtBalances",
  function () {
    browser.fill("userid", "<userid>").pressButton("proceed", function () {
      var indexes = browser
        .queryAll('label[for="password"] strong')
        .slice(0, 3)
        .map(function (elem) {
          var value = elem.childNodes[0].nodeValue;
          if (value == "last") return -1;
          else return parseInt(value);
        });

      // you'll need 'password' and 'memorable_answer' variables
      // available to your code by this point

      var characters = indexes
        .map(function (i) {
          if (i == -1) return password[password.length - 1];
          else return password[i - 1];
        })
        .join("");

      browser
        .fill("password", characters)
        .fill("memorableAnswer", memorable_answer)
        .pressButton("proceed", function () {
          browser.dump();
          console.log(browser.html());
        });
    });
  }
);
```
