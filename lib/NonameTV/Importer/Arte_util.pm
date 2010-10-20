package NonameTV::Importer::Arte_util;

use strict;
use warnings;

=pod

Import data from xml files (result of Word2Xml). The parsing of the
data relies only on the text-content of the document, not on the
formatting.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/AddCategory File2Xml MyGet norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/d progress w error/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ImportFull/;
}
our @EXPORT_OK;



# States
use constant {
  ST_START      => 0,
  ST_FDATE      => 1,   # Found date
  ST_FHEAD      => 2,   # Found head with starttime and title
  ST_FSUBINFO   => 3,   # Found sub info
  ST_FDESCSHORT => 4,   # Found short description
  ST_FDESCLONG  => 5,   # After long description
  ST_FADDINFO   => 6,   # After additional info
};

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportFull
{
  my( $filename, $doc, $chd, $dsh ) = @_;
  my $have_batch;
  
  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    error( "Arte: $chd->{xmltvid}: No programme entries found in $filename" );
    return;
  }

  if ($filename =~ m/\.doc$/i) {
    progress( "Arte: $chd->{xmltvid}: Processing $filename" );
    $have_batch = 0;
  } else {
    progress ("Arte: processing batch");
    $have_batch = 1;
  }

  my $date;
  my $currdate = "x";
  my $time;
  my $title;
  my $subinfo;
  my $shortdesc;
  my $longdesc;
  my $addinfo;

  my $state = ST_START;
  
  foreach my $div ($ns->get_nodelist)
  {

    # Ignore English titles in National Geographic.
    next if $div->findvalue( '@name' ) =~ /title in english/i;

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    # strip strange " * " in front of paragraph
    $text =~ s|^\s*\*\s+||;
    next if $text eq "";

    my $type;

    if( isDate( $text ) ){

      $date = ParseDate( $text );
      if( not defined $date ) {
	error( "Arte: $chd->{xmltvid}: $filename Invalid date $text" );
      }

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          if ($have_batch == 0) {
            $dsh->EndBatch( 1 );
          }
        }

        if ($have_batch == 0) {
          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
        }
        $dsh->StartDate( $date , "03:00" );
        $currdate = $date;

        progress("Arte: $chd->{xmltvid}: Date is: $date");

        $state = ST_FDATE;
      }

    } elsif( isTitle( $text ) ){

      # start of a new programme, write out last one and go ahead

      $state = ST_FHEAD;

    } elsif( isSubTitle( $text ) ){

      $state = ST_FSUBINFO;

    } elsif( $text =~ /^\[Kurz\]$/i ){

      $state = ST_FDESCSHORT;

    } elsif( $text =~ /^\[Lang\]$/i ){

      $state = ST_FDESCLONG;

    } elsif( $text =~ /^\[Zusatzinfo\]$/i ){

      $state = ST_FADDINFO;

    }

    # did we collect one full programme?
    if( ( $state eq ST_FDATE or $state eq ST_FHEAD ) and $time and $title and ( $subinfo or $longdesc ) ){
      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
      };


      # strip duration
      $title =~ s/\s+\d+\s+min\.\s*$//i;

      my $aspect = undef;
      if( $title =~ /\s+16:9\s*$/ ){
        $aspect = "16:9";
        $title =~ s/\s+16:9\s*$//i;
      }

      my $stereo = undef;
      if( $title =~ /\s+stereo\s*$/i ){
        $stereo = "stereo";
        $title =~ s/\s+stereo\s*$//i;
      }

      # parse episode number
      my $episode;
      if ($title =~ m|\s*\(\d+/\d+\)\s*$|) {
        my ($episodenum, $episodecount) = ($title =~ m|\s*\((\d+)/(\d+)\)\s*$|);
        $episode = '. ' . ($episodenum-1) . '/' . ($episodecount) . ' .';
        $title =~ s|\s*\(\d+/\d+\)\s*$||;
      } elsif ($title =~ m|\s*\(\d+\)\s*$|) {
        my ($episodenum) = ($title =~ m|\s*\((\d+)\)\s*$|);
        $episode = '. ' . ($episodenum-1) . ' .';
        $title =~ s|\s*\(\d+\)\s*$||;
      }
      $ce->{episode} = $episode if $episode;
      $ce->{title} = $title;
      d( "Arte: $chd->{xmltvid}: $time - $title" );


      if ( defined ($subinfo)) {
        ParseExtraInfo( \$dsh->{ds}, \$ce, $subinfo );
      }

      $shortdesc =~ s/^\[Kurz\]// if $shortdesc;
      $longdesc =~ s/^\[Lang\]// if $longdesc;
      $ce->{description} = $longdesc if $longdesc;


      $ce->{aspect} = $aspect if $aspect;
      $ce->{stereo} = $stereo if $stereo;


      $dsh->AddProgramme( $ce );

      $time = undef;
      $title = undef;
      $subinfo = undef;
      $shortdesc = undef;
      $longdesc = undef;
      $addinfo = undef;
    }

    # after subinfo line there comes
    # some text with information about the program
    if ( $state eq ST_FHEAD ) {
      ( $time, $title ) = ParseTitle( $text );
    } elsif( $state eq ST_FSUBINFO ){
      $subinfo .= $text . "\n";
    } elsif( $state eq ST_FDESCSHORT ){
      $shortdesc .= $text . "\n";
    } elsif( $state eq ST_FDESCLONG ){
      $longdesc .= $text . "\n";
    } elsif( $state eq ST_FADDINFO ){
      $addinfo .= $text . "\n";
    }
  }
 
  if ($have_batch == 0) {
    $dsh->EndBatch( 1 );
  }

  return;
}

