package NonameTV::Importer::Svt_xml;

use strict;
use warnings;

=pod

Imports data for SVT-channels. Sent by SVT via MAIL in XML-Format

Every day is handled as a seperate batch,
The files get sent everyday for today + 5 weeks

Example for 2011-08-25:
2011-08-25 - 2011-09-18

Channels: SVT1, SVT1 (both cast in seperate HD channels aswell,
but the same schedule), SVTB, 24, SVTK (Kunskapskanalen).

Features opposite the Web importer:
Season ids, no "Från", widescreen, LIVE aswell.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;

use NonameTV qw/norm ParseXml AddCategory MonthNumber ParseDescCatSwe AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;
  
  # use augment
  #$self->{datastore}->{augment} = 1;

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

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "SvtXML: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "SvtXML: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( ".//se:SVTPublicScheduleEvent" );

    if( $rows->size() == 0 ) {
      error( "SvtXML: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  foreach my $row ($rows->get_nodelist) {

      my $time = $row->findvalue( './/se:StartTime/@startcet' );
      my $title = $row->findvalue( './/se:Title/@official' );
      my $date = $row->findvalue( './/se:Date/@startcet' );
      
	  if($date ne $currdate ) {
        if( $currdate ne "x" ) {
			$dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("SvtXML: Date is: $date");
      }

	  # extra info
	  my $season = $row->findvalue( './/se:TechnicalDetails/@seriesno' );
	  my $episode = $row->findvalue( './/se:TechnicalDetails/@episodeno' );
	  my $of_episode = $row->findvalue( './/se:TechnicalDetails/@episodecount' );
	  my $desc = norm( $row->findvalue( './/se:LongDescription/@description' ) );
	  my $year = $row->findvalue( './/se:TechnicalDetails/@productionyear' );
	  
	  my $start = $self->create_dt( $date."T".$time );
	  
	  # Genre description
	  my $genredesc = norm( $row->findvalue( './/se:ShortDescription/@description' ) );
	  


      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->ymd("-") . " " . $start->hms(":"),
      };
      
      if( defined( $year ) and ($year =~ /(\d\d\d\d)/) )
    	{
      		$ce->{production_date} = "$1-01-01";
    	}
      
      my ( $program_type, $category ) = ParseDescCatSwe( $genredesc );

  	  AddCategory( $ce, $program_type, $category );
      
      # Episode info in xmltv-format
      if( ($episode ne "0") and ( $of_episode ne "0") and ( $season ne "0") )
      {
        $ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $of_episode );
      }
      elsif( ($episode ne "0") and ( $of_episode ne "0") )
      {
        $ce->{episode} = sprintf( ". %d/%d .", $episode-1, $of_episode );
      }
      elsif( ($episode ne "0") and ( $season ne "0") )
      {
        $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      }
      elsif( $episode ne "0" )
      {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }
      
      # Remove if season = 0, episode 1, of_episode 1 - it's a one episode only programme
      if(($episode eq "1") and ( $of_episode eq "1") and ( $season eq "0")) {
      	$ce->{episode} = undef;
      }
      
      
      # Person
      my @sentences = (split_text( $desc ), "");
      
      for( my $i=0; $i<scalar(@sentences); $i++ )
  	  {
  	  	if( my( $directors ) = ($sentences[$i] =~ /^Regi:\s*(.*)/) )
    	{
      		$ce->{directors} = parse_person_list( $directors );
      		$sentences[$i] = "";
    	}
   		elsif( my( $actors ) = ($sentences[$i] =~ /^I rollerna:\s*(.*)/ ) )
    	{
      		$ce->{actors} = parse_person_list( $actors );
      		$sentences[$i] = "";
    	}
    	elsif( my( $actors2 ) = ($sentences[$i] =~ /^Övriga\s+medverkande:\s*(.*)/ ) )
    	{
      		$ce->{actors} = parse_person_list( $actors2 );
      		$sentences[$i] = "";
    	}
    	elsif( my( $commentators ) = ($sentences[$i] =~ /^Kommentator:\s*(.*)/ ) )
    	{
      		$ce->{commentators} = parse_person_list( $commentators );
      		$sentences[$i] = "";
    	}
     }
      
      $ce->{description} = join_text( @sentences );
      
      
     progress( "SvtXML: $chd->{xmltvid}: $time - $title" );
     $ds->AddProgramme( $ce );

    } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $date, $time ) = split( 'T', $str );

  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

# From SVT_WEB

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

1;
