<?php

require "config.php";
require "common.php";
require "mysql.php";

$debug=false;

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
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML>
<HEAD>
<TITLE>NonameTV</TITLE>
<META http-equiv=Content-Type content="text/html; charset=utf-8" />
<LINK href="css/nonametv.css" rel=stylesheet>
</HEAD>

<BODY text=#000000 vLink=#000099 aLink=#0000ff link=#000099 bgColor=#f0f0f0 
leftMargin=0 topMargin=0 marginheight="0" marginwidth="0">

<?php

print "<h1>NonameTV</h1>\n";

?>

<h2>Admin section</h2>
<p>
Use the links in the admin menu section to administrate nonameTV.
Keep the access to these scripts controled.
</p>

<h2>Public section</h2>
<p>
The links in the public menu section are to be used for
public access on your site.
</p>

<?php

//
// disconnect from main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
        	sql_dodisconnect( $myc );
		break;
}

?>

</BODY>
</HTML>
