package MyPlace::URLRule::OO;
our $VERSION = 'v2.0';

use MyPlace::URLRule qw/parse_rule apply_rule @URLRULE_LIB get_rule_handler/;
 
use strict;
use warnings;
use Cwd qw//;
use MyPlace::Script::Message;
use File::Basename;
use MyPlace::Program::Saveurl;
#use Encode qw/decode_utf8 encode_utf8 find_encoding/;
use utf8;
#my $UTF8 = find_encoding("utf-8");
my $PROGRAM_SAVE;

sub getcwd {
	goto &Cwd::getcwd;
	#return $UTF8->decode(Cwd::getcwd());
}

sub lib {
	my $self = shift;
	if(@_) {
		@URLRULE_LIB = @_;
	}
	else {
		return \@URLRULE_LIB;
	}
}

sub short_wd {
	my $full = shift;
	my $base = shift;
	$base =~ s/[^\/]+$//;
	if($base) {
		return substr($full,length($base));
	}
	else {
		return $full;
	}
}

sub reset {
	my $self = shift;
	foreach (qw/msghd response outdated callback_called exitval/){;
		delete $self->{$_};
	}
	return $self;
}

sub new {
	my $class = shift;
	my %res = @_;
	my $self = {};
	$self->{request} = {
			buildurl=>1,
			createdir=>1,
			%res
		};
	if($self->{request}->{buildurl}) {
		require URI;
	}
	$self->{startwd} = getcwd();
	$self = bless $self,$class;
	MyPlace::URLRule::set_callback(
		'apply_rule',
		\&callback_applyRule,
		$self
	);
	return $self;
}

sub _safe_path {
	foreach(@_) {
		next unless($_);
		s/^\.+//g;
		s/:/ - /g;
		#s/[\/\\\?\*]/_/g;
		s/^\s+|[\.\s]+$|(?<=\/)\s+|[\.\s]+(?=\/)//g;
		s/\s+/ /g;
	}
	if(wantarray) {
		return @_;
	}
	else {
		return $_[0] if($_[0]);
	}
}

sub apply{
	my $self = shift;
	my $request = shift;
	my $rule;
	($rule,$request) = $self->request($request,@_);
	return $self->applyRule($rule,$request);
}

sub request {
	my $self = shift;
	my $request = shift;
	if(!ref $request) {
		unshift @_,$request;
		$request = {};
		@{$request}{qw/url level action title progress/} = @_;
	}
	$request = {%{$self->{request}},%{$request}};
	$request->{action} = 'COMMAND:echo' unless($request->{action});
	my $rule = parse_rule(@{$request}{qw/url level action/});
	#print STDERR (Data::Dumper->Dump([$rule,$request],[qw/*rule *request/]));
	return ($rule,$request);
}


sub applyRule {
	my ($self,$rule,$request) = @_;
	my $handler = get_rule_handler($rule);
	if(!$handler) {
		return 0,{error=>"No handler found for $rule->{url}"},$rule;
	}
	if($self->{request}->{BeforeApplyRule}) {
		$self->{request}->{BeforeApplyRule}($rule,$request,$handler);
	}
	my ($status,$result) = $handler->apply($request->{url},$request->{level},$request->{action});
	if($self->{request}->{AfterApplyRule}) {
		($status,$result) = $self->{request}->{AfterApplyRule}($status,$result,$rule,$request,$handler);
	}
	return $status,$result,$rule;
}

sub outdated {
	my $self = shift;
	$self->{outdated} = 1;
	app_warning($self->{msghd} . 'STOP HERE DATA IS OUTDATED',"\n");
	return;
}

sub aa_apply_rule {
	my $self = shift;
	my ($rule,$res) = $self->request(@_);
	$self->{msghd} = ($res->{progress} || '') . "[L$rule->{level}] ";
	$self->{response} = undef;
	$self->{callback_called} = undef;
	app_prompt($self->{msghd} . 'Rule',$rule->{source},"\n");
	if($self->{request}->{createdir} && $res->{title}) {
		my $wd = _safe_path($res->{title});
		if(! -d $wd) {
			$self->makedir($wd) or die("$!\n");
		}
		$self->changedir($wd,'autoApply request') or die("$!\n");
	}
	app_prompt($self->{msghd} . 'URL' , $rule->{url},"\n");
    app_prompt($self->{msghd} . "Directory",short_wd(getcwd,$self->{startwd}),"\n");
	my ($status,$result) = $self->applyRule($rule,$res);
	if(!$status) {
		if($result->{error}) {
			app_error($self->{msghd},"Error: $result->{error}","\n");
		}
		elsif($result->{message}) {
			app_message($self->{msghd},$result->{message},"\n");
		}
		else {
			app_error($self->{msghd},"Unknown error accoure\n");
		}
		return $status;
	}
	elsif($result->{failed}) {
		app_error($self->{msghd},"Rule not working for $res->{url}\n");
		return undef;
	}
	else {
		return $rule,$res,$result;
	}
}

