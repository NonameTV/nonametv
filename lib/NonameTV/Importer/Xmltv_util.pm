package NonameTV::Importer::Xmltv_util;

use strict;
use warnings;

=pod

Importer for data for various Xmltv sites.

=cut

use DateTime;
use XML::LibXML;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/progress error p w/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ParseData/;
}
our @EXPORT_OK;

sub ParseData
{
  my( $batch_id, $cref, $chd, $ds ) = @_;

  $ds->{SILENCE_END_START_OVERLAP}=1;
#  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
  my $doc;
  eval { $doc = ParseXml ($cref); };
  if( $@ ne "" )
  {
    error( "Xmltv_util - $chd->{display_name}: $chd->{xmltvid}: Failed to parse $@" );
    return 0;
  }
  
  # Find all "programme"-entries.
  my $ns = $doc->find( '//programme' );
  if( $ns->size() == 0 ){
    error( "Xmltv_util - $chd->{display_name}: $chd->{xmltvid}: No 'programme' blocks found" );
    return 0;
  }
  progress("Xmltv_util - $chd->{display_name}: $chd->{xmltvid}: " . $ns->size() . " 'programme' blocks found");
  
  foreach my $prog ($ns->get_nodelist)
  {

    # the id of the program
    my $origchannel  = $prog->findvalue( './@channel ' );

    #
    # start time
    #
    my $start = create_dt( $prog->findvalue( './@start' ) );
    if( not defined $start ){
      error( "Xmltv_util - $chd->{display_name}: $chd->{xmltvid}: Invalid starttime '" . $prog->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = create_dt( $prog->findvalue( './@stop' ) );
    if( not defined $end ){
      error( "Xmltv_util - $chd->{display_name}: $chd->{xmltvid}: Invalid endtime '" . $prog->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }

    # title
    my $title = $prog->findvalue( './title' );
    next if( ! $title );

    # description
    my $subtitle = $prog->findvalue( './sub-title' );
    my $description = $prog->findvalue( './desc' );
    my $genre = $prog->findvalue( './category' );
    my $url = $prog->findvalue( './url' );
    my $production_year = $prog->findvalue( './date' );
    my $episodenum = $prog->findvalue( './episode-num' );

    # The director and actor info are children of 'credits'
    my( $directors, $actors, $writers, $adapters, $producers, $presenters, $commentators, $guests );
    my $credits = $prog->findnodes( './/credits' );
    if( $credits->size() > 0 ){

      foreach my $credit ($credits->get_nodelist)
      {

        # directors
        my $directornodes = $credit->findnodes( './/director' );
        if( $directornodes->size() > 0 ){
          foreach my $director ($directornodes->get_nodelist)
          {
            $directors .= $director->textContent . ", ";
          }
          $directors =~ s/, $//;
        }

        # actors
        my $actornodes = $credit->findnodes( './/actor' );
        if( $actornodes->size() > 0 ){
          foreach my $actor ($actornodes->get_nodelist)
          {
            $actors .= $actor->textContent . ", ";
          }
          $actors =~ s/, $//;
        }

        # writers
        my $writernodes = $credit->findnodes( './/writer' );
        if( $writernodes->size() > 0 ){
          foreach my $writer ($writernodes->get_nodelist)
          {
            $writers .= $writer->textContent . ", ";
          }
          $writers =~ s/, $//;
        }

        # adapters
        my $adapternodes = $credit->findnodes( './/adapter' );
        if( $adapternodes->size() > 0 ){
          foreach my $adapter ($adapternodes->get_nodelist)
          {
            $adapters .= $adapter->textContent . ", ";
          }
          $adapters =~ s/, $//;
        }

        # producers
        my $producernodes = $credit->findnodes( './/producer' );
        if( $producernodes->size() > 0 ){
          foreach my $producer ($producernodes->get_nodelist)
          {
            $producers .= $producer->textContent . ", ";
          }
          $producers =~ s/, $//;
        }

        # presenters
        my $presenternodes = $credit->findnodes( './/presenter' );
        if( $presenternodes->size() > 0 ){
          foreach my $presenter ($presenternodes->get_nodelist)
          {
            $presenters .= $presenter->textContent . ", ";
          }
          $presenters =~ s/, $//;
        }

        # commentators
        my $commentatornodes = $credit->findnodes( './/commentator' );
        if( $commentatornodes->size() > 0 ){
          foreach my $commentator ($commentatornodes->get_nodelist)
          {
            $commentators .= $commentator->textContent . ", ";
          }
          $commentators =~ s/, $//;
        }

        # guests
        my $guestnodes = $credit->findnodes( './/guest' );
        if( $guestnodes->size() > 0 ){
          foreach my $guest ($guestnodes->get_nodelist)
          {
            $guests .= $guest->textContent . ", ";
          }
          $guests =~ s/, $//;
        }

      }

    }

    progress("Xmltv_util - $chd->{display_name}: $chd->{xmltvid}: $start - $title");

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
    };

    $ce->{subtitle} = $subtitle if $subtitle;
    $ce->{description} = $description if $description;
    $ce->{url} = $url if $url;

    if( $genre ){
      #my($program_type, $category ) = $ds->LookupCat( $chd->{display_name}, $genre );
      #AddCategory( $ce, $program_type, $category );
    }

    
    if( $production_year =~ /(\d{4})/ )
    {
      $ce->{production_date} = "$1-01-01";
    }

    if( $episodenum ){
        # parse $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
    }

    $ds->AddProgramme( $ce );

  }
  
  # Success
  return 1;
}

sub create_dt
{
  my( $text ) = @_;

#print ">$text<\n";

  my( $year, $month, $day, $hour, $min, $sec );

  # format '20100608011500 +0200'
  if( $text =~ /^(\d{14})\s+[+|-](\d{4})/ ){
    ( $year, $month, $day, $hour, $min, $sec ) = ( $text =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/ );
  }
  
  if( $sec > 59 ) {
    return undef;
  }

  my $dt;
  eval {
  $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $min,
                          second => $sec,
                          time_zone => 'Europe/Zagreb',
                          );
  };
  if ($@){
    error ("Could not convert time! Check for daylight saving time border.");
    return undef;
  };
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;
