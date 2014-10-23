package NonameTV::DataStore;

use strict;
use utf8;
use warnings;

use NonameTV qw/FixProgrammeData/;
use NonameTV::Augmenter;
use NonameTV::Log qw/d p w f StartLogSection EndLogSection/;
use SQLAbstraction::mysql;

use Carp qw/confess/;
use DateTime::Format::Strptime;

use Storable qw/dclone/;

=head1 NAME

NonameTV::DataStore

=head1 DESCRIPTION

Interface to the datastore for NonameTV. The datastore is normally
an SQL database, but the interface for this class makes no
assumption about it.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a hashref as the only parameter.
This is a ref to the configuration for the object from the nonametv.conf-
file.

The configuration must contain the following keys:

type

"MySQL" is currently the only allowed type.

dbhost, dbname, username, password

Specifies how to connect to the MySQL database.

=cut

sub new {
  my $class = ref( $_[0] ) || $_[0];

  my $self = {};
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key ( keys( %{ $_[1] } ) ) {
    $self->{$key} = ( $_[1] )->{$key};
  }

  defined( $self->{type} ) and $self->{type} eq "MySQL"
    or die "type must be MySQL: $self->{type}";

  defined( $self->{dbhost} )   or die "You must specify dbhost";
  defined( $self->{dbname} )   or die "You must specify dbname";
  defined( $self->{username} ) or die "You must specify username";
  defined( $self->{password} ) or die "You must specify password";

  $self->{sa} = SQLAbstraction::mysql->new(
    {
      dbhost     => $self->{dbhost},
      dbname     => $self->{dbname},
      dbuser     => $self->{username},
      dbpassword => $self->{password},
    }
  );

  $self->{sa}->Connect();

  $self->{SILENCE_END_START_OVERLAP} = 0;
  $self->{SILENCE_DUPLICATE_SKIP}    = 0;

  return $self;
}

=item Creating a new batch

To create a new batch or replace an old batch completely, 
do the following steps:

  StartBatch( $batch_id );
  AddProgramme( ... );
  AddProgramme( ... );
  ...
  EndBatch( $success, $message );

=item StartBatch

Called by an importer to signal the start of a batch of updates.
Takes a single parameter containing a string that uniquely identifies
a set of programmes.  

=cut

sub StartBatch {
  my ( $self, $batchname ) = @_;

  confess("Nested calls to StartBatch")
    if ( defined( $self->{currbatch} ) );

  my $id = $self->{sa}->Lookup( 'batches', { name => $batchname }, 'id' );

  if ( defined($id) ) {
    $self->{sa}->DoSql("START TRANSACTION");
    $self->{sa}->Delete( 'programs', { batch_id => $id } );
  }
  else {
    $id = $self->{sa}->Add( 'batches', { name => $batchname } );
    $self->{sa}->DoSql("START TRANSACTION");
  }

  $self->{last_start} = "1970-01-01 00:00:00";
  $self->{last_prog}  = undef;

  $self->SetBatch( $id, $batchname );
}

# Hidden method used internally and by DataStore::Updater.
sub SetBatch {
  my $self = shift;
  my ( $id, $batchname ) = @_;

  $self->{currbatch}     = $id;
  $self->{currbatchname} = $batchname;
  $self->{batcherror}    = 0;
}

# Hidden method used internally and by DataStore::Updater.
sub ClearBatch {
  my $self = shift;

  delete $self->{currbatch};
  delete $self->{currbatchname};
  delete $self->{batcherror};
}

=item CommitPrograms

CommitPrograms is a dummy method in this class. It only actually does
something in NonameTV::DataStore::Helper.

=cut

sub CommitPrograms {
  my $self = shift;
}

=item EndBatch

Called by an importer to signal the end of a batch of updates.
Takes two parameters: 

An integer containing 1 if the batch was processed
successfully, 0 if the batch failed and the database should
be rolled back to the contents as they were before StartBatch was called.
and -1 if the batch should be rolled back because it has not changed.

A string containing a log-message to add to the batchrecord. If success==1,
then the log-message is stored in the field 'message'. If success==0, then
the log-message is stored in abort_message. If success==-1, the log message
is not stored. The log-message can be undef.

=cut

