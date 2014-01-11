package NonameTV::Importer::Instore;

use strict;
use warnings;

=pod

Importer for data from Instore Brodcast.
One file per channel and day downloaded from their site.
The downloaded file is in xml-format.

Channels: OUTTV

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;
use Math::Round 'nearest';

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{UrlRoot} = "http://login.instorebroadcast.com/previews/outtv/Webadvance/" if !defined( $self->{UrlRoot} );

    $self->{datastore}->{augment} = 1;

  	my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $dt = DateTime->now(time_zone => "local")->subtract( days => 1);
  my $date = $dt->ymd;

  my( $year, $month, $day ) = ( $date =~ /(\d+)-(\d+)-(\d+)$/ );

  my $url = $self->{UrlRoot} . $day . '.' . $month . '.' .
    $chd->{grabber_info} . '.xml';

  return( $url, undef );
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref =~ '<!--' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//broadcastingprogramm" );

  if( $ns->size() == 0 ) {
    return (undef, "No data found" );
  }

  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;


  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//broadcast" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }

  my $currdate = "x";

  foreach my $sc ($ns->get_nodelist)
  {
    my $start = $self->create_dt( $sc->findvalue( './date' ) . " " . $sc->findvalue( './time' ) );
    if( not defined $start )
    {
      w "Invalid starttime '"
          . $sc->findvalue( './date' ) . " " . $sc->findvalue( './time' ) . "'. Skipping.";
      next;
    }

    # Date
    my $date = $start->ymd("-");

	if($date ne $currdate ) {
      	if( $currdate ne "x" ) {
      	#	$dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        print $batchid."\n";

        #$dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("OUTTV: Date is: $date");
    }

    # Data
    my $title   = norm($sc->findvalue( './title'   ));
    $title =~ s/&amp;/&/g; # Wrong encoded char
    my $desc    = norm($sc->findvalue( './text'    ));
    my $genre   = norm($sc->findvalue( './genre'   ));
    my $season  = norm($sc->findvalue( './season'  ));
    my $episode = norm($sc->findvalue( './episode' ));
    my $year	= norm($sc->findvalue( './year'    ));
    my $dir		= norm($sc->findvalue( './producer'));


	my $ce = {
        channel_id 		=> $chd->{id},
        title 			=> $title,
        start_time 		=> $start,
        description 	=> $desc,
        production_date => $year."-01-01",
    };

    progress( "Instore: $chd->{xmltvid}: $start - $title" );

    my($program_type, $category ) = $ds->LookupCat( 'Instore', $genre );
	AddCategory( $ce, $program_type, $category );

	# Episode info in xmltv-format
    if( ($episode ne "0" and $episode ne "") and ( $season ne "0" and $season ne "") )
    {
    	$episode = int $episode;
    	$season  = int $season;
    	$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
    } elsif( $episode ne "0" and $episode ne "" ) {
    	$episode = int $episode;
    	if( defined( $year ) and ($year =~ /(\d\d\d\d)/) ) {
        	$ce->{episode} = sprintf( "%d . %d .", $1-1, $episode-1 );
        } else {
        	$ce->{episode} = sprintf( ". %d .", $episode-1 );
        }
    }

    if($dir ne "") {
    	$ce->{directors} = norm($dir);
    }

	# Add Programme
	$dsh->AddCE( $ce );
  }

  #$dsh->EndBatch( 1 );

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my $addhour = 0;


  my( $date, $time ) = split( ' ', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $day, $month, $year ) = split( '\/', $date );

  # Remove the dot and everything after it.
  $time =~ s/\..*$//;

  my( $hour, $minute, $second ) = split( ":", $time );

  # round the minutes as its in a very odd format.
  $minute = nearest(5, $minute);

  # If minute >= 60 add hour instead
  if($minute >= 60) {
  	$minute = 0;
  	$addhour = 1;
  }


  my $dt = DateTime->new( year => $year,
                          month => $month,
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          time_zone => "Europe/Stockholm",
                          );

  $dt->set_time_zone( "UTC" );


  # add hour
  if($addhour eq 1) {
 	 $dt->add(hours => 1);
 	 $addhour = 0;
  }

  return $dt;
}

1;