#!/usr/bin/perl -w
# $Id$
package MyPlace::Program::URLRule;
use base 'MyPlace::Program';
use strict;
use warnings;
use MyPlace::URLRule::Database;
use MyPlace::URLRule::SimpleQuery;
use File::Spec::Functions qw/catdir catfile/;
use Cwd qw/getcwd/;
my $MSG_PROMPT = 'urlrule';

my %EXIT_CODE = qw/
	OK			0
	FAILED		1
	DO_NOTHING	2
	ERROR_USAGE 3
/;

sub VERSION {'v0.1'}
sub OPTIONS {qw/
	help|h|? 
	manual|man
	hosts=s
	no-hosts|nh
	database|db
	no-database|ndb
	all|a
	thread=i
	retry
	prompt|p=s
	url|u
	overwrite|force|f
	files
	directory|d=s
	sed
	write|w
	disable=s@
	input|i=s
	follow
	reposter
/;}


sub p_out {
	print @_;
}

sub p_msg {
	print STDERR "$MSG_PROMPT> ",@_;
}

sub p_err {
	print STDERR "$MSG_PROMPT> ",@_;
}

sub p_warn {
	print STDERR "$MSG_PROMPT> ",@_;
}

sub check_trash {
	my $path = shift;
	foreach('#Empty','#Trash') {
		my $dir = $_ . "/" . $path;
		if(-d $dir) {
			print STDERR "[$path] in [$_] IGNORED!\n";
			return undef;
		}
	}
	return 1;
}

sub DB_INIT {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	return if($OPTS{url});

	if(!($OPTS{hosts} or defined $OPTS{database})) {
		$OPTS{all} = 1 unless($OPTS{'no-database'});
	}
	if($OPTS{all}) {
		$OPTS{hosts} = $OPTS{hosts} || "*";
		$OPTS{database} = $OPTS{database} || "";
	}
	if($OPTS{'no-database'} and $OPTS{'no-hosts'}) {
		print STDERR "Error: --no-hosts and --no-database both specified\n";
		return $self;
	}
	if($OPTS{'no-database'}) {
		delete $OPTS{database};
		$OPTS{hosts} = $OPTS{hosts} || "*";
	}
	if($OPTS{'no-hosts'}) {
		delete $OPTS{hosts};
		$OPTS{database} = $OPTS{database} || "";
	}
	if(not($OPTS{hosts} or defined $OPTS{database})) {
		print STDERR "Error: no --hosts or --database specified\n";
		return $self;
	}
	if(defined($OPTS{hosts})) {
		$self->{USQ} = MyPlace::URLRule::SimpleQuery->new();
		my @opts  = ('overwrite'=>1) if($OPTS{overwrite});
		foreach my $host (split(/\s*,\s*/,$OPTS{hosts})) {
			$self->{USQ}->load_db($host,@opts);
		}
	}
	if(defined($OPTS{database})) {
		$self->{DB} = [MyPlace::URLRule::Database->new()];
	}
	return $self;
}

sub dbfiles {
	my $self = shift;
	my @files;
	if($self->{USQ}) {
		push @files,$self->{USQ}->dbfiles;
	}
	if($self->{DB}) {
		foreach(@{$self->{DB}}) {
			push @files, $_->dbfiles;
		}
	}
	return @files;
}

sub query {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	if(!@_) {
		p_err "Nothing to do for nothing\n";
		return;
	}
	my @target;
	if($OPTS{url}) {
		push @target,{
			url=>shift(@_),
			level=>(shift(@_) || 0),
			title=>(shift(@_) || ""),
		}
	}
	my @queries;
	my $q = shift(@_);
	while($q) {
		if($q =~ m/^http/) {
			my $level = shift(@_);
			if(!$level) {
				$level = 0;
			}
			elsif($level !~ /^[0-9]$/) {
				unshift @_,$level;
				$level = 0;
			}
			push @target,{url=>$q,level=>$level};
		}
		else {
			push @queries,$q;
		}
		$q = shift(@_);
	}
#	die(join("\n",map {$_->{url}} @target),"\n");

	return @target unless(@queries);


	if($self->{USQ}) {
		my $USQ = $self->{USQ};
		foreach(@queries) {
			my ($status,@result) = $USQ->query($_);
			if($status) {
				foreach my $item (@result) {
					push @target,{
						host=>$item->[4],
						id=>$item->[0],
						name=>$item->[1],
						url=>$item->[2],
						level=>$item->[3],
					}
				}
			}
		}	
	}
	if($self->{DB} and @{$self->{DB}}) {
		foreach my $USD (@{$self->{DB}}) {
			foreach(@queries) {
				my ($status,@result) = $USD->query($_);
				push @target,@result if($status);
			}
		}
	}
	if(!@target) {
		p_err "Query \"@queries\" match nothing!\n";
	}
	return @target;
}


