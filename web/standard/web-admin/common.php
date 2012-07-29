<?php

/*
** function: set_browser_variables
** arguments: none
** returns: void
*/
function set_browser_variables()
{
	global $dconf;

	// set browser variables
	print "<script language=\"javascript\">\n";
	print "  var popuphelp = " . $dconf['popuphelp'] . ";\n";
	print "</script>\n";
}

function dbg( $nas , $kaj )
{
	print "<hr>\n";
	print "<h3>" . $nas . "</h3>\n";
	print "<pre>\n";
	print_r( $kaj );
	print "</pre>\n";
}

function dbgfile( $fn )
{
	print "<hr>\n";
	print "<h3>" . $fn . "</h3>\n";
	print "<pre>\n";
	readfile( $fn );
	print "</pre>\n";
}

function addlog( $vri , $s )
{
        global $dconf;

        if(($fp = fopen( $dconf['logfile'] , "a" )) == false )
                return false;

        if( $vri ){
                fwrite( $fp , date( "d/m/Y H:i:s - " ) );
        }

        fwrite( $fp , $s . "\n" );
        if( $dconf['verbose'] ) print "<pre>" . $s . "</pre>\n";

        fclose( $fp );
}

function reloadUrl($string,$url)
{
	print "<form name=\"reloadUrl\">\n";
	print "<input type=\"button\" value=\"" . $string . "\" class=\"gumb\" onClick=\"javascript:window.location.href='" . $url . "'\">\n";
	print "</form>\n";
}

function goBack($string)
{
	print "<form name=\"goback\">\n";
	print "<input type=\"button\" value=\"" . $string . "\" class=\"gumb\" onClick=\"javascript:window.history.back()\">\n";
	print "</form>\n";
}

//
// read the information about the user updating the table
//
function db_readdatachange( $myc , $tn )
{
	global $debug;

	$aidb = sql_gettable( $myc , "datachanges" , "tablename='" . $tn . "'" );
	if( $debug ) dbg( "db_readdatachange" , $aidb );
	if( sizeof( $aidb ) == 1 ) return $aidb[0];
	else return false;
}

//
// format text array from template file and values
//
function formattemplate( $fn , $psv )
{
	global $debug;

	if( !file_exists( $fn ) ){
		print "<h3>No template file " . $fn . "</h3>\n";
		return false;
	}

	$ffl = file( $fn );

	reset( $ffl );
	while( list( $fkey , $fval ) = each( $ffl ) ){

		$fval = trim( $fval );

		$naso = false;
		reset( $psv );
		while( list( $pkey , $pval ) = each( $psv ) ){

			if( eregi( "%%" . $pkey . "%%" , $fval ) ){
				if( is_array($psv[$pkey]) ){
					$pl = "";
					reset( $psv[$pkey] );
					while( list( $ppk , $ppv ) = each( $psv[$pkey] ) ){
						$pl .= "," . $ppv;
						$pl = eregi_replace( "^," , "" , $pl );
					}
					$nffl[] = eregi_replace( "%%" . $pkey . "%%" , $pl , $fval );
				} else {
					if( is_bool( $pval ) )
						$nffl[] = eregi_replace( "%%" . $pkey . "%%" , $strbool[$pval] , $fval );
					else
						$nffl[] = eregi_replace( "%%" . $pkey . "%%" , $pval , $fval );
				}
				$naso = true;
				break;
			}

		}
		if( ! $naso ) $nffl[] = $fval;
	}

	if( $debug ) dbg( "new file" , $nffl );

	return $nffl;
}

//
// print array-file to file
//
function array2file( $fcontents , $fn )
{
	global $debug;

	if( ( $fp = fopen( $fn , "w" ) ) == false ) return false;

	reset( $fcontents );
	while (list ($line_num, $line) = each ($fcontents)) {
		fputs( $fp , trim($line) . "\n" );
	}

	fclose( $fp );
}

function sendemail( $to , $subject , $body )
{
	global $dconf;

	if( is_array($body) ) $body = implode ( "\n", $body );

	switch( $dconf[maildelivery] ){
		case 'internal':
			$headers = "From: NonameTV\nReply-To: " . $dconf[adminemail];
			$rc = mail( $to , $subject, $body , $headers );
			break;
		case sendmail:
			$headers = "From: NonameTV\nTo: " . $to . "\nReply-To: " . $dconf[adminemail];
			$fp = popen( $dconf[sendmail] . " -it" , "w" );
			if( ! $fp ){ $rc = false; break; }
			fwrite( $fp, $headers . "\n" );
			fwrite( $fp, "Subject: " . $subject . "\n" );
			fwrite( $fp, "\n" );
			fwrite( $fp, $body . "\n" );
			pclose( $fp );
			$rc = true;
			break;
	}

	if( ! $rc ){
		print "<h2>Failed to send email to " . $to . " (delivery method: " . $dconf[maildelivery] . ")</h2>\n";
		print "<h3>message contents:</h3>\n";
		print "<pre>\n" . $body . "\n</pre>\n";
	}
}

function msgPopup( $type , $title , $text )
{
	print "<script language=\"javascript\">\n";
	print "  alert( '" . $text . "' );\n";
	print "</script>\n";
}

function array_sort($multiArray, $secondIndex) {

    if( ! $multiArray ) return false;

    while (list($firstIndex, ) = each($multiArray))
        $indexMap[$firstIndex] = $multiArray[$firstIndex][$secondIndex];
    asort($indexMap);
    while (list($firstIndex, ) = each($indexMap))
        if (is_numeric($firstIndex))
            $sortedArray[] = $multiArray[$firstIndex];
        else $sortedArray[$firstIndex] = $multiArray[$firstIndex];
    return $sortedArray;
} 

function mydate( $format, $timestamp )
{
	$zoneoffest = date('Z');

	$daylight_saving = date('I');

	if( $daylight_saving ){
		$totaloffset = 3600 + $zoneoffest;
	} else {
		$totaloffset = $zoneoffest;
	}

	$date = date( $format , $timestamp + $totaloffset );

	return $date;
}


function str2time( $timestring , $off )
{
	//int mktime ( [int hour [, int minute [, int second [, int month [, int day [, int year [, int is_dst]]]]]]] )

	$t = strtotime ( $timestring );

	//dbg( $timestring , $t );

	// off is set to 1 if local time is to be generated
	if( $off ) $zoneoffest = date('Z');
	else $zoneoffest = 0;

	$t += $zoneoffest;

	//dbg( "getdate" , getdate ( $t ));

	return( $t );
}

function hmins( $timestring )
{
	$t = str2time( $timestring , 1 );

	//$da = getdate( $t );
	//$s = $da['hours'] . ":" . $da['minutes'];

	$s = strftime( "%H:%M" , $t );

	return( $s );
}

?>
