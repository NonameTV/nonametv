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

$lngstrns = loadlanguage( 'nowshowing' );
if( $debug ) dbg("language strings - nowshowing" , $lngstrns );

$lngstrpd = loadlanguage( 'programdetails' );
if( $debug ) dbg("language strings - program details" , $lngstrpd );

?>
<html>
<head>
<title>Now showing</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<script type="text/javascript" src="js/mythweb/init.js"></script>
<script type="text/javascript" src="js/mythweb/browser.js"></script>
<script type="text/javascript" src="js/mythweb/utils.js"></script>
<script type="text/javascript" src="js/mythweb/mouseovers.js"></script>
<script type="text/javascript" src="js/mythweb/visibility.js"></script>
<script type="text/javascript" src="js/mythweb/ajax.js"></script>
<link href="css/nonametv.css" rel=stylesheet>
<link href="css/nowshowing.css" rel=stylesheet>
<link href="css/categories.css" rel=stylesheet>
<link href="css/mythweb/style.css" rel=stylesheet>
<link href="css/mythweb/header.css" rel=stylesheet>
<link href="css/mythweb/menus.css" rel=stylesheet>
<link href="css/mythweb/programming.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

print "<h1>" . $lngstrns['title'] . "</h1>\n";
print "<p>" . $lngstrns['headertext'] . "</p>\n";

//
// main
//

//dbg("request",$_REQUEST);

$chgdb = load_channelgroups( $myc );
if( $debug ) dbg( "channel groups" , $chgdb );

//draw_catlegend();

// reset program item counter
$prgcnt=0;

