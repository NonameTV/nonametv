<?php

function db_loadChannels( $kaj , $vrijednost )
{
        global $dconf;
	global $myc;

        switch( $dconf['dbtype'] ){
		case 'mysql':
                	$tdb = sql_loadChannels( $myc , $kaj , $vrijednost );
                	return $tdb;
        }

	return false;
}

function sql_addChannel( $myc , $s )
{
	global $debug;

	$tblname = 'channels';

	//
	// prvo insert novog channela (name je unique)...
	//
	$q = "INSERT INTO " . $tblname . " SET id='" . $s['id'] . "'";
	if( $debug ) dbg( "INSERT INTO" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>MySQL: Can't add channel " . $s['id'] . " to " . $tblname . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<pre>MySQL: Channel " . $s['id'] . " added</pre>\n";

	//
	// nakon inserta azuriranje podataka...
	//
	sql_updateChannel( $myc , $s );

	return true;
}

function sql_updateChannel( $myc , $s )
{
	global $debug;

	$tblname = 'channels';

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
			print "<h4>MySQL: Can't update field " . $sav . " of channel " . $s['id'] . "</h4>\n";
			print mysql_error( $myc ) . "\n";
			return false;
		}
	}

	print "<pre>MySQL: Channel " . $s['id'] . " updated</pre>\n";

	return true;
}

function sql_deleteChannel( $myc , $s )
{
	global $debug;

	$q = "DELETE FROM files WHERE channelid='" . $s['id'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete files for channel " . $s['id'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}
	$q = "DELETE FROM programs WHERE channel_id='" . $s['id'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete programs for channel " . $s['id'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}
	$q = "DELETE FROM services WHERE dbchid='" . $s['id'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete services for channel " . $s['id'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	$tblname = 'channels';

	$q = "DELETE FROM " . $tblname . " WHERE id='" . $s['id'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete channel " . $s['id'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: Channel " . $s['id'] . " deleted</h4>\n";

	return true;
}

function sql_loadChannels( $myc , $kaj , $vrijednost )
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

	$chdb = sql_readtable( $myc , 'channels' , $cond );
	if( ! $chdb ) return false;

	array_sort( $chdb , "xmltvid" );

	return $chdb;
}

function sql_findChannel( $myc , $kaj , $vrijednost )
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

	$sn = sql_readtable( $myc , 'channels' , $cond );
	if( $debug ) dbg("sql_findChannel" , $sn );

	if( sizeof( $sn ) == 1 ){
		// fix multiline text fields
		//$sn[0][somefieldname] = split ("\n", $sn[0][fwrules]);
		return $sn[0];
	} else return false;
}


function listChannels( $chdb )
{
	global $dconf;

	reset( $chdb );
	while( list( $chk , $chv ) = each( $chdb ) ){

        	print "<tr class=\"";
		print ($chv['export']=='1') ? "chanExported" : "chanNotExported"
;
		print "\">\n";

        	print "<td><a href=\"editchannel.php?channel=" . $chv['id'] . "\">";
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


function listChannelsLogos( $chdb )
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

function set_channel_defaults( $ch )
{
	if( ! isset($ch['display_name']) ) $ch['display_name'] = '';
	if( ! isset($ch['xmltvid']) ) $ch['xmltvid'] = '';
	if( ! isset($ch['chgroup']) ) $ch['chgroup'] = '';
	if( ! isset($ch['grabber']) ) $ch['grabber'] = '';
	if( ! isset($ch['export']) ) $ch['export'] = '0';
	if( ! isset($ch['grabber_info']) ) $ch['grabber_info'] = '';
	if( ! isset($ch['logo']) ) $ch['logo'] = '0';
	if( ! isset($ch['def_pty']) ) $ch['def_pty'] = '';
	if( ! isset($ch['def_cat']) ) $ch['def_cat'] = '';
	if( ! isset($ch['sched_lang']) ) $ch['dsched_lang'] = '';
	if( ! isset($ch['empty_ok']) ) $ch['empty_ok'] = '0';

	return( $ch );
}

function load_channelgroups( $myc )
{
	$chg = sql_readtable( $myc , 'channelgroups' , "" );

	return( $chg );
}

?>
