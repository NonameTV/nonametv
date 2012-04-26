package NonameTV::Importer::CanalPlus;

use strict;
use warnings;

=pod

Importer for data from Canal+. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

Note that grabber_info can be either '6' or '20&g=2'. It seems that
g=2 is used to select a different set of channels. When g=2 is used,
data for all channels in that group is returned. The unwanted data is
filtered out in FilterContent.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use Compress::Zlib;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w f/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    $self->{datastore}->{augment} = 1;

    # Canal Plus' webserver returns the following date in some headers:
    # Fri, 31-Dec-9999 23:59:59 GMT
    # This makes Time::Local::timegm and timelocal print an error-message
    # when they are called from HTTP::Date::str2time.
    # Therefore, I have included HTTP::Date and modified it slightly.

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  # Find the first day in the given week.
  # Copied from
  # http://www.nntp.perl.org/group/perl.datetime/5417?show_headers=1 
  my $ds = DateTime->new( year=>$year, day => 4 );
  $ds->add( days => $week * 7 - $ds->day_of_week - 6 );
  
  my $de=$ds->clone->add( days => 6 );
  my $url = $self->{UrlRoot} .
    'ds=' . $ds->ymd("-") . '&' . 
    'de=' . $de->ymd('-') . '&' . 
    'c=' . $chd->{grabber_info};

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $uncompressed = Compress::Zlib::memGunzip($$cref);
  my $doc;

  if( defined $uncompressed ) {
      $doc = ParseXml( \$uncompressed );
  }
  else {
      $doc = ParseXml( $cref );
  }

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//Channel" );

  if( $ns->size() == 0 ) {
    return (undef, "No channels found" );
  }
  
  foreach my $ch ($ns->get_nodelist) {
    my $currid = $ch->findvalue( '@Id' );
    if( $currid != $chid ) {
      $ch->unbindNode();
    }
  }

  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }
  
  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//Schedule" );

  if( $ns->size() == 0 )
  {
    f "No data found";
    return 0;
  }
  
  foreach my $sc ($ns->get_nodelist)
  {
    # Sanity check. 
    # What does it mean if there are several programs?
    if( $sc->findvalue( 'count(.//Program)' ) != 1 ) {
      f "Wrong number of Programs for Schedule " .
          $sc->findvalue( '@Id' );
      return 0;
    } 

    my $title = $sc->findvalue( './Program/@Title' );

    my $start = $self->create_dt( $sc->findvalue( './@CalendarDate' ) );
    if( not defined $start )
    {
      w "Invalid starttime '" 
          . $sc->findvalue( './@CalendarDate' ) . "'. Skipping.";
      next;
    }

    my $next_start = $self->create_dt( $sc->findvalue( './@NextStart' ) );

    # NextStart is sometimes off by one day.
    if( defined( $next_start ) and $next_start < $start )
    {
      $next_start = $next_start->add( days => 1 );
    }

    my $length  = $sc->findvalue( './Program/@Length ' );
    w "$length is not numeric."
      if( $length !~ /^\d*$/ );

    my $end;

    if( ($length eq "") or ($length == 0) )
    {
      if( not defined $next_start ) {
	w "Neither next_start nor length for " . $start->ymd() . " " . 
	    $start->hms() . " " . $title;
	next;
      }
      $end = $next_start;
    }
    else
    {
      $end = $start->clone()->add( minutes => $length );

      # Sometimes the claimed length of the movie makes the movie end
      # a few minutes after the next movie is supposed to start.
      # Assume that next_start is correct.
      if( (defined $next_start ) and ($end > $next_start) 
          and ($next_start > $start) )
      {
        $end = $next_start;
      }
    }

    my $series_title = $sc->findvalue( './Program/@SeriesTitle' );
    my $org_title = $sc->findvalue( './Program/@OriginalTitle' );
    
    my $org_desc = $sc->findvalue( './Program/@LongSynopsis' );
    my $epi_desc = $sc->findvalue( './Program/@EpisodeLongSynopsis' );
    my $desc  = $epi_desc || $org_desc;
    
    my $genre = norm($sc->findvalue( './Program/@Genre' ));
#    my $country = $sc->findvalue( './Program/@Country' );

    # LastChance is 0 or 1.
#    my $lastchance = $sc->findvalue( '/Program/@LastChance' );

    # PremiereDate can be compared with CalendarDate
    # to see if this is a premiere.
#    my $premieredate = $sc->findvalue( './Program/@PremiereDate' );

    # program_type can be partially derived from this:
    my $sport = $sc->findvalue( './Program/@Sport' );
    my $series = $sc->findvalue( './Program/@Series' );

    if( $series and ($series_title eq "") ) {
#      w "Series without SeriesTitle: $title";
    }
 
    my $production_year = $sc->findvalue( './Program/@ProductionYear' );

    my $sixteen_nine = $sc->findvalue( './Program/@SixteenNine' );
    my $soundfive_one = $sc->findvalue( './Program/@SoundFiveOne' );
	#    my $letterbox = $sc->findvalue( './Program/@Letterbox' );
    
    # Episode info
    my $epino = $sc->findvalue( './Program/@EpisodeNo' );
    my $seano = $sc->findvalue( './Program/@SeasonNo' );
    my $of_episode = $sc->findvalue( './Program/@NumberOfEpisodes' );
    
    # The director and actor info is in a somewhat strange format. 
    # Actor is a child of Director and the data seems to contain
    # all combinations of Actor and Director.

    my %directors;
    my @directors;
    my $ns2 = $sc->find( './/Director' );
  
    foreach my $dir ($ns2->get_nodelist)
    {
      my $names = $dir->findvalue('./@Name');

      # Sometimes they list several directors with newlines between
      # the names.
      foreach my $name (split "\n", $names)
      {
        $name = norm( $name );
        if( not defined( $directors{ $name } ) )
        {
          $directors{$name} = 1;
          push @directors, $name;
        }
      }
    }
    
    my %actors;
    my @actors;
    my $ns3 = $sc->find( './/Actor' );
  
    foreach my $act ($ns3->get_nodelist)
    {
      my $name = norm( $act->findvalue('./@Name') );
      if( not defined( $actors{ $name } ) )
      {
        $actors{$name} = 1;
        push @actors, $name;
      }
    }

    my $ce = {
      channel_id  => $chd->{id},
      description => norm($desc),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
      aspect      => $sixteen_nine ? "16:9" : "4:3", 
    };

    if( $series_title =~ /\S/ )
    {
      $ce->{title} = norm($series_title);
      $title = norm( $title );

      if( $title =~ /^Del\s+(\d+),\s+(.*)/ )
      {
        $ce->{subtitle} = $2;
      }
      elsif( $title ne $ce->{title} ) 
      {
        $ce->{subtitle } = $title;
      }
    }
    else
    {
	# Remove everything inside ()
	$org_title =~ s/\(.*\)//g;
      $ce->{title} = norm($org_title) || norm($title);
    }

    if( $sport )
    {
      $ce->{category} = 'Sports';
    }

    $ce->{program_type} = "series"
      if $series;

    if( (not $series) and (not $sport) ) {
      $ce->{program_type} = 'movie';
    }

    my($program_type, $category ) = $ds->LookupCat( "CanalPlus", 
                                                    $genre );
    AddCategory( $ce, $program_type, $category );

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ", ", @directors;
    }

    if( scalar( @actors ) > 0 )
    {
      $ce->{actors} = join ", ", @actors;
    }
  
  	if( $soundfive_one eq 1 )
  	{
  		$ce->{stereo} = 'surround';
  	}
  
    if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
          if($of_episode) {
          	$ce->{episode} = sprintf( "%d . %d/%d .", $seano-1, $epino-1, $of_episode );
          }
     	}else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
          if( defined( $production_year ) and 
            ($production_year =~ /\d{4}/) )
        	{
          		$ce->{episode } = $production_year-1 . " " . $ce->{episode};
        	}
        }
    }
    
    $self->extract_extra_info( $ce );

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $date, $time ) = split( 'T', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  if( $second > 59 ) {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = @_;
  
}
    
1;
