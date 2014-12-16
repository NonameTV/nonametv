package NonameTV::Importer::NonstopWeb;

use strict;
use warnings;

=pod

Importer for data from Nonstop.
One file per channel and month downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;
use Text::Unidecode;
use File::Slurp;
use Encode;

use NonameTV qw/ParseXml norm AddCountry AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "Nonstop: $chd->{xmltvid}: Processing XML $file" );
 
  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };
  if( $@ ne "" )
  {
    error( "Nonstop: $file: Failed to parse xml" );
    return 0;
  }
  
  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//z:row" );

  if( $ns->size() == 0 )
  {
    error( "Nonstop: $file: No data found." );
    return 0;
  }
  
  foreach my $sc ($ns->get_nodelist)
  {
    my $title_original = $sc->findvalue( './@SeriesOriginalTitle' );
    my $title_programme = $sc->findvalue( './@ProgrammeSeriesTitle' );
    my $title = norm($title_programme) || norm($title_original);

    my $start = $self->create_dt( $sc->findvalue( './@SlotLocalStartTime' ) );
    if( not defined $start )
    {
      w "Invalid starttime '"
          . $sc->findvalue( './@SlotLocalStartTime' ) . "'. Skipping.";
      next;
    }
    
    my $desc = undef;
    my $desc_episode = $sc->findvalue( './@ProgrammeEpisodeLongSynopsis' );
	my $desc_series = $sc->findvalue( './@ProgrammeSeriesLongSynopsis' );
	$desc = $desc_episode || $desc_series;

	my $genre = $sc->findvalue( './@SeriesGenreDescription' );
	my $production_year = $sc->findvalue( './@ProgrammeSeriesYear' );
		# Subtitle, DefaultEpisodeTitle contains the original episodetitle.
        # I.e. Plastic Buffet for Robot Chicken
        # For some series (mostly on TNT7) defaultepisodetitle contains (Part {episodenum})
        # That should be remove later on, but for now you should use Tvdb augmenter for that.
    my $subtitle_episode = $sc->findvalue( './@ProgrammeEpisodeTitle' );
    my $subtitle_default = $sc->findvalue( './@DefaultEpisodeTitle' );
    my $subtitle = norm($subtitle_episode) || norm($subtitle_default);
    my $aspect = $sc->findvalue( './@ProgrammeVersionTechnicalTypesAspect_Ratio' );
    my $country = $sc->findvalue( './@SeriesCountryOfOrigin' );

    my $ce = {
      title => norm($title),
      channel_id => $chd->{id},
      description => norm($desc),
      start_time => $start->ymd("-") . " " . $start->hms(":"),
    };

    my($country2 ) = $ds->LookupCountry( "Nonstop", norm($country) );
    AddCountry( $ce, $country2 );
    
    my ( $dummy, $season, $dummy2, $episode ) = ($desc =~ /\((S.song|Season)\s*(\d+)\s*(avsnitt|episode)\s*(\d+)\)/i );
    
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
        
        $ce->{description} =~ s/\(S.song(.*)\)$//;
        $ce->{description} =~ s/\(Season(.*)\)$//;
        
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
    
        # Change $iv if they add more actors in the future
        for( my $v=1; $v<=5; $v++ ) {
            my $actor_name = norm($sc->findvalue( './@ProgrammeSeriesCreditsContact' . $v ));
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
        $ce->{actors} = join( ";", grep( /\S/, @actors ) );
        $ce->{directors} = join( ";", grep( /\S/, @directors ) );
        $ce->{writers} = join( ";", grep( /\S/, @writers ) );
        
        # Remove big subtitle for Commerical programmes.
        if($ce->{title} eq "Commercial programming") {
            $ce->{subtitle} = undef;
        }
    
    
    
    if( (defined $aspect) and ($aspect eq "16*9 (2)")) {
     $ce->{aspect} = "16:9";
    } else {
     $ce->{aspect} = "4:3";
    }
    
    if( $genre ){
		my($program_type, $category ) = $ds->LookupCat( 'Nonstop', $genre );
		AddCategory( $ce, $program_type, $category );
	}

	$ce->{original_title} = norm($title_original) if defined($title_original) and $ce->{title} ne norm($title_original) and norm($title_original) ne "";

    $ds->AddProgramme( $ce );
    progress("Nonstop: $chd->{xmltvid}: $start - $title");
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  # Failsafe
  if($str eq "2012-03-25T02:30:00") {
  	next;
  }
  
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

  my $dt = DateTime->new( year => $year,
                          month => $month,
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => "Europe/Stockholm",
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}
    
1;