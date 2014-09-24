package NonameTV::Importer::FOXTV;

use strict;
use warnings;

=pod

Import data from FOX

Channels: FOX (SWEDEN)

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
  my $chanfileid = $chd->{grabber_info};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  } else {
    error( "FOXTV: Unknown file format: $file" );
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
    error( "FOXTV: $file: Failed to parse xml" );
    return;
  } else {
    progress("Processing $file");
  }

  my $currdate = "x";
  my $column;

  my $rows = $doc->findnodes( "//Event" );

  if( $rows->size() == 0 ) {
    error( "FOXTV: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($week, $year);
  ($week, $year) = ($file =~ /wk\s*(\d\d)_(\d\d)/i);
  ($week) = ($file =~ /wk\s*(\d\d)/i) if(!defined $year);

  if(!defined $year) {
    error( "FOXTV: $chd->{xmltvid}: Failure to get year from filename, grabbing current year" ) ;
    $year = (localtime)[5] + 1900;
    #return;
  } else { $year += 2000; }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;

  $dsh->StartBatch( $batchid , $chd->{id} );
  ## END

  foreach my $row ($rows->get_nodelist) {
    my($day, $month, $year, $date);
    my $title = norm($row->findvalue( 'ProgrammeTitle' ) );
    my $title_org = norm($row->findvalue( 'OriginalTitle' ) );

    my $start = $row->findvalue( 'StartTime' );
    ($day, $month, $year) = ($row->findvalue( 'Date' ) =~ /^(\d\d)\/(\d\d)\/(\d\d\d\d)$/);
    $date = $year."-".$month."-".$day;
	if($date ne $currdate ) {
        if( $currdate ne "x" ) {
		#	$dsh->EndBatch( 1 );
        }

        #my $batchid = $chd->{xmltvid} . "_" . $date;
        #$dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("FOXTV: Date is: $date");
    }

    my $hd = norm($row->findvalue( 'HighDefinition' ) );
    my $ws = norm($row->findvalue( 'Formatwidescreen' ) );
    my $yr = norm($row->findvalue( 'YearOfRelease' ));
    my $ep_desc  = norm($row->findvalue( 'episodesynopsis' ) );
    my $se_desc  = norm($row->findvalue( 'seasonsynopsis' ) );
    my $pg_desc  = norm($row->findvalue( 'EPGSynopsis' ) );
    my $subtitle = norm($row->findvalue( 'EpisodeTitle' ) );
    my $ep_num   = norm($row->findvalue( 'EpisodeNumber' ) );
    my $se_num   = norm($row->findvalue( 'SeasonNumber' ) );
    my $of_num   = norm($row->findvalue( 'NumberofepisodesintheSeason' ) );
    my $genre    = norm($row->findvalue( 'Longline' ) );
    my $prodcountry = norm($row->findvalue( 'productioncountry' ) );
    my $actors = $row->findvalue( 'Actors' );
    $actors =~ s/, /;/g;
    $actors =~ s/;$//g;
    my $directors = $row->findvalue( 'Directors' );
    $directors =~ s/, /;/g;
    $directors =~ s/;$//g;

    my $desc = $pg_desc || $ep_desc || $se_desc;

    my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start,
        description => norm($desc)
    };

    if( defined( $yr ) and ($yr =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    # Aspect
    if($ws eq "Yes")
    {
      $ce->{aspect} = "16:9";
    } else {
      $ce->{aspect} = "4:3";
    }

    # HDTV & Actors
    $ce->{quality} = 'HDTV' if ($hd eq 'Yes');
    $ce->{actors} = norm($actors) if($actors ne "" and $actors ne "null");
    $ce->{directors} = norm($directors) if($directors ne "" and $directors ne "null");
    $ce->{subtitle} = norm($subtitle) if defined($subtitle) and $subtitle ne "" and $subtitle ne "null";

    # Episode info in xmltv-format
    if( ($ep_num ne "0" and $ep_num ne "") and ( $of_num ne "0" and $of_num ne "") and ( $se_num ne "0" and $se_num ne "") )
    {
        $ce->{episode} = sprintf( "%d . %d/%d .", $se_num-1, $ep_num-1, $of_num );
    }
    elsif( ($ep_num ne "0" and $ep_num ne "") and ( $of_num ne "0" and $of_num ne "") )
    {
      	$ce->{episode} = sprintf( ". %d/%d .", $ep_num-1, $of_num );
    }
    elsif( ($ep_num ne "0" and $ep_num ne "") and ( $se_num ne "0" and $se_num ne "") )
    {
        $ce->{episode} = sprintf( "%d . %d .", $se_num-1, $ep_num-1 );
    }
    elsif( $ep_num ne "0" and $ep_num ne "" )
    {
        $ce->{episode} = sprintf( ". %d .", $ep_num-1 );
    }

    my ( $program_type, $category ) = $self->{datastore}->LookupCat( "FOXTV", $genre );
    AddCategory( $ce, $program_type, $category );

    my ( $country ) = $self->{datastore}->LookupCountry( "FOXTV", $prodcountry );
    AddCountry( $ce, $country );

    # Original title
    $title_org =~ s/(Series |Y)(\d+)$//i;
    $title_org =~ s/$se_num//i;
    if(defined($title_org) and norm($title_org) =~ /, The$/i)  {
        $title_org =~ s/, The//i;
        $title_org = "The ".norm($title_org);
    }
    $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

    progress( "FOXTV: $chd->{xmltvid}: $start - $title" );
    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return 1;
}

1;