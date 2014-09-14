package NonameTV::Importer::DWDE_XLS;

use strict;
use warnings;


=pod

Import data from XLS or XLSX files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::Read;
use Archive::Zip qw/:ERROR_CODES/;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");


use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm normUtf8 AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "UTC" );
  $self->{datastorehelper} = $dsh;

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

  if( $file =~ /\.xls|.xlsx$/i ){
    $self->ImportXLS( $file, $chd );
  } elsif( $file =~ /\.zip$/i ) {
    my $zip = Archive::Zip->new();
    if( $zip->read( $file ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }


    my @files;

    my @members = $zip->members();
    foreach my $member (@members) {
        push( @files, $member->{fileName} ) if $member->{fileName} =~ /xls/i;
    }

    my $numfiles = scalar( @files );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }

    d "Using file $files[0]";

    # file exists - could be a new file with the same filename
    # remove it.
    my $filename = '/tmp/'.$files[0];
    if (-e $filename) {
    	unlink $filename; # remove file
    }

    my $content = $zip->contents( $files[0] );

    open (MYFILE, '>>'.$filename);
	print MYFILE $content;
	close (MYFILE);

    $self->ImportXLS( $filename, $chd );
    unlink $filename; # remove file
  }else {
    error( "DWDE_XLS: Unknown file format: $file" );
  }


  return;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls or .xlsx files.
  progress( "DWDE_XLS: $xmltvid: Processing $file" );

  my($coldate, $coltime, $coltitle, $colsubtitle, $coldesc, $colgenre);

  my $date;
  my $currdate = "x";
  if($xmltvid eq "amerika.dw.de") {
    $coldate  = 0;
    $coltime  = 2;
    $coltitle = 3;
    $colsubtitle = 4;
    $coldesc  = 5;
  } elsif($xmltvid eq "la.dw.de") {
    $coldate  = 1;
    $coltime  = 3;
    $coltitle = 4;
    $colsubtitle = 5;
    $coldesc  = 6;
  }elsif($xmltvid eq "asien.dw.de") {
    $coldate  = 2;
    $coltime  = 4;
    $coltitle = 9;
    $colsubtitle = 10;
    $coldesc  = 11;
  }else {
    $coldate  = 0;
    $coltime  = 1;
    $coltitle = 2;
    $colgenre = 3;
    $coldesc  = 4;
  }


  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} !~ /1/ ){
      progress( "DWDE_XLS: Skipping other sheet: $oWkS->{Name}" );
      next;
    }

    progress( "DWDE_XLS: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;
    # browse through rows
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      if(!defined($coldate)) {
        f "No date found,";
        return;
      }

      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("DWDE_XLS: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$coltime];
      next if( ! $oWkC );



      my $time = 0;  # fix for  12:00AM
      $time=$oWkC->{Val} if( $oWkC->Value );

	  #Convert Excel Time -> localtime
      $time = ExcelFmt('hh:mm', $time);
      $time =~ s/_/:/g; # They fail sometimes

      # Desc
      $oWkC = $oWkS->{Cells}[$iR][$coldesc];
      my $desc = norm($oWkC->Value) if( $oWkC );

      # genre
      $oWkC = $oWkS->{Cells}[$iR][$colgenre] if defined($colgenre);
      my $genre = norm($oWkC->Value) if( $oWkC and defined($colgenre) );

      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title	   => norm($title),
        aspect     => '16:9',
      };

      $ce->{description} = $desc if defined($desc);

      # Duno what this is, not genre, I think.
      if(defined($colgenre) and defined($genre) and $genre ne "" ){
      #  my ($program_type2, $category2 ) = $ds->LookupCat( 'DWDE', $genre );
      #	AddCategory( $ce, $program_type2, $category2 );
      }

	  progress("$xmltvid: $time - $title") if $title;
      $dsh->AddProgramme( $ce ) if $title;
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  #print Dumper($dinfo);

  my( $month, $day, $year );
#      progress("Mdatum $dinfo");
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){ # format   '2010-04-22'
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{2}.\d{2}.\d{4}$/ ){ # format '11/18/2011'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+).(\d+).(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}-\d{1,2}-\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d{1,2}\/\d{1,2}\/\d{2}$/ ){ # format '10-18-11' or '1-9-11'
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
