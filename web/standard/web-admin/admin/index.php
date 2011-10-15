<?php

require "../config.php";
require "../common.php";
require "../mysql.php";
require "admins.php";

$debug = false;

//
// check NonameTV user
//
start_nonametv_session();
$dadmin = get_session_data();
if( !$dadmin ) notlogged_redirect();

?>
<html>
<head>
<title>NonameTV Master Administrator Page</title>
<meta http-equiv="Content-Type" content="text/html; charset=<?php print $lngstr[codepage]; ?>">
<link href="../css/nonametv.css" rel=stylesheet>
</head>

<body bgcolor="#FFFFFF" text="#000000">
<h1>NonameTV Master Administrator Page</h1>

<?php

if( ! $dadmin['ismaster'] ){
	print "<h2>Dear " . $dadmin['username'] . ",</h2>\n";
	print "<h2>Only NonameTV master administrators have access to this page.</h2>\n";
        flush();
        sleep(3);

        print "<script language=javascript>\n";
        print "  top.location.href = \"index.php\";\n";
        print "</script>\n";
}

if( $debug ) dbg( "dconf" , $dconf );
if( $debug ) dbg( "dadmin" , $dadmin );

//
// connect to main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
		$myc = sql_doconnect();
		break;
}

//
// main
//

if( $debug ) dbg( "_POST" , $_POST );
if( $debug ) dbg( "_REQUEST" , $_REQUEST );

if( isset( $_REQUEST['conf'] ) ) $conf = $_REQUEST['conf'];

reloadUrl("Add new administrator","editadmin.php?action=new" );

$admdb = sql_ucitajAdmins( $myc );
if( $admdb ){
	sort( $admdb );
	if( $debug ) dbg( "admins database" , $admdb );

	print "<table width=\"75%\">\n";
	print "<tr class=\"tableTitle\">\n";
	print "  <td>username</td>\n";
	print "  <td>name</td>\n";
	print "  <td>email</td>\n";
	print "  <td align=\"center\">master</td>\n";
	print "  <td align=\"center\">subnets</td>\n";
	print "  <td align=\"center\">hosts</td>\n";
	print "  <td align=\"center\">dns</td>\n";
	print "  <td align=\"center\">dhcp</td>\n";
	print "</tr>\n";

	izlistajAdmins( $admdb );

	print "</table>\n";

        $aidb = db_readdatachange( $myc , "admins" );
        if( $debug ) dbg( "aidb" , $aidb );

        pokaziAI($aidb);
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
