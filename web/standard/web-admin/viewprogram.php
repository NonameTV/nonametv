<?php

require "config.php";
require "common.php";
require "mysql.php";
#require "commonmysql.php";
require "channels.php";
require "programs.php";
require "language.php";

$debug=false;

if( $debug ){
	dbg( "NonameTV" , $dconf );
}

//
// connect to main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
       		$myc = sql_doconnect();
       		if( ! $myc ) exit;      
		break;
}

$lngstrpd = loadlanguage( 'programdetails' );
if( $debug ) dbg("language strings - program details" , $lngstrpd );

?>
<html>
<head>
<title>View program</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

function doexit()
{
	global $dconf,$myc;

	//
	// disconnect from main database
	//
	switch( $dconf['dbtype'] ){
		case 'mysql':
       			sql_dodisconnect( $myc );
			break;
	}

	print "</body>\n";
	print "</html>\n";

	exit;
}

//
// main
//
if( isset( $_REQUEST['channel'] ) ) $channel_id = $_REQUEST['channel'];
else {
	print "<h2>" . $lngstrpd['nochanspecified'] . "</h2>";
	doexit();
}
if( isset( $_REQUEST['time'] ) ) $showtime = $_REQUEST['time'];
else {
	print "<h2>" . $lngstrpd['notimespecified'] . "</h2>";
	doexit();
}

$chann = sql_findChannel( $myc , 'id' , $channel_id );
if( ! $chann ){
	print "<h2>" . $lngstrpd['invchanid'] . ": " . $channel_id . "</h2>";
	doexit();
}

$prog = sql_findProgram( $myc , $channel_id , "start_time" , strftime( "%Y-%m-%d %H:%M:%S" , $showtime ) );
if( ! $prog ){
	print "<h2>" . $lngstrpd['noprogstartingat'] . ": " . strftime( "%Y-%m-%d %H:%M:%S" , $showtime + date('Z') ) . "</h2>";
	doexit();
}
//dbg("prog",$prog);

if( $chann['logo'] ){
	print "<img src=\"" . $dconf['urllogos'] . "/" . $chann['xmltvid'] . ".png\">\n";
}
print "<h1>" . $lngstrpd['progdetailsfor'] . " " . $chann['display_name'] . " " . $lngstrpd['at'] . " " . strftime( "%Y-%m-%d %H:%M:%S" , $showtime + date('Z') ) . "</h1>\n";

print "\n<!-- program details table -->\n";
print "<table width=\"75%\" border=\"0\" cellpadding=\"4\" cellspacing=\"2\" class=\"viewprogram\">\n";

print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
print "    <td align=\"right\">" . $lngstrpd['prgtitle'] . ":</td>\n";
print "    <td align=\"left\">\n";
print "      <b>" . $prog[0]['title'] . "</b>\n";
print "    </td>\n";
print "  </tr>\n";

if( strlen(trim($prog[0]['subtitle'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgsubtitle'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['subtitle'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['category'])) ){
	$cellclass = cellclass_category( $prog[0] , $chann['def_cat'] );
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgcategory'] . ":</td>\n";
	print "    <td align=\"left\" class=\"" . $cellclass . "\">\n";
	print "      " . $prog[0]['category'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['description'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgdescription'] . ":</td>\n";
	print "    <td align=\"left\">\n";
        $predesc = ereg_replace( "\n" , "<br>" , $prog[0]['description'] );
	print "      " . $predesc . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['directors'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgdirectors'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['directors'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['actors'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgactors'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['actors'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['writers'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgwriters'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['writers'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['adapters'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgadapters'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['adapters'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['producers'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgproducers'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['producers'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['presenters'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgpresenters'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['presenters'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['commentators'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgpresenters'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['commentators'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

if( strlen(trim($prog[0]['guests'])) ){
	print "  <tr valign=\"top\" class=\"viewprogram_tableBody\">\n";
	print "    <td align=\"right\">" . $lngstrpd['prgguests'] . ":</td>\n";
	print "    <td align=\"left\">\n";
	print "      " . $prog[0]['guests'] . "\n";
	print "    </td>\n";
	print "  </tr>\n";
}

print "</table>\n";

doexit();

?>