sub aa_process_result {
	my $self = shift;
	my ($rule,$res,$response) = @_;
	$self->process($response,$rule);
	return 0;
}

sub aa_process_nextlevel {
	my $self = shift;
	my ($rule,$res,$response) = @_;
	return 1 unless($response->{nextlevel});
	my %next = %{$response->{nextlevel}};
	app_prompt($self->{msghd} . 'NextLevel','Get ' . $next{count} . " items\n");# if($next{level});
	$self->{msghd} = "[Level $next{level}] ";
	if($response->{base} and $self->{request}->{buildurl}) {
		foreach(@{$next{data}}) {
			#print STDERR $_,"\n";
			next if(m/^(https?|ftp|magnet|qvod|bdhd|thunder|ed2k|data):/);
			if(m/^(.+)\s*\t\s*([^\t]+)$/) {
				$_ = URI->new_abs($1,$response->{base})->as_string . "\t$2"
			}
			else {
				$_ = URI->new_abs($_,$response->{base})->as_string;
			}	
		}
	}
	my $count = $next{count};
	my $idx = $count;
	my @requests;
	foreach my $link (@{$next{data}}) {
		my $linkname = undef;
		if($link =~ m/^(.+)\s*\t\s*([^\t]+)$/) {
			$link = $1;
			$linkname = $2;
		}
		my $req = {
			level=>$next{level},
			action=>$next{action},
			progress=>($res->{progress} || "") . "[$idx/$count]",
			url=>$link,
			title=>$linkname,
		};
		$idx--;
		push @requests,$req;
	}
	return $rule,$res,$response,@requests;
}

sub autoApply2 {
	my $self = shift;
	return 2 if($self->{outdated});
	my $DIR_KEEP = getcwd;
	my ($rule,$res,$result) = $self->aa_get_response(@_);
	if(!($rule and $result)) {
		chdir $DIR_KEEP;
		return 3;
	}
	my @data = $self->aa_process_result($rule,$res,$result);
	$self->aa_process_data($rule,$res,$result,@data);
	if($self->{outdated}) {
		chdir $DIR_KEEP;
		return 2;
	}
	my $DIR_NOW = getcwd;
	my @requests = $self->aa_process_nextlevel($rule,$res,$result);
	foreach(@requests) {
		$self->aa_process_request($_);
		if($self->{outdated}) {
			chdir $DIR_KEEP;
			return 2;
		}	
		chdir($DIR_NOW);
	}
	chdir $DIR_KEEP;
	return 0;
}


