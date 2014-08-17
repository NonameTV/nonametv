package NonameTV::Importer::CMore;

use strict;
use warnings;

=pod

Importer for data from C More. 
One file per channel and day downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use Compress::Zlib;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w f p/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
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

  my( $date ) = ($objectname =~ /_(.*)/);

#  my $url = 'http://press.cmore.se/export/xml/' . $date . '/' . $date . '/?channelId=' . $chd->{grabber_info};
  my $url = $self->{UrlRoot} . 'export/xml/' . $date . '/' . $date . '/?channelId=' . $chd->{grabber_info};

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
  
#  foreach my $ch ($ns->get_nodelist) {
#   my $currid = $ch->findvalue( '@Id' );
#    if( $currid != $chid ) {
#      $ch->unbindNode();
#    }
#  }

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

    my $length  = $sc->findvalue( './Program/@Duration ' );
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
    my $org_title = $sc->findvalue( './Program/@Title' );
    
    my $org_desc = $sc->findvalue( './Program/Synopsis/Short' );
    my $epi_desc = $sc->findvalue( './Program/Synopsis/Long' );
    my $desc  = $epi_desc || $org_desc;
    
    my $genre = norm($sc->findvalue( './Program/@GenreKey' ));
#    my $country = $sc->findvalue( './Program/@Country' );

    # LastChance is 0 or 1.
#    my $lastchance = $sc->findvalue( '/Program/@LastChance' );

    # PremiereDate can be compared with CalendarDate
    # to see if this is a premiere.
#    my $premieredate = $sc->findvalue( './Program/@PremiereDate' );

    # program_type can be partially derived from this:
    my $sport = $sc->findvalue( './Program/@Sport' );
    my $series = $sc->findvalue( './Program/@Series' );
    my $cate = $sc->findvalue( './Program/@Category' );

    if( $series and ($series_title eq "") ) {
#      w "Series without SeriesTitle: $title";
    }
 
    my $production_year = $sc->findvalue( './Program/@ProductionYear' );

    
    # Episode info
    my $epino = $sc->findvalue( './Program/@EpisodeNumber' );
    my $seano = $sc->findvalue( './Program/@SeasonNumber' );
    my $of_episode = $sc->findvalue( './Program/@NumberOfEpisodes' );

    # Actors and Directors
    my $actors = norm( $sc->findvalue( './Program/@Actors' ) );
    my $direcs = norm( $sc->findvalue( './Program/@Directors' ) );

    my $ce = {
      channel_id  => $chd->{id},
      description => norm($desc),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
    };

    #      end_time    => $end->ymd("-") . " " . $end->hms(":"),

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

    my($program_type, $category ) = $ds->LookupCat( "CMore_genre", $genre );
    AddCategory( $ce, $program_type, $category );

    my($program_type2, $category2 ) = $ds->LookupCat( "CMore_category", $cate );
    AddCategory( $ce, $program_type2, $category2 );

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
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
        	    my( $year ) = ($ce->{production_date} =~ /(\d{4})-/ );
          		$ce->{episode } = $year-1 . " " . $ce->{episode};
        	}
        }

        $ce->{program_type} = 'series';
    }

    # Actors and directors
    if(defined($actors)) {
    	$ce->{actors} = $actors;
    }

    if(defined($direcs)) {
    	$ce->{directors} = $direcs;
    }
    
    $self->extract_extra_info( $ce );

    # Org title
    my $title_org = $sc->findvalue( './Program/@OriginalTitle' );
    if($ce->{program_type} eq 'series') {
        $ce->{subtitle} = norm($title_org);
    } elsif($ce->{program_type} eq 'movie') {
        $ce->{original_title} = norm($title_org) if $ce->{title} ne $title_org and norm($title_org) ne "";
    }

    p( "CMore: $chd->{xmltvid}: $start - $title" );

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
