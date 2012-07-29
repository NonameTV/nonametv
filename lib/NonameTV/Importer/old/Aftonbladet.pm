package NonameTV::Importer::Aftonbladet;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Aftonbladet";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "Aftonbladet: Processing $file" );
  
  $self->{fileerror} = 0;

  # We only support one channel for Aftonbladet.
  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};

  my $doc = Wordfile2Xml( $file );
  
  if( not defined( $doc ) ) {
    error( "Aftonbladet $file: Failed to parse" );
    return;
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "Aftonbladet $file: No divs found." ) ;
    return;
  }

  my $currdate = undef;
  my $ce = undef;
  my $prev_start ="x";

  foreach my $div ($ns->get_nodelist) {
    my( $text ) = norm( $div->findvalue( '.' ) );

    next if $text eq "";

    if( $text =~ /^\S+dag\s+\d{1,2}\s+\S+\s*$/i ) {
      my $date = ParseDate( $text, $file  );
      if( not defined $date ) {
        error( "Aftonbladet $file: Unknown date $text" );
        next;
      }
          
      if( defined $ce ) {
        $prev_start = $ce->{start_time};
        $dsh->AddProgramme( $ce );
      }

      $ce = undef;

      $dsh->EndBatch( 1 )
        if defined $currdate;

      my $batch_id = "${xmltvid}_$date";
      $dsh->StartBatch( $batch_id, $channel_id );
      $dsh->StartDate( $date, "06:00" ); 
      $self->AddDate( $date );
      $currdate = $date;
    }
    elsif( $text =~ /^\d{1,2}.\d\d(\s*-\s*\d{1,2}.\d\d){0,1} / ) {
      if( defined $ce ) {
        # Aftonbladet uses program-blocks that contain several
        # sub-programmes. Ignore the first sub-programme.
        my $t = $ce->{start_time};
        $dsh->AddProgramme( $ce )
          if $ce->{start_time} ne $prev_start;
        $prev_start = $t
      }

      $ce = ParseProgram( $text );
    }
    else {
      if( not defined $ce ) {
        error( "Aftonbladet $file: Ignoring text $text" );
        next;
      }
      $ce->{description} .= " " if defined $ce->{description};
      $ce->{description} .= $text;
      $ce->{description} .= "." unless $ce->{description} =~ /\.$/;
    }
  }
  $dsh->AddProgramme( $ce )
    if defined $ce;

  $dsh->EndBatch( 1 );
    
  return;
}

my %months = (
              jnauari => 1,
              januari => 1,
              februari => 2,
              mars => 3,
              april => 4,
              maj => 5,
              juni => 6,
              juli => 7,
              augusti => 8,
              september => 9,
              oktober => 10,
              november => 11,
              december => 12,
              );

sub ParseDate {
  my( $text, $file ) = @_;

  my( $wday, $day, $month ) = ($text =~ /^(.*?)\s+(\d+)\s+([a-z]+)[\. ]*$/i);
  my $monthnum = $months{lc $month};

  if( not defined $monthnum ) {
    error( "$file: Unknown month '$month' in '$text'" );
    return undef;
  }
  
  my $dt = DateTime->today();
  $dt->set( month => $monthnum );
  $dt->set( day => $day );
 
  if( $dt < DateTime->today()->add( days => -180 ) ) {
    $dt->add( years => 1 );
  }

  return $dt->ymd('-');
}

sub ParseProgram{
  my( $text ) = @_;

  my( $start, $stop, $title );

  ($start, $stop, $title) = ($text =~ 
                             /^(\d{1,2}\.\d\d)
                             \s*-\s*
                             (\d{1,2}\.\d\d)
                             \s*
                             (.*)$/ix );
  if( not defined $title ) {
    ($start, $title) = ($text =~
                        /^(\d{1,2}\.\d\d)
                        \s*
                        (.*)$/ix );
  }

  return undef if not defined( $title );
  
  $start =~ tr/\./:/;

  my $ce = {
    start_time => $start,
    title => $title,
  };

  if( defined $stop ) {
    $stop =~ tr/\./:/;
    $ce->{end_time} = $stop;
  }

  return $ce;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