sub autoApply {
	my $self = shift;
	return 2 if($self->{outdated});
	my $DIR_KEEP = getcwd;
	my ($rule,$res) = $self->request(@_);
	$self->{msghd} = ($res->{progress} || '') . "[L$rule->{level}] ";
	$self->{response} = undef;
	$self->{callback_called} = undef;
	app_prompt($self->{msghd} . 'Rule',$rule->{source},"\n");
	if($self->{request}->{createdir} && $res->{title}) {
		my $wd = _safe_path($res->{title});
		if(! -d $wd) {
			$self->makedir($wd) or die("$!\n");
		}
		$self->changedir($wd,'autoApply request') or die("$!\n");
	}
	app_prompt($self->{msghd} . 'URL' , $rule->{url},"\n");
    app_prompt($self->{msghd} . "Directory",short_wd($DIR_KEEP,$self->{startwd}),"\n");
	my ($status,$result) = $self->applyRule($rule,$res);
	my @responses;
	if($self->{callback_called}) {
		@responses = @{$self->{response}};
		$self->{callback_called} = undef;
		$self->{response} = undef;
	}
	elsif(!$status) {
		if($result->{error}) {
			app_error($self->{msghd},"Error: $result->{error}","\n");
		}
		elsif($result->{message}) {
			app_message($self->{msghd},$result->{message},"\n");
		}
		else {
			app_error($self->{msghd},"Unknown error accoure\n");
		}
		chdir($DIR_KEEP);
		return $status;
	}
	elsif($result->{failed}) {
		app_error($self->{msghd},"Rule not working for $res->{url}\n");
		chdir($DIR_KEEP);
		return undef;
	}
	push @responses,$result if($status);
	foreach my $response (@responses) {
		#if($response->{track_this}) {
		#	die("Track this: \n\t" . join("\n\t",@{$response->{pass_data}},@{$response->{data}}),"\n")
		#}
		$self->process($response,$rule);
		if($self->{outdated}) {
			chdir $DIR_KEEP;
			return 2;
		}
		if($response->{nextlevel}) {
			my %next = %{$response->{nextlevel}};
			app_prompt($self->{msghd} . 'NextLevel','Get ' . $next{count} . " items\n");# if($next{level});
			#if($response->{track_this}) {
			#	die("Track this: \n\t" . join("\n\t",@{$response->{pass_data}},@{$response->{data}}),"\n")
			#}
			$self->{msghd} = "[Level $next{level}] ";
			if($response->{base} and $self->{request}->{buildurl}) {
				foreach(@{$next{data}}) {
					#print STDERR $_,"\n";
					next if(m/^(https?|ftp|magnet|qvod|bdhd|thunder|ed2k|data):/);
					if(m/^(.+)\s*\t\s*([^\t]+)$/) {
						$_ = URI->new_abs($1,$response->{base})->as_string . "\t$2"
					}
					else {
						$_ = URI->new_abs($_,$response->{base})->as_string;
					}	
				}
			}
			my $cwd = getcwd;
			my $count = $next{count};
			my $idx = $count;
			my @requests;
			foreach my $link (@{$next{data}}) {
				my $linkname = undef;
				if($link =~ m/^(.+)\s*\t\s*([^\t]+)$/) {
					$link = $1;
					$linkname = $2;
				}
				my $req = {
					level=>$next{level},
					action=>$next{action},
					url=>$link,
					title=>$linkname,
				};
				$req->{progress} = ($res->{progress} || "");
				$req->{progress} .= "[$idx/$count]" unless($count == 1);
				$idx--;
				push @requests,$req;
			}
			if($self->{request}->{callback_nextlevels}) {
				$self->{request}->{callback_nextlevels}(@requests);
				chdir $cwd;
			}
			else {
				foreach my $req (@requests) {
					$self->processNextLevel($req);
					if($self->{outdated}) {
						chdir $DIR_KEEP;
						return 2;
					}	
					chdir($cwd);
				}
			}
		}
		$self->{msghd} = "[Level $rule->{level}] ";
	}
	chdir($DIR_KEEP);
	return 1;
}
sub processNextLevel {
	my $self = shift;
	my $req = shift;
	if($self->{request}->{callback_nextlevel}) {
		unshift @_,$req;
		goto $self->{request}->{callback_nextlevel};
	}
	else {
		return $self->autoApply($req);
	}
}
sub changedir {
	my $self = shift;
	my $dir = shift;
	#my $msg = shift(@_) || "";
	#$msg = "($msg)" if($msg);
	#app_prompt($self->{msghd} . "$msg" . "Changes directory","$dir\n");
	app_prompt($self->{msghd} . "Changes directory","$dir\n");
	chdir($dir);
}
sub makedir {
	my $self = shift;
	my $dir = shift;
	#print STDERR "DIR:$dir\n";
	my $pdir = dirname($dir);
	#print STDERR "PDIR:$pdir\n";
	if($pdir and (! -d $pdir)) {
		$self->makedir($pdir);
	}
	return if(-d $dir);
	app_prompt($self->{msghd} . 'Creates directory',$dir,"\n");
	mkdir($dir);
}

sub callback_applyRule {
	my($from,$rule,$result,$self) = @_;
	my $response = $self->to_response($result,$rule);
	#app_prompt($self->{msghd} . 'applyRule callback',$from,"\n\n");
	if($self->{request}->{process_callback_applyrule} || $self->{request}->{callback_process}) {
		my $cwd = getcwd;
		@_ = ($self,$response,$rule);
		$self->process($response,$rule);
		chdir($cwd);
	}
	else {
		push @{$self->{response}},$response;
		$self->{callback_called} = 1;
	}
}

