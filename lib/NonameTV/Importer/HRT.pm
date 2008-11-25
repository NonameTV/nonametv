package NonameTV::Importer::HRT;

use strict;
use warnings;

=pod

Importer for data from HRT. 
One file per channel and 4-day period downloaded from their site.
The downloaded file is in xml-format.

Features:

=cut

use DateTime;
use XML::LibXML;
use Encode qw/encode decode/;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = $self->create_dt( $sc->findvalue( './@stop' ) );
    if( not defined $end )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }
    
    #
    # title, subtitle
    #
    my $title;
#    eval{ $title = decode( "utf-8", $sc->getElementsByTagName('title') ); };
#    if( $@ ne "" ){
#      error( "Failed to decode title $@" );
#    }
    $title = $sc->getElementsByTagName('title');
    my $org_title = $sc->getElementsByTagName('sub-title');
    my $subtitle = $sc->getElementsByTagName('sub-title');
    
    #
    # description
    #
    my $desc  = $sc->getElementsByTagName('desc');
    
    #
    # genre
    #
    my $genre = norm($sc->getElementsByTagName( 'category' ));

    #
    # url
    #
    my $url = $sc->getElementsByTagName( 'url' );

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'date' );

    #
    # episode number
    #
    my $episode = undef;
    if( $sc->getElementsByTagName( 'episode-num' ) ){
      my $ep_nr = int( $sc->getElementsByTagName( 'episode-num' ) );
      my $ep_se = 0;
      if( ($ep_nr > 0) and ($ep_se > 0) )
      {
        $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
      }
      elsif( $ep_nr > 0 )
      {
        $episode = sprintf( ". %d .", $ep_nr-1 );
      }
    }

    # The director and actor info are children of 'credits'
    my $directors = $sc->getElementsByTagName( 'director' );
    my $actors = $sc->getElementsByTagName( 'actor' );
    my $writers = $sc->getElementsByTagName( 'writer' );
    my $adapters = $sc->getElementsByTagName( 'adapter' );
    my $producers = $sc->getElementsByTagName( 'producer' );
    my $presenters = $sc->getElementsByTagName( 'presenter' );
    my $commentators = $sc->getElementsByTagName( 'commentator' );
    my $guests = $sc->getElementsByTagName( 'guest' );

    progress("HRT: $chd->{xmltvid}: $start - $title");

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title) || norm($org_title),
      subtitle     => norm($subtitle),
      description  => norm($desc),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
      #aspect       => $sixteen_nine ? "16:9" : "4:3", 
      directors    => norm($directors),
      actors       => norm($actors),
      writers      => norm($writers),
      adapters     => norm($adapters),
      producers    => norm($producers),
      presenters   => norm($presenters),
      commentators => norm($commentators),
      guests       => norm($guests),
      url          => norm($url),
    };

    if( defined( $episode ) and ($episode =~ /\S/) )
    {
      $ce->{episode} = norm($episode);
      $ce->{program_type} = 'series';
    }

    my($program_type, $category ) = $ds->LookupCat( "HRT", $genre );

    AddCategory( $ce, $program_type, $category );

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    $dsh->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  my $second = substr( $str , 12 , 2 );
  my $offset = substr( $str , 15 , 5 );

  if( not defined $year )
  {
    return undef;
  }
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Zagreb',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # Find the first day in the given week.
  # Copied from
  # http://www.nntp.perl.org/group/perl.datetime/5417?show_headers=1 
  #my $dt = DateTime->new( year=>$year, day => 4 );
  #$dt->add( days => $week * 7 - $dt->day_of_week - 6 );

  my $url = $self->{UrlRoot} . "\?$data->{grabber_info}";

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
