<?php

$dconf = array(

	//
	// general
	//
        'verbose' => false,
        'lowercase' => true,
	'logfile' => "/var/log/nonametv/nonametv-web.log",

	//
	// language that we use
	// it uses strings from table named "languagestrings"
	//
	'language' => "en",

        //
        // primary database server
        //
        'dbtype' => "mysql",
        'dbhost' => "<ip>",
        'dbname' => "nonametv",
        'dbuser' => "<user>",
        'dbpass' => "<pw>",

        //
        // secondary database server
        //
        'dbsectype' => "",
        'dbsechost' => "",
        'dbsecname' => "",
        'dbsecuser' => "",
        'dbsecpass' => "",

        //
        // channel logos url
        //
        'urllogos' => "http://xmltv.tvzon.se/chanlogos/",

	//
	// programs list
	//
	'channsinline' => 6,

	//
	// Now playing setup
	//
	'tablewidth' => 100,	// width of the table (%)
	'timewidth' => 120,	// time window to display (minutes)
	'grancell' => 1,	// smallest cell width (minutes)
	'grantimebar' => 15,	// time bar granularity (minutes)
	'displayshort' => 'no',	// display programs shorter than grancell
	'shiftarrow' => 60,	// how much time to shift on left/right arrow click
	'firstcellwidth' => 20,	// width of the first cell (percent of the whole row)
	'lastcellwidth' => 20,	// width of the last cell (percent of the whole row)
	'logosdir' => '44x44/',	// icons directory with trailing '/', leave blank for 100x100

	//
	// nonametv backend programs
	//
	'nonametvuser' => "gonix",
	'nonametvhome' => "/home/gonix/nonametv/nonametv/",
	'scriptexportchannels' => "/home/gonix/bin/exportchannels.sh",

	//
	// system executables paths
	//
	'sudo' => "/usr/bin/sudo",
);

?>
