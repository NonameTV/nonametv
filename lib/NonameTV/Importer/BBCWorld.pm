package NonameTV::Importer::BBCWorld;

=pod

This importer imports data from the BBC World site.
The data is fetched per day/channel.

=cut

use strict;
use warnings;

use DateTime;
use Encode;

use NonameTV qw/MyGet norm Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    
    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;
    
    return $self;
}

sub ImportContent
{
    my $self = shift;
    
    my( $batch_id, $cref, $chd ) = @_;
    
    my $ds = $self->{datastore};
    my $dsh = $self->{datastorehelper};
    
    $ds->{SILENCE_END_START_OVERLAP}=1;
    
    my( $date ) = ($batch_id =~ /_(.*)$/);

    $dsh->StartDate( $date, "00:00" );
        
    my $str = decode( "iso-8859-1", $$cref );

    my @rows = split("\n", $str );

    if( scalar( @rows < 2 ) )
    {
      error( "$batch_id: No data found" );
      return 0;
    }

    my $columns = [ split( "\t", $rows[0] ) ];

    for ( my $i = 1; $i < scalar @rows; $i++ )
    {
      my $start = "";
      my $desc = "";
      my $title = "";
      my $subtitle = "";
      next if (norm($rows[$i]) eq "");
      my $inrow = $self->row_to_hash($batch_id, $rows[$i], $columns );
      #print "<<<<$rows[$i]>>>>\n";
      $start = $inrow->{'Time'};
      #next if undef $start; 
      #next if $start eq "";
      $title = $inrow->{'Programme'};
      $subtitle = $inrow->{'Episode'};
      $desc = $inrow->{'Billing'};

      #print "start>$start<\n";
      #print "title>$title<\n";
      #print "subtitle>$subtitle<\n";
      #print "desc>$desc<\n";

			# Remove (r) and so on
			$title =~ s/\(.*\)//g;

      my $ce = {
        title => norm($title),
        subtitle => norm($subtitle),
        description => norm($desc),
        start_time => $start,
      };
    
    
      $dsh->AddProgramme( $ce );
    
    
    }
    
    return 1;
}

sub FetchDataFromSite
{

    my $self = shift;
    my( $batch_id, $data ) = @_;
    
    my( $date ) = ($batch_id =~ /_(.*)/);
    
    my ($year, $month, $day) = split(/-/, $date);

    my $channeluri = $self->{UrlRoot};
    $channeluri = $channeluri."StartDate=$day/$month/$year&EndDate=$day/$month/$year";
    # print "DEBUG: $channeluri\n";
    my ( $content, $code ) = MyGet ($channeluri );
    
    return( $content, $code );
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

sub createDate
{
    my $self = shift;
    my( $str ) = @_;
    
    my $date = substr( $str, 0, 2 );
    my $month = substr( $str, 2, 2 );
    my $year = substr( $str, 4, 4 );
    
    return "$year-$month-$date";

}

1;

