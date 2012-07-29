<?php

require "config.php";
require "common.php";
require "mysql.php";
require "admin/admins.php";

$debug = false;

//
// start session and check login
//
start_nonametv_session();
$dadmin = get_session_data();
if( $debug ) dbg( "admin" , $dadmin );

//
// read global config
//
if( $debug ) dbg( "dconf" , $dconf );

?>
<html>
<head>
<title>NonameTV</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
</head>
<body bgcolor="#aaaaaa" text="#000000" leftMargin=0 topMargin=0 marginwidth="0" marginheight="0">
<table height="100%" cellspacing=0 cellpadding=0 width="100%" border=0>
  <tbody> 
  <tr bgcolor=#aaaaaa> 
    <td align=left><img alt="NonameTV Admin Tool" src="images/logo-nonametv.png" border=0></td>
    <td align=left><font size="+1">NonameTV admin tool</font></td>
    <td valign=bottom align=right>
<?php

// if logged in, display logof
if( $dadmin ){
        print "      <a class=small href=\"admin/logout.php\" target=\"_top\">logout</a>\n";
        print "      &nbsp;|&nbsp\n";
        print "      <a class=small href=\"admin/myadmin.php\" target=\"main\">myadmin</a>\n";
        print "      &nbsp;|&nbsp;\n";

        // if user is master admin, display master admins page link
        if( $dadmin['ismaster'] ){
                print "      <a class=small href=\"admin/index.php\" target=\"main\">masteradmin</a>\n";
                print "      &nbsp;|&nbsp\n";
        }
}

?>
    </td>
  </tr>
  </tbody> 
</table>
</body>
</html>
