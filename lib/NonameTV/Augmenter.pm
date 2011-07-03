package NonameTV::Augmenter;

use strict;
use warnings;

use NonameTV::Factory qw/CreateAugmenter/;
use NonameTV::Log qw/d/;

#
# THIS IS NOT THE BASE CLASS FOR AUGMENTERS! (CONTRARY TO HOW IMPORTER.PM IS THE BASE CLASS FOR IMPORTERS)
#
# Augmenters augment programmes with additional data
#
# tools/nonametv-augment
#
# Fixups          applies manually configured fixups, see tv_grab_uk_rt for use cases
# PreviouslyShown copies data from previous showings on the same or other channels
# TheTVDB         replaces programme related data with community data
# TMDb            replaces programme related data with community data
#
# The configuration is stored in one table in the database
#
# fields in the configuration
#   channel_id - the channel id (foreign key, may be null)
#   augmenter  - name of the augmenter to run, case sensitive
#   title      - program title to match
#   otherfield - other field to match (e.g. episodetitle, program_type, description, start_time)
#   othervalue - value to match in otherfield
#   remoteref  - reference in foreign database, e.g. movie id in tmdb or series id in tvdb
#   matchby    - which field is matched in the remote datastore in which way
#                e.g. match episode by episodetitle in tmdb
#                or   match episode by absolute episode number in tmdb
#
#
# DasErste, Fixups, Tagesschau, , , , setcategorynews
# DasErste, Fixups, Frauenfussballlaenderspiel, , , , settypesports
# Tele5 match by episodetitle for known series at TVDB
# Tele5 match Babylon5 by absolute number (need to add that to the backend first)
# Tele5 match by title for programmes with otherfield category=movie at TMDB
# ZDFneo, TheTVDB, Weeds, , , 74845, episodetitle
# ZDFneo, TheTVDB, Inspector Barnaby
# ZDFneo match by episodetitle for known series at TVDB
#
#
# Usual order of execution
# run Importers that really import
# run Augmenters
# run Importers to copy/mix/transform (combine, downconvert, timeshift)
# run Exporters
#
#
# Logic
# 1) get timestamp of last start of augmenter
# 2) find batches that have been updated (reset to station data) since then
# 3) order batches by batch id
# 4) for each batch
# 5)   collect all augmenters that match by channel_id
# 6)   for each programme ordered by start time
# 7)     select matching augmenters
# 7b)    skip to next programme if none matches or it is the same as last time
# 8)     order augmenters by priority
# 9)     apply augmenter with highest priority
#
#
#
# API for each Augmenter
#
# initialize
# create backend API instances etc.
#
# augment (Programme)
# input: programme + rule
# output: programme + error
#

sub new( @@ ){
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  $self->{datastore} = $_[1];

  return $self;
}

sub ReadLastUpdate( @ ){
  my $self = shift;

  my $ds = $self->{datastore};
 
  my $last_update = $ds->sa->Lookup( 'state', { name => "augmenter_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->sa->Add( 'state', { name => "augmenter_last_update", value => 0 } );
    $last_update = 0;
  }

  return $last_update;
}

sub WriteLastUpdate( @@ ){
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'state', { name => "augmenter_last_update" }, 
               { value => $update_started } );
}

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

sub AugmentBatch( @@ ) {
  my( $self, $batchid )=@_;

  ###
  # set up for augmenting one specific channel by batchid
  ###
  (my $channel_xmltvid )=($batchid =~ m|^(\S+)_|);

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
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
      d( "creating augmenter '" . $iter->{'augmenter'} . "' augmenter\n" );
      $augmenter->{ $iter->{'augmenter'} }= CreateAugmenter( $iter->{'augmenter'}, $self->{datastore} );
    }

    # append rule to array
    push( @ruleset, $iter );
  }

  if( @ruleset == 0 ){
    d( 'no augmenterrules for this batch' );
    return;
  }


  d( "ruleset for this batch: \n" );
  foreach my $therule ( @ruleset ) {
    d( sprint_rule( $therule ) . "\n" );
  }


  ###
  # augment all programs from one batch by batchid
  ###

  # program metadata from augmenter
  my $newprogram;
  # result code from augmenter
  my $result;

    ( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT p.* from programs p, batches b
        WHERE (p.batch_id = b.id)
          AND (b.name LIKE ?)
        ORDER BY start_time asc, end_time desc", 
  # name of batch to use for testing
      [$batchid] );
  
  my $ce;
  while( defined( $ce = $sth->fetchrow_hashref() ) ) {
    # copy ruleset to working set
    my @rules = @ruleset;

    if( defined( $ce->{subtitle} ) ) {
      d( "augmenting program: " . $ce->{title} . " - \"" . $ce->{subtitle} . "\"\n" );
    } else {
      d( "augmenting program: " . $ce->{title} . "\n" );
    }

    # loop until no more rules match
    while( 1 ){
      ###
      # order rules by quality of match
      ###
      foreach( @rules ){
        my $score = 0;
        $_->{score} = undef;

        # match by channel_id
        if( defined( $_->{channel_id} ) ) {
          if( $_->{channel_id} eq $ce->{channel_id} ){
            $score += 1;
          } else {
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
              next;
            }
          } else {
            if( $_->{title} eq $ce->{title} ){
              $score += 4;
            } else {
              next;
            }
          }
        }

        # match by other field
        if( defined( $_->{otherfield} ) ){
          if( defined( $_->{othervalue} ) ) {
            if( defined( $ce->{$_->{otherfield}} ) ){
              if( $_->{othervalue} =~ m|^\^| ){
                # regexp?
                if( $ce->{$_->{otherfield}} =~ m|$_->{othervalue}| ){
                  $score += 2;
                } else {
                  next;
                }
              }else{
                if( $_->{othervalue} eq $ce->{$_->{otherfield}} ){
                  $score += 2;
                } else {
                  next;
                }
              }
            } else {
              next;
            }
          } else {
            if( !defined( $ce->{$_->{otherfield}} ) ){
              $score += 2;
            } else {
              next;
            }
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

      d( 'best matching rule: ' . sprint_rule( $rule ) . "\n" );

      # apply the rule
      ( $newprogram, $result ) = $augmenter->{$rule->{augmenter}}->AugmentProgram( $ce, $rule );

      if( scalar keys %{$newprogram} ) {
        d( "augmenting as follows:\n" . sprint_augment( $ce, $newprogram ) );
        while( my( $key, $value )=each( %$newprogram ) ) {
          if( $value ) {
            $ce->{$key} = $value;
          } else {
            delete( $ce->{$key} );
          }
        }

        # handle description as a special case. We will not remove it, only replace it.
        if( exists( $newprogram->{description} ) ) {
          if( !$newprogram->{description} ) {
            delete( $newprogram->{description} );
          }
        }

        # TODO collect updates, compare and only push back to database what really has been changed
        $self->{datastore}->sa->Update( 'programs', {
            channel_id => $ce->{channel_id},
            start_time => $ce->{start_time}
          }, $newprogram );
      }

      # go around and find the next best matching rule
    }
  }
}

1;
