package NonameTV::Importer::Arte_http;

use strict;
use warnings;

=pod

Download weekly word file in zip archive from arte pro

=cut

use DateTime;

use IO::Uncompress::Unzip qw/unzip/;
use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Importer::Arte_util qw/ImportFull/;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/p w/;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    # notice that the weeks run saturday-friday, and you might get 2 days less then expected!
    if ($self->{MaxWeeks} > 6) {
        $self->{MaxWeeks} = 6;
    }

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore} );

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub InitiateDownload {
  my $self = shift;

  my $mech = $self->{cc}->UserAgent();

  $mech->get('http://presse.arte.tv/ArtePro2/home.xhtml');

  if (!$mech->success()) {
    return $mech->status_line;
  }

  $mech->form_with_fields( ( 'form1:password' ) );
  $mech->field( 'form1:user', $self->{Username}, 1 );
  $mech->field( 'form1:password', $self->{Password}, 1 );
  $mech->click_button( name => 'form1:einloggen' );

  if ($mech->success()) {
    return undef;
  } else {
    return $mech->status_line;
  }
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $url = sprintf( "http://presse.arte.tv/ArtePro2/download?filename=/data/artepro/tempDir/apios/progr/struppi/arte_%02d.xml", $week);

  return( $url, undef );
}

sub ContentExtension {
  return 'zip';
}

