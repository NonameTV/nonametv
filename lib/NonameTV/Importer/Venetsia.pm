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

Radio Channels: Yle Radio Suomi, Yle Puhe, Yle Radio 1, YleX, Yle Klassinen, Yle Mondo, Etel�-Karjalan Radio, Etel�-Savon Radio,
								Kainuun Radio, Kymenlaakson Radio, Lahden Radio, Lapin Radio, Oulu Radio, Pohjanmaan Radio, Pohjois-Karjalan Radio,
								Radio H�me, Radio It�-Uusimaa, Radio Keski-Pohjanmaa, Radio Keski-Suomi, Radio Per�meri, Radio Savo, Satakunnan Radio,
								Tampereen Radio, Turun Radio, Ylen aikainen, Ylen l�ntinen, Yle S�mi Radio, Yle Radio Vega, Yle X3M, Radio Vega Huvudstadsregionen,
								Radio Vega V�stnyland, Radio Vega �boland, Radio Vega �sterbotten, Radio Vega �stnyland, YleSat 1, YleSat 2, Radio Nova

=cut

use utf8;

use DateTime;
use DateTime::TimeZone;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;
use File::Basename;

use NonameTV qw/norm ParseXml AddCategory/;
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

  my $filename = fileparse($file);
  my ( $id, $filedate ) = split(/_/, $filename);

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
  my $hours = 3;
  #if($chd->{grabber_info} != "") {
  #  $hours = $chd->{grabber_info};
  #}

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( "//ProgramItem" );

    if( $rows->size() == 0 ) {
      error( "Venetsia: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  $dsh->StartBatch( $chd->{xmltvid}."_".$filedate , $chd->{id} );
  foreach my $row ($rows->get_nodelist) {
      my $time        = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramLocationTable/tva:BroadcastEvent/tva:PublishedStartTime' ));
      my $endtime     = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramLocationTable/tva:BroadcastEvent/tva:PublishedEndTime' ));
      my $title       = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramInformation/tva:BasicDescription/tva:Title' ));
      my $description = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramInformation/tva:BasicDescription/tva:Synopsis' ));
      my $genre       = norm($row->findvalue( './/ProgramInformation/tva:ProgramDescription/tva:ProgramInformation/tva:BasicDescription/tva:Genre' ));
      
      my $start = $self->create_dt( $time );
      my $end = $self->create_dt( $endtime );

      # Different timezone (need to be -1 hour)
      if($chd->{grabber_info} eq "UTC") {
        #my ( $date, $tz ) = split(/\+/, $time);
        #my( $timezone_hour, $timezone_minute ) = ($tz =~ /^(\d+):(\d+)$/ );
        #$timezone_hour =~ s/^0+//;

          # DST removal thingy
          #$start->subtract( hours => $timezone_hour ); # Daylight saving time
          #$end->subtract( hours => $timezone_hour ); # Normal time
      }

      # TV Finland schedule is actually GMT+2 when the Finland timezones is GMT+3 (so add a hour which got removed)
      if($chd->{xmltvid} eq "tvfinland.yle.fi") {
        $start->add( hours => 1 );
        $end->add( hours => 1 );
      }
      
      # Add hours specificed for each channel. (TV Finland has 3 hours if you are in Sweden, etc.)
      #$start->add( hours => $hours );
      
      my $date = $start->ymd("-");
      
      # Remove Stuff
      $title =~ s/SVT://;
      $title =~ s/FOX\s+Kids://;
      $title =~ s/\(T\)//;
      $title =~ s/\(S\)//;
      $title =~ s/Elokuva://;
      $title =~ s/\(TXT\)//;
      $title =~ s/\(.*\)//;
      $title =~ s/Series\s+\d+//;
      $title =~ s/YR\d+//;
      $title =~ s/\s+Y\d+//;
      $title =~ s/\s+S\d+//;
      $title =~ s/Elokuva://;
      $title =~ s/Elokuvat://;
      $title =~ s/Kino://;
      $title =~ s/Bio\s+Klassiker://;
      $title =~ s/Sommarbio://;
      $title =~ s/Film://;
      $title =~ s/\.$//; # remove ending dot.
      
      $title = norm($title);
      
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
		#			$dsh->EndBatch( 1 );
        }

        #my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Venetsia: Date is: $date");
      }


      my $ce = {
        channel_id  => $chd->{id},
        title       => norm($title),
        start_time  => $start,
        end_time    => $end,
      };

      if(defined($description) and $description ne "") {
        $ce->{description} = norm($description);
      }

 	 ## Stuff
 	 my @sentences = (split_text( $description ), "");
 	 my $season = "0";
 	 my $episode = "0";
 	 my $eps = "0";

      if( defined($sentences[0]) and $sentences[0] =~ /\bfr.n (\d\d\d\d)\b/ )
      {
        $ce->{production_date} = "$1-01-01";
      }

           for( my $i2=0; $i2<scalar(@sentences); $i2++ )
       	  {
       	  	if( my( $seasontextnum ) = ($sentences[$i2] =~ /^Kausi (\d+)./ ) )
     	    {
     	      $season = $seasontextnum;

     	      # Only remove sentence if it could find a season
     	      if($season ne "") {
     	      	$sentences[$i2] = "";
     	      }
     	    }elsif( my( $seasontextnum12 ) = ($sentences[$i2] =~ /^Säsong (\d+)(\d+)./i ) )
     	    {
     	      $season = $seasontextnum12;

     	      # Only remove sentence if it could find a season
     	      if($season ne "") {
     	      	$sentences[$i2] = "";
     	      }
     	    } elsif( my( $seasontextnum11, $episoder, $ofepisodess ) = ($sentences[$i2] =~ /^Säsong (\d+), del (\d+)\/(\d+)./i ) )
     	    {
     	      $season = $seasontextnum11;
     	      $episode = $episoder;
              $eps = $ofepisodess;

     	      # Only remove sentence if it could find a season
     	      if($season ne "") {
     	      	$sentences[$i2] = "";
     	      }
     	    }elsif( my( $seasontextnum9 ) = ($sentences[$i2] =~ /^(\d+) säsongen./i ) )
     	    {
     	      $season = $seasontextnum9;

     	      # Only remove sentence if it could find a season
     	      if($season ne "") {
     	      	$sentences[$i2] = "";
     	      }
     	    }
     	    elsif( my( $dummy4 ) = ($sentences[$i2] =~ /^S(\s*)songsstart./i ) )
            {
                $sentences[$i2] = "";
            }elsif( my( $episodetextnum5, $ofepisode3 ) = ($sentences[$i2] =~ /^(\d+)\/(\d+)./ ) )
            {
            	$episode = $episodetextnum5;
            	$eps = $ofepisode3;

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum4, $ofepisode2 ) = ($sentences[$i2] =~ /Del (\d+)\/(\d+)./i ) )
            {
            	$episode = $episodetextnum4;
            	$eps = $ofepisode2;

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum8, $ofepisode8, $epititle2 ) = ($sentences[$i2] =~ /^Del (\d+) av (\d+)\:(.*)./i ) )
            {
            	$episode = $episodetextnum8;
            	$eps = $ofepisode8;
            	$ce->{subtitle} = norm($epititle2);

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum11, $ofepisode11) = ($sentences[$i2] =~ /^(\d+)\/(\d+)./ ) )
            {
            	$episode = $episodetextnum11;
            	$eps = $ofepisode11;

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum7, $ofepisode7, $epititle ) = ($sentences[$i2] =~ /^Del (\d+)\/(\d+)\:(.*)./i ) )
            {
            	$episode = $episodetextnum7;
            	$eps = $ofepisode7;
            	$ce->{subtitle} = norm($epititle);

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum2, $ofepisode ) = ($sentences[$i2] =~ /^Del (\d+) av (\d+)./i ) )
            {
            	$episode = $episodetextnum2;
            	$eps = $ofepisode;

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum3 ) = ($sentences[$i2] =~ /^Del (\d+)./i ) )
            {
            	$episode = $episodetextnum3;

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            }elsif( my( $episodetextnum ) = ($sentences[$i2] =~ /^Osa (\d+)./ ) )
            {
            	$episode = $episodetextnum;

            	# Only remove sentence if it could find a season
            	if($episode ne "") {
                	$sentences[$i2] = "";
                }
            } elsif( my( $directors ) = ($sentences[$i2] =~ /^Ohjaus:\s*(.*)/) )
            {
                $ce->{directors} = parse_person_list( $directors );
                $sentences[$i2] = "";
            } elsif( my( $directors4 ) = ($sentences[$i2] =~ /^O:\s*(.*)/) )
            {
                $ce->{directors} = parse_person_list( $directors4 );
                $sentences[$i2] = "";
            }elsif( my( $actors5 ) = ($sentences[$i2] =~ /^P:\s*(.*)/ ) )
            {
                #$ce->{actors} = parse_person_list( $actors5 ); # not sure if producer or actor
                $sentences[$i2] = "";
            }elsif( my( $actors ) = ($sentences[$i2] =~ /^Pääosissa:\s*(.*)/ ) )
            {
                $ce->{actors} = parse_person_list( $actors );
                $sentences[$i2] = "";
            }elsif( my( $directors7 ) = ($sentences[$i2] =~ /^R:\s*(.*)/) )
            {
                $ce->{directors} = parse_person_list( $directors7 );
                $sentences[$i2] = "";
            }elsif( my( $actors7 ) = ($sentences[$i2] =~ /^S:\s*(.*)/ ) )
            {
                $ce->{actors} = parse_person_list( $actors7 );
                $sentences[$i2] = "";
            }elsif( my( $actors9 ) = ($sentences[$i2] =~ /^Programledare:\s*(.*)/ ) )
            {
                $ce->{presenters} = parse_person_list( $actors9 );
                $sentences[$i2] = "";
            }

            elsif( my( $directors2 ) = ($sentences[$i2] =~ /^Regi:\s*(.*)/) )
            {
                  $ce->{directors} = parse_person_list( $directors2 );
                  $sentences[$i2] = "";
            }
            elsif( my( $directors3 ) = ($sentences[$i2] =~ /^Regi\s*(.*)/) )
            {
                  $ce->{directors} = parse_person_list( $directors3 );
                  $sentences[$i2] = "";
            }
            elsif( my( $writers2 ) = ($sentences[$i2] =~ /^Manus:\s*(.*)/) )
            {
                  $ce->{writers} = parse_person_list( $writers2 );
                  $sentences[$i2] = "";
            }
            elsif( my( $actors2 ) = ($sentences[$i2] =~ /^I rollerna:\s*(.*)/ ) )
            {
                  $ce->{actors} = parse_person_list( $actors2 );
                  $sentences[$i2] = "";
            }
            elsif( my( $actors3 ) = ($sentences[$i2] =~ /^I huvudrollerna:\s*(.*)/ ) )
            {
                  $ce->{actors} = parse_person_list( $actors3 );
                  $sentences[$i2] = "";
            }
            elsif( my( $actors6 ) = ($sentences[$i2] =~ /^I huvudrollerna\s*(.*)/ ) )
            {
                  $ce->{actors} = parse_person_list( $actors6 );
                  $sentences[$i2] = "";
            }

            # Clean it up
            elsif( my( $rerun, $dummerinoerino3 ) = ($sentences[$i2] =~ /^\(R\)(|\.)/ ) )
            {
                  $sentences[$i2] = "";
            }
            elsif( my( $dunno, $dummerinoerino2 ) = ($sentences[$i2] =~ /^\(U\)(|\.)/ ) )
            {
                  $sentences[$i2] = "";
            }
            elsif( my( $hdtv, $dummerinoerino ) = ($sentences[$i2] =~ /^HD(|\.)$/ ) )
            {
                  $ce->{quality} = "HDTV";
                  $sentences[$i2] = "";
            }
     	 }

     	 my ( $season2 ) = ($description =~ /^(\d+). kausi./ ); # bugfix
     	 if(defined($season2) and $season == 0) {
     	 	$season = $season2;
     	 }

        my ( $season3 ) = ($description =~ /^(\d+). tuotantokausi./ ); # bugfix
     	 if(defined($season3) and $season == 0) {
     	 	$season = $season3;
     	 }

         my ( $episode2 ) = ($description =~ /^(\d+). jakso./ ); # bugfix
     	 if(defined($episode2) and $episode2 == 0) {
     	 	$episode = $episode2;
     	 }

     	 # Episode info in xmltv-format
               if( ($episode ne "0") and ( $eps ne "0") and ( $season ne "0") )
               {
                 $ce->{episode} = sprintf( "%d . %d/%d .", $season-1, $episode-1, $eps );
               }
               elsif( ($episode ne "0") and ( $eps ne "0") )
               {
                 	$ce->{episode} = sprintf( ". %d/%d .", $episode-1, $eps );
               }
               elsif( ($episode ne "0") and ( $season ne "0") )
               {
                 $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode-1 );
               }
               elsif( $episode ne "0" )
               {
               		$ce->{episode} = sprintf( ". %d .", $episode-1 );
               }

     $ce->{description} = join_text( @sentences );
     # Extra info
     my ( $extradesc ) = ($ce->{description} =~ /^\((.*)\)/ ); # bugfix

     if(!defined($extradesc)) {
        my ( $extradesc2, $tedummy ) = ($ce->{description} =~ /\((.*)\)(|\.)$/ ); # bugfix
        $extradesc = $extradesc2;
        $ce->{description} =~ s/\((.*)\)(|\.)$//i;
     }

     $ce->{description} =~ s/^\((.*)\)//i;
     $ce->{description} = norm($ce->{description});

     # Prod year - (Country Year)
     if(defined($extradesc) and $extradesc =~ /(\d\d\d\d)/) {
	  	$ce->{production_date} = "$1-01-01";
	 }

     # Remove if season = 0, episode 1, of_episode 1 - it's a one episode only programme
     #if(($episode eq "1") and ( $season eq "0")) {
     #	delete($ce->{episode});
     #}



     # Genre
     if(defined($genre) and $genre ne "") {
        my($program_type, $category ) = $ds->LookupCat( 'Venetsia', $genre );
          AddCategory( $ce, $program_type, $category );
     }

     $ds->AddProgramme( $ce );
     progress( "Venetsia: $chd->{xmltvid}: $start - $title" );

    } # next row

  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $year, $month, $day, $hour, $minute, $second, $timezone_hour, $timezone_minute ) = 
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)\+(\d+):(\d+)$/ );
  
  

  my $dt = DateTime->new( year      => $year,
                          month     => $month,
                          day       => $day,
                          hour      => $hour,
                          minute    => $minute,
                          time_zone => 'Europe/Helsinki'
                          );

  
  $dt->set_time_zone( "UTC" );
  return $dt;
}

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm()
  # Replace newlines followed by a capital with space and make sure that there
  # is a dot to mark the end of the sentence.
#  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  $str =~ s/\s*b[\. ]*la\.*\b//;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\b&\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}


1;
