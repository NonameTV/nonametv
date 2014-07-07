package NonameTV::Importer::HBO;

use strict;
use warnings;

=pod

Import data from Xml-files downloaded from www.hbo.hr

The possible grabber_info values HBO,HBOCOMEDY,CMAX,CMAX2

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Roman;

use NonameTV::DataStore::Helper;
use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $xmltvid, $date ) = ( $batch_id =~ /^(.*)_(\d+-\d+-\d+)$/);

  my $url = $self->{UrlRoot} . "?date=" . $date . "&channel=" . $data->{grabber_info};

  progress("HBO: $xmltvid: Fetching data from $url");

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  progress( "HBO: $channel_xmltvid: Processing XML" );

  # clean some characters from xml that can not be parsed
  my $xmldata = $$cref;
  $xmldata =~ s/\&/(and)/;
  $xmldata =~ s/<br >//i;
  $xmldata =~ s/<\/b>//i;

  my( $date ) = ( $batch_id =~ /^.*_(\d+-\d+-\d+)$/);
  $dsh->StartDate( $date , "06:00" );

  # parse XML
  my $doc;
  my $xml = XML::LibXML->new;

  eval { $doc = $xml->parse_string($xmldata); };
  if( $@ ne "" ) {
    error( "HBO: $batch_id: Failed to parse $@" );
    return 0;
  }

  # find the master node - tv
  my $ntvs = $doc->findnodes( "//schedule" );
  if( $ntvs->size() == 0 ) {
    error( "HBO: $channel_xmltvid: $xmldata: No schedule nodes found" ) ;
    return;
  }
  progress( "HBO: $channel_xmltvid: found " . $ntvs->size() . " schedule nodes" );

  # browse through ntvs
  foreach my $ntv ($ntvs->get_nodelist) {

    # find all programs
    my $prgs = $ntv->findnodes( ".//item" );
    if( $prgs->size() == 0 ) {
      error( "HBO: $channel_xmltvid: No programs found" ) ;
      next;
    }
    progress( "HBO: $channel_xmltvid: found " . $prgs->size() . " programs" );

    # browse through programs
    foreach my $prg ($prgs->get_nodelist) {

      my $scheduleid = $prg->findvalue( './@schedule_id' );
      my $movieid = $prg->findvalue( './@movie_id' );

      my $title = $prg->findvalue( 'title' );
      next if not $title;

      my $starttime = $prg->findvalue( 'start_time' );
      next if not $starttime;

      my $starttimefull = $prg->findvalue( 'start_time_full' );
      my $duration =      $prg->findvalue( 'duration' );
      my $lead =          $prg->findvalue( 'lead' );
      my $thnimage =      $prg->findvalue( 'thn_image' );
      my $channelid =     $prg->findvalue( 'channel_id' );
      my $category =      $prg->findvalue( 'content_type' );
      my $genre =         $prg->findvalue( 'primary_genre' );

      my $ce = {
        channel_id => $channel_id,
        title => norm($title),
        start_time => $starttime,
      };

      $ce->{schedule_id} = $scheduleid if ( $scheduleid =~ /\S/ );
      $ce->{description} = $lead if $lead;
      $ce->{url_image_thumbnail} = $thnimage if ( $thnimage =~ /\S/ );

      my( $pty, $cat );
      # Primary program_type
      if(defined($category) and $category and $category ne "") {
        ( $pty, $cat ) = $ds->LookupCat( 'HBO_primary', $category );
      	AddCategory( $ce, $pty, $cat );
      }

      # Genre
      if(defined($genre) and $genre and $genre ne "") {
        ( $pty, $cat ) = $ds->LookupCat( 'HBO_genre', $genre );
        AddCategory( $ce, $pty, $cat );
      }

      # Episode
      my($ep, $seasonroman, $seas, $episode);
      ( $seasonroman, $ep ) = ($ce->{title} =~ /(\S*)\.,\s+(\d+).\s+del$/ );

      if( (defined $ep) and (defined $seasonroman) and isroman($seasonroman) )
      {
        my $romanseas = arabic($seasonroman);

        # add it
        if(defined($romanseas)) {
            $ce->{title} =~ s/(\S*)\.,\s+(\d+).\s+del$//;
            $ce->{title} = norm($ce->{title});
            $episode = sprintf( "%d . %d .", $romanseas-1, $ep-1 );
        }
      }

      ( $ep ) = ($ce->{title} =~ /,\s+(\d+).\s+del$/ );
      $ce->{title} =~ s/,\s+(\d+).\s+del$//;
      $ce->{title} = norm($ce->{title});

      if( (defined $ep) )
      {
        # add it
        $episode = sprintf( " . %d .", $ep-1 );
      }

      # HBO HR
      ( $seasonroman, $ep ) = ($ce->{title} =~ /(\S*),\s+ep\.\s+(\d+)$/ );

      if( (defined $ep) and (defined $seasonroman) and isroman($seasonroman) )
      {
        my $romanseas = arabic($seasonroman);

        # add it
        if(defined($romanseas)) {
            $ce->{title} =~ s/(\S*),\s+ep\.\s+(\d+)$//;
            $ce->{title} = norm($ce->{title});
            $episode = sprintf( "%d . %d .", $romanseas-1, $ep-1 );
        }
      }

      ( $ep ) = ($ce->{title} =~ /,\s+ep\.\s+(\d+)$/ );
      $ce->{title} =~ s/,\s+ep\.\s+(\d+)$//;
      $ce->{title} = norm($ce->{title});

      if( (defined $ep) )
      {
        # add it
        $episode = sprintf( " . %d .", $ep-1 );
      }

      $ce->{title} =~ s/\.$//; # Remove ending .

      $ce->{episode} = $episode if $episode;

      $dsh->AddProgramme( $ce );

      progress( "HBO: $channel_xmltvid: $starttime - $ce->{title}" );
    }
  }

  return 1;
}

sub create_dt {
  my ( $text ) = @_;

  if( $text !~ /^\d{14}$/ ){
    return undef;
  }

  my( $year, $month, $day, $hour, $minute, $second ) = ( $text =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/ );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          nanosecond => 0,
                          time_zone => 'Europe/Zagreb',
  );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
