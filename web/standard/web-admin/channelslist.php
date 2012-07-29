<?php

require "config.php";
require "common.php";
require "mysql.php";
require "channels.php";
require "admin/admins.php";

$debug=false;

//
// start session and check login
//
start_nonametv_session();
$dadmin = get_session_data();
if( $debug ) dbg( "admin" , $dadmin );
if( !$dadmin ) notlogged_redirect();

//
// read global config
//
if( $debug ) dbg( "dconf" , $dconf );

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

<form name="new">
<input type="button" value="Add new channel" class="gumb" onClick="javascript:window.location.href='editchannel.php?action=new'">
</form>

<?php

//
// main 
//   

$chgdb = load_channelgroups( $myc );
if( $debug ) dbg( "channel groups" , $chgdb );

reset($chgdb);
while( list( $cgk , $cgv ) = each( $chgdb ) ){

        $chdb = db_loadChannels( "chgroup" , $cgv['abr'] );
        if( $debug ) dbg( "channels" , $chdb );

        print "<h2>" . $cgv['display_name'] . " (" . sizeof($chdb) . ")</h2>\n";

	if( $chdb ){
		$chdb = array_sort( $chdb , $cgv['sortby'] );

		print "<table width=\"75%\">\n";
		print "<tr class=\"tableTitle\">\n";
		print "  <td>Channel</td>\n";
		print "  <td>Display Name / XMLTV ID</td>\n";
		print "  <td>Grabber</td>\n";
		print "  <td>URL</td>\n";
		print "</tr>\n";

		listChannels( $chdb );

		print "</table>\n";
	}
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
