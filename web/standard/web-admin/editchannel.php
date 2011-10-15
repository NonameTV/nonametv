<?php
 
require "config.php";
require "common.php";
require "mysql.php";
require "channels.php";
 
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
<title>Channel details</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<link href="css/nonametv.css" rel=stylesheet>
<script language="JavaScript1.2" src="js/common.js"></script>
</head>
<body bgcolor="#FFFFFF" text="#000000">

<?php

function channelform( $ch )
{
	global $action;
	global $dconf;
	global $chgdb;

	print "<h1>Edit channel details: " . $ch['id'] . "</h1>\n";
	print "<form name=channel action=\"editchannel.php\" method=post>\n";
	switch( $action ){
		case 'none':
		case 'add':
		case 'update':
		case 'delete':
			print "  <input type=\"hidden\" name=\"id\" value=\"" . $ch['id'] . "\">\n";
		break;
	}
	print "  <table>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">General channel settings</td>\n";
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
		 	print $ch['id'];
			break;
		case 'new':
			print "<input type=\"text\" name=\"id\" value=\"" . $ch['id'] . "\" size=\"12\" maxlength=\"12\">\n";
		break;
	}
	print "</td>\n";
	print "    </tr>\n";
	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Display Name</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"display_name\" value=\"" . $ch['display_name'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">XMLTV ID</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"xmltvid\" value=\"" . $ch['xmltvid'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Channel group</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <select name=\"chgroup\">\n";
	reset($chgdb);
	while( list( $gk , $gv ) = each($chgdb) ){
		print "          <option value=\"" . $gv['abr'] . "\">" . $gv['display_name'] . "</option>\n";
	}
	print "        </select>\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">Importer settings</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Grabber</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"grabber\" value=\"" . $ch['grabber'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Grabber Info</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"grabber_info\" value=\"" . $ch['grabber_info'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">Exporter settings</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Export</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"checkbox\" name=\"export\" value=\"1\"" ;
	if( $ch['export'] == '1' ) print " checked";
	print "> check if you want to export this channel\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Logo</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"checkbox\" name=\"logo\" value=\"1\"" ;
	if( $ch['logo'] == '1' ) print " checked";
	print "> check if you have logo available for this channel<br>\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr class=\"tableTitle\">\n";
	print "      <td colspan=\"2\">Additional settings</td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Default Program Type</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"def_pty\" value=\"" . $ch['def_pty'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Default Category</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"def_cat\" value=\"" . $ch['def_cat'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Language used for schedules</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"sched_lang\" value=\"" . $ch['sched_lang'] . "\" size=\"100\" maxlength=\"100\">\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">OK if empty</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"checkbox\" name=\"empty_ok\" value=\"1\"" ;
	if( $ch['empty_ok'] == '1' ) print " checked";
	print "> check if it is ok to have no data for this channel<br>\n";
	print "      </td>\n";
	print "    </tr>\n";

	print "    <tr>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <div align=\"right\">Channel url</div>\n";
	print "      </td>\n";
	print "      <td class=\"tableBody\">\n";
	print "        <input type=\"text\" name=\"url\" value=\"" . $ch['url'] . "\" size=\"100\" maxlength=\"100\">\n";
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

	print "<script language=javascript>\n";
	print "  setCtrlValue( window.document.channel.chgroup , \"" . $ch['chgroup'] . "\" );\n";
	print "</script>\n";
}

//
// main
//

// arguments from the command line/url
if( $debug ) dbg( "REQUEST" , $_REQUEST );
if( isset($_REQUEST['action']) ) $action = $_REQUEST['action'];
if( isset($_REQUEST['channel']) ) $channelarg = $_REQUEST['channel'];

// posted data
if( $debug ) dbg( "_POST" , $_POST );

if(isset($_POST['id'])) $channelpost['id'] = $_POST['id'];
if(isset($_POST['display_name'])) $channelpost['display_name'] = $_POST['display_name'];
if(isset($_POST['xmltvid'])) $channelpost['xmltvid'] = $_POST['xmltvid'];
if(isset($_POST['chgroup'])) $channelpost['chgroup'] = $_POST['chgroup'];
if(isset($_POST['grabber'])) $channelpost['grabber'] = $_POST['grabber'];
if(isset($_POST['export'])) $channelpost['export'] = $_POST['export'];
if(isset($_POST['grabber_info'])) $channelpost['grabber_info'] = $_POST['grabber_info'];
if(isset($_POST['logo'])) $channelpost['logo'] = $_POST['logo'];
if(isset($_POST['def_pty'])) $channelpost['def_pty'] = $_POST['def_pty'];
if(isset($_POST['def_cat'])) $channelpost['def_cat'] = $_POST['def_cat'];
if(isset($_POST['sched_lang'])) $channelpost['sched_lang'] = $_POST['sched_lang'];
if(isset($_POST['empty_ok'])) $channelpost['empty_ok'] = $_POST['empty_ok'];
if(isset($_POST['url'])) $channelpost['url'] = $_POST['url'];

if( $debug ) dbg( "channelpost" , $channelpost );

// set default values if not set
if( isset($channelpost) ) $channelpost = set_channel_defaults( $channelpost );

// convert to lowercase
if( $dconf['lowercase'] && isset($channelpost) ){
        $channelpost['xmltvid'] = strtolower( $channelpost['xmltvid'] );
}

//
// action from form
//
if( isset($_POST['Add']) && $_POST['Add'] == 'Add' ) $action = 'add';
if( isset($_POST['Update']) && $_POST['Update'] == 'Update' ) $action = 'update';
if( isset($_POST['Delete']) && $_POST['Delete'] == 'Delete' ) $action = 'delete';

//
// check if there is already a channel with this name
//
if( $action != 'new' ){
        switch( $dconf['dbtype'] ){
		case 'mysql':

                	// first try to find from posted data
                	if( !$found && isset($channelpost['id']) ) $found = sql_findChannel( $myc , 'id' , $channelpost['id'] );
                	if( $debug && $found ){
                        	dbg( "sql: found from posted data" , $found );
                	}

                	// if !found with posted data
                	// try to find with data from arguments
                	if( !$found && $channelarg ) $found = sql_findChannel( $myc , 'id' , $channelarg );
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
                        print ("<h3>Invalid channel: " . $channelarg . " </h3>\n");
                        exit;
                case 'new': // if action==new -> we need blank form for new channel
                        if( $channelarg ) $channel['id'] = $channelarg; else $channel['id'] = '';
			$channel = set_channel_defaults( $channel );
                        break;
                default:
                        //dbg($action,"...");
                        break;
        }
}
else $channel = $found;

// remember current dhcp group
// on delete or update channel should be removed from old group
//$channel[olddhcpgroup] = $channel[dhcpgroup];

switch( $action ){
	case 'none':
	case 'new':
		$chgdb = load_channelgroups( $myc );
		channelform( $channel );
		break;
	case 'add':
		if( $found && !strcasecmp($found['id'],$channelpost['id'] )){
                        print "<h1>Channel with ID " . $channelpost['id'] . " exists</h1>\n";
                        reloadUrl('Continue','channelslist.php');
                        print "<script language=\"javascript\">\n";
                        print "  url = 'showchannel.php?name=" . $found[name] . "';\n";
                        print "  openDialog( url , 'showchannel' , 'width=300,height=300,resizable=yes,scrollbars=yes,status=yes' );\n";
                        print "</script>\n";
                        break;
		}
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_addChannel( $myc , $channelpost );
				break;
                }

		print "<h1>Channel " . $channelpost['id'] . " added</h1>\n";
		reloadUrl('Continue','channelslist.php');
		addlog(true,"Channel " . $channelpost['id'] . " added" );
		break;
	case 'update':
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_updateChannel( $myc , $channelpost );
				break;
                }

		print "<h1>Channel " . $channelpost['id'] . " updated</h1>\n";
		reloadUrl('Continue','channelslist.php');
		addlog(true,"Channel " . $channelpost['id'] . " updated" );
		break;
	case 'delete':
                switch( $dconf['dbtype'] ){
			case 'mysql':
                        	sql_deleteChannel( $myc , $channelpost );
				break;
                }
		print "<h1>Channel " . $channelpost['id'] . " deleted</h1>\n";
		reloadUrl('Continue','channelslist.php');
		addlog(true,"Channel " . $channelpost['id'] . " deleted" );
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
