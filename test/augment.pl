#!/usr/bin/perl -w

use strict;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Data::Dumper;
use Encode;
#use NonameTV::Augmenter::Tvdb;
use NonameTV::Factory qw/CreateAugmenter CreateDataStore CreateDataStoreDummy /;

my $ds = CreateDataStore( );

my $dt = DateTime->now( time_zone => 'UTC' );
$dt->add( days => 7 );

my $batchid = 'neo.zdf.de_' . $dt->week_year() . '-' . $dt->week();
printf( "augmenting %s...\n", $batchid );

my $augmenter = CreateAugmenter( 'Tvdb', $ds );

# program metadata from augmenter
my $newprogram;
# result code from augmenter
my $result;

# stripped down rule for testing
my %simplerule = ( matchby => 'episodetitle' );

    my ( $res, $sth ) = $ds->sa->Sql( "
        SELECT p.* from programs p, batches b
        WHERE (p.batch_id = b.id)
          AND (b.name LIKE ?)
        ORDER BY start_time asc, end_time desc", 
# name of batch to use for testing
      [$batchid] );
  
  my $found=0;
  my $notfound=0;
  my $ce = $sth->fetchrow_hashref();
  while( defined( $ce ) ) {
    if( ( $ce->{program_type} eq 'series' )and( defined( $ce->{subtitle} ) ) ) {
      $ce->{subtitle} =~ s|,\sTeil (\d+)$| ($1)|;
      $ce->{subtitle} =~ s|\s-\sTeil (\d+)$| ($1)|;
      $ce->{subtitle} =~ s|\s\(Teil (\d+)\)$| ($1)|;
      ( $newprogram, $result ) = $augmenter->AugmentProgram( $ce, \%simplerule );
      if( defined( $newprogram) ) {
        $found++;
      } else {
        $notfound++;
      }
    }

    $ce = $sth->fetchrow_hashref();
  }

  printf( "found %d/%d episodes at tvdb by name\n", $found, $found+$notfound );
