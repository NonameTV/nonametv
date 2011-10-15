//
// common.js
//

// browser versioning stuff
var bV = parseInt(navigator.appVersion);
var is40 = parseInt( navigator.appVersion ) >= 4 ; 

var isNav = ( navigator.appName == "Netscape" );
var isIE = ! isNav ;

NS4 = (document.layers) ? 1 : 0;
IE4 = ((document.all) && (bV >= 4)) ? 1 : 0;
ver4 = (NS4 || IE4) ? 1 : 0;

function openDialog( href, name, options )
{
	if( ! href ) return null ; // can't do nuthin'

	var nW = null ;
	var defName = 'DIALOG' ;
	var defOptions = 'resizable=no,scrollbars=no,width=460,height=360,dependent' ;

	// set up defaults
	if ( ! options ) options = defOptions ;
	if ( ! name ) 	 name 	 = defName ;

//alert( href + "\n" + name + "\n" + options );

	nW = window.open( href, name, options );

	if ( nW && ( isNav || ( -1 == href.indexOf( ':' ) ) ) )
		nW.focus();

	return nW ;
}

function runprog_win( url )
{
  openDialog( url , 'runprog' , 'width=760,height=600,resizable=yes,scrollbars=yes,status=yes' );
}

function IPpick()
{
	var url = 'ippick.php';

	openDialog( url , "ippick" , "width=600,height=500,resizable=yes,scrollbars=yes,status=yes" );
}

function OwnersInfo( ownid )
{
	var url = 'mysql/displaytable.php?table=owners+id=' + window.document.host.owner[window.document.host.owner.selectedIndex].value;

	openDialog( url , "ownersinfo" , "width=600,height=500,resizable=yes,scrollbars=yes,status=yes" );
}

function LocationInfo( locid )
{
	var url = 'mysql/displaytable.php?table=location+id=' + window.document.host.loc[window.document.host.loc.selectedIndex].value;

	openDialog( url , "locationinfo" , "width=600,height=500,resizable=yes,scrollbars=yes,status=yes" );
}

function IPcheck( adr )
{
	var url = 'ippick.php?address=' + adr;

	openDialog( url , "ippick" , "width=600,height=500,resizable=yes,scrollbars=yes" );
}

function getCtrlValue ( ctrl )
{

//alert( "CTRL: " + ctrl.name + "," + ctrl.type );

	switch( ctrl.type )
	{
		case "text" :
		case "hidden":
		case "password":
		case "checkbox":
		case "radio":
			return ctrl.value ;

		case "select-one" :
		case "select-multiple" :
			if ( isIE ) return ctrl.value ;
			if ( -1 == ( ctrl.selectedIndex ) )	return "" ;
			return ctrl.options[ ctrl.selectedIndex ].value ;

		case "textarea":
			return ctrl.value ;

		default:
			alert( "getCtrlValue(): Control type Not Implemented: " + ctrl.type + "\ncontrol name = " + ctrl.name );
			return "" ;

	}	// switch( ctrl.type )

}	// getCtrlValue ()

function setCtrlValue ( ctrl, value )
{
//alert( "CTRL: " + ctrl.name + "," + ctrl.type );
	switch( ctrl.type )
	{
		case "text" :
		case "hidden" :
		case "password" :
		    ctrl.value = value ;
			break;

		/* for select lists, find and select the option whose
		   VALUE == this.m_props[ prop ].value
		*/
		case "select-one" :
		case "select-multiple" :
			if ( isIE ) 
			{
				ctrl.value = value ;
				break;
			}
			else
			{
				for ( var i=0; i < ctrl.options.length; i++ )
				{
				    if ( ctrl.options[i].value == value )
					{
						ctrl.selectedIndex = i ;
						//alert( ctrl.name + "[" + i + "]:" + ctrl.options[i].value );
						break ;
					}
				}
				break;
			}

		case "checkbox":
			ctrl.checked = ( value ) ? true : false ;
			break;

		case "radio":
			ctrl.checked = ( value ) ? true : false ;
			break;

		case "textarea":
			ctrl.value = value ;
			break;

		default:
			alert( "setCtrlValue(): Control type Not Implemented: " + ctrl.type + "\ncontrol name = " + ctrl.name );

	}	// swtich( ctrl.type )

}	// setCtrlValue ()

function izaberiadresu( adr )
{

	oldadr = getCtrlValue( window.opener.document.host.ips );

	newadr = oldadr + "\n" + adr;
	
	setCtrlValue( window.opener.document.host.ips , newadr );
}

function viewfile( f )
{
	window.location.href = "viewfile.php?file=" + f;
}

function poruka( text )
{
	alert( text );
}

function nsUpdate( action , zone , name , type , value )
{
	var url = 'nsupdate.php?action=' + action + '+zone=' + zone + '+name=' + name + '+type=' + type + '+value=';

	if( type == 'txt' ) url += "\"" + value + "\"";
	else url += value;

	openDialog( url , "nsupdate" , "width=600,height=400,resizable=yes,scrollbars=yes,status=yes" );
}

function LiveUpdate( kaj , zone )
{
	var url = 'nsupdate.php?liveupdate=' + kaj + '+zone=' + zone;

	openDialog( url , "nsupdate" , "width=600,height=400,resizable=yes,scrollbars=yes,status=yes" );
}

function sendLiveUpdate()
{
	req = getCtrlValue( window.nsupdate.sendnsreq );
//alert( req );
	window.location.href = "nsupdate.php?sendnsreq=" + escape(req);
}

function upisiZonu()
{
	return prompt("Enter zone");
}

function popup_description( text )
{
	window.status = text;
}

function hide_description()
{
	window.status = "";
}

function ShowAttribs(oElem)
{
    var txtAttribs;

    // Retrieve the collection of attributes for the specified object.
    var oAttribs = oElem.attributes;

    // Iterate through the collection.
    for (var i = 0; i < oAttribs.length; i++)
    {
        var oAttrib = oAttribs[i];

        // Print the name and value of the attribute. 
        // Additionally print whether or not the attribute was specified
        // in HTML or script.
        txtAttribs += oAttrib.nodeName + '=' + oAttrib.nodeValue + ' (' + oAttrib.specified + ')\n'; 
    }
    alert(txtAttribs);
}
