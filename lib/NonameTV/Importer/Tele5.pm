package NonameTV::Importer::Tele5;

use strict;
use warnings;

=pod

Channels: Tele5 and all SWR channels
Country: Germany

Import data from Richtext-files delivered via e-mail or web.
There is a seperate file for each channel/week.

Features:
 * do not store descriptive texts outside of german speaking area for Tele5
 * split SWR Fernsehen into it's three regional variants

Grabber Info: name, variant
 * Name of channel in files (as a safe guard)
 * Name of regional variant (BW, RP, SR) for channel SWR FS

=cut

use DateTime;
use Encode qw/from_to/;
use RTF::Tokenizer;
use utf8;

use NonameTV::Log qw/d p w error f/;
use NonameTV qw/AddCategory MonthNumber norm normLatin1 normUtf8/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  if (!defined $self->{ServerInDeAtCh}) {
    warn 'Programme sysnopsis may only be stored on servers in germany, austria and switzerland. Set ServerInDeAtCh to yes or no.';
    $self->{ServerInDeAtCh} = 'no';
  }
  if ($self->{ServerInDeAtCh} eq 'yes') {
    $self->{KeepDesc} = 1;
  }

  $self->{datastore}->{augment} = 1;

  $self->{RTFDebug} = 0;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my @grabber_info = split( /,\s*/, $chd->{grabber_info} );
  $self->{channel_name} = shift( @grabber_info );
  if( $self->{channel_name} eq 'SWR' ) {
    $self->{region_name} = shift( @grabber_info );
#    # needed as regional programs may start together but have different running times which we don't get
#    $self->{datastore}->{SILENCE_END_START_OVERLAP} = 1;
  }

  my $regexp = $self->{channel_name} . '(?:_[MDFS][oira]|)_Pw_[[:digit:]]+A\.rtf';
  $regexp =~ s|\s|_|g;

  if ( $file =~ /$regexp/i ){
    $self->ImportRTF ($file, $chd);
  } else {
    p( 'unknown file: ' . $file );
  }

  return;
}

