Versions
========

1.0
---
First release. Converter working without any configuration and without any frills.

1.0.1
-----
Fixed downloads so that only files from todays date are downloaded.

1.1
---
Fixed so that the script can parse a Swedb.xmltv configuration file to decide which files should be downloaded.

1.1.1
-----
Rewrote the gzip file part so that it should work in python 2.6

1.1.2
-----
Rewrote file opening so that the file is checked for gzip format first and then opened as a text file if not
in gzip format.

1.1.3
-----
Fixed credits xml info so that it follows the xmltv.dtd.

1.1.4
-----
Fixed order so that it corresponds with the xmltv.dtd.

1.1.5
-----
Fixed setting the gzip time so that the file can be copied with rsync and not copied if the contents aren't different.
