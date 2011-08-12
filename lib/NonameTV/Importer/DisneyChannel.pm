package NonameTV::Importer::DisneyChannel;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail in zip-files.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Archive::Zip qw/:ERROR_CODES/;
use Data::Dumper;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file/;
use IO::Scalar;

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d p w f/;

use NonameTV::Importer::BaseUnstructured;

use base 'NonameTV::Importer::BaseUnstructured';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


		# use augment
    $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContent {
  my $self = shift;
  my( $filename, $cref, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $data;

  if( $filename =~ /\.xml$/i ) {
    $data = $$cref;
  }
  elsif( $filename =~ /\.zip$/i ) {
    my( $fh, $tempname )  = tempfile();
    write_file( $fh, $cref );
    my $zip = Archive::Zip->new();
    if( $zip->read( $tempname ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @swedish_files;
    
    my @members = $zip->members();
    foreach my $member (@members) {
      push( @swedish_files, $member->{fileName} ) 
	  if $member->{fileName} =~ /swe.*xml$/i;
    }
    
    my $numfiles = scalar( @swedish_files );
    if( $numfiles != 1 ) {
      f "Found $numfiles matching files, expected 1.";
      return 0;
    }

    d "Using file $swedish_files[0]";

    $data = $zip->contents( $swedish_files[0] );
  }

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($data); };

  if( not defined( $doc ) ) {
    f "Not well-formed xml";
    return 0;
  }

  my $ns = $doc->find( "//ss:Row" );
  
  if( $ns->size() == 0 ) {
    f "No Rows found";
    return 0;
  }

  my $batch_id;

  my $currdate = "x";
  my $column;

  foreach my $row ($ns->get_nodelist) {
    if( not defined( $column ) ) {
      # This is the first row. Check where the columns are.
      my $ns2 = $row->find( ".//ss:Cell" );
      next if $ns2->size() == 0;

      my $i = 1;
      $column = {};
      foreach my $cell ($ns2->get_nodelist) {
	my $v = $cell->findvalue( "." );
	d "Found column $v";
	$column->{$v} = "ss:Cell[$i]";
	$i++;
      }

      # Check that we found the necessary columns.
      foreach my $col ("Date", "Time", "(SWE) Title", "SYNOPSIS") {
	if( not defined( $column->{$col} ) ) {
	  f "Column $col not found.";
	  return 0;
	}
      }

      next;
    }

    my $orgdate = norm( $row->findvalue( $column->{Date} ) );
    my $orgstarttime = norm( $row->findvalue( $column->{Time} ) );
    my $title = norm( $row->findvalue( $column->{"(SWE) Title"} ) );
    
    my $genre = norm( $row->findvalue( $column->{"Genre"} ) );
    
    my $synopsis = norm( $row->findvalue( $column->{SYNOPSIS} ) );

    if( $orgdate !~ /\S/ ) {
	w "Empty date for $title";
	next;
    }

    my( $year, $month, $day ) = ParseDate( $orgdate );
    if( not defined $day ) {
      w "Invalid date $orgdate";
      next;
    }
    my $date = sprintf( "%4d-%02d-%02d", $year, $month, $day );

    my( $hour, $minute ) = ParseTime( $orgstarttime );
    if( not defined $minute ) {
      w "Invalid time $orgstarttime";
      next;
    }
    my $starttime = sprintf( "%02d:%02d", $hour, $minute );
      
    if( $date ne $currdate ) {
      if( $currdate ne "x" ) {
	$ds->EndBatch( 1 );
      }

      my $batch_id = $xmltvid . "_" . $date;
      $ds->StartBatch( $batch_id );
      $currdate = $date;
    }

    my $start_dt = $self->to_utc( $date, $starttime );

    if( not defined( $start_dt ) ) {
      w "Invalid start-time '$date' '$starttime'. Skipping.";
      next;
    }

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      description => $synopsis,
      start_time => $start_dt->ymd('-') . " " . $start_dt->hms(':'),
    };
    
    if( $genre and (isGenre($genre)) ){
			my($program_type, $category ) = $ds->LookupCat( 'DisneyChannel', $genre );
			AddCategory( $ce, $program_type, $category );
	}
    
    $ds->AddProgramme( $ce );
  }

  $ds->EndBatch( 1 );
    
  return 1;
}

sub isGenre {
  my( $text ) = @_;
	
  # format 'xx:xx'
  if( $text =~ /^\d{2}\:\d{2}$/i ){
    return 0;
  }
  
  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  my( $day, $month, $year ) = ($text =~ m%^(\d\d)/(\d\d)/(\d\d\d\d)$% );
  
  if( not defined( $year ) ) {
    # This might be a DateTime string instead.
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})T\d\d:\d\d:/ );
  }

  if( not defined( $year ) ) {
    return undef;
  }

  return ($year,$month,$day);
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour, $minute ) = ($text =~ m%^(\d\d):(\d\d)$% );
  
  if( not defined( $minute ) ) {
    # This might be a DateTime string instead.
    ( $hour, $minute ) = ( $text =~ /^\d{4}-\d{2}-\d{2}T(\d\d):(\d\d):/ );
  }
  
  if( not defined( $minute ) ) {  
    return undef;
  }

  return ($hour, $minute);
}

sub to_utc {
  my $self = shift;
  my( $date, $time ) = @_;

  my( $year, $month, $day ) = split( "-", $date );
  
  my( $hour, $minute ) = split( ":", $time );

  my $dt;

  my $add = 0;
  if( $hour > 23 ) {
    $hour -= 24;
    $add = 1;
  }

  eval { 
    $dt = DateTime->new( year   => $year,
			 month  => $month,
			 day    => $day,
			 hour   => $hour,
			 minute => $minute,
			 time_zone => 'Europe/Stockholm',
			 );
  };

  if( not defined $dt ) {
    return undef;
  }

  if( $add ) {
    $dt->add( hours => 24 );
  }

  $dt->set_time_zone( "UTC" );

  return $dt;
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