sub isDate {
  my ( $text ) = @_;

  # format 'Samstag, 21.11.2009'
  if( $text =~ /^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s+\d+\.\d+\.\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text ) = @_;

  my( $weekday, $day, $month, $year );

  # try 'Sunday 1 June 2008'
  if( $text =~ /^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s+\d+\.\d+\.\d+$/i ){
    ( $weekday, $day, $month, $year ) = ( $text =~ /^(\S+),\s+(\d+)\.(\d+)\.(\d+)$/ );
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isTitle
{
  my( $text ) = @_;

  if( $text =~ /^\d\d:\d\d\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseTitle
{
  my( $text ) = @_;

  my( $time, $rest ) = ( $text =~ /^(\d+:\d+)\s+(.*)\s*$/ );

  return( $time, $rest );
}

sub isSubTitle
{
  my( $text ) = @_;

  if( $text =~ m/^\[\d{2}:\d{2}\]\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseExtraInfo
{
  my( $ds, $ce, $text ) = @_;

  my $seengenre = undef;
  my $genre = undef;
  my $productiondate = undef;

  # join back together lines that got split due to length
  $text =~ s/,\n/, /g;
  my @lines = split( /\n/, $text );
  foreach my $line ( @lines ){
    if( $line =~ m/^\[\d{2}:\d{2}\]/ ){
      # strip the time
      $line =~ s|^\[\d{2}:\d{2}\]\s+||;

      # is it an episodetitle?
      if( $line =~ m|^\(\d+\):| ) {
        my ($episodenum, $episodetitle) = ($line =~ m|^\((\d+)\):\s*(.*?)\s*$|);
        if (!defined ($$ce->{episode})) {
          $$ce->{episode} = '. ' . ($episodenum-1) . ' .';
        }
        if (defined ($episodetitle)) {
          $$ce->{subtitle} = $episodetitle;
        }
        next;
      }

      # first line is it a repeat?
      if ($line =~ m/, Wiederholung vom \d+\.\d+\.$/) {
        ($genre) = ($line =~ m|^(.*), Wiederholung vom \d+\.\d+\.$|);
        $seengenre = 1;
        next;
      }

      # strip dub, premiere
      $line =~ s|, Synchronfassung$||;
      $line =~ s|, Erstausstrahlung$||;
      $line =~ s|, Schwerpunkt: [^,]+$||;
      $line =~ s|, Synchronfassung$||;
      $line =~ s|, Originalfassung mit Untertiteln||; # yes, it's not the last
      # is it the genre?
      # genre, contries year, producing stations
      if( ($genre, $productiondate) = ( $line =~ m|^([^,]+)\s*,[^,]+\s+(\d{4}),[^,]+$| ) ) {
        $seengenre = 1;
      } else {
        # then it must be the subtitle
        $$ce->{subtitle} = $line;
        next;
      }
    }

    if( $line =~ /^Dieses Programm wurde in HD produziert\.$/ ){
      $$ce->{quality} = 'HDTV';
      next;
    }

    if( $line =~ /^ARTE stellt diesen Beitrag auch/ ){
      # strip reference to ARTE+7 video on demand
      next;
    }

    if( $line =~ /^ARTE strahlt diesen Film auch in einer untertitelten Fassung f/ ){
      # strip subtitle for hard of hearing
      next;
    }

    if( $line =~ /^ARTE strahlt diesen Film auch in einer H/ ){
      # strip audio for the blind
      next;
    }

    # not the first line, maybe still a repeat? (copy from above)
    if ($line =~ m/, Wiederholung vom \d+\.\d+\.$/) {
      ($genre) = ($line =~ m|^(.*), Wiederholung vom \d+\.\d+\.$|);
      $seengenre = 1;
      next;
    }
    if ($line =~ m/^Wiederholung vom \d+\.\d+\.$/) {
      next;
    }
    if ($line =~ m/^Wiederholung vom \d+\. \d+\. \d{4}$/) {
      next;
    }

    # parse actors
    if( $line =~ /^Mit:\s+.*$/ ){
      my ( $actor ) = ( $line =~ /^Mit:\s+(.*)$/ );
      # remove name of role, not yet supported
      my @actors = split( ', ', $actor );
      foreach my $person (@actors) {
        $person =~ s|\s+-\s+\(.*\)$||;
      }
      $$ce->{actors} = join( ', ', @actors);
      next;
    }

    if( $line =~ m|^Themenabend:| ) {
       next;
    }

    # parse credits (all but actors)
    if( $line =~ /^\S+:\s+.*$/ ){
      my @credits = split( '; ', $line );
      foreach my $credit (@credits) {
        my ($job, $people) = ($credit =~ m|^(\S+):\s*(.*)$|);
        if ($job eq 'Regie') {
          $$ce->{directors} = $people;
        } elsif ($job eq 'Buch') {
          $$ce->{writers} = $people;
        } elsif ($job eq 'Kamera') {
        } elsif ($job eq 'Schnitt') {
        } elsif ($job eq 'Ton') {
        } elsif ($job eq 'Musik') {
        } elsif ($job eq 'Produzent') {
          $$ce->{producers} = $people;
        } elsif ($job eq 'Produktion') {
        } elsif ($job eq 'Redaktion') {
        } elsif ($job eq 'Moderation') {
          $$ce->{presenters} = $people;
        } elsif ($job eq 'Gast') {
          $$ce->{Guests} = $people;
        } elsif ($job eq 'Dirigent') {
        } elsif ($job eq 'Orchester') {
        } elsif ($job eq 'Choreografie') {
        } elsif ($job eq 'Komponist') {
        } elsif ($job eq 'Maske') {
        } elsif ($job eq 'Kostüme') {
        } elsif ($job eq 'Ausstattung') {
        } elsif ($job eq 'Regieassistenz') {
        } elsif ($job eq 'Restaurierung') {
        } elsif ($job eq 'Licht') {
        } elsif ($job eq 'Fernsehregie') {
        } elsif ($job eq 'Inszenierung') {
        } elsif ($job eq 'Chor') {
        } elsif ($job eq 'Herstellungsleitung') {
        } elsif ($job eq 'Buch/Autor') {
          $$ce->{writers} = $people;
        } else {
          d( "unhandled job $job" );
        }
      }
      # FIXME split at ; and handle more roles the just directors
      next;
    }

    # strip dub, premiere
    $line =~ s|, Synchronfassung$||;
    $line =~ s|, Erstausstrahlung$||;
    $line =~ s|, Schwerpunkt: [^,]+$||;
    $line =~ s|, Synchronfassung$||;
    $line =~ s|, Originalfassung mit Untertiteln||; # yes, it's not the last
    # is it the genre?
    # genre, contries year, producing stations
    if( ($genre, $productiondate) = ($line =~ m|^([^,]+)\s*,[^,]+\s+(\d{4}),[^,]+$| ) ) {
      $seengenre = 1;
      next;
    }
    # genre, contries year
    if( ($genre, $productiondate) = ($line =~ m|^([^,]+)\s*,[^,]+\s+(\d{4})$| ) ) {
      $seengenre = 1;
      next;
    }
    # contries year, producing stations
    if( ($productiondate) = ($line =~ m|[^,]+\s+(\d{4}),[^,]+$| ) ) {
      next;
    }

    # FIXME has title (incl. part number), origtitle, partnumber: empty episode title
    if( $line =~ m|^\(\d+\):$| ) {
      next;
    }


    w( "unhandled subinfo: $line" );
  }

  if( defined( $productiondate ) ) {
    $$ce->{production_date} = $productiondate . '-01-01';
  }

  if( defined( $genre) ) {
    my ( $program_type, $categ ) = $$ds->LookupCat( "Arte_genre", $genre );
    AddCategory( $$ce, $program_type, $categ );
  }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
