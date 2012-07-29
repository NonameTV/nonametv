package NonameTV::Importer::Kanal10;

use strict;
use warnings;

=pod

Channels: Kanal10 (http://kanal10.se/)

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

  progress( "Kanal10: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Kanal10 $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//p" );
  
  if( $ns->size() == 0 ) {
    error( "Kanal10 $xmltvid: $file: No ps found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;
  my $year;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );
    
    # Get year from Program.versikt :year:
    if( isYear( $text ) ) { # the line with the date in format 'Programöversikt 2011'
        $year = ParseYear( $text );
        progress("Kanal10: Year is $year");
    }
    

    if( isDate( $text ) ) { # the line with the date in format 'Måndag 11 Juli'

      $date = ParseDate( $text, $year );

      if( $date ) {

        progress("Kanal10: Date is $date");

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

    } elsif( isShow( $text ) ) {

      my( $time, $title, $desc ) = ParseShow( $text );
      next if( ! $time );
      next if( ! $title );

      #$title = decode( "iso-8859-2" , $title );


      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
      };

      	
        
        my $d = norm($desc);
        if((not defined $d) or ($d eq "")) {
        	$d = norm($title);
        }
       
      # Episode
      if($d) {
      		my ($ep, $eps);
      		
          	# Del 2
  			( $ep ) = ($d =~ /\bdel\s+(\d+)/ );
  			$ce->{episode} = sprintf( " . %d .", $ep-1 ) if defined $ep;

  			# Del 2 av 3
  			( $ep, $eps ) = ($d =~ /\bdel\s+(\d+)\((\d+)\)/ );
  			$ce->{episode} = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    		if defined $eps;
    		
    		
      }

	  # Just in case
	  $ce->{title} = norm($title);

	  # Remove repris (use this in the future?)
      $title =~ s/\(Repris(.*)\)$//;
      
      # Set title
      $ce->{title} = norm($title);
      $ce->{description} = norm($desc) if $desc;

			push( @ces , $ce );

    } else {
        # skip
    }
  }

	# save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub isDate {
  my ( $text ) = @_;

    #print("text:  $text\n");

  # format 'Måndag 11 06'
  if( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+\d+\$/i ){
    return 1;
  } elsif( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+(januari|februari|mars|april|maj|juni|juli|augusti|september|oktober|november|december)$/i ){ # format 'Måndag 11 juli'
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text, $year ) = @_;
#print("text2:  $text\n");
  my( $dayname, $day, $monthname, $month );

  # format 'Måndag 11 06'
  if( $text =~ /^(Måndag|Tisdag|Onsdag|Torsdag|Fredag|Lördag|Söndag)\s+\d+\.\d+\.\d+\.$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.(\d+)\.(\d+)\.$/ );
  } elsif( $text =~ /^(M.ndag|Tisdag|Onsdag|Torsdag|Fredag|L.rdag|S.ndag)\s+\d+\s+(januari|februari|mars|april|maj|juni|juli|augusti|september|oktober|november|december)$/i ){ # format 'Måndag 11 Juli'
    ( $dayname, $day, $monthname ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\S+)$/i );

    $month = MonthNumber( $monthname, 'sv' );
  }
	
#my $dt_now = DateTime->now();

print("day: $day, month: $month, year: $year\n");

  my $dt = DateTime->new(
  				year => $year,
    			month => $month,
    			day => $day,
      		);
  
  # Add a year if the month is January
  #if($month eq 1) {
  #  	$dt->add( year => 1 );
  #}

  #return sprintf( '%d-%02d-%02d', $year, $month, $day );
  return $dt->ymd("-");
}

sub isShow {
  my ( $text ) = @_;

  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $text =~ /^\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $genre, $desc, $rating );

  ( $time, $title ) = ( $text =~ /^(\d+\.\d+)\s+(.*)$/ );

  # parse description
  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $title =~ /\s+-\s+(.*)$/ ){
    ( $desc ) = ( $title =~ /\s+-\s+(.*)$/ );
    $title =~ s/\s+-\s+(.*)$//;
  }

  my ( $hour , $min ) = ( $time =~ /^(\d+).(\d+)$/ );
  
  $time = sprintf( "%02d:%02d", $hour, $min );

  return( $time, $title, $desc );
}

sub isYear {
  my ( $text ) = @_;

  # format 'Programöversikt 2011 (Programtablå)'
  if( $text =~ /Program.versikt\s+\d+\s*/i ){
    return 1;
  }

  return 0;
}

sub ParseYear {
  my( $text ) = @_;
  my( $year, $dummy );

  # format 'Måndag 11 06'
  if( $text =~ /(Program.versikt)\s+\d+\s+/i ){ # format 'Måndag 11 Juli'
    ( $dummy, $year ) = ( $text =~ /(\S+)\s+(\d+)\s+(\S+)/i );
  }
  return $year;
}


sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("Kanal10: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
