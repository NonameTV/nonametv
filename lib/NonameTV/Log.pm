package NonameTV::Log;

=begin nd

package: NonameTV::Log

Logging-module for NonameTV.

=cut

use strict;
use warnings;

use POSIX qw/strftime/;
use IO::File;

use Carp qw/confess/;

use NonameTV::Config qw/ReadConfig/;

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/progress error
                    d p w f
                    StartLogSection EndLogSection
                    SetVerbosity/;
  
}
our @EXPORT_OK;

sub d;
sub p;
sub w;
sub e;

=begin nd

Topic: Severities

Logging is done at four different severities.

 Debug    - For debugging purposes
 Progress - Something has been updated.
 Warning  - Something unexpected has happened. 
            Execution of this task continued anyway. 
 Fatal    - A fatal error has occured. 
            Execution of this task will be aborted.

The perl built-in "warn" is overridden by this module and will print a
message at severity Warning. This means that the message will be
prefixed by the current LogSection to aid in debugging. The message
will include the entire stack-trace as printed by Carp::confess.

Topic: Log outputs

The log output is sent to three different destinations.

*STDERR*

Each message is prefixed with the severity and the current LogSection
name. The call to <SetVerbosity> decides which severities are printed
on STDERR.


*LOGFILE*

LogFile logs everything up to and including severity Progress. Each
message is prefixed with the severity and the current LogSection name.

*LogSection*

EndLogSection returns all messages with severity Warning and Fatal
that have been issued since the matching call to StartLogSection. The
messages are prefixed with the severity. 

=cut

use constant {
  DEBUG => 1,
  PROGRESS => 2,
  WARNING => 3,
  FATAL => 4,
  NONE => 100,
};

my $stderr_level = WARNING;
my $file_level = PROGRESS;


my $logfile;
my @section = [ undef, "", 0 ];

BEGIN {
  # Set STDOUT to use utf8 encoding. This avoids "Wide character in print"
  # warnings.
  binmode STDOUT, ":encoding(UTF8)";
  binmode STDERR, ":encoding(UTF8)";
  
  my $conf = ReadConfig();

  $logfile = new IO::File "$conf->{LogFile}", O_WRONLY|O_APPEND|O_CREAT;

  die "Failed to open logfile $conf->{LogFile} for writing"
    unless defined $logfile;

  # Flush the logfile to disk for each write.
  $logfile->autoflush( 1 );

  # write the log in a specific encoding
  $logfile->binmode( ":encoding(UTF-8)" );

  # Turn all "warn" statements into w():s.
  $SIG{'__WARN__'} = \&mywarn;
}

=begin nd

Group: Logging Functions

The logging functions all take a string as argument. This string is
prefixed with the chosen severity and current context and appended to
the different log outputs that are available.

For example:

>  if( $errorcondition ) {
>    w "Something wrong";
>  }
>
>  if( $downloadfailed ) {
>    f "Download failed";
>    return 0;
>  }

=cut

=begin nd

Print a log-message at severity Debug.

Parameters:

  $message - The message that shall be printed. 

Returns: 

nothing

=cut

sub d #( $message ) 
{
  my( $message ) = @_;

  writelog( DEBUG, "D", $section[0][0], $message );
}

=begin nd

Print a log-message at severity Progress.

Parameters:

  $message - The message that shall be printed. 

Returns: 

nothing

=cut

sub p #( $message )
{
  my( $message ) = @_;

  writelog( PROGRESS, "P", $section[0][0], $message );
}

=begin nd

Print a log-message at severity Warning.

Parameters:

  $message - The message that shall be printed. 

Returns: 

nothing

=cut

sub w #( $message )
{
  my( $message ) = @_;

  writelog( WARNING, "W", $section[0][0], $message );
}

=begin nd

Print a log-message at severity Fatal.

Parameters:

  $message - The message that shall be printed. 

Returns: 

nothing

=cut

sub f #( $message )
{
  my( $message ) = @_;

  writelog( FATAL, "F", $section[0][0], $message );
}

sub writelog {
  my( $level, $levelstr, $prefix, $message ) = @_;

  # Remove trailing newline added by warn.
  $message =~ s/\s+$//;

  my $pmessage;
  if( defined( $prefix ) ) {
    $pmessage = "$prefix: $message";
  }
  else {
    $pmessage = $message;
  }

  my $time = strftime( '%F %T', localtime );

  # Print to STDERR if the verbosity level says so
  # or if the current logsection is not captured.
  if( ($level >= $stderr_level) or 
      ($level >= WARNING and not $section[0][3]) ) {
    print STDERR "$levelstr: $pmessage\n";
  }

  if( $level >= $file_level ) {
    print $logfile "$time $levelstr: $pmessage\n";
  }

  if( $level >= WARNING ) {
    $section[0][1] .= "$levelstr: $message\n";
  }

  if( $level > $section[0][2] ) {
    $section[0][2] = $level;
  }
}

