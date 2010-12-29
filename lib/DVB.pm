package DVB;


=pod

This file contains some DVB related functions.
Draft: "ETSI EN 300 468"

=cut

use strict;
use warnings;

use utf8;
use Env;

use NonameTV::Log qw/progress/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/DVBCategory/;
}
our @EXPORT_OK;

sub DVBCategory
{
  my( $ds, $categ, $type ) = @_;

  my $defaultcategory = "0:0:0:0";
  return $defaultcategory if ( $categ !~ /\S+/i );

  my $q = "SELECT * from dvb_cat WHERE `category` LIKE '%" . $categ . "%' LIMIT 1";
  my( $res, $data ) = $ds->sa->Sql( $q );

  return $defaultcategory if( ! $res );

  while( my $category = $data->fetchrow_hashref() ) {
    return $category->{dvb_category};
  }

  return $defaultcategory;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
