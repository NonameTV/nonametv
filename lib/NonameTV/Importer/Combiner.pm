package NonameTV::Importer::Combiner;

=pod

Combine several channels into one. Read data from xmltv-files downloaded
via http.

Limitations:

 - No support for different schedules for different days.
 - No support for schedule-periods that span midnight.

=cut 

use strict;
use warnings;


my %channel_data;

=pod 
_Bakgrund:_Discovery Mix är en s k promotion-kanal för Discoverys 5 tv-kanaler: Discovery, Animal Planet, Discovery Civilization, Discovery Sci-Trek och Discovery Travel & Adventure.

Discovery Mix sänder från de olika Discoverykanalernas dagliga program. Discovery Mix plockar det program som visas på respektive kanal vid en fastställd tidpunkt. Det är en 5 minuters paus mellan varje kanalbyte och i två fall pauser på 25 minuter.

Kanalen sänds bara hos Com Hem, som sköter bytet mellan inslagen från de olika kanalerna enligt den tidtabell som Discovery lagt upp.

_Här är tablån för Discovery Mix: _

07.00-09.00 Animal Planet

09.00-09.50 Discovery Travel & Adventure

09.55-10.45 Discovery Sci-Trek

10.50-11.40 Discovery Civilization

11.45-12.35 Discovery Travel & Adventure

PAUS

13.00-15.00 Animal Planet

15.00-15.50 Discovery Travel & Adventure

15.55-16.45 Discovery Sci-Trek

16.50-17.40 Discovery Civilization

17.45-18.35 Discovery Travel & Adventure

PAUS

19.00-21.00 Animal Planet

21.00-01.00 Discovery Channel

=cut

$channel_data{ "nordic.mix.discovery.com" } =
  { 
    "nordic.discovery.com" => 
      [ 
        {
          day => 'all',
          time => "2100-0100",
        },
      ],
    "nordic.animalplanet.discovery.com" =>
      [
        {
          day => 'all',
          time => "0700-0900"
        },
        {
          day => 'all',
          time => "1300-1500"
        },
        {
          day => 'all',
          time => "1900-2100"
        },
      ],
    "nordic.travel.discovery.com" =>
      [
        {
          day => 'all',
          time => "0900-0950",
        },
        {
          day => 'all',
          time => "1145-1235",
        },
        {
          day => 'all',
          time => "1500-1550"
        },
        {
          day => 'all',
          time => "1745-1835",
        },

      ],
    "nordic.science.discovery.com" =>
      [
        {
          day => 'all',
          time => "0955-1045",
        },
        {
          day => 'all',
          time => "1555-1645"
        },
      ],
    "nordic.civilisation.discovery.com" =>
      [
        {
          day => 'all',
          time => "1050-1140",
        },
        {
          day => 'all',
          time => "1650-1740"
        },
      ],
  };

=pod

Barnkanalen och Kunskapskanalen samsänder via DVB-T.
Vad jag vet är det aldrig några överlapp, så jag
inkluderar alla program på båda kanalerna.

=cut

$channel_data{ "svtb-svt24.svt.se" } =
  { 
    "svtb.svt.se" => 
      [ 
        {
          day => 'all',
        },
      ],
    "svt24.svt.se" =>
      [
        {
          day => 'all',
        },
      ],
  };

=pod

Viasat Nature/Crime och Nickelodeon samsänder hos SPA.

=cut

$channel_data{ "viasat-nature-nick.spa.se" } =
  { 
    "nature.viasat.se" => 
      [ 
        {
          day => 'all',
	  time => '1800-0000',
        },
      ],
    "nickelodeon.se" =>
      [
        {
          day => 'all',
	  time => '0600-1800',
        },
      ],
  };

=pod

Cartoon Network/TCM

=cut

$channel_data{ "cntcm.tv.gonix.net" } =
  { 
    "cartoonnetwork.tv.gonix.net" => 
      [ 
        {
          day => 'all',
	  time => '0500-2100',
        },
      ],
    "tcm.tv.gonix.net" =>
      [
        {
          day => 'all',
	  time => '2100-0500',
        },
      ],
  };

=pod

HustlerTV (switched)

=cut

$channel_data{ "hustlertvsw.tv.gonix.net" } =
  { 
    "hustlertv.tv.gonix.net" =>
      [
        {
          day => 'all',
	  time => '2200-0700',
        },
      ],
  };

=pod

ZDFneo / KI.KA switch on ZDFmobil

=cut

$channel_data{ "neokika.zdfmobil.de" } =
  { 
    "kika.de" => 
      [ 
        {
          day => 'all',
	  time => '0600-2100',
        },
      ],
    "neo.zdf.de" =>
      [
        {
          day => 'all',
	  time => '2100-0600',
        },
      ],
  };

use DateTime;
use XML::LibXML;
use Compress::Zlib;

use NonameTV qw/MyGet ParseXmltv/;

use NonameTV::Importer::BaseDaily;

