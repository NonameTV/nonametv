package NonameTV::Importer::Venetsia;

use strict;
use warnings;

=pod

Imports data for YLE Channels and more provided by Venetsia,

The file is downloaded by YOU seperately from the site in a TAR file
inside of it, it is alot of PER DAY files.

Their site is too hard coded to do this automaticly in the script.

TV Channels: Yle TV1, Yle TV2, MTV3, Nelonen, Sub, SuomiTV, TV5, Yle Teema, Yle Fem, Yle HD, JIM, Liv, AVA, TV Finland,
						 Nelonen Kino, Nelonen Perhe, Nelonen Maailma, MTV3 MAX, MTV3 Fakta, MTV3 Sarja, MTV3 Scifi, MTV3 Komedia,
						 MTV3 LEFFA, MTV3 Juniori, Nelonen Pro 1, Nelonen Pro 2

Radio Channels: Yle Radio Suomi, Yle Puhe, Yle Radio 1, YleX, Yle Klassinen, Yle Mondo, Etelä-Karjalan Radio, Etelä-Savon Radio,
								Kainuun Radio, Kymenlaakson Radio, Lahden Radio, Lapin Radio, Oulu Radio, Pohjanmaan Radio, Pohjois-Karjalan Radio,
								Radio Häme, Radio Itä-Uusimaa, Radio Keski-Pohjanmaa, Radio Keski-Suomi, Radio Perämeri, Radio Savo, Satakunnan Radio,
								Tampereen Radio, Turun Radio, Ylen aikainen, Ylen läntinen, Yle Sámi Radio, Yle Radio Vega, Yle X3M, Radio Vega Huvudstadsregionen,
								Radio Vega Västnyland, Radio Vega Åboland, Radio Vega Österbotten, Radio Vega Östnyland, YleSat 1, YleSat 2, Radio Nova

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;

use NonameTV qw/norm ParseXml/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Helsinki" );
  $self->{datastorehelper} = $dsh;
  
  # use augment
  #$self->{datastore}->{augment} = 1;

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

  progress( "Venetsia: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "Venetsia: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( "//ProgramItem" );

    if( $rows->size() == 0 ) {
      error( "Venetsia: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  foreach my $row ($rows->get_nodelist) {
      my $time = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramLocationTable/tva:BroadcastEvent/tva:PublishedStartTime' ));
      my $title = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramInformation/tva:BasicDescription/tva:Title' ));
      my $description = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramInformation/tva:BasicDescription/tva:Synopsis' ));
      
      my $start = $self->create_dt( $time );
      
      # Add hours specificed for each channel. (TV Finland has 3 hours if you are in Sweden, etc.)
      $start->add( hours => $chd->{grabber_info} );
      
      my $date = $start->ymd("-");
      
      # Remove Stuff
      $title =~ s/SVT://;
      $title =~ s/\(T\)//;
      $title =~ s/\(\d*\)//;
      
      $title = norm($title);
      
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
					$dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Venetsia: Date is: $date");
      }


      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->hms(":"),
        description => $description,
      };
      
  		# Try to extract episode-information from the description.
  		my( $ep, $eps, $name, $dummy, $episode );

  		# Del 2
  		( $dummy, $ep ) = ($description =~ /\b(Del|Avsnitt)\s+(\d+)/ );
  		$episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  		# Del 2 av 3
  		( $dummy, $ep, $eps ) = ($description =~ /\b(Del|Avsnitt)\s+(\d+)\s*av\s*(\d+)/ );
 		 	$episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    	if defined $eps;
  
  		if( defined $episode ) {
    		if( exists( $ce->{production_date} ) ) {
      		my( $year ) = ($ce->{production_date} =~ /(\d{4})-/ );
      		$episode = ($year-1) . $episode;
    		}
    		
    		$ce->{episode} = $episode;
    		# If this program has an episode-number, it is by definition
    		# a series (?). Svt often miscategorize series as movie.
    		$ce->{program_type} = 'series';
  		}
     
     if( $description =~ /Del\s+\d+\.*/ )
    {
      # Del 2 av 3: Pilot (episodename)
 	  	#( $ce->{subtitle} ) = ($description =~ /:\s*(.+)\./);
 	  
 	  	# norm
 	  	#$ce->{subtitle} = norm($ce->{subtitle});
 		}
     
     progress( "Venetsia: $chd->{xmltvid}: $start - $title" );
     $dsh->AddProgramme( $ce );

    } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  
  # Remove timezone shitty
  $str =~ s/\+02:00$//;
  
  my( $date, $time ) = split( 'T', $str );

  my( $year, $month, $day ) = split( '-', $date );
  
  my( $hour, $minute, $second ) = split( ":", $time );
  

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Helsinki',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;
