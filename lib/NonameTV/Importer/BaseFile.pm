package NonameTV::Importer::BaseFile;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that uses data found in one directory
per channel where new files "magically appear" in the directory and must be
processed in the order that they appear.

=cut

use DateTime;
use POSIX qw/floor/;
use Encode;

use NonameTV::Log qw/progress error StartLogSection EndLogSection/;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ remove-missing/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'quiet'        => 0,
      'remove-missing' => 0,
    };

    $self->{conf} = ReadConfig();

    return $self;
}

sub ImportData {
  my $self = shift;
  my( $p ) = @_;
  
  NonameTV::Log::SetVerbosity( $p->{verbose}, $p->{quiet} );

  $self->UpdateFiles();

  my $ds = $self->{datastore};

  foreach my $data (@{$self->ListChannels()}) {
    progress( "Checking files for $data->{xmltvid}" );
    if( $p->{'remove-missing'} ) {
      $self->RemoveMissing( $ds, $data );
      next;
    }
    
    if( $p->{'force-update'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $dir = $self->{conf}->{FileStore} . "/" . $data->{xmltvid};
    my $filelist_raw = qx/ls -t -r -1 $dir/;
    my $filelist = decode( "utf-8", $filelist_raw );

    my @files = split( "\n", $filelist );
    
    foreach my $file (@files) {

      # ignore directories
      next if -d "$dir/$file";

      # Ignore emacs backup-files.
      next if $file =~ /~$/;
      my $md5 = md5sum( "$dir/$file" );
      my $fdata = $ds->sa->Lookup( "files", { channelid => $data->{id},
                                              filename => $file } );
      
      if( defined( $fdata ) and ($fdata->{md5sum} ne $md5) ) {
        # The file has changed since we last saw it. 
        # Treat it as a new file.

        $ds->sa->Delete( "files", { channelid => $data->{id},
                                    filename => $file } );
      
        $fdata = undef;
      }

      if( defined( $fdata ) ) {
        # We have seen this file before
        next unless $p->{'force-update'};
        $ds->sa->Delete( "files", { channelid => $data->{id},
                                    filename => $file } );
      }

      $ds->sa->Add( "files", { channelid => $data->{id},
                               filename => $file,
                               'md5sum' => $md5,
                    } );
      
      $self->DoImportContentFile( "$file", $data );
    }
  }
}

sub DoImportContentFile {
  my $self = shift;
  my( $file, $data ) = @_;

  my $ds = $self->{datastore};

  StartLogSection( $self->{ConfigName} . " $file", 1 );

  $ds->StartTransaction();
  
  $self->{earliestdate} = "2100-01-01";
  $self->{latestdate} = "1970-01-01";

  # Import file
  my $dir = $self->{conf}->{FileStore} . "/" . $data->{xmltvid};
  eval { $self->ImportContentFile( "$dir/$file", $data ); };
  my( $message, $highest ) = EndLogSection( $self->{ConfigName} . " $file" );
  if( $@ ) {
    $message .= $@;
    $highest = 5;
    $ds->Reset();
  }

  if( $highest > 3 ) {
    $ds->EndTransaction( 0 );

    $ds->sa->Update( "files", 
                     { channelid => $data->{id},
                       filename => $file, },
                     { successful => 0,
                       message => $message, } );
    
  }
  else { 
    $ds->EndTransaction( 1 );
  
    $ds->sa->Update( "files", 
                     { channelid => $data->{id},
                       filename => $file, },
                     { successful => 1,
                       message => $message,
                       earliestdate => $self->{earliestdate},
                       latestdate => $self->{latestdate},
                     } );
  
  }
}  

sub AddDate {
  my $self = shift;
  my( $date ) = @_;

  if( $date gt $self->{latestdate} ) {
    $self->{latestdate} = $date;
  }

  if( $date lt $self->{earliestdate} ) {
    $self->{earliestdate} = $date;
  }
}

sub RemoveMissing {
  my $self = shift;
  my( $ds, $chd ) = @_;

  my $sth = $ds->sa->Iterate( 'files', { channelid => $chd->{id} } );

  my $dir = $self->{conf}->{FileStore} . "/" . $chd->{xmltvid};

  while( my $data = $sth->fetchrow_hashref ) {

    if( not -f( $dir . "/" . $data->{filename} ) ) {
      progress( "Removing " . $dir . "/" . $data->{filename} );
      $ds->sa->Delete( 'files', { id => $data->{id} } );
    }
  }
}
  
sub ImportContentFile {
  my $self = shift;

  my( $filename, $chd ) = @_;

  die "You must override ImportContentFile";
}

sub UpdateFiles {
  my $self = shift;

}

sub md5sum {
  my( $file ) = @_;
  open(FILE, $file) or die "Can't open '$file': $!";
  binmode(FILE);
  
  return Digest::MD5->new->addfile(*FILE)->hexdigest;
}

1;
