<?php

require "config.php";
require "common.php";
require "mysql.php";
require "epgservers.php";
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

$lngstr = loadlanguage( 'listepgservers' );
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

print "<h1>" . $lngstr['title'] . "</h1>\n";

?>
<form name="new">
<input type="button" value="Add new server" class="gumb" onClick="javascript:window.location.href='editepgserver.php?action=new'">
</form>
<?php

//
// main
//

$sdb = sql_loadEPGservers( $myc , '' , '' );
if( $debug ) dbg( "epgservers" , $sdb );

if( $sdb ){
	print "<table width=\"80%\" border=\"0\" cellpadding=\"4\" cellspacing=\"0\">\n";
	print "<tr class=\"tableTitle\">\n";
	print "  <td>" . $lngstr['name'] . "</td>\n";
	print "  <td>" . $lngstr['active'] . "</td>\n";
	print "  <td>" . $lngstr['description'] . "</td>\n";
	print "</tr>\n";

	$rowstyle = 0;

	reset( $sdb );
	while( list( $sk , $sv ) = each( $sdb ) ){

		print "<tr class=\"tableBody\">\n";
		print "  <td><a href=\"editepgserver.php?id=" . $sv['id'] . "\">" .  $sv['name'] . "</a></td>\n";
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
