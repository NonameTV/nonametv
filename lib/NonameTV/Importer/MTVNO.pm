package NonameTV::Importer::MTVNO;

use strict;
use warnings;

=pod

Importer for data from MTV Networks (Viacom Media Networks, VIMN).
One file per channel and week downloaded from their site.

Format is "XMLTV" - Their kind of XMLTV, this is much like the MTVde.pm importer
but specified for Norway/Scandinavia.

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML;

use NonameTV qw/AddCategory norm normUtf8 ParseXml/;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/d progress w error f/;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  # Use augmenter, and get teh fabulous shit
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $channel = $chd->{grabber_info};
  my $url = sprintf( "http://api.mtvnn.com/v2/airings.xmltv?channel_id=%d&program_week_is=%d&language_code=no&country_code=NO", $channel, $week );

  d( "MTVNN: fetching data from $url" );

  return ($url, undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # mixed in windows line breaks
  $$cref =~ s|
||g;

  return( $cref, undef);
}

sub ImportContent( $$$ ) {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  # Parse
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return 0;
  }

  # Find all "Base"-entries.
  my $ns = $doc->find( "//programme" );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  foreach my $pgm ($ns->get_nodelist)
  {
    # Times
  	my $start = $self->ParseTime($pgm->findvalue( './@start' ));
  	#my $stop = $self->ParseTime($pgm->findvalue( './@stop' ));
  	# Stoptime makes it look ugly (they end it at 26:59 etc, (when ads begin))

  	# Title stuff
  	my $title    = norm($pgm->findvalue('./title'));
  	my $subtitle = norm($pgm->findvalue('./sub-title'));

  	# Episode
  	my $episodenum = norm($pgm->findvalue('./episode-num'));
  	my $seasonnum = norm($pgm->findvalue('./season-num'));

  	# Description
  	my $format_desc = normUtf8($pgm->findvalue('./format_desc'));
  	my $format_desc_short = normUtf8($pgm->findvalue('./format_desc_short'));
  	my $desc = normUtf8($pgm->findvalue('./desc'));
  	my $desc_short = normUtf8($pgm->findvalue('./desc_short'));
  	my $description = $desc_short || $desc || $format_desc_short || $format_desc;


  	# Other
  	my $genre = norm($pgm->findvalue('./format_genre'));
  	my $production_year = norm($pgm->findvalue('./format_production_year'));
  	my $live = norm($pgm->findvalue( './live' ));
  	my $repeat = norm($pgm->findvalue( './repeat_level' ));

  	my $ce = {
      title => norm($title),
      channel_id => $chd->{id},
      description => $description,
      start_time => $start->ymd("-") . " " . $start->hms(":"),
      #end_time => $stop->ymd("-") . " " . $stop->hms(":"),
    };

    # Special things from MTVde.pm
    if( $subtitle ){
      my $season;
      my $episode;
      my $dummy;
      if( ($dummy, $season, $episode ) = ($subtitle =~ m|^S(.*)song (\d+) Avsnitt (\d+)$| ) ){
        $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
      #} elsif( ($dummy, $season, $episode ) = ($subtitle =~ m|^Season (\d+) Episode (\d+)$| ) ){
      #  $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
      } elsif( ( $episode ) = ($subtitle =~ m|^Avsnitt (\d+)$| ) ){
        $ce->{episode} = '. ' . ($episode - 1) . ' .';
      } else {
        # unify style of two or more episodes in one programme
        $subtitle =~ s|\s*/\s*| / |g;
        # unify style of story arc
        $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
        $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
        $subtitle =~ s|[ ,-]+pt. (\d)+$| \($1\)|;
        $ce->{subtitle} = norm( $subtitle );
      }
    }
    if($seasonnum and $seasonnum ne "") {
    	$ce->{episode} = sprintf( "%d . %d .", $seasonnum-1, $episodenum-1 );
    }
    if( $production_year =~ m|^\d{4}$| ){
      $ce->{production_date} = $production_year . '-01-01';
    }
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "MTVNN", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    # Other
	if( $live eq "true" )
	{
		$ce->{live} = "1";
	}
	else
	{
		$ce->{live} = "0";
	}
	if( $repeat eq "1" )
	{
		$ce->{rerun} = "1";
	}
	else
	{
		$ce->{rerun} = "0";
	}

    progress("MTVNN: $chd->{xmltvid}: ".$start->ymd("-") . " " . $start->hms(":")." - $title");

  	$self->{datastore}->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub ParseTime( $ ){
  my $self = shift;
  my ($timestamp) = @_;

  #FROM MTVDE.pm

  if( $timestamp ){
    # 20120607090000
    my ($year, $month, $day, $hour, $minute, $second) = ($timestamp =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      second    => $second,
      time_zone => "Europe/Stockholm",
    );
    $dt->set_time_zone( 'UTC' );

    #print Dumper($dt);

    return $dt;
  } else {
    return undef;
  }
}

1;