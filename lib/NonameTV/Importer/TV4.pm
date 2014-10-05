package NonameTV::Importer::TV4;

=pod

This importer imports data from TV4's press service. The data is fetched
as one xml-file per day and channel.

Features:

Episode numbers parsed from description.

previously-shown-date info available but not currently used.

   <program>
      <transmissiontime>15:45</transmissiontime>
      <title>S�songsstart: Melrose Place </title>
      <description>Amerikansk dramaserie fr�n 1995 i 34 avsnitt.  Om en grupp unga 
m�nniskor som bor i ett hyreshus p� Melrose Place i Los Angeles. Fr�gan �r vem de kan 
lita p� bland sina grannar, f�r p� Melrose Place kan den man tror �r ens b�sta v�n 
visa sig vara ens v�rsta fiende.      Del 17 av 34.  Bobby f�r ett ultimatum av 
Peter. Kimberley ber�ttar f�r Alan om Matts tidigare k�rleksaff�rer vilket f�r Alan 
att ta avst�nd fr�n Matt. Billy har skuldk�nslor efter Brooks sj�lvmordsf�rs�k och 
kr�ver att Amanda tar henne tillbaka.</description>
      <episode_description> Del 17 av 34.  Bobby f�r ett ultimatum av Peter. 
Kimberley ber�ttar f�r Alan om Matts tidigare k�rleksaff�rer vilket f�r Alan att ta 
avst�nd fr�n Matt. Billy har skuldk�nslor efter Brooks sj�lvmordsf�rs�k och kr�ver 
att Amanda tar henne tillbaka.</episode_description>
<program_description>Amerikansk dramaserie fr�n 1995 i 34 avsnitt.  Om en grupp unga 
m�nniskor som bor i ett hyreshus p� Melrose Place i Los Angeles. Fr�gan �r vem de kan 
lita p� bland sina grannar, f�r p� Melrose Place kan den man tror �r ens b�sta v�n 
visa sig vara ens v�rsta fiende.     </program_description>
<creditlist>
  <person>
    <role_played>Michael Mancini</role_played>
    <real_name>Thomas Calabro</real_name>
  </person>
  <person>
    <role_played>Billy Campbell</role_played>
    <real_name>Andrew Shue</real_name>
  </person>
  <person>
    <role_played>Alison Parker</role_played>
   <real_name>Courtney Thorne-Smith</real_name>
  </person>
  <person>
    <role_played>Jake Hanson</role_played>
    <real_name>Grant Show</real_name>
  </person>
  <person>
    <role_played>Jane Mancini</role_played>
    <real_name>Josie Bissett</real_name>
  </person>
  <person>
    <role_played>Matt Fielding Jr</role_played>
    <real_name>Doug Savant</real_name>
  </person>
  <person>
    <role_played>Amanda Woodward</role_played>
    <real_name>Heather Locklear</real_name>
  </person>
</creditlist>
<next_transmissiondate>2005-01-11</next_transmissiondate>
</program>

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Roman;
use Data::Dumper;

