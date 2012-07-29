<?php
 
require "config.php";
require "common.php";
require "mysql.php";
require "transcat.php";
 
$debug=false;
 
$action='none';
 
//                     
// connect to main database          
//   
switch( $dconf['dbtype'] ){
	case 'mysql':
        	$myc = sql_doconnect();
        	if( !$myc ) exit;
		break;
}

?>
<html>
<head>
<title>Category details</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
<script language="JavaScript1.2" src="js/common.js"></script>
</head>
<body bgcolor="#FFFFFF" text="#000000">

<?php

function transcatform( $tc )
{
	global $action;
	global $dconf;

	print "<h1>Edit category details: " . $tc['type'] . " / " . $tc['original'] . "</h1>\n";
	print "<form name=transcat action=\"edittranscat.php\" method=post>\n";

	print "  <table>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">Original category details</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Type</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">";
	print "        <input type=\"text\" name=\"type\" value=\"" . $tc['type'] . "\" size=\"64\" maxlength=\"64\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Original</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">";
	print "        <input type=\"text\" name=\"original\" value=\"" . $tc['original'] . "\" size=\"64\" maxlength=\"64\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">Translated category details</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Category</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">";
	print "        <input type=\"text\" name=\"category\" value=\"" . $tc['category'] . "\" size=\"64\" maxlength=\"64\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Program type</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">";
	print "        <input type=\"text\" name=\"program_type\" value=\"" . $tc['program_type'] . "\" size=\"64\" maxlength=\"64\">\n";
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
if( $_REQUEST['type'] ) $argtype = $_REQUEST['type'];
if( $_REQUEST['original'] ) $argoriginal = $_REQUEST['original'];

// posted data
if( $debug ) dbg( "_POST" , $_POST );
if( isset( $_POST['type'] ) ) $catpost['type'] = $_POST['type'];
if( isset( $_POST['original'] ) ) $catpost['original'] = $_POST['original'];
if( isset( $_POST['category'] ) ) $catpost['category'] = $_POST['category'];
if( isset( $_POST['program_type'] ) ) $catpost['program_type'] = $_POST['program_type'];

if( $debug ) dbg( "catpost" , $catpost );

//
// action from form
//
if( isset( $_POST['Add'] ) && ( $_POST['Add'] == 'Add' ) ) $action = 'add';
if( isset( $_POST['Update'] ) && ( $_POST['Update'] == 'Update' ) ) $action = 'update';
if( isset( $_POST['Delete'] ) && ( $_POST['Delete'] == 'Delete' ) ) $action = 'delete';

//
// load categories from _REQUEST
//
if( $action == 'none' ){

	$cond = "";

	if( isset($argtype) ) $cond .= " `type`='" . $argtype . "'";
	if( isset($argtype) && isset($argoriginal) ) $cond .= " AND ";
	if( isset($argoriginal) ) $cond .= " `original`='" . $argoriginal . "'";
	if( $debug ) dbg( "cond" , $cond );

	$found = db_loadTransCats( $cond );
	if( $debug ) dbg( "found" , $found );
}

switch( $action ){
	case 'none':
	case 'new':
		transcatform( $found[0] );
		break;
	case 'add':
		if( $found && !strcasecmp($found['id'],$catpost['id'] )){
                        print "<h1>Category with ID " . $catpost['id'] . " exists</h1>\n";
                        reloadUrl('Continue','transcat.php');
                        print "<script language=\"javascript\">\n";
                        print "  url = 'showtranscat.php?name=" . $found[name] . "';\n";
                        print "  openDialog( url , 'showtranscat' , 'width=300,height=300,resizable=yes,scrollbars=yes,status=yes' );\n";
                        print "</script>\n";
                        break;
		}
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_addCategory( $myc , $catpost );
				break;
                }

		print "<h1>Category " . $catpost['id'] . " added</h1>\n";
		reloadUrl('Continue','transcat.php');
		addlog(true,"Category " . $catpost['id'] . " added" );
		break;
	case 'update':
		sql_updateTransCat( $myc , $catpost );

		print "<h1>Category type " . $catpost['type'] . " and original " . $catpost['original'] . " updated</h1>\n";
		reloadUrl('Continue','listtranscat.php');
		break;
	case 'delete':
		sql_deleteTransCat( $myc , $catpost );
		print "<h1>Category type " . $catpost['type'] . " and original " . $catpost['original'] . " deleted</h1>\n";
		reloadUrl('Continue','listtranscat.php');
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
