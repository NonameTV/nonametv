package NonameTV::Importer::SRF;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

Registration at: https://medienportal.srf.ch/app/
Webservice documentation available via: http://www.crosspoint.ch/index.php?is_presseportal_ws

TODO handle regional programmes on DRS

=cut

use Encode qw/decode encode/;
use utf8;
use Data::Dumper;

use NonameTV qw/AddCategory normLatin1 norm ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f/;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore}, 'Europe/Zurich' );

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $xmltvid, $date ) = ( $objectname =~ /^(.+)_(\d+-\d+-\d+)$/ );

  if (!defined ($chd->{grabber_info})) {
    return (undef, 'Grabber info must contain channel id!');
  }

  my $url = sprintf( 'http://programmdatenwebservice.srf.ch/app/programinfo.asmx/getProgramInfoExtendedHD' .
    '?username=%s&password=%s&channel=%s&fromDate=%s&toDate=%s', $self->{Username}, $self->{Password}, $chd->{grabber_info}, $date, $date );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref = decode( 'utf-8', $$cref );

  $$cref =~ s|\x{0d}$||g;      # strip carriage return from the line endings
  $$cref =~ s|\x{a0}+(?=<)||g; # strip trailing non-breaking whitespace
  $$cref = normLatin1( $$cref );

  $$cref = encode( 'utf-8', $$cref );

  return( $cref, undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $doc = ParseXml ($cref);
  
  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  # The data really looks like this...
  my $ns = $doc->find ('//SENDUNG');
  if( $ns->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  my $date = $doc->findvalue( '//SENDUNG[1]/DATUM' );
  $date =~ s|(\d+)\.(\d+)\.(\d+)|$3-$2-$1|;
  $self->{datastorehelper}->StartDate( $date );

  foreach my $programme ($ns->get_nodelist) {
    my ($time) = ($programme->findvalue ('./ZEIT') =~ m|(\d+\:\d+)|);
    if( !defined( $time ) ){
      w( 'programme without start time!' );
    }else{
      my ($title) = $programme->findvalue ('./TITEL');
      my ($org_title) = $programme->findvalue ('./ORGTITEL');
      my ($cast) = $programme->findvalue ('./PERSONEN');

      my $ce = {
#        channel_id => $chd->{id},
        start_time => $time,
        title => norm(normLatin1($title)),
      };

      my ($subtitle) = $programme->findvalue ('./UNTERTITEL');
      if( $subtitle ){
        $ce->{subtitle} = $subtitle;
      }

      my ($description) = $programme->findvalue ('./INHALT');
      if( !$description ){
        ($description) = $programme->findvalue ('./LEAD');
      }
      if( $description ){
        $ce->{description} = norm(normLatin1($description));
      }

      my ($genre) = $programme->findvalue ('./GENRE');
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "SRF", $genre );
      AddCategory( $ce, $program_type, $categ );

      my ($year) = $programme->findvalue ('./PRODJAHR');
      if( $year ){
        $ce->{production_date} = $year . '-01-01';
      }

      # Cast
      if($cast) {
        $cast =~ s/^Mit/Mit:/; # Make it pretty
        $cast =~ s/^Ein Film von/Regie:/; # Alternative way
        my @sentences = (split_personen( $cast ), "");
        my( $actors, $dummy, $actors2, $directors, $writers, $guests, $guest, $presenter, $host, $producer );

        for( my $i=0; $i<scalar(@sentences); $i++ )
        {
            if( ( $actors ) = ($sentences[$i] =~ /^Mit\:(.*)/ ) )
            {
              $ce->{actors} = norm(parse_person_list(normLatin1($actors)));;
              $sentences[$i] = "";
            }
            elsif( ( $directors ) = ($sentences[$i] =~ /^Regie\:(.*)/ ) )
            {
                $directors =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{directors} = norm(parse_person_list(normLatin1($directors)));;
                $sentences[$i] = "";
            }
            elsif( ($dummy, $presenter ) = ($sentences[$i] =~ /^(Moderator|Moderation)\:(.*)/ ) )
            {
                $presenter =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{presenters} = norm(parse_person_list(normLatin1($presenter)));;
                $sentences[$i] = "";
            }
            elsif( ($host ) = ($sentences[$i] =~ /^Redaktion\:(.*)/ ) )
            {
                $host =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{commentators} = norm(parse_person_list(normLatin1($host)));;
                $sentences[$i] = "";
            }
            elsif( ( $producer ) = ($sentences[$i] =~ /^Produzent\:(.*)/ ) )
            {
                $producer =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{producers} = norm(parse_person_list(normLatin1($producer)));;
                $sentences[$i] = "";
            }
            elsif( ( $writers ) = ($sentences[$i] =~ /^Drehbuch\:(.*)/ ) )
            {
                $writers =~ s/\((.*?)\)//g; # Remove () texts
                $ce->{writers} = norm(parse_person_list(normLatin1($writers)));;
                $sentences[$i] = "";
            }
            elsif( ( $actors2 ) = ($sentences[$i] =~ /^Sprecher\:(.*)/ ) )
            {
                $actors2 =~ s/\((.*?)\)//g; # Isn't a role.
                $ce->{actors} = norm(parse_person_list(normLatin1($actors2)));;
                $sentences[$i] = "";
            }
        }
      }



      $ce->{original_title} = norm(normLatin1($org_title)) if $org_title;

      $self->{datastorehelper}->AddProgramme( $ce );
    }
  }

  return 1;
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

sub split_personen
{
  my( $t ) = @_;

  return () if not defined( $t );

  $t =~ s/(\S+)\:\s+([\(A-ZÅÄÖ])/;;$1: $2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
  }

  return @sent;
}

1;
