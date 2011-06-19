#!/usr/bin/perl -w

use strict;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

use DateTime;
use Data::Dumper;
use Encode;
use NonameTV::Factory qw/CreateAugmenter CreateDataStore CreateDataStoreDummy /;

sub cmp_rules_by_score( ){
  if(!defined( $a->{score} ) && !defined( $b->{score} )){
    return 0;
  } elsif(!defined( $a->{score} ) ){
    return 1;
  } elsif(!defined( $b->{score} ) ){
    return -1;
  } else {
    return -($a->{score} <=> $b->{score});
  }
}

sub sprint_rule( @ ){
  my ($rule_ref) = @_;
  my $result = '';

  if( $rule_ref ){
    if( $rule_ref->{channel_id} ){
      $result .= 'channel=' . $rule_ref->{channel_id} . ', ';
    }
    if( $rule_ref->{title} ){
      $result .= 'title=\'' . $rule_ref->{title} . '\', ';
    }
    if( $rule_ref->{otherfield} ){
      if( defined( $rule_ref->{othervalue} ) ){
        $result .= $rule_ref->{otherfield} . '=\'' . $rule_ref->{othervalue} . '\', ';
      } else {
        $result .= $rule_ref->{otherfield} . '=NULL, ';
      }
    }
    if( $rule_ref->{augmenter} ){
      $result .= $rule_ref->{augmenter};
      if( $rule_ref->{matchby} ){
        $result .= '::' . $rule_ref->{matchby};
      }
      if( $rule_ref->{remoteref} ){
        $result .= '( ' . $rule_ref->{remoteref} . ' )';
      }
    }
  }

  return( $result );
}

sub sprint_augment( @@ ){
  my ($programme_ref, $augment_ref) = @_;
  my $result = '';

  if( $programme_ref && $augment_ref){
    foreach my $attribute ( 'title', 'subtitle', 'episode',
                            'program_type', 'category', 'actors' ) {
      if( exists( $augment_ref->{$attribute} ) ){
        if( defined( $programme_ref->{$attribute} ) && defined( $augment_ref->{$attribute} ) ) {
          if( $programme_ref->{$attribute} ne $augment_ref->{$attribute} ){
            $result .= '  changing ' . $attribute . " to \'" .
                       $augment_ref->{$attribute} .  "\' was \'" .
                       $programme_ref->{$attribute} . "\'\n";
# TODO add verbose mode
#          } else {
#            $result .= '  leaving  ' . $attribute . " unchanged\n";
          }
        } elsif( defined( $programme_ref->{$attribute} ) ){
          $result .= '  removing ' . $attribute . "\n";
        } elsif( defined( $augment_ref->{$attribute} ) ){
          $result .= '  adding   ' . $attribute . " as \'" .
                     $augment_ref->{$attribute} . "\'\n";
        }
      }
    }
  }

  return( $result );
}

my $ds = CreateDataStore( );

my $dt = DateTime->now( time_zone => 'UTC' );
$dt->add( days => 7 );

my $batchid = 'neo.zdf.de_' . $dt->week_year() . '-' . $dt->week();
printf( "augmenting %s...\n", $batchid );


###
# set up for augmenting one specific channel by batchid
###
(my $channel_xmltvid )=($batchid =~ m|^(\S+)_|);

my( $res, $sth ) = $ds->sa->Sql( "
    SELECT ar.*
      FROM channels c, augmenterrules ar
     WHERE c.xmltvid LIKE ?
       AND (ar.channel_id = c.id
        OR  ar.channel_id IS NULL)",
    [$channel_xmltvid] );

my $augmenter = { };
my @ruleset;

my $iter;
while( defined( $iter = $sth->fetchrow_hashref() ) ){
  # set up augmenters
  if( !defined( $augmenter->{ $iter->{'augmenter'} } ) ){
    printf( "creating '%s' augmenter\n", $iter->{'augmenter'} );
    $augmenter->{ $iter->{'augmenter'} }= CreateAugmenter( $iter->{'augmenter'}, $ds );
  }

  # append rule to array
  push( @ruleset, $iter );
}


print( "ruleset for this batch: \n" );
foreach my $therule ( @ruleset ) {
  printf( "%s\n", sprint_rule( $therule ) );
}


###
# augment all programs from one batch by batchid
###

# program metadata from augmenter
my $newprogram;
# result code from augmenter
my $result;

    ( $res, $sth ) = $ds->sa->Sql( "
        SELECT p.* from programs p, batches b
        WHERE (p.batch_id = b.id)
          AND (b.name LIKE ?)
        ORDER BY start_time asc, end_time desc", 
# name of batch to use for testing
      [$batchid] );
  
  my $found=0;
  my $notfound=0;
  my $ce;
  while( defined( $ce = $sth->fetchrow_hashref() ) ) {
    # copy ruleset to working set
    my @rules = @ruleset;

    if( defined( $ce->{subtitle} ) ) {
      printf( "\naugmenting program: %s - \"%s\"\n", $ce->{title}, $ce->{subtitle} );
    } else {
      printf( "\naugmenting program: %s\n", $ce->{title} );
    }

    # loop until no more rules match
    while( 1 ){
      ###
      # order rules by quality of match
      ###
      foreach( @rules ){
        my $score = 0;

        # match by channel_id
        if( defined( $_->{channel_id} ) ) {
          if( $_->{channel_id} eq $ce->{channel_id} ){
            $score += 1;
          } else {
            $_->{score} = undef;
            next;
          }
        }

        # match by title
        if( defined( $_->{title} ) ) {
          # regexp?
          if( $_->{title} =~ m|^\^| ) {
            if( $ce->{title} =~ m|$_->{title}| ){
              $score += 4;
            } else {
              $_->{score} = undef;
              next;
            }
          } else {
            if( $_->{title} eq $ce->{title} ){
              $score += 4;
            } else {
              $_->{score} = undef;
              next;
            }
          }
        }

        # match by other field
        if( defined( $_->{otherfield} ) && defined( $_->{othervalue} ) ) {
          if( $_->{othervalue} eq $ce->{$_->{otherfield}} ){
            $score += 2;
          } else {
            $_->{score} = undef;
            next;
          }
        }

        $_->{score} = $score;
      }

      @rules = sort{ cmp_rules_by_score }( @rules );
      #printf( "rules after sorting: %s\n", Dumper( \@rules ) );

      # take the best matching rule from the array (we apply it now and don't want it to match another time)
      my $rule = shift( @rules );

      # end loop if the best matching rule is not a mathing rule after all
      if( !defined( $rule->{score} ) ){
        last;
      }

      printf( "best matching rule: %s\n", sprint_rule( $rule ) );

      # apply the rule
      ( $newprogram, $result ) = $augmenter->{$rule->{augmenter}}->AugmentProgram( $ce, $rule );

      if( defined( $newprogram) && ( $rule->{augmenter} eq 'Tvdb' ) ) {
        $found++;
      }
      if( defined( $newprogram) ) {
        printf( "augmenting as follows:\n%s", sprint_augment( $ce, $newprogram ) );
        while( my( $key, $value )=each( %$newprogram ) ) {
          if( $value ) {
            $ce->{$key} = $value;
          } else {
            delete( $ce->{$key} );
          }
        }
      }

      # go around and find the next best matching rule
    }
  }

  printf( "found %d episodes at tvdb\n", $found );
