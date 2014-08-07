package NonameTV::Importer::OKV;

use strict;
use warnings;

=pod

Importer for OKV (Öppna Kanalen Växjö).
The file downloaded is a XML-file and provides data for
one week.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;
use Math::Round 'nearest';

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{augment} = 1;

  	my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;

  	$self->{MaxDays} = 8;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);

  my $url = 'http://okv.se/tabla.xml/'.$date;

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
  my $ns = $doc->find( "//programtable" );

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
  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 )
  {
    f "No data found 2";
    return 0;
  }

  my $currdate = "x";

  foreach my $sc ($ns->get_nodelist)
  {
    my $start = $self->create_dt( $sc->findvalue( './datum' ) . " " . $sc->findvalue( './time' ) );
    if( not defined $start )
    {
      w "Invalid starttime '"
          . $sc->findvalue( './datum' ) . " " . $sc->findvalue( './time' ) . "'. Skipping.";
      next;
    }

    # Date
    my $date = $start->ymd("-");

	if($date ne $currdate ) {
      	if( $currdate ne "x" ) {
      	#	$dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        #print $batchid."\n";

        #$dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("OKV: Date is: $date");
    }

    # Data
    my $title    = norm($sc->findvalue( './title'   ));
    $title       =~ s/&amp;/&/g; # Wrong encoded char
    my $desc     = norm($sc->findvalue( './description'    ));
    my $year     = norm($sc->findvalue( './year'    ));
    my $duration = norm($sc->findvalue( './duration'    ));
    my $genre    = norm($sc->findvalue( './genre'    ));
    my $end      = $start->clone()->add( minutes => $duration );

	my $ce = {
        channel_id 		=> $chd->{id},
        title 			=> $title,
        start_time 		=> $start,
        description 	=> $desc,
        end_time        => $end,
    };

    my ( $dummy, $dummy2, $episode ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+)$/i ); # bugfix
    if(defined($episode)) {
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    my ( $dummy3, $dummy4, $episode2, $ofepisodes ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+) av (\d+)$/i ); # bugfix
    if(defined($episode2)) {
        $ce->{episode} = sprintf( ". %d/%d .", $episode2-1, $ofepisodes );
    }

    my ( $dummy5, $dummy6, $episode3, $subtitle ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+)\: (.*)$/i ); # bugfix
    if(defined($episode3)) {
        $ce->{episode} = sprintf( ". %d .", $episode3-1 );
        $ce->{subtitle} = norm($subtitle);
    }

    my ( $dummy7, $dummy8, $episode4, $ofepisodes2 ) = ($title =~ /(,|) (del|avsnitt|akt|vecka) (\d+) \(av (\d+)\)$/i ); # bugfix
    if(defined($episode4)) {
        $ce->{episode} = sprintf( ". %d/%d .", $episode4-1, $ofepisodes2 );
    }

    # Clean title
    $title =~ s/, vecka (\d+)//;
    $title =~ s/, avsnitt (\d+) av (\d+)//;
    $title =~ s/, del (\d+) av (\d+)//;
    $title =~ s/, avsnitt (\d+)\: (.*)//;
    $title =~ s/, del (\d+)\: (.*)//;
    $title =~ s/, avsnitt (\d+)//;
    $title =~ s/, del (\d+)//;
    $title =~ s/, akt (\d+) \(av (\d+)\)//;
    $title =~ s/, akt (\d+)//;
    $title =~ s/ avsnitt (\d+) av (\d+)//;
    $title =~ s/ del (\d+) av (\d+)//;
    $title =~ s/ avsnitt (\d+)\: (.*)//;
    $title =~ s/ del (\d+)\: (.*)//;
    $title =~ s/ avsnitt (\d+)//;
    $title =~ s/ del (\d+)//;

    my ( $subtitle2 ) = ($title =~ /\: (.*)$/i ); # bugfix
    if(defined($subtitle2)) {
        $ce->{subtitle} = norm($subtitle2);
    }

    $title =~ s/\: (.*)$//;

    # norm it and replace it
    $ce->{title} = norm($title);

    # Genre
    if($genre ne "") {
        my($program_type, $category ) = $ds->LookupCat( 'OKV', $genre );
        AddCategory( $ce, $program_type, $category );
    }

    progress( "OKV: $chd->{xmltvid}: $start - $title" );

    # year
    if($year =~ /(\d\d\d\d)/) {
	  $ce->{production_date} = "$1-01-01";
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


  my( $date, $time ) = split( ' ', $str );

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '\-', $date );

  # Remove the dot and everything after it.
  $time =~ s/\..*$//;

  my( $hour, $minute, $second ) = split( ":", $time );


  my $dt = DateTime->new( year => $year,
                          month => $month,
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          time_zone => "Europe/Stockholm",
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;