sub EndBatch {
  my ( $self, $success, $log ) = @_;

  confess("EndBatch called without StartBatch")
    unless defined( $self->{currbatch} );

  $log = "" if not defined $log;

  $self->AddLastProgramme(undef);

  if ( $success == 0 or $self->{batcherror} ) {
    $self->{sa}->DoSql("Rollback");
    d "Rolling back changes";

    if ( defined($log) ) {
      $self->SetBatchAbortMessage( $self->{currbatch}, $log );
    }
  }
  elsif ( $success == 1 ) {
    if( exists( $self->{augment} ) ){
      StartLogSection( 'augment ' . $self->{currbatchname}, 1 );
      if( $self->{augment} == 1 ){
        my $augmenter = NonameTV::Augmenter->new( $self );
        eval { $augmenter->AugmentBatch( $self->{currbatchname} ) };
      }
      $log .= EndLogSection( 'augment ' . $self->{currbatchname} );
    }

    $self->{sa}->Update(
      'batches',
      { id => $self->{currbatch} },
      {
        last_update   => time(),
        message       => $log,
        abort_message => "",
      }
    );

    $self->{sa}->DoSql("Commit");
  }
  elsif ( $success == -1 ) {
    $self->{sa}->DoSql("Rollback");
  }
  else {
    confess("Wrong value for success");
  }

  delete $self->{currbatch};
}

sub SetBatchAbortMessage {
  my $self = shift;
  my ( $batch, $message ) = @_;

  $self->{sa}
    ->Update( 'batches', { id => $batch }, { abort_message => $message } );
}

=item AddProgramme

Called by an importer to add a programme for the current batch.
Takes a single parameter contining a hashref with information
about the programme.

  $ds->AddProgramme( {
    channel_id => 1,
    start_time => "2004-12-24 14:00:00",
    end_time   => "2004-12-24 15:00:00", # Optional
    title      => "Kalle Anka och hans vänner",
    subtitle   => "Episode title"        # Optional
    description => "Traditionsenligt julfirande",
    episode    =>  "0 . 12/13 . 0/3", # Season, episode and part as xmltv_ns
                                      # Optional
    category   => [ "sport" ],        # Optional
  } );

The times must be in UTC. The strings must be properly encoded perl-strings.

To specify a period of no programmes, either set the end_time of the last
programme explicitly, or add a special program like this: 

  $ds->AddProgramme( {
    channel_id => 1,
    start_time => "2004-12-24 23:00:00",
    title      => "end-of-transmission",
  } );


=cut

sub AddProgramme {
  my ( $self, $data ) = @_;

  confess("You must call StartBatch before AddProgramme")
      unless exists $self->{currbatch};

  confess(
    "Required item channel_id missing"
  ) if not defined( $data->{channel_id} );

  return if $self->{batcherror};

  if (  ( $data->{start_time} eq $self->{last_start} )
    and ( $data->{title} = $self->{last_title} ) )
  {
    w "Skipping duplicate entry for $data->{start_time}"
      unless $self->{SILENCE_DUPLICATE_SKIP};
    return;
  }
  elsif ( $data->{start_time} le $self->{last_start} ) {
    w "Starttime must be later than last starttime: "
        . $self->{last_start} . " -> "
        . $data->{start_time} . ": "
        . $data->{title};
    return;
  }

  my $first_programme = defined $self->{last_prog} ? 0 : 1;

  $self->AddLastProgramme( $data->{start_time} );

  $self->{last_start} = $data->{start_time};
  $self->{last_title} = $data->{title};

  if ( $data->{title} eq 'end-of-transmission' and not $first_programme ) {

    # If this is not the first programme in the batch, then
    # we have already added all the necessary info with the call to
    # AddLastProgramme. Do not add an explicit entry for end-of-transmission
    # since this might collide with the start of tomorrows shows.
    return;
  }

  if ( exists( $data->{end_time} ) ) {
    if ( $data->{start_time} ge $data->{end_time} ) {
      w "Stoptime must be later than starttime: "
          . $data->{start_time} . " -> "
          . $data->{end_time} . ": "
          . $data->{title};
      return;
    }
  }

  FixProgrammeData($data);

  $self->{last_prog} = dclone($data);
}