sub CMD_LIST {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my @target = @_;
	if(!@target) {
		return 1;
	}
	my $idx = 1;
	foreach(@target) {
		printf "[%03d]%-15s %30s [%d] %s\n",
				$idx,
				($_->{host} ? '<' . $_->{host} . '>' : '<URL>'),
				$_->{url},
				$_->{level},
				($_->{name} || "");
		$idx++;
	}
	return 0;
}

sub CMD_ACTION {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $cmd = shift(@_) || "UPDATE";
	my @target = @_;
	use MyPlace::URLRule::OO;
	my @request;
	my $count = 0;
	my %r;
	foreach my $item (@target) {
		if(!$item->{host}) {
			push @request,{
				count=>1,
				level=>$item->{level},
				url=>$item->{url},
				title=>$item->{title},
			};
			$count++;
			next;
		}
		my $dbname = $item->{host};
		if($dbname =~ m/^.+\|([^\|]+)$/) {
			$dbname = $1;
		}
		next unless($dbname);
		my $title = catdir($item->{name},$dbname);
		next unless(check_trash($title));
		push @request,{
			count=>1,
			level=>$item->{level},
			url=>$item->{url},
			title=>$title,
		};
		push @{$r{directory}},$title;
		$count++;
	}
	my $idx = 0;
	my $URLRULE = new MyPlace::URLRule::OO('action'=>$cmd,'thread'=>$OPTS{thread},'force'=>$OPTS{force});
	foreach(@request) {
		$idx++;
		$_->{progress} = "[$idx/$count]";
		$URLRULE->autoApply($_);
		$URLRULE->reset();
	}
	if($URLRULE->{DATAS_COUNT}) {
		return $EXIT_CODE{OK},\%r;
	}
	else {
		return $EXIT_CODE{DO_NOTHING},\%r;
	}
}

use File::Spec::Functions qw/catdir catfile/;
sub CMD_MOVE {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $dst = shift;
	my @target = @_;
	my $dstdir = $dst;
	foreach(@target) {
		my $oldname = $_->{name};
		my $newname = $dst;
		$self->CMD_ADD($newname,$_->{id},$_->{host});
		if($OPTS{'files'}) {
			my $src_target = catdir($_->{name},$_->{host},$_->{id});
			my $dst_target = catdir($dstdir,$_->{host},$_->{id});
			if(!-d $src_target) {
				p_err("Error, Directory $src_target not exist!");
				next;
			}
			my @cmds = (qw/mv -v --/,$src_target,$dst_target);
			print STDERR join(" ",@cmds),"\n";
			if(system(@cmds) != 0) {
				print STDERR "Error: $!\n";
			}
		}
	}
}
sub CMD_DOWNLOAD {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my @target = @_;
	my @request;
	my $count = 0;
	my %r;
	$self->CMD_ACTION('DATABASE',@target);
	use MyPlace::Program::Downloader;
	my $DL = new MyPlace::Program::Downloader;
	my @DLOPT = qw/--quiet --input urls.lst --recursive/;
	push @DLOPT,"--retry" if($OPTS{retry});

	foreach my $item (@target) {
		if($item->{host}) {
			my $dbname = $item->{host};
			if($dbname =~ m/^.+\|([^\|]+)$/) {
				$dbname = $1;
			}
			next unless($dbname);
			my $title = catdir($item->{name},$dbname);
			next unless(check_trash($title));
			push @request,$title;
			push @{$r{directory}},$title;
		}
		else {
			my $title = $item->{title} || ".";
			push @request,$title;
			push @{$r{directory}},$title;
		}
		$count++;
	}
	my $idx = 0;
	my $dlcount = 0;
	foreach(@request) {
		$idx++;
		my ($done,$error,$msg) = $DL->execute(@DLOPT,'--directory',$_,);
		if($done) {
			$dlcount += $done;
		}
		elsif($error) {
			print STDERR "Error($error): $msg\n";
		}
	}
	if($dlcount > 0) {
		return $EXIT_CODE{OK},\%r;
	}
	else {
		return $EXIT_CODE{DO_NOTHING},\%r;
	}
}

