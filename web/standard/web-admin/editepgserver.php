<?php
 
require "config.php";
require "common.php";
require "mysql.php";
require "epgservers.php";
 
$debug=false;
 
$action='none';
$found = false;
 
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
<title>EPG server details</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
<script language="JavaScript1.2" src="js/common.js"></script>
</head>
<body bgcolor="#FFFFFF" text="#000000">

<?php

function epgserverform( $es )
{
	global $action;
	global $dconf;

	print "<h1>Edit details for EPG server: " . $es['name'] . "</h1>\n";
	print "<form name=epgserver action=\"editepgserver.php\" method=post>\n";
	switch( $action ){
		case 'none':
		case 'add':
		case 'update':
		case 'delete':
			print "  <input type=\"hidden\" name=\"id\" value=\"" . $es['id'] . "\">\n";
		break;
	}
	print "  <table>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">General details</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">ID</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">";
	switch( $action ){
		case 'none':
		case 'add':
		case 'update':
		case 'delete':
		 	print $es['id'];
			break;
		case 'new':
			print "<input type=\"text\" name=\"id\" value=\"" . $es['id'] . "\" size=\"12\" maxlength=\"12\">\n";
		break;
	}
	print "</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Active</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"checkbox\" name=\"active\" value=\"1\"" ;
	if( $es['active'] == '1' ) print " checked";
	print "> check if you want to make this server active\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Name</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"name\" value=\"" . $es['name'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Description</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"description\" value=\"" . $es['description'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Vendor</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"vendor\" value=\"" . $es['vendor'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Type</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"type\" value=\"" . $es['type'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "  </table>\n";

	if( $action == 'new' ){
		print "  <input type=\"submit\" value=\"Add\" class=\"gumb\" name=\"Add\">\n";
	}

	if( $action == 'none' ){
		print "<p>\n";
		print "  <input type=\"submit\" value=\"Update\" class=\"gumb\" name=\"Update\">\n";
		print "  <input type=\"submit\" value=\"Delete\" class=\"gumb\" name=\"Delete\">\n";
		print "</p>\n";
	}

	print "</form>\n";
}

//
// main
//

// arguments from the command line/url
if( $debug ) dbg( "REQUEST" , $_REQUEST );
if( isset($_REQUEST['action']) ) $action = $_REQUEST['action'];
if( isset($_REQUEST['id']) ) $idarg = $_REQUEST['id'];

// posted data
if( $debug ) dbg( "_POST" , $_POST );

if(isset($_POST['id'])) $epgserverpost['id'] = $_POST['id'];
if(isset($_POST['active'])) $epgserverpost['active'] = $_POST['active'];
if(isset($_POST['name'])) $epgserverpost['name'] = $_POST['name'];
if(isset($_POST['description'])) $epgserverpost['description'] = $_POST['description'];
if(isset($_POST['vendor'])) $epgserverpost['vendor'] = $_POST['vendor'];
if(isset($_POST['type'])) $epgserverpost['type'] = $_POST['type'];

if( $debug ) dbg( "epgserverpost" , $epgserverpost );

// set default values if not set
if( isset($epgserverpost) ) $epgserverpost = set_epgserver_defaults( $epgserverpost );

// convert to lowercase
if( $dconf['lowercase'] && isset($epgserverpost) ){
        $epgserverpost['name'] = strtolower( $epgserverpost['name'] );
}

//
// action from form
//
if( isset($_POST['Add']) && $_POST['Add'] == 'Add' ) $action = 'add';
if( isset($_POST['Update']) && $_POST['Update'] == 'Update' ) $action = 'update';
if( isset($_POST['Delete']) && $_POST['Delete'] == 'Delete' ) $action = 'delete';

//
// check if there is already a epgserver with this name
//
if( $action != 'new' ){
        switch( $dconf['dbtype'] ){
		case 'mysql':

                	// first try to find from posted data
                	if( !$found && isset($epgserverpost['id']) ) $found = sql_findEPGserver( $myc , 'id' , $epgserverpost['id'] );
                	if( $debug && $found ){
                        	dbg( "sql: found from posted data" , $found );
                	}

                	// if !found with posted data
                	// try to find with data from arguments
                	if( !$found && $idarg ) $found = sql_findEPGserver( $myc , 'id' , $idarg );
                	if( $debug && $found ){
                        	dbg( "sql: found from arguments" , $found );
                	}
			break;

        }
}

//
// not found
//
if( $found == false ){
        switch( $action ){
                case 'none': // if action==none -> this is edit, so it must be found
                        print ("<h3>Invalid epgserver: " . $idarg . " </h3>\n");
                        exit;
                default:
                        //dbg($action,"...");
                        break;
        }

	$epgserver = set_epgserver_defaults( false );
}
else $epgserver = $found;

// remember current dhcp group
// on delete or update epgserver should be removed from old group
//$epgserver[olddhcpgroup] = $epgserver[dhcpgroup];

switch( $action ){
	case 'none':
	case 'new':
		epgserverform( $epgserver );
		break;
	case 'add':
		if( $found && !strcasecmp($found['id'],$epgserverpost['id'] )){
                        print "<h1>EPG server with ID " . $epgserverpost['id'] . " exists</h1>\n";
                        print "<script language=\"javascript\">\n";
                        print "  url = 'showepgserver.php?name=" . $found[name] . "';\n";
                        print "  openDialog( url , 'showepgserver' , 'width=300,height=300,resizable=yes,scrollbars=yes,status=yes' );\n";
                        print "</script>\n";
                        break;
		}
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_addEPGserver( $myc , $epgserverpost );
				break;
                }

		print "<h1>EPG server " . $epgserverpost['id'] . " added</h1>\n";
		addlog(true,"EPG server " . $epgserverpost['id'] . " added" );
		break;
	case 'update':
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_updateEPGserver( $myc , $epgserverpost );
				break;
                }

		print "<h1>EPG server " . $epgserverpost['id'] . " updated</h1>\n";
		addlog(true,"EPG server " . $epgserverpost['id'] . " updated" );
		break;
	case 'delete':
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_deleteEPGserver( $myc , $epgserverpost );
				break;
                }
		print "<h1>EPG server " . $epgserverpost['id'] . " deleted</h1>\n";
		addlog(true,"EPG server " . $epgserverpost['id'] . " deleted" );
		break;
}

reloadUrl('Back to servers list','listepgservers.php');

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
