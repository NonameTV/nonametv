<?php

require "config.php";
require "common.php";
require "mysql.php";
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

//$lngstr = loadlanguage( 'importers' );
//if( $debug ) dbg("language strings" , $lngstr );

?>
<html>
<head>
<title>Active Importers</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

//print "<h1>" . $lngstr['title'] . "</h1>\n";
//print "<p>" . $lngstr['headertext'] . "</p>\n";

//
// main
//

$channels = sql_loadChannels( $myc , NULL , NULL );
if( $debug ) dbg( "channels" , $channels );

reset( $channels );
while( list( $k , $v ) = each( $channels ) ){

	if( ! $v['export'] ) continue;

	$importers[$v['grabber']][] = $v['display_name'];
}
if( $debug ) dbg( "importers" , $importers );

reset($importers);
while( list( $k , $v ) = each( $importers ) ){

        print "<h2>" . $k . "(" . sizeof( $v ) . ")</h2>\n";

	$v = array_sort( $v , 'display_name' );

	reset( $v );
	while( list( $gck , $gcv ) = each( $v ) ){
		print "&nbsp;&nbsp;" . $gcv . "<br>\n";
	}


/*
		print "<table width=\"80%\" border=\"0\" cellpadding=\"4\" cellspacing=\"0\">\n";
		print "<tr class=\"tableTitle\">\n";
		print "  <td width=\"25%\" nowrap=\"nowrap\">" .  $lngstr['channel'] . "</td>\n";
		print "  <td width=\"25%\" nowrap=\"nowrap\">" .  $lngstr['xmltvid'] . "</td>\n";
		print "  <td width=\"25%\" nowrap=\"nowrap\">" .  $lngstr['datasource'] . "</td>\n";
		print "</tr>\n";

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
*/
}

//print "<p>" . $lngstr['footertext'] . "</p>\n";

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
