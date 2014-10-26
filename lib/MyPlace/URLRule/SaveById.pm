

package MyPlace::URLRule::SaveById;

use File::Spec::Functions qw/catfile catdir/;
use MyPlace::ReEnterable;

sub new {
	my $class = shift;
	my $self = bless {},$class;
	if(@_) {
		my %opt = @_;
		foreach(keys %opt) {
			$self->{options}->{uc($_)} = $opt{$_};
		}
	}
	$self->{database} = "TEXT INPUT";
	return $self;
}


sub level {
	my $self = shift;
	return ($self->{options}->{LEVEL} || 0);
}

sub build_url {
	my $self = shift;
	my $id = shift;
	my $name = shift;
	my $template = $self->{options}->{URI_TEMPLATE};
	if(!$template) {
		return undef,"No URI template defined";
	}
	my $r = $template;
	$r =~ s/###ID###/$id/g;
	$r =~ s/###NAME###/$name/g;
	return $r;
}

sub _parse_from_file {
	my $self = shift;
	my $input = shift;
	my @lines;
	open FI,'<',$input or return undef,"$!, while opening $input";
	@lines = <FI>;
	close FI;
	return $self->_parse_from_text(@lines);
}

sub _parse_from_text {
	my $self = shift;
	my %info;
	my @sortedId;
	foreach(@_) {
		chomp;
		next unless($_);
		next if(m/^\s*$/);
		#print STDERR "TEXT:[$_]\n";
		if(m/^\s*\#OPTION\s*:\s*([^\s]+)\s+(.*?)\s*$/) {
			if(!defined $self->{options}->{$1}) {
				$self->{options}->{uc($1)}=$2 ? $2 : 'TRUE';
			}
		}
		elsif(m/^\s*([^\s]+)\s+([^\s+]+)\s*$/) {
			push @sortedId,$1 unless($following{$1});
			$info{$1} = "$2";
		}
		elsif(m/^\s*([^\s]+)\s*$/) {
			push @sortedId,$1 unless($following{$1});
			#$info{$1} = 1;
		}
		else {
			push @sortedId,$_;
		}
	}
	#die();
	if(!@sortedId) {
		return undef,"Invalid data feed";
	}
	return {
		info=>\%info,
		sortedId=>\@sortedId,
	};
}

sub add {
	my $self = shift;
	my %info = ();
	my @sorted = ();
	if($self->{info}) {
		%info = %{$self->{info}};
		@sorted = @{$self->{sortedId}};
	};
	my ($r,$msg) = $self->_parse_from_text(@_);
	if(!$r) {
		return undef,$msg;
	}
	my %incoming = %{$r->{info}};
	my @id = @{$r->{sortedId}};
	my $count;
	foreach my $id(@id) {
		if($id =~ m/^\s*$/) {
			next;
		}
		elsif($id =~ m/^#/) {
			next;
		}
		elsif($info{$id}) {
			next;
		}
		elsif($info{"#$id"}) {
			next;
		}
		elsif($incoming{$id}) {
			$count++;
			$info{$id} = $incoming{$id};
			push @sorted,$id;
		}
		else {
			push @sorted,$id;
		}
	}
	$self->{info} = \%info;
	$self->{sortedId} = \@sorted;
	return $count,'No id found';
}

sub saveTo {
	my $self = shift;
	my $output = shift;
	my $comment = shift;
	if(!$self->{info}) {
		return undef,"No id to save";
	}
	open FO,">",$output or return undef,"$!, while writting $output";
	foreach my $opt (keys %{$self->{options}}) {
		print FO "#OPTION: $opt\t",$self->{options}->{$opt},"\n";
	}
	foreach my $id (@{$self->{sortedId}}) {
		#	my $value = $self->{info}->{$id};
		#next unless($value);
		#if($value eq 'TRUE') {
		#	print FO $id,"\n";
		#}
		if($self->{info}->{$id}) {
			print FO $id,"\t",$self->{info}->{$id},"\n";
		}
		else {
			print FO $id,"\n";
		}
	}
	print FO "#$comment\n" if($comment);
	close FO;
	return 1;
}


sub feed {
	my $self = shift;
	my $data = shift;
	my $type = shift(@_) || "";
	if(!$data) {
		if($self->{data}) {
			$data = $self->{data};
		}
		else {
			return undef,"No data supplied";
		}
	}
	my ($r,$msg);
	if(ref $data && $data->{info} && $data->{sortedId}) {
		$r = $data;
	}
	elsif($type eq 'file' or -f $data) {
		$self->{database} = $data;
		($r,$msg) = $self->_parse_from_file($data);
	}
	else {
		($r,$msg) = $self->_parse_from_text($data);
	}
	#use Data::Dumper;die(Data::Dumper->Dump([$r],[qw/$r/]));
	if($r) {
		$self->{info} = $r->{info};
		$self->{sortedId} = $r->{sortedId};
	}
	return undef,$msg unless($self->{info} && $self->{sortedId});
	return $r;
}



