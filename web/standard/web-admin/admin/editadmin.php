<?php

require "../config.php";
require "../common.php"; 
require "../mysql.php";
require "../language.php";
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
// connect to main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
        	$myc = sql_doconnect();
        	if( !$myc ) exit;
		break;
}

//
// load language
//
$lngstr = loadlanguage( 'admins' );
if( $debug ) dbg("language strings" , $lngstr );

?>
<html>
<head>
<title>NonameTV: Edit Admin</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<script language="JavaScript1.2" src="../javascript/common.js"></script>
<link href="../css/nonametv.css" rel=stylesheet>
</head>
<body bgcolor="#FFFFFF" text="#000000">

<?php

function adminform( $a )
{
	global $action;
	global $shdb;

	print "<h1>Edit admin details: " . $a['username'] . "</h1>\n";
	print "<form name=admin action=\"editadmin.php\" method=post>\n";
	switch( $action ){
		case 'none':
		case 'add':
		case 'update':
		case 'delete':
			print "  <input type=\"hidden\" name=\"username\" value=\"" . $a['username'] . "\">\n";
		break;
	}
	print "  <table width=\"75%\">\n";
	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">username</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">";
	switch( $action ){
		case 'none':
		case 'add':
		case 'update':
		case 'delete':
		 	print $a['username'];
			break;
		case 'new':
			print "<input type=\"text\" name=\"username\" value=\"" . $a['username'] . "\" size=\"60\" maxlength=\"60\">\n";
		break;
	}

	print "</td>\n";
	print "    </tr>\n";
	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">password</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\" onMouseOver=\"drc('Leave this field blank to keep the old password','Admin password');return true;\" onMouseOut=\"nd();return true;\">\n";
	print "        <input type=\"text\" name=\"newpassword1\" value=\"\" size=\"60\" maxlength=\"60\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "</td>\n";
	print "    </tr>\n";
	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">password</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\" onMouseOver=\"drc('Retype new password if you want to change it','Admin password');return true;\" onMouseOut=\"nd();return true;\">\n";
	print "        <input type=\"text\" name=\"newpassword2\" value=\"\" size=\"60\" maxlength=\"60\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "</td>\n";
	print "    </tr>\n";
	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">fullname</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"fullname\" value=\"" . $a['fullname'] . "\" size=\"60\" maxlength=\"60\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\" width=\"100\">\n";
	print "        <div align=\"right\">email</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"email\" value=\"" . $a['email'] . "\" size=\"60\" maxlength=\"60\">\n";
	print "      </td>\n";
	print "    </tr>\n";

        print "    <tr>\n";
        print "      <td class=\"tableBody\">\n";
        print "        <div align=\"right\">privileges</div>\n";
        print "      </td>\n";       
        print "      <td class=\"tableBody\">\n";
        print "        <input type=\"checkbox\" name=\"ismaster\" value=\"true\"";
        	if( $a['ismaster'] == 'true' ) print " checked";
        	print "> this is master administrator - has all priveleges<br>\n";
        print "        <input type=\"checkbox\" name=\"cansubnets\" value=\"true\"";
        	if( $a['cansubnets'] == 'true' ) print " checked";
        	print "> subnets - allow this admin to manage subnets<br>\n";
        print "        <input type=\"checkbox\" name=\"canhosts\" value=\"true\"";
        	if( $a['canhosts'] == 'true' ) print " checked";
        	print "> hosts - allow this admin to manage hosts<br>\n";
        print "        <input type=\"checkbox\" name=\"candns\" value=\"true\"";
        	if( $a['candns'] == 'true' ) print " checked";
        	print "> dns - allow this admin to manage dns<br>\n";
        print "        <input type=\"checkbox\" name=\"candhcp\" value=\"true\"";
        	if( $a['candhcp'] == 'true' ) print " checked";
        	print "> dhcp - allow this admin to manage dhcp<br>\n";
        print "      </td>\n";   
        print "    </tr>\n";
	print "  </table>\n";

	if( $action == 'new' ){
		print "  <input type=\"submit\" value=\"Add\" class=\"gumb\" name=\"Add\">\n";
	}
	if( $action == 'none' ){
		print "  <input type=\"submit\" value=\"Update\" class=\"gumb\" name=\"Update\">\n";
		print "  <input type=\"submit\" value=\"Delete\" class=\"gumb\" name=\"Delete\">\n";
	}
	print "  <input type=\"button\" value=\"Cancel\" class=\"gumb\" onClick=\"javascript:window.history.back()\">\n";
	print "</form>\n";
}

//
// main
//

// arguments from the command line/url
if( $debug ) dbg( "REQUEST" , $_REQUEST );
if( isset($_REQUEST['action']) ) $action = $_REQUEST['action'];
if( isset($_REQUEST['admin']) ) $adminarg = $_REQUEST['admin'];

// posted data
if( $debug ) dbg( "_POST" , $_POST );
if( $debug ) dbg( "_REQUEST" , $_REQUEST );

//
// action from form
//
if( isset($_POST['Add']) && $_POST['Add'] == 'Add' ) $action = 'add';
if( isset($_POST['Update']) && $_POST['Update'] == 'Update' ) $action = 'update';
if( isset($_POST['Delete']) && $_POST['Delete'] == 'Delete' ) $action = 'delete';

