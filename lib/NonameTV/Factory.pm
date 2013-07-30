package NonameTV::Factory;

use strict;
use warnings;

=head1 NAME

NonameTV::Factory

=head1 DESCRIPTION

Create other NonameTV objects based on the available configuration.

=head1 METHODS

=over 4

=cut

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ CreateAugmenter
                       CreateDataStore CreateDataStoreDummy
                       CreateImporter CreateExporter CreateFileStore
                       InitHttpCache
                     /;
}
our @EXPORT_OK;

use NonameTV::Config qw/ReadConfig/;

=item CreateAugmenter( $name, $ds, $sched_lang )

Create an augmenter from the configuration in $conf->{Augmenter}->{$name}
and associate it with the NonameTV::DataStore in $ds.

Returns the newly created augmenter or dies if creation fails.

=cut

sub CreateAugmenter( $$$ ){
  my( $name, $ds, $lang ) = @_;

  my $conf = ReadConfig();
  
  if( not exists( $conf->{Augmenters}->{$name} ) ) {
    print STDERR "No such augmenter $name\n";
    exit 1;
  }

  my $aug_data = $conf->{Augmenters}->{$name};
  $aug_data->{ConfigName} = $name;

  my $aug_type = $aug_data->{Type};

  if( not defined $aug_type ) {
    print STDERR "Augmenter $name has no Type-field\n";
    exit 1;
  }

  # if the configuration does not specify a Language use the one from the
  # channel configuration that gets passed here as third parameter
  if( !defined( $aug_data->{Language} ) ){
    $aug_data->{Language} = $lang;
  }

  my $aug = eval "use NonameTV::Augmenter::$aug_type; 
                  NonameTV::Augmenter::${aug_type}->new( \$aug_data, \$ds );"
                      or die $@;
  return $aug;
}

=item CreateImporter( $name, $ds )

Create an importer from the configuration in $conf->{Importer}->{$name}
and associate it with the NonameTV::DataStore in $ds.

Returns the newly created importer or dies if creation fails.

=cut

sub CreateImporter {
  my( $name, $ds ) = @_;

  my $conf = ReadConfig();
  
  if( not exists( $conf->{Importers}->{$name} ) ) {
    print STDERR "No such importer $name\n";
    exit 1;
  }

  my $imp_data = $conf->{Importers}->{$name};
  $imp_data->{ConfigName} = $name;

  my $imp_type = $imp_data->{Type};

  if( not defined $imp_type ) {
    print STDERR "Importer $name has no Type-field\n";
    exit 1;
  }

  my $imp = eval "use NonameTV::Importer::$imp_type; 
                  NonameTV::Importer::${imp_type}->new( \$imp_data, \$ds );"
                      or die $@;
  return $imp;
}

=item CreateExporter( $name, $ds )

Create an exporter from the configuration in $conf->{Exporter}->{$name}
and associate it with the NonameTV::DataStore in $ds.

Returns the newly created exporter or dies if creation fails.

=cut

sub CreateExporter {
  my( $name, $ds ) = @_;

  my $conf = ReadConfig();
  
  if( not exists( $conf->{Exporters}->{$name} ) ) {
    print STDERR "No such exporter $name\n";
    exit 1;
  }

  my $exp_data = $conf->{Exporters}->{$name};
  my $exp_type = $exp_data->{Type};

  my $exp = eval "use NonameTV::Exporter::$exp_type; 
                  NonameTV::Exporter::${exp_type}->new( \$exp_data, \$ds );"
                      or die $@;
  return $exp;
}

=item CreateFileStore( $importername )

Create a NonameTV::FileStore object that matches the configuration
for an importer. 

Returns the newly created filestore or dies if creation fails.

=cut

sub CreateFileStore {
  my( $importername ) = @_;

  require NonameTV::FileStore;

  my $conf = ReadConfig();
  
  if( not exists( $conf->{Importers}->{$importername} ) ) {
    print STDERR "No such importer $importername\n";
    exit 1;
  }

  my $path;

  if( exists( $conf->{Importers}->{$importername}->{FileStore} ) ) {
    $path = $conf->{Importers}->{$importername}->{FileStore};
  }
  elsif( exists( $conf->{FileStore} ) ) {
    $path = $conf->{FileStore};
  }
  else {
    print STDERR "No FileStore found in configuration for " .
        "importer $importername.";
    exit 1;
  }

  return NonameTV::FileStore->new( { Path => $path } );
}

=item CreateDataStore

Create a NonameTV::DataStore from the configuration.

Returns the newly created datastore or dies if creation fails.
If CreateDataStore is called more than once, the same DataStore object
will be returned avery time.

=cut

my $ds;

sub CreateDataStore {
  return $ds if defined $ds;

  my $conf = ReadConfig();
  
  require NonameTV::DataStore;
  $ds = NonameTV::DataStore->new( $conf->{DataStore} );

  return $ds;
}

=item CreateDataStoreDummy

Create a dummy datastore (see NonameTV::DataStore::Dummy) from the
configuration.

Returns the newly created datastore or dies if creation fails.

=cut

sub CreateDataStoreDummy {
  my $conf = ReadConfig();
  
  require NonameTV::DataStore::Dummy;
  return NonameTV::DataStore::Dummy->new( $conf->{DataStore} );
}

=item InitHttpCache

Initialize the HTTP::Cache::Transparent module from the configuration.

=cut

sub InitHttpCache {
  require HTTP::Cache::Transparent;
  my $conf = ReadConfig();
  HTTP::Cache::Transparent::init( $conf->{Cache} );
}

1;

