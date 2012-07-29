package NonameTV::Importer::Cinemax;

use strict;
use warnings;

=pod

Importer for data from Cinemax Classic music channel. 
One file per month downloaded from LNI site.
The downloaded file is in xls format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use HTML::TableExtract;
use HTML::Parse;
use HTML::FormatText;
use Encode qw/decode encode/;

use NonameTV qw/MyGet norm/;
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

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} , "Europe/Zagreb" );
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

  if( $file =~ /\.html$/i ){
    $self->ImportHTML( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportHTML
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress("Cinemax: $channel_xmltvid: processing HTML/XLS file $file");

  # get year and month from filename
  my( $year, $month ) = ( $file =~ /Cinemax(\d{4})(\d{2})\.html$/ );

  my $te = HTML::TableExtract->new(
           #headers => [qw(TID TITTEL)],
           keep_html => 1
  );

  #$te->parse($$cref);
  $te->parse_file($file);

  my $table = $te->first_table_found();

  my $date;
  my $currdate = "x";

  foreach my $row ($table->rows) {

    my $col;

    #
    # column 0: date
    #
    $col = @$row[0];
    if( isDate( $col ) ){

      $date = ParseDate( $col, $year, $month );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Cinemax: $channel_xmltvid: Date is: $date");
      }
    }

    #
    # column 1: time
    #
    $col = @$row[1];
    next if( ! $col );
    next if( $col !~ /^\d{2}:\d{2}$/ );
    my $time = $col;

    #
    # column 2: title
    #
    $col = @$row[2];
    next if( ! $col );
    my $title = $col;

    eval{ $title = decode( "iso-8859-2", $title ); };

    #
    # column 3: length
    #
    $col = @$row[3];
    my $length = $col;

    progress("Cinemax: $channel_xmltvid: $time - $title");

    my $ce = {
      channel_id => $channel_id,
      start_time => $time,
      title => $title,
    };

    $dsh->AddProgramme( $ce );

  }

  $dsh->EndBatch( 1 );

  return;
}

sub isDate
{
  my( $text ) = @_;

  if( $text =~ /^&nbsp;\d+$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $dateinfo, $year, $month ) = @_;

  my( $day ) = ( $dateinfo =~ /^&nbsp;(\d+)$/ );

  sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub UpdateFiles {
  my( $self ) = @_;

  # the url to fetch data from
  # is in the format http://www.cinemax-tv.com/WebServices/DownloadSchedule.aspx?CountryId=CRO&Year=2008&Month=11&ChannelId=CMAX
  # UrlRoot = http://www.cinemax-tv.com/WebServices/DownloadSchedule.aspx
  # GrabberInfo = CMAX or CMAX2

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      my $filename = "Cinemax" . sprintf( "%04d%02d", $dt->year, $dt->month ) . ".html";

      my $url = $self->{UrlRoot} . "/?CountryId=CRO&Year=" . $dt->year . "&Month=" . $dt->month . "&ChannelId=" . $data->{grabber_info};
      progress("Cinemax: Fetching html file from $url");

      url_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );
    }
  }
}

sub url_get {
  my( $url, $file ) = @_;

  my( $content, $code ) = MyGet( $url );

  open (FILE,">$file");
  print FILE $content;
  close (FILE);
}

1;
