package NonameTV::Importer::DreiSat;

use strict;
use warnings;

=pod

Importer for data from DreiSat. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use XML::LibXML;
use Switch;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/progress w error/;
use NonameTV::Importer::ZDF_util qw/ParseData/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    if (defined $self->{UrlRoot}) {
      w ( $self->{Type} . ": deprecated parameter UrlRoot");
    }

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  # Tomica's (more like the files from ZDF and ZDFneo)
  my $url1 = sprintf( "http://pressetreff2.3sat.de/Public/Woche/3Sat_%04d%02d.XML", $year, $week);
  # Karl's (looks like some postprocessed version, basically the same)
  my $url2 = sprintf( "http://programmdienst.3sat.de/wspressefahne/Dateien/3sat_Woche%02d%02d.xml", $week, $year%100 );

#  progress($self->{Type} . ": fetching data from $url");

  return( [$url1, $url2], undef );
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $c;
  my $cref = \$c;

  gunzip $gzcref => $cref
    or $cref = $gzcref;

  # turn right single ' into '
  $$cref =~ s|&#8217;|'|g;

  my $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programmdaten" );

  if( $ns->size() == 0 ) {
    return (undef, "No channels found" );
  }
  
  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};

#  error ref ($cref);

  return ParseData ($batch_id, $cref, $chd, $ds);
}

1;
