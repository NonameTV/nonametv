package NonameTV::Importer::AFN;

use strict;
use warnings;

=pod

Importer for AFN guide at http://508.myafn.dodmedia.osd.mil/ScheduleList.aspx
The importer field should contain the channel name as it appears on the site, e.g. "AFN|prime Pacific"

=cut

use HTML::Entities;
use HTML::TableExtract;
use HTML::Parse;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Unicode::String;

use NonameTV qw/Html2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseDaily;
use NonameTV::Log qw/p w f/;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    if ($self->{MaxDays} >= 30) {
      $self->{MaxDays} = 30;
    }

    $self->{datastore}->{augment} = 1;

    # FIXME it would be strongly preferred if someone could hint if the start or stop time should be moved slightly
    # we get overlaps of up to 9 minutes which seem to be intentional, so I'd guess cutting of some minutes at the
    # start times is the way to go
    $self->{datastore}->{SILENCE_END_START_OVERLAP} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $xmltvid, $year, $month, $day ) = ( $objectname =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );

  my $url = "http://508.myafn.dodmedia.osd.mil/ScheduleList.aspx?TimeZone=(GMT)%20Greenwich%20Mean%20Time&StartDate=$month/$day/$year&";

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref =~ s|\r||g;

  my $doc = Html2Xml ($$cref);
  if( not defined $doc ) {
    return (undef, 'Html2Xml failed' );
  } 

  # remove head
  foreach my $node ($doc->find ('//head')->get_nodelist) {
    $node->unbindNode ();
  }

  # save program table
  my $saveddata;
  my @nodes = $doc->find ('//table[@class="GridView"]')->get_nodelist();
  $saveddata = $nodes[0];
  $nodes[0]->unbindNode ();

  # drop body content
  foreach my $node ($doc->find ('/html/body')->get_nodelist) {
    $node->removeChildNodes ();
    $node->addChild ($saveddata);
  }

  # remove bgcolor
  foreach my $node ($doc->find ('//@bgcolor')->get_nodelist) {
    $node->unbindNode ();
  }


  $cref = $doc->toStringHTML ();

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'html';
}


sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my( $xmltvid, $year, $month, $day ) = ( $batch_id =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );

  my $ds = $self->{datastore};

  my $te = HTML::TableExtract->new(
#    keep_html => 1
  );

  $te->parse($$cref);

  my $table = $te->table(0, 0);

  for (my $i = 1; $i < $table->row_count(); $i++) {
    my @row = $table->row($i);

    if( $chd->{grabber_info} ne norm( $row[1] ) ){
      next;
    }

    my ( $hour, $minute, $ampm ) = ( $row[0] =~ m|(\d+):(\d+) ([AP]M)| );
    if( $hour == 12 ) {
      $hour = 0;
    }
    if( $ampm eq 'PM' ){
      $hour += 12;
    }

    my $title = norm( $row[2] );
    $title =~ s|:$||;
    my ($rating) = ( $row[3] =~ m|\((.*?)\s*\)| );
    $rating = norm( $rating );
    my ($duration) = ( $row[4] =~ m|\((.*?)\s*mins| );
    $duration = norm( $duration );
    my $episodetitle = norm( $row[5] );
    my $description = norm( $row[6] );

    my $start = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day,
                          hour  => $hour,
                          minute => $minute,
                          time_zone => 'UTC'
                          );

    my $end = $start->clone()->add( minutes => $duration );

    my $ce = {
        channel_id  => $chd->{id},
        start_time  => $start->ymd("-") . " " . $start->hms(":"),
        end_time    => $end->ymd("-") . " " . $end->hms(":"),
        title       => $title
    };

    if( $rating ){
      $ce->{rating} = $rating;
    }

    if( $description ){
      $ce->{description} = $description;
    }

    if( $episodetitle ){
      if( $episodetitle eq 'Live' ){
        $ce->{program_type} = 'tvshow';
      }elsif( $episodetitle =~ m|^Prod Year| ){
        my( $year )=( $episodetitle =~ m|^Prod Year (\d{4})$| );
        $ce->{production_date} = $year . '-01-01';
        $ce->{program_type} = 'movie';
      }else{
        # simplify " (Pt. #)" to " (#)"
        $episodetitle =~ s|\s*\(Pt\.\s+(\d+)\)$| ($1)|;
        $ce->{subtitle} = $episodetitle;
        $ce->{program_type} = 'series';
      }
    }

    $ds->AddProgramme( $ce );
  }

  return 1;
}


1;
