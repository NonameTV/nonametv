package NonameTV::Importer::RAI;

use strict;
use warnings;
use utf8;
use Unicode::String;

=pod

Import data for RAI in xml-format.

=cut


use DateTime;
use XML::LibXML;
use Roman;

use NonameTV qw/ParseXml AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f p/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  if( defined( $self->{UrlRoot} ) ){
    w( 'UrlRoot is deprecated' );
  } else {
    $self->{UrlRoot} = 'http://www.ufficiostampa.rai.it/work/rss/';
  }

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Rome" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref eq '' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub FilterContent {
  my( $self, $cref, $chd ) = @_;

  return( $cref, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  #$$cref = Unicode::String::latin1 ($$cref)->utf8 ();

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//programma" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }

  foreach my $b ($ns->get_nodelist) {
  	# Start and so on
    my $start = ParseDateTime( $b->findvalue( "giorno" ) );

    if( $start->ymd("-") ne $currdate ){
		p("Date is ".$start->ymd("-"));

		$dsh->StartDate( $start->ymd("-") , "00:00" );
		$currdate = $start->ymd("-");
	}

    my $title = $b->findvalue( "titolo" );
    my $time = $b->findvalue( "ora" );
    my $text = $b->findvalue( "trama" );

    # Descr. and genre
    my $desc = $b->findvalue( "sottotitolo" );

	# Put everything in a array
    my $ce = {
      channel_id => $chd->{id},
      start_time => $time.":00",
      title => norm($title),
      description => norm($desc),
    };

    if( defined( $text ) and ($text =~ /(\d\d\d\d)/) )
    {
    	$ce->{production_date} = "$1-01-01";
    }

    # Title
    if( $title =~ /^FILM/  ) {
    	$ce->{title} =~ s/FILM//g; # REMOVE ET
    	$ce->{program_type} = 'movie';
    }elsif( $title =~ /^TELEFILM/  ) {
        $ce->{title} =~ s/TELEFILM//g; # REMOVE ET
        $ce->{program_type} = 'series';
    }elsif( $title =~ /^TV MOVIE/  ) {
        $ce->{title} =~ s/TV MOVIE//g; # REMOVE ET
        $ce->{program_type} = 'series';
    }elsif( $title =~ /^MOVIE/  ) {
        $ce->{title} =~ s/MOVIE//g; # REMOVE ET
    }

    # Desc
    if( $desc =~ /^FILM/  ) {
        $ce->{program_type} = 'movie';
    }

    if( my( $years, $country ) = ($text =~ /(\d\d\d\d)\s+(.*)$/) )
    {
    	$text =~ s/$years//g; # REMOVE ET
    	$text =~ s/$country//g; # REMOVE ET
    	$text = norm($text);
    }

    if( my( $directors ) = ($text =~ /^di\s*(.*)\s*con/) )
    {
    	$ce->{directors} = norm(parse_person_list( $directors )) if norm($directors) ne "AA VV"; # What is AA VV?
    }

    if( my( $actors ) = ($text =~ /con\s*(.*)/) )
    {
    	$ce->{actors} = norm(parse_person_list( $actors ));

    	#print("$ce->{actors}\n");
    }

    $ce->{title} =~ s/\^ Visione RAI//g;
    $ce->{title} = norm($ce->{title});

    # season, episode, episode title
    my($ep, $season, $episode, $dummy);

    # Episode and season (roman)
    ( $dummy, $ep ) = ($ce->{title} =~ /Ep(\.|)\s*(\d+)$/i );
    if(defined($ep) && !defined($ce->{episode})) {
        $ce->{episode} = sprintf( " . %d .", $ep-1 );
        $ce->{title} =~ s/- Ep(.*)$//gi;
      	$ce->{title} =~ s/Ep(.*)$//gi;
      	$ce->{title} =~ s/ serie$//gi;
      	$ce->{title} = norm($ce->{title});

      	# Season
      	my ( $original_title, $romanseason ) = ( $ce->{title} =~ /^(.*)\s+(.*)$/ );

        # Roman season found
        if(defined($romanseason) and isroman($romanseason)) {
            my $romanseason_arabic = arabic($romanseason);

            # Episode
          	my( $romanepisode ) = ($ce->{episode} =~ /.\s+(\d*)\s+./ );

          	# Put it into episode field
          	if(defined($romanseason_arabic) and defined($romanepisode)) {
          			$ce->{episode} = sprintf( "%d . %d .", $romanseason_arabic-1, $romanepisode );

          			# Set original title
          			$ce->{title} = norm($original_title);
          	}
        }
    }

    # pt. ep
    ( $ep ) = ($title =~ /pt\.\s*(\d+)/ );
    if(defined($ep) && !defined($ce->{episode})) {
        $ce->{episode} = sprintf( " . %d .", $ep-1 );
        $ce->{title} =~ s/pt. (.*)$//g;
        $ce->{title} =~ s/pt.(.*)$//g;
    }

    # pt. ep
    ( $ep ) = ($title =~ /pt\s*(\d+)/ );
    if(defined($ep) && !defined($ce->{episode})) {
        $ce->{episode} = sprintf( " . %d .", $ep-1 );
        $ce->{title} =~ s/pt (.*)$//g;
        $ce->{title} =~ s/pt(.*)$//g;
    }

    # Genre, in a way
    my ($genre) = ($ce->{description} =~ /^(.*)\s+-/ );
    if(defined($genre)) {
        $ce->{description} =~ s/^(.*) -//gi;
    }

    $ce->{title} = norm($ce->{title});

	p($time." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  #$dsh->EndBatch( 1 );

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+)$/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
      );

  return $dt;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;


  my( $date ) = ( $objectname =~ /(\d+-\d+-\d+)$/ );
  my( $year, $month, $day ) =
        ($date =~ /^(\d+)-(\d+)-(\d+)$/ );

  $month =~ s/^0*//;


  my $url = sprintf( "%s%s%s%s%spal.xml",
                     $self->{UrlRoot}, $chd->{grabber_info},
                     $day, $month, $year);


  return( $url, undef );
}

# Split a string into individual sentences.
sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End: