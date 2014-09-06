package NonameTV::Importer::Turner_xml;

use strict;
use warnings;

=pod

Imports data for Turner. The files are sent through MAIL and is in XML format.

Channels: TNT Film, Boomerang, Cartoon Network, TNT Serie

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;
use Text::Unidecode;
use File::Slurp;
use Encode;

use NonameTV qw/ParseXml norm normLatin1 normUtf8 AddCategory MonthNumber AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "Turner_xml: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "Turner_xml: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $days = $doc->findnodes( "//ScheduleDay" );

    if( $days->size() == 0 ) {
      error( "Turner_xml: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  foreach my $day ($days->get_nodelist) {
    my $progs = $day->findnodes( ".//Event" );
    my $date = $day->findvalue( './@date' );
    $date =~ s/\//-/g;

    if( $progs->size() == 0 ) {
        error( "Turner_xml: $chd->{xmltvid}: No Progs found" ) ;
        return;
    }

    if( $date ne $currdate ){
      	progress("Turner_xml: Date is $date");

        if( $currdate ne "x" ) {
        	$dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
    }

    foreach my $prog ($progs->get_nodelist) {
        my ($start, $end);
        my $title = norm($prog->findvalue( 'IdentificationName' ) );

        # TNT SERIE & TNT FILM
        $start = create_dt($prog->findvalue( './StartDateTimeSec' ) ) if $prog->findvalue( './StartDateTimeSec' );
        $end = create_dt($prog->findvalue( './EndDateTimeSec' ) ) if $prog->findvalue( './EndDateTimeSec' );

        # Boomerang & CN
        $start = create_dt($prog->findvalue( './StartDateTime' ) ) if $prog->findvalue( './StartDateTime' );
        $end = create_dt($prog->findvalue( './EndDateTime' ) ) if $prog->findvalue( './EndDateTime' );

        my $desc = $prog->findvalue( 'ExtendedEventDescription/EventDescription' );

        my $ce = {
            channel_id => $chd->{id},
            title => norm($title),
            start_time => $start->hms(":"),
            end_time => $end->hms(":"),
            description => norm($desc),
        };

        # Extra info
        my $title_org = $prog->findvalue( 'ExtendedEventDescription/English_Programme_title' );
        my $season  = $prog->findvalue( 'ExtendedEventDescription/SeasonNo' );
        my $episode = $prog->findvalue( 'ExtendedEventDescription/EpisodeNo' );
        my $subtitle = $prog->findvalue( 'ExtendedEventDescription/German_episode_title' );
        my $subtitle_org = $prog->findvalue( 'ExtendedEventDescription/English_Episode_title' );

        my $genre = $prog->findvalue( 'ExtendedEventDescription/genre' );

        my ($program_type, $category ) = $ds->LookupCat( "Turner_xml", $genre );
		AddCategory( $ce, $program_type, $category );

        # Extra info
        my @actors;
        my @directors;

        my $ns2 = $prog->find( './ExtendedEventDescription/Item' );

        foreach my $item ($ns2->get_nodelist)
        {
            my $itype = $item->findvalue( 'ItemDescription' );
            my $itext = $item->findvalue( 'ItemText' );

            if(norm($itype) =~ /^Director/) {
                $ce->{program_type} = "movie";
                push @directors, norm($itext);
            }

            if(norm($itype) =~ /^Actor/) {
                push @actors, norm($itext);
            }

            if(norm($itype) eq "Year" and ($itext =~ /(\d\d\d\d)/)) {
                $ce->{production_date} = "$1-01-01";
            }
        }

        # add them
        if( scalar( @actors ) > 0 )
        {
            $ce->{actors} = join ";", @actors;
        }

        if( scalar( @directors ) > 0 )
        {
            $ce->{directors} = join ";", @directors;
        }

        if( defined $season and $season ne "" ) {
      		$ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
      	} elsif( defined $episode and $episode ne "" ) {
      		$ce->{episode} = sprintf( ". %d .", $episode-1 );
      	}

      	# Subtitle
      	$ce->{subtitle} = norm($subtitle) if defined $subtitle and norm($subtitle) ne "";
      	$ce->{original_subtitle} = norm($subtitle_org) if defined $subtitle_org and norm($subtitle_org) ne "";

        if(norm($ce->{original_subtitle}) =~ /, The$/i) {
            $ce->{original_subtitle} =~ s/, The//i;
            $ce->{original_subtitle} = norm("The ".norm($ce->{original_subtitle}));
        }

        if(norm($ce->{original_subtitle}) =~ /, A$/i) {
            $ce->{original_subtitle} =~ s/, A//i;
            $ce->{original_subtitle} = norm("A ".norm($ce->{original_subtitle}));
        }

      	$title_org =~ s/\- Season (\d+)$//i if defined $title_org and norm($title_org) ne "";

        if(norm($title_org) =~ /, The$/i) {
            $title_org =~ s/, The//i;
            $title_org = norm("The ".norm($title_org));
        }

        $ce->{original_title} = norm($title_org) if defined $title_org and norm($title_org) ne norm($title) and norm($title_org) ne "";

        progress( "Turner_xml: $chd->{xmltvid}: $start - $title" );
        $dsh->AddProgramme( $ce );
    }
  } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}

sub create_dt
{
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
                          time_zone => 'Europe/Stockholm',
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;