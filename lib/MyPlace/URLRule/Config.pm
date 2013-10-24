#!/usr/bin/perl -w
use strict;
use warnings;
package MyPlace::URLRule::Config;
use File::Spec::Functions qw/catfile/;
my $NHISTORY = "history";
my $NIGNORE = "ignore";
my $NRESUME = "resume";


sub new {
	my $class = shift;
	my $dir = shift(@_) || ".urlrule";
	my $self = bless {configDir=>$dir},$class;
	if(! -d $dir) {
		mkdir $dir or die("$!\n");
	}
	$self->init(@_);
	return $self;
}

sub init {
	my $self = shift;
	foreach(@_) {
		if($_ eq $NHISTORY) {
			$self->history();
		}
		if($_ eq $NIGNORE) {
			$self->history();
		}
		if($_ eq $NRESUME) {
			$self->history();
		}
	}
}

sub history {
	my $self = shift;
	if(!$self->{$NHISTORY}) {
		require MyPlace::History;
		$self->{$NHISTORY} = MyPlace::History->new(catfile($self->{configDir},"/$NHISTORY"));
	}
	return $self->{$NHISTORY};
}

sub ignore {
	my $self = shift;
	if(!$self->{$NIGNORE}) {
		require MyPlace::History;
		$self->{$NIGNORE} = MyPlace::History->new(catfile($self->{configDir},"/$NIGNORE"));
	}
	return $self->{$NIGNORE};
}

sub resume {
	my $self = shift;
	if(!$self->{$NRESUME}) {
		require MyPlace::ReEnterable;
		$self->{$NRESUME} = MyPlace::ReEnterable->new("main",catfile($self->{configDir},"/$NRESUME"));
	}
	return $self->{$NRESUME};
}

