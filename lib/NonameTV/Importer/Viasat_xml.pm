package NonameTV::Importer::Viasat_xml;

use strict;
use warnings;

=pod

Importer for data from Viasat.
The data is a day-seperated feed of programmes.
<programtable>
	<day date="2012-09-10>
		<program>
		</program>
	</day>
</programtable>

Use this instead of Viasat.pm as the TAB-seperated is
a dumb idea. If an employee of MTG drops a tab in the desc
it think its a new field.
=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory AddCountry/;
use NonameTV::Log qw/w progress error f/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinWeeks} = 0 unless defined $self->{MinWeeks};
    $self->{MaxWeeks} = 4 unless defined $self->{MaxWeeks};
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    
    # use augment
    $self->{datastore}->{augment} = 1;

    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
  my $pad_len = 2;
  $week = sprintf("%0${pad_len}d", $week);

  my $url = 'http://press.viasat.tv/press/cm/listings/'. $chd->{grabber_info} . $year . '-' . $week.'.xml';

  return( $url, undef );
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref =~ '<!--' ) {
    return "404 not found";
  }
  elsif( $$cref eq '' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}


sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref =~ s| xmlns="http://www.mtg.se/xml/weeklisting"||g;
  $$cref =~ s|\?>|\?>\n|g;

  my $doc = ParseXml( $cref );
 
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  my $str = $doc->toString(1);

  return (\$str, undef);
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

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );
  my $currdate = "x";
  
  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//day" );
  
  if( $ns->size() == 0 ) {
    f "No days found";
    return 0;
  }

  foreach my $sched_date ($ns->get_nodelist) {
  	# Date
    my( $date ) = norm( $sched_date->findvalue( '@date' ) );
    
    if( $currdate ne "x" ){
		# save last day if we have it in memory
		#FlushDayData( $xmltvid, $dsh , @ces );
		#$dsh->EndBatch( 1 );
		#@ces = ();
	}

	#my $batch_id = "${xmltvid}_" . $date;
	#$dsh->StartBatch( $batch_id, $channel_id );
	$dsh->StartDate( $date , "00:00" ); 
	$currdate = $date;

	progress("Viasat: $xmltvid: Date is $date");
    
    # Programmes
    my $ns2 = $sched_date->find('program');
    foreach my $emission ($ns2->get_nodelist) {
      # General stuff
      my $start_time = $emission->findvalue( 'startTime' );
      my $other_name = $emission->findvalue( 'name' );
      my $original_name = $emission->findvalue( 'orgName' );
      my $name = $other_name || $original_name;
      $name =~ s/#//g; # crashes the whole importer
      $name =~ s/(HD)//g; # remove category_
      
      # # End of airtime
      if( ($name eq "END") )
      {
      	$name = "end-of-transmission";
      }
      
      if( ($name eq "GODNAT") )
      {
      	$name = "end-of-transmission";
      }

      if( $name =~ /^P.\s+GENSYN/)
      {
      	$name = "end-of-transmission";
      }
      
      
      # Category and genre
      my $category = $emission->findvalue( 'category' ); # category_series, category_movie, category_news
      $category =~ s/category_//g; # remove category_
      my $genre = $emission->findvalue( 'genre' );
      
      # Description
      my $desc_episode = $emission->findvalue( 'synopsisThisEpisode' );
      my $desc_series = $emission->findvalue( 'synopsis' );
      my $desc_logline = $emission->findvalue( 'logline' );
      my $desc = $desc_episode || $desc_series || $desc_logline;
      
      # Season and episode
      my $episode = $emission->findvalue( 'episode' );
      my $season = $emission->findvalue( 'season' );

      # Remove from title
      if(defined($season) and $season ne "" and $category eq "series") {
        $name =~ s/- s(.*)son $season$//;
        $name =~ s/$season$//;
        $name = norm($name);
      }

      my $eps = "";
      my $episode2 = "";
      ( $episode2, $eps ) = ($desc =~ /Del\s+(\d+):(\d+)/i );
      $desc =~ s/Del (\d+):(\d+)//gi;
      
      # Extra stuff
      my $prodyear = $emission->findvalue( 'productionYear' );
      my $widescreen = $emission->findvalue( 'wideScreen' );
      my $bline = $emission->findvalue( 'bline' );
      my $rerun = $emission->findvalue( 'rerun' );
      my $live = $emission->findvalue( 'live' );
      
      # Actors and directors
      my @actors;
      my @directors;

      my $ns3 = $emission->find( './/castMember' );
      foreach my $act ($ns3->get_nodelist)
	  {
	  	push @actors, $act->to_literal;
	  }

	  my @countries;
      my $ns4 = $emission->find( './/country' );
      foreach my $con ($ns4->get_nodelist)
	  {
	    my ( $c ) = $self->{datastore}->LookupCountry( "Viasat", $con->to_literal );
	  	push @countries, $c if defined $c;
	  }

	  my $ce = {
	      title       => norm($name),
	      description => norm($desc),
	      start_time  => $start_time,
      };
      
      $ce->{bline} = $bline if $bline;
      
      # Send back original swedish title
      if(norm($name) ne norm($original_name)) {
      	$ce->{original_title} = norm($original_name);
      }
      
      # Actors
      if( scalar( @actors ) > 0 )
	  {
	      $ce->{actors} = join ";", @actors;
	  }

      if( scalar( @countries ) > 0 )
	  {
	      $ce->{country} = join "/", @countries;
	  }
	  
	  # prod year
	  if(defined($prodyear) and $prodyear ne "" and $prodyear =~ /(\d\d\d\d)/)
	  {
	  	$ce->{production_date} = "$1-01-01";
	  } elsif(defined($bline) and $bline ne "" and $bline =~ /(\d\d\d\d)/) {
        $ce->{production_date} = "$1-01-01";
      }
	  
	  # Find aspect-info
	  if( $widescreen eq "true" )
	  {
	    $ce->{aspect} = "16:9";
	  }
	  else
	  {
	    $ce->{aspect} = "4:3";
	  }
	  
	  # Find rerun-info
	  if( $rerun eq "true" )
	  {
	    $ce->{rerun} = "1";
	  }
	  else
	  {
	    $ce->{rerun} = "0";
	  }
	  
	  # Find live-info
	  if( $live eq "true" )
	  {
	    $ce->{live} = "1";
	  }
	  else
	  {
	    $ce->{live} = "0";
	  }

	  if( $emission->findvalue( 'director' ) ) {
	    my $dirs = norm($emission->findvalue( 'director' ));
	    $dirs =~ s/ & /, /g;
	    $ce->{directors} = parse_person_list($dirs);
	  }

      
      # Episodes
      if($episode2 and $episode2 ne "") {
      	if($season) {
      		if($eps and $eps ne "") {
      			$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode2-1, $eps );
      		} else {
      			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode2-1 );
      		}
      	}elsif($eps and $eps ne "") {
      		$ce->{episode} = sprintf( " . %d/%d . ", $episode2-1, $eps );
      	} else {
      		$ce->{episode} = sprintf( " . %d . ", $episode2-1 );
      	}
      } elsif($episode) {
      	if($season) {
      		if($eps and $eps ne "") {
      			$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode-1, $eps );
      		} else {
      			$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      		}
      	}elsif($eps and $eps ne "") {
      		$ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $eps );
      	} else {
      		$ce->{episode} = sprintf( " . %d . ", $episode-1 );
      	}
      }
      
      # Genres and category
      my( $pty, $cat );
	  if(defined($genre) and $genre and $genre ne "") {
	      ( $pty, $cat ) = $ds->LookupCat( 'Viasat2_genre', $genre );
	  	  AddCategory( $ce, $pty, $cat );
	  }
	  
	  if(defined($category) and $category and $category ne "") {
	      ( $pty, $cat ) = $ds->LookupCat( 'Viasat2_category', $category );
	  	  AddCategory( $ce, $pty, $cat );
	  }

	  $ce->{external_ids} = 'viasat_' . $emission->findvalue( 'uniqueId' );
      
      progress( "Viasat: $chd->{xmltvid}: $start_time - $name" );
      $dsh->AddProgramme( $ce );
    }
  }

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;