sub query {
	my $self = shift;
	my %target;
	my @Id;
	my %info = ();
	my @sortedId = ();
	if($self->{info}) {
		%info = %{$self->{info}};
		@sortedId = @{$self->{sortedId}};
	}
	if(@_) {
	#my $utf8 = find_encoding("utf-8");
	#map $_=$utf8->decode($_),@_;
		my @keys = keys %info;
		QUERY:foreach my $r(@_) {
			foreach my $key (@keys) {
				if($r eq $key) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					next QUERY;
				}
			}
			foreach my $key (@keys) {
				if($r eq $info{$key}) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					next QUERY;
				}
			}
			my $matched = 0;
			foreach my $key (@keys) {
				if($key =~ m/$r/) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					$matched = 1;
				}
			}
			foreach my $key (@keys) {
				if($info{$key} =~ m/$r/) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					$matched = 1;
				}
			}
			if(!$matched) {
				print STDERR "Query [$r] match nothing in database ($self->{database})\n";
			}
		}
	}
	else {
		%target = %info;
		@Id = @sortedId;
	}
	return {
		target=>\%target,
		sortedId=>\@Id,
	};
}

sub _upgrade {
	my $self = shift;
	my $query = shift;
	foreach my $id(@{$query->{sortedId}}) {
		next if($id =~ m/^#/);
		my $name = $query->{target}->{$id} || $id;
		if(! -d $name) {
			#print STDERR "$name [Ignored, Directory not exists]\n";
			next;
		}
		my $newdir = catdir("_upgrade",$name,$self->{options}->{HOST});
		if(!-d $newdir) {
			system("mkdir","-vp","--",$newdir);
		}
		my $newname = catdir($newdir,$id); 
		if(-d $newname) {
			print STDERR "$name [Ignored, Maybe upgraded already]\n";
		}
		else {
			system("mv","-v","--",$name,$newname);
		}
	}
}

sub update {
	my $self = shift;
	my $query = shift;
	my $WD = shift;
	my $level = $self->level;
	
	if($self->{DEBUG}) {
		foreach my $id(@{$query->{sortedId}}) {
			next if($id =~ m/^#/);
			my $name = $query->{target}->{$id} || $id;
			#print STDERR "NAME:$WD $name \n";
			my $dist = catfile($WD,$name);
			my ($url,$msg) = $self->build_url($id,$name);
			if(!$url) {
				die("Error: $msg\n");
			}
			print STDERR "[$name] $url $level\n";
		}
		return;
	}

=old method

	mkdir ".urlrule" unless -d ".urlrule";
	my $R = MyPlace::ReEnterable->new('main',catfile(".urlrule","resume"));
	if($query->{target}) {
		
		foreach my $id (@{$query->{sortedId}}) {
			next if($id =~ m/^#/);
			#print STDERR "WD:$WD\nID:$id\nNAME:$query->{target}->{$id} \n";
			my $dist = catfile($WD,$query->{target}->{$id});
			$R->unshift(
				$dist,
				'load_rule',
				undef,
				$self->build_url($id,$query->{target}->{$id}),
				$self->level,
				"SAVE",
				'',
			);
		}
		$R->saveToFile();
		exec('urlrule_action');
=cut
	if($query->{target}) {
		my $hostname = $self->{options}->{HOST};
		my $HOSTNAME = uc($hostname);
		my $db = "DATABASE_" . $HOSTNAME . ".URL";
		open FO,">",$db or die("Error opening $db for writting: $!\n");
		foreach my $id (@{$query->{sortedId}}) {
				next if($id =~ m/^\s*#/);
				print FO $query->{target}->{$id},"\n\t",$id,"\n\t\t",$hostname,"\n";
		}
		close FO;
		if(!$HOSTNAME) {
			$HOSTNAME = "SAVEBYID";
		}
		my $host = "HOST_" . $HOSTNAME . ".URL";
		if(!-f $host) {
			$host = "HOSTS_SAVEBYID.URL";
		}
		if(!-f $host) {
			$host = "HOSTS.URL";
		}
		if(! -f $host) {
			$host = "HOST_" . $HOSTNAME . ".URL";
			open FO,">",$host or die("Error opening $host for writting:$!\n");
			print FO $hostname,
					"\n\t",$self->{options}->{URI_TEMPLATE},
					"\n\t\t",$self->{options}->{LEVEL},
					"\n";
			close FO;
		}

		exec("urlrule_task","--database",$db,"--hosts",$host,"SAVE",'/.+/');
	}
	else {
		die("Nothing to do\n");
	}
}


1;

__END__
