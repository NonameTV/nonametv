package NonameTV::Importer::Svt_web;

=pod

This importer imports data from SvT's press site. The data is fetched
as one html-file per day and channel.

Features:

Episode-info parsed from description.

=cut

use strict;
use warnings;
use utf8;

use DateTime;
use XML::LibXML;
use DateTime;
use String::Util 'trim';

use NonameTV qw/MyGet normLatin1 Html2Xml ParseXml ParseDescCatSwe AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

my %channelids = ( "SVT1" => "svt1.svt.se",
                   "SVT2" => "svt2.svt.se",
                   );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub InitiateDownload {
  my $self = shift;

  # Login
  my $username = $self->{Username};
  my $password = $self->{Password};

  my $url = "http://www.pressinfo.svt.se/app/index.asp?"
    . "SysLoginName=$username"
    . "\&SysPassword=$password";

  # Do the login. This will set a cookie that will be transferred on all
  # subsequent page-requests.
  my( $dataref, $error ) = $self->{cc}->GetUrl( $url );
  
  return $error;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # http://www.pressinfo.svt.se/app/schedule_full.html.dl?kanal=SVT%201&Sched_day_from=0&Sched_day_to=0&Det=Det&Genre=&Freetext=
  # Day=0 today, Day=1 tomorrow etc. Day can be negative.
  # kanal SVT 1, SVT 2, SVT Europa, Barnkanalen, 24, Kunskapskanalen


  my( $date ) = ($objectname =~ /_(.*)/);

  my( $year, $month, $day ) = split( '-', $date );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day 
                          );

  my $today = DateTime->today( time_zone=>'local' );
  my $day_diff = $dt->subtract_datetime( $today )->delta_days;

  my $u = URI->new('http://www.pressinfo.svt.se/app/schedule_full.html.dl');
  $u->query_form( {
    kanal => $chd->{grabber_info},
    Sched_day_from => $day_diff,
    Sched_day_to => $day_diff,
    Det => "Det",
    Genre => "",
    Freetext => ""});

  return( $u->as_string(), undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  my $ns = $doc->find( "//@*" );

  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    if( $attr->nodeName() ne "class" ) {
      $attr->unbindNode();
    }
  }

  # The data contains a header with text that is changed each day.
  # E.g. "Tabl� f�r i g�r Torsdag 27 mars 2008".
  # Replace it with "Torsdag 27 mars 2008".
  $ns = $doc->find( '//font[@class="header"]' );
  if( $ns->size() != 1 ) {
    return (undef, "Expected to find exactly one heading.");
  }

  foreach my $node ($ns->get_nodelist) {
    my $text = $node->textContent();
    $text =~ s/Tabl.*([MTOFLS])/$1/;

    $node->removeChildNodes();
    $node->addChild( XML::LibXML::Text->new( $text ) );
  }

  my $str = $doc->toString(1);

  return( \$str, undef );
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'html';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
#  $ds->{SILENCE_END_START_OVERLAP}=1;
  my $dsh = $self->{datastorehelper};
  $self->{currxmltvid} = $chd->{xmltvid};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  {
    my( $year, $month, $day ) = split("-", $date);
    $self->{currdate} = DateTime->new( year => $year,
                                       month => $month, 
                                       day => $day );
  }

  my $doc = ParseXml( $cref );
  
  if( not defined( $doc ) )
  {
    error( "$batch_id: Failed to parse." );
    return 0;
  }

  # Check that we have downloaded data for the correct day.
  my $daytext = $doc->findvalue( '//font[@class="header"]' );
  my( $day ) = ($daytext =~ /\b(\d{1,2})\D+(\d{4})\b/);

  if( not defined( $day ) )
  {
    error( "$batch_id: Failed to find date in page ($daytext)" );
    return 0;
  }

  my( $dateday ) = ($date =~ /(\d\d)$/);

  if( $day != $dateday )
  {
    error( "$batch_id: Wrong day: $daytext" );
    return 0;
  }
        
  # The data really looks like this...
  my $ns = $doc->find( "//table/td/table/tr/td/table/tr" );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  $dsh->StartDate( $date, "03:00" );
  
  my $skipfirst = 1;
  my $programs = 0;

  foreach my $pgm ($ns->get_nodelist)
  {
    if( $skipfirst )
    {
      $skipfirst = 0;
      next;
    }
    
    my $time  = $pgm->findvalue( 'td[1]//text()' );
    my $title = $pgm->findvalue( 'td[2]//font[@class="text"]//text()' );
    my $desc  = $pgm->findvalue( 'td[2]//font[@class="textshorttabla"]//text()' );
    
    
    # If schedule not yet published, do a next;
    if($desc eq "Tabl�n �nnu ej publicerad") {
    	next;
    }

    # SVt can have titles that include program block information.
    # Ideally we should use the fact that they are separated by <br>
    # but I cannot make that work.
    $title =~ s/.*\d+:\d+\s*-\s*\d+:\d+://;

    my( $starttime ) = ( $time =~ /^\s*(\d+\.\d+)/ );
    my( $endtime ) = ( $time =~ /-\s*(\d+.\d+)/ );
    
    $starttime =~ tr/\./:/ if $starttime;
    if((not defined $starttime) or ( $starttime !~ /\d+:\d+/ ))
    {
      next;
    }
    
    my $title_fixed = trim(norm_title($title));
    
    my $ce =  {
      start_time  => $starttime,
      title       => $title_fixed,
      description => norm_desc($desc),
    };
    
    #print("Title: '$title_fixed'\n");
    
    if( defined( $endtime ) )
    {
      $endtime =~ tr/\./:/;
      $ce->{end_time} = $endtime;
    }
    
    $self->extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
    $programs++;
  }
  
  if( $programs > 0 )
  {
    # Success
    return 1;
  }
  else
  {
    # This is normal for some channels. We do not want to rollback
    # because of this.
    error( "$batch_id: No programs found" )
      if( not $chd->{empty_ok} );
    return 1;
  }
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = shift;

  my( $ds ) = $self->{datastore};

  my( $program_type, $category, $season );
  
  $season = "";

  #
  # Try to extract category and program_type by matching strings
  # in the description. The empty entry is to make sure that there
  # is always at least one entry in @sentences.
  #

  my @sentences = (split_text( $ce->{description} ), "");
  
  ( $program_type, $category ) = ParseDescCatSwe( $sentences[0] );

  # If this is a movie we already know it from the svt_cat.
  if( defined($program_type) and ($program_type eq "movie") )
  {
    $program_type = undef; 
  }

  $ce->{title} =~ s/^Seriestart:\s*//;
  $ce->{title} =~ s/^Novellfilm:\s*//;
  $ce->{title} =~ s/^Filmklubben\s+Norden:\s*//;

  # Default aspect is 4:3.
  #$ce->{aspect} = "4:3";

  for( my $i=0; $i<scalar(@sentences); $i++ )
  {
    # Find production year from description.
    if( ($sentences[$i] =~ /film fr.n (\d\d\d\d)\b/i) or
	($sentences[$i] =~ /serie fr.n (\d\d\d\d)\b/i) or
	($sentences[$i] =~ /^fr.n (\d\d\d\d)\.*$/i) )
    {
      $ce->{production_date} = "$1-01-01";
      $sentences[$i] = "";
    }

    if( $sentences[$i] eq "Bredbild." )
    {
      $ce->{aspect} = "16:9";
      $sentences[$i] = "";
    }
    elsif( my( $seasontext ) = ($sentences[$i] =~ /^(.*) säsongen./ ) )
    {
      $seasontext =~ s/ och sista//g;
      $seasontext = lc($seasontext);
      
      $season = SeasonText($seasontext);
      
      #print("Text: $seasontext - Num: $season\n");
      
      # Only remove sentence if it could find a season
      if($season ne "") {
      	$sentences[$i] = "";
      }
    }
    elsif( $sentences[$i] eq "4:3-format." )
    {
   	  print("HEJ\n");
      $ce->{aspect} = "4:3";
      $sentences[$i] = "";
    }
    elsif( $sentences[$i] =~ /^(Även|Från)
     ((
      \s+|
      [A-Z]\S+|
      i\s+[A-Z]\S+|
      tidigare\s+i\s*dag|senare\s+i\s*dag|
      tidigare\s+i\s*kväll|senare\s+i\s*kväll|
      \d+\/\d+|
      ,|och|samt
     ))+
     \..*
     $/x )
    {
       $sentences[$i] = "";
#      $self->parse_other_showings( $ce, $sentences[$i] );
    }
    elsif( $sentences[$i] =~ /Text(at|-tv)\s+(sid|sid.|sidan)*\s+\d+\./ )
    {
#      $ce->{subtitle} = 'sv,teletext';
      $sentences[$i] = "";
    }
    elsif( $sentences[$i] eq "Visas i SVT Play." )
    {
      $sentences[$i] = "";
    }
    elsif( $sentences[$i] eq "5.1-ljud." )
    {
      $sentences[$i] = "";
    }
    elsif( $sentences[$i] eq "HD." )
    {
      $ce->{quality} = "HDTV";
    
      # Set somethiing?
      $sentences[$i] = "";
    }
    elsif( $sentences[$i] =~ /Del\s+\d+\.*/ )
    {
      # If this program has an episode-number, it is by definition
	  # a series (?). Svt often miscategorize series as movie.
	  $ce->{program_type} = 'series';
	  
      my( $ep, $eps, $name, $episode, $dummy );
      # Del 2 av 3: Pilot (episodename)
 	  ( $ce->{subtitle} ) = ($sentences[$i] =~ /:\s*(.+)\./);
 	  
 	  # norm
 	  $ce->{subtitle} = normLatin1($ce->{subtitle});
 	  
 	  # Del 2
	  ( $dummy, $ep ) = ($sentences[$i] =~ /\b(Del|Avsnitt)\s+(\d+)/ );
	  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;
	
	
	
	  # Del 2 av 3
	  ( $dummy, $ep, $eps ) = ($sentences[$i] =~ /\b(Del|Avsnitt)\s+(\d+)\s*av\s*(\d+)/ );
	  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
	    if defined $eps;
	  
	  if( defined $episode ) {
	    if( exists( $ce->{production_date} ) and $season eq "" ) {
	      my( $year ) = ($ce->{production_date} =~ /(\d{4})-/ );
	      $episode = ($year-1) . $episode;
	    } elsif($season ne "") {
	    	$episode = $season-1 . $episode;
	    }
	    $ce->{episode} = $episode;
	  }
 	  
 	  $sentences[$i] = "";
 	}
    elsif( my( $directors4 ) = ($sentences[$i] =~ /^Regi\s+och\s+manus:\s*(.*)/) )
    {
      # If this program has an director, it should be
	  # a movie. If it isn't, please tag this DIRECTLY.
	  $ce->{program_type} = 'movie';
    
      $ce->{directors} = parse_person_list( $directors4 );
      $sentences[$i] = "";
    }
    elsif( my( $directors ) = ($sentences[$i] =~ /^Regi:\s*(.*)/) )
    {
      # If this program has an director, it should be
	  # a movie. If it isn't, please tag this DIRECTLY.
	  $ce->{program_type} = 'movie';
    
      $ce->{directors} = parse_person_list( $directors );
      $sentences[$i] = "";
    }
    elsif( my( $directors2 ) = ($sentences[$i] =~ /^I\s+regi\s+av\s+(.*)/) )
    {
      # If this program has an director, it should be
	  # a movie. If it isn't, please tag this DIRECTLY.
	  $ce->{program_type} = 'movie';
	  
      $ce->{directors} = parse_person_list( $directors2 );
      $sentences[$i] = "";
    }
    elsif( my( $actors ) = ($sentences[$i] =~ /^I rollerna:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors );
      $sentences[$i] = "";
    }elsif( my( $actors2 ) = ($sentences[$i] =~ /^Medverkande:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors2 );
      $sentences[$i] = "";
    }elsif( $sentences[$i] =~ /l.ngfilm/ ) {
        $ce->{program_type} = "movie";
    }
  }
  
  # Parse the desc if it doesnt have a program_type
  if(!defined($ce->{program_type})) {
  	AddCategory( $ce, $program_type, $category );
  } elsif(defined($ce->{program_type}) and $ce->{program_type} ne "movie") {
  	AddCategory( $ce, $program_type, $category );
  }
  
  $ce->{description} = join_text( @sentences );

  #extract_episode( $ce );
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  
  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

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

