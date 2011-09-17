package NonameTV::Importer::NonstopWeb;

use strict;
use warnings;

=pod

Importer for data from Nonstop. 
One file per channel and month downloaded from their site.
The downloaded file is in xml-format.

=cut

use utf8;
use DateTime;
use XML::LibXML;
use HTTP::Date;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseMonthly;

use base 'NonameTV::Importer::BaseMonthly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinMonths} = 0;
    $self->{MaxMonths} = 1;

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $url = $self->{UrlRoot} .
    $chd->{grabber_info} . '/' . $year . '/' . $month;

  return( $url, undef );
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref =~ '<!--' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//rs:data" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
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
  my $ns = $doc->find( "//z:row" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }
  
  foreach my $sc ($ns->get_nodelist)
  {
    my $title_original = $sc->findvalue( './@SeriesOriginalTitle' );
	my $title_programme = $sc->findvalue( './@ProgrammeSeriesTitle' );
	my $title = norm($title_programme) || norm($title_original);

    my $start = $self->create_dt( $sc->findvalue( './@SlotLocalStartTime' ) );
    if( not defined $start )
    {
      w "Invalid starttime '" 
          . $sc->findvalue( './@SlotLocalStartTime' ) . "'. Skipping.";
      next;
    }
    
    my $desc = undef;
    my $desc_episode = $sc->findvalue( './@ProgrammeEpisodeLongSynopsis' );
	my $desc_series  = $sc->findvalue( './@ProgrammeSeriesLongSynopsis' );
	$desc = $desc_episode || $desc_series;
	
	my $genre = $sc->findvalue( './@SeriesGenreDescription' );
	my $production_year = $sc->findvalue( './@ProgrammeSeriesYear' );
	my $subtitle =  $sc->findvalue( './@ProgrammeEpisodeTitle' );
	my $aspect =  $sc->findvalue( './@ProgrammeVersionTechnicalTypesAspect_Ratio' );

	progress("Nonstop: $chd->{xmltvid}: $start - $title");

    my $ce = {
      title 	  => norm($title),
      channel_id  => $chd->{id},
      description => norm($desc),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
    };
    
    $ce->{subtitle} = $subtitle if $subtitle;
    
    my ( $season, $episode ) = ($desc =~ /\(S�song\s*(\d+)\s*avsnitt\s*(\d+)\)/ );
    
    if((defined $season) and ($episode > 0) and ($season > 0) )
    {
      $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    }
    elsif((defined $episode) and ($episode > 0) )
    {
      $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }
    
    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }
    
    
    
    if( (defined $aspect) and ($aspect eq "16*9 (2)")) {
    	$ce->{aspect} = "16:9";
    } else {
    	$ce->{aspect} = "4:3";
    }
    
    if( $genre ){
			my($program_type, $category ) = $ds->LookupCat( 'Nonstop', $genre );
			AddCategory( $ce, $program_type, $category );
	}

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
    
1;
