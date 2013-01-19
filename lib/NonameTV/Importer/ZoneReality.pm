package NonameTV::Importer::ZoneReality;

use strict;
use warnings;

=pod

Channels: ZoneReality

Import data from XLS or DOC files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
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

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.xls$/i );

  progress( "ZoneReality: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "ZoneReality: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {


      # get the names of the columns from the 1st row
      # the columns that we use are
      # Date
      # Film start hour
      # Polish Title
      # Episode number
      # Season
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;

          # alternate column name for 'Date'
          $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Tx Date/ );

          # alternate column name for 'Film start hour'
          $columns{'Film start hour'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Billed Start/ );

          # alternate column name for 'Polish title'
          $columns{'Polish Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Poljski titl/ );
          $columns{'Polish Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ );
        }
        next;
      }

#foreach my $col (%columns) {
#print "$col\n";
#}

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        progress("ZoneReality: $xmltvid: Date is $date");

        if( $currdate ne "x" ){
          # save last day if we have it in memory
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

      # starttime - column ('Film start hour')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Film start hour'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $starttime = ParseTime( $oWkC->Value );
      next if( ! $starttime );

      # title - column ('Polish Title')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Polish Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      my $epino = $oWkS->{Cells}[$iR][$columns{'Episode number'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode number'}];
      my $seano = $oWkS->{Cells}[$iR][$columns{'Season'}]->Value if $oWkS->{Cells}[$iR][$columns{'Season'}];

      progress("ZoneReality: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $starttime,
      };

      if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}
  
sub ImportDOC
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "ZoneReality: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "ZoneReality $xmltvid: $file: Failed to parse" );
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
    error( "ZoneReality $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    # skip the bottom of the document
    # all after 'TJEDNI PROGRAM'
    last if( $text =~ /^Produced by EBS New Media/ );

#print ">$text<\n";

    if( isDate( $text ) ) { # the line with the date in format 'FRIDAY 1 AUGUST 2008 - ZONE REALITY EMEA 1'
      $date = ParseDate( $text );

      if( $date ) {

        progress("ZoneReality: $xmltvid: Date is $date");

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

      my( $time, $title, $genre ) = ParseShow( $text );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){

        my($program_type, $category ) = $ds->LookupCat( "ZoneReality", $genre );
        AddCategory( $ce, $program_type, $category );

        $ce->{description} = $genre;
      }

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    } else {

        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        # remove ' - ' from the start
  	$text =~ s/^\s*-\s*//;
        $element->{description} .= $text;
    }
  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("ZoneReality: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

  # format 'FRIDAY 1 AUGUST 2008 - ZONE REALITY EMEA 1'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+\d+\s+\S+\s+\d+\s+- ZONE REALITY EMEA 1$/i ){
    return 1;
  } elsif( $text =~ /^\d+-\d+-\d+$/ ){
    return 1;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

#print "ParseDate: >$text<\n";

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\S+\s+\d+\s+\S+\s+\d+/ ) { # format 'FRIDAY 1 AUGUST 2008 - ZONE REALITY EMEA 1'
    ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)/ );
    $month = MonthNumber( $monthname, 'en' );
  } elsif( $text =~ /^\d+-\d+-\d+$/ ) { # format '10-1-08'
    ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } elsif( $text =~ /^0\.\d+$/){ # format '0.377962962962964'
    my $daysecs = int( 86400 * $text );
    $hour = int( $daysecs / 3600 );
    $min =  int( ( $daysecs - ( $hour * 3600 ) ) / 60 );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub isShow {
  my ( $text ) = @_;

  # format '12:40 Glazbeni program'
  if( $text =~ /^\d+\:\d+\s+.*/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $genre );

#  if( $text =~ /\,/ ){
#    ( $genre ) = ( $text =~ /\,\s*(.*)/ );
#    $text =~ s/\,\s*.*//;
#  }
    
  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\:(\d+)\s+(.*)/ );

  return( $hour . ":" . $min , $title , $genre );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
