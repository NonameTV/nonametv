<?php

require "config.php";
require "common.php";
require "mysql.php";
require "epgservers.php";
require "networks.php";
require "transportstreams.php";
require "services.php";
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
       		if( !$myc ) exit;      
		break;
}

$lngstr = loadlanguage( 'viewepg' );
if( $debug ) dbg("language strings" , $lngstr );

?>
<html>
<head>
<title>List EPG servers</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
<link href="css/viewepg.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

//
// main
//

print "<h1>" . $lngstr['title'] . "</h1>\n";

$edb = sql_loadEPGservers( $myc , '' , '' );
if( $debug ) dbg( "epgservers" , $edb );

if( $edb ){
	print "<table width=\"80%\" border=\"0\" cellpadding=\"4\" cellspacing=\"0\">\n";
	print "<tr class=\"tableTitle\">\n";
	print "  <td>" . $lngstr['name'] . "</td>\n";
	print "  <td>" . $lngstr['description'] . "</td>\n";
	print "</tr>\n";

	$rowstyle = 0;

	reset( $edb );
	while( list( $ek , $ev ) = each( $edb ) ){

		print "<tr class=\"tableEPGServer\">\n";
		print "  <td>" .  $ev['name'] . "</td>\n";
		print "  <td>" .  $ev['description'] . "</td>\n";
		print "</tr>\n";

                $ndb = sql_loadNetworks( $myc , 'epgserver' , $ev['id'] );
		reset( $ndb );
		while( list( $nk , $nv ) = each( $ndb ) ){
			print "<tr class=\"tableNetwork\">\n";
			print "  <td>&nbsp;&nbsp;" .  $nv['nid'] . " - " . $nv['name'] . "</td>\n";
			print "  <td>" .  $nv['description'] . "</td>\n";
			print "</tr>\n";

                	$tdb = sql_loadTSs( $myc , 'network' , $nv['id'] );
			if( ! $tdb ) continue;
			reset( $tdb );
			while( list( $tk , $tv ) = each( $tdb ) ){
				print "<tr class=\"tableTS\">\n";
				print "  <td>&nbsp;&nbsp;&nbsp;&nbsp;" .  $tv['tsid'] . "</td>\n";
				print "  <td>" .  $tv['description'] . "</td>\n";
				print "</tr>\n";


				$rowstyle = 0;

                		$sdb = sql_loadServices( $myc , 'transportstream' , $tv['id'] );
				if( ! $sdb ) continue;
				reset( $sdb );
				while( list( $sk , $sv ) = each( $sdb ) ){
					print "<tr class=\"tableService_rowstyle" . $rowstyle . "\">\n";
					print "  <td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;" .  $sv['serviceid'] . "</td>\n";
					print "  <td>" .  $sv['description'] . "</td>\n";
					print "</tr>\n";
					$rowstyle = 1 - $rowstyle;
				}
			}
                }

		$rowstyle = 1 - $rowstyle;
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