sub AddLastProgramme {
  my $self = shift;
  my ($nextstart) = @_;

  my $data = $self->{last_prog};
  return if not defined $data;

  if ( defined($nextstart) ) {
    if ( defined( $data->{end_time} ) ) {
      if ( $nextstart lt $data->{end_time} ) {
        w "Starttime must be later than or equal to last endtime: "
            . $data->{end_time} . " -> "
            . $nextstart
          unless $self->{SILENCE_END_START_OVERLAP};

        $data->{end_time} = $nextstart;
      }
    }
    else {
      $data->{end_time} = $nextstart;
    }
  }

  $self->AddProgrammeRaw($data);
  $self->{last_prog} = undef;
}

=item AddProgrammeRaw

Same as AddProgramme but does not check for overlapping programmes or
require that the programmes are added in order.

=cut

sub AddProgrammeRaw {
  my ( $self, $data ) = @_;

  die("You must call StartBatch before AddProgramme")
    unless exists $self->{currbatch};

  return if $self->{batcherror};

  if ( $data->{title} !~ /\S/ ) {
    w "Empty title at " . $data->{start_time};
    $data->{title} = "end-of-transmission";
  }

  $data->{batch_id} = $self->{currbatch};

  if ( not defined( $data->{category} ) ) {
    delete( $data->{category} );
  }

  if ( not defined( $data->{program_type} ) ) {
    delete( $data->{program_type} );
  }

  if ( exists( $data->{description} ) and defined( $data->{description} ) ) {

    # Strip leading and trailing whitespace from description.
    $data->{description} =~ s/^\s+//;
    $data->{description} =~ s/\s+$//;
  }

  if ( $self->{sa}->Add( 'programs', $data, 0 ) == -1 ) {
    my $err = $self->{dbh_errstr};

    # Check for common error-conditions
    my $data_org = $self->{sa}->Lookup(
      "programs",
      {
        channel_id => $data->{channel_id},
        start_time => $data->{start_time}
      }
    );

    if ( defined($data_org) ) {
      if ( $data_org->{title} eq "end-of-transmission" ) {
        w "Replacing end-of-transmission "
            . "for $data->{channel_id}-$data->{start_time}";

        $self->{sa}->Delete(
          "programs",
          {
            channel_id => $data->{channel_id},
            start_time => $data->{start_time}
          }
        );

        if ( $self->{sa}->Add( 'programs', $data, 0 ) == -1 ) {
          w $self->{dbh_errstr};
          $self->{batcherror} = 1;
        }
      }
      elsif ( $data_org->{title} eq $data->{title} ) {
        w "Skipping duplicate entry "
            . "for $data->{channel_id}-$data->{start_time}"
          unless $self->{SILENCE_DUPLICATE_SKIP};
      }
      else {
        w "Duplicate programs "
            . $data->{start_time} . ": '"
            . $data->{title} . "', '"
            . $data_org->{title}
            . "'";
        $self->{batcherror} = 1;
      }
    }
    else {
      if ($err) {
        w $err;
      } else {
        w "FIXME error but empty err variable! (might be field in ce that is not in the programs table)";
      }
      $self->{batcherror} = 1;
    }
  }
}

=item ClearChannel

Delete all programs for a channel. Takes one parameter, the channel id
for the channel in question.

Returns the number of programs that were deleted.

=cut

sub ClearChannel {
  my $self = shift;
  my ($chid) = @_;

  my $deleted = $self->{sa}->Delete( 'programs', { channel_id => $chid } );

  my $xmltvid = $self->{sa}->Lookup( 'channels', { id => $chid }, 'xmltvid' );

  $self->{sa}->DoSql( "delete from batches where name like '${xmltvid}_%'", [] );
  $self->{sa}->Delete( 'files', { channelid => $chid } );

  return $deleted;
}

=item FindGrabberChannels 

Returns an array with all channels associated with a specific channel.
Each channel is described by a hashref with keys matching the database.

Takes one parameter: the name of the grabber.
The result is ordered by xmltvid.

=cut

sub FindGrabberChannels {
  my $self = shift;
  my ($grabber) = @_;

  my @result;

  return $self->{sa}->LookupMany( 'channels', { grabber => $grabber },
				  [ 'xmltvid' ] );
}

=item LookupCat

Lookup a category found in an infile and translate it to
a proper program_type and category for use in AddProgramme.

  my( $pty, $cat ) = $ds->LookupCat( 'Viasat', 'MUSIK' );
  $ds->AddProgramme( { ..., category => $cat, program_type => $pty } );

=cut

