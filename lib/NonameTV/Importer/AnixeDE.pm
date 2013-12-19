package NonameTV::Importer::AnixeDE;

use strict;
use warnings;
use Encode qw/from_to/;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use NonameTV::Log qw/f/;
use NonameTV qw/norm ParseXml/;

use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use base 'NonameTV::Importer::BaseOne';

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
  my( $xmltvid, $year, $month, $day) = ( $objectname =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );

  my $url = 'http://www.anixehd.tv/prog.php';

  # Only one url to look at and no error
  return ([$url], undef);
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
  my $programs = $doc->find ('//article');
  if( $programs->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  foreach my $program ($programs->get_nodelist) {
    my ($year, $month, $day, $hour, $minute, $second) = ($program->findvalue ('bctime') =~ m|^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$|);
    my $start_time = DateTime->new ( 
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => 'Europe/Berlin'
    );
    $start_time->set_time_zone ('UTC');

    my $title = $program->findvalue ('titel');

    my $ce = {
      channel_id => $chd->{id},
      start_time => $start_time->ymd ('-') . ' ' . $start_time->hms (':'),
      title => $title,
    };

    my $description = $program->findvalue ('kurz');
    if ($description) {
      $ce->{description} = $description;
    }

    $ce->{quality} = 'HDTV';

    $self->{datastore}->AddProgramme ($ce);
  }

  return 1;
}


1;
