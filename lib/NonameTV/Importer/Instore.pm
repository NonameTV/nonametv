package NonameTV::Importer::Instore;

use strict;
use warnings;

=pod

Importer for data from Instore Brodcast.
One file per channel and day downloaded from their site.
The downloaded file is in xml-format.

Channels: OUTTV

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{UrlRoot} = "http://login.instorebroadcast.com/previews/outtv/Webadvance/" if !defined( $self->{UrlRoot} );

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $dt = DateTime->now(time_zone => "local")->subtract( days => 1);
  my $date = $dt->ymd;

  my( $year, $month, $day ) = ( $date =~ /(\d+)-(\d+)-(\d+)$/ );

  my $url = $self->{UrlRoot} . $day . '.' . $month . '.' .
    $chd->{grabber_info} . '.xml';

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
  my $ns = $doc->find( "//broadcastingprogramm" );

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
  my $ns = $doc->find( "//broadcast" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }

  foreach my $sc ($ns->get_nodelist)
  {
    my $start = $self->create_dt( $sc->findvalue( './date' ) . " " . $sc->findvalue( './time' ) );
    if( not defined $start )
    {
      w "Invalid starttime '"
          . $sc->findvalue( './date' ) . " " . $sc->findvalue( './time' ) . "'. Skipping.";
      next;
    }

    print($start."\n");

  }

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;


  my( $date, $time ) = split( ' ', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '\/', $date );

  # Remove the dot and everything after it.
  $time =~ s/\..*$//;

  my( $hour, $minute, $second ) = split( ":", $time );


  my $dt = DateTime->new( year => $year,
                          month => $month,
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          time_zone => "Europe/Stockholm",
                          );

  $dt->set_time_zone( "UTC" );

  print($dt);

  return $dt;
}

1;