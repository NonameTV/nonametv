package NonameTV::Importer::MediaTravel;

use strict;
use warnings;

=pod

Importer for data from Mezzo Classic music channel. 
One file per month downloaded from LNI site.
The downloaded file is in xls format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Encode qw(from_to);

use NonameTV qw/MyGet norm AddCategory/;
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

  #defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  #my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  #$self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  #my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  $ds->{SILENCE_END_START_OVERLAP}=1;

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  #my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # there is no date information in the document
  # the first and last dates are known from the file name
  # which is in format 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # as each day is in one worksheet, other days are
  # calculated as the offset from the first one

#return if ( $file !~ /221010/ );
  progress( "FOX XML: $chd->{xmltvid}: Processing XML $file" );

  my $batch_id = $chd->{xmltvid} . "_" . $file;
  $ds->StartBatch( $batch_id , $chd->{id} );
  
  my $doc;
  my $xml = XML::LibXML->new;
  $xml->set_option( "encoding", "utf-16" );
  eval { $doc = $xml->parse_file($file); };
  if( $@ ne "" )
  {
    error( "MediaTravel: $chd->{xmltvid}: Failed to parse $@" );
    return 0;
  }
  
  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  if( $ns->size() == 0 ) {
    error( "MediaTravel: $chd->{xmltvid}: No 'programme' blocks found" ) ;
    return 0;
  }
  progress( "MediaTravel: $chd->{xmltvid}: " . $ns->size() . " programme blocks found" );

  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $start = $sc->findvalue( './@start' );
    if( not defined $start )
    {
      error( "MediaTravel: $chd->{xmltvid}: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # stop time
    #
    my $stop = $sc->findvalue( './@stop' );
    if( not defined $stop )
    {
      error( "MediaTravel: $chd->{xmltvid}: Invalid stoptime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }

    my( $startdate, $starttime ) = ParseDateTime( $start );
    my( $stopdate, $stoptime ) = ParseDateTime( $stop );
    next if( ! $startdate );
    next if( ! $starttime );

    my $title = $sc->findvalue( 'title' );
    next if( ! $title );

    my $genre = $sc->findvalue( 'category' );
    my $description = $sc->findvalue( 'desc' );
    my $url = $sc->findvalue( 'url' );

    progress("MediaTravel: $chd->{xmltvid}: $startdate $starttime - $title");

    my $ce = {
      channel_id => $chd->{id},
      start_time => $startdate . " " . $starttime,
      end_time => $stopdate . " " . $stoptime,
      title => norm($title),
    };

    $ce->{description} = $description if $description;
    $ce->{url} = $url if $url;

#    if( $genre ){
#      my($program_type, $category ) = $ds->LookupCat( "MediaTravel", norm($genre) );
#      AddCategory( $ce, $program_type, $category );
#    }

    $ds->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub ParseDateTime
{
  my( $text ) = @_;

#print "ParseDateTime: >$text<\n";

  my( $year, $month, $day, $hour, $min, $sec ) = ( $text =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/ );

  return( $year . "-" . $month . "-" . $day , $hour . ":" . $min . ":" . $sec );
}

sub UpdateFiles {
  my( $self ) = @_;

return;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format http://www.lni.tv/lagardere-networks-international/uploads/media/MediaTravel.xls
  # UrlRoot = http://www.lni.tv/lagardere-networks-international/uploads/media/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      my ( $filename, $url );

      # format: 'MediaTravel.xls'
      $filename = "MediaTravel" . $dt->month_name . "_" . $dt->strftime( '%y' ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("MediaTravel: $xmltvid: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      # format: 'MediaTravel Schedule November_08.xls'
      $filename = "MediaTravel Schedule " . $dt->month_name . "_" . $dt->strftime( '%y' ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("MediaTravel: $xmltvid: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      # format: 'Mezzo_Schedule_November_2008.xls'
      $filename = "Mezzo_Schedule_" . $dt->month_name . "_" . $dt->strftime( '%Y' ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("MediaTravel: $xmltvid: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      # format: 'MediaTravel Schedule November_2008.xls'
      $filename = "Mezzo Schedule " . $dt->month_name . "_" . $dt->strftime( '%Y' ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("Mezzo: $xmltvid: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );
    }
  }
}

sub ftp_get {
  my( $url, $file ) = @_;

  qx[curl -S -s -z "$file" -o "$file" "$url"];
}

1;
