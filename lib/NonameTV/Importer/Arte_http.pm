package NonameTV::Importer::Arte_http;

use strict;
use warnings;

=pod

Download weekly word file in zip archive from arte pro

=cut

use DateTime;

use IO::Uncompress::Unzip qw/unzip/;
use NonameTV qw/ParseXml Word2Xml/;
use NonameTV::Importer::Arte_util qw/ImportFull/;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/p/;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    if ($self->{MaxWeeks} > 6) {
        $self->{MaxWeeks} = 6;
    }

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore} );

    return $self;
}

sub InitiateDownload {
  my $self = shift;

  my $mech = $self->{cc}->UserAgent();

  my $response = $mech->get('http://w3.artepro.com/Login.cfm?Identifiant=' . $self->{Username} . '&Password=' . $self->{Password});

  if ($response->is_success) {
    return undef;
  } else {
    return $response->status_line;
  }
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $url = sprintf( "http://w3.artepro.com/popup/download_texte.cfm?Filelist=%d/%d,", $year, $week);

  p ($self->{Type} . ": fetching data from $url");

  return( $url, undef );
}

sub ContentExtension {
  return 'zip';
}

sub FilterContent {
  my $self = shift;
  my( $zref, $chd ) = @_;

  if (!($$zref =~ m/^PK/)) {
    return (undef, "returned data is not a zip file");
  }

  my $cref;
  unzip $zref => \$cref;

  my $doc = Word2Xml( $cref );

  if( not defined $doc ) {
    return (undef, "Word2Xml failed" );
  }

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $doc = ParseXml ($cref);

  ImportFull ($batch_id, $doc, $chd, $self->{datastorehelper});

  return 1;
}


1;
