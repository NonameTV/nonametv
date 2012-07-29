package NonameTV::Language;

=pod

Languages module for NonameTV.

=cut

use strict;
use warnings;

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/LoadLanguage/;
}
our @EXPORT_OK;

sub LoadLanguage
{
  my( $lang, $module , $ds ) = @_;

  my $lng;

  my $sth = $ds->sa->Iterate( 'languagestrings', 
                              { language => $lang, module => $module } );
  if( not defined( $sth ) )
  {
     die( "No strings found in database for language $lang, " .
	  "module $module." );
    return;
  }

  while( my $data = $sth->fetchrow_hashref() )
  {
    $lng->{$data->{strname}} = $data->{strvalue};
  }

  return( $lng );
}

1;
