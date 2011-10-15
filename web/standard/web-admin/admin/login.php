<?php
require "../config.php";
require "../common.php";
require "../mysql.php";
require "admins.php";

$debug = false;

//
// start session and perform user login
//
start_nonametv_session();

if( $debug ) dbg( "dconf" , $dconf );

//
// connect to main database
//
switch( $dconf['dbtype'] ){
	case 'mysql':
		$myc = sql_doconnect();
		if( !$myc ) exit;
		break;
}

// check posted data
if( $debug ) dbg( "_POST" , $_POST );
if( $debug ) dbg( "_REQUEST" , $_REQUEST );

if( isset( $_POST['Login'] ) ){

	$dad = login_check( $_POST['username'] , $_POST['password'] );
	if( $debug ) dbg( "Authorized admin" , $dad );

	// if admin is authorized then
	// pass the data via session and then reload NonameTV
	if( $dad ){

		// update last login time and location
		$tmpadm['username'] = $dad['username'];
		$tmpadm['lastlogin'] = time();
		$tmpadm['lastlocation'] = $REMOTE_ADDR;
		sql_azurirajAdmin( $myc , $tmpadm );

		// set data which we pass via session
		$_SESSION['username'] = $dad['username'];
		$_SESSION['fullname'] = $dad['fullname'];
		$_SESSION['email'] = $dad['email'];
		$_SESSION['language'] = $dad['language'];
		$_SESSION['ismaster'] = $dad['ismaster'];
		$_SESSION['roleeditor'] = $dad['roleeditor'];

		// redirect
		print "<script language=javascript>\n";
		if( $debug ) print "  alert(\"bingoooooooooooooo!\");\n";
		else print "  top.location.href = \"../index.php\";\n";
		print "</script>\n";
	} else {
		print "<center>\n";
		print "<h3>Incorrect username and/or password</h3>\n";
		print "</center>\n";
	}

	if( $debug ){
		dbg( "_SESSION" , $_SESSION );
		phpinfo();
		exit;
	}
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
<html>
<head>
<title>NonameTV: Login</title>
<meta http-equiv="Content-Type" content="text/html; charset=<?php print $lngstr[codepage]; ?>">
<link href="../css/nonametv.css" rel=stylesheet>
</head>
<body>

<center>

<br><br><br><br>

<form name="login" method="post" action="login.php">
  <table>
    <tr class="tableTitle">
      <td align="center" colspan="2">Login to NonameTV</td>
    </tr>
    <tr class="tableBody">
      <td align="right">Username:</td><td><input type="text" name="username" maxlength="12"></td>
    </tr>
    <tr class="tableBody">
      <td align="right">Password:</td><td><input type="password" name="password" maxlength="12"></td>
    </tr>
    <tr class="tableTitle">
      <td align="center" colspan="2"><input class="gumb" type="submit" name="Login" value="Login"></td>
    </tr>
  </table>
</form>

</center>

</body>
</html>
