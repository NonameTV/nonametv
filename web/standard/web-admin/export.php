<?php

require "config.php";
require "common.php";
require "mysql.php";
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
<title>Export</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

//
// main
//
if( $_REQUEST['what'] ) $what = $_REQUEST['what'];
else {
}

switch( $what ){
	case "channels":
		$cmd = $dconf['sudo'] . " -u " . $dconf['nonametvuser'] . " " . $dconf['scriptexportchannels'];
		break;
	default:
		break;
}

print "<h3>Executing: " . $cmd . "</h3>\n";

system ( $cmd );

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
