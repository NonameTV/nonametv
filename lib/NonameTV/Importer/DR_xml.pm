package NonameTV::Importer::DR_xml;

use strict;
use warnings;
use utf8;
use Unicode::String;

=pod

Import data for DR in xml-format. 

=cut


use DateTime;
use XML::LibXML;
use Roman;

use NonameTV qw/ParseXml AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f p/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  if( defined( $self->{UrlRoot} ) ){
    w( 'UrlRoot is deprecated' );
  } else {
    $self->{UrlRoot} = 'http://www.dr.dk/Tjenester/epglive/epg.';
  }

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref eq '<!--error in request: -->' ) {
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
  my( $self, $cref, $chd ) = @_;

  $$cref =~ s|<message_id>.*</message_id>||;
  $$cref =~ s|<message_timestamp>.*</message_timestamp>||;

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

  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }
  
  foreach my $b ($ns->get_nodelist) {
  	# Start and so on
    my $start = ParseDateTime( $b->findvalue( "pro_publish[1]/ppu_start_timestamp_announced" ) );

    if( $start->ymd("-") ne $currdate ){
		p("Date is ".$start->ymd("-"));

		$dsh->StartDate( $start->ymd("-") , "00:00" );
		$currdate = $start->ymd("-");
	}

    my $title = $b->findvalue( "pro_title" );
    my $title_alt = $b->findvalue( "pro_publish[1]/ppu_title_alt" );
    my $subtitle = $b->findvalue( "pro_publish[1]/pro_punchline" );
    my $genretext = $b->findvalue( "pro_publish[1]/ppu_punchline" );
    my $year = $b->findvalue( "prd_prodyear" );
    my $country = $b->findvalue( "prd_prodcountry" );
    
    # Episode finder
    my $of_episode = undef;
    my $episode = undef;
    $episode = $b->findvalue( "prd_episode_number" );
    $of_episode = $b->findvalue( "prd_episode_total_number" );
    
    # Descr. and genre
    my $desc = $b->findvalue( "pro_publish[1]/ppu_description" );
    my $genre = $b->findvalue( "prd_genre_text" );

	# Cleanup
	$title =~ s/Fredagsfilm: //i;

	# Put everything in a array	
    my $ce = {
      channel_id => $chd->{id},
      start_time => $start->hms(":"),
      title => norm($title),
      description => norm($desc),
      subtitle	  => norm($subtitle),
    };

	  # Episode info in xmltv-format
      if( ($episode ne "") and ( $of_episode ne "") )
      {
        $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
      }
      elsif( $episode ne "" )
      {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }
    
    $ce->{aspect} = '4:3';
    
    my $widescreen =  $b->findvalue( 'pro_publish[1]/ppu_video' );
	if( $widescreen eq '16:9' ){
   	 	$ce->{aspect} = '16:9';
	}
	if( $widescreen eq 'HD' ){
   	 	$ce->{quality} = "HDTV";
	}
	
	my $live = $b->findvalue( 'pro_publish[1]/ppu_islive' );
	if( $live eq "TRUE" )
	{
		$ce->{live} = "1";
	}
	else
	{
		$ce->{live} = "0";
	}
	
	my $rerun = $b->findvalue( 'pro_publish[1]/ppu_isrerun' );
	if( $rerun eq "TRUE" )
	{
		$ce->{rerun} = "1";
	}
	else
	{
		$ce->{rerun} = "0";
	}
    
    $ce->{production_date} = "$year-01-01" if $year ne "";

    # Sometimes these production years differs through out the
    # schedules, use the punchline if years is found in it.
    if( $genretext =~ /\bfra (\d\d\d\d)\b/ )
    {
        $ce->{production_date} = "$1-01-01";
    }
    
    my($program_type, $category ) = $ds->LookupCat( 'DR', $genre );
	AddCategory( $ce, $program_type, $category );

	## Arrays
	my @actors;
    my @directors;

	## Split the text, add directors and more.
	my @sentences = (split_text( $ce->{description} ), "");
	for( my $i=0; $i<scalar(@sentences); $i++ )
    {
		if( my( $role, $name ) = ($sentences[$i] =~ /^(.*)\:\s+(.*)./) )
        {
        	# If name is longer than 15 skip. Probably a fucked up text.
        	if(length($name) > 15) {
        		#print("Longer than 15.\n");
        		next;
        	}

        	# Include the role
			my $name_new = norm( $name )." (".norm($role).")";

			if( $role =~ /Instruktion/i  ) {
				# This should ONLY happened on the Instruktion one.
				$name = parse_person_list($name);

				# Director
				push @directors, $name;

				# Not a series?
				if(!defined($ce->{episode})) {
					# If this program has an director, it should be
                	# a movie. If it isn't, please tag this DIRECTLY.
                	$ce->{program_type} = 'movie';

                	# Category removal
                	if(defined($ce->{category}) and $ce->{category} eq "Series") {
                    	$ce->{category} = undef;
                    }
				}

				# Use the original title if found
				$ce->{title} = norm($title_alt) if $title_alt;
				$ce->{original_title} = norm($title) if $title_alt; # Add original title
			} else {
				push @actors, $name_new;
			}

			$sentences[$i] = "";
        }

    }

	$ce->{description} = join_text( @sentences );

	# Season and this is a series now.
      if(defined($ce->{episode})) {
      	my ( $original_title, $romanseason ) = ( $ce->{title} =~ /^(.*)\s+(.*)$/ );

      	# Roman season found
      	if(defined($romanseason) and isroman($romanseason)) {
      		my $romanseason_arabic = arabic($romanseason);

      		$ce->{title} = norm($original_title);
      		$ce->{original_title} = norm($title) if $title_alt; # Add original title

      		# Series
      		$ce->{program_type} = "series";
      		if(defined($ce->{category}) and $ce->{category} eq "Movies") {
      			$ce->{category} = undef;
      		}

      		$ce->{episode} = $romanseason_arabic-1 . $ce->{episode};

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

    # DR fucks Family guy up and tags every episode as a movie, wtf?
    if($ce->{title} eq "Family Guy") {
    	$ce->{program_type} = "series";
    	if(defined($ce->{category})) {
        	$ce->{category} = undef;
        }
    }

	p($start." $ce->{title}");

    $dsh->AddProgramme( $ce );
  }

  return 1;
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) = 
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)$/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
      );

  return $dt;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;


  my( $date ) = ( $objectname =~ /(\d+-\d+-\d+)$/ );

  my $url = sprintf( "%s%s.drxml?dato=%s",
                     $self->{UrlRoot}, $chd->{grabber_info}, 
                     $date);


  return( $url, undef );
}

# Split a string into individual sentences.
sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
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
  }

  return join( ", ", grep( /\S/, @persons ) );
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