sub ImportRTF {
  my $self = shift;
  my( $file, $chd ) = @_;

  p( "Tele5: Processing $file" );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $channel_name = $self->{channel_name};
  my $region_name = $self->{region_name};

  my $tokenizer = RTF::Tokenizer->new( file => $file );

  if( not defined( $tokenizer ) ) {
    error( "Tele5 $file: Failed to parse" );
    return;
  }

  my $enoughtext = 0;
  my $desc = '';
  my $text = '';
  my $textfull = 0;
  my $date;
  my $currdate = undef;
  my $title;
  my $havedatetime = 0;

  my $gotbatch;
  my $laststart;

  my $infooter = 0;
  my $grouplevel = 0;

  my $copyrightstring;
  if( $channel_name eq 'Tele 5' ) {
    $copyrightstring = "\n" . chr(169) . ' by Tele5' . chr(174);
  } else {
    $copyrightstring = '';
  }
  

  while( my ( $type, $arg, $param ) = $tokenizer->get_token( ) ){
    if( $type eq 'text' ){
      $arg = Encode::decode ('windows-1252', $arg);
    }

#    last if( $type eq 'eof' );

    if( ( $type eq 'control' ) and ( $arg eq 'par' ) ){
        if( $grouplevel == 3 ) {
          $desc .= "\n";
        }else{
          $text .= "\n";
        }
    } elsif( ( $type eq 'control' ) and ( $arg eq 'tab' ) ){
        if( $grouplevel < 3 ) {
          $text .= "\t";
        }
    } elsif( ( $type eq 'control' ) and ( ( $arg eq '*' ) or ( $arg eq 'fonttbl' ) or ( $arg eq 'footer' ) or ( $arg eq 'header' ) ) ){
      if( $self->{RTFDebug} ) {
        d( 'footerstart' );
      }
      $text .= "\n";
      if( $infooter == 0 ) {
        $infooter = $grouplevel;
      }
    } elsif( ( $type eq 'group' ) ){
      if( $arg == 0 ) {
        if( $grouplevel == $infooter ) {
          if( $self->{RTFDebug} ) {
            d( 'footerend' );
          }
          $infooter = 0;
          $desc = '';
          $text = '';
        }
        $grouplevel -= 1;
      } elsif( $arg == 1 ) {
        $grouplevel += 1;
      } else {
        e( 'error in group handling' );
      }
    } elsif( $type eq 'eof' ){
      $text .= "\n\n";
    } elsif( ( $type eq 'text' ) and ( $infooter == 0 ) and ( $enoughtext == 0 ) ){
      if( $arg =~ m/^(?:Auszeichnungen|Hintergrund der Handlung|Hintergrund zur Serie|Serienkurztext|Starinfo.*?|Zur Serie):/ ){
        # ignore text from here on
        $enoughtext = 1;
      } else {
        if( $grouplevel == 3 ) {
          $desc .= ' ' . $arg;
        }elsif(($arg ne 'Planet Schule') && ($arg ne 'TAGESTIPP')){
          $text .= ' ' . $arg;
        }
        if( $self->{RTFDebug} ) {
          d( 'text(' . $grouplevel .'):' . $arg );
        }
      }
    } else {
      if( $self->{RTFDebug} ) {
        d( 'unknown type: ' . $type . ':' . $arg );
      }
    }

    if( $text =~ m|\n\n\n$| ){
      $text =~ s|^\s+||m;
      $text =~ s|\s+$||m;
      $text =~ s|\n+$||;

      # got one block, either a new day or one program
      if( $text =~ m|^[\s\n]*$|s ) {
        # empty block
        d( 'empty block: ' . $text );
      } elsif ($text =~ m|$channel_name, Programmwoche|) {
        d( 'parsing date from: ' . $text );
        my ($week, $daystring) = ($text =~ m|$channel_name, Programmwoche (\d+)\n ([^\n]*)|);
        my ($day, $month, $year) = ($daystring =~ m|(\d+)\. (\S+) (\d+)|);
        $month = MonthNumber ($month, 'de');

        if (!$gotbatch) {
          $gotbatch = 1;
          if( $file =~ m|_[MDFS][oira]_Pw_\d+A.rtf$| ){
            $self->{datastore}->StartBatch ($chd->{xmltvid} . '_' . $year . '-' . sprintf("%02d", $month) . '-' . sprintf("%02d", $day));
          }elsif( $file =~ m|_Pw_\d+A.rtf$| ){
            $self->{datastore}->StartBatch ($chd->{xmltvid} . '_' . $year . '-' . sprintf("%02d", $week));
          }else{
            f('parsinge day or week from filename did not work');
          }
        }

        $currdate = DateTime->new (
          year => $year,
          month => $month,
          day => $day,
          time_zone => 'Europe/Berlin');
        p( "new day: $daystring == " . $currdate->ymd( '-' ));
        $laststart = undef;
      } else { 
#        $text =~ s|^\s+||mg;
        d( 'TEXT: ' . $text );

        my $ce = {};
        $ce->{channel_id} = $chd->{id};

        # start_time and title
        my ($hour, $minute, $title) = ($text =~ m |^\s*(\d{2}):(\d{2})\s+(.*)$|m);
        if (!defined ($hour)) {
          # TODO may be regional window, then use the last start_time/duration
          # SWR has 3 regional variants that sometimes share the same time slots
          if( $channel_name ne 'SWR' ) {
            p ('program without start time');
            $text = '';
            next;
          } else {
            d ('program without start time, using last start without end');
            $ce->{start_time} = $laststart->ymd('-') . ' ' . $laststart->hms(':');
            # we did not find time:title, so guess the title is the first line
            ( $title ) = ($text =~ m |^\s*(.*?)\n|s);
          }
        } else {
          my $starttime = $currdate->clone();
          $starttime->set_hour ($hour);
          $starttime->set_minute ($minute);
          $starttime->set_time_zone ('UTC');
          if (!$laststart) {
            $laststart = $starttime->clone();
          }
          if (DateTime->compare ($laststart, $starttime) == 1) {
            # add 1 to the date without messing with the value of the houer in localtime
            $starttime->set_time_zone ('Europe/Berlin');
            $starttime->add (days => 1);
            $currdate->add (days => 1);
            $starttime->set_time_zone ('UTC');
          }
          $ce->{start_time} = $starttime->ymd('-') . ' ' . $starttime->hms(':');
          $laststart = $starttime;

          # span between start and stop
          my( $duration ) = ( $text =~ m|^\s*Sendedauer: (\d+)$|m );
          if( defined( $duration ) ) {
            # Sendedauer is not adjusted for DST switchover (it's 60 minutes off twice a year)
            # this ugly hack will eat 60 minutes when switchung to DST and spit out 60 minutes when switching back
            my $stoptime = $starttime->clone();
            $stoptime->set_time_zone("Europe/Berlin"); # convert UTC to local
            $stoptime->set_time_zone("floating");      # forget the time zone
            $stoptime->add( minutes => $duration );    # add the minutes
            $stoptime->set_time_zone("Europe/Berlin"); # force local time without adjustment
            $stoptime->set_time_zone("UTC");           # convert local to UTC
            $ce->{end_time} = $stoptime->ymd('-') . ' ' . $stoptime->hms(':');
          }

          # if we have text *before* the start time then that might be the program type inside the label!
          my ($label) = ($text =~ m|^\s*(.+)\n\s*\d{2}:\d{2}\s+.*\n|m);
          if ($label) {
            my ($program_type, $categ) = $ds->LookupCat ('Tele5Label', $label);
            AddCategory ($ce, $program_type, $categ);
            $text =~ s|^\s*.+\n(\s*\d{2}:\d{2}\s+.*\n)|$1|m;
          }

          # if we still have text *before* the start time then that might be the program type inside the label!
          ($label) = ($text =~ m|^\s*(.+)\n\s*\d{2}:\d{2}\s+.*\n|m);
          if ($label) {
            my ($program_type, $categ) = $ds->LookupCat ('Tele5Label', $label);
            AddCategory ($ce, $program_type, $categ);
            $text =~ s|^\s*.+\n(\s*\d{2}:\d{2}\s+.*\n)|$1|m;
          }
        }

        # skip if SWR an wrong region
        if( $channel_name eq 'SWR' ) {
          if( $text =~ m/^\s*(?:BW|RP|SR)$/m ) {
            my( $programregion )=( $text =~ m/^\s*(BW|RP|SR)$/m );
            $text =~ s/^\s*(?:BW|RP|SR)$//m;
            if( $region_name ne $programregion ) {
              d( 'skipping for region ' . $programregion . ' we want ' . $region_name );
              $desc = '';
              $text = '';
              next;
            }
          }
        }

        # season number
        if ($text =~ m|^\s*Staffel \d+$|m) {
          $text =~ s/\n\s*Staffel \d+(?:\n|$)/\n/;
        }

        # episode number
        my ($episodenum) = ($text =~ m/^\s*Folge\s+(\d+)(?:\/\d+$|\s+von\s+\d+$|$)/m);
        if ($episodenum) {
          $ce->{episode} = ' . ' . ($episodenum - 1) . ' . ';

          # episode title
          my ($episodetitle) = ($text =~ m/\n(.*)\n\s*Folge\s+\d+\n/);
          #error 'episode title: ' . $episodetitle;
          if( defined( $episodetitle ) ) {
            # strip trailing orignal episode title if present
            $episodetitle =~ s|\(.*?\)\s*$||;
            # strip leading and trailing space
            #$episodetitle = norm( $episodetitle );
            $episodetitle =~ s|^\s*(.+?)\s*$|$1|;
            $ce->{subtitle} = $episodetitle;
          }
        } else {
          # FIXME why do we not have a title???
          if (!$title) {
            w ("No title found in: $text");
          } else {
          # seems to be a movie, maybe it's a multi part movie
          if ($title =~ m|[,-] Teil \d+$|) {
            my ($partnum) = ($title =~ m|[,-] Teil (\d+)$|);
            $title =~ s|[,-] Teil \d+$||;
            $ce->{episode} = ' . . ' . ($partnum - 1);
          } elsif ($title =~ m|[,-] Teil \d+: .*$|) {
            my ($partnum, $episodetitle) = ($title =~ m|[,-] Teil (\d+): (.*)$|);
            $title =~ s|[,-] Teil \d+: .*$||;
            $ce->{episode} = ' . . ' . ($partnum - 1);
            $ce->{subtitle} = $episodetitle;
          }
          }
        }

        # strip first line / title
        $text =~ s|^[^\n]*\n|\n|s;

        # let's see if there is a subtitle if we don't have one already
        if( !$ce->{subtitle} ){
          # try second line of text for normal episode titles
          my( $subtitle )=( $text =~ m/^\n\s*([^\n]*)\n\s*(?:Folge\s+|Sendedauer:\s+)/s );
          if( $subtitle ){
            # filter out false positives
            if( !( $subtitle =~ m/^\s*(?:VPS:|Folge\s|\d{2}:\d{2}\s)/ ) ) {
              $ce->{subtitle} = $subtitle;
              $text =~ s/^\n\s*([^\n]*)\n\s*(Folge\s+|Sendedauer:\s+)/\n\n$2/s;
            }
          } else {
            # try third line next, if second line is "Thema"
            my( $subtitle )=( $text =~ m/^\n\s*Thema\n\s*([^\n]*)\n\s*(?:Folge\s+|Sendedauer:\s+)/s );
            if( $subtitle ){
              $ce->{subtitle} = $subtitle;
              $text =~ s/^\n\s*Thema\n\s*([^\n]*)\n\s*(Folge\s+|Sendedauer:\s+)/\n\n\n$2/s;
            }
          }
        }

        #
        # now pull all information from the text
        #

        # year of production and genre/program type
        my ($genre, $production_year) = ($text =~ m |\n\s*(.*)\n\s*Produziert:\s*.*\s(\d+)|);
        if ($production_year) {
          $ce->{production_date} = $production_year . '-01-01';
        }
        if ($genre) {
          if (!($genre =~ m|^Sendedauer:|)) {
            my ($program_type, $categ) = $ds->LookupCat ('Tele5', $genre);
            AddCategory ($ce, $program_type, $categ);
            $text =~ s|\n.*\n\s*Produziert:\s*.*\s\d+||;
          } else {
            $text =~ s|\n\s*Produziert:\s*.*\s\d+||;
          }
        }
        $text =~ s|\n\s*Sendedauer:\s+\d+||;

        # parse DD5.1 attribute for radio channels
        if ($desc =~ m|^\s*Dolby Digital 5.1\s*$|m) {
          $ce->{stereo} = 'dolby digital';
          $desc =~ s/(?:^|\n)\s*Dolby Digital 5.1\s*(?:\n|$)/\n/;
        }
        # synopsis
        if ($self->{KeepDesc}) {
          if ($desc) {
            $desc =~ s|\s+$||s;
            $ce->{description} = $desc . $copyrightstring;
          }
        }

        # case
        if ($text =~ m|\n\s*Besetzung:\n.*\n\n|s){
          (my $cast) = ($text =~ m|\n\s*Besetzung:\n(.*)\n\n|s);

          $cast = normLatin1 (normUtf8 ($cast));

          my @castArray = split ("\n", $cast);
          foreach my $castElement (@castArray) {
            my ($role, $actor) = split ("\t", $castElement);
            if (defined ($actor)) {
              $actor = norm ($actor);
              $role = norm ($role);
              if ($role) {
                $actor .= ' (' . $role . ')';
              }
              if (!defined ($ce->{actors})) {
                $ce->{actors} = $actor;
              } else {
                $ce->{actors} = join (', ', $ce->{actors}, $actor);
              }
            }
          }

          $text =~ s/\n\s*Besetzung:\n.*\n(?:\n|$)/\n/s;
        }

        # aspect
        if ($text =~ m|^\s*\[Bild: 4:3 \]$|m) {
          $ce->{aspect} = '4:3';
          $text =~ s/\n\s*\[Bild: 4:3 \](?:\n|$)/\n/;
        }
        if ($text =~ m|^\s*\[Bild: 16:9 \]$|m) {
          $ce->{aspect} = '16:9';
          $text =~ s/\n\s*\[Bild: 16:9 \](?:\n|$)/\n/;
        }
        if ($text =~ m|^\s*Bildformat 16:9$|m) {
          $ce->{aspect} = '16:9';
          $text =~ s/\n\s*Bildformat 16:9(?:\n|$)/\n/;
        }

        # quality
        if ($text =~ m|^\s*\[HDTV: HD \]$|m) {
          $ce->{quality} = 'HDTV';
          $text =~ s/\n\s*\[HDTV: HD \](?:\n|$)/\n/;
        }
        if ($text =~ m|^\s*HDTV$|m) {
          $ce->{quality} = 'HDTV';
          $text =~ s/\n\s*HDTV(?:\n|$)/\n/;
        }

        # stereo
        if ($text =~ m|^\s*\[Ton: Mono \]$|m) {
          $ce->{stereo} = 'mono';
          $text =~ s/\n\s*\[Ton: Mono \](?:\n|$)/\n/;
        }
        if ($text =~ m|^\s*Stereo$|m) {
          $ce->{stereo} = 'stereo';
          $text =~ s/\n\s*Stereo(?:\n|$)/\n/;
        }
        if ($text =~ m|^\s*Dolby Surround$|m) {
          $ce->{stereo} = 'surround';
          $text =~ s/\n\s*Dolby Surround(?:\n|$)/\n/;
        }
        if ($text =~ m|^\s*Zweikanal$|m) {
          $ce->{stereo} = 'bilingual';
          $text =~ s/\n\s*Zweikanal(?:\n|$)/\n/;
        }

        if ($text =~ m|^\s*Für Hörgeschädigte$|m) {
          #$ce->{subtitle} = 'yes';
          $text =~ s/\n\s*Für Hörgeschädigte(?:\n|$)/\n/;
        }

        # repeat
        if ($text =~ m|^\s*Wiederholung vom \d+\.\d+\.\d+$|m) {
          $text =~ s/\n\s*Wiederholung vom \d+\.\d+\.\d+(?:\n|$)/\n/;
        }

        # category override for kids (as we don't have a good category for anime anyway)
        if ($text =~ m|^\s*KINDERPROGRAMM$|m) {
          $ce->{category} = 'Kids';
        }

        # program type movie (hard to guess it from the genre)
        if ($text =~ m/^\s*(?:Spielfilm|Film)$/m) {
          $ce->{program_type} = 'movie';
        }

        #
        if ($text =~ m|^\s*Kirchenprogramm$|m) {
          $ce->{program_type} = 'tvshow';
        }

        # program_type and category for daily shows
        if ($title eq 'Homeshopping') {
          $ce->{program_type} = 'tvshow';
        } elsif ($title eq 'Dauerwerbesendung') {
          $ce->{program_type} = 'tvshow';
        } elsif ($title =~ m|^Making of eines aktuellen Kinofilms$|i) {
          $ce->{program_type} = 'tvshow';
          $ce->{category} = 'Movies';
        } elsif ($title =~ m|^Wir lieben Kino|) {
          $ce->{program_type} = 'tvshow';
          $ce->{category} = 'Movies';
        } elsif ($title =~ m|^Gottschalks Filmkolumne|) {
          $ce->{program_type} = 'tvshow';
          $ce->{category} = 'Movies';
        }

        # directors
        my ($directors) = ($text =~ m|^\s*Regie:\s*(.*)$|m);
        if ($directors) {
          $ce->{directors} = $directors;
          $text =~ s/\n\s*Regie:.*(?:\n|$)/\n/;
        }

        # presenters
        my ($presenters) = ($text =~ m|^\s*Moderation:\s*(.*)$|m);
        if ($presenters) {
          $ce->{presenters} = $presenters;
          $text =~ s/\n\s*Moderation:.*(?:\n|$)/\n/;
        }

        # writer
        my ($authors) = ($text =~ m|^\s*Autor(?:in):\s*(.*)$|m);
        if ($authors) {
          $ce->{writers} = $authors;
          $text =~ s/\n\s*Autor(?:in):.*(?:\n|$)/\n/;
        }

        # writer
        my ($writers) = ($text =~ m|^\s*Drehbuch:\s*(.*)$|m);
        if ($writers) {
          $ce->{writers} = $writers;
          $text =~ s/\n\s*Drehbuch:.*(?:\n|$)/\n/;
        }

        # episode number
        my $episode;
        ($episode, $episodenum) = ($text =~ m/^\s*Folge (\d+) von (\d+)$/m);
        if($episodenum) {
          $ce->{episode} = '. ' . ($episode - 1) . ' .';
          $text =~ s/\n\s*Folge \d+ von \d+(?:\n|$)/\n/;
        }

        ($episode) = ($text =~ m/^\s*Folge (\d+)$/m);
        if($episode) {
          $ce->{episode} = '. ' . ($episode - 1) . ' .';
          $text =~ s/\n\s*Folge \d+(?:\n|$)/\n/;
        }

        $ce->{title} = $title;
        $self->{datastore}->AddProgramme ($ce);
        # FIXME this should be handled in a generic way, but until then
        # do it on a one off base
        if( $self->{earliestdate} gt $ce->{start_time} ) {
          $self->{earliestdate} = $ce->{start_time};
        }
        # end_time would be better, but we don't have end_time
        if( $self->{latestdate} lt $ce->{start_time} ) {
          $self->{latestdate} = $ce->{start_time};
        }
        if( $text ){
          d( 'left over text: ' . $text );
        }
      }
      $desc = '';
      $enoughtext = 0;
      $text = '';
    }

    last if( $type eq 'eof' );
  }

  $self->{datastore}->EndBatch (1, undef);
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
