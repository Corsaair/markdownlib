markdownlib
===========

An ActionScript 3.0 implementation of Markdown to HTML based on the
original work of John Gruber.

A straightforward (as much as possible) port of `Markdown.pl` v*1.0.1*.

This project can also be seen as a nice tutorial on how to port perl regexp
to AS3 regexp, with identical or similar features, with limitations, and
in some cases their workaround.


Why do it like that ?
---------------------

I looked around and there were no AS3 libraries to parse the markdown format
(well .. there were a gist `Showdown.as` but it was not working).

To write such a library, you have basically two choices, either you fully
embrace the original code and try to port it line-by-line and stay as
close as possible to the original, or you go the opposite way and try
to rethink the whole thing.

I decided to go with the line-by-line port to first acclimate myself
on how markdown internals are working and to produce a fairly
compatible output.


Install
-------

This AS3 library is meant to be used in the context of [Redtamarin](https://github.com/Corsaair/redtamarin)
or other utilities like [as3shebang](https://github.com/Corsaair/as3shebang).

We do not have yet a package manager for Redtamarin, so you will have
to install "by hand" (eg. copy the right file at the right place).


Flash Platform Compatibility
----------------------------

The code does not rely on any particular API or features not available
in the Flash Player or AIR and so should work there too.

My main focus being Redtamarin I did not provide a build to generate a SWC yet.

Simply put it should work but I did not tested it and you are welcome to try it
for yourself (contribution welcome).


Usage
-----

```as3
var markdownlib:* = Domain.currentDomain.load( "markdownlib.abc" );
trace( markdownlib + " loaded"  ); //optional

import text.markdown.*;

//use any definitions of the markdown library
```

**sources**

Copy `markdownlib/src` to your current AS3 project path.

In your main AS3 file
```as3
include "markdownlib.as";

import text.markdown.*;

//use any definitions of the markdown library
```


Example
-------

```as3
import text.markdown.*;

var md:String = "This is **Markdown**";
var html:String = Markdown( md );
trace( html );"

```


Known Differences in Output
---------------------------

To be continued ...



