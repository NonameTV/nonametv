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
       		if( !$myc ) exit;      
		break;
}

?>
<html>
<head>
<title>Program</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
<link href="css/categories.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">

<?php

//
// main
//
$channel_id = $_REQUEST['id'];

$chann = sql_findChannel( $myc , 'id' , $channel_id );

print "<h1>Programs for " . $chann['display_name'] . "</h1>\n";
if( $chann['logo'] ){
	print "<img src=\"" . $dconf['urllogos'] . "/" . $chann['xmltvid'] . ".png\">\n";
}
print "<h4>ID: " . $chann['id'] . "</h4>\n";
print "<h4>XMLTV ID: " . $chann['xmltvid'] . "</h4>\n";
print "<h4>Language: " . $chann['sched_lang'] . "</h4>\n";
print "<h4>Grabber : " . $chann['grabber'] . "</h4>\n";
print "<h4>Grabber info : " . $chann['grabber_info'] . "</h4>\n";
print "<h4>Exported: " . $chann['export'] . "</h4>\n";

$pdb = sql_findProgram( $myc , $channel_id , '' , '' );
if( $debug ) dbg( "programs" , $pdb );

print "<h4>Total: " . sizeof( $pdb ) . " items found</h4>\n";

if( $pdb ){
	print "<table width=\"75%\">\n";
	print "<tr class=\"tableTitle\">\n";
	print "  <td>Start time</td>\n";
	print "  <td>End time</td>\n";
	print "  <td>Title</td>\n";
	print "  <td>Description</td>\n";
	print "  <td>Category</td>\n";
	print "</tr>\n";

	listPrograms( $chann['id'] , $pdb );

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
