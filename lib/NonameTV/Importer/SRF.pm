package NonameTV::Importer::SRF;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

Registration at: https://medienportal.srf.ch/app/
Webservice documentation available via: http://www.crosspoint.ch/index.php?is_presseportal_ws

TODO handle regional programmes on DRS

=cut

use Encode qw/from_to/;

use NonameTV qw/AddCategory ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f/;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore}, 'Europe/Zurich' );

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $xmltvid, $date ) = ( $objectname =~ /^(.+)_(\d+-\d+-\d+)$/ );

  if (!defined ($chd->{grabber_info})) {
    return (undef, 'Grabber info must contain channel id!');
  }

  my $url = sprintf( 'https://medienportal.srf.ch/app/ProgramInfo.asmx/getProgramInfoExtendedHD' .
    '?username=%s&password=%s&channel=%s&fromDate=%s&toDate=%s', $self->{Username}, $self->{Password}, $chd->{grabber_info}, $date, $date );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  return( $cref, undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $doc = ParseXml ($cref);
  
  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  # The data really looks like this...
  my $ns = $doc->find ('//SENDUNG');
  if( $ns->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  my $date = $doc->findvalue( '//SENDUNG[1]/DATUM' );
  $date =~ s|(\d+)\.(\d+)\.(\d+)|$3-$2-$1|;
  $self->{datastorehelper}->StartDate( $date );

  foreach my $programme ($ns->get_nodelist) {
    my ($time) = ($programme->findvalue ('./ZEIT') =~ m|(\d+\:\d+)|);
    if( !defined( $time ) ){
      w( 'programme without start time!' );
    }else{
      my ($title) = $programme->findvalue ('./TITEL');

      my $ce = {
#        channel_id => $chd->{id},
        start_time => $time,
        title => $title
      };

      my ($subtitle) = $programme->findvalue ('./UNTERTITEL');
      if( $subtitle ){
        $ce->{subtitle} = $subtitle;
      }

      my ($description) = $programme->findvalue ('./INHALT');
      if( !$description ){
        ($description) = $programme->findvalue ('./LEAD');
      }
      if( $description ){
        $ce->{description} = $description;
      }

      my ($genre) = $programme->findvalue ('./GENRE');
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "SRF", $genre );
      AddCategory( $ce, $program_type, $categ );

      my ($year) = $programme->findvalue ('./PRODJAHR');
      if( $year ){
        $ce->{production_date} = $year . '-01-01';
      }

      $self->{datastorehelper}->AddProgramme( $ce );
    }
  }

  return 1;
}


1;
