package NonameTV::Importer::PinkTV;

=pod

This importer imports data from PinkTV's press service. The data is fetched
as one html per day and channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Encode;

use NonameTV qw/MyGet Html2Xml FindParagraphs AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $dsh->{DETECT_SEGMENTS} = 1;
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ($objectname =~ /_(\d+)-(\d+)-(\d+)/);

  my $url;

  if( $chd->{grabber_info} =~ /^http:/i ){
    $url = $chd->{grabber_info} . '?dan=' . sprintf( '%02d%02d%02d', $year, $month, $day );
  } else {
    $year -= 2000 if $year gt 2000;
    $url = $self->{UrlRoot} . '?zona=0'
      . '&dan=' . sprintf( '%02d%02d%02d', $year, $month, $day )
      . '&tv=' . $chd->{grabber_info};
  }

  progress("Fetching data from $url");

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

#sub FilterContent {
#  my $self = shift;
#  my( $cref, $chd ) = @_;
#
##print "$$cref\n";
#  my $doc = Html2Xml( $$cref );
##print "$doc\n";
#
#  if( not defined $doc ) {
#    return (undef, "Html2Xml failed" );
#  }
#
#  my $paragraphs = FindParagraphs( $doc, "//." );
#foreach my $p (@$paragraphs) {
#print "p: $p\n";
#}
#
#  my $str = join( "\n", @{$paragraphs} );
#print "str $str\n";
#
#  return( \$str, undef );
#}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my @lines = split( /\n/, $$cref );

  if( scalar(@lines) == 0 ) {
    error( "$batch_id: No lines found." ) ;
    return 0;
  }

  $dsh->StartDate( $date, "02:00" );

  my $ce = undef;

  foreach my $text (@lines) {

#print ">$text<\n";

    if( isShow( $text ) ){

      my( $title, $genre, $time ) = ParseShow( $text );

      $title = decode("windows-1250", $title);

      progress("PinkTV: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( "PinkTV", $genre );
        AddCategory( $ce, $program_type, $category );
      }
  
      $dsh->AddProgramme( $ce );
    }
  }
  
  # Success
  return 1;
}

sub isShow {
  my( $text ) = @_;

  if ( $text =~ /new Array\(\'/ ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $title, $genre, $time ) = ( $text =~ /new Array\(\'(.*)\',.*,.*,.*,(.*),.*,\'(.*)\',.*,.*,.*,.*,.*,.*,.*,/ );

  return( $title, $genre, $time );
}

1;
