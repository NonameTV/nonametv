<?php

require "config.php";
require "common.php";
require "mysql.php";
#require "commonmysql.php";
require "channels.php";

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

?>
<html>
<head>
<title>Channels</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<h1>Channels</h1>

<?php

//
// main
//

$chdb = db_loadChannels( "" , "" );
if( $debug ) dbg( "channels" , $chdb );

if( $chdb ){
	$chdb = array_sort( $chdb , "display_name" );

	print "<table width=\"75%\">\n";

	listChannelsLogos( $chdb );

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
