package NonameTV::Importer::DWDE;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use Encode qw/decode/;
use XML::LibXML;

use NonameTV qw/AddCategory Html2Xml ParseXml norm/;
#use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseOne;
use NonameTV::Log qw/d p w f/;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
#    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Only one url to look at and no error
  return ([$chd->{grabber_info}], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # FIXME convert latin1/cp1252 to utf-8 to HTML
  # $cref = decode( 'windows-1252', $cref );

  # cut away frame around tables
  $$cref =~ s|^.*?(<table cell.+<!-- / col4 -->).*$|<html><body>$1</body></html>|s;

  my $doc = Html2Xml ($$cref);
  $doc->setEncoding( 'utf-8' );
  $cref = $doc->toString ();

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'html';
}

sub normX {
  my $theString = shift;
  if ($theString) {
    $theString =~ s|[\r\n]+| |gs;
    $theString =~ s|[[:space:]]+| |g;
    $theString =~ s/^\s+//;
    $theString =~ s/\s+$//;
    if ($theString eq '') {
      $theString = undef;
    }
  }

  return $theString;
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
#  my $dsh = $self->{datastorehelper};

  my $doc;
  eval { $doc = ParseXml ($cref); };
  if( $@ ne "" )
  {
    w( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  # Find all "tr"-elements that have a class attribute => programme row.
  my $ns = $doc->find( '//tr[@class!="legend"]' );
  if( $ns->size() == 0 ){
    w( "$batch_id: No programme rows found" );
    return 0;
  }
  p( "Found " . $ns->size() . " shows" );

  foreach my $sc ($ns->get_nodelist)
  {
    my %ce = (
        channel_id  => $chd->{id},
    );

    # the series title
    my $title = $sc->findvalue( './td/div/a' );
    $ce{title} = norm(decode('utf-8', $title));

    # the series subtitle (not an episode title!)
    my $subtitle = $sc->findvalue( './td/div/div/h2' );
    $ce{subtitle} = norm(decode('utf-8', $subtitle));

    # the start time (unixtime in msec utc)
    my $starttime = $sc->findvalue( './td/script' );
    $starttime =~ s|^.*\((\d+)\).*$|$1|s;
    $starttime = $starttime / 1000;
    $starttime = DateTime->from_epoch( epoch => $starttime );
    $ce{start_time} = $starttime->ymd("-") . " " . $starttime->hms(":");

    # the synopsis
    my $desc = $sc->findvalue( './td/div/div/p/text()' );
    $ce{description} = normX(decode('utf-8', $desc));

    d ("$ce{start_time} - $ce{title} - $ce{subtitle}\n");
    if( defined( $ce{description} ) ){
      d ("$ce{description}\n");
    }

    my ( $program_type, $categ ) = $ds->LookupCat( "DeutscheWelle", $ce{title} );
    AddCategory( \%ce, $program_type, $categ );

    $ds->AddProgramme( \%ce );
  }

  return 1;
}


1;