use NonameTV::Log qw/progress error/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxDays} = 32 unless defined $self->{MaxDays};
    $self->{MaxDaysShort} = 2 unless defined $self->{MaxDaysShort};

    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ short-grab/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'quiet'        => 0,
      'short-grab'   => 0,
    };


    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;
  
  NonameTV::Log::SetVerbosity( $p->{verbose}, $p->{quiet} );

  my $maxdays = $p->{'short-grab'} ? $self->{MaxDaysShort} : $self->{MaxDays};

  my $ds = $self->{datastore};

  foreach my $data (@{$self->ListChannels()} ) {
    if( not exists( $channel_data{$data->{xmltvid} } ) )
    {
      die "Unknown channel '$data->{xmltvid}'";
    }

    if( $p->{'force-update'} and not $p->{'short-grab'} )
    {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $start_dt = DateTime->today->subtract( days => 1 );

    for( my $days = 0; $days <= $maxdays; $days++ )
    {
      my $dt = $start_dt->clone;
      $dt=$dt->add( days => $days );

      my $batch_id = $data->{xmltvid} . "_" . $dt->ymd('-');

      my %ch_content;
      my $changed = 0;
      my $error = 0;

      foreach my $chan (keys %{$channel_data{$data->{xmltvid}}})
      {
        my $curr_batch = $data->{xmltvid}. "_" . $chan . "_" . $dt->ymd('-');
        my( $content, $code ) = $self->FetchData( $curr_batch, $data );

        $ch_content{$chan} = $content;
        $changed = 1 if $code;
        $error = 1 if not defined( $content );
      }

      if( ($error==0) and ($p->{'force-update'} or $changed)  )
      {
        progress( "$batch_id: Processing data" );

        # Process the gzipped xml-files into an array of program-
        # entries.
        my %prog;
        foreach my $ch (keys %ch_content)
        {
          my $xmldata = Compress::Zlib::memGunzip( \($ch_content{$ch}) );
          $prog{$ch} = ParseXmltv( \$xmldata );
        }

        my $progs = $self->BuildDay( $batch_id, \%prog, 
                                     $channel_data{$data->{xmltvid}}, $data );
      }
      elsif( $error )
      {
        error( "$batch_id: Failed to fetch data" );
      }
    }
  }
}

sub BuildDay
{
  my $self = shift;
  my( $batch_id, $prog, $sched, $chd ) = @_;

  my $ds =$self->{datastore};

  my @progs;

  my( $channel, $date ) = split( /_/, $batch_id );

  $ds->StartBatch( $batch_id );

  my $date_dt = date2dt( $date );

  foreach my $subch (keys %{$sched})
  {
    foreach my $span (@{$sched->{$subch}}) {
      my $sstart_dt;
      my $sstop_dt;

      if( defined( $span->{time} ) ) {
	my( $sstart, $sstop ) = split( /-/, $span->{time} );
	
	$sstart_dt = changetime( $date_dt, $sstart );
	$sstop_dt = changetime( $date_dt, $sstop );
	if( $sstop_dt lt $sstart_dt ) {

	  # BUG: The algorithm will discard any programs that start after
	  # midnight and matches a span-entry that starts before midnight.
	  # To fix this, we should generate two spans from this entry,
	  # one that spans midnight on the night before this date
	  # and one that spans midnight on the night after this date.

	  $sstop_dt->add( days => 1 );
	}
      }
      else { 
	$sstart_dt = date2dt( "1970-01-01" );
	$sstop_dt = date2dt( "2030-01-01" );
      }

      foreach my $e (@{$prog->{$subch}}) {
	my $pstart_dt = $e->{start_dt}->clone();
	my $pstop_dt = $e->{stop_dt}->clone();
	
	my $partial = 0;
	
	if( $pstart_dt lt $sstart_dt ) {
	  $pstart_dt = $sstart_dt->clone();
	  $partial = 1;
	}
	
	if( $pstop_dt gt $sstop_dt ) {
	  $pstop_dt = $sstop_dt->clone();
	  $partial = 1;
	}
	
	next if $pstart_dt ge $pstop_dt;
	
	my %e2 = %{$e};

	$pstart_dt->set_time_zone( "UTC" );
	$pstop_dt->set_time_zone( "UTC" );

	$e2{start_time} = $pstart_dt->ymd('-') . " " . $pstart_dt->hms(':');
	$e2{end_time} = $pstop_dt->ymd('-') . " " . $pstop_dt->hms(':');
	
	delete( $e2{start_dt} );
	delete( $e2{stop_dt} );

	if( $partial ) {
	  $e2{title} = "(P) " . $e2{title};
	}
	
	$e2{channel_id} = $chd->{id};
	
	$ds->AddProgrammeRaw( \%e2 );
      }
    }
  }
  $ds->EndBatch( 1 );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $id ) = ($batch_id =~ /_(.*)/);

  my $url = $self->{UrlRoot} . $id . '.xml.gz';

  my( $content, $code ) = MyGet( $url );

  if( not defined( $content ) )
  {
    print "$url failed.\n";
  }
  return( $content, $code );
}
    
sub date2dt {
  my( $date ) = @_;

  my( $year, $month, $day ) = split( '-', $date );
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          time_zone => 'Europe/Stockholm',
                          );
}

sub changetime {
  my( $dt, $time ) = @_;

  my( $hour, $minute ) = ($time =~ m/(\d+)(\d\d)/);

  my $dt2 = $dt->clone();

  $dt2->set( hour => $hour,
	    minute => $minute );

  return $dt2;
}

1;
