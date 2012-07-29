package NonameTV::Importer::STVSplit;

use strict;
use warnings;

=pod

Channels: Splitska TV

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
#use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "STVSplit: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "STVSplit $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "STVSplit $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    # skip the bottom of the document
    # all after 'TJEDNI PROGRAM'
    last if( $text =~ /^TJEDNI PROGRAM$/ );

#print ">$text<\n";

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        progress("STVSplit: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            # save last day if we have it in memory
            FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title ) = ParseShow( $text );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    } else {

        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        # remove ' - ' from the start
  	$text =~ s/^\s*-\s*//;
        $element->{description} .= $text;
    }
  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("STVSplit: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format '___ Petak ______________________________________ 11.07.2008. ___'
  if( $text =~ /^_*\s*(ponedjeljak|utorak|srijeda|Četvrtak|petak|subota|nedjelja)\s*_*\s*\d+\.\d+\.\d+\.\s*_*$/i ){
    return 1;

  # format '____ 05.11.2010. ___ Petak ____________________________________________________'
  } elsif( $text =~ /^_*\s*\d+\.\d+\.\d+\.\s*_*\s*(ponedjeljak|utorak|srijeda|Četvrtak|petak|subota|nedjelja)\s*_*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $month, $year );

#print ">$text<\n";

  # format '___ Petak ______________________________________ 11.07.2008. ___'
  if( $text =~ /^_*\s*(ponedjeljak|utorak|srijeda|Četvrtak|petak|subota|nedjelja)\s*_*\s*\d+\.\d+\.\d+\.\s*_*$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^_*\s*(\S+)\s*_*\s*(\d+)\.(\d+)\.(\d+)\.\s*_*$/ );

  # format '____ 05.11.2010. ___ Petak ____________________________________________________'
  } elsif( $text =~ /^_*\s*\d+\.\d+\.\d+\.\s*_*\s*(ponedjeljak|utorak|srijeda|Četvrtak|petak|subota|nedjelja)\s*_*$/i ){
    ( $day, $month, $year, $dayname ) = ( $text =~ /^_*\s*(\d+)\.(\d+)\.(\d+)\.\s*_*\s*(\S+)\s*_*$/ );
  }


  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '12:40 Glazbeni program'
  if( $text =~ /^\d+\:\d+\s+.*/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^(\d+)\:(\d+)\s+(.*)/ );

  return( $hour . ":" . $min , $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
