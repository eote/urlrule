#!/usr/bin/perl -w
package MyPlace::URLRule::Sites;
use strict;
use warnings;
use File::Spec::Functions qw/catfile/;
use MyPlace::URLRule::SimpleQuery;

sub new {
	my $class = shift;
	return bless {},$class;
}

sub get_database {
	my $self = shift;
	my $site = shift;
	return undef unless($site);
	return $self->{cached}->{$site} if($self->{cached}->{site});
	$self->{cached}->{$site} = new MyPlace::URLRule::SimpleQuery($site);
	return $self->{cached}->{$site};
}

sub query {
	my $self = shift;
	my $site = shift;
	my @NAMES = @_;
	
	my $db = $self->get_database($site);
	if(!$db) {
		return undef,"Database not available for site:$site";
	}
	if(!@NAMES) {
		return $db->all();
	}
	my @result;
	my $error;
	foreach my $keyword (@NAMES) {
		my($status,@r) = $db->query($keyword);
		if($status) {
			push @result,@r;
		}
	}
	if(@result) {
		return 1,\@result;
	}
	else {
		return 1, "Query " . join(", ",@NAMES) . " match nothing";
	}
}

sub do_print {
	my $self = shift;
	my $site = shift;
	my @names = @_;
	my ($status,$result) = $self->query($site,@names);
	if(!$status) {
		print STDERR $result,"\n";
		return;
	}
	print STDERR "[" . uc($site) . "]:\n";
	my $idx = 0;
	foreach my $item(@{$result}) {
		$idx++;
		printf "\t[%03d] %-20s [%d]  %s\n",$idx,$item->[1],$item->[2],$item->[0];
		$idx++;
	}
	return;
}

sub do_action {
	my $self = shift;
	my $cmd = shift;
	my $site = shift;
	my @names = @_;
	my ($status,$result) = $self->query($site,@names);
	if($status) {
		my $action = uc($cmd);
		use MyPlace::URLRule::OO;
		my $URLRULE = new MyPlace::URLRule::OO('action'=>$action);
		my @request;
		my $count = 0;
		foreach my $item(@$result) {
			next unless($item && @{$item});
			push @request,{
				count=>1,
				level=>$item->[2],
				url=>$item->[1],
				title=>$item->[0] . "/$site/",
			};
			$count++;
		}
		my $idx = 0;
		foreach(@request) {
			$idx++;
			$_->{progress} = "[$idx/$count]";
			$URLRULE->autoApply($_);
		}
		return 0;
	}
}

sub do_update {
	my $self = shift;
	return $self->do_action('UPDATE',@_);
}

sub do_save {
	my $self = shift;
	return $self->do_action('SAVE',@_);
}

sub add_id {
	my $self = shift;
	my $site = shift;
	my $db = $self->get_database($site);
	if(@_) {
		my $r = $db->add(@_);
		$db->save();
		return $r;
	}
	else {
		return undef;
	}
}

__END__

#       vim:filetype=perl
1;

