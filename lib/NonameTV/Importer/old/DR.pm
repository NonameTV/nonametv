package NonameTV::Importer::DR;

use strict;
use warnings;

=pod

Import data from dr.dk. Data is downloaded in structured text-files.

According to their press-contact, the data on the site will not be updated
with last-minute changes. These are only distributed via mail and are
currently not taken into account.

On the site, there are two types of files: Hvid and Blå.

Blå - er vores foreløbige sendeplan. Der mangler en del udsendelser og
vi ændrer tit programmerne uden at give besked.

Hvid - er den endelige sendeplan. Hvis vi ændrer i noget, sender vi
altid 'Hvide rettelser'.

i.e. Blå - preliminary schedule. Can be updated at any time.
Hvid - Final schedule. Only updated via "changes-documents".

=cut

use DateTime;
use Encode;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    # The data contains duplicates. Ignore them.
    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  # Prefer Hvid but sometimes only Blå exists.
  my $url1 = sprintf( "%s%s_%4d_%d_Hvid.txt",
		      $self->{UrlRoot}, $chd->{grabber_info}, 
		      $year, $week );
  my $url2 = sprintf( "%s%s_%4d_%d_Blå.txt",
		      $self->{UrlRoot}, $chd->{grabber_info}, 
		      $year, $week );

  return( [$url1, $url2], undef );
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  if( $$cref eq '<script type="text/javascript" src="http://www.dr.dk/drdk404/404.js"></script>' ) {
    return "404 not found";
  }
  else {
    return undef;
  }
}

sub ContentExtension {
  return 'txt';
}

sub FilteredExtension {
  return 'txt';
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Decode the string into perl's internal format.
  # see perldoc Encode

  my $str = decode( "windows-1252", $$cref );

  my @rows = split("\n", $str );

  if( scalar( @rows < 2 ) ) {
    f "No data found";
    return 0;
  }

  my $date = undef;
  my $ce;

  for ( my $i = 0; $i < scalar @rows; $i++ ) {
    next if $rows[$i] =~ /^\s*$/;

    my @columns = split( "\t", $rows[$i] );

    if( $columns[0] eq "D" ) {
      my $newdate = $columns[1];
      $newdate =~ s/(\d{4})(\d{2})(\d{2})/$1-$2-$3/;
      $dsh->StartDate( $newdate );
      $date = $newdate;
    }
    elsif( $columns[0] eq "O" ) {
      if( not defined( $date ) ) {
	w "O without D.";
	next;
      }
      
      if( defined( $ce ) ) {
	finish_programme( $dsh, $ce );
      }
      
      $ce = {};
      $ce->{start_time} = $columns[1];
      $ce->{title} = $columns[2];
      $ce->{description} = [];
    }
    elsif( $columns[0] eq "U" ) {
      push @{$ce->{description}}, $columns[2];
    }
    elsif( $columns[0] eq "P" ) {
      # Ignore
    }
    else {
      f "Unknown row-type '$columns[0]' in row $i";
      return 0;
    } 
  }

  finish_programme( $dsh, $ce );

  # Success
  return 1;
}

sub finish_programme {
  my( $dsh, $ce ) = @_;

  $ce->{start_time} =~ s/\./:/;

  # Some programs have no titles. This is probably an error in the data,
  # but there is nothing we can do about it.
  return if( $ce->{title} =~ /^\s*$/ );
  
  # The title field contains various "markings" that mean different things.
  # Parse and remove them.

  # Episodes
  my( $ep, $eps ) = ($ce->{title} =~ m/\((\d+):(\d+)\)/);
  if( defined( $eps ) ) {
    $ce->{episode} = " . " . ($ep-1) . "/" . $eps . " . ";
    $ce->{title} =~ s/\(\d+:\d+\)//;
  }
  else {
    ( $ep ) = ($ce->{title} =~ m/\((\d+)\)/);
    if( defined( $ep ) ) {
      $ce->{episode} = " . " . ($ep-1) . " . ";
      $ce->{title} =~ s/\(\d+\)//;
    }
  }

  $ce->{title} =~ s/16:9//;
  $ce->{title} =~ s/UTXT//;
  $ce->{title} =~ s/Surround//;
 

  $ce->{title} = norm( $ce->{title} );
  if( $ce->{title} eq "Godnat" ) {
    $ce->{title} = "end-of-transmission";
  }

  $ce->{description} = norm( join( " ", @{$ce->{description}} ) );
  $dsh->AddProgramme( $ce );
}

1;
