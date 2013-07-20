package NonameTV::Importer::BBC;

use strict;
use warnings;

=pod

Importer for data from BBC.co.uk.
Could be radio, tv channels etc.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinDays} = 0 unless defined $self->{MinDays};
    $self->{MaxDays} = 7 unless defined $self->{MaxDays};

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );

  my( $service, $outlet ) = split( /:/, $chd->{grabber_info} );

  my $url = 'http://www.bbc.co.uk/'.$service.'/programmes/schedules/'.$outlet.'/'.$year.'/'.$month.'/'.$day.'.xml';

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
  my $ns = $doc->find( "//broadcast" );

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
  my $ns = $doc->find( "//broadcasts" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }


  foreach my $sc ($ns->get_nodelist)
  {
		my $start = $self->create_dt( $sc->findvalue( './/start' ) );
        if( not defined $start )
        {
          w "Invalid starttime '"
              . $sc->findvalue( './/start' ) . "'. Skipping.";
          next;
        }

        my $end = $self->create_dt( $sc->findvalue( './/end' ) );

        my $ce = {
                channel_id => $chd->{id},
                title => norm($sc->findvalue( './/display_titles/title' ) ),
                subtitle => norm($sc->findvalue( './/display_titles/subtitle' ) ),
                description => norm($sc->findvalue( './/short_synopsis' ) ),
                start_time => $start->ymd("-") . " " . $start->hms(":"),
                end_time => $end->ymd("-") . " " . $end->hms(":"),
              };

        progress( "BBC: $chd->{xmltvid}: $start - ".norm($sc->findvalue( './/display_titles/title' ) ) );
    	$ds->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    time_zone => "Europe/Stockholm"
      );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;