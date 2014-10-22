package NonameTV::Importer::MTVde;

use strict;
use warnings;

=pod

Importer for data from MTV Networks Germany GmbH.
One file per channel and week downloaded from their site.

AGB:                  http://presse.viva.tv/node/53
channel ids:          http://origin-ops.mtvnn.com/presse/presse.html
format description:   http://struppi.tv/
VG Media EPG License: http://www.vgmedia.de/de/lizenzen/epg.html

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML::XPathContext;

use NonameTV qw/AddCategory norm ParseXml/;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/d progress w error f/;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  if (!defined $self->{HaveVGMediaLicense}) {
    warn( 'Extended event information (texts, pictures, audio and video sequences) is subject to a license sold by VG Media. Set HaveVGMediaLicense to yes or no.' );
    $self->{HaveVGMediaLicense} = 'no';
  }
  if ($self->{HaveVGMediaLicense} eq 'yes') {
    $self->{KeepDesc} = 1;
  }

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $channel = $chd->{grabber_info};
  if( $channel =~ m|^\d+$| ){
    # weeks are numbered 1 to 52/53
    my $url = sprintf( "http://api.mtvnn.com/v2/airings.struppi?channel_id=%d&program_week_is=%d", $channel, $week );

    d( "MTVde: fetching data from $url" );

    return( [$url], undef );
  } else {
    return( undef, 'grabber_info must contain the channel id, see http://origin-ops.mtvnn.com/presse/presse.html');
  }
}

sub ContentExtension {
  return 'xml';
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # mixed in windows line breaks
  $$cref =~ s|||g;

  $$cref =~ s| xmlns:ns='http://struppi.tv/xsd/'||;
  $$cref =~ s| xmlns:xsd='http://www.w3.org/2001/XMLSchema'||;

  $$cref =~ s| generierungsdatum='[^']+'| generierungsdatum=''|;

  return( $cref, undef);
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent( $$$ ) {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $doc = ParseXml ($cref);
  
  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  my $xpc = XML::LibXML::XPathContext->new( );
  $xpc->registerNs( s => 'http://struppi.tv/xsd/' );

  my $programs = $xpc->findnodes( '//s:sendung', $doc );
  if( $programs->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  sub by_start {
    return $xpc->findvalue('s:termin/@start', $a) cmp $xpc->findvalue('s:termin/@start', $b);
  }

  foreach my $program (sort by_start $programs->get_nodelist) {
    $xpc->setContextNode( $program );
    my $ce = ();
    $ce->{channel_id} = $chd->{id};
    $ce->{start_time} = $self->parseTimestamp( $xpc->findvalue( 's:termin/@start' ) );
    $ce->{end_time} = $self->parseTimestamp( $xpc->findvalue( 's:termin/@ende' ) );

    my $title = $xpc->findvalue( 's:titel/s:alias[@titelart="titel"]/@aliastitel' );
    if( !$title ){
      $title = $xpc->findvalue( 's:titel/s:alias[@titelart="originaltitel"]/@aliastitel' );
    }
    if( !$title ){
      $title = $xpc->findvalue( 's:titel/@termintitel' );
    }
    if( $title eq 'Comedy Central Programming') {
      # remove pseudo program when channel nick is off air
      next;
    }
    if( $title ){
      $ce->{title} = $title;
    }

    my $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="untertitel"]/@aliastitel' );
    if( !$subtitle ){
      $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="originaluntertitel"]/@aliastitel' );
    }
    if( $subtitle ){
      my $staffel;
      my $folge;
      if( ( $staffel, $folge ) = ($subtitle =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
        $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
      } elsif( ( $folge ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
        $ce->{episode} = '. ' . ($folge - 1) . ' .';
      } else {
        # unify style of two or more episodes in one programme
        $subtitle =~ s|\s*/\s*| / |g;
        # unify style of story arc 
        $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
        $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
        $ce->{subtitle} = norm( $subtitle );
      }
    }

    my $production_year = $xpc->findvalue( 's:produktion/s:produktionszeitraum/s:jahr/@von' );
    if( $production_year =~ m|^\d{4}$| ){
      $ce->{production_date} = $production_year . '-01-01';
    }

    my $genre = $xpc->findvalue( 's:infos/s:klassifizierung/s:genre' );
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "MTVde", $genre );
      AddCategory( $ce, $program_type, $category );
    }
    $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@formatgruppe' );
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "MTVde", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    my $url = $xpc->findvalue( 's:infos/s:url/@link' );
    if( $url ){
      $ce->{url} = $url
    }

    $self->{datastore}->AddProgramme( $ce );

#    d( $xpc->getContextNode()->toString() . Dumper ( $ce ) );

  }

  return 1;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute, $second, $offset) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})([+-]\d{2}:\d{2}|)$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    if( $offset ){
      $offset =~ s|:||;
    } else {
      $offset = 'Europe/Berlin';
    }
    my $dt = DateTime->new ( 
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute, 
      second    => $second,
      time_zone => $offset
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt->ymd( '-' ) . ' ' . $dt->hms( ':' ) );
  } else {
    return undef;
  }
}

1;