sub CMD_SED {
	my $self = shift;
	my $OPTS = $self->{OPTS};
	my $expref = shift;
	my @exps;
	my @files = @_;
	if(!$expref) {
	}
	elsif(ref $expref) {
		@exps = @$expref;
	}
	else {
		push @exps,$expref;
	}
	if(!@exps) {
		p_err "Invalid Usage\n$0 SED\nUsage:\n$0 SED [options] <Perl RegExp statement>\n";
		return $self->EXIT_CODE("USAGE");
	}
	
	if(!@files) {
		p_err "No database file to edit\n";
		return $self->EXIT_CODE("ERROR");
	}
	my $EXITVAL = $self->EXIT_CODE("OK");

	EDITFILE:
	foreach my $file(@files) {
		p_msg "File:$file ...";
		if(! -f $file) {
			p_err "File not exist: $file\n";
			$EXITVAL = $self->EXIT_CODE("IGNORED");
			next;
		}
		my @data;
		my $FH;
		if(!open $FH,"<",$file) {
			p_err "Error reading $file:$!\n";
			$EXITVAL = $self->EXIT_CODE("ERROR");
			next;
		}
		@data = <$FH>;
		close $FH;
		my @changed;
		foreach(@data) {
			foreach my $exp(@exps) {
				my $old = $_;
				eval($exp);
				if($@) {
					p_err "Error executing exp:$exp\n";
					next EDITFILE;
				}
				if($old ne $_) {
					push @changed,[$old,$_];
				}
			}	
		}
		if(@changed) {
			print STDERR "\t[OK]\n";
			foreach(@changed) {
				print STDERR "\t$_->[0]\n\t=> $_->[1]\n";
			}
		}
		else {
			print STDERR "\t[NOTHING CHANGED]\n";
		}
		if(@changed and $OPTS->{write}) {
			my $FO;
			system("cp","-av",'--',$file,$file . ".bak");
			if(!open $FO,">",$file) {
				p_err "Error writting $file:$!\n";
				$EXITVAL = $self->EXIT_CODE("ERROR");
				next;
			}
			p_msg "Writting $file ...";
			print $FO @data;
			close $FO;
			print STDERR "\t[OK]\n"
		}
	}
	return $EXITVAL;
}

use MyPlace::URLRule qw/parse_rule apply_rule/;
use Data::Dumper;
sub CMD_DUMP {
	my $self = shift;
	my @target = @_;
	foreach(@target) {
		my $rule = parse_rule($_->{url},$_->{level} || 0);
		my ($status,$r) = apply_rule($rule);
		print STDERR Data::Dumper->Dump([$rule,$r],[qw/$rule $result/]),"\n";
	}
	return $EXIT_CODE{OK};
}

my %URL_EXPS = (
	'mm\.taobao\.com'=>[
		'mm\.taobao\.com\/([^#&?]+)',
		'$1',undef,'mm.taobao.com',
	],
	'(?:www\.)moko\.cc'=>[
		'(?:www\.)moko\.cc\/([^\/]+)',
		'$1',undef,'moko.cc',
	],
	'tieba\.baidu\.com'=>[
		'tieba\.baidu\.com\/p\/(\d+)',
		'$1',undef,'post.tieba.baidu.com|tieba.baidu.com',
	],
	'\d+\.qzone\.qq\.com' => [
		'(\d+)\.qzone\.qq\.com',
		'$1',undef,'qzone.qq.com',
	],
	'user\.qzone\.qq\.com\/\d+' => [
		'user\.qzone\.qq\.com\/(\d+)',
		'$1',undef,'qzone.qq.com',
	],
	'home\.51\.com\/' => [
		'home\.51\.com\/([^\/]+)',
		'$1',undef,'home.51.com',
	],
	'[^\.]+\.taobao\.com' => [
		'([^\.]+)\.taobao\.com',
		'$1',undef,'shop.taobao.com',
	],
	'[^\.]+\.poco\.cn'=> [
		'([^\.]+)\.poco\.cn',
		'$1',undef,'poco.cn',
	],
	'blog\.sina\.com\.cn\/'=> [
		'blog\.sina\.com\.cn\/([^?&]+)',
		'$1',undef,'blog.sina.com.cn',
	],
);

