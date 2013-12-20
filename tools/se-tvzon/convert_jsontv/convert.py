import datetime
import gzip
import json
import time
import urllib2
import os
from sys import stdout, argv
from bs4 import BeautifulSoup
import xml.etree.ElementTree as ET
from xml.dom import minidom

credits_order = ['director', 'actor', 'writer', 'adapter', 'producer',
                 'composer', 'editor', 'presenter', 'commentator', 'guest']

channels = []

def parse_arguments():
    if len(argv) == 2:
        file = open(argv[1], "r")
        for line in file.readlines():
            try:
                line_array = line.replace("\n", "").split("=")
                if line_array[0] == "channel":
                    print line_array[1]
                    channels.append(line_array[1])
            except IndexError:
                pass

def download_json_files():
    if not os.path.exists('/tmp/xmltv_convert/json'):
        os.makedirs('/tmp/xmltv_convert/json')

    page = urllib2.urlopen('http://json.xmltv.se/')
    soup = BeautifulSoup(page)
    soup.prettify()

    for anchor in soup.findAll('a', href=True):
        if anchor['href'] != '../':
            try:
                anchor_list = anchor['href'].split("_")
                channel = anchor_list[0]
                filedate = datetime.datetime.strptime(anchor_list[1][0:10], "%Y-%m-%d").date()
            except IndexError:
                filedate = datetime.datetime.today().date()

            if filedate >= datetime.datetime.today().date():
                if len(channels) == 0 or channel in channels or channel == "channels.js.gz":
                    stdout.write("Downloading http://xmltv.tvtab.la/json/%s " % anchor['href'])
                    f = urllib2.urlopen('http://xmltv.tvtab.la/json/%s' % anchor['href'])
                    data = f.read()
                    with open('/tmp/xmltv_convert/json/%s' % anchor['href'].replace('.gz', ''), 'w+ ') as outfile:
                        outfile.write(data)
                    stdout.write("Done!\n")
                    stdout.flush()

