package NonameTV::Importer::NonstopWeb;

use strict;
use warnings;

=pod

Importer for data from Nonstop. 
One file per channel and month downloaded from their site.
The downloaded file is in xml-format.

=cut

use utf8;
use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml normUtf8 AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseMonthly;

use base 'NonameTV::Importer::BaseMonthly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinMonths} = 0;
    $self->{MaxMonths} = 1;

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;
    
    #$self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $url = $self->{UrlRoot} .
    $chd->{grabber_info} . '/' . $year . '/' . $month;

  #return( $url, undef );
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

	#$$cref =~ s|encoding="utf-8"|encoding="utf8" |;

  my $doc;
  #$doc = ParseXml( $cref );
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($$cref); };

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//rs:data" );

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
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;
  my $dsh = $self->{datastorehelper};
  
    
  
  my $currdate = "x";
  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  print Dumper( $chd, $dsh, $batch_id , $channel_id );
  
  
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }
  
  # Find all "Schedule"-entries.
    my $ns = $doc->find( "//z:row" );
    
    if( $ns->size() == 0 ) {
        error( "Nonstop: $chd->{xmltvid}: No data found" );
        return;
    }
    
    my $column;

    foreach my $sc ($ns->get_nodelist) {
        my $start = $self->create_dt( $sc->findvalue( './@SlotUTCStartTime' ) );
        if( not defined $start )
        {
            w "Invalid starttime '" 
            . $sc->findvalue( './@SlotUTCStartTime' ) . "'. Skipping.";
            next;
        }
        
        # Date
        my $date = $start->ymd("-");
        my $time = $start->hms(":");
        
        ## Title
        my $title_original = $sc->findvalue( './@SeriesOriginalTitle' );
        my $title_programme = $sc->findvalue( './@ProgrammeSeriesTitle' );
        my $title = normUtf8($title_programme) || normUtf8($title_original);
       #my $title = normUtf8($title_original)  || normUtf8($title_programme);
        
        ## Batch
        if($date ne $currdate ) {
            if( $currdate ne "x" ) {
                #$dsh->EndBatch( 1 );
            }

            my $batchid = $xmltvid . "_" . $date;
            #$dsh->StartBatch( $batch_id , $channel_id );
            $dsh->StartDate( $date , "06:00" );
            $currdate = $date;

            progress("Nonstop: Date is: $date");
        }
        
        ## Description
        my $desc = undef;
        my $desc_episode = $sc->findvalue( './@ProgrammeEpisodeLongSynopsis' );
        my $desc_series  = $sc->findvalue( './@ProgrammeSeriesLongSynopsis' );
        $desc = $desc_episode || $desc_series;
        
        my $genre = $sc->findvalue( './@SeriesGenreDescription' );
       #my $subgenre = $sc->findvalue( './@SeriesSubGenreDescription' ); # Same data as the one above, somehow.
        my $production_year = $sc->findvalue( './@ProgrammeSeriesYear' );
        
        # Subtitle, DefaultEpisodeTitle contains the original episodetitle.
        # I.e. Plastic Buffet for Robot Chicken
        # For some series (mostly on TNT7) defaultepisodetitle contains (Part {episodenum})
        # That should be remove later on, but for now you should use Tvdb augmenter for that.
        my $subtitle_episode = $sc->findvalue( './@ProgrammeEpisodeTitle' );
        my $subtitle_default = $sc->findvalue( './@DefaultEpisodeTitle' );
        my $subtitle = normUtf8($subtitle_default) || normUtf8($subtitle_episode);
        
        
        progress("Nonstop: $xmltvid: $time - $title");

        my $ce = {
            title       => $title,
            channel_id  => $channel_id,
            description => normUtf8($desc),
            start_time  => $time,
        };

        my ( $dummy, $season, $episode ) = ($desc =~ /\(S(.*)song\s*(\d+)\s*avsnitt\s*(\d+)\)/ );
    
        if((defined $season) and ($episode > 0) and ($season > 0) )
        {
            $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
            $ce->{program_type} = "series";
        }
        elsif((defined $episode) and ($episode > 0) )
        {
            $ce->{episode} = sprintf( ". %d .", $episode-1 );
            $ce->{program_type} = "series";
        }
        
        $ce->{description} =~ s/\(S(.*)song(.*)\)$//;
        
        # Year (it should actually get year from augmenter instead (as sometimes it's the wrong year))
        if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
        {
            $ce->{production_date} = "$1-01-01";
        }
        
        
        # Genre
        if( $genre ){
            my($program_type, $category ) = $ds->LookupCat( 'Nonstop', $genre );
            AddCategory( $ce, $program_type, $category );
        }
        
        # HD
        if($sc->findvalue( './@HighDefinition' ) eq "1") {
            $ce->{quality} = "HDTV";
        }
        
        # On movies, the subtitle (defaultepisodetitle) is same as seriestitle
        if($title ne $subtitle) {
            #if(defined($ce->{program_type}) and ($ce->{program_type} ne "movie")) {
                $ce->{subtitle} = $subtitle if $subtitle;
            #}
        }
        
        # Get credits
        # Make arrays
        my @actors;
        my @directors;
        my @writers;
    
        # Change $i if they add more actors in the future
        for( my $v=1; $v<=5; $v++ ) {
            my $actor_name = normUtf8($sc->findvalue( './@ProgrammeSeriesCreditsContact' . $v ));
            my $job = $sc->findvalue( './@ProgrammeSeriesCreditsCredit' . $v );
            # Check if it's defined (that that actor is already in the xmlfeed)
            if(defined($actor_name)) {
                # Check the job
                if(defined($job) and $job =~ /Act/) {
                    push(@actors, $actor_name);
                }
                if(defined($job) and $job =~ /Himself/) {
                    push(@actors, $actor_name);
                }
                if(defined($job) and $job =~ /Director/) {
                    push(@directors, $actor_name);
                }
                if(defined($job) and $job =~ /Creator/) {
                    push(@writers, $actor_name);
                }
                
            }
        }
        
        # Get the peoples.
        $ce->{actors} = join( ", ", grep( /\S/, @actors ) );
        $ce->{directors} = join( ", ", grep( /\S/, @directors ) );
        $ce->{writers} = join( ", ", grep( /\S/, @writers ) );
        
        # Remove big subtitle for Commerical programmes.
        if($ce->{title} eq "Commercial programming") {
            $ce->{subtitle} = undef;
        }
        
        $dsh->AddProgramme( $ce );
    }
    
    #$dsh->EndBatch( 1 );
  
    # Success
    return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $date, $time ) = split( 'T', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  if( $second > 59 ) {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'UTC',
                          );
  
  $dt->set_time_zone( "Europe/Stockholm" );
  
  return $dt;
}
    
1;