sub parse_url {
	my $url = shift;
	
	my %result;
	foreach my $site(keys %URL_EXPS) {
		next unless($url =~ m/^https?:\/\/$site|^$site/);
		my($exp,$r1,$r2,$r3) = @{$URL_EXPS{$site}};
		next unless($exp);
		if($url =~ m/https?:\/\/$exp/) {
			$result{profile} = eval("\"$r1\"") if($r1);
			$result{uname} = eval("\"$r2\"") if($r2);
			$result{host} = eval("\"$r3\"") if($r3);
			last;
		}
	}
	return 1,\%result if(%result);
	if($url =~ m/^http/) {
		require MyPlace::URLRule;
		my $rule = MyPlace::URLRule::parse_rule($url,":info");
		my ($status,$result) = apply_rule($rule);
		if($status and $result->{profile}) {
			return 1,$result;
		}
		else {
			return 0,"Error: failed extract information from URL <$url>";
		}
	}
	return 1,\%result;
}

sub CMD_ADD {
	my $self = shift;
	my $OPTS = $self->{OPTS};
	my $name = shift;
	my $id = shift;
	my $host = shift(@_) || $OPTS->{hosts} || $OPTS->{db};
	my $exitval = 0;

	if(!$id) {
		$id = $name;
		$name = '';
	}
	if(!$host) {
		my ($r,$result) = parse_url($id);
		if($r) {
			if($result->{profile}) {
				p_msg "ID => $result->{profile}\n";
				$id = $result->{profile};
			}
			if($result->{uname} and !$name) {
				p_msg "NAME => $result->{uname}\n";
				$name = $result->{uname};
			}
			if($result->{host} and !$host) {
				p_msg "HOST => $result->{host}\n";
				$host = $result->{host};
				$OPTS->{hosts} = $host if(!$OPTS->{hosts});
			}
		}
		else {
			die($result . "\n");
		}
	}

	if(defined $OPTS->{hosts}	or defined $OPTS->{all}) {
		$OPTS->{hosts} = $host if($host);
	}
	if(!defined $OPTS->{hosts}) {
		die("Error <HOSTS> not defined\n");
	}
	if($OPTS->{follow}) {
		my @hosts;
		foreach my $hostname (split(/\s*,\s*/,$OPTS->{hosts})) {
			push @hosts,$hostname;
			my $f = "sites/$hostname/follows.txt";
			foreach($f,"follows/$hostname/follows.txt") {
				$f = $_ if(-f $_);
			}
			push @hosts,$f;
		}
		$OPTS->{hosts} = join(",",@hosts);
	}
	if($OPTS->{reposter}) {
		$name = '#Reposter/' . $name if($name);
	}
	$self->DB_INIT();

	if($self->{USQ}) {
		printf STDERR "%12s %s\n",'[HOSTS]', "Add $id -> $name <$OPTS->{hosts}>";
		 my ($count,$msg) = $self->{USQ}->additem($id,$name);
#		 print STDERR "\t$msg\n" if($msg);
		 if($count) {
			 $self->{USQ}->save();
		 }
		 $exitval = $count > 0 ? $self->EXIT_CODE('OK') : $self->EXIT_CODE('IGNORED');
	}
	if($self->{DB} and @{$self->{DB}}) {
		foreach my $USD (@{$self->{DB}}) {
			printf STDERR "%12s %s\n","[DATABASE]","Add $name -> $id -> $host";
			$USD->add($name,$id,$host);
			if($USD->is_dirty) {
				$USD->save();
			}
		}
	}
	return $exitval;
}