def create_xml():
    if not os.path.exists('/tmp/xmltv_convert/xml'):
        os.makedirs('/tmp/xmltv_convert/xml')

    for filename in os.listdir('/tmp/xmltv_convert/json/'):
        if filename != '.' and filename != '..':
            stdout.write("Opening %s, creating XML " % filename)
            try:
                json_data = gzip.open('/tmp/xmltv_convert/json/%s' % filename, 'rb').read()
            except IOError:
                json_data = open('/tmp/xmltv_convert/json/%s' % filename).read()
            data = json.loads(json_data)

            root = ET.Element("tv", { "generator-info-name": "nonametv" })

            if filename != "channels.js":
                for programme in data['jsontv']['programme']:
                    starttime = time.localtime(float(programme['start']))
                    stoptime = time.localtime(float(programme['stop']))

                    starttime_offset = "+0200" if starttime.tm_isdst else "+0100"
                    stoptime_offset = "+0200" if stoptime.tm_isdst else "+0100"

                    # Programme should always contain something
                    xml_programme = ET.SubElement(root, "programme", {"start": "%s %s" % (time.strftime("%Y%m%d%H%M%S", starttime),
                                                                                         starttime_offset),
                                                                      "stop": "%s %s" % (time.strftime("%Y%m%d%H%M%S", stoptime),
                                                                                        stoptime_offset),
                                                                      "channel": programme['channel'] })

                    # A title should be there
                    if programme.has_key("title"):
                        for key in programme['title'].keys():
                            title = programme['title'][key]
                            parsed_title = ''.join(c for c in title if ord(c) >= 32)
                            xml_desc = ET.SubElement(xml_programme, "title", { "lang": key })
                            xml_desc.text = parsed_title

                    # A subtitle COULD be there
                    if programme.has_key("subTitle"):
                        for key in programme['subTitle'].keys():
                            subtitle = programme['subTitle'][key]
                            parsed_subtitle = ''.join(c for c in subtitle if ord(c) >= 32)
                            xml_subtitle = ET.SubElement(xml_programme, "sub-title", { "lang": key })
                            xml_subtitle.text = parsed_subtitle

                    # A description COULD be there
                    if programme.has_key("desc"):
                        for key in programme['desc'].keys():
                            description = programme['desc'][key]
                            parsed_description = ''.join(c for c in description if ord(c) >= 32)
                            xml_desc = ET.SubElement(xml_programme, "desc", { "lang": key })
                            xml_desc.text = parsed_description

                    # Credits COULD be present
                    if programme.has_key("credits"):
                        xml_credits = ET.SubElement(xml_programme, "credits")
                        for key in credits_order:
                            for value in programme['credits'].get(key, []):
                                xml_credit = ET.SubElement(xml_credits, key)
                                xml_credit.text = value

                    # A date COULD be there
                    if programme.has_key("date"):
                        xml_date = ET.SubElement(xml_programme, "date")
                        xml_date.text = programme['date']

                    # A category COULD be there
                    if programme.has_key("category"):
                        for key in programme['category'].keys():
                            for value in programme['category'][key]:
                                xml_category = ET.SubElement(xml_programme, "category", { "lang": key })
                                xml_category.text = value.replace("\n", "")

                    # An url COULD be present
                    if programme.has_key("url"):
                        url = ET.SubElement(xml_programme, "url")
                        url.text = programme['url'][0]

                    # An episode number sequence COULD be present
                    if programme.has_key("episodeNum"):
                        for key in programme['episodeNum'].keys():
                            episode_num = ET.SubElement(xml_programme, "episode-num", { "system": key })
                            episode_num.text = programme['episodeNum'][key].replace("\n", "")

                    # Video COULD be present
                    if programme.has_key("video"):
                        if programme['video'].has_key("aspect"):
                            xml_video = ET.SubElement(xml_programme, "video")
                            xml_video_aspect = ET.SubElement(xml_video, "aspect")
                            xml_video_aspect.text = programme['video']['aspect']

                    # A rating COULD be present
                    if programme.has_key("rating"):
                        if programme['rating'].has_key("mpaa"):
                            rating = ET.SubElement(xml_programme, "rating", { "system": "MPAA" })
                            rating_value = ET.SubElement(rating, "value")
                            rating_value.text = programme['rating']['mpaa']
                        if programme['rating'].has_key("stars"):
                            star_rating = ET.SubElement(xml_programme, "star-rating")
                            star_rating_value = ET.SubElement(star_rating, "value")
                            star_rating_value.text = programme['rating']['stars']

            else:
                for key in data['jsontv']['channels']:
                    xml_channel = ET.SubElement(root, "channel", { "id": key })

                    for lang in data['jsontv']['channels'][key]['displayName'].keys():
                        xml_display_name = ET.SubElement(xml_channel, "display-name", { "lang": lang })
                        xml_display_name.text = data['jsontv']['channels'][key]['displayName'][lang]

                    xml_base_url = ET.SubElement(xml_channel, "base-url")
                    xml_base_url.text = "http://server.local/xmltv/"

                    if data['jsontv']['channels'][key].has_key('icon'):
                        xml_icon = ET.SubElement(xml_channel, "icon", { "src": data['jsontv']['channels'][key]['icon'] })

            outfile = gzip.GzipFile('/tmp/xmltv_convert/xml/%s' % filename.replace('.js', '.xml.gz'), 'w+', 9, None, long(1))
            text = ET.tostring(root, encoding="utf-8")
            doc = minidom.parseString(text)
            dt = minidom.getDOMImplementation('').createDocumentType('tv', None, 'xmltv.dtd')
            doc.insertBefore(dt, doc.documentElement)
            outfile.write(doc.toprettyxml(encoding="utf-8"))
            outfile.close()

            stdout.write("Done!\n")

os.environ['TZ'] = 'Europe/Stockholm'

print "Deleting old files..."
if os.path.exists('/tmp/xmltv_convert/json'):
    for filename in os.listdir('/tmp/xmltv_convert/json/'):
        if filename != '.' and filename != '..':
            os.remove('/tmp/xmltv_convert/json/%s' % filename)

if os.path.exists('/tmp/xmltv_convert/xml'):
    for filename in os.listdir('/tmp/xmltv_convert/xml/'):
        if filename != '.' and filename != '..':
            os.remove('/tmp/xmltv_convert/xml/%s' % filename)

print "Check which files should be downloaded..."
parse_arguments()

print "Downloading files..."
download_json_files()

print "Reformat json to xml..."
create_xml()