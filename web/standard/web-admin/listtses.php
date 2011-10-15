<?php

require "config.php";
require "common.php";
require "mysql.php";
require "language.php";
require "epgservers.php";
require "networks.php";

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

$lngstr = loadlanguage( 'listtses' );
if( $debug ) dbg("language strings" , $lngstr );

?>
<html>
<head>
<title>List EPG servers</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

function picksrvidform()
{
	global $myc;

	print "<h1>Pick EPG server</h1>\n";
	print "<form name=epgserver action=\"listtses.php\" method=post>\n";

	$srvdb = sql_loadEPGservers( $myc , '' , '' );

	print "  <table>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Name</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <select name=\"srvid\">\n";
	reset($srvdb);
	while( list( $sk , $sv ) = each($srvdb) ){
		print "          <option value=\"" . $sv['id'] . "\">" . $sv['name'] . "</option>\n";
	}
	print "        </select>\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "  </table>\n";

	print "  <input name=\"Action\" value=\"Continue\" type=\"submit\" class=\"gumb\">\n";

	print "</form>\n";
}

function picknetidform( $srvid )
{
	global $myc;

	print "<h1>Pick network on EPG server " . $srvid . "</h1>\n";
	print "<form name=network action=\"listtses.php\" method=post>\n";
	print "  <input type=\"hidden\" name=\"srvid\" value=\"" . $srvid . "\">\n";

	$netdb = sql_loadNetworks( $myc , 'epgserver' , $srvid );

	print "  <table>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Name</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <select name=\"netid\">\n";
	reset($netdb);
	while( list( $nk , $nv ) = each($netdb) ){
		print "          <option value=\"" . $nv['id'] . "\">" . $nv['name'] . "</option>\n";
	}
	print "        </select>\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "  </table>\n";

	print "  <input name=\"Action\" value=\"Continue\" type=\"submit\" class=\"gumb\">\n";

	print "</form>\n";
}

//
// main
//

$srvid = false;
$netid = false;

if( $debug ) dbg( "REQUEST" , $_REQUEST );
if( isset($_REQUEST['srvid']) ) $srvid = $_REQUEST['srvid'];
if( isset($_REQUEST['netid']) ) $netid = $_REQUEST['netid'];

if( $debug ) dbg( "POST" , $_POST );
if( isset($_POST['srvid']) ) $srvid = $_POST['srvid'];
if( isset($_POST['netid']) ) $netid = $_POST['netid'];

if( ! $srvid ){
	picksrvidform();
        sql_dodisconnect( $myc );
	exit;
}

if( $srvid and ! $netid ){
	picknetidform( $srvid );
        sql_dodisconnect( $myc );
	exit;
}

print "<h1>" . $lngstr['title'] . " " . $srvid . "</h1>\n";

print "<form name=\"new\">\n";
print "  <input type=\"button\" value=\"Add new network\" class=\"gumb\" onClick=\"javascript:window.location.href='editnetwork.php?action=new&srvid=" . $srvid . "'\">\n";
print "</form>\n";

$ndb = sql_loadNetworks( $myc , 'epgserver' , $srvid );
if( $debug ) dbg( "networks" , $ndb );

if( $ndb ){
	print "<table width=\"80%\" border=\"0\" cellpadding=\"4\" cellspacing=\"0\">\n";
	print "<tr class=\"tableTitle\">\n";
	print "  <td>" . $lngstr['name'] . "</td>\n";
	print "  <td>" . $lngstr['active'] . "</td>\n";
	print "  <td>" . $lngstr['description'] . "</td>\n";
	print "</tr>\n";

	$rowstyle = 0;

	reset( $ndb );
	while( list( $sk , $sv ) = each( $ndb ) ){

		print "<tr class=\"tableBody\">\n";
		print "  <td><a href=\"editnetwork.php?id=" . $sv['id'] . "\">" .  $sv['name'] . "</a></td>\n";
		print "  <td>" .  $sv['active'] . "</td>\n";
		print "  <td>" .  $sv['description'] . "</td>\n";
		print "</tr>\n";

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
