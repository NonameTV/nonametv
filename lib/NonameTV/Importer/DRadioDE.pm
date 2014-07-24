package NonameTV::Importer::DRadioDE;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use Encode;
use HTML::TableExtract;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use NonameTV::Log qw/w f/;
use NonameTV qw/Html2Xml/;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $xmltvid, $year, $month, $day ) = ( $objectname =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );

  if (!defined ($chd->{grabber_info})) {
    return (undef, 'Grabber info must contain path!');
  }

  my $url = $chd->{grabber_info} . '?drbm:date=' . $day .  '.' . $month . '.' . $year;

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $cref;

  gunzip $gzcref => \$cref
    or die "gunzip failed: $GunzipError\n";

  $cref =~ s/\r//g;
  $cref =~ s/encoding="iso-8859-1"/encoding="windows-1252"/g;
  $cref =~ s/charset=iso-8859-1"/charset=windows-1252"/g;

  my $doc = Html2Xml ($cref);
  if( not defined $doc ) {
    return (undef, 'Html2Xml failed' );
  } 

  # remove head
  foreach my $node ($doc->find ('//head')->get_nodelist) {
    $node->unbindNode ();
  }

  # save program table
  my $saveddata;
  my @nodes = $doc->find ('//table[thead/tr/th="Zeit"]')->get_nodelist();
  $saveddata = $nodes[-1];
  $nodes[-1]->unbindNode ();

  # drop body content
  foreach my $node ($doc->find ('/html/body')->get_nodelist) {
    $node->removeChildNodes ();
    $node->addChild ($saveddata);
  }

  # drop link to recorder
  foreach my $node ($doc->find ('//a[@class="link_recorder"]')->get_nodelist) {
    $node->unbindNode ();
  }
  # <a href="deutschlandradio-recorder-programmieren.1406.de.html?drpl:params=%7CAtelier+neuer+Musik%7C127%7C20140208220500%7C20140208225000%7C0%7C0%7C0%7C0%7C0" title="Sendung mitschneiden - Sie ben&ouml;tigen den kostenlosen dradio-Recorder" class="psradio">aufnehmen</a>
  foreach my $node ($doc->find ('//a[@class="psradio"]')->get_nodelist) {
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

  my $dt = DateTime->new( 
                          year      => $year,
                          month     => $month,
                          day       => $day,
                          hour      => 0,
                          minute    => 0,
                          time_zone => 'Europe/Berlin'
                          );

  my $te = HTML::TableExtract->new();

  $te->parse($$cref);

  my $table = $te->table(0, 0);

  for (my $i = 1; $i <= $table->row_count(); $i+=1) {
    my @row = $table->row($i);

    my ( $hour, $minute ) = ( $row[0] =~ m|(\d+):(\d+) Uhr| );

    $row[1] =~ s|\n\s*\n|\n|sg;
    $row[1] =~ s|^\s*||m;
    $row[1] =~ s|\s*$||m;
    $row[1] =~ s|^\n||s;

    # FIXME sometimes upstream provides really messed up encoding, e.g in
    # latvian names. Interestingly they get them right in the articles but
    # wrong in the program guide

    # FIXME I'm not sure why utf-8 bytes work, but perl characters don't.
    # I thought it should be the other way around.
    $row[1] = encode( 'utf-8', $row[1] );

    my ( $title ) = ( $row[1] =~ m|^(.*)$|m );
    my ( $desc ) = ( $row[1] =~ m|\n(.+)$|s );

    my $start;
    eval {
       $start = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day,
                          hour  => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Berlin'
                          );
    };
    if ($@){
      if ($hour && $minute) {
        w ("Could not convert time! Check for daylight saving time border. " . $year . "-" . $month . "-" . $day . " " . $hour . ":" . $minute);
      } else {
        w ("Could not find time! " . $year . "-" . $month . "-" . $day);
      }
      next;
    };

    $start->set_time_zone ('UTC');

    my $ce = {
        channel_id  => $chd->{id},
        start_time  => $start->ymd("-") . " " . $start->hms(":"),
        title => $title
    };
    if ($desc) {
      $ce->{description} = $desc;
    }

    $ds->AddProgramme( $ce );
  }

  $dt->add (days => 1);
  $dt->set_time_zone ('UTC');

  $ds->AddProgramme( {
    channel_id => 1,
    start_time => $dt->ymd("-") . " " . $dt->hms(":"),
    title      => "end-of-transmission",
  } );

  return 1;
}


1;
