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
use Roman;
use Data::Dumper;

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
  } elsif( norm($$cref) eq '<?xml version="1.0" encoding="ISO-8859-1"?>') {
    return "404 not found";
  } else {
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

  	# Episode and ofepisode
  	my ($episode2, $ofepisode, $rsarab, $episode);
  	if($title =~ /\((\d+)\)$/i) {
  	    ($episode2) = ($title =~ /\((\d+)\)$/i);
  	} elsif($title =~ /\((\d+):(\d+)\)$/i) {
  	    ($episode2, $ofepisode) = ($title =~ /\((\d+):(\d+)\)$/i);
  	}

  	# Clean it up
    $title =~ s/\(.*\)//g;
    $title =~ s/:\|apostrofe\|;/'/g;
    my $org_title = $b->findvalue( "originaltitel" );
    $org_title =~ s/:\|apostrofe\|;/'/g;
    my $titles = $title || $org_title;
    $titles =~ s/Tv-premiere://g if $titles;
    $titles =~ s/S.sonpremiere://g if $titles;
    $titles =~ s/S.sonafslutning://g if $titles;
  
  
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

    # Episode title
    my $subtitle = $b->findvalue( "pressoriginalepisodetitle" );
    $subtitle =~ s/:\|apostrofe\|;/'/g;

    # Genre (with prod year)
    my $genre = $b->findvalue( "genre" );


	# Put everything in a array	
    my $ce = {
      channel_id => $chd->{id},
      start_time => $start,
      title => norm($titles),
      description => norm($desc),
    };

    if($subtitle ne "") {
        my ( $original_title, $romanseason, $episode );

        # orgname - romanseason - num
        if($subtitle =~ /^(.*)\s+-\s+(.*)\s+-\s+(\d+)$/) {
            ( $original_title, $romanseason, $episode ) = ( $subtitle =~ /^(.*)\s+-\s+(.*)\s+-\s+(\d+)$/ );
            $ce->{episode} = sprintf( " . %d .", $episode-1 );
        }

        # orgname - num
        if($subtitle =~ /^(.*)\s+-\s+(\d+)$/) {
            ( $original_title, $episode ) = ( $subtitle =~ /^(.*)\s+-\s+(\d+)$/ );
            $ce->{episode} = sprintf( " . %d .", $episode-1 );
            $subtitle = "";
        }

        # orgname - romanseason (num)
        if($subtitle =~ /^(.*)\s+-\s+(.*)\s+\((\d+)\)$/) {
            ( $original_title, $romanseason, $episode ) = ( $subtitle =~ /^(.*)\s+-\s+(.*)\s+\((\d+)\)$/ );
            $ce->{episode} = sprintf( " . %d .", $episode-1 );
        }

        # Clean it up
        if(defined($romanseason)) {
            $romanseason =~ s/\(.*\)//g;
            $romanseason = norm($romanseason);
        }

        # Roman season found
        if(defined($romanseason) and isroman($romanseason)) {
            $rsarab = arabic($romanseason);
        }
    }

    # Episode
    if(defined($ofepisode)) {
        $ce->{episode} = sprintf( " . %d/%d .", $episode2-1, $ofepisode );
    } elsif(defined($episode2)) {
        $ce->{episode} = sprintf( " . %d .", $episode2-1 );
    }

    # Season
    if(defined($rsarab) and defined($ce->{episode})) {
        my $sea = $rsarab-1;
        $sea .= $ce->{episode};
        $ce->{episode} = $sea;
        $subtitle = "";
    }

    $ce->{subtitle} = norm($subtitle) if $subtitle;
    
    progress("$day $start - $titles");
    
    # Director (only movies)
    my ( $dir ) = ( $desc =~ /Instr.:\s+(.*)./ );
    if(defined($dir) and $dir ne "") {
    	$ce->{directors} = norm($dir);
    	$ce->{program_type} = 'movie';
    } else {
    	my $instruktion = $b->findvalue( "instruktion" );
    	my ( $instr ) = ( $instruktion =~ /Instr.:\s+(.*)/ );
    	if(defined($instr) and $instr and $instr ne "") {
    	    $instr = norm($instr);
    	    $instr =~ s/\.$//;
    	    $ce->{directors} = norm($instr);
            $ce->{program_type} = 'movie';
    	}
    }

    # Year
    if( ($genre =~ /fr. (\d\d\d\d)\b/i) or
    ($genre =~ /fra (\d\d\d\d)\.*$/i) )
    {
        $ce->{production_date} = "$1-01-01";
    }

    # Remove year from genre so we can parse it
    $genre =~ s/fra (\d+)//g;

    if( $genre and $genre ne "" ) {
		my($program_type, $category ) = $ds->LookupCat( 'SBSTV', $genre );
		AddCategory( $ce, $program_type, $category );
	}



    # Actors
    my $actors = $b->findvalue( "medvirkende" );
    my @acts;
    if($actors and $actors ne "") {
        $actors =~ s/Medv.://g;
        $actors =~ s/.$//g;
        my @actors_array = split(',', norm($actors));

        foreach my $actor (@actors_array) {
            # char name is before actor name
            my( $role, $act ) = ( $actor =~ /(.*):(.*)$/ );
            my $pushname = norm($act) . " (" . norm($role) . ")";


            push(@acts, $pushname);
        }

        $ce->{actors} = join( ", ", @acts );
    }


    if(defined($ce->{subtitle}) and ($ce->{subtitle} =~ /$ce->{title}/i)) {
        $ce->{subtitle} = undef;
    }

    $ce->{original_title} = norm($org_title) if $ce->{title} ne norm($org_title) and norm($org_title) ne "";

    $dsh->AddProgramme( $ce );
  }

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\bog\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
    s/\.//;
  }

  return join( ", ", grep( /\S/, @persons ) );
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
