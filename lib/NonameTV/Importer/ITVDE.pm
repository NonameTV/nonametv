package NonameTV::Importer::ITVDE;

use strict;
use warnings;

=pod

Importer for data from ITV Germany.

Channels: Family TV and Das Neue TV
Country: Germany

=cut

use Data::Dumper;
use DateTime;
use XML::LibXML::XPathContext;

use NonameTV qw/AddCategory AddCountry norm ParseXml/;
use NonameTV::Importer::BaseFile;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d progress w error f/;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $cref=`cat \"$file\"`;

  $cref =~ s|
  ||g;

  $cref =~ s| xmlns:ns='http://struppi.tv/xsd/'||;
  $cref =~ s| xmlns:xsd='http://www.w3.org/2001/XMLSchema'||;

  $cref =~ s| generierungsdatum='[^']+'| generierungsdatum=''|;


  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_string($cref); };

  if (not defined ($doc)) {
    f ("$file: Failed to parse.");
    return 0;
  }

  my $xpc = XML::LibXML::XPathContext->new( );
  $xpc->registerNs( s => 'http://struppi.tv/xsd/' );

  my $programs = $xpc->findnodes( '//s:sendung', $doc );
  if( $programs->size() == 0 ) {
    f ("$file: No data found");
    return 0;
  }

  sub by_start {
    return $xpc->findvalue('s:termin/@start', $a) cmp $xpc->findvalue('s:termin/@start', $b);
  }

  my $currdate = "x";

  foreach my $program (sort by_start $programs->get_nodelist) {
        $xpc->setContextNode( $program );
        my $start = $self->parseTimestamp( $xpc->findvalue( 's:termin/@start' ) );
        my $end = $self->parseTimestamp( $xpc->findvalue( 's:termin/@ende' ) ) if $xpc->findvalue( 's:termin/@ende' ) =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/;
        my $ce = ();
        $ce->{channel_id} = $chd->{id};

        $ce->{start_time} = $start->ymd("-") . " " . $start->hms(":");
        $ce->{end_time} = $end->hms(":") if $end;

        if($start->ymd("-") ne $currdate ) {
           if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
           }

          my $batchid = $chd->{xmltvid} . "_" . $start->ymd("-");
          $dsh->StartBatch( $batchid , $chd->{id} );
          #$dsh->StartDate( $start->ymd("-") , "06:00" );
          $currdate = $start->ymd("-");
          progress("Tele5_xml: $chd->{xmltvid}: Date is: ".$start->ymd("-"));
        }

        $ce->{title} = norm($xpc->findvalue( 's:titel/@termintitel' ));

        my $title_org;
        $title_org = $xpc->findvalue( 's:titel/s:alias[@titelart="originaltitel"]/@aliastitel' );
        $ce->{original_title} = norm($title_org) if $title_org and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

        my ($folge, $staffel);
        my $subtitle = $xpc->findvalue( 's:titel/s:alias[@titelart="untertitel"]/@aliastitel' );
        my $subtitle_org = $xpc->findvalue( 's:titel/s:alias[@titelart="originaluntertitel"]/@aliastitel' );
        if( $subtitle ){
          if( ( $folge, $staffel ) = ($subtitle =~ m|^Folge (\d+) \((\d+)\. Staffel\)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge, $staffel ) = ($subtitle =~ m|^Folge (\d+) \(Staffel (\d+)\)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $staffel, $folge ) = ($subtitle =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge ) = ($subtitle =~ m|^Folge (\d+)$| ) ){
            $ce->{episode} = '. ' . ($folge - 1) . ' .';
          } else {
            # unify style of two or more episodes in one programme
            $subtitle =~ s|\s*/\s*| / |g;
            # unify style of story arc
            $subtitle =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
            $subtitle =~ s|[ ,-]+Part (\d)+$| \($1\)|;
            $ce->{subtitle} = norm( $subtitle );
          }
        }

        if( $subtitle_org ){
          if( ( $folge, $staffel ) = ($subtitle_org =~ m|^Folge (\d+) \(Staffel (\d+)\)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $staffel, $folge ) = ($subtitle_org =~ m|^Staffel (\d+) Folge (\d+)$| ) ){
            $ce->{episode} = ($staffel - 1) . ' . ' . ($folge - 1) . ' .';
          } elsif( ( $folge ) = ($subtitle_org =~ m|^Folge (\d+)$| ) ){
            $ce->{episode} = '. ' . ($folge - 1) . ' .';
          } else {
            # unify style of two or more episodes in one programme
            $subtitle_org =~ s|\s*/\s*| / |g;
            # unify style of story arc
            $subtitle_org =~ s|[ ,-]+Teil (\d)+$| \($1\)|;
            $subtitle_org =~ s|[ ,-]+Part (\d)+$| \($1\)|;
            $ce->{original_subtitle} = norm( $subtitle_org ) if defined $ce->{subtitle} and $ce->{subtitle} ne norm( $subtitle_org );
            $ce->{subtitle} = norm( $subtitle_org ) if not defined $ce->{subtitle};
          }
        }

        my $production_year = $xpc->findvalue( 's:infos/s:produktion[@gueltigkeit="sendung"]/s:produktionszeitraum/s:jahr/@von' );
        if( $production_year =~ m|^\d{4}$| ){
          $ce->{production_date} = $production_year . '-01-01';
        }

        my @countries;
        my $ns4 = $xpc->find( 's:infos/s:produktion[@gueltigkeit="sendung"]/s:produktionsland/@laendername' );
        foreach my $con ($ns4->get_nodelist)
	    {
	        my ( $c ) = $self->{datastore}->LookupCountry( "Arte", $con->to_literal );
	  	    push @countries, $c if defined $c;
	    }

        if( scalar( @countries ) > 0 )
        {
              $ce->{country} = join "/", @countries;
        }

        my $season  = $xpc->findvalue( 's:infos/s:folge/@staffel' );
        my $episode = $xpc->findvalue( 's:infos/s:folge/@folgennummer' );

        if(defined($episode) and $episode and $episode ne "") {
            if(defined($season) and $season and $season ne "") {
                $ce->{episode} = ($season - 1) . ' . ' . ($episode - 1) . ' .';
            } else {
                $ce->{episode} = ' . ' . ($episode - 1) . ' .';
            }
        }

        my $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@hauptgenre' );
        if( $genre ){
          my ( $program_type, $category ) = $self->{datastore}->LookupCat( "Tele5_genre", $genre );
          AddCategory( $ce, $program_type, $category );
        }
        $genre = $xpc->findvalue( 's:infos/s:klassifizierung/@formatgruppe' );
        if( $genre ){
          my ( $program_type2, $category2 ) = $self->{datastore}->LookupCat( "Tele5_main", $genre );
          AddCategory( $ce, $program_type2, $category2 );
        }

        #Descr
        my $desc = $xpc->findvalue( 's:text[@textart="Kurztext"]' );
        if( ! $desc) {
            $desc = $xpc->findvalue( 's:text[@textart="Beschreibung"]' );
        }
        if( ! $desc) {
            $desc = $xpc->findvalue( 's:text[@textart="Allgemein"]' );
        }


        if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Mono"]/@art' ) ) {
          $ce->{stereo} = 'mono';
        }
        if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Stereo"]/@art' ) ) {
          $ce->{stereo} = 'stereo';
        }
        if( $xpc->findvalue( 's:infos/s:sonderzeichen/s:ton[@art="Mehrkanal"]/@art' ) ) {
          $ce->{stereo} = 'surround';
        }

        my $aspect = $xpc->findvalue( 's:infos/s:sonderzeichen/s:bildverhaeltnis/@verhaeltnis' );
        if( $aspect ){
          if ($aspect eq '16:9') {
            $ce->{aspect} = '16:9';
          } elsif ($aspect eq 'Stereo') {
            $ce->{aspect} = 'stereo';
          } elsif ($aspect eq '4:3') {
            $ce->{aspect} = '4:3';
          } else {
            w( 'unhandled type of aspect: ' . $aspect );
          }
        }

        my $quality = $xpc->findvalue( 's:infos/s:sonderzeichen/s:hd[@vorhanden="true"]/@vorhanden' );
        if( $quality ){
          if ($quality eq 'true') {
            $ce->{quality} = 'HDTV';
          } else {
            w( 'unhandled type of quality: ' . $quality );
          }
        }

        ParseCredits( $ce, 'actors',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Darsteller"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'directors',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Regie"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'producers',  $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Produzent"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Autor"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'writers',    $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Drehbuch"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'presenters', $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Moderation"]/s:mitwirkendentyp/s:person/s:name' );
        ParseCredits( $ce, 'guests',     $xpc, 's:mitwirkende/s:mitwirkender[@funktion="Gast"]/s:mitwirkendentyp/s:person/s:name' );

        #print Dumper($ce);

        $ce->{description} = norm($desc) if $desc and $desc ne "";

        $ds->AddProgrammeRaw( $ce );

        progress("Tele5_xml: $chd->{xmltvid}: ".$ce->{start_time}." - ".$ce->{title});
  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub parseTimestamp( $ ){
  my $self = shift;
  my ($timestamp, $date) = @_;

  if( $timestamp ){
    # 2011-11-12T20:15:00+01:00
    my ($year, $month, $day, $hour, $minute) = ($timestamp =~ m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
    if( !defined( $year )|| !defined( $hour ) ){
      w( "could not parse timestamp: $timestamp" );
    }

    my $dt = DateTime->new (
      year      => $year,
      month     => $month,
      day       => $day,
      hour      => $hour,
      minute    => $minute,
      time_zone => 'Europe/Berlin'
    );
    $dt->set_time_zone( 'UTC' );

    return( $dt );

  } else {
    return undef;
  }
}

# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->findvalue( '@vorname' )." ".$node->findvalue( '@name' );

    if( norm($person) ne '' ) {
      push( @people, split( '&', $person ) );
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}


sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ';', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ';', @people );
    }
  }
}

1;
