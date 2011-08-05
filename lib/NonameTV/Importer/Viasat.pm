package NonameTV::Importer::Viasat;

use strict;
use warnings;

=pod

Import data from Viasat's press-site. The data is downloaded in
tab-separated text-files.

Features:

Proper episode and season fields. The episode-field contains a
number that is relative to the start of the series, not to the
start of this season.

program_type

=cut


use DateTime;
use Encode;

use NonameTV qw/AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    # flag to enable decoding according to charset in Content-Type header
    $self->{cc}->{wantdecode} = 1;
    
    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "%s%s%02d-%02d_tab.txt",
                     $self->{UrlRoot}, $chd->{grabber_info}, 
                     $year, $week );

  return( $url, undef );
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

  my $str = decode( "utf-8", $$cref );

  my @rows = split("\n", $str );

  if( scalar( @rows < 2 ) )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  my $columns = [ split( "\t", $rows[0] ) ];

  for ( my $i = 1; $i < scalar @rows; $i++ )
  {
    my $inrow = $self->row_to_hash($batch_id, $rows[$i], $columns );
    
    if ( exists($inrow->{'Date'}) )
    {
      $dsh->StartDate( $inrow->{'Date'} );
    }
    
    my $start = $inrow->{'Start time'};

    my $title = norm( $inrow->{'name'} );
    
    # Maybe we should put original title in a column sometime?
    #my $title_org = norm( $inrow->{'org name'} );

		#my $title = $title_org || $title_normal;

    my $description = $inrow->{'Synopsis this episode'}
    || $inrow->{'Synopsis'}; 
    
    $description = norm( $description );
    
    # Episode info in xmltv-format
    my $ep_nr = $inrow->{'episode nr'} || 0;
    my $ep_se = $inrow->{'Season number'} || 0;
    my $episode = undef;
    
    # Del 3:13 in description - of_episod is not in use at the moment
    my ( $ep_nr2, $eps ) = ($description =~ /del\s+(\d+):(\d+)/ );
    my ( $ep_nr3, $eps2 ) = ($description =~ /Del\s+(\d+):(\d+)/ );
    
    if((defined $ep_nr2)) {
    	$ep_nr = $ep_nr2;
    }
    
    if((defined $ep_nr3)) {
    	$ep_nr = $ep_nr3;
    }
    
    if((defined $ep_nr) and ($ep_nr > 0) and ($ep_se > 0) )
    {
      $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
    }
    elsif((defined $ep_nr) and ($ep_nr > 0) )
    {
      $episode = sprintf( ". %d .", $ep_nr-1 );
    }

    my $ce = {
      title => $title,
      description => $description,
      start_time => $start,
      episode => $episode,
      Viasat_category => norm( $inrow->{Category} ),
      Viasat_genre => norm( $inrow->{Genre} ),
    };
    
    if( my( $commentators ) = ($description =~ /Kommentatorer:\s*(.*)/ ) )
    {
      $ce->{commentators} = parse_person_list( $commentators );
    }

    if( defined( $inrow->{'Production Year'} ) and
        $inrow->{'Production Year'} =~ /(\d\d\d\d)/ )
    {
      $ce->{production_date} = "$1-01-01";
    }

    my $cast = norm( $inrow->{'Cast'} );
    if( $cast =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $cast =~ s/\s*m[\. ]*fl\.*\b//;

      # Remove trailing '.'
      $cast =~ s/\.$//;

      my @actors = split( /\s*,\s*/, $cast );
      foreach (@actors)
      {
        # The character name is sometimes given in parentheses. Remove it.
        # The Cast-entry is sometimes cutoff, which means that the
        # character name might be missing a trailing ).
        s/\s*\(.*$//;
      }
      $ce->{actors} = join( ", ", grep( /\S/, @actors ) );
    }

    my $director = norm( $inrow->{'Director'} );
    if( $director =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $director =~ s/\s*m[\. ]*fl\.*\b//;
      
      # Remove trailing '.'
      $director =~ s/\.$//;
      my @directors = split( /\s*,\s*/, $director );
      $ce->{directors} = join( ", ", grep( /\S/, @directors ) );
    }
    
    my $guest = norm( $inrow->{'Guest'} );
    if( $guest =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $guest =~ s/\s*m[\. ]*fl\.*\b//;
      
      # Remove trailing '.'
      $guest =~ s/\.$//;
      my @guests = split( /\s*,\s*/, $guest );
      $ce->{guests} = join( ", ", grep( /\S/, @guests ) );
    }
    
    my $host = norm( $inrow->{'Host'} );
    if( $host =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $host =~ s/\s*m[\. ]*fl\.*\b//;
      
      # Remove trailing '.'
      $host =~ s/\.$//;
      my @hosts = split( /\s*,\s*/, $host );
      $ce->{presenters} = join( ", ", grep( /\S/, @hosts ) );
    }
    
    my $commentator = norm( $inrow->{'Commentator'} );
    if( $commentator =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $commentator =~ s/\s*m[\. ]*fl\.*\b//;
      
      # Remove trailing '.'
      $commentator =~ s/\.$//;
      my @commentators = split( /\s*,\s*/, $commentator );
      $ce->{commentators} = join( ", ", grep( /\S/, @commentators ) );
    }

    $self->extract_extra_info( $ce );
    
    progress("Viasat: $chd->{xmltvid}: $start - $title");
    $dsh->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub row_to_hash
{
  my $self = shift;
  my( $batch_id, $row, $columns ) = @_;

  my @coldata = split( "\t", $row );
  my %res;
  
  if( scalar( @coldata ) > scalar( @{$columns} ) )
  {
    error( "$batch_id: Too many data columns " .
           scalar( @coldata ) . " > " . 
           scalar( @{$columns} ) );
  }

  for( my $i=0; $i<scalar(@coldata) and $i<scalar(@{$columns}); $i++ )
  {
    $res{$columns->[$i]} = norm($coldata[$i])
      if $coldata[$i] =~ /\S/; 
  }

  return \%res;
}

sub extract_extra_info
{
  my $self = shift;

  my( $ce ) = @_;

  my $ds = $self->{datastore};

  my $ltitle = lc $ce->{title};

  if ( ($ltitle eq "slut") or
       ($ltitle eq "godnatt") or
       ($ltitle eq "end") or
       ($ltitle eq "close") or
       ($ltitle eq "pause") or
       ($ltitle eq "*end") )               
  {
    $ce->{title} = "end-of-transmission";
  }

  # Remove trailing . from category.
  my $viasat_cat = $ce->{Viasat_category};
  $viasat_cat =~ s/\.\s*$//;
  
  my( $pty, $cat ) = $ds->LookupCat( 'Viasat_category', $viasat_cat );
  AddCategory( $ce, $pty, $cat );
  
  my $viasat_genre = $ce->{Viasat_genre};
  $viasat_genre =~ s/\.\s*$//;

  ( $pty, $cat ) = $ds->LookupCat( 'Viasat_genre', $viasat_genre );
  AddCategory( $ce, $pty, $cat );
  
  delete( $ce->{Viasat_category} );
  delete( $ce->{Viasat_genre} );
}

# From Kanal5_util
sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  
  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}

1;
