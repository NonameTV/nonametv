package NonameTV::Importer::Tele5;

use strict;
use warnings;
use Encode qw/from_to/;

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
use RTF::Tokenizer;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d p w error f/;
use NonameTV qw/AddCategory MonthNumber norm/;

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

  my $regexp = $self->{channel_name} . '_Pw_[[:digit:]]+A\.rtf';
  $regexp =~ s|\s|_|g;

return if ( $file !~ /$regexp/i );

  $self->ImportRTF ($file, $chd);

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
  from_to ($copyrightstring, "windows-1252", "utf8");
  

  while( my ( $type, $arg, $param ) = $tokenizer->get_token( ) ){

#    last if( $type eq 'eof' );

    if( ( $type eq 'control' ) and ( $arg eq 'par' ) ){
      $text .= "\n";
    } elsif( ( $type eq 'control' ) and ( ( $arg eq '*' ) or ( $arg eq 'fonttbl' ) or ( $arg eq 'footer' ) or ( $arg eq 'header' ) ) ){
      d( 'footerstart' );
      $text .= "\n";
      if( $infooter == 0 ) {
        $infooter = $grouplevel;
      }
    } elsif( ( $type eq 'group' ) ){
      if( $arg == 0 ) {
        if( $grouplevel == $infooter ) {
          d( 'footerend' );
          $infooter = 0;
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
        $text .= ' ' . $arg;
        d( 'text:' . $arg );
      }
    } else {
      d( 'unknown type: ' . $type . ':' . $arg );
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

        if (!$gotbatch) {
          $gotbatch = 1;
          $self->{datastore}->StartBatch ($chd->{xmltvid} . '_' . $year . '-' . sprintf("%02d", $week));
        }

        $month = MonthNumber ($month, 'de');
        $currdate = DateTime->new (
          year => $year,
          month => $month,
          day => $day,
          time_zone => 'Europe/Berlin');
        p( "new day: $daystring == " . $currdate->ymd( '-' ));
        $laststart = undef;
      } else { 
        d "TEXT: $text";
        from_to ($text, "windows-1252", "utf8");

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
        }

        # skip if SWR an wrong region
        if( $channel_name eq 'SWR' ) {
          if( $text =~ m/^\s*(?:BW|RP|SR)$/m ) {
            my( $programregion )=( $text =~ m/^\s*(BW|RP|SR)$/m );
            if( $region_name ne $programregion ) {
              d( 'skipping for region ' . $programregion . ' we want ' . $region_name );
              $text = '';
              next;
            }
          }
        }

        # episode number
        my ($episodenum) = ($text =~ m |^\s*Folge\s+(\d+)$|m);
        if ($episodenum) {
          $ce->{episode} = ' . ' . ($episodenum - 1) . ' . ';

          # episode title
          my ($episodetitle) = ($text =~ m |\n(.*)\n\s*Folge\s+\d+\n|);
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

        # year of production and genre/program type
        my ($genre, $production_year) = ($text =~ m |\n\s*(.*)\n\s*Produziert:\s+.*\s(\d+)|);
        if ($production_year) {
          $ce->{production_date} = $production_year . '-00-00';
        }
        if ($genre) {
          if (!($genre =~ m|^Sendedauer:|)) {
            my ($program_type, $categ) = $ds->LookupCat ('Tele5', $genre);
            AddCategory ($ce, $program_type, $categ);
          }
        }

        # synopsis
        if ($self->{KeepDesc}) {
          my ($desc) = ($text =~ m|^.*\n\n(.*?)$|s);
          if ($desc) {
            $ce->{description} = $desc . $copyrightstring;
          }
        }

        # aspect
        if ($text =~ m|^\s*Bildformat 16:9$|m) {
          $ce->{aspect} = '16:9';
        }

        # stereo
        if ($text =~ m|^\s*Stereo$|m) {
          $ce->{stereo} = 'stereo';
        } elsif ($text =~ m|^\s*Dolby Surround$|m) {
          $ce->{stereo} = 'surround';
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
        } elsif ($title eq 'Making of eines aktuellen Kinofilms') {
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
        }

        $ce->{title} = $title;
        $self->{datastore}->AddProgramme ($ce);
      }
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
