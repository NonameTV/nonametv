package NonameTV::Importer::CNBCEurope;

use strict;
use warnings;

=pod

Imports data for CNBC Europe. The files are in XML format.
Files is sent via mail.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;
use File::Temp qw/tempfile/;
use File::Slurp qw/write_file read_file/;

use NonameTV qw/norm ParseDescCatSwe ParseXml AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "GMT" );
  $self->{datastorehelper} = $dsh;

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

  my $data = read_file($file);

  if(!defined($data)) {
    return 0;
  }

$data =~ s|
||g;
$data =~ s| xmlns="urn:crystal-reports:schemas:report-detail"||;

  my $doc = XML::LibXML->load_xml(string => $data);

  my $currdate = "x";
  my $column;

  # the grabber_data should point exactly to one worksheet
  my $rows = $doc->findnodes( './/CrystalReport/Group[@Level="1"]' );

  if( $rows->size() == 0 ) {
    error( "CNBCEurope: $chd->{xmltvid}: No Rows found" ) ;
    return;
  }

  foreach my $row ($rows->get_nodelist) {
      my $date = $self->create_dt( $row->findvalue( './/GroupHeader/Section/Field/Value' ) );
      $date = $date->ymd("-");

      # Date
      if($date ne $currdate ) {
        if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
        }

        my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("CNBCEurope: Date is: $date");
      }

      # Programs
      my $progs = $row->findnodes( './/Group[@Level="2"]' );

      if( $progs->size() == 0 ) {
          error( "CNBCEurope: $chd->{xmltvid}: No Programs found" ) ;
      }

      foreach my $prog ($progs->get_nodelist) {
        my $title = $prog->findvalue( './/Field[@Name="programName1"]/Value' );
        $title =~ s/16:9//gi;

        $title =~ s/1st hr//gi;
        $title =~ s/2nd & 3rd hr//gi;
        $title =~ s/\#(\d+) Hour(s|)//gi;
        $title =~ s/\((\d+) Part(|s)\)//gi;
        $title =~ s/2nd hr//gi;
        $title =~ s/3rd hr//gi;
        $title =~ s/1st hour//gi;
        $title =~ s/1 hour//gi;
        $title =~ s/Series (\d+)//gi;
        $title =~ s/2nd hour//gi;
        $title =~ s/3rd hour//gi;
        $title =~ s/\#(\d+) min//gi;
        $title =~ s/\#(\d+)min//gi;
        $title =~ s/\#(\d+)//gi;
        $title =~ s/\(UNSPONSORED\)//gi;
        $title =~ s/\(f\)//gi;
        $title =~ s/\(g\)//gi;
        $title =~ s/^L\-//gi;

        $title = norm($title);


        $title =~ s/-$//;
        #$title =~ s/\: ep (\d+)$//i;

        my $start = $prog->findvalue( './/Field[@Name="hour1"]/Value' );

        my $desc2 = $prog->findvalue( './/Field[@Name="Synopsis1"]/Value' );
        my $desc3 = $prog->findvalue( './/Field[@Name="result1"]/Value' );
        my $desc = $desc2 || $desc3;

        my $ce = {
                channel_id => $chd->{id},
                title => norm($title),
                start_time => $start,
                description => norm($desc),
              };


        my( $t, $st ) = ($ce->{title} =~ /^(.*)\:(.*)/);
        if( defined( $st ) )
        {
          # This program is part of a series and it has a colon in the title.
          # Assume that the colon separates the title from the subtitle.
          $ce->{title} = ucfirst(lc(norm($t)));
          $ce->{subtitle} = ucfirst(lc(norm($st)));

          # Episode
          my($episode);
          ( $episode ) = ($ce->{title} =~ /ep\s+(\d+)$/i );
          ( $episode ) = ($ce->{subtitle} =~ /Episode\s+(\d+)$/i );
          ( $episode ) = ($ce->{subtitle} =~ /Episode\s+number\s+(\d+)$/i );
          $ce->{title} =~ s/\: ep (\d+)$//i;
          if($ce->{title} =~ /^Cnbc originals/i) {
            $ce->{title} = "CNBC Originals";
          }
          $ce->{title} =~ s/-$//;

          if($episode) {
            $episode+=0; # Remove leading zeros
            $ce->{subtitle} = undef; # Remove subtitle, its a ep number not a subtitle.
            $ce->{episode} = ". " . ($episode-1) . " .";
          }

          # Jimmy Fallon
          if($ce->{title} eq "The tonight show starring jimmy fallon" or $ce->{title} eq "Tonight show starring jimmy fallon") {
            $ce->{title} = "The Tonight Show Starring Jimmy Fallon";

            # Might get removed if the subtitle is an episode num
            if(defined($ce->{subtitle})) {
                $ce->{subtitle} =~ s/\b(\w)/\U$1/g; # Big letter every word, its a name.
                $ce->{guests} = $ce->{subtitle};
            }
          } else {
            $ce->{title} =~ s/\b(\w)/\U$1/g; # Big letter every word, its a name.
            $ce->{title} =~ s/Cnbc/CNBC/i;
            $ce->{title} =~ s/Nbc/NBC/i;
            $ce->{title} =~ s/^Us/US/i;
            $ce->{title} =~ s/Us Pga$/US PGA/i;
            $ce->{title} = norm($ce->{title});
          }
        }

        progress( "CNBCEurope: $chd->{xmltvid}: $start - $ce->{title}" );

        $dsh->AddProgramme( $ce );
      }

  } # next row

  $dsh->EndBatch( 1 );

  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
    $str =~ s/\..*$//;
  my( $date, $time ) = split( 'T', $str );

print("date: $date\n");
#print("time: $time\n");

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '-', $date );

  # Remove the dot and everything after it.


  my( $hour, $minute, $second ) = split( ":", $time );



  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'GMT',
                          );
 ##
 ##$dt->set_time_zone( "UTC" );

  return $dt;
}

1;