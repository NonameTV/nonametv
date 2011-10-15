<?php

require "config.php";
require "common.php";
require "mysql.php";
require "transcat.php";

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
<title>Categories</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<h1>Categories</h1>

<?php

//
// main 
//   

$trdb =  db_loadTransCats( "" );
if( $debug ) dbg( "transcats" , $trdb );

if( $trdb ){
	$trdb = array_sort( $trdb , "type" );

	print "<table width=\"75%\">\n";
	print "<tr class=\"tableTitle\">\n";
	print "  <td>Type</td>\n";
	print "  <td>Original</td>\n";
	print "  <td>Category</td>\n";
	print "  <td>Program Type</td>\n";
	print "</tr>\n";

	listTransCats( $trdb );

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
