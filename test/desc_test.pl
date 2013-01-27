#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

my $text = "Filmklubben Norden: Hämnden";
$text =~ s/^Filmklubben\s+Norden:\s*//;

print("$text\n");