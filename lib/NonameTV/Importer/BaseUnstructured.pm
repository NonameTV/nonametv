package NonameTV::Importer::BaseUnstructured;

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

use NonameTV qw/CompareArrays/;
use NonameTV::Log qw/d p w f StartLogSection EndLogSection/;

use NonameTV::Config qw/ReadConfig/;
use NonameTV::Factory qw/CreateFileStore CreateDataStoreDummy/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ rescan 
                               interactive/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'quiet'        => 0,
      'rescan'       => 0,
      'interactive'  => 0,
    };

    my $conf = ReadConfig();
    
    $self->{filestore} = CreateFileStore( $self->{ConfigName} );

    return $self;
}

sub ImportData {
  my $self = shift;
  my( $p ) = @_;
  
  if( $p->{interactive} ) {
      $self->ImportDataInteractive();
  }
  else {
      $self->ImportDataAutomatic( $p );
  }
}

sub ImportDataAutomatic {
  my $self = shift;
  my( $p ) = @_;

  NonameTV::Log::SetVerbosity( $p->{verbose}, $p->{quiet} );

  my $ds = $self->{datastore};
  my $fs = $self->{filestore};

  foreach my $data (@{$self->ListChannels()}) {
    StartLogSection( $data->{xmltvid}, 0 );
    p "Checking files";
    
    if( $p->{'rescan'} ) {
      $fs->RecreateIndex( $data->{xmltvid} );
    }
    
    my @processfiles;

    if( $p->{'force-update'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      p "Deleted $deleted records";

      @processfiles = $fs->ListFiles( $data->{xmltvid} );
    }
    else {
      my $dbfiles = $ds->sa->LookupMany( "files", 
					 { channelid => $data->{id} } );
      my @old = map { [ $_->{filename}, $_->{md5sum} ] } @{$dbfiles};

      my @new = $fs->ListFiles( $data->{xmltvid} );

      CompareArrays( \@new, \@old, {
	added => sub { push @processfiles, $_[0] },
	deleted => sub {
	  $ds->sa->Delete( "files", { channelid => $data->{id},
				      "binary filename" => $_[0]->[0] } );
	},
	equal => sub { push( @processfiles, $_[0] ) 
			   if( $_[0]->[1] ne $_[1]->[1] );
		     },
	cmp => sub { $_[0]->[0] cmp $_[1]->[0] },
	max => [ "zzzzzzzz" ],
      } );

      # Process the oldest (lowest timestamp) files first.
      @processfiles = sort { $a->[2] <=> $b->[2] } @processfiles;
    }

    foreach my $file (@processfiles) {
      # Mysql string comparisons are case-insensitive. 
      # By forcing one string to binary, the comparison is done
      # case-sensitive instead.
      $ds->sa->Delete( "files", { channelid => $data->{id},
                                  "binary filename" => $file->[0] } );
      
      $ds->sa->Add( "files", { channelid => $data->{id},
                               filename => $file->[0],
                               'md5sum' => $file->[1],
                    } );

      $self->DoImportContent( $file->[0], $data );
    }
    
    EndLogSection( $data->{xmltvid} );
  }
}

sub ImportDataInteractive {
  my $self = shift;

  require Term::ReadLine;

  NonameTV::Log::SetVerbosity( 1, 0 );

  my $ds = $self->{datastore};
  my $fs = $self->{filestore};

  my @channels = @{$self->ListChannels()};

  my $term = new Term::ReadLine "BaseUnstructured";
  my $data = $channels[0];

  my @files = $self->ListFiles( $data );

  my $OUT = $term->OUT || \*STDOUT;
  while ( defined (my $line = $term->readline("$data->{xmltvid}> ")) ) {
    my( $command, @arg ) = split( /\s+/, $line );
    next if not defined $command;
    if( $command eq "channels" ) {
      my $c=1;
      foreach my $d (@channels) {
        printf("%2d. %s\n", $c++, $d->{xmltvid} );
      }
    }
    elsif( $command eq "channel" ) {
      if( $arg[0] > 0 and $arg[0] <= scalar( @channels ) ) {
	$data = $channels[$arg[0]-1];
	@files = $self->ListFiles( $data );
      }
      else {
        print $OUT "Unknown channel $arg[0]\n";
      }
    }
    elsif( $command eq "rescan" ) {
      $self->{filestore}->RecreateIndex( $data->{xmltvid} );
      @files = $self->ListFiles( $data );
    }
    elsif( $command eq "files" ) {
      my $c = 1;
      foreach my $file (@files) {
	printf( "%2d. %s %s\n", $c++, $file->[2], $file->[0] );
      }
    }
    elsif( $command eq "info" ) {
      print $files[$arg[0]-1]->[3] . "\n";
    }
    elsif( $command eq "import" ) {
      if( $arg[0] < 1 or $arg[0] > scalar @files ) {
	print "No such file $arg[0].\n";
      }
      else {
        my $filename = $files[$arg[0]-1][0];
        my $md5sum = $files[$arg[0]-1][4];
	$ds->sa->Delete( "files", { channelid => $data->{id},
				    "binary filename" => $filename } );
      
	$ds->sa->Add( "files", { channelid => $data->{id},
				 filename => $filename,
				 'md5sum' => $md5sum,
		      } );

	$self->DoImportContent( $filename, $data );
	@files = $self->ListFiles( $data );
      }
    }
    elsif( $command eq "debug" ) {
      if( $arg[0] < 1 or $arg[0] > scalar @files ) {
	print "No such file $arg[0].\n";
      }
      else {
        my $filename = $files[$arg[0]-1][0];
        my $md5sum = $files[$arg[0]-1][1];

	NonameTV::Log::SetVerbosity( 2, 0 );
	
	my $ds_org = $self->{datastore};
	$self->{datastore} = CreateDataStoreDummy();
	$self->DoImportContent( $filename, $data );
	$self->{datastore} = $ds_org;

	NonameTV::Log::SetVerbosity( 1, 0 );
      }
    }
    elsif( $command eq "help" ) {
      print << 'EOHELP';
Available commands:

channels
  List available channels for this importer.

channel <num>
  Select a new channel.

files
  List available files along with their status for the current channel.

info <num>
  Print the error-message for a specific file.

import <num>
  Import data from the specified file.

debug <num>
  Perform a debug import from the specified file. The database will
  not be updated and the imported data will be printed on the console
  instead.

rescan
  Rescan the list of files for this channel.

EOHELP
    }
    else {
      print $OUT "Unknown command $command\n";
    }
    $term->addhistory($line);
  }

  print $OUT "\n";
}

sub ListFiles {
  my $self = shift;
  my( $data ) = @_;

  my $dbfiles = $self->{datastore}->sa->LookupMany( "files", 
				     { channelid => $data->{id} } );
  my @old = map { [ $_->{filename}, $_->{md5sum}, 
		    $_->{successful}, $_->{message} ] } @{$dbfiles};
  
  my @new = $self->{filestore}->ListFiles( $data->{xmltvid} );
  
  my @files;
  CompareArrays( \@new, \@old, {
    added => sub { push @files, [ $_[0][0], $_[0][2], "N", "", $_[0][1] ] },
    deleted => sub {},
    equal => sub { push @files, [$_[0][0], $_[0][2], 
				 $_[0][1] ne $_[1][1] ? "C" :
				 ($_[1][2] ? " " : "E"), $_[1][3], $_[0][1] ];
    },
    cmp => sub { $_[0]->[0] cmp $_[1]->[0] },
    max => [ "zzzzzzzz" ],
  } );

  # Process the oldest (lowest timestamp) files first.
  return sort { $a->[1] <=> $b->[1] } @files;
}

sub DoImportContent {
  my $self = shift;
  my( $filename, $data ) = @_;

  my $ds = $self->{datastore};

  StartLogSection( $data->{xmltvid} . " $filename", 1 );

  $ds->StartTransaction();
  
  $self->{earliestdate} = "2100-01-01";
  $self->{latestdate} = "1970-01-01";

  my $cref = $self->{filestore}->GetFile( $data->{xmltvid}, $filename );

  p "Processing";

  eval { $self->ImportContent( $filename, $cref, $data ); };
  my( $message, $highest ) = EndLogSection( $data->{xmltvid} . 
					    " $filename" );
  if( $@ ) {
    $message .= $@;
    $highest = 5;
    $ds->Reset();
  }

  if( $highest > 3 ) {
    $ds->EndTransaction( 0 );

    $ds->sa->Update( "files", 
                     { channelid => $data->{id},
                       "binary filename" => $filename, },
                     { successful => 0,
                       message => $message, } );
    
  }
  else { 
    $ds->EndTransaction( 1 );
  
    $ds->sa->Update( "files", 
                     { channelid => $data->{id},
                       "binary filename" => $filename, },
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

=begin nd

Method: ImportContent

The ImportContent method must be overridden in an importer. It does
the actual job of importing data from a batch into the database.

The call to ImportContent is wrapped inside a StartLogSection with the
ConfigName and filename. ImportContent must call StartBatch itself,
since the base class cannot know which batch(es) this file contains.

Returns: 1 on success, 0 if the import failed so badly that the
  database hasn't been updated with data from the file.

=cut

sub ImportContent #( $filename, $cref, $chd )
{
  my $self = shift;

  my( $filename, $cref, $chd ) = @_;

  die "You must override ImportContent";
}

sub md5sum {
  my( $file ) = @_;
  open(FILE, $file) or die "Can't open '$file': $!";
  binmode(FILE);
  
  return Digest::MD5->new->addfile(*FILE)->hexdigest;
}

1;
