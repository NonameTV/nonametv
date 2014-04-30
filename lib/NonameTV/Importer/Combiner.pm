package NonameTV::Importer::Combiner;

=pod

Combine several channels into one. Read data from xmltv-files downloaded
via http.

Configuration:
  - day is either 'all' or '<one>'
    with lower case english two letter day names (mo, tu, we, th, fr, sa, su)
    or numbers with 1 being monday
    see http://search.cpan.org/dist/DateTime-Event-Recurrence/lib/DateTime/Event/Recurrence.pm
  - time is either '<hhmm>-<hhmm>' in local time (FIXME which one??) or left empty for all day aka '0000-0000' (in local time!)

Todo:
  - where to store the time zone of each schedule?
    grabber_info looks like the best place for it

Bugs:
  - a 12 hour nonstop program with a channel switch every hour doesn't work

=cut 

use strict;
use warnings;


my %channel_data;

=pod 
_Bakgrund:_Discovery Mix �r en s k promotion-kanal f�r Discoverys 5 tv-kanaler: Discovery, Animal Planet, Discovery Civilization, Discovery Sci-Trek och Discovery Travel & Adventure.

Discovery Mix s�nder fr�n de olika Discoverykanalernas dagliga program. Discovery Mix plockar det program som visas p� respektive kanal vid en fastst�lld tidpunkt. Det �r en 5 minuters paus mellan varje kanalbyte och i tv� fall pauser p� 25 minuter.

Kanalen s�nds bara hos Com Hem, som sk�ter bytet mellan inslagen fr�n de olika kanalerna enligt den tidtabell som Discovery lagt upp.

_H�r �r tabl�n f�r Discovery Mix: _

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

Barnkanalen och Kunskapskanalen sams�nder via DVB-T.
Vad jag vet �r det aldrig n�gra �verlapp, s� jag
inkluderar alla program p� b�da kanalerna.

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

Viasat Nature/Crime och Nickelodeon sams�nder hos SPA.

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

=pod

TV4 Film and TV4 Fakta is airing in different times on Boxer
TV4 Film:  Friday 21:00 - Monday 08:00
TV4 Fakta: Monday 08:00 - Friday 21:00

=cut

$channel_data{ "tv4film.boxer.se" } =
  {
    "film.tv4.se" =>
	[
          {
             day => 'fr',
             time => '2100-0100',
          },
          {
             day => 'sa',
          },
          {
             day => 'su',
          },

          {
          	 day => 'mo',
          	 time => '0000-0800',
          },
	],
    };

$channel_data{ "tv4fakta.boxer.se" } =
  {
    "fakta.tv4.se" =>
	[
        {
          day => 'mo',
	  time => '0800-0100',
        },
        {
          day => 'tu',
        },
        {
          day => 'we',
        },
        {
          day => 'th',
        },
        {
          day => 'fr',
	  time => '0000-2100',
        },
	],
    };

=pod

C More Sport/SF-Kanalen

=cut

$channel_data{ "sport-sf.cmore.se" } =
  {
    "sf-kanalen.cmore.se" =>
	[
	  {
	     day => 'mo',
	     time => '0100-1800',
	  },
	  {
             day => 'tu',
             time => '0100-1800',
          },
          {
             day => 'we',
             time => '0100-1800',
          },
          {
             day => 'th',
             time => '0100-1800',
          },
          {
             day => 'fr',
             time => '0100-1800',
          },
          {
             day => 'sa',
             time => '0100-1200',
          },
          {
             day => 'su',
             time => '0100-1200',
          },
	],
   "sport.cmore.se" =>
	[
          {
             day => 'mo',
             time => '1800-0100',
          },
          {
             day => 'tu',
             time => '1800-0100',
          },
          {
             day => 'we',
             time => '1800-0100',
          },
          {
             day => 'th',
             time => '1800-0100',
          },
          {
             day => 'fr',
             time => '1800-0100',
          },
          {
             day => 'sa',
             time => '1200-0100',
          },
          {
             day => 'su',
             time => '1200-0100',
          },
        ],
    };

=pod

ARTE / EinsExtra on ARD national mux from HR

=cut

$channel_data{ "arteeinsextra.ard.de" } =
  { 
    "arte.de" => 
      [ 
        {
          day => 1,
	  time => '0000-0300',
        },
        {
          day => 1,
	  time => '1400-0300',
        },
        {
          day => 2,
	  time => '1400-0300',
        },
        {
          day => 3,
	  time => '1400-0300',
        },
        {
          day => 4,
	  time => '1400-0300',
        },
        {
          day => 5,
	  time => '1400-0300',
        },
        {
          day => 'sa',
	  time => '0800-0000',
        },
        {
          day => 'su',
        },
      ],
    "eins-extra.ard.de" =>
      [
        {
          day => 'mo',
	  time => '0300-1400',
        },
        {
          day => 'tu',
	  time => '0300-1400',
        },
        {
          day => 'we',
	  time => '0300-1400',
        },
        {
          day => 'th',
	  time => '0300-1400',
        },
        {
          day => 'fr',
	  time => '0300-1400',
        },
        {
          day => 'sa',
	  time => '0300-0800',
        },
      ],
  };

=pod

Nickelodeon Germany / Comedy Central. The share the same channel and do not overlap.

=cut

$channel_data{ "nickcc.mtvnetworks.de" } =
  { 
    "nick.de" => 
      [ 
        {
          day => 'all',
        },
      ],
    "comedycentral.de" =>
      [
        {
          day => 'all',
        },
      ],
  };

$channel_data{ "ch.nickcc.mtvnetworks.de" } =
  { 
    "nick.ch" => 
      [ 
        {
          day => 'all',
        },
      ],
    "comedycentral.ch" =>
      [
        {
          day => 'all',
        },
      ],
  };

