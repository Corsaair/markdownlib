markdownlib
===========

An ActionScript 3.0 implementation of Markdown by John Gruber.

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

TODO

