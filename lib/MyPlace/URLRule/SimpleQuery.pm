#!/usr/bin/perl -w
package MyPlace::URLRule::SimpleQuery;
use strict;
use warnings;
use MyPlace::URLRule;
use MyPlace::SimpleQuery;
our $SQ_DATABASE_LIST = "weibo.com,weipai.cn,vlook.cn,google.search.image,miaopai.com,blog.sina.com.cn,meipai.com,weishi.com";

our @SQ_DATABASE_ALL;

sub load_db {
	my $self = shift;
	my $dbname = shift;
	my @options = @_;
	if(ref $dbname) {
		($dbname,@options) = @$dbname;
	}
	elsif($dbname eq '*') {
		@SQ_DATABASE_ALL = ();	
		foreach my $pdir (@MyPlace::URLRule::URLRULE_LIB) {
			next unless(-d $pdir);
			foreach my $dir(glob("$pdir/sites/*/")) {
				if(-d $dir and $dir =~ m/([^\/]+)\/$/) {
					push @SQ_DATABASE_ALL,$1;
				}
			}
		}
		foreach(@SQ_DATABASE_ALL) {
			$self->load_db($_,@options);
		}
		return;
	}

	my $dbfile = $dbname;
	foreach my $basename ($dbname, uc($dbname), $dbname . ".sq", uc($dbname) . ".sq") {
		if(-f $basename) {
			$dbfile = $basename;
			last;
		}
		my $filename = MyPlace::URLRule::locate_file($basename);
		if(-f $filename) {
			$dbfile = $filename;
			last;
		}
		$filename = MyPlace::URLRule::locate_file("sites/$basename");
		if(-f $filename) {
			$dbfile = $filename;
			last;
		}
		$filename = MyPlace::URLRule::locate_file("sites/$basename/database.sq");
		if(-f $filename) {
			$dbfile = $filename;
			last;
		}
	}
	my $db = new MyPlace::SimpleQuery;
	if(@options) {
			$db->set_options(@options);
	}
	print STDERR "Loading database [$dbname] $dbfile ...\n" if($self->{VERBOSE});
	$db->feed($dbfile) if(-f $dbfile);
	$self->{db} = {} unless($self->{db});
	$self->{db}->{$dbname} = $db;
	$self->{dbinfo} = {} unless($self->{dbinfo});
	$self->{dbinfo}->{$dbname} = $dbfile;
	return $db;
}

sub dbfiles {
	my $self = shift;
	return unless($self->{dbinfo});
	my @files;
	foreach(keys %{$self->{dbinfo}}) {
		push @files,$self->{dbinfo}->{$_};
	}
	return @files;
}

sub get_dbinfo {
	my $self = shift;
	my $info = $self->{dbinfo};
	return %{$info};
}

sub new {
	my $class = shift;
	my $self = bless {},$class;
	foreach(@_) {
		$self->load_db($_);
	}
	return $self;
}

sub additem {
	my $self = shift;
	my $total = 0;
	my @error;
	if($self->{db}) {
		foreach my $dbname (keys %{$self->{db}}) {
			my ($count,$msg) = $self->{db}->{$dbname}->additem(@_);
			if($count) {
				$total += $count;
				#print STDERR "$count Id add to [database:$dbname]\n";
			}
			else {
				push @error,"[database:$dbname] $msg";
			}
		}
		if(@error) {
			#print STDERR join("\n",@error),"\n";
		}
		return $total,join("\n",@error);
	}
	else {
		return undef,"NO database loaded"; 
	}
}
sub add {
	my $self = shift;
	my $total = 0;
	my @error;
	if($self->{db}) {
		foreach my $dbname (keys %{$self->{db}}) {
			my ($count,$msg) = $self->{db}->{$dbname}->add(@_);
			if($count) {
				$total += $count;
				#print STDERR "$count Id add to [database:$dbname]\n";
			}
			else {
				push @error,"[database:$dbname] $msg";
			}
		}
		if(@error) {
			#print STDERR join("\n",@error),"\n";
		}
		return $total,join("\n",@error);
	}
	else {
		return undef,"NO database loaded"; 
	}
}

sub save {
	my $self = shift;
	if($self->{db}) {
		foreach my $dbname (keys %{$self->{db}}) {
			$self->{db}->{$dbname}->saveTo($self->{dbinfo}->{$dbname});
		}
	}
	else {
		return undef,"NO database loaded"; 
	}
	
}

sub item {
	my $self = shift;
	my $idName = shift;
	my $dbname = shift;
	if(!$dbname) {
		$dbname = (keys %{$self->{db}})[0];
	}
	return $self->{db}->{$dbname}->item($idName,@_);
}

sub find_item {
	my $self = shift;
	my $idName = shift;
	my $dbname = shift;
	if(!$dbname) {
		$dbname = (keys %{$self->{db}})[0];
	}
	return $self->{db}->{$dbname}->find_item(undef,$idName,@_);
}
sub find_items {
	my $self = shift;
	my $dbname = shift;
	if(!$dbname) {
		$dbname = (keys %{$self->{db}})[0];
	}
	return $self->{db}->{$dbname}->find_items(@_);
}

sub query {
	my $self = shift;
	my $key = shift;
	my $dbname = shift;
	if($dbname) {
		if($self->{db}->{dbname}) {
			return $self->{db}->{dbname}->query($key);
		}
		else {
			return undef,"Database $dbname not load";
		}
	}
	elsif($self->{db}) {
		my @result;
		foreach my $dbname (keys %{$self->{db}}) {
			my ($r,@item) = $self->{db}->{$dbname}->query($key);
			if($r) {
				push @result,@item;
			}
		}
		if(@result) {
			return 1,@result;
		}
		else {
			return undef,"Query $key match nothing";
		}
	}
	else {
		return undef,"NO database loaded"; 
	}
}

sub all {
	my $self = shift;
	my $dbname = shift;
	if($dbname) {
		if($self->{db}->{dbname}) {
			return $self->{db}->{dbname}->all();
		}
		else {
			return undef,"Database $dbname not load";
		}
	}
	elsif($self->{db}) {
		my @result;
		foreach my $dbname (keys %{$self->{db}}) {
			my ($r,@item) = $self->{db}->{$dbname}->all();
			if($r) {
				push @result,@item;
			}
		}
		if(@result) {
			return 1,@result;
		}
		else {
			return undef,"Database contains nothing";
		}
	}
	else {
		return undef,"NO database loaded"; 
	}

}

1;
__END__
