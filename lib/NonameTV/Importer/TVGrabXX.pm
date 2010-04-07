package NonameTV::Importer::TVGrabXX;

use strict;
use warnings;

=pod

Importer for data from other XMLTV sources using tv_grab_xx grabbers.
The tv_grab_xx should be run before this importer. The output file
of the grabber should be the file: $self->{FileStore} . "/tv_grab/" . $tvgrabber . ".xml";

Use grabber_data to specify grabber and the channel.

Example: to grab RAI1 using Italian grabber tv_grab_it, the grabber_data
will look like 'tv_grab_it;www.raiuno.rai.it'

Features:

=cut

use DateTime;
use XML::LibXML;
use Encode qw/encode decode/;

use NonameTV qw/norm AddCategory/;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  #defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $conf = ReadConfig();
  $self->{FileStore} = $conf->{FileStore};

  return $self;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $tvgrabber, $tvchannel ) = ( $data->{grabber_info} =~ /^(.*);(.*)$/ );
  $self->{tvgrabber} = $tvgrabber;
  $self->{tvchannel} = $tvchannel;

  my $xmlf = $self->{FileStore} . "/tv_grab/" . $tvgrabber . ".xml";

  open(XMLFILE, $xmlf);
  undef $/;
  my $content = <XMLFILE>;
  close(XMLFILE);

  return( $content, "" );
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
  
  # Find starting '<tv>' block
  my $tvbs = $doc->find( '//tv' );
  if( $tvbs->size() == 0 ){
    error( "$batch_id: No root <tv>' blocks found in xml file" );
    return 0;
  }
  progress("TVGrabXX: $chd->{xmltvid}: Found " . $tvbs->size() . " <tv> blocks in xml file");

  # browse through <tv> nodes
  foreach my $tvb ($tvbs->get_nodelist){

    # Filter all "programme" entries for this channel
    my $ns = $tvb->findnodes( './programme[@channel="' . $self->{tvchannel} . '"]' );
    if( $ns->size() == 0 ){
      error( "$batch_id: No shows found for $self->{tvchannel}" );
      return 0;
    }
    progress("TVGrabXX: $chd->{xmltvid}: Found " . $ns->size() . " shows for $self->{tvchannel}");

    # browse through shows
    foreach my $sc ($ns->get_nodelist)
    {
      #
      # start time
      #
      my $start = $self->create_dt( $sc->findvalue( './@start' ) );
      if( not defined $start ){
        error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
        next;
      }

      #
      # end time
      #
      my $end = $self->create_dt( $sc->findvalue( './@stop' ) );
      if( not defined $end ){
        error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
        next;
      }

      #
      # title
      #
      my $title = $sc->getElementsByTagName('title');
      next if( ! $title );

      #
      # subtitle
      #
      my $subtitle = $sc->getElementsByTagName('sub-title');
    
      #
      # description
      #
      my $description  = $sc->getElementsByTagName('desc');
    
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

      progress("TVGrabXX: $chd->{xmltvid}: $start - $title");

      my $ce = {
        channel_id   => $chd->{id},
        title        => norm($title),
        start_time   => $start->ymd("-") . " " . $start->hms(":"),
        end_time     => $end->ymd("-") . " " . $end->hms(":"),
      };

      $ce->{subtitle} = $subtitle if $subtitle;
      $ce->{description} = $description if $description;

      $ce->{directors} = $directors if $directors;
      $ce->{actors} = $actors if $actors;
      $ce->{writers} = $writers if $writers;
      $ce->{adapters} = $adapters if $adapters;
      $ce->{producers} = $producers if $producers;
      $ce->{presenters} = $presenters if $presenters;
      $ce->{commentators} = $commentators if $commentators;
      $ce->{guests} = $guests if $guests;

      $ce->{url} = $url if $url;

      if( defined( $episode ) and ($episode =~ /\S/) )
      {
        $ce->{episode} = norm($episode);
        $ce->{program_type} = 'series';
      }

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( $chd->{xmltvid}, $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      $ds->AddProgramme( $ce );

    }

  }

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $year, $month, $day, $hour, $minute, $second, $offset ) = ( $str =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s(.*)$/ );

  return undef if( ! $year );
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => $offset,
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;