sub LookupCat {
  my $self = shift;
  my ( $type, $org ) = @_;

  return ( undef, undef ) if ( not defined($org) ) or ( $org !~ /\S/ );

  $org =~ s/^\s+//;
  $org =~ s/\s+$//;

  # I should be using locales, but I don't dare turn them on.
  $org = lc($org);
  $org =~ tr/ÅÄÖ/åäö/;

  # The field has room for 50 characters. Unicode may occupy
  # several bytes with one character.
  # Treat all categories with the same X character prefix
  # as equal.
  $org = substr( $org, 0, 44 );

  $self->LoadCategories()
    if not exists( $self->{categories} );

  if ( not exists( $self->{categories}->{"$type++$org"} ) ) {

    # MySQL considers some characters as equal, e.g. e and é.
    # Trying to insert both anime and animé will give an error-message
    # from MySql. Therefore, I try to lookup the new entry before adding
    # it to see if MySQL thinks it already exists. I should probably
    # normalize the strings before inserting them instead...
    my $data =
      $self->{sa}->Lookup( "trans_cat", { type => $type, original => $org } );
    if ( defined($data) ) {
      $self->{categories}->{ $type . "++" . $org } =
        [ $data->{program_type}, $data->{category} ];
    }
    else {
      $self->AddCategory( $type, $org );
    }
  }

  if ( defined( $self->{categories}->{"$type++$org"} ) ) {
    return @{ ( $self->{categories}->{"$type++$org"} ) };
  }
  else {
    return ( undef, undef );
  }

}

sub LookupCountry {
  my $self = shift;
  my ( $type, $org ) = @_;

  return ( undef, undef ) if ( not defined($org) ) or ( $org !~ /\S/ );

  $org =~ s/^\s+//;
  $org =~ s/\s+$//;

  # I should be using locales, but I don't dare turn them on.
  $org = lc($org);
  $org =~ tr/ÅÄÖ/åäö/;

  # The field has room for 50 characters. Unicode may occupy
  # several bytes with one character.
  # Treat all countries with the same X character prefix
  # as equal.
  $org = substr( $org, 0, 44 );

  $self->LoadCountries()
    if not exists( $self->{countries} );

  if ( not exists( $self->{countries}->{"$type++$org"} ) ) {

    # MySQL considers some characters as equal, e.g. e and é.
    # Trying to insert both anime and animé will give an error-message
    # from MySql. Therefore, I try to lookup the new entry before adding
    # it to see if MySQL thinks it already exists. I should probably
    # normalize the strings before inserting them instead...
    my $data =
      $self->{sa}->Lookup( "trans_country", { type => $type, original => $org } );
    if ( defined($data) ) {
      $self->{countries}->{ $type . "++" . $org } =
        [ $data->{country} ];
    }
    else {
      $self->AddCountry( $type, $org );
    }
  }

  if ( defined( $self->{countries}->{"$type++$org"} ) ) {
    return @{ ( $self->{countries}->{"$type++$org"} ) };
  }
  else {
    return ( undef, undef );
  }

}

=item Reset

Reset the datastore-object to its initial state. This method can be called
between imports to make sure that errors from one import does not affect
the next import.

=cut

sub Reset {
  my $self = shift;

  if ( defined( $self->{currbatch} ) ) {
    $self->EndBatch(0);
  }
}

=item StartTransaction

Start a new datastore transaction. Can be used to wrap a set of datastore
operations into a single transaction that can either be committed or
reverted.

    $ds->StartTransaction();
    # Do stuff to the datastore
    $ds->EndTransaction(1); # Commit the changes.

=cut

sub StartTransaction {
  my $self = shift;

  $self->{sa}->DoSql("START TRANSACTION");
}

=item EndTransaction

End a datastore transaction. Takes a boolean parameter that decides if
the transaction shall be committed (true) or reverted (false).

=cut

sub EndTransaction {
  my $self = shift;
  my ($commit) = @_;

  if ($commit) {
    $self->{sa}->DoSql("COMMIT");
  }
  else {
    $self->{sa}->DoSql("ROLLBACK");
  }
}

sub LoadCategories {
  my $self = shift;

  my $d = {};

  my $sth = $self->{sa}->Iterate( 'trans_cat', {} );
  if ( not defined($sth) ) {
    $self->{categories} = {};
    w "No categories found in database.";
    return;
  }

  while ( my $data = $sth->fetchrow_hashref() ) {
    $d->{ $data->{type} . "++" . $data->{original} } =
      [ $data->{program_type}, $data->{category} ];
  }
  $sth->finish();

  $self->{categories} = $d;
}

