package NonameTV::Augmenter::Tvdb;

use strict;
use warnings;

use TVDB::API;
use utf8;
use Data::Dumper;

use NonameTV qw/norm normUtf8 AddCategory/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{ApiKey} )   or die "You must specify ApiKey";
    defined( $self->{Language} ) or die "You must specify Language";

    # need config for main content cache path
    my $conf = ReadConfig( );

    my $cachefile = $conf->{ContentCachePath} . '/' . $self->{Type} . '/tvdb.' . $self->{Language} . '.db';
    my $bannerdir = $conf->{ContentCachePath} . '/' . $self->{Type} . '/banner';

    $self->{tvdb} = TVDB::API::new({ apikey    => $self->{ApiKey},
                                     lang      => $self->{Language},
                                     cache     => $cachefile,
                                     banner    => $bannerdir,
                                     useragent => "nonametv (http://nonametv.org)",
                                  });
    # only update if there is some data to be updated
    if (defined ($self->{tvdb}->{cache}->{Update}->{lastupdated})) {
     # $self->{tvdb}->getUpdates( 'guess' );
    }else{
      # on an empty cache set last update before fetching any data to
      # avoid getting the list of all updates just to see that there is
      # nothing to update
      $self->{tvdb}->{cache}->{Update}->{lastupdated} = time( );
    }

    my $langhash = $self->{tvdb}->getAvailableLanguages( );
    $self->{LanguageNo} = $langhash->{$self->{Language}}->{id};

    # only consider Ratings with 10 or more votes by default
    if( !defined( $self->{MinRatingCount} ) ){
      $self->{MinRatingCount} = 10;
    }

    my $opt = { quiet => 1 };
    Debug::Simple::debuglevels($opt);

    return $self;
}


sub ParseCast( $$ ) {
  my( $self, $cast )=@_;

  my $result;

  my @people = ();
  if( $cast ) {
    push( @people, split( '\||, ', $cast ) );
  }
  foreach( @people ){
    $_ = normUtf8( norm( $_ ) );
    if( $_ eq '' ){
      $_ = undef;
    }
  }
  @people = grep{ defined } @people;
  if( @people ) {
    # replace
    $result = join( ';', @people );
  } else {
    # remove
    $result = undef;
  }

  return( $result );
}