sub parse_other_showings
{
  my $self = shift;
  my( $ce, $l ) = @_;

  my $type;
  my $channel = "same";
  my $date = "unknown";

 PARSER: 
  {
    if( $l =~ /\G(�ven|Fr�n)\s*/gcx ) 
    {
      $type = ($1 eq "�ven") ? "also" : "previously";
      
      redo PARSER;
    }
    if( $l =~ /\Gi*\s* ([A-Z]\w*) \s*/gcx ) 
    {
      $channel = $1;
      redo PARSER;
    }
    if( $l=~ /\G(tidigare\s+i\s*dag
                 |senare\s+i\s*dag
                 |tidigare\s+i\s*kv�ll
                 |senare\s+i\s*kv�ll)\s*/gcx )  
    {
      $date = "today";
      redo PARSER;
    }
    if( $l =~ /\G(\d+\/\d+)\s*/gcx )
    {
      $date = $1;
      redo PARSER;
    }
    if( $l =~ /\G(,|och|samt)\s*/gcx ) 
    {
      $self->add_showing( $ce, $type, $date, $channel );
      $date = "unknown";
      $channel = "same";
      redo PARSER;
    }
    if( $l =~ /\G(\.)\s*/gcx ) 
    {
      $self->add_showing( $ce, $type, $date, $channel );
      $date = "unknown";
      $channel = "same";
      redo PARSER;
    }
    if( $l =~ /\G(.+)/gcx ) 
    {
      print "error: $1\n";
      redo PARSER;
    }
    
  }
}
    
