<?php

function sql_addEPGserver( $myc , $s )
{
	global $debug;

	$tblname = 'epgservers';

	//
	// prvo insert novog epgservera (name je unique)...
	//
	$q = "INSERT INTO " . $tblname . " SET id='" . $s['id'] . "'";
	if( $debug ) dbg( "INSERT INTO" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>MySQL: Can't add epgserver " . $s['id'] . " to " . $tblname . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<pre>MySQL: EPGserver " . $s['id'] . " added</pre>\n";

	//
	// nakon inserta azuriranje podataka...
	//
	sql_updateEPGserver( $myc , $s );

	return true;
}

function sql_updateEPGserver( $myc , $s )
{
	global $debug;

	$tblname = 'epgservers';

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
			print "<h4>MySQL: Can't update field " . $sav . " of epgserver " . $s['id'] . "</h4>\n";
			print mysql_error( $myc ) . "\n";
			return false;
		}
	}

	print "<pre>MySQL: EPGserver " . $s['id'] . " updated</pre>\n";

	return true;
}

function sql_deleteEPGserver( $myc , $s )
{
	global $debug;

	$tblname = 'epgservers';

	$q = "DELETE FROM " . $tblname . " WHERE id='" . $s['id'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete epgserver " . $s['id'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: EPGserver " . $s['id'] . " deleted</h4>\n";

	return true;
}

function sql_loadEPGservers( $myc , $kaj , $vrijednost )
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

	$chdb = sql_readtable( $myc , 'epgservers' , $cond );
	if( ! $chdb ) return false;

	return $chdb;
}

function sql_findEPGserver( $myc , $kaj , $vrijednost )
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

	$sn = sql_readtable( $myc , 'epgservers' , $cond );
	if( $debug ) dbg("sql_findEPGserver" , $sn );

	if( sizeof( $sn ) == 1 ){
		// fix multiline text fields
		//$sn[0][somefieldname] = split ("\n", $sn[0][fwrules]);
		return $sn[0];
	} else return false;
}


function listEPGservers( $chdb )
{
	global $dconf;

	reset( $chdb );
	while( list( $chk , $chv ) = each( $chdb ) ){

        	print "<tr class=\"";
		print ($chv['export']=='1') ? "chanExported" : "chanNotExported"
;
		print "\">\n";

        	print "<td><a href=\"editepgserver.php?epgserver=" . $chv['id'] . "\">";
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


function listEPGserversLogos( $chdb )
{
	global $dconf;
	$last='';
	$ur=0;

	$chdb = array_sort( $chdb , "xmltvid" );

	reset( $chdb );
	while( list( $chk , $chv ) = each( $chdb ) ){

		if( $last != $chv['xmltvid'][0] ){

       			print "<tr class=\"tableTitle\">\n";
			print "  <td colspan=7><a name=\"" . $chv['xmltvid'][0] . "\">" . $chv['xmltvid'][0] . "</td>\n";
       			print "</tr>\n";
			$last = $chv['xmltvid'][0];
			$ur = 0;
		}

        	if( $ur == 0 ) print "<tr class=\"tableBody\">\n";

        	print "  <td class=\"";
		print ($chv['export']=='1') ? "chanExported" : "chanNotExported";
		print "\" align=\"center\">\n";

		print "    <a href=\"programview.php?id=" . $chv['id'] . "\">";
		print "      <b>" . $chv['display_name'] . "</b><br>\n";
		print "      <b>" . $chv['xmltvid'] . "</b><br>\n";
		if( $chv['logo'] == "1" ) print "      <img src=\"" . $dconf['urllogos'] . "/44x44/" . $chv['xmltvid'] . ".png\" border=\"0\">\n";
		print "    </a>\n";
		print "  </td>\n";

		$ur++;

        	if( $ur >= $dconf['channsinline'] ){
			$ur = 0;
			print "</tr>\n";
		}
	}
}

function set_epgserver_defaults( $es )
{
	if( ! isset($es['id']) ) $es['id'] = '';
	if( ! isset($es['active']) ) $es['active'] = '0';
	if( ! isset($es['name']) ) $es['name'] = '';
	if( ! isset($es['description']) ) $es['description'] = '';
	if( ! isset($es['vendor']) ) $es['vendor'] = '';
	if( ! isset($es['type']) ) $es['type'] = '';

	return( $es );
}

?>