use NonameTV qw/MyGet norm ParseDescCatSwe AddCategory FixProgrammeData/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $dsh->{DETECT_SEGMENTS} = 1;
    $self->{datastorehelper} = $dsh;

    # use augment
    $self->{datastore}->{augment} = 1;

    defined( $self->{ApiKey} ) or die "You must specify ApiKey";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = $self->{UrlRoot} . '?userId='.$self->{ApiKey}
    . '&startDate=' . $date
    . '&endDate=' . $date
    . '&channelId=pi' . $chd->{grabber_info}
    . '&format=xml&programText=LongestPossible';

  return( $url, undef );
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

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return 0;
  }
  
  # Find all "program"-entries.
  my $ns = $doc->find( "//program" );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }
  
  $dsh->StartDate( $date, "00:00" );
  
  foreach my $pgm ($ns->get_nodelist)
  {
    my $starttime = $pgm->findvalue( 'transmissiontime' );
    my $title =$pgm->findvalue( 'title' );
    my $title_org = $pgm->findvalue( 'originaltitle' );
    my $desc = $pgm->findvalue( 'description' );
    my $ep_desc = $pgm->findvalue( 'episode_description' );
    my $pr_desc = $pgm->findvalue( 'program_description' );
    my $live = $pgm->findvalue( 'live' );
    my $definition = $pgm->findvalue( 'definition' );
    my $season = $pgm->findvalue( 'season_number' );
    my $episode = $pgm->findvalue( 'episode_number' );
    my $eps = $pgm->findvalue( 'number_of_episodes' );
    my $prodyear = $pgm->findvalue( 'production_year' );
    
    my $prev_shown_date = $pgm->findvalue( 'previous_transmissiondate' );
    
    my $description = $ep_desc || $pr_desc || $desc;

    # Check if ep_desc includes data we don't want
    $description =~ s/Reprisstart\.//i;
    $description =~ s/S.songsavslutning\.//i;
    $description = $pr_desc || $desc if norm($description) eq "";
    
    if( ($title =~ /^[- ]*s.ndningsuppeh.ll[- ]*$/i) )
    {
      $title = "end-of-transmission";
    }
    
    my $ce = {
      title       	 => norm($title),
      title_org		 => norm($title_org),
      description    => norm($description),
      start_time  	 => $starttime,
      ep_desc     	 => norm($ep_desc),
      pr_desc     	 => norm($pr_desc),
    };
    
#     $ce->{prev_shown_date} = norm($prev_shown_date)
#     if( $prev_shown_date =~ /\S/ );

	# Find live-info
	  if( $live eq "true" )
	  {
	    $ce->{live} = "1";
	  }
	  else
	  {
	    $ce->{live} = "0";
	  }
	  
	# HDTV
	  if( $definition eq "HD" )
	  {
	    $ce->{quality} = "HDTV";
	  }

    my @actors;
    my @directors;
    my @producers;

    my $ns2 = $pgm->find( './/person' );

    foreach my $act ($ns2->get_nodelist)
    {
      my $role = undef;
      my $name = norm( $act->findvalue('./real_name') );
      my $type = norm( $act->findvalue('./type') );

      # Role played
      if( $act->findvalue('./role_played') ) {
      	$role = norm( $act->findvalue('./role_played') );

      	if($name ne "" and $role ne "" and $type !~ /Regiss(.*)r/i and $type !~ /Producent/i) {
      	    $name .= " (".$role.")";
      	}
      }

      # Don't add if TV4 forgot the real name.
      if((defined $name) and ($name ne "")) {
		  if( $type =~ /Regiss(.*)r/i )
		  {
			push @directors, $name;
		  }
		  elsif($type =~ /Producent/i)
		  {
            push @producers, $name;
		  }
		  else
		  {
			push @actors, $name;
		  }
      }
    }

    if( $prodyear =~ /(\d\d\d\d)/ )
    {
        $ce->{production_date} = "$1-01-01";
    }

    if( scalar( @actors ) > 0 )
    {
      $ce->{actors} = join ";", @actors;
    }

    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ";", @directors;
    }

    if( scalar( @producers ) > 0 )
    {
      $ce->{producers} = join ";", @producers;
    }

    if($episode) {
      if($season) {
      	if($eps and $eps ne "") {
      		$ce->{episode} = sprintf( "%d . %d/%d . ", $season-1, $episode-1, $eps );
      	} else {
      		$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      	}
      }elsif($eps and $eps ne "") {
      	$ce->{episode} = sprintf( " . %d/%d . ", $episode-1, $eps );
      } else {
      #	$ce->{episode} = sprintf( " . %d . ", $episode-1 ); # TV4 puts movies as episode 1
      }
    }

    $self->extract_extra_info( $ce );

    # only movies got directors
    if( scalar( @directors ) > 0 and !defined($ce->{episode}) and scalar( @actors ) > 0 )
    {
        $ce->{program_type} = "movie";
    } elsif($ce->{title} =~ /^(Handboll|Fotboll|Hockey|Ishockey|Innebandy|Simning)\:/i or $ce->{title} =~ /^(Handboll|Fotboll|Hockey|Ishockey|Innebandy|Simning|UFC)$/i)
    {
        $ce->{program_type} = "sports";
    }

    $ce->{title} =~ s/\:$//;

    progress($date." ".$starttime." - ".$ce->{title});
    
    $dsh->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = @_;

  #
  # Try to extract category and program_type by matching strings
  # in the description.
  #
  my @pr_sentences = split_text( $ce->{pr_desc} );
  my @ep_sentences = split_text( $ce->{ep_desc} );
  
  my( $program_type, $category ) = ParseDescCatSwe( $pr_sentences[0] );
  AddCategory( $ce, $program_type, $category );
  ( $program_type, $category ) = ParseDescCatSwe( $ep_sentences[0] );
  AddCategory( $ce, $program_type, $category );

  extract_episode( $ce );

  # Remove control characters {\b Text in bold}
  $ce->{description} =~ s/\{\\b\s+//g;
  $ce->{description} =~ s/\}//g;

  # Remove temporary fields
  delete $ce->{pr_desc};
  delete $ce->{ep_desc};

  if( $ce->{title} =~ /^Pokemon\s+(\d+)\s*$/ )
  {
    $ce->{title} = "Pok�mon";
    $ce->{subtitle} = $1;
  }

  # Must remove "Reprisstart: " and similar strings before the next check.
  FixProgrammeData( $ce );
}

