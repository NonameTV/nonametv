<?php

function sql_doconnect()
{
	global $dconf;

	if( !strlen(trim( $dconf['dbhost'] )) ){
		print "<h4>MySQL server not specified</h4>\n";
		return false;
	}

	if( !strlen(trim( $dconf['dbuser'] )) ){
		print "<h4>MySQL server username not specified</h4>\n";
		return false;
	}

	if( $dconf['verbose'] ) print "<pre>\n";

	//
	// first try to connect to master server
	//
	$mysid = 1;
	$mysserv = $dconf['dbhost'];
	$mysuser = $dconf['dbuser'];
	$myspass = $dconf['dbpass'];
	$mysdb = $dconf['dbname'];

	$myc = false;

	while( true ){
		if( $dconf['verbose'] )
			print "Connecting to mysql://" . $mysuser . "@" . $mysserv . "/" . $mysdb . "...\n";

		if( !strlen(trim( $myspass )) ){
			$myc = mysql_connect( $mysserv , $mysuser );
		} else {
			$myc = mysql_connect( $mysserv , $mysuser , $myspass );
		}

		if( ! $myc ) print "<h4>Unable to connect to " . $mysserv . "</h4>\n";
		else {
			if( !mysql_select_db( $mysdb , $myc ) ){
				print "<h4>Could not select database " . $mysdb . "</h4>\n";
			}
		}

		flush();

		if( $myc || ( $mysid > 1 ) ) break;
		else {
			//
			// try next secondary server
			//
			$mysid = 2;
			$mysserv = $dconf['dbsechost'];
			$mysuser = $dconf['dbsecuser'];
			$myspass = $dconf['dbsecpass'];
			$mysdb = $dconf['dbsecname'];  
		}
	}

	if( $dconf['verbose'] ){
		print "Connected to MySQL server " . mysql_get_server_info() . " at " . mysql_get_host_info() . "\n";
		print "Selected database: " . $mysdb . "\n";
		print "Client encoding: " . mysql_client_encoding() . "\n";
	}

	if( $dconf['verbose'] ) print "</pre>\n";

	sql_setcharset( $myc , 'utf8' );

	return $myc;
}

function sql_dodisconnect( $myc )
{
	global $dconf;

	if( $dconf['verbose'] ) print "<pre>\n";

	if( $dconf['verbose'] )
		print "Disconnecting from " . $dconf['dbuser'] . "@" . $dconf['dbhost'] . "...\n";

	mysql_close ( $myc );
	if( ! $myc ){
		print "<h4>Unable to disconnect from " . $dconf['dbhost'] . "</h4>\n";
		return false;
	}

	if( $dconf['verbose'] ) print "</pre>\n";

	return true;
}

function sql_setcharset( $myc , $cs )
{
	global $dconf;

	$q = "SET NAMES '" . $cs . "'";

	if( !mysql_query( $q , $myc ) ) {
		print("Can't SET NAMES to " . $cs . "\n");
		print mysql_error( $myc ) . "\n";
		return false;
	}

	$q = "SET CHARACTER SET " . $cs;

	if( !mysql_query( $q , $myc ) ) {
		print("Can't SET CHARACTER SET to " . $cs . "\n");
		print mysql_error( $myc ) . "\n";
		return false;
	}

	if( $dconf['verbose'] ) print "<h4>MySQL: Character set to " . $cs . "</h4>\n";

	return true;
}

function sql_emptytable( $myc , $tblname )
{
	$q = "DELETE FROM " . $tblname;

	if( !mysql_query( $q , $myc ) ) {
		print("Can't empty table " . $tblname . " in " . $dconf['dbname'] . "\n");
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: Table " . $tblname . " is now empty</h4>\n";

	return true;
}

function sql_readtable( $myc  , $tblname , $condition )
{
        global $debug;

        if( !strlen(trim( $tblname )) ){
                print "<pre>Table name not specified</pre>\n";
                return false;
        }

        $q = "SELECT * FROM " . $tblname;
        if( strlen(trim($condition)) ) $q .= " WHERE " . $condition;
        if( $debug ) dbg( "SQL: sql_readtable query" , $q );

        $result = mysql_query( $q , $myc );
        if( ! $result ){
                //print "<pre>" . ( $myc ) . "</pre>\n";
                return false;
        }

        while ($row = mysql_fetch_assoc($result)) {
                $tmpdb[] = $row;
        }

        mysql_free_result($result);

        if( isset( $tmpdb ) ) return $tmpdb;
	else return false;
}

function sql_gettable( $myc  , $tblname , $condition )
{
	return sql_readtable( $myc  , $tblname , $condition );
}

function sql_getrecord( $myc  , $tblname , $condition )
{
	global $debug,$dconf;

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

function sql_listfields( $myc , $tblname )
{
	global $debug,$dconf;

	$result = mysql_query("SHOW COLUMNS FROM " . $tblname , $myc );
	if( ! $result ){
		print mysql_error( $myc ) . "\n";
		return false;
	}

	if( mysql_num_rows( $result ) > 0 ){
		while( $row = mysql_fetch_assoc( $result ) ){
			$fields[] = $row;
		}
	}

	mysql_free_result($result);

	return( $fields );
}
?>
