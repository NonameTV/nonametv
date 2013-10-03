package NonameTV::Importer::SBSTV;

use strict;
use warnings;
use utf8;

=pod

Import data for SBS TV Denmark. The format is XML.

The grabberinfo must the same as the <station></station>-tag in the XML.

Channels: Kanal 4, Kanal 5, 6'eren and The Voice TV.

(May not be used in commercial usage without allowance from SBSTV)

=cut


use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress w f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


	$self->{datastore}->{augment} = 1;
  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  if( defined( $self->{UrlRoot} ) ){
    w( 'UrlRoot is deprecated' );
  } else {
    $self->{UrlRoot} = 'http://ttv.sbstv.dk/programoversigtxml/xml.php';
  }

  return $self;
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref eq '<!--error in request: -->' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub FilterContent {
  my( $self, $cref, $chd ) = @_;

  return( $cref, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;
  
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $channel_name = $chd->{name};
  my $grabber_info = $chd->{grabber_info};
  my $currdate = "x";
  

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }
  
  
  foreach my $b ($ns->get_nodelist) {
  	my $station = $b->findvalue( "station" );
  	my $day = $b->findvalue( "day" );
  	
  	if( $day ne $currdate ) {

          #$dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $day , "00:00" ); 
          $currdate = $day;

          progress("Date is $day");
    }
  	
  	# Skip if the channel_name aint right
  	if($station ne $grabber_info) {
  		next;
  	}
  
  	my $title = $b->findvalue( "titel" );
    $title =~ s/\(.*\)//g;
    $title =~ s/:\|apostrofe\|;/'/g;
    my $org_title = $b->findvalue( "originaltitel" );
    $org_title =~ s/:\|apostrofe\|;/'/g;
    my $titles = $org_title || $title;
  
  
  	# Start and so on
    my $starttime = $b->findvalue( "starttid" );
    
    if($starttime eq "") {
    	f("No starttime for $titles");
    	next;
    }
    
    my( $start, $start_dummy ) = ( $starttime =~ /(\d+:\d+):(\d+)/ );
    #my $stoptime = $b->findvalue( "sluttid" );
    #my( $stop, $stop_dummy ) = ( $stoptime =~ /(\d+:\d+):(\d+)/ );

    
    # Descr. and genre
    my $desc = $b->findvalue( "ptekst1" );
    $desc =~ s/:\|apostrofe\|;/'/g;
    
   
    
    my $genre = $b->findvalue( "genre" );
    $genre =~ s/fra (\d+)//g;

	# Put everything in a array	
    my $ce = {
      channel_id => $chd->{id},
      start_time => $start,
      title => norm($titles),
      description => norm($desc),
    };
    
    progress("$day $start - $titles");
    
    # Director
    my ( $dir ) = ( $desc =~ /Instr.:\s+(.*)./ );
    if(defined($dir) and $dir ne "") {
    	$ce->{directors} = norm($dir);
    } else {
    	my $instruktion = $b->findvalue( "instruktion" );
    	my ( $instr ) = ( $instruktion =~ /Instr.:\s+(.*)./ );
    	$ce->{directors} = norm($instr);
    }
    
    if( $genre and $genre ne "" ) {
		my($program_type, $category ) = $ds->LookupCat( 'SBSTV', $genre );
		AddCategory( $ce, $program_type, $category );
	}


    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}


sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;


  my( $year, $month, $day ) = ( $objectname =~ /20(\d+)-(\d+)-(\d+)$/ );

  my $url = sprintf( "%s?dato=%s%s%s",
                     $self->{UrlRoot},  $day, $month, $year);


  return( $url, undef );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
