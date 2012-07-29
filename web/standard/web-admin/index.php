<?php

require "config.php";
require "common.php";
require "mysql.php";
require "admin/admins.php";

//
// start session and check login
//
start_nonametv_session();
$dadmin = get_session_data();

//
// read global config
//
if( $debug ) dbg( "dconf" , $dconf );

?>
<html>
<head>
<title>NonameTV</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta http-equiv="description" content="NonameTV - XMLTV">
<meta http-equiv="Replay to" content="tcrnek@gonix.net">
<meta http-equiv="Keywords" content="XMLTV, backend">
<meta http-equiv="address" content="Zagreb, Croatia">
<link rel="shortcut icon" href="images/favicon.ico" type="image/x-icon" />
</head>
<frameset rows="88,*" frameborder="NO" border="0" framespacing="0"> 
  <frame name="top" scrolling="NO" noresize src="topframe.php" >
<?php

  if( $dadmin ){

?>
  <frameset cols="120,*" frameborder="NO" border="0" framespacing="0"> 
    <frame name="menu" noresize src="menu.php">
    <frame name="main" src="main.php">
  </frameset>
<?php

  } else {

?>
    <frame name="login" scrolling="YES" noresize src="admin/login.php">
<?php

  }

?>
</frameset>
<noframes>
<body bgcolor="#FFFFFF" text="#000000">
</body>
</noframes> 
</html>
