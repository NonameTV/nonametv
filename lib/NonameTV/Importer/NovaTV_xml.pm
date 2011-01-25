package NonameTV::Importer::NovaTV_xml;

use strict;
use warnings;

=pod

Import data from Xml-files downloaded from PORT.hu

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

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

  return $self;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $xmltvid, $year, $month, $day ) = ($batch_id =~ /^(.*)_(\d+)-(\d+)-(\d+)$/);

  my $url;
  $url = $self->{UrlRoot} . "/" . $data->{grabber_info} . "/?" . $year . $month . $day;

  progress("NovaTV_xml: $xmltvid: Fetching data from $url");

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  progress( "NovaTV_xml: $channel_xmltvid: Processing XML" );

  # clean some characters from xml that can not be parsed
  my $xmldata = $$cref;
  $xmldata =~ s/\&/(and)/;
  $xmldata =~ s/<br >//i;
  $xmldata =~ s/<\/b>//i;

  # parse XML
  my $doc;
  my $xml = XML::LibXML->new;

  eval { $doc = $xml->parse_string($xmldata); };
  if( $@ ne "" ) {
    error( "NovaTV_xml: $batch_id: Failed to parse $@" );
    return 0;
  }

  # find the master node - tv
  my $ntvs = $doc->findnodes( "//tv" );
  if( $ntvs->size() == 0 ) {
    error( "NovaTV_xml: $channel_xmltvid: $xmldata: No tv nodes found" ) ;
    return;
  }
  progress( "NovaTV_xml: $channel_xmltvid: found " . $ntvs->size() . " tv nodes" );

  # browse through ntvs
  foreach my $ntv ($ntvs->get_nodelist) {

    my $tvsource = $ntv->findvalue( './@source' );
    if( $tvsource !~ /^Nova TV$/ and $tvsource !~ /^Mini TV$/ and $tvsource !~ /^Doma TV$/ ){
      error( "NovaTV_xml: $channel_xmltvid: Invalid tv source: $tvsource" );
      return;
    }

    # find all programs
    my $prgs = $ntv->findnodes( ".//program" );
    if( $prgs->size() == 0 ) {
      error( "NovaTV_xml: $channel_xmltvid: No programs found" ) ;
      next;
    }
    progress( "NovaTV_xml: $channel_xmltvid: found " . $prgs->size() . " programs" );

    # browse through programs
    foreach my $prg ($prgs->get_nodelist) {

      my $start = $prg->findvalue( './@start' );
      if( not defined $start )
      {
        error( "NovaTV_xml: $channel_xmltvid: Invalid starttime '$start'. Skipping." );
        next;
      }
      my $starttime = create_dt( $start );
      if( not defined $starttime ){
        error( "NovaTV_xml: $channel_xmltvid: Can't parse starttime '$start'. Skipping." );
        next;
      }

      my $stop = $prg->findvalue( './@stop' );
      if( not defined $stop )
      {
        error( "NovaTV_xml: $channel_xmltvid: Invalid endtime '$stop'. Skipping." );
        next;
      }
      my $endtime = create_dt( $stop );
      if( not defined $endtime ){
        error( "NovaTV_xml: $channel_xmltvid: Can't parse endtime '$stop'. Skipping." );
        next;
      }

      my $title = $prg->findvalue( 'title' );
      my $type = $prg->findvalue( 'type' );
      my $genre = $prg->findvalue( 'genre' );
      my $desc = $prg->findvalue( 'desc' );

      next if not $title;

      progress( "NovaTV_xml: $channel_xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time => $endtime->ymd("-") . " " . $endtime->hms(":"),
      };

      $ce->{description} = $desc if $desc;

      if( $type ){
        my($program_type, $category ) = $ds->LookupCat( 'NovaTV_type', $type );
        AddCategory( $ce, $program_type, $category );
      }

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'NovaTV_genre', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $ds->AddProgramme( $ce );
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
