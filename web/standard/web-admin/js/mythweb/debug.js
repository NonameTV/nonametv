/**
 * A random assortment of javascript debug routines
 *
 * @url         $URL: svn+ssh://ijr@cvs.mythtv.org/var/lib/svn/trunk/mythplugins/mythweb/js/debug.js $
 * @date        $Date: 2006-03-21 03:15:41 -0500 (Tue, 21 Mar 2006) $
 * @version     $Revision: 9435 $
 * @author      $Author: xris $
 * @copyright   Silicon Mechanics
 * @license     LGPL
 *
 * @package     SiMech
 * @subpackage  Javascript
 *
/**/

    var debug_window_handle;
// Create a debug window and debug into it
    function debug_window(string) {
        if (!debug_window_handle || debug_window_handle.closed) {
            debug_window_handle = window.open('', 'Debug Window','scrollbars, resizable, width=400, height=600');
            debug_window_handle.document.write('<html><body style="font-size: 9pt; background-color: #f88;">');
        }
        debug_window_handle.document.write('<pre>'+string+'</pre><hr>');
    }
