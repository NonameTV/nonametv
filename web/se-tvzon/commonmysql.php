<?php

function sql_connect($server,$username,$password,$database)
{
	global $dconf,$debug;

	if( !strlen(trim( $server )) ){
		print "<h4>MySQL server not specified</h4>\n";
		return false;
	}

	if( !strlen(trim( $username )) ){
		print "<h4>MySQL server username not specified</h4>\n";
		return false;
	}

	if( $dconf[verbose] )
		print "<pre>Connecting to mysql://" . $username . "@" . $server . "/" . $database . "...</pre>\n";

	if( !strlen(trim( $password )) ){
		$myc = mysql_connect( $server , $username );
	} else {
		$myc = mysql_connect( $server , $username , $password );
	}
	if( ! $myc ){
		print "<h4>Unable to connect to " . $server . "</h4>\n";
		return false;
	}

	if( $dconf[verbose] )
		print "Connected to MySQL server " . mysql_get_server_info() . " at " . mysql_get_host_info() . "\n";

	if( !mysql_select_db( $database ) ){
		print "<h4>Could not select database " . $database . "</h4>\n";
		return false;
	}

	if( $dconf[verbose] )
		print "<pre>Database " . $database . " selected</pre>\n";

	return $myc;
}

function sql_disconnect( $myc , $server )
{
	global $dconf;

	if( $dconf[verbose] )
		print "<pre>Closing connection to MySQL server " . $server . "...</pre>\n";

	mysql_close ( $myc );
	if( ! $myc ){
		print "<h4>Unable to disconnect from " . $server . "</h4>\n";
		return false;
	}

	return true;
}


function sql_gettable( $myc  , $tblname , $condition )
{
	global $debug;

	if( !strlen(trim( $tblname )) ){
		print "<pre>Table name not specified</pre>\n";
		return false;
	}

	$q = "SELECT * FROM " . $tblname;
	if( strlen(trim($condition)) ) $q .= " WHERE " . $condition;
	if( $debug ) dbg( "SQL: sql_gettable query" , $q );

	$result = mysql_query( $q , $myc );
	if( ! $result ){
		//print "<pre>" . ( $myc ) . "</pre>\n";
		return false;
	}

	while ($row = mysql_fetch_assoc($result)) {
		$tmpdb[] = $row;
	}

	mysql_free_result($result);

	return $tmpdb;
}
   
function sql_getrecord( $myc  , $tblname , $condition )
{
	global $debug;

	if( !strlen(trim( $tblname )) ){
		print "<pre>Table name not specified</pre>\n";
		return false;
	}

	$q = "SELECT * FROM " . $tblname;
	if( strlen(trim($condition)) ) $q .= " WHERE " . $condition;
	if( $debug ) dbg( "SQL: sql_getrecord query" , $q );

	$result = mysql_query( $q , $myc );
	if( $debug ) dbg( "SQL: sql_getrecord result" , $result );
	if( ! $result ){
		//print "<pre>" . ( $myc ) . "</pre>\n";
		return false;
	}

	$row = mysql_fetch_assoc($result);
	if( $debug ) dbg( "SQL: sql_getrecord row" , $row );

	mysql_free_result($result);

	return $row;
}

?>