reset($chgdb);
while( list( $cgk , $cgv ) = each( $chgdb ) ){

	print "<h2>" . $cgv['display_name'] . "</h2>\n";

	$chdb = db_loadChannels( "chgroup" , $cgv['abr'] );
	if( $debug ) dbg( "channels" , $chdb );

	if( $chdb ){
		$chdb = array_sort( $chdb , $cgv['sortby'] );

		if( isset($_REQUEST['time']) ) $fromtime = $_REQUEST['time'];
		if( ! isset($fromtime) ){
			$fromtime = time();
			//$fromtime = 1156800291;
//dbg("time",$fromtime);
//dbg("offset zone dst",date("Z T I",$fromtime));

			// find last 'timewidth' point before requested time
			// as this is the actual starting time
			$da = getdate($fromtime);
			$da['minutes'] = (int)($da['minutes'] / $dconf['grantimebar']) * $dconf['grantimebar'];
			$da['seconds'] = 0;
			$fromtime = mktime ( $da['hours'] , $da['minutes'] , $da['seconds'] , $da['mon'] , $da['mday'] , $da['year'] );
		}

		$totime = $fromtime + ( $dconf['timewidth'] * 60 );
//dbg("fromtime",$fromtime);
//dbg("totime",$totime);

		print "\n<!-- now showing table -->\n";
		print "<table width=\"" . $dconf['tablewidth'] . "%\" border=\"0\" cellpadding=\"4\" cellspacing=\"1\" class=\"nowshowing\">\n";

		draw_timebar( $fromtime , $dconf['timewidth'] , $dconf['grancell'] , $dconf['grantimebar'] );
?>

<?php
		reset($chdb);
		while( list( $chk , $chv ) = each($chdb) ){

			// skip channel if it is not to be exported
			if( $chv['export'] != "1" ) continue;

			print "\n<!-- " . $chv['display_name'] . " -->\n";

			print "<tr class=\"nowshowing_tablebody\">\n";

			print "  <td class=\"nowshowing_firstcell\" width=\"" . $dconf['firstcellwidth'] . "%\" align=\"center\" valign=\"center\">\n";
			print "<a href=\"nowonchannel.php?id=" . $chv['id'] . "&time=" . $fromtime . "\">\n";
			if( $chv['logo'] ) print "<img src=\"" . $dconf['urllogos'] . "/" . $dconf['logosdir'] . $chv['xmltvid'] . ".png\" border=0><br>\n";
			print $chv['display_name'] . "<br>\n";
			if( $chv['url'] ) print "<a href=\"" . $chv['url'] ."\" target=\"_new\">" . $chv['url'] ."</a>\n";
			print "</a></td>\n";

			$prgchunk = extract_programs( $chv['id'] , $fromtime , $totime );
//dbg("prgchunk",$prgchunk);
			if( !$prgchunk ){
				$hole['channel_id'] = $chv['id'];
				$hole['start_time'] = date( "Y-m-d H:i:s" , $fromtime );
				$hole['end_time'] = date( "Y-m-d H:i:s" , $totime );
				$hole['title'] = $lngstrns['nodata'];
				$hole['description'] = $lngstrns['nodatadesc'];
				$hole['category'] = "hole";
//dbg("hole",$hole);
				$prgchunk[] = $hole;
			}

			$prgchunk = fix_programs( $prgchunk , $fromtime , $totime );

			reset($prgchunk);
			while( list( $pck , $pcv ) = each( $prgchunk ) ){
//dbg("program",$pcv);
				$cp = cellwidth( $pcv , $fromtime , $dconf['timewidth'] );
//dbg("cp" , $cp );
				// if a program is shorter than a value we have
				// set for shorter cell length -> colspan will be 0
				if( ( $dconf['displayshort'] == "no" ) && ( $cp['s'] < 1 ) ){
					// fill the hole...
				} else {
					$cellclass = cellclass_category( $pcv , $chv['def_cat'] );

					print "<td align=\"left\" valign=\"top\" width=\"" . $cp['w'] . "%\" colspan=\"" . $cp['s'] . "\" class=\"" . $cellclass . "\">\n";
					//print hmins($pcv['start_time']) . " - " . hmins($pcv['end_time']) . "<br>\n";
					print hmins($pcv['start_time']) . "<br>\n";
					print "<b>";
					if( $cellclass != "cat_hole" ) print "<a href=\"viewprogram.php?channel=" . $pcv['channel_id'] . "&time=" . str2time($pcv['start_time'], 0 ) . "\" id=\"program_" . $prgcnt . "\" onmouseover=\"popup('program_" . $prgcnt . "',''); return true;\">";
					#if( $cellclass != "cat_hole" ) print "<a id=\"program_" . $prgcnt . "\" onclick=\"popup('program_" . $prgcnt . "',''); return true;\">";
					print $pcv['title'];
					if( $cellclass != "cat_hole" ) print "</a>";
					print "</b><br>\n";
					if( isset($pcv['subtitle']) ) print $pcv['subtitle'] . "<br>\n";

					// icons on the bottom
					print "<table>\n";
					print "  <tr>\n";
					if( isset($pcv['url']) && strlen(trim($pcv['url'])) ){
						//if( !strstr( "://" , $pcv['url'] ) ) $pcv['url'] = "http://" . $pcv['url'];
						print "<td><a href=\"" . $pcv['url'] . "\" target=\"_new\"><img src=\"images/world.gif\" border=\"0\"></a></td>\n";
					}
					print "  </tr>\n";
					print "</table>\n";

					print "</td>\n";

					$prgdetails[$prgcnt]['title'] = $pcv['title'];
					$prgdetails[$prgcnt]['description'] = $pcv['description'];
					$prgcnt++;
				}
			}

			print "<td class=\"nowshowing_lastcell\" width=\"" . $dconf['lastcellwidth'] . "%\"><a href=\"nowshowing.php?time=" . ( $fromtime + $dconf['timewidth'] + $dconf['shiftarrow'] * 60 ) . "\"><img src=\"images/right.gif\" border=\"0\" alt=\"right\"></a></td>\n";
			print "</tr>\n";
		}

		print "</table>\n";

	} // next channel group
}

/*
reset($prgdetails);
while( list( $pdk , $pdv ) = each( $prgdetails ) ){
	print "<div id=\"program_" . $pdk . "_popup\" class=\"popup\">\n";
	print "  <dl class=\"details_list\">\n";
	print "    <dt>" . $lngstrpd['prgtitle'] . ":</dt><dd>" . $pdv['title'] . "</dd>\n";
	print "    <dt>" . $lngstrpd['prgdescription'] . ":</dt><dd>" . $pdv['description'] . "</dd>\n";
	print "  </dl>\n";
	print "</div>\n";
}
*/

//
// disconnect from main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
       		sql_dodisconnect( $myc );
		break;
}

?>

</body>
</html>
