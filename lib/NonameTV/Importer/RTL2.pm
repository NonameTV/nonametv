package NonameTV::Importer::RTL2;

use strict;
use warnings;

=pod

Imports data for RTL2.de. The files are sent through MAIL and is in XML format.

Features:
Season, actors, English title

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Munich" );
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

  progress( "RTL2: $chd->{xmltvid}: Processing XML $file" );


  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "RTL2: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( ".//programmElement" );

    if( $rows->size() == 0 ) {
      error( "RTL2: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  foreach my $row ($rows->get_nodelist) {
      my $title = norm($row->findvalue( './/header//stitel' ) );

      my $org_title = norm($row->findvalue( './/header//otitel' ) );
      my $time = $row->findvalue( './/header//szeit' );
      my $type = $row->findvalue( './@typ' );
      my $rerun = $row->findvalue( './@rerun' );

      my $date = $row->findvalue( './/header//kdatum' );
      $date =~ s/\./-/g; # They fail sometimes
	  my $start = $self->create_dt( $date."T".$time );
	  $date = $start->ymd("-");

	  if( $date ne $currdate ){
      	progress("RTL2: Date is $date");

        if( $currdate ne "x" ) {
        	$dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        #$dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

	  # extra info
	  my $desc = norm( $row->findvalue( './/langinhalt' ) );
	  my $year = $row->findvalue( './/header//produktionsjahr' );
	  my $hd = $row->findvalue( './/header//label//hd' );
	  my $genre = $row->findvalue( './/header//pressegenre');
	  my $prodco = $row->findvalue( './/header//produktionsland');
	  my $aspect = $row->findvalue( './/header//bildformat');

	  my $subtitle = $row->findvalue( './/header//epistitel' );
	  my $subtitle_org = $row->findvalue( './/header//oepistitel' );

      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start,
      };

      if(defined $prodco and $prodco ne "") {
        my @conts = split(', ', norm($prodco));
        my @countries;

        foreach my $c (@conts) {
            my ( $c2 ) = $self->{datastore}->LookupCountry( "KFZ", $c );
            push @countries, $c2 if defined $c2;
        }

        if( scalar( @countries ) > 0 )
        {
              $ce->{country} = join "/", @countries;
        }
      }

      if( defined( $year ) and ($year =~ /(\d\d\d\d)/) )
    	{
      		$ce->{production_date} = "$1-01-01";
    	}


      if( defined( $subtitle ) and ($subtitle ne '') )
      {
            $ce->{subtitle} = norm($subtitle);
      }

     #print Dumper($ce);

     # hd
    if( $hd eq "true") {
     	$ce->{quality} = "HDTV";
    }

    my @actors;
    my @directors;
    my @writers;

    my $ns2 = $row->find( './/mitwirkende//Darsteller' );
    foreach my $act ($ns2->get_nodelist)
    {
		my $name = norm( $act->findvalue('./pname') );

        # Role played - TODO: Add rolename to the actor
        if( $act->findvalue('./rname') and norm($act->findvalue('./rname')) ne "" ) {
        	my $name .= " (".norm( $act->findvalue('./rname') ).")";
        }

        push @actors, $name;
    }

    my $ns3 = $row->find( './/mitwirkende//Stab' );
    foreach my $stab ($ns3->get_nodelist)
    {
    	my $name = norm( $stab->findvalue('./pname') );

        # Type
        my $type = norm( $stab->findvalue('./@typ') );

		# Directors
		if($type eq "Regie") {
			push @directors, $name;
		}

		# Writers
        if($type eq "Drehbuch") {
			push @writers, $name;
		}
    }

    # Actors
	if( scalar( @actors ) > 0 )
	{
		$ce->{actors} = join ";", @actors;
    }

    if( scalar( @directors ) > 0 )
    {
        $ce->{directors} = join ";", @directors;
    }

    if( scalar( @writers ) > 0 )
    {
        $ce->{writers} = join ";", @writers;
    }

    # Genre
    my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "RTL2", $genre );
    # movie
    if( $type eq "Film") {
       AddCategory( $ce, 'movie', $categ );
    } elsif($type eq "Serie") {
        AddCategory( $ce, 'series', $categ );
    } elsif($type eq "Sonderablauf") {
        AddCategory( $ce, 'tvshow', $categ );
    } else {
        AddCategory( $ce, 'series', $categ );
    }

    $ce->{title} = norm($title);
    $ce->{original_title} = norm($org_title) if $org_title and $org_title ne $title;
    $ce->{original_subtitle} = norm($subtitle_org) if $subtitle_org and $subtitle ne $subtitle_org;

    $ce->{aspect} = norm($aspect) if $aspect;

     progress( "RTL2: $chd->{xmltvid}: $start - $title" );
     $dsh->AddCE( $ce );

    } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $date, $time ) = split( 'T', $str );

  my( $day, $month, $year ) = split( '-', $date );

  my( $hour, $minute ) = split( ":", $time );


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