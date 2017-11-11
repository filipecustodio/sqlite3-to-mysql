#!/opt/local/bin/perl

# Convert sqlite3 to mysql dump.
# Inspired by Thomas Eng https://github.com/athlite
#
# Filipe Custodio, NOV 2017

use strict;
use Data::Dumper;

scalar( @ARGV ) == 2 || die "usage: $0 <input.sql> <output.sql>";

open( FILE, $ARGV[0] ) || die 'cannot open ' . $ARGV[0];

# Read structure and map integers and varchars

my $cur_table;
my $colcount;
my $dbstruct = {};

while ( <FILE> ) {
	chomp;
	
	if ( /CREATE TABLE (\w+)/ ) {
		$cur_table = $1;
		$colcount = 0;
	} elsif ( /^\s*\);/ ) {
		$cur_table = undef;
	} elsif ( /INSERT INTO "([^"]+)" VALUES\s*\(([^)]+)\);/ ) {
		my $table = $1;
		my $col = 0;
		my $collist = $2;
		while ( $collist ne '' ) {
			my $v;
			if ( $collist =~ /^'([^']*)'\s*,*\s*(.*)$/ ) {
				$v = $1;
				$collist = $2;
			} elsif ( $collist =~ /^([^,]*),*(.*)$/ ) {
				$v = $1;
				$collist = $2;
			}
			my $t = $dbstruct->{$table}->[$col]->{type};
			if ( $t ) {
				if ( $t eq 'INTEGER' ) {
					if ( $dbstruct->{$table}->[$col]->{maxvalue} ) {
						if ( $dbstruct->{$table}->[$col]->{maxvalue} < $v ) {
							$dbstruct->{$table}->[$col]->{maxvalue} = $v;
						}
					} else {
						$dbstruct->{$table}->[$col]->{maxvalue} = $v;
					}
				} elsif ( $t eq 'VARCHAR' ) {
					if ( $dbstruct->{$table}->[$col]->{maxlen} ) {
						if ( $dbstruct->{$table}->[$col]->{maxlen} < length($v) ) {
							$dbstruct->{$table}->[$col]->{maxlen} = length($v);
						}
					} else {
						$dbstruct->{$table}->[$col]->{maxlen} = length($v);
					}
				}
			}
			$col++;
		}
	} elsif ( /^\s*(\w+)\s+(\w+).*/ ) {
		if ( $cur_table ) {
			$dbstruct->{$cur_table}->[$colcount]->{name} = $1;
			$dbstruct->{$cur_table}->[$colcount]->{type} = $2;
			$colcount++;
		}
	}
}

close FILE;

# Second pass, make the actual transformations

open( FILE, $ARGV[0] ) || die 'cannot open ' . $ARGV[0];
open( OUTPUT, '>' . $ARGV[1] ) || die 'cannot write to ' . $ARGV[1];

while ( <FILE> ) {
	my $line = $_;
	
	# DB column structure
	if ( /CREATE TABLE (\w+)(.*)$/ ) {
		$line = "DROP TABLE IF EXISTS $1; CREATE TABLE $1$2";
		$cur_table = $1;
		$colcount = 0;
	} elsif ( /^\s*\);/ ) {
		$cur_table = undef;
	} elsif ( /^(\s*)(\w+)\s+(\w+)(.*)$/ ) {
		if ( $cur_table ) {
			# Change data types
			my $start = $1;
			my $c = $2;
			my $t = $3;
			my $end = $4;
			
			if ( $t eq 'INTEGER' ) {
				my $max = $dbstruct->{$cur_table}->[$colcount]->{maxvalue};
				if ( $max ) {
					if ( $max <= 127 ) {
						$t = 'TINYINT';
					} elsif ( $max <= 32767 ) {
						$t = 'SMALLINT';
					} elsif ( $max <= 8388607 ) {
						$t = 'MEDIUMINT';
					} elsif ( $max <= 2147483647 ) {
						$t = 'INT';
					} else {
						$t = 'BIGINT';
					}
				} else {
					$t = 'INT';
				}
			} elsif ( $t eq 'VARCHAR' ) {
				my $max = $dbstruct->{$cur_table}->[$colcount]->{maxlen};
				if ( $max ) {
					if ( $max <= 21845 ) {
						$t = 'VARCHAR(' . $max . ')';
					} elsif ( $max <= 65535 ) {
						$t = 'TEXT';
					} else {
						$t = 'LONGTEXT';
					}
				} else {
					$t = 'VARCHAR(90)';
				}
			}
			$colcount++;
			$line = $start . $c . ' ' . $t . $end . "\n";
		}
	}
	
	# Now the rest of the filtering
	my $reserved_words = [ 'utc_timestamp' ]; # Add here any words that need escaping
	
	$line =~ s/PRAGMA.*;//g;
	$line =~ s/BEGIN TRANSACTION.*//g;
	$line =~ s/COMMIT;//g;
	$line =~ s/.*sqlite_sequence.*;//g;
	$line =~ s/"/`/g;
	$line =~ s/AUTOINCREMENT/AUTO_INCREMENT/g;
	$line =~ s/DEFERRABLE INITIALLY DEFERRED//g;
	$line =~ s/'t'/1/g;
	$line =~ s/,X'/,'/g;
	
	foreach ( @{$reserved_words} ) {
		$line =~ s/$_/`$_`/g;
	}
	
	print OUTPUT $line;
}

close(FILE);
close(OUTPUT);




