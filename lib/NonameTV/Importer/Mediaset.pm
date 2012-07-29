package NonameTV::Importer::Mediaset;

use strict;
use warnings;

=pod

Channels: Italia1, Rete4, Canale5, Iris,
          Diretta Calcio 1, Diretta Calcio 2, Diretta Calcio 3, Diretta Calcio 4, Diretta Calcio 5, Diretta Calcio 6,
          Joi, Mya, Steel, Premium Calcio 24

Import data from MHT delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Mediaset";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "Mediaset: $xmltvid: Processing $file" );
  
  my $doc = Htmlfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Mediaset: $xmltvid: $file: Failed to parse" );
    return;
  }

  my $tables = $doc->find( "//table" );

  if( $tables->size() == 0 ) {
    error( "Mediaset: $xmltvid: $file: No tables found." ) ;
    return;
  }
  progress( "Mediaset: $xmltvid: Found " . $tables->size() . " tables");

  my $currdate = "x";
  my $date = undef;

  foreach my $table ($tables->get_nodelist) {

    my $rows = $table->findnodes( "./tbody/tr" );
    if( $rows->size() == 0 ) {
      error( "Mediaset: $xmltvid: $file: No rows found in a table." ) ;
      next;
    }
    progress( "Mediaset: $xmltvid: Found " . $rows->size() . " rows");

    foreach my $row ($rows->get_nodelist) {

      # the row with <th> contain date
      # in the format 'Domenica 9 novembre 2008'
      my $ths = $row->findnodes( "./th" );
      if( $ths->size() == 1 ) {

        progress( "Mediaset: $xmltvid: Extracting date from table header" ) ;

        foreach my $th ($ths->get_nodelist) {

          if( isDate( $th->string_value() ) ){

            $date = ParseDate( $th->string_value() );
            next if( ! $date );

            if( $date ne $currdate ) {

              progress("Mediaset: $xmltvid: Date is $date");

              if( $date ne $currdate ) {

                if( $currdate ne "x" ){
                  $dsh->EndBatch( 1 );
                }

                my $batch_id = "${xmltvid}_" . $date;
                $dsh->StartBatch( $batch_id, $channel_id );
                $dsh->StartDate( $date );
                $currdate = $date;
              }
            }
          }
        }
        next;
      }

      # the rows with 3 cells contain time, genre, title
      my $cells = $row->findnodes( "./td" );
      if( $cells->size() == 0 ) {
        error( "Mediaset: $xmltvid: $file: No cells found in a row." ) ;
        next;
      } elsif( $cells->size() != 3 ) {
        error( "Mediaset: $xmltvid: Skipping row with " . $cells->size() . " cells." );
        next;
      }

      my $time = undef;
      my $genre = undef;
      my $showinfo = undef;

      foreach my $cell ($cells->get_nodelist) {
        if( ! $time ){
          $time = norm( $cell->string_value() );
        } elsif( ! $genre ){
          $genre = norm( $cell->string_value() );
        } elsif( ! $showinfo ){
          $showinfo = $cell->toString();
        }
      } # next cell

      my( $title, $description, $stereo, $bilingual, $aspect ) = ParseShow( $showinfo );

      progress("Mediaset: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

      $ce->{description} = $description if $description;

      $ce->{stereo} = $stereo if $stereo;

      $ce->{aspect} = $aspect if $aspect;

      $dsh->AddProgramme( $ce );

    } # next row

  } # next table

  $dsh->EndBatch( 1 );

  progress( "Mediaset: $xmltvid: Finished $file" );

  return;
}

sub isDate {
  my( $text ) = @_;

  # date is in format 'Sabato 15 novembre 2008'
  if( $text =~ /^\S+\s+\d+\s+(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;
#print ">$text<\n";

  my( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)$/ );
  my $month = MonthNumber( $monthname, "it" );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseShow {
  my( $text ) = @_;

  $text = norm( $text );
#print "ParseShow: >$text<\n";

  my( $title, $description, $infos );
  my( $stereo, $bilingual, $format );

  ( $title ) = ( $text =~ /\<h4\>(.*)\<\/h4\>/i );

  ( $description ) = ( $text =~ /\<p\>(.*)\<\/p\>/i );
  #$description =~ s/<(([^ >]|\n)*)>//g; # strip html tags

  ( $infos ) = ( $text =~ /\<div class="3Dplus"\>(.*)\<\/div\>/i );
  if( $infos ){
#print "INFOS: $infos\n";

    if( $infos =~ /\<h5\>Stereo\<\/h5\>/i ){
      $stereo = 1;
    } else {
      $stereo = 0;
    }

    if( $infos =~ /\<h5\>Bilingue\<\/h5\>/i ){
      $bilingual = 1;
    } else {
      $bilingual = 0;
    }

    if( $infos =~ /\<h5\>Formato.*\<\/h5\>/i ){
      ( $format ) = ( $infos =~ /\<h5\>Formato\s+(.*)<\/h5\>/ );
    }
  }

  return( $title, $description, $stereo, $bilingual, $format );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
