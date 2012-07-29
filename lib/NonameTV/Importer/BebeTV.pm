package NonameTV::Importer::BebeTV;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use DateTime::Format::Excel;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
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

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if ( $file !~ /xls$/i );

  if( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "BebeTV: $xmltvid: $file: Unknown file format" );
  }

  return;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.doc$/i );

  progress( "BebeTV: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "BebeTV: $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  if( $ns->size() == 0 ) {
    error( "BebeTV: $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

#print ">$text<\n";

    if( $text eq "" ) {
      # blank line
    }
    elsif( isDate( $text ) ) { # the line with date in format '2008.05.26 Monday'

      $date = ParseDate( $text );

      if( defined $date ) {

        if( $currdate ne "x" ){
          $dsh->EndBatch( 1 )
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date, "00:00" ); 
        $currdate = $date;

        progress("BebeTV: $xmltvid: Date is $date");
      }

    }
    elsif( isShow( $text ) ) { # the line with show in format '2008.05.26 0:15 Title'

      my( $time, $title, $episinfo, $duration );

      ( $date, $time, $title, $episinfo, $duration ) = ParseShow( $text );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date, "00:00" ); 
        $currdate = $date;

        progress("BebeTV: $xmltvid: Date is $date");
      }

      progress("BebeTV: $xmltvid: $time - $title");

      my $ce = {
        channel_id   => $chd->{id},
	start_time => $time,
	title => norm($title),
      };

      my $episode = undef;
      my ( $ep_nr , $ep_se );
      if( $episinfo ){

        if( $episinfo =~ /^\d+\/\d+$/ ){
          ( $ep_nr , $ep_se ) = ( $episinfo =~ /(\d+)\/(\d+)/ );
          $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
        }
        elsif( $episinfo =~ /^\d+$/ )
        {
          $ep_nr = ( $episinfo =~ /(\d+)/ );
          $episode = sprintf( ". %d .", $ep_nr-1 );
        }

        $ce->{episode} = norm($episode);
        $ce->{program_type} = 'series';

      }

      if( $chd->{xmltvid} =~ /bebetvhd/ ){
        $ce->{quality} = "HDTV";
      }

      $dsh->AddProgramme( $ce );

    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}


sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xls$/i );

  progress( "BebeTV: $xmltvid: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 2;
  my $colsynop = 3;

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++){

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "BebeTV: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    my $date;
    my $currdate = "x";

    # browse through rows
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++){

      # date
      my $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date, "00:00" );
        $currdate = $date;

        progress("BebeTV: $xmltvid: Date is $date");
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # synopsis
      $oWkC = $oWkS->{Cells}[$iR][$colsynop];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $synopsis = $oWkC->Value;

      progress("BebeTV: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

      $ce->{description} = $synopsis if $synopsis;

      if( $chd->{xmltvid} =~ /bebetvhd/ ){
        $ce->{quality} = "HDTV";
      }

      $dsh->AddProgramme( $ce );

    } # next row

    $dsh->EndBatch( 1 );

  } # next sheet

  return;
}

sub isDate {
  my( $text ) = @_;

  if( $text =~ /^\d{4}\.\d{2}\.\d{2}\.*\s+\S+$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

#print ">$text<\n";

  my( $year , $month , $day , $dayname );

  if( $text =~ /(\d{4})\.(\d{2})\.(\d{2})\.*\s+(\S+)/ ){
    ( $year , $month , $day , $dayname ) = ( $text =~ /(\d{4})\.(\d{2})\.(\d{2})\.*\s+(\S+)/ );
  } elsif( $text =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year , $month , $day ) = ( $text =~ /(\d+)-(\d+)-(\d+)/ );
  } elsif( $text =~ /^\d+-\d+-\d+$/ ){
    ( $month , $day , $year ) = ( $text =~ /(\d+)-(\d+)-(\d+)/ );
  } elsif( $text =~ /^\d+$/ ){
    my $dt = DateTime::Format::Excel->parse_datetime( $text );
    $year = $dt->year;
    $month = $dt->month;
    $day = $dt->day;
  }
  
  $year += 2000 if $year lt 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

#print ">$text<\n";

  my( $hour , $min , $sec );

  if( $text =~ /^\[\d+\]:\d+:\d+$/ ){ # format '[00]:00:30'
    ( $hour , $min, $sec ) = ( $text =~ /^\[(\d+)\]:(\d+):(\d+)$/ );
  } elsif( $text =~ /^\d+:\d+:\d+$/ ){ # format '00:00:30'
    ( $hour , $min, $sec ) = ( $text =~ /^(\d+):(\d+):(\d+)$/ );
  } elsif( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } elsif( $text =~ /^0\.\d+$/){ # format '0.377962962962964'
    my $daysecs = int( 86400 * $text );
    $hour = int( $daysecs / 3600 );
    $min =  int( ( $daysecs - ( $hour * 3600 ) ) / 60 );
  }
    

  return sprintf( "%02d:%02d", $hour, $min );
}

sub isShow {
  my( $text ) = @_;

  if( $text =~ /^\d+\.\d+\.\d+\.*\s+\d+:\d+/ ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $year, $month, $day, $hour, $min, $sec, $string );

  if( $text =~ /^\d+\.\d+\.\d+\.*\s+\d+:\d+\s+.*$/ ){
    ( $year, $month, $day, $hour, $min, $string ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)\.*\s+(\d+):(\d+)\s+(.*)$/ );
  } elsif( $text =~ /^\d+\.\d+\.\d+\.*\s+\d+:\d+:\d+\s+.*$/ ){
    ( $year, $month, $day, $hour, $min, $sec, $string ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)\.*\s+(\d+):(\d+):(\d+)\s+(.*)$/ );
  }

  my( $title, $episode, $duration );
  if( $string =~ /Ep\.:(\d+)\/(\d+)/ ){ # example: 'Magic fingers	Ep.:2/1	2'
  	( $title, $episode, $duration ) = ( $string =~ /(.*)Ep\.:(\d+\/\d+)\s+(\d+)/ );
  } elsif( $string =~ /Ep\.:\d+\s+\d+/ ){ # example: Waterworld	Ep.:6	15'
  	( $title, $episode, $duration ) = ( $string =~ /(.*)Ep\.:(\d+)\s+(\d+)/ );
  } else {
    $title = $string;
  }

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  my $time = sprintf( "%02d:%02d", $hour, $min );

  return( $date, $time , $title , $episode , $duration );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
