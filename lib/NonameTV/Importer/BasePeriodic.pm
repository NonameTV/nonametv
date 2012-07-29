package NonameTV::Importer::BasePeriodic;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file for each period. 

Grabbers should normally derive from BaseOne, BaseWeekly or BaseDaily
instead. They all derive from BasePeriodic. To implement a grabber deriving
from BaseOne, BaseWeekly or BaseDaily, the following methods must be
implemented:

  my $error = $imp->InitiateDownload();


InitiateChannelDownload
Object2Url
FilterContent
ImportContent
 
=cut

use DateTime;
use POSIX qw/floor/;

use NonameTV qw/MyGet/;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/SetVerbosity StartLogSection EndLogSection d p w f/;
use NonameTV::ContentCache;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    my $conf  = ReadConfig();
    
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ 
			    short-grab remove-old clear/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'quiet'        => 0,
      'short-grab'   => 0,
      'remove-old'   => 0,
      'clear'        => 0,
    };

    $self->{cc} = NonameTV::ContentCache->new( { 
      basedir => $conf->{ContentCachePath} . $self->{ConfigName},
      credentials => $conf->{ContentCacheCredentials},
      callbackobject => $self,
      useragent => "nonametv (http://nonametv.org)", 
    } );

    return $self;
}

sub BatchPeriods { 
  my $self = shift;
  my( $shortgrab ) = @_;

  die "You must override BatchPeriods";
}

sub InitiateDownload {
  my $self = shift;

  return undef;
}

sub InitiateChannelDownload {
  my $self = shift;
  my( $chd ) = @_;

  return undef;
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  return ( $cref, undef );
}

sub ContentExtension {
  my $self = shift;

  return undef;
}

sub FilteredExtension {
  my $self = shift;

  return undef;
}

sub ApproveContent {
  my $self = shift;
  my( $cref, $callbackdata ) = @_;

  return undef;
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  die "You must override ImportContent";
}

sub ImportData {
  my $self = shift;
  my( $p ) = @_;

  if( $p->{'remove-old'} ) {
    $self->RemoveOld();
    return;
  }
  
  if( not $self->can("Object2Url") ) {
    # Fallback to old code...
    return $self->ImportOld( $p );
  }

  SetVerbosity( $p->{verbose}, $p->{quiet} );

  StartLogSection( $self->{ConfigName}, 1 );

  my $error1 = $self->InitiateDownload( $p );
  f $error1 if defined $error1;

  my $dsh = exists( $self->{datastorehelper} ) ? $self->{datastorehelper} : 
      $self->{datastore};

  my $ds = $self->{datastore};

  my $message1 = EndLogSection( $self->{ConfigName} );

  foreach my $data (@{$self->ListChannels()} ) {
    StartLogSection( $data->{xmltvid}, 1 );
    my $error2 = $self->InitiateChannelDownload( $data );
    f $error2 if defined $error2;

    if( $p->{'clear'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      p "Deleted $deleted records";
      $p->{'force-update'} =1;
    }

    my @batch_periods = $self->BatchPeriods( $p->{'short-grab'} );

    my $message2 = EndLogSection( $data->{xmltvid} );
 
    foreach my $period (@batch_periods) {
      my $batch_id = $data->{xmltvid} . "_" . $period;

      StartLogSection( $batch_id, 1 );

      my $error = $message1 . $message2;

      my $cref;
      if( $error eq "" ) {
        d "Fetching data";
        ( $cref, $error ) = $self->{cc}->GetContent( 
          $batch_id, $data, $p->{'force-update'} );
      }

      my $res;
      $dsh->StartBatch( $batch_id, $data->{id} );

      if( defined $cref ) { 
        p "Processing data";
        $res = $self->ImportContent( $batch_id, $cref, $data );
      }
      elsif( defined $error ) {
        f $error;
	$res = 0;
      }
      else {
        # Nothing has changed.
	$res = -1;
      }

      # Make sure that all error-messages have been produced before
      # EndLogSection.
      $dsh->CommitPrograms();

      my $message = EndLogSection( $batch_id );
      $dsh->EndBatch( $res, $message );
    }
  }
}

sub ImportOld {
  my $self = shift;
  my( $p ) = @_;

  NonameTV::Log::SetVerbosity( $p->{verbose}, $p->{quiet} );

  my $ds = $self->{datastore};

  foreach my $data (@{$self->ListChannels()} ) {
    if( $p->{'force-update'} and not $p->{'short-grab'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      p "Deleted $deleted records for $data->{xmltvid}";
    }

    my @batch_periods = $self->BatchPeriods( $p->{'short-grab'} );
 
    foreach my $period (@batch_periods) {
      my $batch_id = $data->{xmltvid} . "_" . $period;

      $self->ImportBatch( $batch_id, $data, $p->{'force-update'} );
    }
  }
}

=pod

ImportBatch

Called from Base*.pm to import data for a single batch. Logs errors to the 
batch-entry in the database.

=cut

sub ImportBatch {
  my $self = shift;

  my( $batch_id, $chd, $force_update ) = @_;

  my $ds;

  StartLogSection( $batch_id, 1 );  

  d "Fetching data";
  
  if( exists( $self->{datastorehelper} ) ) {
    $ds = $self->{datastorehelper};
  }
  else {
    $ds = $self->{datastore};
  }

  $ds->StartBatch( $batch_id, $chd->{id} );

  my( $content, $code ) = $self->FetchData( $batch_id, $chd );
  
  if( not defined( $content ) ) {
    f "Failed to fetch data ($code)";
    my $message = EndLogSection( $batch_id );
    $ds->EndBatch( 0, $message );
    return;
  }
  elsif( (not ($force_update) and ( not $code ) ) ) {
    # No changes.
    my $message = EndLogSection( $batch_id );
    $ds->EndBatch( -1 );
    return;
  }

  p "Processing data";

  my $res = $self->ImportContent( $batch_id, \$content, $chd ); 

  my $message = EndLogSection( $batch_id );

  if( $res ) {
    # success
    $ds->EndBatch( 1, $message );
  }
  else {
    # failure
    $ds->EndBatch( 0, $message );
  }
}

sub RemoveOld {
  my $self = shift;

  $self->{cc}->RemoveOld();
}

1;
