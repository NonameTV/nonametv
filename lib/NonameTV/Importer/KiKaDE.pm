package NonameTV::Importer::KiKaDE;

use strict;
use warnings;
use Encode qw/from_to/;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use NonameTV::Log qw/f/;
use NonameTV qw/ParseXml/;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    # at most 7 weeks, limit to 4 to roughly match 32day default
    if ($self->{MaxWeeks} > 4) {
      $self->{MaxWeeks} = 4;
    }

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $xmltvid, $year, $week ) = ( $objectname =~ /^(.+)_(\d+)-(\d+)$/ );

  if (!defined ($chd->{grabber_info})) {
    return (undef, 'Grabber info must contain path!');
  }

  my $url = sprintf( 'http://www.kika-presse.de/media/export/text%dpw%02d.xml', $year , $week );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref =~ s|$||g;
  $$cref =~ s|http://www.kika-presse.de/scripts/media/export/dtd/kika_programmWoche.dtd|http://www.kika-presse.de/media/export/dtd/kika_programmWoche.dtd|;
  # misescaped entities
  $$cref =~ s|&amp;#(\d+);|&#$1;|g;
  # convert misencoded entities (always unicode, never anything else in xml!)
  $$cref =~ s|&#x80;|&#x20AC;|g; # Euro
  $$cref =~ s|&#x82;|'|g;
  $$cref =~ s|&#x84;|"|g;
  $$cref =~ s|&#x85;|...|g;
  $$cref =~ s|&#x91;|'|g;
  $$cref =~ s|&#x92;|'|g;
  $$cref =~ s|&#x93;|"|g;
  $$cref =~ s|&#x94;|"|g;
  $$cref =~ s|&#x96;|-|g;
  $$cref =~ s|&#x97;|-|g;
  $$cref =~ s|&#x99;|&#x2122;|g; # TM

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
  my $ns = $doc->find ('//ProgrammTag');
  if( $ns->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  foreach my $tag ($ns->get_nodelist) {
    my ($day, $month, $year) = ($tag->findvalue ('@date') =~ m|(\d+)\.(\d+)\.(\d+)|);
    my $programs = $tag->find ('ProgrammPunkt');

    foreach my $program ($programs->get_nodelist) {
      my ($hour, $minute) = ($program->findvalue ('@Time') =~ m|(\d+)\.(\d+)|);
      my $start_time = DateTime->new ( 
        year      => $year,
        month     => $month,
        day       => $day,
        hour      => $hour,
        minute    => $minute,
        time_zone => 'Europe/Berlin'
      );
      $start_time->set_time_zone ('UTC');

      my ($title) = $program->findvalue ('ProgrammElement/Titel');
      if ($title eq 'Sendeschluss') {
        $title = 'end-of-transmission';
      }

      my $ce = {
        channel_id => $chd->{id},
        start_time => $start_time->ymd ('-') . ' ' . $start_time->hms (':'),
        title => $title
      };

      my $episodes = $program->findnodes ('ProgrammElement/Folge');
      my ($desc, $episodenumber, $subtitle, $multipleepisodes);
      foreach my $episode ($episodes->get_nodelist) {
        my $episodetitle = $episode->findvalue ('FolgenTitel');
        $episodenumber = $episode->findvalue ('@Folgennummer');
        if ($subtitle) {
          $subtitle .= ' / ';
          $desc .= "\n\n";
          $multipleepisodes = 1;
        }
        if (($episodetitle eq 'Teil') || ($episodetitle eq 'Folge') ){
          $episodetitle = 'Folge ' . $episodenumber;
        }
        if( $episodetitle ne 'Titel wird nachgereicht.' ){
          $subtitle .= $episodetitle;
        }

        my $episodedesc = $episode->findvalue ('FolgeLangText');
        if( $episodedesc ne 'Inhalt wird nachgereicht!' ){
          $desc .= $episodedesc;
        }
      }

      if (!$desc) {
        $desc = $program->findvalue ('ProgrammElement/LangText');
      }

      if ($subtitle) {
        $ce->{subtitle} = $subtitle;
        $ce->{program_type} = 'series';
      }

      if ($desc) {
        $ce->{description} = $desc;
      }

      if ((!$multipleepisodes) && ($episodenumber)) {
        $ce->{episode} = ' . ' . ($episodenumber-1) . ' . ';
      }

      $self->{datastore}->AddProgramme ($ce);
    }
  }

  return 1;
}


1;