sub FillHash( $$$$ ) {
  my( $self, $resultref, $series, $episode, $ceref )=@_;

  return if( !defined $episode );

  my $episodeid = $series->{Seasons}[$episode->{SeasonNumber}][$episode->{EpisodeNumber}];

  #print Dumper($series);

  if( $episode->{SeasonNumber} == 0 ){
    # it's a special
    $resultref->{episode} = undef;
    $resultref->{subtitle} = normUtf8( norm( "Special - ".$episode->{EpisodeName} ) );
  }else{
    $resultref->{episode} = ($episode->{SeasonNumber} - 1) . ' . ' . ($episode->{EpisodeNumber} - 1) . ' .';

    # use episode title
    $resultref->{subtitle} = normUtf8( norm( $episode->{EpisodeName} ) ) if not defined $ceref->{original_subtitle};
  }

# TODO skip the Overview for now, it falls back to english in a way we can not detect
#  if( defined( $episode->{Overview} ) and ($episode->{Language} eq $self->{Language}) and !defined($resultref->{description}) ) {
#    $resultref->{description} = normUtf8(norm($episode->{Overview})) . "\nSource: TheTVDB.com - DMCA Takedown via Link in URL";
#  }

  if( $series->{FirstAired} ) {
    $resultref->{production_date} = $series->{FirstAired};
  }
  
  # episodepic
  if( $episode->{filename} ) {
#    $resultref->{url_image_main} = sprintf('http://thetvdb.com/banners/%s', $episode->{filename});
  }

  if(defined($episodeid)) {
      $resultref->{url} = sprintf(
        'http://thetvdb.com/?tab=episode&seriesid=%d&seasonid=%d&id=%d&lid=%d',
        $episode->{seriesid}, $episode->{seasonid}, $episodeid, $self->{LanguageNo}
      );
  }
  
  my $tvdbactors = $series->{Actor};

  my @actors = ();
  # only add series actors if its not a special
  if( $episode->{SeasonNumber} != 0 and $series->{Actor} and $series->{Actor} ne "" ){
    while ( my ($actorid, $data) = each %{ $tvdbactors } ) {
      my $name = normUtf8( norm ( $data->{Name} ) );

      # Role played
      if( defined ($data->{Role}) ) {
      	$name .= " (".normUtf8( norm ( $data->{Role} ) ).")";
      }

       push @actors, $name;
    }
  }

  # always add the episode cast
  if( $episode->{GuestStars} ) {
    push( @actors, split( '\|', norm($episode->{GuestStars}) ) );
  }
  foreach( @actors ){
    $_ = normUtf8( norm( $_ ) );
    if( $_ eq '' ){
      $_ = undef;
    }
  }
  @actors = grep{ defined } @actors;
  
  if( @actors ) {
  	  # replace programme's actors
	  $resultref->{actors} = join( ';', @actors );
	} else {
	  # remove existing actors from programme
	  $resultref->{actors} = undef;
  }

	$resultref->{directors} = $self->ParseCast( norm($episode->{Director}) );
	$resultref->{writers} = $self->ParseCast( norm($episode->{Writer}) );

  $resultref->{program_type} = 'series';  
  # Genre
  if( $series->{Genre} ){
    if( $episode->{SeasonNumber} != 0 ){
      # notice, Genre is ordered by some internal order, not by importance!
      my @genres = split( '\|', $series->{Genre} );
      foreach( @genres ){
        $_ = normUtf8( norm( $_ ) );
        if( $_ eq '' ){
          $_ = undef;
        }
      }
      @genres = grep{ defined } @genres;
      my @cats;
      foreach my $genre ( @genres ){
        my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "Tvdb", $genre );
        # set category, unless category is already set!
        push @cats, $categ if defined $categ;
      }
      my $cat = join "/", @cats;
      AddCategory( $resultref, undef, $cat );
    } else {
      $resultref->{category} = 'Special';
    }
  }

  # Use episode rating if there are more then MinRatingCount ratings for the episode. If the
  # episode does not have enough ratings consider using the series rating instead (if that has enough ratings)
  # if not rating qualifies leave it away.
  # the Rating at Tvdb is 1-10, turn that into 0-9 as xmltv ratings always must start at 0
  if(defined($episode->{RatingCount}) and defined($self->{MinRatingCount})) {
  	if( $episode->{RatingCount} >= $self->{MinRatingCount} ){
    	$resultref->{'star_rating'} = $episode->{Rating}-1 . ' / 9';
  	} elsif( $series->{RatingCount} >= $self->{MinRatingCount} ){
    	$resultref->{'star_rating'} = $series->{Rating}-1 . ' / 9';
  	}
  }
  
  
  # Extra id
  $resultref->{extra_id} = $episode->{seriesid};
  $resultref->{extra_id_type} = "thetvdb";
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';



  if( $ceref->{title} eq 'SOKO Leipzig' ){
    # broken dataset on Tvdb
    return( undef, 'known bad data for SOKO Leipzig, skipping' );
  }

  # Runned before every other "matchby", so it can guess the right "matchby" by what data which is supplied.
  if( $ruleref->{matchby} eq 'guess' ) {
    # Subtitles, no episode
    if(defined($ceref->{subtitle}) && !defined($ceref->{episode})) {
    	# Match it by subtitle
    	$ruleref->{matchby} = "episodetitle";
    } elsif(!defined($ceref->{subtitle}) && defined($ceref->{episode})) {
    	# The opposite, match it by episode
    	$ruleref->{matchby} = "episodeseason";
    } elsif(defined($ceref->{subtitle}) && defined($ceref->{episode})) {
        # Check if it has season otherwise title.
        my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
        if( (defined $episode) and (defined $season) ){
            $ruleref->{matchby} = "episodeseason";
        } else {
            $ruleref->{matchby} = "episodetitle";
        }
    } else {
    	# Match it by seriesname (only change series name) here later on maybe?
    	return( undef, 'couldn\'t guess the right matchby, sorry.' );
    }
  }

  if( $ceref->{url} && $ceref->{url} =~ m|^http://thetvdb\.com/| ) {
      #$result = "programme is already linked to thetvdb.com, ignoring";
      #$resultref = undef;
  }elsif( $ceref->{url} && $ceref->{url} =~ m|^http://tvrage\.com/| ) {
      #$result = "programme is already linked to tvrage.com, ignoring";
      #$resultref = undef;
  }elsif( $ruleref->{matchby} eq 'episodeabs' ) {
    # match by absolute episode number from program hash. USE WITH CAUTION, NOT EVERYONE AGREES ON ANY ORDER!!!

    if( defined $ceref->{episode} ){
      my( $episodeabs )=( $ceref->{episode} =~ m|^\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      if( defined $episodeabs ){
        $episodeabs += 1;

        my $series;
        if( defined( $ruleref->{remoteref} ) ) {
          my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref}, 0 );
          $series = $self->{tvdb}->getSeries( $seriesname, 0 );
        } else {
          $series = $self->{tvdb}->getSeries( $ceref->{title}, 0 );

          # Check against original title if the title cant be found.
          if(!(defined($series)) and (defined($ceref->{original_title}) and $ceref->{original_title} ne "")) {
          #      w("trying original title ".$ceref->{original_title}." instead of ".$ceref->{title});
                $series = $self->{tvdb}->getSeries( $ceref->{original_title}, 0 );
          }
        }
        if( defined $series ){
          my $episode = $self->{tvdb}->getEpisodeAbs( $series->{SeriesName}, $episodeabs );

          if( defined( $episode ) ) {
            $self->FillHash( $resultref, $series, $episode, $ceref );
          } else {
            w( "no absolute episode " . $episodeabs . " found for '" . $ceref->{title} . "'" );
          }
        }
      }
    }
  }elsif( $ruleref->{matchby} eq 'episodeseason' ) {
    # match by episode and season - Note that the episode and season
    # must be the real episode and season, often on swedish channels
    # like TV4 the season is year, this will not work. As TheTVDb only
    # use the real season, like 5. And about episodes, some channels like
    # Viasat uses the total number of episodes, like 121 in Simpsons.
    # This will not work either. But Viasat often have the real episodes
    # in description, paste it from there. Sorry about the long text.

		if( defined $ceref->{episode} ){
      my( $season, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      if( (defined $episode) and (defined $season) ){
        $episode += 1;
        $season += 1;

        my $series;
        if( defined( $ruleref->{remoteref} ) ) {
          my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref}, 0 );
          $series = $self->{tvdb}->getSeries( $seriesname, 0 );
        } else {
          $series = $self->{tvdb}->getSeries( $ceref->{title}, 0 );

          # Check against original title if the title cant be found.
          if(!(defined($series)) and (defined($ceref->{original_title}) and $ceref->{original_title} ne "")) {
          #  w("trying original title \"".$ceref->{original_title}."\" instead of \"".$ceref->{title}."\"");
            $series = $self->{tvdb}->getSeries( $ceref->{original_title}, 0 );
          }
        }
        
        if( (defined $series)){
        	# Use $ce->{original_title} with the real title if its provided by the data
        	if(!defined($ceref->{original_title})) {
        	    #$resultref->{title} = normUtf8( norm( $series->{SeriesName} ) );
        	}
        	
        	# Find season and episode
        	if(($season ne "") and ($episode ne "")) {
        		my $episode2 = $self->{tvdb}->getEpisode($series->{SeriesName}, $season, $episode, 0);

          	if( defined( $episode2 ) ) {
            	$self->FillHash( $resultref, $series, $episode2, $ceref );
          	} else {
            	w( "no episode " . $episode . " of season " . $season . " found for '" . $ceref->{title} . "'" );
          	}
          }
        }
      }
    }
  }elsif( $ruleref->{matchby} eq 'episodeseasontitle' ) {
    # Same as episodeseason except it also paste season from title
    # Used like:
  	# title: Jersey Shoe 2
  	# remoteref: 2
  	# ( much like Fixups setseason )
    
    # Check is remoteref is actually in there, or the whole shit will crash.
    if( defined( $ruleref->{remoteref} ) ) {

    	my( $season ) = $ruleref->{remoteref};
    	
		if( defined $ceref->{episode} ){
      	    my( $season_episode, $episode )=( $ceref->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
      	    if( (defined $episode) and (defined $season_episode) ){
        		$episode += 1;
        		$season_episode += 1;
        
        		my $seriesname = $ceref->{title};
        		
        		# Remove the season from title
        		$seriesname =~ s/$season//;
        		
        		# Norm it.
        		$seriesname = norm($seriesname);
        
                my $series = $self->{tvdb}->getSeries( $seriesname, 0 );
        
        		if( (defined $series)){
        			# Find season and episode
        			if(($season ne "") and ($episode ne "")) {
        				my $episode2 = $self->{tvdb}->getEpisode($series->{SeriesName}, $season, $episode, 0);

       	   			if( defined( $episode2 ) ) {
     	       			$self->FillHash( $resultref, $series, $episode2, $ceref );
          			} else {
            			w( "no episode " . $episode . " of season " . $season . " found for '" . $seriesname . "'" );
          			}
         	 	  }
        	  }
      	}
    	}
   	}
 }elsif( $ruleref->{matchby} eq 'episodetitle' ) {
    # match by episode title from program hash

    if( defined( $ceref->{subtitle} ) ) {
      my $series;
      if( defined( $ruleref->{remoteref} ) ) {
        my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref}, 0 );
        $series = $self->{tvdb}->getSeries( $seriesname, 0 );
      } else {
        $series = $self->{tvdb}->getSeries( $ceref->{title}, 0 );

        # Check against original title if the title cant be found.
        if(!(defined($series)) and (defined($ceref->{original_title}) and $ceref->{original_title} ne "")) {
        #    w("trying original title ".$ceref->{original_title}." instead of ".$ceref->{title});
            $series = $self->{tvdb}->getSeries( $ceref->{original_title}, 0 );
        }
      }
      if( defined $series ){
        #$resultref->{title} = normUtf8( norm( $series->{SeriesName} ) );
        
        my $episodetitle = $ceref->{subtitle};

        $episodetitle =~ s|\s+-\s+Teil\s+(\d+)$| ($1)|;   # _-_Teil_#
        $episodetitle =~ s|\s+\/\s+Teil\s+(\d+)$| ($1)|;  # _/_Teil_#
        $episodetitle =~ s|,\s+Teil\s+(\d+)$| ($1)|;      # ,_Teil #
        $episodetitle =~ s|\s+Teil\s+(\d+)$| ($1)|;       # _Teil #
        $episodetitle =~ s|\s+\(Teil\s+(\d+)\)$| ($1)|;   # _(Teil_#)
        $episodetitle =~ s|\s+-\s+(\d+)\.\s+Teil$| ($1)|; # _-_#._Teil

        $episodetitle =~ s|\s*\(Part\s+(\d+)\)$| ($1)|;   # _(Part_#) for Comedy Central Germany
        $episodetitle =~ s|\s+-\s+\((\d+)\)$| ($1)|;      # _-_(#) for Comedy Central Germany
        $episodetitle =~ s|\bPart\s+(\d+)$| ($1)|;        # ...Part_# for Comedy Central Germany

        $episodetitle =~ s|\s*-\s+part\s+(\d+)$| ($1)|;   # _(Part_#) for Al Jazeera International

        $episodetitle =~ s|\s+-\s+(\d+)$| ($1)|;          # _-_# for ORF

        # Discovery
        $episodetitle =~ s|\s+\s+| |;           # Two spaces to one space
        $episodetitle =~ s|\s+-\s+\(| \(|;      # " - (" to " ("
        $episodetitle =~ s|,\s+\(| \(|;         # ", (" to " ("
        $episodetitle =~ s|\:\s+\(| \(|;        # ": (" to " ("

        # " - - " to " - " for Eisenbahnromantik on SWR, maybe happens when shuffling title/subtitle around
        $episodetitle =~ s|\s+-\s+-\s+| - |;

        my $episode = $self->{tvdb}->getEpisodeByName( $series->{SeriesName}, $episodetitle );

        if( defined( $episode ) ) {
          $self->FillHash( $resultref, $series, $episode, $ceref );
        } else {
          if(!(defined($episode)) and (defined($ceref->{original_subtitle}) and $ceref->{original_subtitle} ne "")) {
            my $org_eptitle = $ceref->{original_subtitle};

            $org_eptitle =~ s|\s+-\s+Teil\s+(\d+)$| ($1)|;   # _-_Teil_#
            $org_eptitle =~ s|\s+\/\s+Teil\s+(\d+)$| ($1)|;  # _/_Teil_#
            $org_eptitle =~ s|,\s+Teil\s+(\d+)$| ($1)|;      # ,_Teil #
            $org_eptitle =~ s|\s+Teil\s+(\d+)$| ($1)|;       # _Teil #
            $org_eptitle =~ s|\s+\(Teil\s+(\d+)\)$| ($1)|;   # _(Teil_#)
            $org_eptitle =~ s|\s+-\s+(\d+)\.\s+Teil$| ($1)|; # _-_#._Teil

            $org_eptitle =~ s|\s*\(Part\s+(\d+)\)$| ($1)|;   # _(Part_#) for Comedy Central Germany
            $org_eptitle =~ s|\s+-\s+\((\d+)\)$| ($1)|;      # _-_(#) for Comedy Central Germany
            $org_eptitle =~ s|\bPart\s+(\d+)$| ($1)|;        # ...Part_# for Comedy Central Germany

            $org_eptitle =~ s|\s*-\s+part\s+(\d+)$| ($1)|;   # _(Part_#) for Al Jazeera International

            $org_eptitle =~ s|\s+-\s+(\d+)$| ($1)|;          # _-_# for ORF

            # " - - " to " - " for Eisenbahnromantik on SWR, maybe happens when shuffling title/subtitle around
            $org_eptitle =~ s|\s+-\s+-\s+| - |;

            my $episode_org = $self->{tvdb}->getEpisodeByName( $series->{SeriesName}, $org_eptitle );
            if( defined( $episode_org ) ) {
              $self->FillHash( $resultref, $series, $episode_org, $ceref );
            } else {
                w( "episode not found by title nor org subtitle: " . $ceref->{title} . " - \"" . $episodetitle . "\"" );
            }
          } else {
            w( "episode not found by title: " . $ceref->{title} . " - \"" . $episodetitle . "\"" );
          }
        }
      } else {
        d( "series not found by title: " . $ceref->{title} );
      }
    }

  }elsif( $ruleref->{matchby} eq 'seriesname' ) {
    # get seriesname and set it (to the right name)
    # works for channels which don't have season or episode
    # or doesn't have the right one.

      my $series;
      if( defined( $ruleref->{remoteref} ) ) {
        my $seriesname = $self->{tvdb}->getSeriesName( $ruleref->{remoteref}, 0 );
        $series = $self->{tvdb}->getSeries( $seriesname, 0 );
      } else {
        $series = $self->{tvdb}->getSeries( $ceref->{title}, 0 );
      }
      if( defined $series ){
        # Set title
        $ceref->{title} = normUtf8( norm( $series->{SeriesName} ) );
      } else {
        d( "series not found by title: " . $ceref->{title} );
      }

  }elsif( $ruleref->{matchby} eq 'episodeid' ) {
      # match by episode id from remote_ref (sid|eid)
      my $series;
      
      my( $sid, $eid ) = split( / /, $ruleref->{remoteref} );
      
      # Get title
      my $seriesname = $self->{tvdb}->getSeriesName( $sid, 0 );
      $series = $self->{tvdb}->getSeries( $seriesname, 0 );
      
      $resultref->{description} = "hej";
      
      # Do the fabulous things.
      if( defined $series ){
        $resultref->{title} = normUtf8( norm( $series->{SeriesName} ) );

        my $episode = $self->{tvdb}->getEpisodeId( $eid, 0 );
        if( defined( $episode ) ) {
          $self->FillHash( $resultref, $series, $episode, $ceref );
        } else {
          w( "episode not found by id: " . $ceref->{title} . " - \"" . $eid . "\"" );
        }
      } else {
        d( "series not found by title: " . $ceref->{title} );
      }

  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
  }

  if( !scalar keys %{$resultref} ){
    $resultref = undef;
  } else {
  }

  return( $resultref, $result );
}

1;
