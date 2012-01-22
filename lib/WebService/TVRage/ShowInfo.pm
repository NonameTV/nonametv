#===============================================================================
#         FILE:  ShowInfo.pm
#       AUTHOR:  Joakim Nylén, http://tvtab.la
#      COMPANY:  dotMedia Networks
#===============================================================================

use strict;
use warnings;

package WebService::TVRage::ShowInfo;

use Mouse;
use LWP::UserAgent;
use HTTP::Request::Common;
use XML::Simple;
use Data::Dumper;
use WebService::TVRage::Show;
has 'showId' => ( is => 'rw');
has 'URL' => ( is => 'rw',
               default => 'http://www.tvrage.com/feeds/showinfo.php?sid=');

sub search {
    my $self = shift;
    my $showId = shift;
    sleep (1);
    $self->showId($showId);
    my $uA = LWP::UserAgent->new( timeout => 20);
    my $showSearchReq = HTTP::Request->new(GET => $self->URL . $self->showId);
    my $showSearchResponse = $uA->request($showSearchReq);
    print $showSearchResponse->error_as_HTML unless $showSearchResponse->is_success;
    my $xml = new XML::Simple;
    my $processedXML = $xml->XMLin( $showSearchResponse->decoded_content, (ForceArray => ['Showinfo']));
    return undef if $processedXML == 0;
    my $object = WebService::TVRage::Show->new();
    $object->_showHash($processedXML);
    return $object;
}

1;