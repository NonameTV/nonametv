package NonameTV::Importer::SBSRadio;

use strict;
use utf8;
use warnings;

=pod

Importer for SBS Radio (Mix Megapol, The Voice and more)
The file downloaded is in JSON format.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;
    $self->{NO_DUPLICATE_SKIP} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);
  my( $year, $month, $day ) = split( /-/, $date );
  
  my $url = $self->{UrlRoot} . "/epg/" . $year . $month . $day . "_".$chd->{grabber_info}."_other_PI.xml";

  return( $url, undef );
}


sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref eq '' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub FilterContent {
  my( $self, $cref, $chd ) = @_;

  return( $cref, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  #$$cref = Unicode::String::latin1 ($$cref)->utf8 ();

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $currdate = "x";

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse XML.";
    return 0;
  }

  my $ns = $doc->find( "//programme" );

  if( $ns->size() == 0 ) {
    f "No data found";
    return 0;
  }

  # Each Programme
  foreach my $b ($ns->get_nodelist) {

    # Data
    my $image = $b->findvalue( "imageUrl" );
    my $longtitle = $b->findvalue( "longName" );
    my $shorttitle = $b->findvalue( "mediumName" );
    my $title = $longtitle || $shorttitle;

    my $desc = $b->findvalue( 'longDescription' );

  	# Airings
    my $airings = $b->find( "./location" );

    if( $airings->size() == 0 ) {
        f "No airings found";
        return 0;
    }

    # Each airing
    foreach my $a ($airings->get_nodelist) {

        # Start and so on
        my $start = ParseDateTime( $a->findvalue( './/@time' ) );
        my $time = $start->hms(":");

        my $duration = $a->findvalue( './/@duration' );
        my( $hours ) = ($duration =~ /^PT(\d+)H$/ );

        # Otherwise it will whine
        if( $start->ymd("-") ne $currdate ){
            progress("Date is ".$start->ymd("-"));

            $dsh->StartDate( $start->ymd("-") , "00:00" );
            $currdate = $start->ymd("-");
        }

        # Put everything in a array
        my $ce = {
            channel_id => $chd->{id},
            start_time => $time,
            title => norm($title),
            poster => norm($image),
        };

        # endtime
        if(defined($hours)) {
           my $end = $start->clone->add( hours => $hours ); # Endtime
           $ce->{end_time} = $end->hms(":");
        }

        my $live = $a->findvalue( "./live" );

        # Find live-info
        if( $live eq "true" )
        {
            $ce->{live} = "1";
        }
        else
        {
            $ce->{live} = "0";
        }

        $ce->{description} = norm($desc) if defined $desc and $desc;

        progress($time." $ce->{title}");

        $dsh->AddProgramme( $ce );

    }



  }

  #$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
      );

  return $dt;
}

1;