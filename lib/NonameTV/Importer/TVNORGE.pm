package NonameTV::Importer::TVNORGE;

=pod

This importer works for both TVNorge, MAX and FEM.
It downloads per day xml files from respective channel's
pressweb. The files are in xml-style

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinDays} = 0 unless defined $self->{MinDays};
    $self->{MaxDays} = 25 unless defined $self->{MaxDays};

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Vienna" );
  	$self->{datastorehelper} = $dsh;
  	
  	$self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );

  my $url = $self->{UrlRoot} .
    $chd->{grabber_info} . '/' . $day . $month . $year;

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//program" );

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
  
  my( $date ) = ($batch_id =~ /_(.*)$/);
  

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
 	$dsh->StartDate( $date , "00:00" ); 
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }
  
  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }
  
  
  
  foreach my $sc ($ns->get_nodelist)
  {
  	
  	
  	
    my $title_original = $sc->findvalue( './originaltitle' );
	my $title_programme = $sc->findvalue( './title' );
	my $title = norm($title_programme) || norm($title_original);

	$title =~ s/^Premiere: //g;

    my $start = $sc->findvalue( './starttime' );
    my $end = $sc->findvalue( './endtime' );

    my $hd = $sc->findvalue( './hd' );
    
    my $desc = undef;
    my $desc_episode = $sc->findvalue( './shortdescription' );
	$desc = norm($desc_episode);
	
	my $genre = $sc->findvalue( './category' );
	my $production_year = $sc->findvalue( './productionyear' );
	my $episode =  $sc->findvalue( './episode' );
	my $numepisodes =  $sc->findvalue( './numepisodes' );

	# TVNorge seems to have the season in the originaltitle, weird.
	# �r 2
    my ( $dummy, $season ) = ($title_original =~ /(.r|sesong)\s*(\d+)$/ );


	progress("TVNorge: $chd->{xmltvid}: $start - $title");

    my $ce = {
      title 	  => norm($title),
      channel_id  => $chd->{id},
      description => norm($desc),
      start_time  => $self->create_dt( $start ),
      end_time    => $self->create_dt( $end ),
    };
    
    
    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    if( $genre ){
    	my($program_type, $category ) = $ds->LookupCat( 'TVNorge', $genre );
    	AddCategory( $ce, $program_type, $category );
    }

    # Director
    my $director = norm($sc->findvalue( './director' ));
    if(defined($director) and $director ne "") {
        $ce->{directors} = parse_person_list($director);
        $ce->{program_type} = 'movie';
    }

    # Hosts
    my $host = norm($sc->findvalue( './host' ));
    if(defined($host) and $host ne "") {
        $ce->{presenters} = parse_person_list($host);
    }

    # Actors
    my @actors;
    my $acts = $sc->find( './/actors' );
    foreach my $act ($acts->get_nodelist)
    {
        my $name = $act->to_literal;

        # Only push actors with an actual name
        if($name ne "") {
            push @actors, $name;
        }
    }

    if( scalar( @actors ) > 0 )
    {
        $ce->{actors} = join ";", @actors;
    }

	# Episodes
	if(($season) and ($episode) and ($numepisodes)) {
		$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode-1, $numepisodes );
	} elsif(($season) and ($episode) and (!$numepisodes)) {
		$ce->{episode} = sprintf( "%d . %d . ", $season-1, $episode-1 );
	} elsif((!$season) and ($episode) and ($numepisodes)) {
		$ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $numepisodes );
	} elsif((!$season) and ($episode) and (!$numepisodes)) {
		 $ce->{episode} = sprintf( " . %d . ", $episode-1 );
	}

	# HD
	if($hd eq "true")
	{
	    $ce->{quality} = 'HDTV';
	}

	# original title
    if(defined($title_original) and $title_original =~ /, (.r|sesong) (.*)/i) {
  	    $title_original =~ s/, (.r|sesong) (.*)//i;
  	}

  	$ce->{original_title} = norm($title_original) if defined($title_original) and $ce->{title} ne norm($title_original) and norm($title_original) ne "";


    $dsh->AddProgramme( $ce );
  }
  
  # Success
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

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+)$/ );


  
  return sprintf( "%02d:%02d", $hour, $minute );
}
    
1;