=begin nd

Group: Miscellaneous functions

=cut

=begin nd

Set the lowest Severity level that will be printed on STDERR.

Parameters:

  $verbose - Verbosity level, 0, 1, or 2.
  $quiet - Be quiet, 0, 1, or 2.

Normally, severities Warning and Fatal are printed to STDERR. The
SetVerbosity function is meant to be used with command-line option
parsing where each occurence of --verbose increases $verbose with 1
and each occurence of --quiet increases $quiet by 1. It gives the
following result.

  --verbose prints Progress as well.
  --verbose --verbose prints Debug and Progress as well.
  --quiet prints only Fatal.
  --quiet --quiet prints nothing

Note that --quiet only applies to output that is generated within a
LogSection where $captured is true. Otherwise, Warning and Fatal are
always printed to STDERR. The idea behind this is that --quiet
silences output that is captured elsewhere, i.e. in the database
somewhere.

=cut
 
sub SetVerbosity #( $verbose, $quiet )
{
  my( $verbose, $quiet ) = @_;

  if( $verbose == 1 ) {
    $stderr_level = PROGRESS;
  }
  elsif( $verbose > 1 ) {
    $stderr_level = DEBUG;
  }
  elsif( $quiet == 1 ) {
    $stderr_level = FATAL;
  }
  elsif( $quiet > 1 ) {
    $stderr_level = NONE;
  }
  else {
    $stderr_level = WARNING;
  }
}

=begin nd

  StartLogSection/EndLogSection can be used to catch all warnings and
  fatal errors in a section of code.

  Parameters:
    
    $sectionname - A prefix that will be added to all messages.
    $captured - False if warnings and fatal messages should be printed 
                on STDERR even if the verbosity level is set to quiet. 
                True otherwise.

  Returns:

     Nothing.

This is for example used to catch
log messages emitted for each batch in an importer.

 
>  StartLogSection( "batchname", 1 );
>    (do stuff that may emit log messages)
>  my( $messages, $highestpriority ) = EndLogSection( "batchname" );


StartLogSection can be nested. An outer LogSection will NOT catch
messages that are caught by the inner LogSection.

=cut 

sub StartLogSection #( $sectionname, $captured )
{
  my( $sectionname, $captured ) = @_;

  confess "You need to specify \$captured to StartLogSection"
      if not defined $captured;

  unshift @section, [ $sectionname, "", 0, $captured ];
}


=begin nd

Parameters:
  $sectionname - Same name as in the matching call to StartLogSection. 
    The name is only used to catch bugs where a call to StartLogSection 
    is not followed by a matching call to EndLogSection. 

Returns:

In array context, EndLogSection returns a string containing the
messages and an integer describing the highest log level used in the
section. In scalar context, only the string is returned.

=cut

sub EndLogSection #( $sectionname )
{
  my( $sectionname ) = @_;

  if( $sectionname eq $section[0][0] ) {
    my $logstring = $section[0][1];
    my $logstring_highest = $section[0][2];
    shift @section;

    if( wantarray ) {
      return ($logstring, $logstring_highest);
    }
    else {
      return $logstring;
    }
  }
  else { 
    confess "Mismatched LogSections, got $sectionname, expected $section[0][0]";
  }
}

=begin nd

Group: Deprecated functions

These log-functions can be used by older code only. They should not be
used for new code. The LogSection string is not appended to these
messages.

=cut


=begin nd

Print a log-message at severity Progress.

Parameters:

  $message - The message that shall be printed. 

Returns: 

nothing

=cut

sub progress #( $message )
{
  my( $message ) = @_;

  writelog( PROGRESS, "PROG", undef, $message );
}

=begin nd

Print a log-message at severity Warning.

Parameters:

  $message - The message that shall be printed. 

Returns: 

nothing

=cut

sub error #( $message )
{
  my( $message ) = @_;

  writelog( WARNING, "ERROR", undef, $message );
}

sub mywarn {
  my( $message ) = @_;

#  w Carp::longmess( $message );
  w $message;
}


1;
