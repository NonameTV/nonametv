package NonameTV::Importer::RBBDE;

use strict;
use warnings;

=pod

Download weekly xml file from rbb-online.de. It contains three channels,
the common channel and the two branched out regional variants. To get a
complete guide the common channel is combined with one variant each.

Based on Arte_http

Entry point for human consumption
http://presseservice.rbb-online.de/programmwochen/rbb_fernsehen/rbb_fernsehen_programmwoche.phtml

=cut

use DateTime;
use Data::Dumper qw/Dumper/;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseWeekly;
use NonameTV::Log qw/d p w f/;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    # notice that the weeks run saturday-friday, and you might get 2 days less then expected!
    if ($self->{MaxWeeks} > 6) {
        $self->{MaxWeeks} = 6;
    }

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore} );

    $self->{datastore}->{SILENCE_END_START_OVERLAP}=1;
#    $self->{datastore}->{augment} = 1;

    return $self;
}


sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $url = sprintf( "http://presseservice.rbb-online.de/programmwochen/rbb_fernsehen/%04d/rbb-%02d.xml", $year, $week);

  return( $url, undef );
}


sub ContentExtension {
  return 'xml';
}


sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # a reexport without changes still doesn't need to be handled
  $cref =~ s| exportzeit=\"[^\"]+\"| exportzeit=\"\"|;

  my $doc = ParseXml( $cref );

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

  my $programs = $xpc->findnodes( '//SERVICE[@servicename="' . $chd->{grabber_info} . '"]/SENDEABLAUF/SENDUNGSBLOCK/SENDEPLATZ', $doc );
  if( $programs->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  my $latest = DateTime->new( year => 1900 );

  foreach my $program ($programs->get_nodelist) {
    $xpc->setContextNode( $program );
    my $ce = ();
    $ce->{channel_id} = $chd->{id};
#    my $vpsstart = $xpc->findvalue( 'ZEITINFORMATIONEN/VPS_LABEL/VPS_DATUM' ) . 'T' . $xpc->findvalue( 'ZEITINFORMATIONEN/VPS_LABEL/VPS_ZEIT' ) . ':00';
#    if( $vpsstart eq 'T:00' ){
#      $vpsstart = $self->parseTimestamp( $xpc->findvalue( 'ZEITINFORMATIONEN/SENDESTART' ) );
#    }
#    $ce->{start_time} = $self->parseTimestamp( $vpsstart );
    $ce->{start_time} = $self->parseTimestamp( $xpc->findvalue( 'ZEITINFORMATIONEN/SENDESTART' ), \$latest );
    $ce->{end_time} = $self->parseTimestamp( $xpc->findvalue( 'ZEITINFORMATIONEN/SENDESTOP' ), \$latest );

    my $title = $xpc->findvalue( 'SENDUNGSINFORMATIONEN/TITELINFORMATIONEN/SENDUNGSTITELTEXT' );
    $ce->{title} = norm( $title );

    my $absepisodenum = $xpc->findvalue( 'SENDUNGSINFORMATIONEN/ERWEITERTE_TITELINFORMATIONEN/FOLGENINFORMATIONEN/FOLGENNUMMER' );
    if( defined( $absepisodenum ) ){
      if( $absepisodenum ne '' ){
        $ce->{episode} = '. ' . ($absepisodenum - 1) . ' .';
      }
    }

#    my $genre = $xpc->findvalue( 'infos/klassifizierung/genre' );
#    if( $genre ){
#      my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Arte_genre", $genre );
#      AddCategory( $ce, $program_type, $category );
#    }

    my $synopsis = $xpc->findvalue( 'SENDUNGSINFORMATIONEN/INHALTSINFORMATIONEN/KURZINHALTSTEXT' );
    if( $synopsis ){
      $ce->{description} = norm( $synopsis );
    }

#    ParseCredits( $ce, 'actors',     $xpc, 'mitwirkende/mitwirkender[@funktion="Darsteller"]/mitwirkendentyp/person/name/@name' );
#    ParseCredits( $ce, 'directors',  $xpc, 'mitwirkende/mitwirkender[@funktion="Regie"]/mitwirkendentyp/person/name/@name' );
#    ParseCredits( $ce, 'producers',  $xpc, 'mitwirkende/mitwirkender[@funktion="Produzent"]/mitwirkendentyp/person/name/@name' );
#    ParseCredits( $ce, 'writers',    $xpc, 'mitwirkende/mitwirkender[@funktion="Autor"]/mitwirkendentyp/person/name/@name' );
#    ParseCredits( $ce, 'writers',    $xpc, 'mitwirkende/mitwirkender[@funktion="Drehbuch"]/mitwirkendentyp/person/name/@name' );
#    ParseCredits( $ce, 'presenters', $xpc, 'mitwirkende/mitwirkender[@funktion="Moderation"]/mitwirkendentyp/person/name/@name' );
#    ParseCredits( $ce, 'guests',     $xpc, 'mitwirkende/mitwirkender[@funktion="Gast"]/mitwirkendentyp/person/name/@name' );

    $self->{datastore}->AddProgramme( $ce );

#    d( $xpc->getContextNode()->toString() . Dumper ( $ce ) );

  }

  return 1;
}


sub parseTimestamp( $$ ){
  my $self = shift;
  my ($timestamp, $latest) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00 in local time
    my ($year, $month, $day, $hour, $minute, $second) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }
    my $dt = DateTime->new ( 
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute, 
      second    => $second,
      time_zone => 'Europe/Berlin',
    );
    $dt->set_time_zone( 'UTC' );

    if( defined( $$latest ) ){
      if( DateTime->compare( $$latest, $dt ) > 0 ){
        if( $$latest->delta_ms( $dt )->delta_minutes() >= 6*60 ){
          # time went backwards more then 6 hours, add a day
          # this is because the period from 6am to 6am is sent with the same date
          $dt->add( days => 1 );
        }
      }
    }
    $$latest = $dt->clone();

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
