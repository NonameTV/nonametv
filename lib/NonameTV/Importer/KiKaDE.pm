package NonameTV::Importer::KiKaDE;

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

    $self->{datastore}->{augment} = 1;

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
  my( $gzcref, $chd ) = @_;
  my $c;
  my $cref = \$c;

  # try to ungzip, just in case (we might be behind a filtering and compressing proxy)
  gunzip $gzcref => $cref
    or $cref = $gzcref;

  $$cref =~ s|
$||mg;
  $$cref =~ s|http://www.kika-presse.de/scripts/media/export/dtd/kika_programmWoche.dtd|http://www.kika-presse.de/media/export/dtd/kika_programmWoche.dtd|;
  # misescaped entities
  $$cref =~ s|&amp;#(\d+);|&#$1;|g;
  # convert misencoded entities (always unicode, never anything else in xml! its windows-1252 in this case)
  $$cref =~ s|&#x80;|&#x20AC;|g; # Euro
  $$cref =~ s|&#x82;|'|g;
  $$cref =~ s|&#x84;|"|g;
  $$cref =~ s|&#x85;|...|g;
  $$cref =~ s|&#x8a;|&#x160;|gi; # S
  $$cref =~ s|&#x8c;|&#x152;|gi; # OE
  $$cref =~ s|&#x8e;|&#x17d;|gi; # Z
  $$cref =~ s|&#x91;|'|g;
  $$cref =~ s|&#x92;|'|g;
  $$cref =~ s|&#x93;|"|g;
  $$cref =~ s|&#x94;|"|g;
  $$cref =~ s|&#x95;|&#x2022;|g; # *
  $$cref =~ s|&#x96;|-|g;
  $$cref =~ s|&#x97;|-|g;
  $$cref =~ s|&#x99;|&#x2122;|g; # TM
  $$cref =~ s|&#x9a;|&#x161;|gi; # s
  $$cref =~ s|&#x9c;|&#x153;|gi; # oe
  $$cref =~ s|&#x9e;|&#x17e;|gi; # z
  $$cref =~ s|&#x9f;|&#x178;|gi; # Y

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

    # copy start of programme to last programme in preparation of splitting multi episode slots
    my $lastprogram;
    foreach my $program ($programs->get_nodelist){
      if( defined( $lastprogram ) ){
        my $stop = $program->findvalue( '@Time' );
        my $attr = XML::LibXML::Attr->new( 'TimeStop', $stop );
        $lastprogram->addChild( $attr );
      }
      $lastprogram = $program;
    }

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

      if ($title eq 'end-of-transmission') {
        $self->{datastore}->AddProgramme ($ce);
      } else {
        ($hour, $minute) = ($program->findvalue ('@TimeStop') =~ m|(\d+)\.(\d+)|);
        if( !defined( $hour )||!defined( $minute ) ){
          f('missing expected stop time!');
          printf( "%s\n", $program->serialize()  );
        }
        my $stop_time = DateTime->new ( 
          year      => $year,
          month     => $month,
          day       => $day,
          hour      => $hour,
          minute    => $minute,
          time_zone => 'Europe/Berlin'
        );
        $stop_time->set_time_zone ('UTC');
        my $duration = $start_time->delta_ms( $stop_time )->minutes;

        my ($widescreen) = $program->findvalue ('ProgrammElement/Technik/T169');
        if ($widescreen eq '1') {
          $ce->{aspect} = '16:9';
        }

        my ($stereo) = $program->findvalue ('ProgrammElement/Technik/TStereo');
        if ($stereo eq '1') {
          $ce->{stereo} = 'stereo';
        }

        ($stereo) = $program->findvalue ('ProgrammElement/Technik/TDolby');
        if ($stereo eq '1') {
          $ce->{stereo} = 'dolby';
        }

        ($stereo) = $program->findvalue ('ProgrammElement/Technik/TZweikanalton');
        if ($stereo eq '1') {
          $ce->{stereo} = 'bilingual';
        }

        my ($captions) = $program->findvalue ('ProgrammElement/Technik/TUntertitel');
        if ($captions eq '1') {
          # $ce->{captions} = 'text';
        }

        my ($blackandwhite) = $program->findvalue ('ProgrammElement/Technik/TSw');
        if ($blackandwhite eq '1') {
          # $ce->{colour} = 'no';
        }

        # description of programme, for series it's the general description of the whole series
        my ($desc) = $program->findvalue ('ProgrammElement/LangText');
        if ($desc) {
          $ce->{description} = $desc;
          if (my ($original_title) = ($desc =~ m|Originaltitel:\s+\"(.*?)\"|)) {
            $ce->{original_title} = $original_title;
          }
        }

        if (my ($directors) = $program->findvalue ('ProgrammElement/ZusatzInfo/Regie')) {
          $directors =~ s|u\.a\.||;
          $directors =~ s|Diverse||;
          $directors = norm ($directors);
          if ($directors) {
            # directors are split by space slash space in the source data
            $ce->{directors} = join (';', split (/\s*\/\s*/, $directors));
          }
        }

        if (my ($zusatztitel) = $program->findvalue ('ProgrammElement/ZusatzTitel')) {
          # grab the year of production
          if (my ($country, $genre, $production_year) = ($zusatztitel =~ m|^(\S+)\s+(\S+)\s+(\d{4})$|)) {
            $ce->{production_date} = $production_year . '-01-01';
            if ($genre =~ m|film|i) {
              $ce->{program_type} = 'movie';
            }
          }
        }

        my $actors = $program->findnodes ('.//NameDarsteller');
        my @actors_array;
        if( $actors->size( ) > 0 ){
          foreach my $actor ($actors->get_nodelist()) {
            my $name = norm( $actor->string_value( ) );
            if( $name ){
              push( @actors_array, $name );
            }
          }
          $ce->{actors} = join( ';', @actors_array );
        }


        my $episodes = $program->findnodes ('ProgrammElement/Folge');
        if( $episodes->size( ) > 0 ){
          $ce->{program_type} = 'series';

          my $durationPerEpisode = $duration / $episodes->size( );

          foreach my $episode ($episodes->get_nodelist) {
            # copy ce hash to episode ce hash
            my %ece = %{$ce};

            # it's the absolute episode number in tvdb terms
            my $episodenumber = $episode->findvalue ('@Folgennummer');
            if( $episodenumber ){
              $ece{episode} = ' . ' . ($episodenumber-1) . ' . ';
            }

            my $episodetitle = $episode->findvalue ('FolgenTitel');
            # remove generic titles
            if( ( $episodetitle eq 'Folge' )||
                ( $episodetitle eq 'Teil' )||
                ( $episodetitle eq 'Titel wird nachgereicht.' )||
                ( $episodetitle eq 'Thema:' )||
                ( $episodetitle eq 'Thema: steht noch nicht fest!' ) ){
              $episodetitle = '';
              # FIXME, mark this as generic episode!
            }
            # strip leading "topic:"
            $episodetitle =~ s|^Folge\s+-\s+||;
            $episodetitle =~ s|^Thema:\s+||;
            if( $episodetitle ){
              $ece{subtitle} = $episodetitle;
            }
  
            my $episodedesc = $episode->findvalue ('FolgeLangText');
            if( ( $episodedesc ne 'Inhalt wird nachgereicht!' ) &&
               !( $episodedesc =~ m|^Inhalt momentan nicht verf..?gbar!$| ) ){
              $ece{description} = $episodedesc;
            }
            $self->{datastore}->AddProgramme (\%ece);

            # advance start time to start of the next episode
            $start_time->add( minutes => $durationPerEpisode );
            $ce->{start_time} = $start_time->ymd ('-') . ' ' . $start_time->hms (':'),
          }
        }else{
          # it is not an episode
          $self->{datastore}->AddProgramme ($ce);
        }
      }
    }
  }

  return 1;
}


1;
