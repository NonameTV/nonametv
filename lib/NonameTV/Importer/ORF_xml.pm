package NonameTV::Importer::ORF_xml;

use strict;
use warnings;

=pod

Importer for data from ORF.
The data is downloaded from ORF's presservice at http://presse.orf.at/
Every day is handled as a separate batch.

Channels: ORF1, ORF2, DreiSat, (a lot of radio stations)

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinDays} = 0 unless defined $self->{MinDays};
    $self->{MaxDays} = 15 unless defined $self->{MaxDays};

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Vienna" );
  	$self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );
 
  my $url = $self->{UrlRoot} .
    $chd->{grabber_info} . '&date=' . $year . $month . $day;

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $$cref =~ s|encoding="LATIN1"|encoding="windows-1252"|;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programmablauf" );

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
  my $dsh = $self->{datastorehelper};
  
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
  	my( $date ) = ($batch_id =~ /_(.*)$/);
	
	$dsh->StartDate( $date , "00:00" );
 
 	 # Find all "z:row"-entries.
 	 my $ns = $doc->find( "//sendung" );

 	 if( $ns->size() == 0 )
 	 {
 	   f "No data found";
 	   return 0;
 	 }
  
  	 
 	 foreach my $sc ($ns->get_nodelist)
  	{

	
	my $title = $sc->findvalue( './titel' );
	

   	 my $time = ParseTime( $sc->findvalue( './zeit' ) );

  	  	my $desc = $sc->findvalue( './info' );
	
		my $subtitle =  $sc->findvalue( './subtitel' );

		progress("ORF_xml: $chd->{xmltvid}: $time - $title");

  		my $ce = {
  	      title 	  => norm($title),
 	      channel_id  => $chd->{id},
	      description => norm($desc),
 	      start_time  => $time,
   		};
   	 
   	 	$ce->{subtitle} = norm($subtitle) if $subtitle;
	
  	  $dsh->AddProgramme( $ce );
 	 }
  
  # Success
  return 1;
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }
  
  return sprintf( "%02d:%02d", $hour, $min );
}
    
1;
