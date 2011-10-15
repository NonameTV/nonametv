<?php

//
// lookup what languages are available
//
function languages_available()
{
	global $myc,$dconf;

        $tables = mysql_list_tables( $dconf['dbname'] , $myc );
        if( ! $tables ){
                print "No language tables found in database " . $dconf['dbname'] . "\n";
                return false;
        }    
        
        while( list( $t ) = mysql_fetch_array( $tables ) ){

                if( strstr( $t , 'lang_' ) ){
			$languages[] = substr( $t , 5 );
		}
        }

	return $languages;
}

//
// load language strings
//
function loadlanguage( $module )
{
	global $myc;
	global $dconf;

	$lang = $dconf['language'];

	$cond = "module='" . $module . "' AND language='" . $lang . "'";
	if( $module ) $langdb = sql_readtable( $myc , "languagestrings" , $cond );
	else $langdb = sql_readtable( $myc , "lang_" . $lang , "" );

        if( ! $langdb ) return false;

	reset($langdb);
	while( list( $lk , $lv ) = each( $langdb ) ){
		$lngstr[$lv['strname']] = $lv['strvalue'];
	}

	return( $lngstr );
}

?>
