package NonameTV::Importer::LuxeTV;

use strict;
use warnings;

=pod

Import data from CSV-files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Text::CSV;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.csv$/i );

#return if( $file !~ /130709/ );

  if( $file =~ /FR\.csv$/i ){
    progress( "LuxeTV: $xmltvid: Skipping $file" );
    return;
  }

  progress( "LuxeTV: $xmltvid: Processing $file" );

  my $date;
  my $currdate = "x";

  open my $CSVFILE, "<", $file or die $!;

  my $csv = Text::CSV->new( {
    sep_char => "\t",
    allow_whitespace => 0,
    blank_is_undef => 1,
    binary => 1,
    verbatim => 1,
  } );

  # get the column names from the first line
  my @columns = $csv->column_names( $csv->getline( $CSVFILE ) );
  if( ! @columns or ( @columns[0] =~ /UNDEF/ ) ){
    progress( "LuxeTV: $xmltvid: No column names" );
    @columns = $csv->column_names( 'Date', 'Time', 'Duration', 'Title', 'Episode', 'Synopsis', 'Genre' );
  }
#foreach my $c (@columns) {
#print ">$c<\n";
#}


  # main loop
  while( my $row = $csv->getline_hr( $CSVFILE ) ){

    if( $row->{'Date'} ) {

      $date = ParseDate( $row->{'Date'} );
      next if( ! $date );

      if( $date ne $currdate ){

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "04:00" );
        $currdate = $date;
        progress( "LuxeTV: $xmltvid: Date is $date" );
      }
    }

    my $time;
    if( $row->{'Time'} ) {
      $time = ParseTime( $row->{'Time'} );
    }
    next if( ! $time );

    my $duration;
    if( $row->{'Duration'} ) {
      $duration = $row->{'Duration'};
    }
    #next if ( $duration !~ /^\d\d\:\d\d\:\d\d\.\d\d$/ );

    my $title;
    if( $row->{'Title'} ) {
      $title = $row->{'Title'};
    }
    next if ( ! $title );

    progress( "LuxeTV: $xmltvid: $time - $title" );

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      start_time => $time,
    };

    my $episode;
    if( $row->{'Episode'} ) {

      my $epinfo = $row->{'Episode'};

      if( $epinfo =~ /^Episode\s+\d+/ ){

        my $ep_nr;
        ( $ep_nr ) = ( $epinfo =~ /^Episode\s+(\d+)/ );

        my $part_no;
        if( $epinfo =~ /\s+part\s+\d+/i ){
          ( $part_no ) = ( $epinfo =~ /\s+part\s+(\d+)/ );
        }

        if( $part_no ){
          $ce->{episode} = sprintf( ". %d . %d", $ep_nr-1, $part_no-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $ep_nr-1 );
        }

      } else {
        $ce->{subtitle} = $epinfo;
      }
    }

    if( $ce->{subtitle} ){
      #$ce->{title} .= " - " . $ce->{subtitle};
    }

    if( $row->{'Synopsis'} ){
      #$ce->{description} = $row->{'Episode'} . "\n\n" if $row->{'Episode'};
      $ce->{description} .= $row->{'Synopsis'};
    }

    if( $row->{'Genre'} ) {
      my($program_type, $category ) = $ds->LookupCat( "LuxeTV", norm($row->{'Genre'}) );
      AddCategory( $ce, $program_type, $category );
    }

    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my( $text ) = @_;

  return undef if( ! $text );
#print "ParseDate >$text<\n";

  my( $day , $month , $year, $monthname );

  if( $text =~ /^\d\d\/\d\d\/\d\d$/ ){
    ( $day , $month , $year ) = ( $text =~ /^(\d\d)\/(\d\d)\/(\d\d)$/ );
  } elsif( $text =~ /^(\d+)-(\S+)-(\d+)$/ ){ # Format: "30-Nov-10"
    ( $day , $monthname , $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );
    $month = MonthNumber( $monthname, "en" );
  } else {
    return undef;
  }

  $year += 2000 if $year lt 100;

  my $date = DateTime->new( year   => $year,
                            month  => $month,
                            day    => $day,
                            hour   => 0,
                            minute => 0,
                            second => 0,
                            nanosecond => 0,
                            time_zone => 'Europe/Paris',
  );

  return $date->ymd("-");
}

sub ParseTime {
  my( $tinfo ) = @_;

#print "$tinfo\n";

  my( $hour, $min, $sec, $ampm );

  if ( $tinfo =~ /^\d\d\:\d\d\:\d\d\s+(AM|PM)$/ ){
    ( $hour, $min, $sec, $ampm ) = ( $tinfo =~ /^(\d\d)\:(\d\d)\:(\d\d)\s+(\S+)$/ );
    $hour += 12 if( $ampm eq "PM" );
    $hour = 0 if( $hour eq 24 );
  } elsif ( $tinfo =~ /^\d+:\d+:\d+$/ ){
    ( $hour, $min, $sec ) = ( $tinfo =~ /^(\d+)\:(\d+)\:(\d+)$/ );
  } else {
    return undef;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
