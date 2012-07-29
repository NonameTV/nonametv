<?php

require "config.php";
require "common.php";
require "mysql.php";
#require "commonmysql.php";
require "channels.php";
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

$lngstr = loadlanguage( 'listchannels' );
if( $debug ) dbg("language strings" , $lngstr );

?>
<html>
<head>
<title>List channels</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
<link href="css/listchannels.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

print "<h1>" . $lngstr['title'] . "</h1>\n";
print "<p>" . $lngstr['headertext'] . "</p>\n";

//
// main
//

$chgdb = load_channelgroups( $myc );
if( $debug ) dbg( "channel groups" , $chgdb );

reset($chgdb);
while( list( $cgk , $cgv ) = each( $chgdb ) ){

        print "<h2>" . $cgv['display_name'] . "</h2>\n";

        $chdb = db_loadChannels( "chgroup" , $cgv['abr'] );
        if( $debug ) dbg( "channels" , $chdb );

	if( $chdb ){
		$chdb = array_sort( $chdb , $cgv['sortby'] );

		print "<table width=\"80%\" border=\"0\" cellpadding=\"4\" cellspacing=\"0\">\n";
		print "<tr class=\"tableTitle\">\n";
		print "  <td width=\"25%\" nowrap=\"nowrap\">" .  $lngstr['channel'] . "</td>\n";
		print "  <td width=\"25%\" nowrap=\"nowrap\">" .  $lngstr['xmltvid'] . "</td>\n";
		print "  <td width=\"25%\" nowrap=\"nowrap\">" .  $lngstr['datasource'] . "</td>\n";
		print "</tr>\n";

		$rowstyle = 0;

		reset( $chdb );
		while( list( $chk , $chv ) = each( $chdb ) ){

			if( $chv['export'] != "1" ) continue;

			print "<tr class=\"listchannels_rowstyle" . $rowstyle . "\">\n";
			print "  <td nowrap=\"nowrap\">\n";
			print "    <div align=\"center\">\n";
			if( strlen(trim($chv['url'])) ) print "      <a href=\"" . $chv['url'] . "\" target=\"_blank\">\n";
			if( $chv['logo'] == "1" ) print "      <img src=\"" . $dconf['urllogos'] . "/44x44/" . $chv['xmltvid'] . ".png\" alt=\"" . $chv['display_name'] . "\" width=\"44\" height=\"44\" border=\"0\" /><br>\n";
			print "      " . $chv['display_name'] . "<br>\n";
			if( strlen(trim($chv['url'])) ) print "      " . $chv['url'] . "</a>\n";

			print "    </div>\n";
			print "  </td>\n";

			print "  <td nowrap=\"nowrap\">" .  $chv['xmltvid'] . "</td>\n";
			print "  <td nowrap=\"nowrap\">" .  $chv['grabber'] . "</td>\n";
			print "</tr>\n";

			$rowstyle = 1 - $rowstyle;
		}

		print "</table>\n";
	}
}

print "<p>" . $lngstr['footertext'] . "</p>\n";

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
