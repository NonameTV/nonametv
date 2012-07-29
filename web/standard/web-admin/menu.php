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
if( $debug ) dbg("admin",$dadmin);
if( !$dadmin ) notlogged_redirect();

//
// read global config
//
if( $debug ) dbg( "dconf" , $dconf );

?>
<HTML>
<HEAD>
<TITLE>nonameTV global menu</TITLE>
<META http-equiv=Content-Type content="text/html; charset=utf-8">
<LINK href="css/nonametv.css" rel=stylesheet>
</HEAD>
<BODY text=#000000 vLink=#000099 aLink=#0000ff link=#000099 bgColor=#aaaaaa 
leftMargin=0 topMargin=0 marginheight="0" marginwidth="0">
<TABLE width="100%">
  <TBODY> 
  <TR> 
    <TD class=tableMenuTitle>Admin</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="channelslist.php">Channels</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="programslist.php">Programs</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listtranscat.php">Categories</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenuTitle>EPG servers</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listepgservers.php">Servers</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listnetworks.php">Networks</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listtses.php">TSes</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listservices.php">Services</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="viewepg.php">View</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenuTitle>Misc</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="importers.php">importers</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenuTitle>Logs</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="log/">Log directory</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenuTitle>Run</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="export.php?what=channels">export channels</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenuTitle>Public</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listchannels.php">List channels</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="listrss.php">List RSS</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="nowshowing.php">Now showing</A></TD>
  </TR>
  <TR> 
    <TD class=tableMenuTitle>Test</TD>
  </TR>
  <TR> 
    <TD class=tableMenu><A target=main href="test/phpinfo.php">PHPinfo</A></TD>
  </TR>
  </TBODY> 
</TABLE>
</BODY>
</HTML>
