<?php

function start_nonametv_session()
{
	global $debug;

	// session name
	session_name("sesNonameTV");

	// session duration: 10 minutes is default
	//session_set_cookie_params( 600 );

	// start the session
	session_start();
}

function get_session_data()
{

	if( isset( $_SESSION['username'] ) ){
		$dad['username'] = $_SESSION['username'];
		$dad['fullname'] = $_SESSION['fullname'];
		$dad['email'] = $_SESSION['email'];
		$dad['language'] = $_SESSION['language'];
		$dad['ismaster'] = $_SESSION['ismaster'];
		$dad['roleeditor'] = $_SESSION['roleeditor'];
		return $dad;
	}
// comment this "return true" to enable session based logon
//return true;

	return false;
}

function notlogged_redirect()
{

?>
<html>
<head>
<title>Login required</title>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
<link href="css/nonametv.css" rel=stylesheet>
</head>
<body bgcolor="#FFFFFF" text="#000000">

<h1>This NonameTV page can not be displayed</h1>
<h3>possible reasons are:</h3>
<ul>
<li>you have opened this page from outside of NonameTV structure</li>
<li>you did not login to NonameTV</li>
<li>your login session time has expired</li>
</ul>

<?php
	flush();
	sleep(10);

	print "<script language=javascript>\n";
	print "  top.location.href = \"index.php\";\n";
	print "</script>\n";
}

function fetch_admin_data( $user )
{
	global $myc;

	return sql_getrecord( $myc  , "admins" , "username='" . $user . "'" );
}

function login_check( $user , $pass )
{
	global $debug;

	$dad = fetch_admin_data( $user );
	if( $debug ) dbg( "fetch_admin_data" , $dad );
	if( !$dad ) return false;

	if( $dad['username'] == $user ){

		if( crypt( $pass , $dad['password'] ) == $dad['password'] ){
			// password verified
			return $dad;
		}
	}

	return false;
}

function sql_dodajAdmin( $myc , $s )
{
	global $debug,$dconf;

	$tblname = 'admins';

	//
	// prvo insert novog admin (username je unique)...
	//
	$q = "INSERT INTO " . $tblname . " SET username='" . $s['username'] . "'";
	if( $debug ) dbg( "INSERT INTO" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>MySQL: Can't add admin " . $s['username'] . " to " . $tblname . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<pre>MySQL: Admin " . $s['username'] . " added</pre>\n";

	//
	// nakon inserta azuriranje podataka...
	//
	sql_azurirajAdmin( $myc , $s );

	return true;
}

function sql_azurirajAdmin( $myc , $s )
{
	global $debug,$dconf;

	$tblname = 'admins';

	$ak = array_keys( $s );
	reset( $ak );
	while( list( $sak , $sav ) = each( $ak ) ){

		// fields that we don't update in mysql database
		//if( $sav == 'oldsharedname' ) continue;
		//if( $sav == 'oldfailover' ) continue;

		switch( $sav ){
			//case 'fwrules': // multiline text fields
			//case 'unwinsservers':
				//$q = "UPDATE " . $tblname . " SET " . $sav . "='" . join( "\n" , $s[$sav] ) . "' WHERE username='" . $s['username'] . "'";
				//break;
			default: // simple fields
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . $s[$sav] . "' WHERE username='" . $s['username'] . "'";
		}

		if( $debug ) dbg( "UPDATE" , $q );

		if( !mysql_query( $q , $myc ) ) {
			print "<h4>MySQL: Can't update field " . $sav . " of admin " . $s['username'] . "</h4>\n";
			print mysql_error( $myc ) . "\n";
			return false;
		}
	}

	print "<pre>MySQL: Admin " . $s['username'] . " updated</pre>\n";

	return true;
}

function sql_brisiAdmin( $myc , $s )
{
	global $debug,$dconf;

	$tblname = 'admins';

	$q = "DELETE FROM " . $tblname . " WHERE username='" . $s['username'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete admin " . $s['username'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: Admin " . $s['username'] . " deleted</h4>\n";

	return true;
}

function sql_ucitajAdmins( $myc )
{
	global $dconf;

	$sndb = sql_gettable( $myc , 'admins' , "" );
	if( ! $sndb ) return false;

	array_sort( $sndb , "username" );

	// convert multiline text fields to array
	reset( $sndb );
	while( list( $k,$v ) = each( $sndb ) ){
		//$sndb[$k]['unwinsservers'] = split ("\n", $v['unwinsservers']);
	}

	return $sndb;
}

function sql_nadjiAdmin( $myc , $kaj , $vrijednost )
{
	global $dconf,$debug;

	switch( $kaj ){
		//case 'fwrules': // walk through multiline text fields
		//case 'unwinsservers':
			//$cond = $kaj . " LIKE '%" . $vrijednost . "%'";
			//return false; // ??????????
		default:
			$cond = $kaj . "='" . $vrijednost . "'";
			break;
	}

	$sn = sql_gettable( $myc , 'admins' , $cond );
	if( $debug ) dbg("sql_nadjiAdmin" , $sn );

	if( sizeof( $sn ) == 1 ){
		// slaganje multiline text polja
		//$sn[0]['fwrules'] = split ("\n", $sn[0]['fwrules']);
		return $sn[0];
	} else return false;
}

function izlistajAdmins($adb)
{
        global $zone;
        
        for( $i=0 ; $i<sizeof($adb) ; $i++ ){
                print "<tr class=\"tableBody\">\n";
                print "  <td><a href=\"editadmin.php?admin=" . $adb[$i]['username'] . "\">" . $adb[$i]['username']
 . "</a></td>\n";
                print "  <td>" . $adb[$i]['fullname'] . "</td>\n";
                print "  <td>" . $adb[$i]['email'] . "</td>\n";
                print "  <td align=\"center\"><img src=\"/images/icons/";
			if( $adb[$i]['ismaster'] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
			print  "\"></td>\n";
                print "  <td align=\"center\"><img src=\"/images/icons/";
			if( $adb[$i]['roleeditor'] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
			print  "\"></td>\n";
/*
                print "  <td align=\"center\"><img src=\"/images/icons/";
			if( $adb[$i]['canhosts'] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
			print  "\"></td>\n";
                print "  <td align=\"center\"><img src=\"/images/icons/";
			if( $adb[$i]['candns'] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
			print  "\"></td>\n";
                print "  <td align=\"center\"><img src=\"/images/icons/";
			if( $adb[$i]['candhcp'] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
			print  "\"></td>\n";
*/
                print "</tr>\n";
        }
}

function privilege_check( $dad , $mn , $redirect )
{
	if( ( $dad[$mn] != 'true' ) && ( $dad['ismaster'] != 'true' )){
		print "<h2>Dear " . $dad['fullname'] . ",</h2>\n";
		print "<h2>You have no access to this NonameTV page.</h2>\n";
		//flush();
		//sleep(5);
        
		//print "<script language=javascript>\n";
		//print "  top.location.href = \"/index.php\";\n";
		//print "</script>\n";

		return false;
	}

	return true;
}  

?>