# Split a string into individual sentences.
sub split_text
{
  my( $t ) = @_;

  return $t if $t !~ /\./;

  $t =~ s/\n/ . /g;
  $t =~ s/\.\.\./..../;
  my @sent = grep( /\S/, split( /\.\s+/, $t ) );
  map { s/\s+$// } @sent;
  $sent[-1] =~ s/\.\s*$//;
  return @sent;
}

sub extract_episode
{
  my( $ce ) = @_;

  return if not defined( $ce->{description} );

  my $d = $ce->{description};


  
  if((defined $ce->{description}) and ($ce->{description} eq "")) {
  	$ce->{description} = $ce->{pr_desc};
  }

  # Get season from Roman numbers after the original title.
  if(defined($ce->{title_org}) and defined($ce->{episode})) {
    # Remove , The at the end and add it at start
    if($ce->{title_org} =~ /, The$/i) {
        $ce->{title_org} =~ s/, The$//i;
        $ce->{title_org} = norm("The ".$ce->{title_org});
    }

    # Remove , A at the end and add it at start
    if($ce->{title_org} =~ /, A$/i) {
        $ce->{title_org} =~ s/, A$//i;
        $ce->{title_org} = norm("A ".$ce->{title_org});
    }

  	my ( $original_title, $romanseason ) = ( $ce->{title_org} =~ /^(.*)\s+(.*)$/ );

  	# Roman season found
  	if(defined($romanseason) and isroman(norm($romanseason))) {
  		my $romanseason_arabic = arabic($romanseason);

  		# Fix original title
  		$ce->{title_org} =~ s/$romanseason//;
  		
  		# Episode
  		my( $season2, $episode2 )=( $ce->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)| );
  		( $episode2 )=( $ce->{episode} =~ m|\.\s*(\d+)\s*/?\s*\d*\s*\.\s*$| );
  		
  		# Put it into episode field
  		if(defined($romanseason_arabic) and not defined($season2) and defined($episode2)) {
  			$ce->{episode} = sprintf( "%d . %d .", $romanseason_arabic-1, $episode2 );
  		}
  	}
  }

  if( defined( $ce->{episode} ) )
  {
    my( $year );
    if( exists( $ce->{production_date} ) )
    {
      ( $year ) = ($ce->{production_date} =~ /(\d{4})-/ );
    }

    my( $season, $episode )=( $ce->{episode} =~ m|^\s*(\d+)\s*\.\s*(\d+)| );

    if(not defined($season) and exists( $ce->{production_date} )) {
        $ce->{episode} = ($year-1) . $ce->{episode};
        $ce->{program_type} = 'series';
    }
  }

  $ce->{original_title} = norm($ce->{title_org}) if lc($ce->{title}) ne lc(norm($ce->{title_org})) and norm($ce->{title_org}) ne "";

  # Replace The in the original title.
  if(defined($ce->{original_title})) {
    # Remove , The at the end and add it at start
    if($ce->{original_title} =~ /, The/i) {
        $ce->{original_title} =~ s/, The//i;
        $ce->{original_title} = norm("The ".$ce->{original_title});
    }

    # Remove , A at the end and add it at start
    if($ce->{original_title} =~ /, A$/i) {
        $ce->{original_title} =~ s/, A$//i;
        $ce->{original_title} = norm("A ".$ce->{original_title});
    }

    # Remove , at the end if it bugs out
    $ce->{original_title} =~ s/,$//;
    $ce->{original_title} =~ s/(\d\d\d\d)$//;

    # Norm
    $ce->{original_title} = norm($ce->{original_title});

    $ce->{original_title} = undef if $ce->{original_title} eq $ce->{title};
  }

  # remove original title
  delete $ce->{title_org};
  
}

1;