=pod

NRK3 and NRK Super TV shares the same slot so the programmes dont overlap.for

=cut

$channel_data{ "nrk3super.nrk.no" } =
  {
    "nrk3.nrk.no" =>
      [
        {
          day => 'all',
        },
      ],
    "supertv.nrk.no" =>
      [
        {
          day => 'all',
        },
      ],
  };


=pod

RBB branches out at 1930 to Berlin/Brandenburg specific schedules

=cut

$channel_data{ "berl.rbb-online.de" } =
  { 
    "rbb.rbb-online.de" => 
      [ 
        {
          day => 'all',
        },
      ],
    "rbbberl.rbb-online.de" =>
      [
        {
          day => 'all',
        },
      ],
  };
$channel_data{ "bra.rbb-online.de" } =
  { 
    "rbb.rbb-online.de" => 
      [ 
        {
          day => 'all',
        },
      ],
    "rbbbra.rbb-online.de" =>
      [
        {
          day => 'all',
        },
      ],
  };



use DateTime;
use DateTime::Event::Recurrence;

use NonameTV::Importer::BaseDaily;

use NonameTV::Log qw/d p w/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxDays} = 32 unless defined $self->{MaxDays};
    $self->{MaxDaysShort} = 2 unless defined $self->{MaxDaysShort};

    if( defined( $self->{UrlRoot} ) ) {
      w( 'UrlRoot is deprecated as we read directly from our database now.' );
    }

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
      p( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $start_dt = DateTime->today->subtract( days => 1 );

    for( my $days = 0; $days <= $maxdays; $days++ )
    {
      my $dt = $start_dt->clone;
      $dt=$dt->add( days => $days );

      my $batch_id = $data->{xmltvid} . "_" . $dt->ymd('-');

      my $gotcontent = 0;
      my %prog;

      foreach my $chan (keys %{$channel_data{$data->{xmltvid}}})
      {
        my $curr_batch = $chan . "_" . $dt->ymd('-');
        my $content = $ds->ParsePrograms( $curr_batch );

        $prog{$chan} = $content;
        $gotcontent = 1 if $content;
      }

      if( $gotcontent )
      {
        p( "$batch_id: Processing data" );

        my $progs = $self->BuildDay( $batch_id, \%prog, 
                                     $channel_data{$data->{xmltvid}}, $data );
      }
      else
      {
        w( "$batch_id: Failed to fetch data" );
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
    # build spanset of schedule times
    my $sspan = DateTime::SpanSet->empty_set ();

    foreach my $span (@{$sched->{$subch}}) {
      my $weekly;
      if (($span->{day}) && ($span->{day} ne 'all')) {
        d( 'handling specific days schedule' );
        $weekly = DateTime::Event::Recurrence->weekly (
          days => $span->{day},
        );
      } else {
        # progress ("handling all days schedule");
        $weekly = DateTime::Event::Recurrence->daily;
      }

      my $iter = $weekly->iterator (
        start => $date_dt->clone->add (days => -1),
        end => $date_dt->clone->add (days => 1)
      );
      while ( my $date_dt = $iter->next ) {
        # progress ("adding schedules for $date_dt to spanset");
        my $sstart_dt;
        my $sstop_dt;

        if( defined( $span->{time} ) ) {
          my( $sstart, $sstop ) = split( /-/, $span->{time} );
	
	  $sstart_dt = changetime( $date_dt, $sstart );
	  $sstop_dt = changetime( $date_dt, $sstop );
	  if( $sstop_dt lt $sstart_dt ) {
	    $sstop_dt->add( days => 1 );
          }
        } else { 
	  $sstart_dt = changetime( $date_dt, '0000' );
	  $sstop_dt = $sstart_dt->clone->add ( days=> 1);
        }

        # progress ("span from $sstart_dt until $sstop_dt");

        $sspan = $sspan->union (
          DateTime::SpanSet->from_spans (
            spans => [DateTime::Span->from_datetimes (
              start => $sstart_dt,
              before => $sstop_dt
            )]
          )
        );
      }
    }

    $sspan->set_time_zone ("Europe/Berlin");
    $sspan->set_time_zone ("UTC");

    # now that we have a spanset containing all spans
    # that should be included it gets easy

    foreach my $e (@{$prog->{$subch}}) {
      # programme span
      my $pspan = DateTime::Span->from_datetimes (
        start => $e->{start_dt},
        before => $e->{stop_dt}
      );
      $pspan->set_time_zone ("UTC");

      # continue with next programme if there is no match
      next if (!$sspan->intersects ($pspan));

      # copy programme
      my %e2 = %{$e};
      # always update the time
      my $ptspan = $sspan->intersection( $pspan );
      $e2{start_dt} = $ptspan->min;
      $e2{stop_dt} = $ptspan->max;

      # partial programme
      if (!$sspan->contains ($pspan)) {
        $e2{title} = "(P) " . $e2{title};
      }

      $e2{start_time} = $e2{start_dt}->ymd('-') . " " . $e2{start_dt}->hms(':');
      delete $e2{start_dt};
      $e2{end_time} = $e2{stop_dt}->ymd('-') . " " . $e2{stop_dt}->hms(':');
      delete $e2{stop_dt};
      d ("match $e2{title} at $e2{start_time} or " . $pspan->min);

      $e2{channel_id} = $chd->{id};

      $ds->AddProgrammeRaw( \%e2 );
    }
  }
  $ds->EndBatch( 1 );
}

sub FetchDataFromSite
{
  return( '', undef );
}
    
sub date2dt {
  my( $date ) = @_;

  my( $year, $month, $day ) = split( '-', $date );
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
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
