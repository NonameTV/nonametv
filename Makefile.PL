require 5.004;
use strict;

use ExtUtils::MakeMaker;

WriteMakefile(
   NAME          => 'NonameTV',
   VERSION_FROM  => 'lib/NonameTV.pm',
   EXE_FILES     => [ qw{
       tools/nonametv-import
       tools/nonametv-export
       } ],
   'dist'        => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (AUTHOR     => 'Mattias Holmlund <mattias@holmlund.se>') : ()),
);
