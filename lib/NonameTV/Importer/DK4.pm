package NonameTV::Importer::DK4;

use strict;
use warnings;
use utf8;
use Unicode::String;

=pod

Import data for DR in xml-format. 

=cut


use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml AddCategory norm normUtf8/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w p f/;
use Data::Dumper;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub FilterContent {
  my( $self, $cref, $chd ) = @_;

  $$cref =~ s|<?xml version="1.0" standalone="yes"?>|<?xml version="1.0" encoding="utf-8"?>|;
  $$cref =~ s|<dk4 xmlns="http://xml.dk4lan.dk">|<dk4>|;

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
  
  #$$cref = Unicode::String::latin1 ($$cref)->utf8 ();
  
  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//ProgramPunkt" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }
  
  foreach my $b ($ns->get_nodelist) {
  	# Start and so on
    my $start = ParseDateTime( $b->findvalue( "StartTid" ) );
    my $date = $start->ymd("-");

	if($date ne $currdate ) {
		if( $currdate ne "x" ) {
			#$ds->EndBatch( 1 );
		}

		my $batchid = $chd->{xmltvid} . "_" . $date;
		#$dsh->StartBatch( $batchid );
		$dsh->StartDate( $date );
		$currdate = $date;

		p("DK4: Date is: $date");
	}

    my $stop = $b->findvalue( "SlutTid" );
    my $title = $b->findvalue( "OriginalTitel" );
    my $subtitle = $b->findvalue( "EpisodeTitel" );
    my $year = $b->findvalue( "ProduktionsAar" );
    #my $country = $b->findvalue( "prd_prodcountry" );
    
    # Episode finder
    my $of_episode = undef;
    my $episode = undef;
    #$episode = $b->findvalue( "EpisodeNr" );
    #$of_episode = $b->findvalue( "AntalEpisoder" );
    
    # Descr. and genre
    my $desc = $b->findvalue( "Omtale1" );
    my $genre = $b->findvalue( "Genre" );

	# Put everything in a array	
    my $ce = {
      channel_id => $chd->{id},
      start_time => $start->hms(":"),
      title => norm($title),
      description => norm($desc),
      subtitle	  => norm($subtitle),
    };

	  # Episode info in xmltv-format
      #if( ($episode ne "") and ( $of_episode ne "") )
      #{
      #  $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
     # }
     # elsif( $episode ne "" )
     # {
     #   $ce->{episode} = sprintf( ". %d .", $episode-1 );
    #  }
    
    $ce->{production_date} = "$year-01-01" if $year ne "";
    
    my($program_type, $category ) = $ds->LookupCat( 'DK4', $genre );
	AddCategory( $ce, $program_type, $category );

	p( "DK4: $start - $title" );

    $dsh->AddProgramme( $ce );
  }

  return 1;
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) = 
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
#    time_zone => "Europe/Copenhagen"
      );

#  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = "http://xml.dk4lan.dk/";


  return( $url, undef );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