sub MAIN {
	my $self = shift;
	my $OPTS = shift;
	$MSG_PROMPT = $OPTS->{prompt} if($OPTS->{prompt});
	if($OPTS->{disable}) {
		foreach(@{$OPTS->{disable}}) {
				$OPTS->{"disable-$_"} = 1;
		}
	}
	$self->{OPTS} = $OPTS;
	if($OPTS->{directory}) {
		if(!chdir $OPTS->{directory}) {
			p_err "Error changing directory to $OPTS->{directory}:$!\n";
			return 1;
		}
		else {
			p_msg "Directory: $OPTS->{directory}\n";
		}
	}	
	

	my $cmd = shift;
	if(!$cmd) {
		$cmd = "HELP";
	}

	my $CMD = uc($cmd);
	my $EXIT = 0;

	if($cmd =~ m/^!(.+)$/) {
		$OPTS->{force} = 1;
		$cmd = $1;
		$CMD = uc($cmd);
	}

	if($CMD eq 'HELP') {
		return $self->USAGE;
	}
	elsif($CMD  eq 'MOVE') {
		$self->{OPTS}->{overwrite} = 1;
	}

	use MyPlace::Time qw/now/;
	if(!$OPTS->{'disable-log'}) {
		my @OARGV = @{$OPTS->{ORIGINAL_ARGV}} if($OPTS->{ORIGINAL_ARGV});
		if(open my $FO,">>",'urlrule.log') {
			print $FO now . ": urlrule ",join(" ",@OARGV),"\n";
			close $FO;
		}
		else {
			p_err "Error opening urlrule.log\n";
			return $self->EXIT_CODE("ERROR");
		}
	}

	if($CMD eq 'ADD') {
		return $self->CMD_ADD(@_);
	}
	else {
		$self->DB_INIT();
	}
	
	my @queries =  @_;

	if($OPTS->{input}) {
		p_msg "Read inputs from $OPTS->{input} ...";
		if($OPTS->{input} eq '-') {
			while(<STDIN>) {
				chomp;
				#p_msg "Add query: $_\n";
				next unless($_);
				push @queries,$_;
			}
			print STDERR "\t[OK]\n";
		}
		elsif(-f $OPTS->{input}) {
			if(open my $FINPUT,"<",$OPTS->{input}) {
				while(<$FINPUT>) {
					chomp;
					#p_msg "Add query: $_\n";
					next unless($_);
					push @queries,$_;
				}
				close $FINPUT;
				print STDERR "\t[OK]\n";
			}
			else {
				p_err "\n\tError reading $OPTS->{input}: $!\n";
				return $self->EXIT_CODE("ERROR");
			}
		}
		else {
			p_err "\n\tError, File not exsits: $OPTS->{input}\n";
			return $self->EXIT_CODE("ERROR");
		}
	}

	my @args;

	if($CMD eq 'MOVE') {
		my $dst = pop @_;
		@queries = @_;
		push @args,$dst if($dst);
	}
	elsif($CMD eq 'SED') {
		my @files = $self->dbfiles;
		return $self->CMD_SED(\@_,@files);
	}
#	print STDERR join(", ",@queries);
	my @target = $self->query(@queries);
	if(!@target) {
		p_msg "Nothing to do\n";
		return 1;
	}
	

	if($CMD eq 'LIST') {
		return $self->CMD_LIST(@target);
	}
	elsif($CMD eq 'DOWNLOAD') {
		return $self->CMD_DOWNLOAD(@target);
	}
	elsif($CMD eq 'DUMP') {
		return $self->CMD_DUMP(@target);
	}
	elsif($CMD eq 'MOVE') {
		return $self->CMD_MOVE($args[0],@target);
	}
	else{
		return $self->CMD_ACTION($cmd,@target);
	}
	return $EXIT;
}

return 1 if caller;
my $PROGRAM = new MyPlace::Program::URLRule;
my ($exitval) = $PROGRAM->execute(@ARGV);
exit $exitval;


1;


__END__

=pod

=head1  NAME

urlrule - PERL script

=head1  SYNOPSIS

urlrule [options] ...

=head1  OPTIONS

=over 12

=item B<--version>

Print version infomation.

=item B<-h>,B<--help>

Print a brief help message and exits.

=item B<--manual>,B<--man>

View application manual

=item B<--edit-me>

Invoke 'editor' against the source

=back

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2015-02-01 00:43  xiaoranzzz  <xiaoranzzz@MyPlace>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@MyPlace>

=cut

#       vim:filetype=perl
