package NonameTV::Importer::TV2;

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

use NonameTV qw/MyGet expand_entities AddCategory norm/;
#use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = 'TV2';

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    #my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    #$self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  #my $dsh = $self->{datastorehelper};

  # Decode the string into perl's internal format.
  # see perldoc Encode

#  my $str = decode( "utf-8", $$cref );
  my $str = decode( "iso-8859-1", $$cref );
  
  my @rows = split("\n", $str );

  if( scalar( @rows < 2 ) )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  my $columns = [ split( "\t", $rows[0] ) ];
  my $date;
  for ( my $i = 1; $i < scalar @rows; $i++ )
  {
    my $inrow = $self->row_to_hash($batch_id, $rows[$i], $columns );
    #my $date = $inrow->{'SENDEDATO'};
    #$date = substr( $date, 0, 10 );
    #$date =~ s/\./-/;
    #if ( exists($inrow->{'Date'}) )
    #{
    #  $dsh->StartDate( $inrow->{'Date'} );
    #}
    my $start = $inrow->{'SENDETID'};
    #my ($date, $time) = split(/ /, $start);
    #$date =~ s/\./-/;
    #$time =~ s/\./:/;
    #$date = turnDate($date);
    #$start = "$date $time";
    #print norm($start);
    $start = parseStart(fq($start));
    
    #my $start = $inrow->{'Start time'};
    #my $start = $starttime;

    my $title = norm( $inrow->{'NORSKTITTEL'} );
    $title = fq($title);
    my $description = $inrow->{'EPISODESYNOPSIS'}
        || $inrow->{'GENERELL_SYNOPSIS'};
    
    $description = norm( $description );
    $description = fq( $description );
    
    # Episode info in xmltv-format
    #my $ep_nr = norm(fq($inrow->{'EPISODENUMMER'})) || 0;
    #my $ep_se = norm(fq($inrow->{'SESONGNUMMER'})) || 0;
    #my $episode = undef;
    #
    #if( ($ep_nr > 0) and ($ep_se > 0) )
    #{
    #  $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
    #}
    #elsif( $ep_nr > 0 )
    #{
    #  $episode = sprintf( ". %d .", $ep_nr-1 );
    #}

    my $ce = {
      title => $title,
      description => $description,
      
      start_time => $start,
      #episode => $episode,

    };

    if( defined( $inrow->{'PRODUKSJONSAARKOPI'} ) and
        $inrow->{'PRODUKSJONSAARKOPI'} =~ /(\d\d\d\d)/ )
    {
      $ce->{production_date} = "$1-01-01";
    }

    my $cast = norm( $inrow->{'ROLLEBESKRIVELSE'} );
    $cast = fq( $cast );
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

    my $director = norm( $inrow->{'REGI'} );
    $director = fq( $director );
    if( $director =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $director =~ s/\s*m[\. ]*fl\.*\b//;
      
      # Remove trailing '.'
      $director =~ s/\.$//;
      my @directors = split( /\s*,\s*/, $director );
      $ce->{directors} = join( ", ", grep( /\S/, @directors ) );
    }

    #$self->extract_extra_info( $ce );
    $ds->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ( $batch_id =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "%s_%02d_%s_%02d.xls",
                     $self->{UrlRoot}, $week, $data->{grabber_info}, 
                     $year);
  
  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub row_to_hash
{
  my $self = shift;
  my( $batch_id, $row, $columns ) = @_;
  $row =~ s/\t.$//;
 # if $(row)
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

sub parseStart
{
    my ($string) = @_;
    #my $string = @$in[0];
    #print "PARSESTART: $string\n";
    my $day = substr( $string,  0, 2 );
    my $mnt = substr( $string,  3, 2 );
    my $yr  = substr( $string,  6, 4 );
    my $hr  = substr( $string, 11, 2 );
    my $min = substr( $string, 14, 2 );
    return ( "$yr-$mnt-$day $hr:$min:00");
}

sub fq
{
    # Remove quotes from strings
    my ($string) = @_;
    $string =~ s/^"//;
    $string =~ s/"$//;
    
    return $string;
}

1;
