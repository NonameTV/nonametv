package NonameTV::Importer::PPS;

use strict;
use warnings;

=pod

Import data from PPS.de

Channels: Disney Channel, Disney XD, Disney Cinemagic, Disney Jr.

=cut

use utf8;

use DateTime;
use Data::Dumper;
use Archive::Zip qw/:ERROR_CODES/;
use XML::LibXML;

use NonameTV qw/norm AddCategory AddCountry/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error d p w f/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } elsif( $file =~ /\.zip$/i ) {

    my $zip = Archive::Zip->new();
    if( $zip->read( $file ) != AZ_OK ) {
      f "Failed to read zip.";
      return 0;
    }

    my @files;
    my @members = $zip->members();
    foreach my $member (@members) {
      push( @files, $member->{fileName} ) if $member->{fileName} =~ /xml$/i;
    }

    my $numfiles = scalar( @files );
    if( $numfiles eq 0 ) {
      f "Found 0 matching files, expected more than that.";
      return 0;
    }

    foreach my $zipfile (@files) {
        d "Using file $zipfile";
        # file exists - could be a new file with the same filename
        # remove it.
        my $filename = '/tmp/'.$zipfile;
        if (-e $filename) {
            unlink $filename; # remove file
        }

        my $content = $zip->contents( $zipfile );

        open (MYFILE, '>>'.$filename);
        print MYFILE $content;
        close (MYFILE);

        $self->ImportXML( $filename, $chd );
        unlink $filename; # remove file
    }
  } else {
    error( "PPS: Unknown file format: $file" );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "PPS: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

  my $rows = $doc->findnodes( "//broadcast" );

  if( $rows->size() == 0 ) {
    error( "PPS: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($year, $month, $day) = ($file =~ /(\d\d\d\d)(\d\d)(\d\d)/);

  if(!defined $year) {
    error( "PPS: $chd->{xmltvid}: Failure to get year from filename" ) ;
    return;
  }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-" . $month . "-" . $day;

  $dsh->StartBatch( $batchid , $chd->{id} );
  ## END

  my $currdate = "x";

  foreach my $row ($rows->get_nodelist) {
    my $start = $self->create_dt($row->findvalue( 'time' ));
    my $end   = $self->create_dt($row->findvalue( 'endtime'  ));

    my $date = $start->ymd("-");
    if($date ne $currdate ) {
      $dsh->StartDate( $date , "06:00" );
      $currdate = $date;

      progress("PPS: Date is: $date");
    }

    my $title         = $row->findvalue( 'title' );
    my $title_org     = $row->findvalue( 'origtitle' );
    my $desc          = $row->findvalue( 'text' );
    my $subtitle      = $row->findvalue( 'subtitle' );
    my $subtitle_org  = $row->findvalue( 'origsubtitle' );
    my $year          = $row->findvalue( 'year' );
    my $dirs          = $row->findvalue( 'director' );
    my $wris          = $row->findvalue( 'writer' );
    my $hdtv          = $row->findvalue( 'hdtv' );
    my $wscreen       = $row->findvalue( 'wscreen' );
    my $stereo        = $row->findvalue( 'stereo' );
    my $dolbydig      = $row->findvalue( 'dolbydig' );
    my $duration      = $row->findvalue( 'duration' );
    my $music         = $row->findvalue( 'music' );
    my $country       = $row->findvalue( 'country' );

    # Clean these up so they can be matched towards TVDB
    $desc =~ s/^\((.*?)\)//;
    $subtitle =~ s/\// \/ /g;
    $subtitle =~ s/\s+\s+/ /g;
    $subtitle_org =~ s/\// \/ /g;
    $subtitle_org =~ s/\s+\s+/ /g;

    # Clean these up so they can be matched towards TVDB
    $title =~ s/÷/-/g;
    $title_org =~ s/÷/-/g;
    $subtitle =~ s/÷/-/g;
    $subtitle_org =~ s/÷/-/g;

    my $ce = {
      channel_id => $chd->{id},
      title => norm($title),
      start_time => $start->ymd("-") . " " . $start->hms(":"),
      end_time   => $end->ymd("-")   . " " . $end->hms(":"),
      description => norm($desc),
    };

    if($year =~ /(\d\d\d\d)/ )
    {
        $ce->{production_date} = "$1-01-01";
    }

    my ($episode, $season);
    if($subtitle and ( $season, $episode ) = ($subtitle =~ m|\((\d+)\): Ep (\d+)$| ) ){
        $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
        $subtitle = "";
    }elsif($subtitle and ( $episode ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
        $ce->{episode} = ' . ' . ($episode - 1) . ' .';
        $subtitle = "";
    }

    $ce->{subtitle} = norm($subtitle) if $subtitle and norm($subtitle) ne "";
    $ce->{original_subtitle} = norm($subtitle_org) if defined($subtitle_org) and defined($ce->{subtitle}) and $ce->{subtitle} ne norm($subtitle_org) and norm($subtitle_org) ne "";
    $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

    # Directors
    $dirs =~ s/, /;/g;
    $dirs =~ s/\//;/g;
    $ce->{directors} = norm($dirs) if $dirs and $dirs ne "";

    # Writers
    $wris =~ s/, /;/g;
    $wris =~ s/\//;/g;
    $ce->{writers} = norm($wris) if $wris and $wris ne "";

    # Actors and producers
    ParseCredits( $ce, 'actors',  $row, 'actor' );
    ParseCredits( $ce, 'producers',  $row, 'funct[function="producer"]/functname' );

    if ($hdtv eq 'hdtv') {
      $ce->{quality} = 'HDTV';
    }

    if ($wscreen eq '16:9') {
      $ce->{aspect} = '16:9';
    }

    if ($stereo eq 'st') {
      $ce->{stereo} = 'stereo';
    }

    if ($dolbydig eq 'dbdig') {
      $ce->{stereo} = 'surround';
    }

    if($music and $music ne "" and (!$subtitle or $subtitle eq "")) {
        $ce->{program_type} = "movie";
    } else {
        $ce->{program_type} = "series";
    }

    my @conts = split(/,|\//, norm($country));
    my @countries;

    foreach my $c (@conts) {
        my ( $c2 ) = $self->{datastore}->LookupCountry( "KFZ", norm($c) );
        push @countries, $c2 if defined $c2;
    }

    if( scalar( @countries ) > 0 )
    {
        $ce->{country} = join "/", @countries;
    }

    # Add it
    $ds->AddProgrammeRaw( $ce );
    progress("$start - $title");
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    if($field eq "actor") {
        my $person = norm($node->findvalue( 'actorname' ));

        if($node->findvalue( 'role' ) ne "") {
            $person .= " (".norm($node->findvalue( 'role' )).")";
        }

        if( $person ne '' ) {
          push( @people, split( '&', $person ) );
        }
    } else {
        my $person = norm($node->string_value());
        if( $person ne '' ) {
          push( @people, split( '&', $person ) );
        }
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}


sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ';', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ';', @people );
    }
  }
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  my( $date, $time ) = split( ' ', $str );

  if( not defined $time )
  {
    return undef;
  }

  my( $year, $month, $day ) = split( '-', $date );
  my( $hour, $minute, $second ) = split( ":", $time );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Stockholm',
                          );

 $dt->set_time_zone( "UTC" );

  return $dt;
}

1;