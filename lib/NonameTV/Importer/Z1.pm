package NonameTV::Importer::Z1;

use strict;
use warnings;

=pod

Channels: Gradska TV Zadar

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/MyGet Wordfile2Xml norm AddCategory MonthNumber/;
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

#return if ( $file !~ /20090407104828-noname/ );

  if( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } elsif( $file =~ /noname$/i ){
    $self->ImportTXT( $file, $chd );
  }

  return;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $chd ) = @_;
  
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.doc$/i );

  progress( "Z1 DOC: $chd->{xmltvid}: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Z1 DOC $chd->{xmltvid}: $file: Failed to parse" );
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
    error( "Z1 DOC $chd->{xmltvid}: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        progress("Z1 DOC: $chd->{xmltvid}: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "$chd->{xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $chd->{id} );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title, $genre, $ep_no, $ep_se ) = ParseShow( $text );

      progress("Z1 DOC: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Z1', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $ep_no and $ep_se ){
        $ce->{episode} = sprintf( "%d . %d .", $ep_se-1, $ep_no-1 );
      } elsif( $ep_no ){
        $ce->{episode} = sprintf( ". %d .", $ep_no-1 );
      }

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}


sub ImportTXT
{
  my $self = shift;
  my( $file, $chd ) = @_;
  
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "Z1 TXT: $chd->{xmltvid}: Processing $file" );

  open(HTMLFILE, $file);
  my @lines = <HTMLFILE>;
  close(HTMLFILE);

  my $date;
  my $currdate = "x";

  foreach my $text (@lines){

    $text = norm( $text );
#print ">$text<\n";

    if( isDate( $text ) ){

      $date = ParseDate( $text );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Z1 TXT: $chd->{xmltvid}: Date is: $date");
      }
    } elsif( $date and isShow( $text ) ) {

      my( $time, $title, $genre, $ep_no, $ep_se ) = ParseShow( $text );

      progress("Z1 TXT: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Z1', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $ep_no and $ep_se ){
        $ce->{episode} = sprintf( "%d . %d .", $ep_se-1, $ep_no-1 );
      } elsif( $ep_no ){
        $ce->{episode} = sprintf( ". %d .", $ep_no-1 );
      }

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );

  return;
}
  

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;
  
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xls$/i );

  progress( "Z1 XLS: $chd->{xmltvid}: Processing $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Z1 XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("Z1 XLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    my $date = undef;

    # find the cell with the date
    # the file contains the schedule for one date on one sheet
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        if( isDate( $oWkC->Value ) ){
          $date = ParseDate( $oWkC->Value );
          if( $date ) {

            my $batch_id = $chd->{xmltvid} . "_" . $date;
            $dsh->StartBatch( $batch_id , $chd->{id} );
            $dsh->StartDate( $date , "06:00" );

            progress("Z1 XLS: $chd->{xmltvid}: Date is: $date");
          } else {
            return 0;
          }
        }
      }
    }

    my $coltime = 2;
    my $coltitle = 3;

    # read the programs
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

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

      progress("Z1 XLS: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      $dsh->AddProgramme( $ce );
    }

    $dsh->EndBatch( 1 );
  }
  
  return;
}

sub isDate {
  my ( $text ) = @_;

  # format 'ÈTVRTAK  23.10.2008.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  # format 'SRIJEDU 21.1.2009.'
  if( $text =~ /^(ponedjeljak|utorak|srijedu|ÈETVRTAK|petak|subotu|nedjelju)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $month, $year );

  # format 'ÈTVRTAK  23.10.2008.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.\s*(\d+)\.\s*(\d+)\.*$/ );
  }

  # format 'SRIJEDU 21.1.2009.'
  if( $text =~ /^(ponedjeljak|utorak|srijedu|ÈETVRTAK|petak|subotu|nedjelju)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.\s*(\d+)\.\s*(\d+)\.*$/i );
  }

  $year += 2000 if $year lt 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

#print "ParseTime: >$text<\n";

  my( $hour, $min, $sec );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour, $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  } else {
    return undef;
  }

  return sprintf( '%02d:%02d', $hour, $min );
}

sub isShow {
  my ( $text ) = @_;

  # format '15.30 Zap skola,  crtana serija  ( 3/52)'
  if( $text =~ /^\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $genre, $ep_no, $ep_se );

  if( $text =~ /\(\d+\/\d+\)/ ){
    ( $ep_no, $ep_se ) = ( $text =~ /\((\d+)\/(\d+)\)/ );
    $text =~ s/\(\d+\/\d+\).*//;
  }

  if( $text =~ /\,.*/ ){
    ( $genre ) = ( $text =~ /\,\s*(.*)$/ );
    $text =~ s/\,.*//;
  }

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  return( $hour . ":" . $min , $title , $genre , $ep_no, $ep_se );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
