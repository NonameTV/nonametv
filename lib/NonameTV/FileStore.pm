package NonameTV::FileStore;

use strict;
use warnings;

use NonameTV::Log qw/d p w f/;

use File::Slurp qw/read_file/;
use LWP::Simple qw/get/;
use Digest::MD5 qw/md5_hex/;
use File::Path qw/mkpath/;
use File::stat;

use Carp qw/croak carp/;

use utf8;

=begin nd

Class: NonameTV::FileStore

=cut

=begin nd:

Constructor: new

=cut 

sub new #( $param )
{
  my $class = ref( $_[0] ) || $_[0];

  my $self = {};
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key ( keys( %{ $_[1] } ) ) {
    $self->{$key} = ( $_[1] )->{$key};
  }

  croak "Failed to specify Path"
      if not defined $self->{Path};

  $self->{_fl} = {};

  return $self;
}

=begin nd

Method: AddFile

Add a new file to the filestore for a specific channel. If an
identical file already exists (same filename and md5sum), no action is
performed. If a file with the same name but different content exists,
the old file is replaced with the new file.

Returns: undef

=cut

sub AddFile #( $xmltvid, $filename, $cref )
{
  my $self = shift;
  my( $xmltvid, $filename, $cref ) = @_;

  $self->LoadFileList( $xmltvid );

  carp "Cannot add a file to a remote filestore"
      if not $self->PathIsLocal();

  my $dir = $self->{Path} . "/$xmltvid";

  mkpath( $dir );

  my( $oldmd5, $ts ) = $self->GetFileMeta( $xmltvid, $filename );
  
  use bytes; # Wide character fix
  my $newmd5 = md5_hex( $$cref . "" ); # Wide character fix
  if( not defined( $oldmd5 ) ) {
    my $fullname = "$dir/$filename";
    open( OUT, "> $fullname" ) or die "Failed to write to $fullname";
    print OUT $$cref;
    close( OUT );
    
    $self->AddFileMeta( $xmltvid, $filename, $newmd5 );
  }
  elsif( $oldmd5 ne $newmd5 ) {
    # Same filename but different content. Make up a new filename.
    my( $base, $ext ) = ($filename =~ /^(.*)(\..*?)$/);
    if( not defined $ext ) {
      $base = $filename;
      $ext = "";
    }

    my $nextmd5;
    my $nextfilename;

    for( my $c=1; $c<100; $c++ ) {
      $nextfilename = "$base-$c$ext";
      ( $nextmd5 ) = $self->GetFileMeta( $xmltvid, $nextfilename );
      if( (not defined( $nextmd5 )) or ($nextmd5 eq $newmd5) ) {
	last;
      }
    }

    if( not defined( $nextmd5 ) ) {
      my $fullname = "$dir/$nextfilename";
      open( OUT, "> $fullname" ) or die "Failed to write to $fullname";
      print OUT $$cref;
      close( OUT );
      
      $self->AddFileMeta( $xmltvid, $nextfilename, $newmd5 );
    }
  }
  else {
#    print "Duplicate file skipped.\n";
  }
}

sub AddFileMeta {
  my $self = shift;
  my( $xmltvid, $filename, $md5 ) = @_;

  # Delete any entry with the same filename
  $self->{_fl}->{$xmltvid} = 
      [ grep { $_->[0] ne $filename } @{$self->{_fl}->{$xmltvid}} ];

  push @{$self->{_fl}->{$xmltvid}}, [ $filename, $md5, time()];
  $self->{_flmodified}->{$xmltvid} = 1;
}

=begin nd

Method: ListFiles

Returns an array with arrayrefs, where each arrayref contains a
filename, an md5sum, and a timestamp for when the file was first added.

=cut

sub ListFiles #( $xmltvid )
{
  my $self = shift;
  my( $xmltvid ) = @_;

  $self->LoadFileList( $xmltvid );

  return @{$self->{_fl}->{$xmltvid}};
}

=begin nd

Method: GetFile

Returns a reference to the contents of the specified file or undef
if the file does not exist.

=cut

sub GetFile {
  my $self = shift;
  my( $xmltvid, $filename ) = @_;

  my $fullname = $self->{Path} . "/$xmltvid/$filename";

  my $result;

  if( $self->PathIsLocal() ) {
    $result = read_file( $fullname, err_mode => 'quiet' );
  }
  else {
    $result = get( $fullname );
  }

  return defined( $result ) ? \$result : undef;
}

sub GetFileMeta {
  my $self = shift;
  my( $xmltvid, $filename ) = @_;

  foreach my $e (@{$self->{_fl}->{$xmltvid}}) {
    return ($e->[1], $e->[2]) if $e->[0] eq $filename;
  }
  
  return undef;
}

=begin nd

Method: RemoveOldFiles

Remove all files for a specific channel that were added more than
$days days ago.

=cut

sub RemoveOldFiles #( $xmltvid, $days )
{
}

sub PathIsLocal {
  my $self = shift;

  return not $self->{Path} =~ /^http:/;
}

sub LoadFileList {
  my $self = shift;
  my( $xmltvid ) = @_;

  return if defined $self->{_fl}->{$xmltvid};

  my @d;

  my $fl = $self->GetFile( $xmltvid, "00files" );

  if( not defined $fl ) {
    $self->RecreateIndex( $xmltvid );
    return;
  }

  foreach my $line (split( "\n", $$fl)) {
    my( $filename, $md5sum, $ts ) = split( "\t", $line );
    push @d, [ $filename, $md5sum, $ts ];
  }

  $self->{_fl}->{$xmltvid} = \@d;
  $self->{_flmodified}->{$xmltvid} = 0;
}

=begin nd

Method: RecreateIndex

Recreate the index file from the files stored in the correct location.

=cut

sub RecreateIndex #( $xmltvid )
{
  my $self = shift;
  my( $xmltvid ) = @_;

  my @data;

  unlink( $self->{Path} . "/$xmltvid/00files" );

  foreach my $file (glob( $self->{Path} . "/$xmltvid/*" )) {
    my( $name ) = ($file =~ /.*\/(.*)/ );
    
    # Dont fucking do that.
    if($name eq "old") {
    	next;
    }
    
    open(FILE, $file) or die "Can’t open ’$file’: $!";
    binmode(FILE);

    my $md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    my $st = stat($file) or die "Couldn't stat $file: $!";
    my $mtime = $st->mtime;

    push( @data, [$name, $md5, $mtime] );
  }

  $self->{_fl}->{$xmltvid} = [ sort { $a->[2] <=> $b->[2] } @data ];
  $self->{_flmodified}->{$xmltvid} = 1;
}

sub WriteFileMeta {
  my $self = shift;
  my( $xmltvid ) = @_;

  my $fullname = $self->{Path} . "/$xmltvid/00files";
  open( OUT, "> $fullname" ) or die "Failed to write to $fullname";
  foreach my $e (@{$self->{_fl}->{$xmltvid}}) {
    print OUT join( "\t", @{$e} ) . "\n";
  }
  close( OUT );
}

sub DESTROY {
  my $self = shift;

  foreach my $xmltvid (keys %{$self->{_flmodified}} ) {
    $self->WriteFileMeta( $xmltvid ) 
        if $self->{_flmodified}->{$xmltvid};
  }
}

=head1 COPYRIGHT

Copyright (C) 2008 Mattias Holmlund.

=cut

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
