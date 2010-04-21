package NonameTV::Importer::RadioXDE;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use HTML::Entities;
use HTML::TableExtract;
use HTML::Parse;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Unicode::String;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV qw/Html2Xml/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Only one url to look at and no error
  return ([$self->{UrlRoot}], undef);
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $cref;

  gunzip $gzcref => \$cref
    or die "gunzip failed: $GunzipError\n";

  # FIXME convert latin1 to utf-8 to HTML
  $cref = Unicode::String::latin1 ($cref)->utf8 ();
  $cref = encode_entities ($cref, "\200-\377");

  # cut away frame around tables
  $cref =~ s|^.+\"0Woche\"> +(<table.+/table>)\n +</div></body>.*$|<html><body><div>$1</div></body></html>|s;

  # remove hyperlinks
#  $cref =~ s|<a href((?!>).)+>(((?!</a>).)*)</a>|$1|g;

  # turn &nbsp; into space
  $cref =~ s|&nbsp;| |g;

  # remove duplicate space
  $cref =~ s|[[:space:]]+| |g;

  # remove class and id
  $cref =~ s| class=\"((?!\").)*\"||g;
  $cref =~ s| id=\"((?!\").)*\"||g;

  my $doc = Html2Xml ($cref);
  $cref = $doc->toStringHTML ();

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html.gz';
}

sub FilteredExtension {
  return 'html';
}

sub trimX {
  my $theString = shift;
  if ($theString) {
    $theString =~ s|\[Tipp\]||g;
    $theString =~ s|\{Tipp\]||g;
    $theString =~ s|\(Wdh.\)||g;
    $theString =~ s|[[:space:]]+| |g;
    $theString =~ s/^\s+//;
    $theString =~ s/\s+$//;
  }

  return $theString;
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $te = HTML::TableExtract->new(
    keep_html => 0
  );

  $te->parse($$cref);

  my $table = $te->table(0,0);
  my @firstrow = $table->row(0);
  my $firstdate = $firstrow[1];

  my $year = DateTime->now()->year();
  my ($day, $month) = ( $firstdate =~ /(\d+)\.(\d+)\./ );

  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day,
                          time_zone => 'Europe/Berlin'
                          );
  # if dt is in the future we have a new year between first date and today
  if (DateTime->compare ($dt, DateTime->now()) > 0) {
    $year--; # substract one year between now and start of guide data
    $dt->subtract (years => 1);
  }

  $dsh->StartDate ($year . "-" .$month."-".$day, "02:00");

  # loop over 11 weeks of programme tables
  for (my $woche = 0; $woche < 11; $woche++) {
    $table = $te->table (0, $woche);
    my $dtgestern = $dt;

    # look over the seven columns/days
    for (my $tagspalte = 1; $tagspalte <= 7; $tagspalte++) {
      # get date
      my $heute = $table->row(0)->[$tagspalte];
      ($day, $month) = ($heute =~ /(\d+)\.(\d+)\./);
      my $dtheute = DateTime->new (year => $year, month => $month, day => $day, time_zone => 'Europe/Berlin');

      # is it new years day today?
      if (DateTime->compare ($dtheute, $dtgestern) < 0) {
        $year++;
        $dtheute->add (years => 1);

# FIXME DataStoreHelper don't really like jumps over into the new year!
        $dsh->StartDate ($year . "-" .$month."-".$day, "00:00");
      }

      # process programmes
      for (my $stunderow = 2; $stunderow < $table->row_count(); $stunderow++) {
        my @programmerow = $table->row ($stunderow);
        my @sendung = split ("\n", $programmerow[$tagspalte]);

        # skip continuations of last programme
        if (!($sendung[0] =~ /^[[:space:]]*$/)) {
          if (!($sendung[0] =~ /^[[:space:]]*dito[[:space:]]*$/)) {
            my ($title, $desc);
            for (my $i = 0; $i < @sendung; $i++) {
              if ($i == 0) {
                $title = $sendung[$i];
              } else {
                if (!$desc) {
                  $desc = $sendung[$i];
                } else {
                  $desc = $desc . " " . $sendung[$i];
                }
              }
            }
            my $start_time = $programmerow[0];

            # trim title
            $title = trimX ($title);

            my $ce = {
              start_time => $start_time,
              title => $title
            };

            # trim description
            $desc = trimX ($desc);
            if ($desc) {
              $ce->{description} = $desc;
            }

            $dsh->AddProgramme ($ce);
          }
        }
      }

      # update gestern
      $dtgestern = $dtheute;
    }
  }

  return 1;
}


1;
