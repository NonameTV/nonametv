package NonameTV::Importer::BBCPrime;

use strict;
use warnings;

=pod

Import data from xml-files that we download via FTP. Use BaseFile as
ancestor to avoid redownloading and reprocessing the files each time.

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/MyGet norm MonthNumber AddCategory/;
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
  
  my $conf = ReadConfig();
  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

return if( $file !~ /Entertainment/i );
  progress( "BBCPrime: $channel_xmltvid: Processing $file" );


  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "BBCPrime: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("BBCPrime: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        my $colrow;

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){

            my $value = $oWkS->{Cells}[$iR][$iC]->Value;
            $value =~ s/\s+//;

            $columns{$value} = $iC;

            $columns{'DATETIME'} = $iC if( $value =~ /^DATE\s*CET$/i );
            $columns{'DATE'} = $iC if( $value =~ /^plandate$/i );
            $columns{'TIME'} = $iC if( $value =~ /^plantime$/i );
            $columns{'PROGRAMME'} = $iC if( $value =~ /^title\s*name$/i );
            $columns{'SERIES'} = $iC if( $value =~ /^series$/i );
            $columns{'EP'} = $iC if( $value =~ /^ep no$/i );
            $columns{'EPISODETITLE'} = $iC if( $value =~ /^EPISODE\s*NAME$/i );
            $columns{'BILLING'} = $iC if( $value =~ /^billing$/i );
            $columns{'GENRE'} = $iC if( $value =~ /^genre$/i );
            $columns{'SUBS'} = $iC if( $value =~ /^subtles$/i );
            $columns{'CERT'} = $iC if( $value =~ /^certificates$/i );

            $colrow = $iR if( ( $value =~ /^PROGRAMME$/ ) or ( $value =~ /^billing$/i ) );

            next;
          }
        }

        if( $colrow ){
          progress("BBCPrime: $channel_xmltvid: Found column names at row $iR" );
#foreach my $col (%columns) {
#print ">$col<\n";
#}
        } else {
          %columns = ();
          next;
        }

      }

      my $oWkC;
      my $time;

      if( defined $columns{'DATETIME'} ){ # old BBC Prime date column format
        $oWkC = $oWkS->{Cells}[$iR][$columns{'DATETIME'}];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        $date = ParseDate( $oWkC->Value );
        $time = ParseTime( $oWkC->Value );
      } elsif( defined $columns{'DATE'} ){ # new BBC Entertainment date column format
        $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        $date = ParseDate( $oWkC->Value );
      }
      next if( ! $date );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("BBCPrime: $channel_xmltvid: Date is: $date");
      }

      if( defined $columns{'TIME'} ){
        $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
        next if( ! $oWkC );
        next if( ! $oWkC->Value );
        $time = ParseTime( $oWkC->Value );
      }
      next if( ! $time );

      # title - column PROGRAMME
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PROGRAMME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( $title =~ /FLOG IT/i );

      #my $srs = $oWkS->{Cells}[$iR][$columns{'SRS'}]->Value if defined $columns{'SRS'};
      my $ep = $oWkS->{Cells}[$iR][$columns{'EP'}]->Value if defined $columns{'EP'};
      my $series = $oWkS->{Cells}[$iR][$columns{'SERIES'}]->Value if defined $columns{'SERIES'};
      my $episodetitle = $oWkS->{Cells}[$iR][$columns{'EPISODETITLE'}]->Value if defined $columns{'EPISODETITLE'};
      my $billing = $oWkS->{Cells}[$iR][$columns{'BILLING'}]->Value if defined $columns{'BILLING'};
      my $genre = $oWkS->{Cells}[$iR][$columns{'GENRE'}]->Value if defined $columns{'GENRE'};
      my $rpt = $oWkS->{Cells}[$iR][$columns{'RPT'}]->Value if defined $columns{'RPT'};
      my $subs = $oWkS->{Cells}[$iR][$columns{'SUBS'}]->Value if defined $columns{'SUBS'};
      my $cert = $oWkS->{Cells}[$iR][$columns{'CERT'}]->Value if defined $columns{'CERT'};

      progress( "BBCPrime: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      if( $series and $ep ){
        $ce->{episode} = sprintf( "%d . %d .", $series-1, $ep-1 );
      } elsif( $ep ){
        $ce->{episode} = sprintf( ". %d .", $ep-1 );
      }

      if( $episodetitle ){
        $ce->{subtitle} = $episodetitle;
      }

      if( $billing ){
        $ce->{description} = $billing;
      }

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'BBCPrime', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $cert ){
        $ce->{rating} = $cert;
      }

      $dsh->AddProgramme( $ce );

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my( $text ) = @_;

#print ">$text<\n";

  my( $day, $monthname, $month, $year );

  if( $text =~ /^\d+\/\d+\/\d+\s+\d+\:\d+$/ ){ # old BBC Prime date format '04/11/2009 23:25'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)\s+\d+\:\d+$/ );
  } elsif( $text =~ /^\d+-\S+-\d+$/ ){ # new BBC Entertainment date format '31-Dec-09'
    ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );
    $year += 2000 if $year < 100;
    $month = MonthNumber( $monthname, "en" );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ){ # new BBC Entertainment date format '01/03/2010'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } else {
    return undef;
  }

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $text ) = @_;

#print ">$text<\n";

  my( $hour, $min );

  if( $text =~ /^\d+\/\d+\/\d+\s+\d+\:\d+$/ ){ # old BBC Prime time format '04/11/2009 23:25'
    ( $hour, $min ) = ( $text =~ /^\d+\/\d+\/\d+\s+(\d+)\:(\d+)$/ );
  } elsif( $text =~ /^\d+\:\d+$/ ){ # new BBC Entertainment time format '22:10'
    ( $hour, $min ) = ( $text =~ /^(\d+)\:(\d+)$/ );
  } elsif( $text =~ /^\d+\:\d+\:\d+$/ ){ # time format '18:40:00'
    ( $hour, $min ) = ( $text =~ /^(\d+)\:(\d+)\:\d+$/ );
  } else {
    return undef;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub UpdateFiles {
  my( $self ) = @_;

#return;

  my $today = DateTime->today;

  my $filename;
  my $url;

  foreach my $data ( @{$self->ListChannels()} ) { 

    my $xmltvid = $data->{xmltvid};

    # first download the default files
    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      $filename = 'Prime%20Europe%20' . $dt->month_name . '%20' . $dt->year . '.XLS';
      $url = $self->{UrlRoot} . '/' . $filename;

      progress("BBCPrime: Fetching data from default $url");
      http_get( $url, $self->{FileStore} . '/' . $xmltvid . '/' . $filename );

    }

    # then download updated file
    # which url must be stored in grabber_info
    if( $data->{grabber_info} ){
      $filename = $data->{grabber_info};
      $url = $self->{UrlRoot} . '/' . $data->{grabber_info};
      progress("BBCPrime: Fetching data from manual $url");
      http_get( $url, $self->{FileStore} . '/' . $xmltvid . '/' . $filename );
    }
  }  
}

sub http_get {
  my( $url, $file ) = @_;

  qx[curl -s -S -z "$file" -o "$file" "$url"];
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
