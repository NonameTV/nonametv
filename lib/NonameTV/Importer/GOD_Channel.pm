package NonameTV::Importer::GOD_Channel;

use strict;
use warnings;

=pod

Channels: GOD Channel/GOD TV (http://www.god.tv/)

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
  #$dsh->{DETECT_SEGMENTS} = 1;
  $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;
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

  progress( "GODTV: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "GODTV: $file: Failed to parse" );
    return;
  }

  #my @nodes = $doc->findnodes( '//table/text()' );
  #foreach my $node (@nodes) {
  #  my $str = $node->getData();
  #  $node->setData( uc( $str ) );
  #}
  
  # Find all paragraphs.
  my $ns = $doc->find( "//p" );
  
  if( $ns->size() == 0 ) {
    error( "GODTV: $file: No p:s found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;
  my $year;
  
  # Get year from filename
  $year = ParseYear( $file );
  progress("GODTV: Year is $year");

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    
    if( isDate( $text ) ) { # the line with the date in format 'Thursday 5th January'

      $date = ParseDate( $text, $year );

      if( $date ) {

        progress("GODTV: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            # save last day if we have it in memory
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
      
      # Empty text
      #undef $text;

    } elsif( isTime( $text ) ) {
        # Time is in this format: 7,00 (note the comma)
        my $time = ParseTime($text);
        my $ce = {
            channel_id => $chd->{id},
            start_time => $time,
        };
        push( @ces , $ce );
        
        # Empty text
        #undef $text;
    } elsif( isShow( $text ) ) {
      # Showname and description is like this: "The Book of Colossians - Chuck Missler"
      # I think its SHOWNAME - ACTOR (but put actor in subtitle as it seems LIVE is actor sometimes)
      my( $title, $subtitle ) = ParseShow( $text );
      next if( ! $title );

      # the last element is the one to which
      # this show belongs to
      my $element = $ces[$#ces];
      
      
      
      # End of schedule
      if ( ($title eq "slut") or
       ($title eq "godnatt") or
       ($title eq "end") or
       ($title eq "close") or
       ($title eq "pause") or
       ($title eq "END OF SCHEDULE") )               
  {
    $element->{title} = "end-of-transmission";
  } else {
      $element->{title} = norm($title);
      $element->{subtitle} = norm($subtitle);
  }

      
      
      # Empty text
      #undef $text;
    } else {
        # skip
        next;
    }
  }

    # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}


sub isTime {
  my ( $text ) = @_;

    #print("text:  $text\n");

  # format '7,00'
  if( $text =~ /^\d+\,\d+$/i ){ 
    return 1;
  }

  return 0;
}

sub ParseTime {
  my( $time ) = @_;
#print("text2:  $time\n");
  my( $hour, $min, $dummy );
  
  if( $time =~ /^\d+\,\d+$/i ){ 
    ($hour, $min) = split(/,/, $time);
    #$dummy = join(':', split(/,/, $time)), "\n";
    
    $hour = $hour-1;

  }
  
  # Set hour to 00 if hour = 24
    if($hour eq "24") {
        $hour = "0";
    } elsif($hour eq "25") {
        $hour = "1";
    }

   #print("hour: $hour, min: $min\n");

  return sprintf( '%02d:%02d', $hour, $min );
  #return $dummy;
}

sub isDate {
  my ( $text ) = @_;

	if($text =~ /-/i){
    	return 0;
  	}

    #print("text:  $text\n");

  # format 'Monday 12th September'
  if( $text =~ /(.*)\s+\d+(st|nd|rd|th)\s*(january|february|march|april|may|june|july|august|september|october|november|december)/i ){ 
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text, $year ) = @_;
  my( $dayname, $dummy, $day, $monthname, $month );
    # format 'Måndag 11 Juli'
  if( $text =~ /(.*)\s+\d+(st|nd|rd|th)\s*(january|february|march|april|may|june|july|august|september|october|november|december)/i ){ 
    ( $dayname, $day, $dummy, $monthname ) = ( $text =~ /^(\S+)\s+(\d+)(st|rd|nd|th)\s+(\S+)$/i );

    $month = MonthNumber( $monthname, 'en' );
  }

    #print("day: $day, month: $month, year: $year\n");

  my $dt = DateTime->new(
                year => $year,
                month => $month,
                day => $day,
            );

  #return sprintf( '%d-%02d-%02d', $year, $month, $day );
  return $dt->ymd("-");
}

sub isShow {
  my ( $text ) = @_;

  if( $text =~ /\s*/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $title ) = @_;

  my( $subtitle );

  if( $title =~ /\s+-\s+(.*)$/ ){
    ( $subtitle ) = ( $title =~ /\s+-\s+(.*)$/ );
    $title =~ s/\s+-\s+(.*)$//;
  } else {
      $subtitle = "";
  }

  return( $title, $subtitle );
}

sub isYear {
  my ( $text ) = @_;

  # format 'January 2012*'
  if( $text =~ /(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+\s*/i ){
    return 1;
  }

  return 0;
}

sub ParseYear {
  my( $text ) = @_;
  my( $year, $dummy );

  # format 'Måndag 11 06'
  if( $text =~ /(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+\s+/i ){ # format 'Måndag 11 Juli'
    ( $dummy, $year ) = ( $text =~ /(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d+)\s+(\S+)/i );
  }
  return $year;
}


sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("GODTV: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