sub process {
	my $self = shift;
	my $response = shift;
	my $rule = shift;
	if($self->{request}->{callback_process}) {
		app_prompt($self->{msghd},"Get " . $response->{count} . " items\n") if($response->{count});
		unshift @_,$self,$response,$rule;
		goto $self->{request}->{callback_process};
	}
	my $wd;
	if($self->{request}->{createdir}) {
		my $wd = _safe_path($response->{title});
		if($wd) {
			if(! -d $wd) {
				$self->makedir($wd) or die("$!\n");
			}
			$self->changedir($wd,'process') or die("$!\n");
		}
	}
	if(!$response->{count}) {
		app_prompt($self->{msghd}, "Nothing to process" . ($response->{title} ? " for [$response->{title}]\n" : "\n" ));
		return $response->{data};
	}
	app_prompt($self->{msghd},"Get " . $response->{count} . " items\n") if($response->{count});
	return unless($response->{count}>0);
	if($response->{base} and $self->{request}->{buildurl}) {
		foreach(@{$response->{data}}) {
			next if(m/^(https?|ftp|magnet|qvod|bdhd|thunder|ed2k|data):/);
			if($_ =~ m/^([^\t]+)\t+(.+)$/) {
				$_ = URI->new_abs($1,$response->{base})->as_string() . "\t$2";
			}
			else {
				$_ = URI->new_abs($_,$response->{base})->as_string; 
			}
		}
	}
	if($self->{request}->{callback_action}) {
		return $self->{request}->{callback_action}($self,$response->{data},$response,$rule);
	}
	$self->do_action($response->{data},$response,$rule);
	return $response->{data};
}

