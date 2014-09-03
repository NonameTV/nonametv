package NonameTV::Importer::HBONordic;

use strict;
use warnings;

=pod

Importer for data from HBO Nordic.
The data is their XMLTV-data which is downloaded daily (per day).

Features:

=cut

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;
use NonameTV::DataStore::Helper;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{datastore}->{augment} = 1;

  	my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;

    return $self;
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );

  my $dt = DateTime->new( year      => $year,
                            month     => $month,
                            day       => $day,
                            hour      => 7,
                            );
  #$dt->set_time_zone( "UTC" );

  my $tz = DateTime::TimeZone->new( name => 'Europe/Stockholm' );
  my $dst = $tz->is_dst_for_datetime( $dt );

  # DST removal thingy
  my $url;

  if($dst) {
    $url = 'http://www.hbonordic.tv/epg/HBON-Schedule-XMLTV-'.$year.'_'.$month.'_'.$day.'T020000Z.xml';
  } else {
    $url = 'http://www.hbonordic.tv/epg/HBON-Schedule-XMLTV-'.$year.'_'.$month.'_'.$day.'T030000Z.xml';
  }

  return( $url, undef );
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }

  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );

  foreach my $sc ($ns->get_nodelist)
  {

    my($title, $subtitle, $desc, $title_org) = undef;


    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = $self->create_dt( $sc->findvalue( './@stop' ) );
    if( not defined $end )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }

    #
    # title
    #
    foreach my $t ($sc->getElementsByTagName('title'))
    {
        if($t->findvalue( './@lang' ) eq $chd->{grabber_info}) {
            $title = norm($t->textContent());
        }

        if($t->findvalue( './@lang' ) eq "en") {
            $title_org = norm($t->textContent());
        }
    }
    if( not defined $title or !length($title) )
    {
       error( "$batch_id: Invalid title '" . $sc->findvalue( './@title' ) . "'. Skipping." );
       next;
    }



    #
    # subtitle
    #
    foreach my $s ($sc->getElementsByTagName('sub-title'))
    {
       if($s->findvalue( './@lang' ) eq $chd->{grabber_info}) {
            $subtitle  = norm($s->textContent());
       }
    }


    #
    # description
    #
    foreach my $d ($sc->getElementsByTagName('desc'))
    {
       if($d->findvalue( './@lang' ) eq $chd->{grabber_info}) {
        $desc = norm($d->textContent());
       }
    }

    #
    # genre
    #
    my $genre = $sc->getElementsByTagName('category');

    #
    # episode number
    #
    my $episode = undef;
    my( $ep_se, $ep_nr ) = undef;
    if( $sc->getElementsByTagName( 'episode-num' ) ){
      ( $ep_se, $ep_nr ) = split( ':', $sc->getElementsByTagName( 'episode-num' ) );
      $ep_se = int $ep_se;
      $ep_nr = int $ep_nr;
    }
    if( $ep_nr ){
      if( ($ep_nr > 0) and ($ep_se > 0) )
      {
        $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
      }
      elsif( $ep_nr > 0 )
      {
        $episode = sprintf( ". %d .", $ep_nr-1 );
      }
    }

    # The director and actor info are children of 'credits'
    my @actors;
    my @directors;
    foreach my $dir ($sc->getElementsByTagName( 'director' ))
    {
        push(@directors, norm($dir->textContent()));
    }
    foreach my $act ($sc->getElementsByTagName( 'actor' ))
    {
        push(@actors, norm($act->textContent()));
    }




    progress("HBONordic: $chd->{xmltvid}: $start - $title");

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
    };

    $ce->{actors} = join( ";", grep( /\S/, @actors ) );
    $ce->{directors} = join( ";", grep( /\S/, @directors ) );

    if( defined( $subtitle ) and length( $subtitle ) )
    {
      $ce->{subtitle} = norm($subtitle);
    }

    if( defined( $desc ) and length( $desc ) )
    {
      $ce->{description} = norm($desc);
    }

    if( defined( $genre ) and length( $genre ) )
    {
      my($program_type, $category ) = $ds->LookupCat( "HBONordic", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    if( defined( $episode ) and ($episode =~ /\S/) )
    {
      $ce->{episode} = norm($episode);
      $ce->{program_type} = 'series';
    } else {
      $ce->{program_type} = 'movie';
    }

    $ce->{original_title} = norm($title_org) if $ce->{title} ne norm($title_org) and norm($title_org) ne "";

    $ds->AddProgramme( $ce );

  }



  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  my $second = substr( $str , 12 , 2 );
  #my $offset = substr( $str , 15 , 5 );

  if( not defined $year )
  {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

1;
