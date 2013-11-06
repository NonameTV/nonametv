Convert for jsontv to xmltv
===========================

This project contains a small script I have written that converts the JSON available at http://xmltv.tvtab.la/json to
xml that can be used for importing the information to mythtv by tv_grab_se_swedb. This means that a more reliable
source of information can be used.

Licence
-------
GPL_v3

Usage
-----
First create a virtual python environment:
virtualenv --no-site-packages env

Activate the virtual environment:
source env/bin/activate

Upgrade pip:
pip install pip --upgrade

Install dependencies:
pip install -r pip-stable.txt

Finally run the program:
python convert.py <complete-path-to-swedb.xmltv>

When the program is finished (will take a while), you will have valid XMLTV files under the /tmp/xmltv_convert/xml/.

Deployment
----------
Before deploying the files, you need to have a server that can serve the files. Setup of such a server is
something that you need to do before running the convert.py file. You will also need to change the url on row 162
in the convert.py file. At the moment it says : xml_base_url.text = "http://server.local/xmltv/", you need to
change the URL to a valid URL to your XML files.
When the xml files are generated (actually xml.gz files), you then need to setup a server that will serve the files to
the grabber. I would also recommend using rsync to sync the files from the /tmp/xmltv_convert/xml/ folder to your
webserver folder. That way when one xml file is deleted, they will be deleted in the web folder as well.