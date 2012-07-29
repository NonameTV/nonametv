package NonameTV::Importer::Kanal5;

use strict;
use warnings;

# Don't include programs shorter than this.
use constant MIN_PROGRAM_SECONDS => 60;

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;

use NonameTV qw/MyGet/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update verbose/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        'verbose'      => 0,
                        );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    $self->{MaxWeeks} = 52 unless defined $self->{MaxWeeks};

    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;
  
  my $ds = $self->{datastore};

  my $sth = $ds->Iterate( 'channels', { grabber => 'kanal5' },
                          qw/id grabber_info xmltvid/ )
     or die "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    my $dt = DateTime->today->set_time_zone( 'Europe/Stockholm' );

    my( $content, $code );
    my $weeks = 0;

    do
    {
      $weeks ++;

      my $batch_id = $data->{xmltvid} . "_" . $dt->week_year . '-' . 
        $dt->week_number;

      print "Fetching listings for $batch_id\n"
        if( $p->{verbose} );

      ( $content, $code ) = $self->FetchData( $batch_id, $data );
            
      if ( defined( $content ) and
           ($p->{'force-update'} or ($code) ) )
      {
        print "Processing listings for $batch_id\n"
          if $p->{verbose};

        my $xml = XML::LibXML->new;
        my $doc;
        eval { $doc = $xml->parse_string($content); };
        if( $@ ne "" )
        {
          print STDERR "$batch_id Failed to parse\n";
          goto nextDay;
        }

        # Find all "TRANSMISSION"-entries.
        my $ns = $doc->find( "//TRANSMISSION" );

        if( $ns->size() == 0 )
        {
          print STDERR "$batch_id: No programme entries found.\n";
          next;
        }

        $ds->StartBatch( $batch_id );

        foreach my $tm ($ns->get_nodelist)
        {
          # Sanity check. 
          # What does it mean if there are several transmissionparts?
          die "Wrong number of transmissionparts for transmission " .
            $tm->findvalue( '@oid' )
            if( $tm->findvalue( 'count(.//TRANSMISSIONPART)' ) ) != 1;
          
          my $tm_p = 
            ($tm->find( '(.//TRANSMISSIONPART)[1]' )->get_nodelist)[0];
          
          my $title =$tm->findvalue(
            './/PRODUCTTITLE[.//PSIPRODUCTTITLETYPE/@oid="131708570"][1]/@title');
          
          if( $title =~ /^\s*$/ )
          {
            # Some entries lack a title. 
            # Fallback to the title in the TRANSMISSION-tag.
            $title = $tm->findvalue( '@title' );
          }
          
          my $startdate = $tm_p->findvalue( './/start[1]/TIMEINSTANT[1]/@date'
                                            );
          my $starttime = $tm_p->findvalue( './/start[1]/TIMEINSTANT[1]/@time'
                                            );
          my $start = create_dt( $startdate, $starttime );
          
          my $enddate = $tm_p->findvalue( './/end[1]/TIMEINSTANT[1]/@date' );
          my $endtime = $tm_p->findvalue( './/end[1]/TIMEINSTANT[1]/@time' );
          my $end = create_dt( $enddate, $endtime );

          round_dt( $start );
          round_dt( $end );

          my $description = $tm->findvalue( './/shortdescription[1]' );

          my $category = $tm->findvalue( './/CATEGORY/@name' );

          if( $end->subtract_datetime_absolute( $start )->delta_seconds 
              < MIN_PROGRAM_SECONDS )
          {
            # This program is too short. Skip it.
            next;
          }

          if( $title eq "natt 5:an" )
          {
            # This show has the wrong stop-time a lot of the time.
            # Skip it.
            next;
          }

          if( $title =~ /^\s*$/ )
          {
            # No title. Skip it.
            next;
          }

          $ds->AddProgramme( {
            channel_id  => $data->{id},
            title       => norm($title),
            description => norm($description),
            start_time  => $start->ymd("-") . " " . $start->hms(":"),
            end_time    => $end->ymd("-") . " " . $end->hms(":"),
#            episode_nr => $inrow->{'episode nr'},
#            season_nr => $inrow->{'Season number'},
#            Bline => $inrow->{'B-line'},
#            Category => $inrow->{'Category'},
#            Genre => $inrow->{'Genre'},
          } );            
        }
        
        $ds->EndBatch( 1 );
      nextDay:
      }  
       
      $dt = $dt->add( days => 7 );

    } while( defined( $content ) and ($weeks <= $self->{MaxWeeks}));
  }

  $sth->finish();

}

sub create_dt
{
  my( $date, $time ) = @_;
  
  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  my $dayadd = 0;
  
  if( $hour > 23 )
  {
    $hour -= 24;
    $dayadd = 1;
  }
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->add( days => $dayadd ) if $dayadd;
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub round_dt
{
  my( $dt ) = @_;

  my $sec  = $dt->second;
  my $min = $dt->min;

  my $newmin = floor((($min*60 + $sec) / 60 / 5) + 0.5) * 5;
  $dt->set( second => 0 );
  if( $min != $newmin )
  {
    $dt->add( minutes => $newmin-$min );
  }
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ($batch_id =~ /_20(\d+)-(\d+)/);

  my $url = sprintf( "%stab%02d%02d.xml", $self->{UrlRoot}, $week, $year );

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $str ) = @_;

    return "" if not defined( $str );

    $str = Utf8Conv( $str );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