sub FilterContent {
  my $self = shift;
  my( $zref, $chd ) = @_;

  if (!($$zref =~ m/^PK/)) {
    return (undef, "returned data is not a zip file");
  }

  my $cref;
  unzip $zref => \$cref;

  # mixed in windows line breaks
#  $$cref =~ s|
#||g;

  $cref =~ s| xmlns:ns='http://struppi.tv/xsd/'||;
  $cref =~ s| xmlns:xsd='http://www.w3.org/2001/XMLSchema'||;

  $cref =~ s| generierungsdatum=\"[^\"]+\"| generierungsdatum=\"\"|;

  $cref =~ s|\s*drgib\d+\s*</text>|</text>|sg;

  my $doc = ParseXml( \$cref );

  if( not defined $doc ) {
    return (undef, "Parse2Xml failed" );
  }

  my $str = $doc->toString(1);

  return (\$str, undef);
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

  my $programs = $xpc->findnodes( '//s:sendung[not(s:termin/s:terminart/s:klammer)]', $doc );
  if( $programs->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  foreach my $program ($programs->get_nodelist) {
    $xpc->setContextNode( $program );
    my $ce = ();
    $ce->{channel_id} = $chd->{id};
    $ce->{start_time} = $self->parseTimestamp( $xpc->findvalue( 's:termin/@start' ) );
#   endtime overlaps and misses alot
#    $ce->{end_time} = $self->parseTimestamp( $xpc->findvalue( 's:termin/@ende' ) );

    my $title = $xpc->findvalue( 's:titel/@termintitel' );
    if( !$title ){
      $title = $xpc->findvalue( 's:titel/s:alias[@titelart="titel"]/@aliastitel' );
    }
    if( !$title ){
      $title = $xpc->findvalue( 's:titel/s:alias[@titelart="originaltitel"]/@aliastitel' );
    }
    my ($episodenum, $episodetotal) = (0, 0);
    if( $title ){
      if( $title =~ m/\s+\(\d+(?:\/\d+|)\)$/ ) {
        ($episodenum, $episodetotal) = ( $title =~ m/\s+\((\d+)(?:\/(\d+)|)\)$/ );
        $title =~ s/\s+\(\d+(?:\/\d+|)\)$//;
      }
      $ce->{title} = norm( $title );
    }

    if( !$title ){
      w( 'program without title at ' . $ce->{start_time} );
      next;
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
        if( ( $folge ) = ($subtitle =~ m|^\((\d+)\):\s+.*$| ) ){
          if( defined( $episodetotal )&&( $episodetotal > 0 ) ) {
            $ce->{episode} = '. ' . ($folge - 1) . '/' . $episodetotal . ' .';
          } else {
            $ce->{episode} = '. ' . ($folge - 1) . ' .';
          }
          $subtitle =~ s|^\(\d+\):\s+||;
        }

        # unify style of two or more episodes in one programme
        $subtitle =~ s|\s*/\s*| / |g;
        # unify style of story arc 
        $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
        $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
        $ce->{subtitle} = norm( $subtitle );
      }
    }

    my $original_title = norm( $xpc->findvalue( 's:titel/s:alias[@titelart="originaltitel"]/@aliastitel' ) );
    if( $original_title ){
      # remove braces
      $original_title =~ s|^\((.*)\)$|$1|;
      $ce->{original_title} = norm( $original_title );
    }

    my $production_year = $xpc->findvalue( 's:infos/s:produktion/s:produktionszeitraum/s:jahr/@von' );
    if( $production_year =~ m|^\d{4}$| ){
      $ce->{production_date} = $production_year . '-01-01';
    }

    my @countries;
    my $ns4 = $xpc->find( 's:infos/s:produktion/s:produktionsland/@laendername' );
    foreach my $con ($ns4->get_nodelist)
	{
	    my ( $c ) = $self->{datastore}->LookupCountry( "Arte", $con->to_literal );
	  	push @countries, $c if defined $c;
	}

    if( scalar( @countries ) > 0 )
    {
        $ce->{country} = join "/", @countries;
    }

    my $genre = $xpc->findvalue( 's:infos/s:klassifizierung/s:genre' );
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Arte_genre", $genre );
      AddCategory( $ce, $program_type, $category );
    }
    $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@kategorie' );
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Arte_genre", $genre );
      AddCategory( $ce, $program_type, $category );
    }
    $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@formatgruppe' );
    if( $genre ){
      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Arte_genre", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    # parse sendung_id to guess if its a series of some kind unless we know it from the genre
    # JT-010252 is a "klammer"
    # CY-###### is a "klammer"
    # PS-011133- is a programme at the beginning with a start_time in the evening, followed by the correct first programme
    # FO-011124- is a programme with times in the evening but put between programs in the morning (huh?)
    # 000000-000-A is a program (seen A and B and C)
    #        ^^^- is 0 for movie/tvshow and >= 1 for series (episode id starting from 1)
    my $sendung_id = $xpc->findvalue( './@sendung_id' );
    if( $sendung_id !~ m|^\d{6}-\d{3}-\w$| ){
      # just skip these out of place programmes for now
      next;
    }
    if( $sendung_id && !$ce->{program_type}){
      my( $folge )=( $sendung_id =~ m|^\d{6}-(\d{3})-[A-Z]$| );
      if( defined( $folge ) ) {
        if( $folge > 0 ) {
          $ce->{program_type} = 'series';
        }
      }
    }

    my $url = $xpc->findvalue( 's:infos/s:url/@link' );
    if( $url ){
      # a link to the root of the arte+7 website gains us nothing progam specific, so skip it
      if( $url ne 'videos.arte.tv'){
         $ce->{url} = $url;
      }
    }

    my $synopsis = $xpc->findvalue( 's:text[@textart="Beschreibung"]' );
    if( $synopsis ){
      $ce->{description} = $synopsis;
    }

    if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Mono"]/@art' ) ) {
      $ce->{stereo} = 'mono';
    }
    if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Stereo"]/@art' ) ) {
      $ce->{stereo} = 'stereo';
    }
    if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Mehrkanal"]/@art' ) ) {
      $ce->{stereo} = 'surround';
    }
    if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="OmU"]/@art' ) ) {
      # we don't handle it, yet
    }
    if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Audiodescription"]/@art' ) ) {
      # we don't handle it, yet
    }

    my $aspect = $xpc->findvalue( 's:infos/s:sonderzeichen/s:bildverhaeltnis/@verhaeltnis' );
    if( $aspect ){
      if ($aspect eq '16:9') {
        $ce->{aspect} = '16:9';
      } elsif ($aspect eq 'Stereo') {
        $ce->{aspect} = 'stereo';
      } else {
        w( 'unhandled type of aspect: ' . $aspect );
      }
    }

    my $quality = $xpc->findvalue( 's:infos/s:sonderzeichen/s:hd[@vorhanden="true"]/@vorhanden' );
    if( $quality ){
      if ($quality eq 'true') {
        $ce->{quality} = 'HDTV';
      } else {
        w( 'unhandled type of quality: ' . $quality );
      }
    }

    ParseCredits( $ce, 'actors',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Darsteller"]/s:mitwirkendentyp/s:person/s:name/@name' );
    ParseCredits( $ce, 'directors',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Regie"]/s:mitwirkendentyp/s:person/s:name/@name' );
    ParseCredits( $ce, 'producers',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Produzent"]/s:mitwirkendentyp/s:person/s:name/@name' );
    ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Autor"]/s:mitwirkendentyp/s:person/s:name/@name' );
    ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Drehbuch"]/s:mitwirkendentyp/s:person/s:name/@name' );
    ParseCredits( $ce, 'presenters', $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Moderation"]/s:mitwirkendentyp/s:person/s:name/@name' );
    ParseCredits( $ce, 'guests',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Gast"]/s:mitwirkendentyp/s:person/s:name/@name' );

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

# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->string_value();
    if( $person ne '' ) {
      push( @people, split( '&', $person ) );
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}


sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ';', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ';', @people );
    }
  }
}

1;


1;
