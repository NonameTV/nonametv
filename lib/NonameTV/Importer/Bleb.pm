package NonameTV::Importer::Bleb;

use strict;
use warnings;

=pod

Importer for data from bleb.org.
The data are in XML format.

    Bleb =>
    {
      Type => 'Bleb',
      UrlRoot => 'http://www.bleb.org/tv/data/listings/',
      MaxDays => 1,
    },

Features:

=cut

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

my $strdmy;

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

  # Find all "channel"-entries.
  my $ch = $doc->find( "//channel" );

  foreach my $c ($ch->get_nodelist)
  {
    #
    # date
    #
    $strdmy = $c->findvalue( './@date' ) ;

  }


  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $starttime = $sc->getElementsByTagName('start');
    if( not defined $starttime )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }
    my $start = $self->create_dt( $starttime );
    next if( ! $start );

    #
    # end time
    #
    my $endtime = $sc->getElementsByTagName('end');
    if( not defined $endtime )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }
    my $end = $self->create_dt( $endtime );
    next if( ! $end );

#print "$starttime -> $start\n";
#print "$endtime -> $end\n";
    
    #
    # check once more if start/end are extracted and defined ok
    #
    if( not defined $start or not defined $end )
    {
      error( "$batch_id: Invalid start/end times '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # title, subtitle
    #
    my $title = $sc->getElementsByTagName('title');
    next if( ! $title );

    my $subtitle = $sc->getElementsByTagName('subtitle');
#print "$title\n";
#print "$subtitle\n";
    
    #
    # description
    #
    my $desc  = $sc->getElementsByTagName('desc');
#print "$desc\n";
    
    #
    # url
    #
    my $url = $sc->getElementsByTagName( 'infourl' );
#print "$url\n";

    #
    # programme type
    #
    my $type = $sc->getElementsByTagName( 'type' );
#print "$type\n";

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'year' );
#print "$production_year\n";

    progress("Bleb: $chd->{xmltvid}: $start - $title");

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
    };

      $ce->{subtitle}  => norm($subtitle) if $subtitle;
      $ce->{description}  => norm($desc) if $desc;
      #url          => norm($url),

    my($program_type, $category ) = $ds->LookupCat( "Bleb", $type );
    AddCategory( $ce, $program_type, $category );
    
#    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
#    {
#      $ce->{production_date} = "$1-01-01";
#    }

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $strhour ) = @_;
  
#print "$strdmy\n";
#print "$strhour\n";

  if( length( $strhour ) == 0 )
  {
    return undef;
  }

  my $day = substr( $strdmy , 0 , 2 );
  my $month = substr( $strdmy , 3 , 2 );
  my $year = substr( $strdmy , 6 , 4 );

  my $hour = substr( $strhour , 0 , 2 );
  my $minute = substr( $strhour , 2 , 2 );
  my $second = 0;
  my $offset = 0;

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
                          time_zone => 'Europe/London',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $bprefixyear , $bmonth , $bday ) = split( "-" , $batch_id );

  my $today = DateTime->today->day();

  my $dayoff = $bday - $today;

  #progress("ID $batch_id BDAY $bday TODAY $today DAYOFF $dayoff");

  # Bleb provides listings for today + 6 days
  # in different directory for every day
  # starting with 0 for today

  my $url = $self->{UrlRoot} . "/" . $dayoff . "/" . $data->{grabber_info};
  progress("Fetching data from: $url");

  my ( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
