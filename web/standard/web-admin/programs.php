<?php

function db_loadPrograms( $tvid )
{
        global $dconf;
	global $myc;

        switch( $dconf['dbtype'] ){
		case 'mysql':
                	$tdb = sql_loadPrograms( $myc , 'xmltvid' , $tvid );
                	return $tdb;
        }

	return false;
}

function sql_addProgram( $myc , $s )
{
	global $debug;

	$tblname = 'programs';

	//
	// prvo insert novog programa (name je unique)...
	//
	$q = "INSERT INTO " . $tblname . " SET name='" . $s[name] . "'";
	if( $debug ) dbg( "INSERT INTO" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>MySQL: Can't add program " . $s[name] . " to " . $tblname . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<pre>MySQL: Program " . $s[name] . " added</pre>\n";

	//
	// nakon inserta azuriranje podataka...
	//
	sql_updateProgram( $myc , $s );

	return true;
}

function sql_updateProgram( $myc , $s )
{
	global $debug;

	$tblname = 'programs';

	$ak = array_keys( $s );
	reset( $ak );
	while( list( $sak , $sav ) = each( $ak ) ){

		// fields that we don't update in mysql database
		if( $sav == 'oldsharedname' ) continue;
		if( $sav == 'oldfailover' ) continue;

		switch( $sav ){
			case 'fwrules': // multiline text fields
			case 'ranges':
			case 'unranges':
			case 'routers':
			case 'staticroutes':
			case 'nameservers':
			case 'unnameservers':
			case 'winsservers':
			case 'unwinsservers':
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . join( "\n" , $s[$sav] ) . "' WHERE name='" . $s[name] . "'";
				break;
			default: // simple fields
				$q = "UPDATE " . $tblname . " SET " . $sav . "='" . $s[$sav] . "' WHERE name='" . $s[name] . "'";
		}

		if( $debug ) dbg( "UPDATE" , $q );

		if( !mysql_query( $q , $myc ) ) {
			print "<h4>MySQL: Can't update field " . $sav . " of program " . $s[name] . "</h4>\n";
			print mysql_error( $myc ) . "\n";
			return false;
		}
	}

	print "<pre>MySQL: Program " . $s[name] . " updated</pre>\n";

	return true;
}

function sql_deleteProgram( $myc , $s )
{
	global $debug;

	$tblname = 'programs';

	$q = "DELETE FROM " . $tblname . " WHERE name='" . $s[name] . "'";
	if( $debug ) dbg( "DELETE" , $q );
	if( !mysql_query( $q , $myc ) ) {
		print "<h4>Can't delete program " . $s[name] . "</h4>\n";
		print mysql_error( $myc ) . "\n";
		return false;
	}

	print "<h4>MySQL: Program " . $s[name] . " deleted</h4>\n";

	return true;
}

function sql_loadPrograms( $myc , $kaj , $vrijednost )
{
	global $dconf,$debug;

	if( strlen(trim($kaj)) ) $cond = $kaj . "='" . $vrijednost . "'";

	$prgdb = sql_readtable( $myc , 'programs' , $cond );
	if( ! $prgdb ) return false;

	//array_sort( $prgdb , "name" );

	return $prgdb;
}

function sql_findProgram( $myc , $channel , $kaj , $vrijednost )
{
	global $dconf,$debug;

	$cond = "channel_id='" . $channel . "'";

	if( strlen(trim( $kaj )) ){
		switch( $kaj ){
			case 'fwrules': // walk through multiline text fields
			case 'ranges':
			case 'unranges':
			case 'routers':
			case 'staticroutes':
			case 'nameservers':
			case 'unnameservers':
			case 'winsservers':
			case 'unwinsservers':
				$cond .= " AND " . $kaj . " LIKE '%" . $vrijednost . "%'";
				return false; // ??????????
			default:
				$cond .= " AND " . $kaj . "='" . $vrijednost . "'";
				break;
		}
	}

	$sn = sql_readtable( $myc , 'programs' , $cond );
	if( $debug ) dbg("sql_findProgram" , $sn );

	return $sn;
}


function listPrograms( $chanid , $prgdb )
{
	global $dconf;

	$prgdb = array_sort( $prgdb , "start_time" );

	reset( $prgdb );
	while( list( $chk , $chv ) = each( $prgdb ) ){

        	print "<tr class=\"tableBody\">\n";

        	print "  <td>\n";
		print $chv['start_time'];
		print "  </td>\n";

        	print "  <td>\n";
		print $chv['end_time'];
		print "  </td>\n";

        	print "<td><a href=\"viewprogram.php?channel=" . $chanid . "&time=" . str2time($chv['start_time'], 0 ) . "\">";
		print $chv['title'];
		print "</a></td>\n";

        	print "  <td>\n";
		$predesc = ereg_replace( "\n" , "<br>" , $chv['description'] );
                print $predesc;
		print "  </td>\n";

        	print "  <td class=\"cat_" . $chv['category'] . "\">\n";
		print $chv['category'];
		print "  </td>\n";

        	print "</tr>\n";
	}
}

function extract_programs( $chanid , $from , $to )
{
	global $dconf;
	global $myc;

	$pdb = sql_loadPrograms( $myc , 'channel_id' , $chanid );
	if( !$pdb ) return false;

	// programs in database are stored
	// with start and end times in UTC
	reset( $pdb );
	while( list( $pk , $pv ) = each( $pdb ) ){

		$stt = str2time( $pv['start_time'] , 1 );
		$ent = str2time( $pv['end_time'] , 1 );

		if( ( $stt < $from ) && ( $ent > $from ) ){ // program started before, but ends inside of window
			$chunk[] = $pv;
		} else if( ( $stt >= $from ) && ( $stt < $to ) ){ // whole program in time window
			$chunk[] = $pv;
		}
	}

	if( isset( $chunk ) ) return( $chunk );
	else return false;
}

function fix_programs( $prgs , $from , $to )
{
	global $dconf;
	global $lngstrns;

	$prg = array_sort( $prgs , "start_time" );
//dbg("programi na pocetku",$prg);

	// fill the holes with no data
	$lastend = $from;
	reset( $prg );
	while( list( $k , $v ) = each( $prg ) ){

		$st = str2time( $v['start_time'] , 1 );
		$et = str2time( $v['end_time'] , 1 );

		if( $st < $from && $et >= $from ){	// now running show
//dbg("dodati trenutni program",$v);
			$np[] = $v;
			$lastend = $et;
		} else if( ( $st >= $from ) && ( $st < $to ) ){ // whole program in time window
			if( $st == $lastend ){
//dbg("dodati - nema rupe",$v);
				$np[] = $v;
				$lastend = $et;
			} else if( $st > $lastend ){
//dbg("dodati - RUPA","od " . $lastend . " do " . $st );

				// insert hole
				$hole['channel_id'] = $v['channel_id'];
				$hole['start_time'] = gmdate( "Y-m-d H:i:s" , $lastend );
				$hole['end_time'] = gmdate( "Y-m-d H:i:s" , $st );
				$hole['title'] = $lngstrns['nodata'];
				$hole['description'] = $lngstrns['nodatadesc'];
				$hole['category'] = "hole";
				$np[] = $hole;

				// add program after the hole
				$np[] = $v;
				$lastend = $et;
			}
		}
	}
	if( $lastend < $to ){
		// insert hole
		$hole['channel_id'] = $v['channel_id'];
		$hole['start_time'] = gmdate( "Y-m-d H:i:s" , $lastend );
		$hole['end_time'] = gmdate( "Y-m-d H:i:s" , $to );
		$hole['title'] = $lngstrns['nodata'];
		$hole['description'] = $lngstrns['nodatadesc'];
		$hole['category'] = "hole";
		$np[] = $hole;
//dbg("dodati - RUPA NA KRAJU od " . $lastend . " do " . $to , $hole);
	}
//dbg("programi nakon filanja rupa",$np);

	$prg = $np;

	// join programs that are shorter than
	// grancell
	reset( $prg );
	while( list( $k , $v ) = each( $prg ) ){

		$st = str2time( $v['start_time'] , 1 );
		$et = str2time( $v['end_time'] , 1 );

		// calculate the time for the program that falls
		// in the window to be displayed
		// check if this is a currently showing program
		// or the program will start during the time window
		if( $st < $from && $et >= $from ){
			$duration = $et - $from;
		} else {
			$duration = $et - $st;
		}

		// duration of the current show in minutes
		$durmins = $duration / 60;

		// check if show duration is less than smallest cell duration
		if( $durmins < $dconf['grancell'] ){
		}
	}

	return($prg);
}

//
// calculate cell width (%) and cell span
//
function cellwidth( $pcv , $fromtime , $window )
{
	global $dconf;
	$c = Array();

	$st = str2time( $pcv['start_time'] , 1 );
	$et = str2time( $pcv['end_time'] , 1 );

	// total width available for programs (%)
	$tw = 100 - $dconf['firstcellwidth'] - $dconf['lastcellwidth'];

	// calculate the time for the program that falls
	// in the window to be displayed
	// check if this is a currently showing program
	// or the program will start during the time window
	if( ($st < $fromtime) && ($et >= $fromtime) && ($et <= ( $fromtime + $window * 60 ))  ){
		// started before, ends in window
		$duration = $et - $fromtime;
	} else if( ($st >= $fromtime) && ($st < ( $fromtime + $window * 60 )) && ($et > ( $fromtime + $window * 60 ) ) ){
		// started in window, ends later
		$duration = $fromtime + $window * 60 - $st;
	} else if( ($st < $fromtime) && ($et > ( $fromtime + $window * 60 ) ) ){
		// started before, ends later
		$duration = $window * 60;
	} else {
		// whole show inside of the time window
		$duration = $et - $st;
	}

	// duration of the current show in minutes
	$durmins = $duration / 60;

	// find the width of the curent show
	$c['w'] = (int)( $durmins / $window * $tw );

	// find the span of the curent show
	$c['s'] = (int)( $durmins / $dconf['grancell'] );

//dbg("span " . $durmins . " " . $dconf['grancell'] ,$c['s']);

	return( $c );
}

//
// draw the time bar (above programs list)
//
function draw_timebar( $start , $window , $gran , $grantime )
{
	global $dconf;
	global $lngstrns;

	print "<tr>\n";

	print "  <td class=\"nowshowing_tabletitle\" width=\"" . $dconf['firstcellwidth'] . "%\" align=\"right\">\n";
	print "    <table>\n";
	print "      <tr>\n";  
	print "        <td align=\"left\" width=\"10%\"><a href=\"nowshowing.php?time=" . ( $start - $dconf['shiftarrow'] * 60 ) . "\"><img src=\"images/left.gif\" border=\"0\" alt=\"left\"></a></td>\n";
	print "        <td align=\"center\"><a href=\"#\" id=\"catlegend\" onmouseover=\"popup('catlegend'); return true;\">" . $lngstrns['categories'] . "</a></td>\n";
	print "        <td align=\"right\" width=\"10%\"><a href=\"nowshowing.php?time=" . ( $start - $dconf['shiftarrow'] * 60 ) . "\"><img src=\"images/left.gif\" border=\"0\" alt=\"left\"></a></td>\n";
	print "      </tr>\n";  
	print "    </table>\n";
	print "  </td>\n";  

	// find first time display point before $start
	$da = getdate($start);
	$da['minutes'] = (int)($da['minutes'] / $grantime) * $grantime;
	$da['seconds'] = 0;
	$tg = mktime ( $da['hours'] , $da['minutes'] , $da['seconds'] , $da['mon'] , $da['mday'] , $da['year'] );
	$stop = $tg + $window * 60;
	
	// calculate the number of time display points
	// and the cell span of one time display point
	// and the width of it
	$cnt = $window / $grantime;
	$tdps = $grantime / $gran;
	$tdpw = ( 100 - $dconf['firstcellwidth'] - $dconf['lastcellwidth'] ) / $cnt;

	do{
		$da = getdate( $tg );
		print "  <td nowrap class=\"nowshowing_tabletitle\" colspan=\"" . $tdps . "\" width=\"" . $tdpw . "%\" align=\"left\"><a href=\"nowshowing.php?time=" . $tg . "\">" . $da['hours'] . ":" . $da['minutes'] . "</a></td>\n";
		$tg += ( $grantime * 60 );
	} while( $tg < $stop );

	print "  <td nowrap class=\"nowshowing_tabletitle\" width=\"" . $dconf['lastcellwidth'] . "%\"><a href=\"nowshowing.php?time=" . ( $start + $window + $dconf['shiftarrow'] * 60 ) . "\"><img src=\"images/right.gif\" border=\"0\" alt=\"right\"></a></td>\n";
	print "</tr>\n";

}

//
// draw_catlegend
//
function draw_catlegend()
{
?>

<div id="catlegend_popup">
<table class="categories" width="400" bgcolor="#003060" class="small" cellpadding="5" cellspacing="5">
  <tr>
    <td colspan="3">Category Legend:</td>
  </tr>
  <tr>
    <td class="cat_Action" align="center"><b>Action</b></td>
    <td class="cat_Adult" align="center"><b>Adult</b></td>
    <td class="cat_Animals" align="center"><b>Animals</b></td>
  </tr>
  <tr>
    <td class="cat_Art_Music" align="center"><b>Art_Music</b></td>
    <td class="cat_Business" align="center"><b>Business</b></td>
    <td class="cat_Children" align="center"><b>Children</b></td>
  </tr>
  <tr>
    <td class="cat_Comedy" align="center"><b>Comedy</b></td>
    <td class="cat_Crime_Mystery" align="center"><b>Crime / Mystery</b></td>
    <td class="cat_Documentary" align="center"><b>Documentary</b></td>
  </tr>
  <tr>
    <td class="cat_Drama" align="center"><b>Drama</b></td>
    <td class="cat_Educational" align="center"><b>Educational</b></td>
    <td class="cat_Food" align="center"><b>Food</b></td>
  </tr>
  <tr>
    <td class="cat_Game" align="center"><b>Game</b></td>
    <td class="cat_Health_Medical" align="center"><b>Health / Medical</b></td>
    <td class="cat_History" align="center"><b>History</b></td>
  </tr>
  <tr>
    <td class="cat_Horror" align="center"><b>Horror</b></td>
    <td class="cat_HowTo" align="center"><b>HowTo</b></td>
    <td class="cat_Misc" align="center"><b>Misc</b></td>
  </tr>
  <tr>
    <td class="cat_News" align="center"><b>News</b></td>
    <td class="cat_Reality" align="center"><b>Reality</b></td>
    <td class="cat_Romance" align="center"><b>Romance</b></td>
  </tr>
  <tr>
    <td class="cat_SciFi_Fantasy" align="center"><b>SciFi / Fantasy</b></td>
    <td class="cat_Science_Nature" align="center"><b>Science / Nature</b></td>
    <td class="cat_Shopping" align="center"><b>Shopping</b></td>
  </tr>
  <tr>
    <td class="cat_Soaps" align="center"><b>Soaps</b></td>
    <td class="cat_Spiritual" align="center"><b>Spiritual</b></td>
    <td class="cat_Sports" align="center"><b>Sports</b></td>
  </tr>
  <tr>
    <td class="cat_Talk" align="center"><b>Talk</b></td>
    <td class="cat_Travel" align="center"><b>Travel</b></td>
    <td class="cat_War" align="center"><b>War</b></td>
  </tr>
  <tr>
    <td class="cat_Western" align="center"><b>Western</b></td>
    <td class="cat_Unknown" align="center"><b>Unknown</b></td>
    <td class="cat_movie" align="center"><b>Movie</b></td>
  </tr>
</table>
</div>

<?php
}

//
// set the class for a cell
// depends on program category
//
function cellclass_category( $p , $def )
{
	switch( $p['category'] ){
		case "hole":
			$c = "cat_hole";
			break;
		case "Movie":
			$c = "cat_movie";
			break;
		case "Action":
			$c = "cat_Action";
			break;
		case "Adult":
			$c = "cat_Adult";
			break;
		case "Animals":
			$c = "cat_Animals";
			break;

		case "Documentary":
			$c = "cat_Documentary";
			break;

		case "Reality":
			$c = "cat_Reality";
			break;

		case "Romance":
			$c = "cat_Romance";
			break;

		case "Sports":
			$c = "cat_Sports";
			break;

		default:
			if( $def ) $c = "cat_" . $def;
			else $c = "cat_default";
	}

/*
		</tr><tr>
			<td class="cat_Art_Music" align="center"><b>Art_Music</b></td>
			<td class="cat_Business" align="center"><b>Business</b></td>
			<td class="cat_Children" align="center"><b>Children</b></td>

		</tr><tr>
			<td class="cat_Comedy" align="center"><b>Comedy</b></td>

			<td class="cat_Crime_Mystery" align="center"><b>Crime / Mystery</b></td>
			<td class="cat_Documentary" align="center"><b>Documentary</b></td>

		</tr><tr>
			<td class="cat_Drama" align="center"><b>Drama</b></td>

			<td class="cat_Educational" align="center"><b>Educational</b></td>
			<td class="cat_Food" align="center"><b>Food</b></td>

		</tr><tr>
			<td class="cat_Game" align="center"><b>Game</b></td>
			<td class="cat_Health_Medical" align="center"><b>Health / Medical</b></td>
			<td class="cat_History" align="center"><b>History</b></td>

		</tr><tr>
			<td class="cat_Horror" align="center"><b>Horror</b></td>

			<td class="cat_HowTo" align="center"><b>HowTo</b></td>
			<td class="cat_Misc" align="center"><b>Misc</b></td>

		</tr><tr>
			<td class="cat_News" align="center"><b>News</b></td>

			<td class="cat_Reality" align="center"><b>Reality</b></td>
			<td class="cat_Romance" align="center"><b>Romance</b></td>

		</tr><tr>
			<td class="cat_SciFi_Fantasy" align="center"><b>SciFi / Fantasy</b></td>
			<td class="cat_Science_Nature" align="center"><b>Science / Nature</b></td>
			<td class="cat_Shopping" align="center"><b>Shopping</b></td>

		</tr><tr>
			<td class="cat_Soaps" align="center"><b>Soaps</b></td>

			<td class="cat_Spiritual" align="center"><b>Spiritual</b></td>
			<td class="cat_Sports" align="center"><b>Sports</b></td>

		</tr><tr>
			<td class="cat_Talk" align="center"><b>Talk</b></td>

			<td class="cat_Travel" align="center"><b>Travel</b></td>
			<td class="cat_War" align="center"><b>War</b></td>

		</tr><tr>
			<td class="cat_Western" align="center"><b>Western</b></td>
			<td class="cat_Unknown" align="center"><b>Unknown</b></td>
*/
	return( $c );
}

?>