sub add_showing
{
  my $self = shift;
  my( $ce, $type, $date, $channel ) = @_;

  my $chid;

  # Ignore entries caused by ", och"
  return if $date eq "unknown" and $channel eq "same";

  if( $channel eq "same" )
  {
    $chid = $self->{currxmltvid};
  }
  else
  {
    $chid = $channelids{$channel};
  }

  my $dt = DateTime->today();
  
  if( $date ne "today" )
  {
    my( $day, $month ) = ($date =~ /(\d+)\s*\/\s*(\d+)/);
    if( not defined( $month ) )
    {
#      error( "Unknown date $date" );
      return;
    }
    $dt->set( month => $month,
              day => $day );

    if( $dt > $self->{currdate} )
    {
      if( $type eq "previously" )
      {
        $dt->subtract( years => 1 );
      }
    }
    else
    {
      if( $type eq "also" )
      {
        $dt->add( years => 1 );
      }
    }
  }

  $date = $dt->ymd("-");

#  error( "Unknown channel $channel" )
#    unless defined $chid;

#  print STDERR "$type $date $chid\n";
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

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm() 
  # Replace newlines followed by a capital with space and make sure that there 
  # is a dot to mark the end of the sentence. 
#  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

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

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

sub norm_desc
{
  my( $str ) = @_;

  # Replace strange bullets with end-of-sentence.
  $str =~ s/([\.!?])\s*\x{95}\s*/$1 /g;
  $str =~ s/\s*\x{95}\s*/. /g;

  return normLatin1( $str );
}

sub norm_title
{
  my( $str ) = @_;

  # Remove strange bullets.
  $str =~ s/\x{95}/ /g;
  
  # Remove premiere and nightmovie and stuff like that
  $str =~ s/Premiär://g;
  $str =~ s/Nattfilm://g;
  $str =~ s/Filmklubben://g;

  return normLatin1( $str );
}

sub SeasonText {
  my( $seasonname ) = @_;

  my( @seasons_1, @seasons_2 );
  @seasons_1 = qw/första andra tredje fjärde femte sjätte/;
  @seasons_2 = qw//;

  my %seasons = ();

  for( my $i = 0; $i < scalar(@seasons_1); $i++ ){
    $seasons{$seasons_1[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@seasons_2); $i++ ){
    $seasons{$seasons_2[$i]} = $i+1;
  }

  my $season = $seasons{$seasonname};
  my $null = "";

  return $season||$null;
}

1;
