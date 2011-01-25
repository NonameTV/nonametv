package NonameTV::Importer::DaVinciLearning;

use strict;
use warnings;

=pod

Import data from Da Vinci Learning

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  $self->{MaxDays} = 10 unless defined $self->{MaxDays};

  my $conf = ReadConfig();
  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);
print "$date\n";

  my $url = $self->{UrlRoot} . '?todo=search&r1=XML'
    . '&firstdate=' . $date
    . '&lastdate=' . $date
    . '&channel=' . $chd->{grabber_info};

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xml$/i ){
    #$self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportFlatXLS( $file, $chd );
  } else {
    error( "DaVinciLearning: Unknown file format: $file" );
  }

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "DaVinciLearning FlatXLS: $chd->{xmltvid}: Processing flat XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "DaVinciLearning FlatXLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("DaVinciLearning FlatXLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            $columns{'Start Plan'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /start plan/i );
            $columns{'library id'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /library id/i );
            $columns{'length'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /length/i );
            $columns{'Programmcode'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /programm code/i );
            $columns{'ORI Cliptitel'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /ORI clip title/i );
            $columns{'ORI epg'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /ORI epg/i );
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'day'}];
      if( $oWkC  and $oWkC->Value ){

        if( isDate( $oWkC->Value ) ){
          $date = ParseDate( $oWkC->Value );
        }

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
          $dsh->StartDate( $date , "06:00" );
          $currdate = $date;

          progress("DaVinciLearning FlatXLS: $chd->{xmltvid}: Date is: $date");
        }
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start Plan'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # Library id
      $oWkC = $oWkS->{Cells}[$iR][$columns{'library id'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $libraryid = $oWkC->Value;

      # Length
      $oWkC = $oWkS->{Cells}[$iR][$columns{'length'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $length = $oWkC->Value;

      # Program code
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Programmcode'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $programcode = $oWkC->Value;

      # Age group
      $oWkC = $oWkS->{Cells}[$iR][$columns{'age group'}];
      my $agegroup = $oWkC->Value if $oWkC->Value;

      # Target audience
      $oWkC = $oWkS->{Cells}[$iR][$columns{'target audience'}];
      my $targetaudience = $oWkC->Value if $oWkC->Value;

      # Genre 1
      $oWkC = $oWkS->{Cells}[$iR][$columns{'genre1'}];
      my $genre1 = $oWkC->Value if $oWkC->Value;

      # Genre 2
      $oWkC = $oWkS->{Cells}[$iR][$columns{'genre2'}];
      my $genre2 = $oWkC->Value if $oWkC->Value;

      # ORI Cliptitel
      $oWkC = $oWkS->{Cells}[$iR][$columns{'ORI Cliptitel'}];
      my $oricliptitle = $oWkC->Value if $oWkC->Value;

      # ORI series title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'ORI series title'}];
      my $oriseriestitle = $oWkC->Value if $oWkC->Value;

      # ORI epg
      $oWkC = $oWkS->{Cells}[$iR][$columns{'ORI epg'}];
      my $oriepg = $oWkC->Value if $oWkC->Value;

      # ORI synopse
      $oWkC = $oWkS->{Cells}[$iR][$columns{'ORI synopse'}];
      my $orisynopsis = $oWkC->Value if $oWkC->Value;

      my $title = $oriseriestitle;

      progress( "DaVinciLearning FlatXLS: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $ce->{schedule_id} = $libraryid if ( $libraryid =~ /\S/ );

      if( $agegroup ){
      }

      if( $targetaudience ){
      }

      if( $genre1 ){
        my($program_type, $category ) = $ds->LookupCat( 'DaVinciLearning', $genre1 );
        AddCategory( $ce, $program_type, $category );
      }
    
      if( $genre2 ){
        my($program_type, $category ) = $ds->LookupCat( 'DaVinciLearning', $genre2 );
        AddCategory( $ce, $program_type, $category );
      }

      if( $oricliptitle ){
        $ce->{subtitle} = $oricliptitle;
      }

      if( $oriseriestitle ){
      }

      if( $oriepg ){
        #$ce->{description} = $orisynopsis . "\n";
      }

      if( $orisynopsis ){
        $ce->{description} = $orisynopsis;
      }

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format '01.09.10'
  if( $text =~ /^\d{2}\.\d{2}\.\d{2}$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my ( $text ) = @_;

#print ">$text<\n";

  my( $year, $day, $month );

  # format '01.09.10'
  if( $text =~ /^\d{2}\.\d{2}\.\d{2}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\.(\d{2})\.(\d{2})$/i );
  }

  $year += 2000 if $year < 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub UpdateFiles {
  my( $self ) = @_;

  # the url to fetch data from is in the format
  # ftp://press@194.29.226.161/01-EPG/01-DVL_Pan_Europe/01-ORI/2010/09 September/PlaylistSave_20100925_TOP_ORI.xls
  # UrlRoot = ftp://press@194.29.226.161/01-EPG/01-DVL_Pan_Europe/01-ORI/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxDays in advance
    for(my $day=0; $day <= $self->{MaxDays} ; $day++) {

      my $dt = $today->clone->add( days => $day );

      my $filename = sprintf( "PlaylistSave_%s%s%s_TOP_ORI.xls", $dt->strftime( '%Y' ), $dt->strftime( '%m' ), $dt->strftime( '%d' ) );
      my $url = sprintf( "%s/%s/%s %s/daily/%s", $self->{UrlRoot}, $dt->strftime( '%Y' ), $dt->strftime( '%m' ), $dt->strftime( '%B' ), $filename );
      progress("DaVinciLearning: $xmltvid: Fetching xls file from $url");
      url_get( $url , $self->{FileStore} . '/' . $xmltvid . '/' . $filename );
    }
  }
}

sub url_get {
  my( $url, $destination ) = @_;

  qx[curl -s -S -z "$destination" -o "$destination" "$url"];
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
