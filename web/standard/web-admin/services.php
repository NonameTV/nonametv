<?php

function sql_addService( $myc , $s )
{
	global $debug;

	$tblname = 'services';

	//
	// prvo insert novog service (name je unique)...
	//
	$q = "INSERT INTO " . $tblname . " SET id='" . $s['id'] . "'";
	if( $debug ) dbg( "INSERT INTO" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>MySQL: Can't add service " . $s['id'] . " to " . $tblname . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<pre>MySQL: Service " . $s['id'] . " added</pre>\n";

	//
	// nakon inserta azuriranje podataka...
	//
	sql_updateService( $myc , $s );

	return true;
}

function sql_updateService( $myc , $s )
{
	global $debug;

	$tblname = 'services';

	$ak = array_keys( $s );
	reset( $ak );
	while( list( $sak , $sav ) = each( $ak ) ){

		// fields that we don't update in mysql database
		if( $sav == 'oldsharedname' ) continue;
		if( $sav == 'oldfailover' ) continue;

		switch( $sav ){
			case 'somefieldname': // multiline text fields
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . join( "\n" , $s[$sav] ) . "' WHERE id='" . $s['id'] . "'";
				break;
			default: // simple fields
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . $s[$sav] . "' WHERE id='" . $s['id'] . "'";
		}

		if( $debug ) dbg( "UPDATE" , $q );

		if( !mysql_query( $q , $myc ) ) {
			print "<h4>MySQL: Can't update field " . $sav . " of service " . $s['id'] . "</h4>\n";
			print mysql_error( $myc ) . "\n";
			return false;
		}
	}

	print "<pre>MySQL: Service " . $s['id'] . " updated</pre>\n";

	return true;
}

function sql_deleteService( $myc , $s )
{
	global $debug;

	$tblname = 'services';

	$q = "DELETE FROM " . $tblname . " WHERE id='" . $s['id'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete service " . $s['id'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: Service " . $s['id'] . " deleted</h4>\n";

	return true;
}

function sql_loadServices( $myc , $kaj , $vrijednost )
{
	global $dconf,$debug;
	$cond = "";

	if( strlen( $kaj ) ){
		switch( $kaj ){
			case 'somefieldname': // walk through multiline text fields
				$cond = $kaj . " LIKE '%" . $vrijednost . "%'";
				return false; // ??????????
			default:
				$cond = $kaj . "='" . $vrijednost . "'";
				break;
		}
	}

	$chdb = sql_readtable( $myc , 'services' , $cond );
	if( ! $chdb ) return false;

	return $chdb;
}

function sql_findService( $myc , $kaj , $vrijednost )
{
	global $dconf,$debug;

	switch( $kaj ){
		case 'somefieldname': // walk through multiline text fields
			$cond = $kaj . " LIKE '%" . $vrijednost . "%'";
			return false; // ??????????
		default:
			$cond = $kaj . "='" . $vrijednost . "'";
			break;
	}

	$sn = sql_readtable( $myc , 'services' , $cond );
	if( $debug ) dbg("sql_findService" , $sn );

	if( sizeof( $sn ) == 1 ){
		// fix multiline text fields
		//$sn[0][somefieldname] = split ("\n", $sn[0][fwrules]);
		return $sn[0];
	} else return false;
}


function listServices( $chdb )
{
	global $dconf;

	reset( $chdb );
	while( list( $chk , $chv ) = each( $chdb ) ){

        	print "<tr class=\"";
		print ($chv['export']=='1') ? "chanExported" : "chanNotExported"
;
		print "\">\n";

        	print "<td><a href=\"editservice.php?service=" . $chv['id'] . "\">";
		print $chv['id'];
		if( $chv['logo'] ) print "<img src=\"" . $dconf['urllogos'] . "/44x44/" . $chv['xmltvid'] . ".png\" border=0>";
		print "</a></td>\n";

        	print "  <td>\n";
		print $chv['display_name'] . "<br>\n";
		print $chv['xmltvid'];
		print "  </td>\n";

        	print "  <td>\n";
		print $chv['grabber'] . "<br>\n";
		print $chv['grabber_info'];
		print "  </td>\n";

        	print "  <td>\n";
		print $chv['url'] . "<br>\n";
		print "  </td>\n";

        	print "</tr>\n";
	}
}


function set_service_defaults( $es )
{
	if( ! isset($es['id']) ) $es['id'] = '';
	if( ! isset($es['active']) ) $es['active'] = '0';
	if( ! isset($es['name']) ) $es['name'] = '';
	if( ! isset($es['operator']) ) $es['operator'] = '';
	if( ! isset($es['description']) ) $es['description'] = '';
	if( ! isset($es['charset']) ) $es['charset'] = 'utf8';

	return( $es );
}

?>
