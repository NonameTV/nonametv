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
  $$cref =~ s|<programmablauf>\n</programmtag>|<programmablauf>\n<programmtag />|s;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programmablauf" );

  if( $ns->size() == 0 ) {
    # TODO sometimes there seem to be no programs on sportplus
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


		progress("ORF_xml: $chd->{xmltvid}: $time - $title");

  		my $ce = {
  	      title 	  => norm($title),
 	      start_time  => $time,
   		};
   	 
  	  	my $desc = $sc->findvalue( './info' );
		# strip repeat
		$desc =~ s|\(Wh\..+?\)||;
		my( $genre, $countries, $year )=( $desc =~ m|\((.+?), (.+?) (\d{4})\)| );
		if( $year ){
			$desc =~ s|\(.+?, .+? \d{4}\)||;
			$ce->{production_date} = $year . '-01-01';

			# split optional "original title - genre"
			$genre =~ s|^.+ - (.+?)$|$1|;
			my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "ORF", $genre );
			# set category, unless category is already set!
			AddCategory( $ce, $program_type, $categ );
		}
	      $ce->{description} = norm($desc) if $desc;

		my $subtitle =  $sc->findvalue( './subtitel' );
   	 	$ce->{subtitle} = norm($subtitle) if $subtitle;
	
		my $stereo =  $sc->findvalue( './m' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'mono';
		}

		$stereo =  $sc->findvalue( './s' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'stereo';
		}

		# dolby surround sound
		$stereo =  $sc->findvalue( './dss' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'surround';
		}

		# dolby digital surround / AC-3 5.1
		$stereo =  $sc->findvalue( './dds' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'dolby digital';
		}

		$stereo =  $sc->findvalue( './zs' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'bilingual';
		}

		my $widescreen =  $sc->findvalue( './bb' );
		if( $widescreen eq 'True' ){
   	 		$ce->{aspect} = '16:9';
		}

#		my $captions =  $sc->findvalue( './ut' );
#		if( $captions eq 'True' ){
#   	 		$ce->{captions} = 'teletext';
#		}

	
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
