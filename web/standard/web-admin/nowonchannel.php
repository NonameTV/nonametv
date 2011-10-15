<?php

require "config.php";
require "common.php";
require "mysql.php";
#require "commonmysql.php";
require "channels.php";
require "programs.php";

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

?>
<html>
<head>
<title>Now on channel</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

//
// main
//
if( $_REQUEST['id'] ) $channel_id = $_REQUEST['id'];
else {
}

$chann = sql_findChannel( $myc , 'id' , $channel_id );

if( $chann['logo'] ){
	print "<img src=\"" . $dconf['urllogos'] . "/" . $chann['xmltvid'] . ".png\">\n";
}
print "<h1>Trenutno na " . $chann['display_name'] . " (" . $chann['xmltvid'] . ")</h1>\n";

if( $_REQUEST['time'] ) $fromtime = $_REQUEST['time'];
if( ! $fromtime ){
	//$fromtime = time();
	$fromtime = 1155647837;

//dbg("fromtime",$fromtime);
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

$pdb = extract_programs( $channel_id , $fromtime , $totime );
if( $debug ) dbg( "programs" , $pdb );

$pdb = fix_programs( $pdb , $fromtime , $totime );


if( $pdb ){
	print "\n<!-- now showing table -->\n";
	print "<table width=\"75%\" border=\"0\" cellpadding=\"4\" cellspacing=\"2\" class=\"nowshowing\">\n";
	print "<tr class=\"tableMenuTitle\">\n";
	print "  <td class=\"tableMenuBody\">Time</td>\n";
	print "  <td class=\"tableMenuBody\">Program</td>\n";
	print "</tr>\n";

        $pdb = array_sort( $pdb , "start_time" );

        reset( $pdb );
        while( list( $chk , $chv ) = each( $pdb ) ){

                print "<tr class=\"tableBody\">\n";

                print "  <td align=\"center\">\n";
                print hmins($chv['start_time']) . " - " . hmins($chv['end_time']);
                print "  </td>\n";

		$cellclass = cellclass_category( $chv , $chann['def_cat'] );

                print "<td class=\"" . $cellclass . "\">";
		if( $cellclass != "cat_hole" ) print "<a href=\"viewprogram.php?channel=" . $chv['channel_id'] . "&time=" . str2time($chv['start_time'], 0 ) . "\">";
                print  "<b>" . $chv['title'] . "</b>";
                if( $cellclass != "cat_hole" ) print "</a>";
		print "</td>\n";

                print "</tr>\n";
        }

	print "</table>\n";
}

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
