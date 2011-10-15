<?php
require "../common.php";
require "../global.php";
require "../mysql/mysql.php";
require "../mysql/commonmysql.php";
require "../localization/language.php";
require "admins.php";
  
$debug=false; 

$action='none';

//
// start session and check login
//
start_nonametv_session();
$dadmin = get_session_data();
if( !$dadmin ) notlogged_redirect();

//
// read global config
//
citajconfig();
if( $debug ) dbg( "dconf" , $dconf );

//
// connect to main database
//
switch( $dconf[maindbtype] ){
	case 'mysql':
        	$myc = sql_spojise();
        	if( !myc ) exit;
		break;
}

//
// load language
//
loadlanguage( 'global' );
if( $debug ){
	loadlanguage( 'debug' );
	dbg( "language" , $lngstr );
}

?>
<html>
<head>
<title>NonameTV: Edit MyAdmin Details</title>
<meta http-equiv="Content-Type" content="text/html; charset=<?php print $lngstr[codepage]; ?>">
<script language="JavaScript1.2" src="../javascript/common.js"></script>
<link href="../css/nonametv.css" rel=stylesheet>
</head>
<body bgcolor="#FFFFFF" text="#000000">

<?php

function myadminform( $a )
{
	global $action;
	global $shdb;
	global $lngstr;

	print "<h1>Edit my admin details: " . $a[username] . "</h1>\n";
	print "<form name=myadmin action=\"myadmin.php\" method=post>\n";

	print "  <table width=\"75%\">\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">username</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">" . $a[username] . "</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">new password</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\" onMouseOver=\"drc('Leave this field blank to keep the old password','Admin password');return true;\" onMouseOut=\"nd();return true;\">\n";
	print "        <input type=\"password\" name=\"newpassword1\" value=\"\" size=\"64\" maxlength=\"64\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">new password</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\" onMouseOver=\"drc('Leave this field blank to keep the old password','Admin password');return true;\" onMouseOut=\"nd();return true;\">\n";
	print "        <input type=\"password\" name=\"newpassword2\" value=\"\" size=\"64\" maxlength=\"64\"> (retype)\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "</td>\n";
	print "    </tr>\n";
	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">fullname</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">" . $a[fullname] . "</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">email</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">" . $a[email] . "</td>\n";
	print "    </tr>\n";

        print "    <tr>\n";         
        print "      <td class=\"tableBody\" width=\"100\">\n";
        print "        <div align=\"right\">" . $lngstr[tr_language] . "</div>\n
";            
        print "      </td>\n";
        print "      <td class=\"tableBody\">\n";
        print "        <select name=\"language\">\n";
        print "          <option value=\"----\" selected>----</option>\n";
        $avl = languages_available();
        reset($avl);
        while( list( $lk , $lv ) = each ( $avl ) ){                  
                print "          <option value=\"" . $lv . "\">" . $lv . "</option>\n";
        }
        print "        </select>\n";
        print "      </td>\n";
        print "    </tr>\n";

        print "    <tr>\n";
        print "      <td class=\"tableBody\">\n";
        print "        <div align=\"right\">my privileges</div>\n";
        print "      </td>\n";       
        print "      <td class=\"tableBody\">";
	print "        <img src=\"/images/icons/";
		if( $a[ismaster] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
		print "\"> master<br>\n";
	print "        <img src=\"/images/icons/";
		if( $a[cansubnets] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
		print "\"> subnets<br>\n";
	print "        <img src=\"/images/icons/";
		if( $a[canhosts] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
		print "\"> hosts<br>\n";
	print "        <img src=\"/images/icons/";
		if( $a[candns] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
		print "\"> dns<br>\n";
	print "        <img src=\"/images/icons/";
		if( $a[candhcp] == 'true' ) print "mark_tick.png"; else print "mark_x.png";
		print "\"> dhcp<br>\n";
	print "      </td>\n";
        print "    </tr>\n";
	print "  </table>\n";

	print "  <input type=\"submit\" value=\"Update\" class=\"gumb\" name=\"Update\">\n";

	print "</form>\n";

        print "<script language=javascript>\n";
        print "  setCtrlValue( window.document.myadmin.language , \"$a[language]\" );\n";
        print "</script>\n";
}

//
// main
//

if( $debug ) dbg( "HTTP_POST_VARS" , $HTTP_POST_VARS );

//
// action from form
//
if( $HTTP_POST_VARS[Add] == 'Add' ) $action = 'add';
if( $HTTP_POST_VARS[Update] == 'Update' ) $action = 'update';
if( $HTTP_POST_VARS[Delete] == 'Delete' ) $action = 'delete';

$myadminpost[username] = $dadmin[username];

if( strlen(trim($HTTP_POST_VARS[newpassword1]))
 && strlen(trim($HTTP_POST_VARS[newpassword2])) ){

	if( $HTTP_POST_VARS[newpassword1] != $HTTP_POST_VARS[newpassword2] ){
		print "<h3>Passwords don't match</h3>\n";
		$action = 'none';
	} else {
		$myadminpost[password] = crypt( $HTTP_POST_VARS[newpassword1] );
	}
}

$myadminpost[language] = $HTTP_POST_VARS[language];

if( $debug ) dbg( "myadminpost" , $myadminpost );

//
// find if I as exist in admins table
//
$naso = sql_nadjiAdmin( $myc , "username" , $dadmin[username] );
if( $debug ) dbg("found me as admin" , $naso);

//
// not found
//
if( !$naso ){
	print "<h1>Dear " . $dadmin[username] . ",</h1>\n";
	print "<h3>You are not found to be an administrator in NonameTV</h3>\n";
	print "<h3>How can you see this page if you are not an admin???</h3>\n";
	print "<h3>Please, call your server administrator</h3>\n";
	//
	// disconnect from main database
	//
	switch( $dconf[maindbtype] ){
		case 'mysql':
        		sql_odspojise( $myc );
			break;
	}
	exit;
}

switch( $action ){
	case 'none':
		myadminform( $naso );
		break;
	case 'update':
                switch( $dconf[maindbtype] ){
			case 'mysql':
				if( $debug ) dbg("MY new details",$myadminpost);
                        	sql_azurirajAdmin( $myc , $myadminpost );
                        	db_writedatachange( $myc , 'admins' );
				break;
                }

		reloadUrl('Continue','myadmin.php');
		print "<h1>Updated my admin: " . $myadminpost[username] . "</h1>\n";
		addlog(true,"Updated my admin: " . $myadminpost[username]);
		break;
}

//
// disconnect from main database
//
switch( $dconf[maindbtype] ){
	case 'mysql':
        	sql_odspojise( $myc );
		break;
}

?>

</body>
</html>
