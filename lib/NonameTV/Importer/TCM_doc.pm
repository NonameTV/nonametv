package NonameTV::Importer::TCM_doc;

use strict;
use warnings;

=pod

Channels: TCM Nordic (SE, NO, DK, EN)

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Data::Dumper;
use XML::LibXML;
use File::Basename;
use Encode qw/decode/;

use NonameTV qw/MyGet Wordfile2Xml AddCategory Htmlfile2Xml norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.doc$/i );

  progress( "Turner_doc: $xmltvid: Processing $file" );

  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Turner_doc - $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }

  # Find all paragraphs.
  my $ns = $doc->find( "//p" );

  if( $ns->size() == 0 ) {
    error( "Turner_doc - $xmltvid: $file: No ps found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;



  my $actors = 0;
  my $batched = 0;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = tcm_norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) {

    } elsif( isShow( $text ) ) {

      $actors = 0;

      my( $time, $date, $title, $director, $prodyear ) = ParseShow( $text );
      next if( ! $time );
      next if( ! $title );

      if(!$batched) {
        $batched = 1;
        my( $year, $month, $day ) = split( '-', $date );
        $ds->StartBatch( $xmltvid."_".$year."-".$month, $channel_id );
      }

      my $ce = {
        channel_id => $chd->{id},
        start_time => $date." ".$time,
        title => $title,
      };

      $ce->{directors} = join( ";", split( /\s*,\s*/, norm($director) ) ) if defined $director and norm($director) ne "";
      if( defined( $prodyear ) and ($prodyear =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      $ce->{program_type} = "movie" if defined $director and norm($director) ne "";

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    } else {
        $actors += 1 if norm($text) ne "";
        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        # Genre
        if($actors eq 1 and $text =~ /,/ and $text !~ /^Genre/i) {
            $element->{actors} = join( ";", split( /\s*,\s*/, norm($text) ) );
        } elsif($text =~ /^Genre/i) {
            my( $genre ) = ($text =~ /^Genre:(.*?)\./ );

            # Add genre
            if(defined $genre and norm($genre) ne "") {
                my ( $pty, $cat ) = $ds->LookupCat( 'TCM_doc', $genre );
                AddCategory( $element, $pty, $cat );
            }
        } elsif($text =~ /TCM Nordic Schedule/i) {

            # Dont add this
        }else {

            $element->{description} .= $text;
        }
    }
  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $ds , @ces );

  $ds->EndBatch( 1 );

  return;
}

sub FlushDayData {
  my ( $xmltvid, $ds , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("Turner: $xmltvid: $element->{start_time} - $element->{title}");
        #print Dumper($element);
        $ds->AddProgramme( $element );
      }
    }
}

sub isShow {
  my ( $text ) = @_;

  if( $text =~ /^^\d+\:\d+\:\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub isDate {
  my ( $text ) = @_;

  #


  if( $text =~ /^(\S*)\s+(\d+)\s+(\S*)\s+(\d\d\d\d)/i ){ # format 'M�ndag 11st Juli'
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $genre, $desc, $rating, $date, $director, $prodyear );

  ( $time, $date, $title ) = ( $text =~ /^(\d+\:\d+\:\d+)\s+(\d+\/\d+\/\d+)\|(.*)$/ );

  # Date
  my( $day, $month, $year ) = split( '/', $date );
  $year += 2000 if $year < 1700;

  # Time
  my ( $hour , $min, $secs ) = ( $time =~ /^(\d+):(\d+):(\d+)$/ );
  my $dt = DateTime->new( year   => $year,
                            month  => $month,
                            day    => $day,
                            hour   => $hour,
                            minute => $min,
                            time_zone => 'Europe/Stockholm',
                            );

  $dt->set_time_zone( "UTC" );

  # Title
  ( $title, $director, $prodyear ) = split( '\|', $title );

  return( $dt->hms(":"), $dt->ymd("-"), $title, $director, $prodyear );
}

sub tcm_norm
{
  my( $str ) = @_;

  return "" if not defined( $str );

#  $str = expand_entities( $str );

  $str =~ tr/\x{96}\x{93}\x{94}/-""/; #
  $str =~ tr/\x{201d}\x{201c}/""/;
  $str =~ tr/\x{2022}/*/; # Bullet
  $str =~ tr/\x{2013}\x{2018}\x{2019}/-''/;
  $str =~ tr/\x{017c}\x{0144}\x{0105}/zna/;
  $str =~ s/\x{85}/... /g;
  $str =~ s/\x{2026}/.../sg;
  $str =~ s/\x{2007}/ /sg;

  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $str =~ tr/\t/\|\|/s;
  $str =~ s/ +/ /;

  return $str;
}

1;