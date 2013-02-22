package NonameTV::Importer::TVChile;

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

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");


use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm normUtf8 AddCategory/;
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
  }else {
  	
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
  progress( "TVChile: $xmltvid: Processing $file" );

	my %columns = ();
  my $date;
  my $currdate = "x";
  my $coldate = 0;
  my $coltime = 1;
  my $coltitle = 2;
  my $colgenre = 3;
  my $coldesc = 4;

  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }
  my $ref = ReadData ($file);

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "TVChile: Processing worksheet: $oWkS->{Name}" );

	my $foundcolumns = 0;
    # browse through rows
    my $i = 5;
    for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
	$i++;
      my $oWkC;

      # date
      $oWkC = $oWkS->{Cells}[$iR][$coldate];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("TVChile: Date is $date");

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

      # title
      $oWkC = $oWkS->{Cells}[$iR][$coltitle];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      $title =~ s/\(RESUMEN SEMANAL\)//g if $title;

	  my $start = create_dt($date." ".$time);
      next if( ! $start );

      my $ce = {
        channel_id => $channel_id,
        start_time => $start->hms(":"),
        title	   => norm($title),
      };
      
      # Desc (only works on XLS files)
      my $field = "E".$i;
      my $desc = $ref->[1]{$field};
      $ce->{description} = normUtf8($desc) if( $desc );
      $desc = '';
      
      # Genre
	  $oWkC = $oWkS->{Cells}[$iR][$colgenre];
	  if( $oWkC and $oWkC->Value ne "" ) {
      	my $genre = $oWkC->Value;
	  	my($program_type, $category ) = $ds->LookupCat( 'TVChile', $genre );
	  	AddCategory( $ce, $program_type, $category );
	  }
      
	  progress("TVChile: ".$start->hms(":")." - $title") if $title;
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

sub create_dt
{
  my( $str ) = shift;
  my( $year, $month, $day, $hour, $minute, $second );

  if( $str =~ /^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}$/ ){
  	( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+)$/ );
  } elsif( $str =~ /^\d{4}-\d{2}-\d{2}  \d{1,2}:\d{2}$/ ){
  	( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+)  (\d+):(\d+)$/ );
  } elsif( $str =~ /^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2} $/ ){
  	( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+) $/ );
  } elsif( $str =~ /^\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2}/ ){
  	( $year, $month, $day, $hour, $minute, $second ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/ );
  } elsif( $str =~ /^\d{4}\/\d{2}\/\d{2}$/ ){
  	( $year, $month, $day ) = 
      ($str =~ /(\d+)\/(\d+)\/(\d+)$/ );
  }else {
  	return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'America/Santiago',
                          );
  # somehow it fails, (one hour off)
  $dt->add( hours => 1 );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
