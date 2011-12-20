#!/usr/bin/perl -w
package MyPlace::URLRule::File;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw();
}
sub new {my $class = shift;return bless {@_},$class;}

1;

__END__
=pod

=head1  NAME

MyPlace::URLRule::File - PERL Module

=head1  SYNOPSIS

use MyPlace::URLRule::File;

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2011-10-09 22:31  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>


# vim:filetype=perl