sub AddCategory {
  my $self = shift;
  my ( $type, $org ) = @_;

  $self->{sa}->Add(
    'trans_cat',
    {
      type     => $type,
      original => $org
    }
  );
  $self->{categories}->{"$type++$org"} = [ undef, undef ];
}

sub LoadCountries {
  my $self = shift;

  my $d = {};

  my $sth = $self->{sa}->Iterate( 'trans_country', {} );
  if ( not defined($sth) ) {
    $self->{countries} = {};
    w "No countries found in database.";
    return;
  }

  while ( my $data = $sth->fetchrow_hashref() ) {
    $d->{ $data->{type} . "++" . $data->{original} } =
      [ $data->{country} ];
  }
  $sth->finish();

  $self->{countries} = $d;
}

sub AddCountry {
  my $self = shift;
  my ( $type, $org ) = @_;

  $self->{sa}->Add(
    'trans_country',
    {
      type     => $type,
      original => $org
    }
  );
  $self->{countries}->{"$type++$org"} = [ undef, undef ];
}

=item sa

Returns the SQLAbstraction object to give direct access to the database.

=cut

sub sa {
  my $self = shift;

  return $self->{sa};
}

=item ParsePrograms

Replacement for fetching our own export and parsing with ParseXmltv.
Returns an array of hashrefs just like ParseXmltv.
Parameter is a batch name. (file name of the export without .xml.gz)

=cut

sub ParsePrograms {
  my $self;
  my $res;
  my $sth;

  my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );

    # replacement for ParseXmltv on our own Export
       $self     = shift;
    my $batch_id = shift;
    my( $xmltv_id, $date ) = ($batch_id =~ m|^(.*)_([-\d]+)$|);
    my $next_date = $parser->parse_datetime( $date . ' 00:00:00' )->add( days => 1 )->ymd('-');

    my $channel = $self->sa->Lookup( 'channels', { xmltvid => $xmltv_id } );
    my $def_cat;
    my $def_pty;
    if( $channel ){
      $def_cat = $channel->{def_cat};
      $def_pty = $channel->{def_pty};
    };

    ( $res, $sth ) = $self->sa->Sql( "
        SELECT p.* from programs p, channels c
        WHERE (c.xmltvid = ?)
          and (p.channel_id = c.id) 
          and (p.start_time >= ?)
          and (p.start_time <= ?) 
        ORDER BY start_time asc, end_time desc", 
      [$xmltv_id, $date . ' 00:00:00', $next_date . ' 23:59:59'] );
  
  my @result;

  my $done;
  my $ce = $sth->fetchrow_hashref();
  if( !defined( $ce ) ) {
    return undef;
  }
  while( my $next_ce = $sth->fetchrow_hashref() ) {
    # Break loop once we have got the whole day?
    if( $ce->{start_time} gt $date . ' 23:59:59' ) {
      $done = 1;
      last;
    }
    if( $ce->{aspect} eq 'unknown' ) {
      delete $ce->{aspect};
    }
    foreach my $key (keys %$ce) {
      if( !defined( $ce->{$key} )) {
        delete $ce->{$key};
      } elsif( $ce->{$key} eq '' ){
        delete $ce->{$key};
      } elsif( $ce->{$key} eq '0000-00-00 00:00:00') {
        delete $ce->{$key};
      }
    }

    $ce->{start_dt} = $parser->parse_datetime( $ce->{start_time} );
    delete $ce->{start_time};

    if( exists( $ce->{end_time} )) {
      $ce->{stop_dt} = $parser->parse_datetime( $ce->{end_time} );
      delete $ce->{end_time};
    } else {
      $ce->{stop_dt} = $parser->parse_datetime( $next_ce->{start_time} );
    }

    if( !defined( $ce->{category} ) && $def_cat){
      $ce->{category} = $def_cat;
    }
    if( !defined( $ce->{program_type} ) && $def_pty){
      $ce->{program_type} = $def_pty;
    }

    push (@result, $ce);
    $ce = $next_ce;
  }

  return \@result;
}

=back 

=head1 COPYRIGHT

Copyright (C) 2006 Mattias Holmlund.

=cut

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
