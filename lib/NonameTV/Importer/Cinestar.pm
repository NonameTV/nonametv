package NonameTV::Importer::Cinestar;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

#return if( $file !~ /EPG CTV 2-11-04-2010/i );

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "Cinestar: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $batch_id = $xmltvid . "_" . $file;
  $ds->StartBatch( $batch_id , $channel_id );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Cinestar: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          next if( ! $oWkS->{Cells}[$iR][$iC] );
          next if( ! $oWkS->{Cells}[$iR][$iC]->Value );

          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;

          # columns alternate names
          $columns{'Title CRO'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Cro Title/i );
          $columns{'Title CRO'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Title$/i );
          $columns{'STARTTIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^POČETAK$/i );
        }
foreach my $col (%columns) {
print ">$col<\n";
}
        next;
      }


      # date - column 0 ('DATUM')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'DATUM'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
$date = $currdate if ( ! $date );
      next if( ! $date );
$currdate = $date;

      # starttime - column ('POČETAK')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'STARTTIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $starttime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );
      next if( ! $starttime );

      # endtime - column ('KRAJ')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'KRAJ'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $endtime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );
      next if( ! $endtime );

      if( $starttime gt $endtime ){
        $endtime = $endtime->add( days => 1 );
      }

      # cro title - column ('HRV NASLOV')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'HRV NASLOV'}];
      next if( ! $oWkC );
      my $crotitle = $oWkC->Value if( $oWkC->Value );
      next if( ! $crotitle );

      my $progtype = $oWkS->{Cells}[$iR][$columns{'VRSTA'}]->Value if $oWkS->{Cells}[$iR][$columns{'VRSTA'}];
      #my $origtitle = $oWkS->{Cells}[$iR][$columns{'ORG. NASLOV'}]->Value if $oWkS->{Cells}[$iR][$columns{'ORG. NASLOV'}];
      my $year = $oWkS->{Cells}[$iR][$columns{'GODINA'}]->Value if $oWkS->{Cells}[$iR][$columns{'GODINA'}];
      my $director = $oWkS->{Cells}[$iR][$columns{'REŽIJA'}]->Value if $oWkS->{Cells}[$iR][$columns{'REŽIJA'}];
      #my $actor = $oWkS->{Cells}[$iR][$columns{'ULOGE'}]->Value if $oWkS->{Cells}[$iR][$columns{'ULOGE'}];
      my $synopsis = $oWkS->{Cells}[$iR][$columns{'SINOPSIS'}]->Value if $oWkS->{Cells}[$iR][$columns{'SINOPSIS'}];
      #my $genre = $oWkS->{Cells}[$iR][$columns{'ŽANR'}]->Value if $oWkS->{Cells}[$iR][$columns{'ŽANR'}];
      #my $country = $oWkS->{Cells}[$iR][$columns{'ZEMLJA'}]->Value if $oWkS->{Cells}[$iR][$columns{'ZEMLJA'}];
      #my $duration = $oWkS->{Cells}[$iR][$columns{'TRAJANJE'}]->Value if $oWkS->{Cells}[$iR][$columns{'TRAJANJE'}];
      #my $rating = $oWkS->{Cells}[$iR][$columns{'DOBNA OZNAKA'}]->Value if $oWkS->{Cells}[$iR][$columns{'DOBNA OZNAKA'}];

      progress("Cinestar: $xmltvid: $starttime - $crotitle");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time     => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title        => $crotitle,
      };

      # subtitle, etc...
      #$ce->{subtitle} = $origtitle if $origtitle;
      $ce->{description} = $synopsis if $synopsis;

      $ce->{program_type} = $progtype if $progtype;
      $ce->{production_date} = "$year-01-01" if $year;
      $ce->{directors} = $director if $director;
      #$ce->{actors} = $actor if $actor;

      # genre
#      if( $genre ){
#        my($program_type, $category ) = $ds->LookupCat( "Cinestar", $genre );
#        AddCategory( $ce, $program_type, $category );
#      }

      $ds->AddProgramme( $ce );
    }

    %columns = ();

  }

  $ds->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

#print ">$dinfo<\n";

  my( $month, $day, $year );

  # format '2010-04-02'
  if( $dinfo =~ /^\d{4}-\d{2}-\d{2}$/ ){
    ( $year, $month, $day ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );

  # format '08/06/09/'
  } elsif( $dinfo =~ /^\d+\/\d+\/\d+\/$/ ){
    ( $day, $month, $year ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)\/$/ );

  # format '6-13-09'
  } elsif( $dinfo =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );

  } else {
    return undef;
  }

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub create_dt
{
  my( $date, $time ) = @_;

#print ">$time<\n";

  my( $hour, $min, $sec, $msec );

  if( $time =~ /\d+:\d+:\d+:\d+/ ){
    ( $hour, $min, $sec, $msec ) = ( $time =~ /(\d+):(\d+):(\d+):(\d+)/ );
  } elsif( $time =~ /\d+:\d+:\d+/ ){
    ( $hour, $min, $sec ) = ( $time =~ /(\d+):(\d+):(\d+)/ );
  } elsif( $time =~ /\d+:\d+/ ){
    ( $hour, $min ) = ( $time =~ /(\d+):(\d+)/ );
  } else {
    return undef;
  }

  my $dt = $date->clone()->add( hours => $hour , minutes => $min );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
