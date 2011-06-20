package NonameTV::Importer::KanalLokal;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f/;

use NonameTV::Importer::BaseUnstructured;

use base 'NonameTV::Importer::BaseUnstructured';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

  return $self;
}

sub ImportContent {
  my $self = shift;
  my( $filename, $cref, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($$cref); };

  if( not defined( $doc ) ) {
    f "Not well-formed xml";
    return 0;
  }
  
  my $ns = $doc->find( "//Event" );
  
  if( $ns->size() == 0 ) {
    f "No Events found";
    return 0;
  }

  my $batch_id;

  foreach my $div ($ns->get_nodelist) {
    my $date = norm( $div->findvalue( 'StartDate' ) );
    my $starttime = norm( $div->findvalue( 'StartTime' ) );
    my $endtime = norm( $div->findvalue( 'EndTime' ) );
    my $title1 = norm( $div->findvalue( 'Title1' ) );
    my $title2 = norm( $div->findvalue( 'Title2' ) );
    my $synopsis = norm( $div->findvalue( 'Synopsis1' ) );

    # Prefer Title2 before Title1
    my $title = $title2 eq "" ? $title1 : $title2;

    if( not defined( $batch_id ) ) {
      $batch_id = $xmltvid . "_" . FindWeek( $date );
      $ds->StartBatch( $batch_id );
    }

    $starttime =~ s/^(\d+:\d+).*/$1/;
    $endtime =~ s/^(\d+:\d+).*/$1/;

    my $start_dt = $self->to_utc( $date, $starttime );
    my $end_dt = $self->to_utc( $date, $endtime );

    if( not defined( $start_dt ) ) {
      w "Invalid start-time '$date' '$starttime'. Skipping.";
      next;
    }

    if( not defined( $end_dt ) ) {
      w "Invalid end-time '$date' '$endtime'. Skipping.";
      next;
    }

    if( $starttime gt $endtime ) {
      $end_dt = $end_dt->add( days => 1 );
    }

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      description => $synopsis,
      start_time => $start_dt->ymd('-') . " " . $start_dt->hms(':'),
      end_time => $end_dt->ymd('-') . " " . $end_dt->hms(':'),
    };
    
    $ds->AddProgramme( $ce );
  }

  $ds->EndBatch( 1 );
    
  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  my( $year, $month, $day ) = split( '-', $text );

  my $dt = DateTime->new(
			 year => $year,
			 month => $month,
			 day => $day );

  return $dt;
}

sub FindWeek {
  my( $text ) = @_;

  my $dt = ParseDate( $text );

  my( $week_year, $week_num ) = $dt->week;

  return "$week_year-$week_num";
}

sub to_utc {
  my $self = shift;
  my( $date, $time ) = @_;

  my( $year, $month, $day ) = split( '-', $date );
  my( $hour, $minute ) = split( ":", $time );

  my $dt;

  eval { 
    $dt = DateTime->new( year   => $year,
			 month  => $month,
			 day    => $day,
			 hour   => $hour,
			 minute => $minute,
			 time_zone => 'Europe/Stockholm',
			 );
  };

  if( not defined $dt ) {
    return undef;
  }

  $dt->set_time_zone( "UTC" );

  return $dt;
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
