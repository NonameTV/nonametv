#!/usr/bin/perl

$role = "Regissör";
if( (defined $role) and ( $role =~ /Regiss(.*)r/i ) )
      {
        print("HEJ\n");
      }