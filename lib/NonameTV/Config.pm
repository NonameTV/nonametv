package NonameTV::Config;

use strict;
use warnings;

=head1 NAME

NonameTV::Config - Read and parse the configuration file(s) for
NonameTV.

=head1 SYNOPSIS

 use NonameTV::Config qw/ReadConfig/;

 my $conf = ReadConfig()

=head1 DESCRIPTION

NonameTV looks for the configuration file first at 

    $HOME/.nonametv.conf

and if that file is not found then it looks at

    /etc/nonametv.conf

After one of these files are loaded, it also looks for a file called override.conf in the root-directory of the NonameTV installation. The contents of override.conf will override any parameters set in the other configuration file.

override.conf is meant to contain any parameters that are specific to
this installation of NonameTV. This can be used to have one production version of NonameTV and one development version on the same system. The override.conf for the development-version can then contain:

  {
    DataStore => {
      dbname => 'nonametv-dev',
    },

    Cache => {
      BasePath => '/var/local/nonametv-dev/cache',
    }

    ContentCachePath => '/var/local/nonametv-dev/contentcache/',

    FileStore => '/var/local/nonametv-dev/channels/',
    LogFile => '/var/log/nonametv/nonametv-dev.log',
  }

=cut

use File::Slurp;
use Carp;

use NonameTV::Path;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.3;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ReadConfig MergeHash/;
}
our @EXPORT_OK;

# Global variable containing the configuration after ReadConfig
# has been called.
my $Conf;

sub ReadConfig {
  return $Conf if defined $Conf;

  my $file;
  if (defined( $ENV{HOME} ) and (-e "$ENV{HOME}/.nonametv.conf")) {
  	$file = "$ENV{HOME}/.nonametv.conf";
  } elsif (-e "/etc/nonametv.conf") {
  	$file = "/etc/nonametv.conf";
  } else {
  	die "No configuration file found in $ENV{HOME}/.nonametv.conf or /etc/nonametv.conf"
  }
  
  my $config = read_file( $file );

  my $conf = eval( $config );
  die "Error in configuration file $file: $@" if $@;

  my $override_file = NonameTV::Path::Root() . "/override.conf";
  if( -f $override_file ) {
    my $str = read_file( $override_file );
    my $override = eval( $str );
    die "Error in configuration file $override_file: $@" if $@;
    if( $override->{ResetConfig} ) {
      $conf = $override;
    }
    else {
      MergeHash( $conf, $override );
    }
  }

  $Conf = $conf;
  return $conf;
}

sub MergeHash {
  my( $src, $add ) = @_;

  croak "$src is not a hashref" if ref( $src ) ne "HASH";
  croak "$add is not a hashref" if ref( $add ) ne "HASH";

  foreach my $key (keys %{$add}) {
    if( not ref( $add->{$key} ) ) {
      $src->{$key} = $add->{$key};
    }
    elsif( ref( $add->{$key} ) eq "HASH" ) {
      $src->{$key} = {} if not defined $src->{$key};
      MergeHash( $src->{$key}, $add->{$key} );
    }
  }
  
}

1;
