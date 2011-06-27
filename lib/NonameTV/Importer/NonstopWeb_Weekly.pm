package NonameTV::Importer::NonstopWeb_Weekly;

use strict;
use warnings;

=pod

Importer for data from Nonstop. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

#use Compress::Zlib;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinWeeks} = 0 unless defined $self->{MinWeeks};
    $self->{MaxWeeks} = 4 unless defined $self->{MaxWeeks};

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  # Find the first day in the given week.
  # Copied from
  # http://www.nntp.perl.org/group/perl.datetime/5417?show_headers=1 
  my $url = $self->{UrlRoot} .
    $chd->{grabber_info} . '/' . $year . '/' . $week;

  return( $url, undef );
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
    # Sanity check. 
    # What does it mean if there are several programs?

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
    
   # my $desc_episode = undef;
   # my $desc_series = undef;
    my $desc = undef;

    my $desc_episode = $sc->findvalue( './@ProgrammeEpisodeLongSynopsis' );
	my $desc_series  = $sc->findvalue( './@ProgrammeSeriesLongSynopsis' );
	
	$desc = norm($desc_episode) || norm($desc_series);
	
	my $genre = $sc->findvalue( './@SeriesGenreDescription' );
	
	my $production_year = $sc->findvalue( './@ProgrammeSeriesYear' );
	
	my $subtitle =  $sc->findvalue( './@ProgrammeEpisodeTitle' );

	progress("Nonstopweb_v2: $chd->{xmltvid}: $start - $title");

    my $ce = {
      title 	  => norm($title),
      channel_id  => $chd->{id},
      description => $desc,
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
    };
    
    $ce->{subtitle} = $subtitle if $subtitle;
    
    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
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

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = @_;
  
}
    
1;