if( isset( $_POST['username'] ) ) $adminpost['username'] = $_POST['username'];
if( isset( $_POST['fullname'] ) ) $adminpost['fullname'] = $_POST['fullname'];
if( isset( $_POST['email'] ) ) $adminpost['email'] = $_POST['email'];
if( isset( $_POST['ismaster'] ) ) $adminpost['ismaster'] = $_POST['ismaster'];
if( isset( $_POST['cansubnets'] ) ) $adminpost['cansubnets'] = $_POST['cansubnets'];
if( isset( $_POST['canhosts'] ) ) $adminpost['canhosts'] = $_POST['canhosts'];
if( isset( $_POST['candns'] ) ) $adminpost['candns'] = $_POST['candns'];
if( isset( $_POST['candhcp'] ) ) $adminpost['candhcp'] = $_POST['candhcp'];

if( isset( $_POST['newpassword1'] ) && isset( $_POST['newpassword2'] ) ){
  if( strlen(trim($_POST['newpassword1'])) && strlen(trim($_POST['newpassword2'])) ){

        if( $_POST['newpassword1'] != $_POST['newpassword2'] ){
                print "<h3>Passwords don't match</h3>\n";               
                $action = 'none';
        } else {              
                $adminpost['password'] = crypt( $_POST['newpassword1'] );
		$clearpassword = $_POST['newpassword1'];
        }
  }
}    

if( $debug ) dbg( "adminpost" , $adminpost );

//
// find if admin exists
//
if( isset( $adminpost['username'] ) ) $naso = sql_nadjiAdmin( $myc , "username" , $adminpost['username'] );
else $naso = sql_nadjiAdmin( $myc , "username" , $adminarg );
if( $debug ) dbg( "found admin" , $naso );

//
// nije pronadjen admin iz posta ili argumenta
//
if( $naso == false ){
        if( $adminarg ) $admin['username'] = $adminarg; else $admin['username'] = '';
}
else $admin = $naso;

switch( $action ){
	case 'none':
	case 'new':
		adminform( $admin );
		break;
	case 'add':
		if( !strcasecmp($naso['username'],$adminpost['username'] )){
			print "<h1>Admin " . $adminpost['username'] . " exists</h1>\n";
			break;
		}
		if( !strlen(trim($adminpost['password'])) ){
			print "<h1>You did not enter admin's password</h1>\n";
			break;
		}
		if( !strlen(trim($adminpost['email'])) ){
			print "<h1>You did not enter admin's email</h1>\n";
			break;
		}
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_dodajAdmin( $myc , $adminpost );
                        	db_writedatachange( $myc , 'admins' );
				break;
                }

		// notify added admin by email
		$adminpost['masteradmin'] = $dadmin['fullname'];
		$adminpost['nodename'] = $dconf['nodename'];
		$adminpost['adminurl'] = $dconf['adminurl'];
		$adminpost['passwordclear'] = $clearpassword;
		$mbody = formattemplate( $dconf['nonametvhome'] . "/templates/messages/admin.new.english.txt" , $adminpost );
		if( $debug ) dbg( "email body" , $mbody );
		sendemail( $adminpost['email'] , "You are new NonameTV admin" , $mbody );

		reloadUrl('Continue','index.php');
		print "<h1>Added admin: " . $adminpost['username'] . "</h1>\n";
		addlog(true,"Added admin: " . $adminpost['username']);
		break;
	case 'update':
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_azurirajAdmin( $myc , $adminpost );
                        	db_writedatachange( $myc , 'admins' );
				break;
                }

		// notify modified admin by email
		$adminpost['masteradmin'] = $dadmin['fullname'];
		$adminpost['nodename'] = $dconf['nodename'];
		$adminpost['adminurl'] = $dconf['adminurl'];
		if( $clearpassword ){
			$adminpost['passwordclear'] = $clearpassword;
			$mbody = formattemplate( $dconf['nonametvhome'] . "/templates/messages/admin.updatepwd.english.txt" , $adminpost );
		} else {
			$mbody = formattemplate( $dconf['nonametvhome'] . "/templates/messages/admin.update.english.txt" , $adminpost );
		}
		if( $debug ) dbg( "email body" , $mbody );
		sendemail( $adminpost['email'] , "Your NonameTV admin details have changed" , $mbody );

		reloadUrl('Continue','index.php');
		print "<h1>Updated admin: " . $adminpost['username'] . "</h1>\n";
		addlog(true,"Updated admin: " . $adminpost['username']);
		break;
	case 'delete':
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_brisiAdmin( $myc , $adminpost );    
                        	db_writedatachange( $myc , 'admins' );
				break;
                }

		// notify deleted admin by email
		$adminpost['masteradmin'] = $dadmin['fullname'];
		$adminpost['nodename'] = $dconf['nodename'];
		$mbody = formattemplate( $dconf['nonametvhome'] . "/templates/messages/admin.delete.english.txt" , $adminpost );
		if( $debug ) dbg( "email body" , $mbody );
		sendemail( $adminpost['email'] , "Your are no longer an NonameTV admin" , $mbody );

		reloadUrl('Continue','index.php');
		print "<h1>Deleted admin: " . $adminpost['username'] . "</h1>\n";
		addlog(true,"Deleted admin: " . $adminpost['username']);
		break;
}

//
// disconnect from main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
        	sql_dodisconnect( $myc );
		break;
}

?>

</body>
</html>
