package NonameTV::Importer::OppnaKanalen_Goteborg;

use strict;
use warnings;

=pod

Channels: ÖppnaKanalen i Göteborg (http://www.oppnakanalengoteborg.se/)

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Encode qw/decode/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "OKGoteborg: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "OKGoteborg: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//div[@style="  padding: 0.00mm 0.00mm 0.00mm 0.00mm; "]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//p" );
  
  if( $ns->size() == 0 ) {
    error( "OKGoteborg: $file: No ps found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) { # the line with the date in format 'Måndag 11 Juli'

      $date = ParseDate( $text );

      if( $date ) {

        progress("OKGoteborg: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
          	FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isTime( $text ) ) {
    	
    	my($time, $endtime) = ParseTime($text);
    
    	my $ce = {
        channel_id  => $chd->{id},
        start_time  => $time,
        end_time	  => $endtime,
        title			  => "",
        description => "",
      };
      
      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );
    
    } else {
        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        my @sentences = (split_text( $text ), "");
        
        
        for( my $i=0; $i<scalar(@sentences); $i++ )
  			{
  				# Set the title if title is empty (aka not set:ed)
  				if(defined($element) and $element->{title} eq "") {
  					$element->{title} .= $sentences[0];
  				}
  				
  				# Set the description if it's not the title
  				if(defined($element) and ($element->{description} eq "") and ($sentences[0] ne $element->{title})) {
  					$element->{description} .= $sentences[0];
  				}
  			}
  			
  			# If title is set:ed check if it has episode info in title
  			if(defined($element) and $element->{title} ne "") {
  				if( $element->{title} =~ /del\s*\d+\s+av\s+\d+$/i ) {
  					my ( $episode, $of_epi ) = ( $text =~ /del\s*(\d+)\s+av\s+(\d+)$/ );
  					$element->{episode} = sprintf( " . %d/%d . ", $episode-1, $of_epi ) if defined $episode;
  					# Remove it from title
  					$element->{title} =~ s/,\s+del\s+(\d+)\s+av\s+(\d+)$//; 
  				}
  			}
    }
  }
	# save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub isDate {
  my ( $text ) = @_;
  # format 'Måndag 11/8 2011'
  if( $text =~ /(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s*\d+\/\d+\s*\d+$/i ) {
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;
  

my ( $weekday, $day, $month, $year  ) = 
      ( $text =~ /(\S+?)\s*(\d+)\/(\d+)\s*(\d+)$/ );
      
  my $dt = DateTime->new(
  				year => $year,
    			month => $month,
    			day => $day,
      		);
  #return sprintf( '%d-%02d-%02d', $year, $month, $day );
  return $dt->ymd("-");
}

sub isTime {
  my ( $text ) = @_;

  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $text =~ /^(\d+[:\.]\d+)\s*\-\s*(\d+[:\.]\d+)$/i ){
    return 1;
  }

  return 0;
}

sub ParseTime {
  my( $text ) = @_;

  my( $time, $endtime );

	# The text is in the format: 18.50 - 19.30
  ( $time, $endtime ) = ( $text =~ /^(\d+[:\.]\d+)\s*\-\s*(\d+[:\.]\d+)$/ );

  my ( $hour , $min ) = ( $time =~ /^(\d+).(\d+)$/ );
  my ( $endhour , $endmin ) = ( $endtime =~ /^(\d+).(\d+)$/ );
  
  $time = sprintf( "%02d:%02d", $hour, $min );
  $endtime = sprintf( "%02d:%02d", $endhour, $endmin );

	#print("time: $time\n");

  return( $time, $endtime );
}


# From Kanal5_Util
sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./;

  # Replace newlines followed by a capital with space and make sure that there is a dot
  # to mark the end of the sentence. 
  $t =~ s/\.*\s*\n\s*([A-Z???])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # Split on a dot and whitespace followed by a capital letter,
  # but the capital letter is included in the output string and
  # is not removed by split. (?=X) is called a look-ahead.
#  my @sent = grep( /\S/, split( /\.\s+(?=[A-Z???])/, $t ) );

  # Mark sentences ending with a dot for splitting.
  $t =~ s/\.\s+([A-Z???])/;;$1/g;

  # Mark sentences ending with ! or ? for split, but preserve the "!?".
  $t =~ s/([\!\?])\s+([A-Z???])/$1;;$2/g;
  
  my @sent = grep( /\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    $sent[-1] =~ s/\.*\s*$//;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( ". ", grep( /\S/, @_ ) );
  $t .= "." if $t =~ /\S/;
  $t =~ s/::/../g;

  # The join above adds dots after sentences ending in ! or ?. Remove them.
  $t =~ s/([\!\?])\./$1/g;

  return $t;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("OKGoteborg: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

1;