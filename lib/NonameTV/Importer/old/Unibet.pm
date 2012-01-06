package NonameTV::Importer::Unibet;

use strict;
use warnings;

=pod

Importer for data from Unibet.
The downloaded file is in xml-format.

TODO:
Find a way to add so multiple programmes on the same starttime
can be exported and added, without any problems. Maybe a new
AddProgramme? AddProgrammeRaw doesn't seem to work.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = $self->{UrlRoot};

  return( $url, undef );
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
  my $dsh = $self->{datastorehelper};
  my $currdate = "x";
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }
  
  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//event" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }
  
  foreach my $sc ($ns->get_nodelist)
  {
  	if( $sc->findvalue( './isAvailableForStreaming' ) eq "true" ) {
  		my $date = ParseDate( $sc->findvalue( './startDate' ) );

      if( $date ) {

				my $xmltvid = $chd->{xmltvid};


        if( $date ne $currdate ) {
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
          progress("Unibet: $xmltvid: Date is $date");
        }
      }
      
      my $start = $sc->findvalue( './startTime' );
  	
    	my $title = $sc->findvalue( './eventName' );

			progress("Unibet: $chd->{xmltvid}: $start - $title");

    	my $ce = {
    	  title 	  => norm($title),
    	  channel_id  => $chd->{id},
    	  start_time  => $start,
    	};

    	$dsh->AddProgramme( $ce );
  	}
  }
  
  # Success
  return 1;
}

sub ParseDate {
  my( $str ) = @_;

  my( $year, $month, $day ) = 
      ($str =~ /^(\d\d)(\d\d)(\d\d)$/ );

	$year+= 2000 if $year< 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

1;