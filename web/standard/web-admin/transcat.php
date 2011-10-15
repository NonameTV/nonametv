<?php

function db_loadTransCats( $uvjet  )
{
        global $dconf;
	global $myc;

        switch( $dconf['dbtype'] ){
		case 'mysql':
                	$tdb = sql_loadTransCats( $myc , $uvjet );
                	return $tdb;
        }

	return false;
}

function sql_updateTransCat( $myc , $s )
{
	global $debug;

	$tblname = 'trans_cat';

	$ak = array_keys( $s );
	reset( $ak );
	while( list( $sak , $sav ) = each( $ak ) ){

		// fields that we don't update in mysql database
		//if( $sav == 'oldsharedname' ) continue;
		//if( $sav == 'oldfailover' ) continue;

		switch( $sav ){
			case 'somefieldname': // multiline text fields
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . join( "\n" , $s[$sav] ) . "' WHERE `type`='" . $s['type'] . "' AND `original`='" . $s['original'] . "'";
				break;
			default: // simple fields
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . $s[$sav] . "' WHERE `type`='" . $s['type'] . "' AND `original`='" . $s['original'] . "'";
		}

		if( $debug ) dbg( "UPDATE" , $q );

		if( !mysql_query( $q , $myc ) ) {
			print "<h4>MySQL: Can't update field " . $sav . " of trans_cat type " . $s['type'] . " and original "  . $s['original'] . "</h4>\n";
			print mysql_error( $myc ) . "\n";
			return false;
		}
	}

	print "<pre>MySQL: TransCat type " . $s['type'] . " and original "  . $s['original'] . " updated</pre>\n";

	return true;
}

function sql_deleteTransCat( $myc , $s )
{
	global $debug;

	$tblname = 'trans_cat';

	$q = "DELETE FROM " . $tblname . " WHERE `type`='". $s['type'] . "' AND `original`='" . $s['original'] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete category type " . $s['type'] . " and original " .  $s['original'] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: Category type " . $s['type'] . " and original " .  $s['original'] . " deleted</h4>\n";

	return true;
}

function sql_loadTransCats( $myc , $uvjet )
{
	global $dconf,$debug;

	$chdb = sql_readtable( $myc , 'trans_cat' , $uvjet );
	if( ! $chdb ) return false;

	array_sort( $chdb , "type" );

	return $chdb;
}

function listTransCats( $chdb )
{
	global $dconf;

	reset( $chdb );
	while( list( $chk , $chv ) = each( $chdb ) ){

        	print "<tr class=\"tableBody\">\n";

        	print "  <td>\n";
		print $chv['type'];
		print "  </td>\n";

        	print "<td><a href=\"edittranscat.php?type=" . $chv['type'] . "&original=" . $chv['original'] . "\">";
		print $chv['original'] . "<br>\n";
		print "</a></td>\n";

        	print "  <td>\n";
		print $chv['category'] . "<br>\n";
		print "  </td>\n";

        	print "  <td>\n";
		print $chv['program_type'] . "<br>\n";
		print "  </td>\n";

        	print "</tr>\n";
	}
}


?>