sub do_action {
	my $self = shift;
	my $data = shift;
	my $response = shift;
	my $rule = shift;

	$self->{exitval} = 1;
    return undef,"No data" unless($data);
    if(ref $data eq 'SCALAR') {
		$data = [$data];
    }
	if(!@{$data}) {
		app_prompt($self->{msghd},colored("No data\n",'RED'));
		return undef, 'No data';
	}
	#app_prompt($self->{msghd} . "Directory",short_wd(getcwd,$self->{startwd}),"\n");
	my $base = $response->{base} || $rule->{base} || $rule->{url};
    my $file=$response->{file};
	my $action = $response->{pipeto} || $response->{action} || '';

	my %ACTION_MODE;
	if($action =~ m/^!(.+)$/) {
		$ACTION_MODE{FORCE} = 1;
		$action = $1;
	}
    if($file) {
		$file =~ s/\s*\w*[\/\\]\w*\s*//g if($file);
		$action = 'FILE';
	}
	elsif(lc($action) =~ m/^file:(.+)$/) {
		$file = $1;
		$action = 'FILE';
	}
	elsif(lc($action) =~ m/^(?:db|database):(.+)$/) {
		$file = $1;
		$action = 'DATABASE';
	}
	#print Data::Dumper->Dump([$response],qw/*response/);
	{
		$action =~ s/#URLRULE_BASE#/$base/g;
		$action =~ s/#URLRULE_TITLE#/$response->{title}/g;
	}
	$self->{DATAS_COUNT} = $self->{DATAS_COUNT} ? $self->{DATAS_COUNT} + @$data : @$data;
	if($action eq 'DOWNLOADER') {
		my $f_urls='urls.lst';
		app_prompt($self->{msghd} . "Write data to database",$f_urls,"\n");
		my %records;
		if(-f $f_urls) {
			if(open FI,'<',$f_urls) {
				foreach(<FI>) {
					chomp;
					$records{$_} = 1;
				}
				close FI;
			}
			else {
				app_error($self->{msghd} . "Error reading $f_urls:$!\n");
				return undef;
			}
		}
		my $count = 0;
		my $OUTDATE = 1;
		if(open FO,'>>',$f_urls) {
			foreach(@{$data}) {
				next if($records{$_});
				print FO $_,"\n";
				$OUTDATE = 0;
				$count++;
			}
			close FO;
			app_prompt($self->{msghd}, "$count lines wrote\n");
			use MyPlace::Program::Downloader;
			my $mpd = new MyPlace::Program::Downloader;
			$mpd->execute(
				'--input'=>$f_urls,
				'--title'=>$response->{title},
				'--retry',
			);
			$self->{DATAS_COUNT} = $count;
			$self->outdated() if($OUTDATE);
			return $count;
		}
		else {
			app_error($self->{msghd} . "Error writing $f_urls:$!\n");
			return undef;
		}
	}
	if($action eq 'DATABASE') {
		my $dbfile = $file || 'urls.lst';
		app_prompt($self->{msghd} . "Write data to database",$dbfile,"\n");
		my %records;
		if(-f $dbfile) {
			if(open FI,'<',$dbfile) {
				foreach(<FI>) {
					chomp;
					$records{$_} = 1;
				}
				close FI;
			}
			else {
				app_error($self->{msghd} . "Error reading $dbfile:$!\n");
				return undef;
			}
		}
		my $count = 0;
		my $OUTDATE = 1;
		my $idx = 0;
		if(open FO,'>>',$dbfile) {
			foreach(@{$data}) {
				if($records{$_}) {
					next;
				}
				$idx++;
				print STDERR "[$idx] $_\n";
				print FO $_,"\n";
				$OUTDATE = 0;
				$count++;
			}
			close FO;
			app_prompt($self->{msghd} . "Write $count lines to",$dbfile,"\n");
			$self->{DATAS_COUNT} = $count;
			#$self->{DATAS_COUNT} - @$data + @KEEPS;
			if((!$ACTION_MODE{FORCE}) and $OUTDATE) {
				$self->outdated();
			}
			return $count;
		}
		else {
			app_error($self->{msghd} . "Error writing $dbfile:$!\n");
			return undef;
		}
	}
    elsif($action eq 'FILE') {
		app_prompt($self->{msghd} . 'Writes file',$file,"\n");
		if (-f $file) {
			print STDERR colored('RED',"Ingored (File exists)...\n");
			return undef;
		}
		else {
            open FO,">",$file or die("$!\n");
            print FO @{$data};
            close FO;
			print STDERR "[OK]\n"	
		}
    }
    elsif($response->{hook}) {
		my $name = $response->{hook}->[0];
		my $func = $response->{hook}->[1];
		app_prompt($self->{msghd} . "Hook","$name\n");
		&$func($_,$response,$rule) foreach(@{$data});
    }
    elsif($action eq 'DUMP') {
        use Data::Dumper;
        local $Data::Dumper::Purity = 1; 
#		app_message("Dump result\n");
        print Data::Dumper->Dump([$response],qw/*response/);
    }
	elsif($action =~ m/^COMMAND:\s*(.+?)\s*$/) {
		$action = $1;
		app_prompt($self->{msghd} . 'Action',"$action\n");
		foreach(@{$data}) {
			system("$action \"$_\"");
		}
	}
	elsif($action eq 'SAVE') {
		app_prompt($self->{msghd} . 'Action',"$action\n");
		if(!$PROGRAM_SAVE) {
			$PROGRAM_SAVE = new MyPlace::Program::Saveurl;
			$PROGRAM_SAVE->setOptions("--history","--referer",$base) if($base);
			$PROGRAM_SAVE->setOptions("--thread",$self->{request}{thread}) if($self->{request}{thread});
		}
		$PROGRAM_SAVE->addTask(@{$data});
		$PROGRAM_SAVE->execute();
	}
	elsif($action eq '!SAVE') {
		app_prompt($self->{msghd} . 'Action',"$action\n");
		if(!$PROGRAM_SAVE) {
			$PROGRAM_SAVE = new MyPlace::Program::Saveurl;
			$PROGRAM_SAVE->setOptions("--referer",$base) if($base);
			$PROGRAM_SAVE->setOptions("--thread",$self->{request}{thread}) if($self->{request}{thread});
		}
		$PROGRAM_SAVE->addTask(@{$data});
		$PROGRAM_SAVE->execute();
	}
	elsif($action eq 'UPDATE') {
		app_prompt($self->{msghd} . 'Action',"$action\n");
		my $OUTDATE = 1;
		my @RECORDS;
		if(open FI, '<',"URLS.txt") {
			foreach(<FI>) {
				chomp;
				s/\t.+$//;
				push @RECORDS,$_;
			}
			close FI;
		}
		my @KEEPS;
		foreach(@{$data}) {
			my $link = $_;
			$link =~ s/\t.+$//;
			foreach my $rec(@RECORDS) {
				next if($link eq $rec);
				push @KEEPS,$_;
				$OUTDATE = 0;
			}
		}
		if(@KEEPS) {
			if(!$PROGRAM_SAVE) {
				$PROGRAM_SAVE = new MyPlace::Program::Saveurl;
				$PROGRAM_SAVE->setOptions("--referer",$base) if($base);
				$PROGRAM_SAVE->setOptions("--thread",$self->{request}{thread}) if($self->{request}{thread});
			}
			$PROGRAM_SAVE->addTask(@KEEPS);
			$PROGRAM_SAVE->execute();
			if(open FO,">>","URLS.txt") {
				print FO join("\n",@KEEPS),"\n";
				close FO;
			}
		}
		$self->{DATAS_COUNT} = $self->{DATAS_COUNT} - @$data + @KEEPS;
		$self->outdated() if($OUTDATE);
	}
    elsif($action) {
		app_prompt($self->{msghd} . 'Action',"$action\n");
        my $childpid = open FO,"|-",$action;
#		print STDERR "Childpid:$childpid\n";
		if($childpid) {
			print FO join("\n",@{$data}),"\n";
			close FO;
			waitpid($childpid,0);
		}
		else {
			exit 0;
		}
    }
    else {
        print $_,"\n" foreach(@{$data});
    }
}

1;

__END__

