package NonameTV::Importer::ZDF;

use strict;
use warnings;

=pod

Importer for data from ZDF. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.
Same format as DreiSat.

=cut

use NonameTV::Log qw/progress w error/;

use NonameTV::Importer::DreiSat;

use base 'NonameTV::Importer::DreiSat';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "http://pressetreff.zdf.de/pd/DownloadWocheXML.asp?Woche=%d%02d&format=xml", $year, $week );

  progress("ZDF: fetching data from $url");

  return( $url, undef );
}


1;
