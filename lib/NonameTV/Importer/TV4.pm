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


    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = $self->{UrlRoot} . '?todo=search&r1=XML'
    . '&firstdate=' . $date
    . '&lastdate=' . $date 
    . '&channel=' . $chd->{grabber_info};

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
  
  $dsh->StartDate( $date );
  
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
    
    my $prev_shown_date = $pgm->findvalue( 'previous_transmissiondate' );
    
    my $description = $ep_desc || $desc || $pr_desc;
    
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

    my $ns2 = $pgm->find( './/person' );
  
    foreach my $act ($ns2->get_nodelist)
    {
    	my $role = undef;
      my $name = norm( $act->findvalue('./real_name') );
      
      # Role played
      if( $act->findvalue('./role_played') ) {
      	$role = norm( $act->findvalue('./role_played') );
      }

      # Don't add if TV4 forgot the real name.
      if((defined $name) and ($name ne "")) {
		  if( (defined $role) and ( $role =~ /Regiss(.*)r/i  ) )
		  {
			push @directors, $name;
		  }
		  else
		  {
			push @actors, $name;
		  }
      }
    }

    if( scalar( @actors ) > 0 )
    {
      $ce->{actors} = join ", ", @actors;
    }

    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ", ", @directors;
    }

    $self->extract_extra_info( $ce );
    
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

  # Find production year from description.
  if( $pr_sentences[0] =~ /\bfr.n (\d\d\d\d)\b/ )
  {
    $ce->{production_date} = "$1-01-01";
  }
  elsif( $ep_sentences[0] =~ /\bfr.n (\d\d\d\d)\b/ )
  {
    $ce->{production_date} = "$1-01-01";
  }

  extract_episode( $ce );

  # Remove control characters {\b Text in bold}
  $ce->{description} =~ s/\{\\b\s+//g;
  $ce->{description} =~ s/\}//g;

  # Find aspect-info and remove it from description.
  if( $ce->{description} =~ s/(\bS.nds i )*\b16:9\s*-*\s*(format)*\.*\s*//i )
  {
    $ce->{aspect} = "16:9";
  }
  else
  {
    $ce->{aspect} = "4:3";
  }

  if( $ce->{description} =~ /16:9/ )
  {
    error( "TV4: Undetected 16:9: $ce->{description}" );
  }

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

#  if( defined($ce->{program_type}) and ($ce->{program_type} eq 'series') )
#  {
    my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
         if( defined( $st ) )
         {
      # This program is part of a series and it has a colon in the title.
      # Assume that the colon separates the title from the subtitle.
      $ce->{title} = $t;
      $ce->{subtitle} = $st;
    }
#  }
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

  # Try to extract episode-information from the description.
  my( $ep, $eps, $ep2, $eps2 );
  my $episode;

  # Del 2 av 3
  ( $ep, $eps ) = ($d =~ /\bDel\s+(\d+)\s*av\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;

	if(defined $episode and defined $eps) { 
		$ce->{description} =~ s/Del\s+(\d+)\s+av\s+(\d+).//; 
	}

  # Del 2
  ( $ep ) = ($d =~ /\bDel\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

	if(defined $episode and defined $ep) { 
		$ce->{description} =~ s/Del\s+(\d+).//; 
	}

  # Avsnitt 2 av 3
  ( $ep2, $eps2 ) = ($d =~ /Avsnitt\s*(\d+)\s*av\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep2-1, $eps2 ) 
    if defined $eps2;
    
  if(defined $episode and defined $eps2) { 
		$ce->{description} =~ s/Avsnitt\s+(\d+)\s+av\s+(\d+).//; 
	}
  
  # Avsnitt 2
  ( $ep2 ) = ($d =~ /Avsnitt\s*(\d+)/ );
  $episode = sprintf( " . %d .", $ep2-1 ) if defined $ep2;

	if(defined $episode and defined $ep2) { 
		$ce->{description} =~ s/Avsnitt\s+(\d+).//; 
	}
	
	# Avsnit 2
  ( $ep2 ) = ($d =~ /Avsnit\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep2-1 ) if defined $ep2;

	if(defined $episode and defined $ep2) { 
		$ce->{description} =~ s/Avsnit\s+(\d+).//; 
	}
  
  if( defined( $episode ) )
  {
    if( exists( $ce->{production_date} ) )
    {
      my( $year ) = ($ce->{production_date} =~ /(\d{4})-/ );
      $episode = ($year-1) . $episode;
    }
    $ce->{episode} = $episode;
    $ce->{program_type} = 'series';
  }
  
  if((defined $ce->{description}) and ($ce->{description} eq "")) {
  	$ce->{description} = $ce->{pr_desc};
  }
  
  # Get season from Roman numbers after the original title.
  if(defined($ce->{title_org}) and defined($ce->{episode})) {
  	my ( $original_title, $romanseason ) = ( $ce->{title_org} =~ /^(.*)\s+(.*)$/ );
  	
  	#my( $original_title, $romanseason ) = ($ce->{title_org} =~ /^(\s*) (\s*)$/i );
  	#print Dumper($ce->{title_org}, $original_title, $romanseason);
  	
  	# Roman season found
  	if(defined($romanseason) and isroman($romanseason)) {
  		my $romanseason_arabic = arabic($romanseason);
  		
  		# Episode
  		my( $romanepisode ) = ($ce->{episode} =~ /.\s+(\d*)\s+./ );
  		
  		#print Dumper($romanseason_arabic, $romanepisode);
  		
  		# Put it into episode field
  		if(defined($romanseason_arabic) and defined($romanepisode)) {
  			$ce->{episode} = sprintf( "%d . %d .", $romanseason_arabic-1, $romanepisode );
  		}
  	}
  }
  
  # remove original title
  delete $ce->{title_org};
  
}

1;
