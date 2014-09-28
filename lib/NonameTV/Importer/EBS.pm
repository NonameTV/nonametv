package NonameTV::Importer::EBS;

use strict;
use warnings;

=pod

Importer for data from EBS New Media.
Channels include: Extreme Sports, CBS Reality, Outdoor Channel HD

Features:

=cut

use DateTime;
use XML::LibXML;
use Data::Dumper;
use POSIX;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;
use NonameTV::DataStore::Helper;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

  	my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;

  	# use augment - this is made for walking.
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = 'http://digigate-exports.ebsnewmedia.com/channel_'.$chd->{grabber_info}.'/schedule.xml';

  return( $url, undef );
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
  #$ds->{SILENCE_END_START_OVERLAP}=1;


  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }

  # Find all "programme"-entries.
  my $ns = $doc->find( "//event" );
  my $currdate = "x";

  foreach my $sc ($ns->get_nodelist)
  {

    my($title, $subtitle, $desc) = undef;
    my $lang = $chd->{sched_lang};

    my $date = $sc->findvalue('.//txDay');
    if($date ne $currdate ) {
        if( $currdate ne "x" ) {
    	#    $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        #$dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("EBS: Date is: $date");
    }


    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue('.//txDay').'T'.$sc->findvalue('.//start') );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue('.//txDay')."T".$sc->findvalue('.//start') . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = $self->create_dt( $sc->getElementsByTagName('txDay').'T'.$sc->findvalue('.//end') );
    if( not defined $end )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue('.//txDay')."T".$sc->findvalue('.//end') . "'. Skipping." );
      next;
    }

    #
    # title
    #
    my $title_eng  = norm($sc->findvalue('.//title'));
    my $title_lang = norm($sc->findvalue('.//title[@lang="'.$lang.'"]'));
    $title = $title_lang || $title_eng;

    if( not defined $title or !length($title) )
    {
       error( "$batch_id: Invalid title '" . $sc->findvalue( './/title' ) . "'. Skipping." );
       next;
    }



    #
    # subtitle
    #
    my $subtitle2_eng = $sc->findvalue('.//EpisodeTitle');
    my $subtitle2_lang = norm($sc->findvalue('.//EpisodeTitle[@lang="'.$lang.'"]'));
    my $subtitle2 = $subtitle2_lang || $subtitle2_eng;
    if(norm($subtitle2) =~ /Serie (\d+), aflevering (\d+)/i) {
        $subtitle2 = undef;
    }
    if (!isdigit($subtitle2)) {
        $subtitle = $subtitle2; # Only set the subtitle if its not a number.
    }


    #
    # description
    #
    my $desc_series = norm($sc->findvalue('.//programmeEPGSynopsis'));
    my $desc_episode = norm($sc->findvalue('.//episodeEPGSynopsis'));
    my $desc_series_lang = norm($sc->findvalue('.//programmeEPGSynopsis[@lang="'.$lang.'"]'));
    my $desc_episode_lang = norm($sc->findvalue('.//episodeEPGSynopsis[@lang="'.$lang.'"]'));

    $desc = $desc_episode_lang || $desc_series_lang || $desc_episode || $desc_series;



    #
    # genre
    #
    my $genre = $sc->findvalue('.//Genre');
    my $subgenre = $sc->findvalue('.//subGenre');

    #
    # episode number
    #
    my $episode = undef;
    my $ep_se = $sc->findvalue('.//Series');
    my $ep_nr = $sc->findvalue('.//EpisodeNum');

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

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->hms(":"),
      end_time     => $end->hms(":"),
      episode      => $episode,
    };

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
      my($program_type, $category ) = $ds->LookupCat( "EBS_Genre", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    if( defined( $subgenre ) and length( $subgenre ) )
    {
        my($program_type, $category ) = $ds->LookupCat( "EBS_subGenre", $subgenre );
        AddCategory( $ce, $program_type, $category );
    }

    $ce->{original_title} = norm($title_eng) if defined($title_eng) and $ce->{title} ne norm($title_eng) and norm($title_eng) ne "";

    $dsh->AddProgramme( $ce );
    progress("EBS: $chd->{xmltvid}: $start - $title");

  }


  #$dsh->EndBatch( 1 );


  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $date, $time ) = split( 'T', $str );

  my( $year, $month, $day ) = split( '-', $date );

  # Remove the dot and everything after it.
  $time =~ s/\..*$//;

  my( $hour, $minute, $second ) = split( ":", $time );


  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,

                          );
#                          time_zone => 'Europe/Stockholm',
  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;
