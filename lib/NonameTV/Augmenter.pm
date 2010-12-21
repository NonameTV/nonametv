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

sub ReadLastUpdate {
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

sub WriteLastUpdate {
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'state', { name => "augmenter_last_update" }, 
               { value => $update_started } );
}

1;
