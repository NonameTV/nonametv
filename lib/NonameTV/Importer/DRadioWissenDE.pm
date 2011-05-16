package NonameTV::Importer::DRadioWissenDE;

use strict;
use warnings;
use Encode qw/from_to/;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use HTML::TableExtract;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

#use NonameTV::Log qw/d p w f/;
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

  my $url = 'http://wissen.dradio.de/programmschema.20.de.html?drbm:date=' . $day . '.' . $month . '.' . $year;

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

  my $doc = Html2Xml ($cref);
  if( not defined $doc ) {
    return (undef, 'Html2Xml failed' );
  } 

  # remove head
  foreach my $node ($doc->find ('//head')->get_nodelist) {
    $node->unbindNode ();
  }

  # remove link to recorder
  foreach my $node ($doc->find ('//a[@class="psradio"]')->get_nodelist) {
    $node->unbindNode ();
  }


  # save program table
  my $saveddata;
  my @nodes = $doc->find ('//div[@class="contentSchedule"]/table')->get_nodelist();
  $saveddata = $nodes[-1];
  $nodes[-1]->unbindNode ();

  # drop body content
  foreach my $node ($doc->find ('/html/body')->get_nodelist) {
    $node->removeChildNodes ();
    $node->addChild ($saveddata);
  }

  $cref = $doc->toStringHTML ();

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html.gz';
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

    from_to($row[1], "iso-8859-1", "utf8");

    my $title = $row[1];

    my $start = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day,
                          hour  => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Berlin'
                          );

    $start->set_time_zone ('UTC');

    my $ce = {
        channel_id  => $chd->{id},
        start_time  => $start->ymd("-") . " " . $start->hms(":"),
        title => $title
    };

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
