package MyPlace::URLRule::OO;
#our $VERSION = 'v2.0';

use MyPlace::URLRule qw/parse_rule apply_rule @URLRULE_LIB get_rule_handler/;
use strict;
use warnings;
use Cwd qw//;
use MyPlace::Script::Message;
use File::Basename;
use Pod::Usage;
use MyPlace::Program::Batchget;
use MyPlace::Program::Saveurl;
use File::Spec;
#use Encode qw/decode_utf8 encode_utf8 find_encoding/;
use utf8;
#my $UTF8 = find_encoding("utf-8");
my $PROGRAM_SAVE;

sub getcwd {
	goto &Cwd::cwd;
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
	my $l = length($full);
	if($l > 60) {
		my @dirs = File::Spec->splitdir($full);
		my @sdir;
		my $level = 3;
		while(@dirs) {
			last if($level < 1);
			my $d = pop @dirs;
			unshift @sdir,$d;
			$level--;
		}
		return File::Spec->catdir(@sdir);
	}
	else {
		return $full;
	}
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
	$self->{levels} = {};
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
	$self->{levels} = {};
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
		s/[\<\?*\:\"\|\>]+/_/;
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

sub progress {
	my $self = shift;
	my $text = "";
	foreach my $idx(reverse 0 .. 100) {
		if($self->{levels}->{"count" . $idx}) {

			$text  = $text . "[" . 
				($self->{levels}->{"done" . $idx}  || "0").
				"/" .
				$self->{levels}->{"count" . $idx} .
				"]";

		}
	}
	return $text;
}

sub apply{
	my $self = shift;
	my $request = shift;
	my $rule;
	($rule,$request) = $self->request($request,@_);
	$self->{levels}->{"count" . $rule->{level}} ||= 0;
	$self->{levels}->{"count" . $rule->{level}} += 1;
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
	elsif($handler->{error}) {
		return 0, {error=>$handler->{error}},$rule;
	}
	if($request->{options}) {
		$handler->{options} = $request->{options};
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
		if(!$self->make_change_dir($wd,'aa_apply_rule')) {
			return undef;
		}
	}
	app_prompt($self->{msghd} . 'URL' , $rule->{url},"\n");
    app_prompt($self->{msghd} . "Directory",short_wd(getcwd(),$self->{startwd}),"\n");
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
	my $DIR_KEEP = getcwd;
	my @DATAS;
	my ($rule,$res) = $self->request(@_);
	$self->{levels}->{"done" . $rule->{level}} ||= 0;
	$self->{levels}->{"done" . $rule->{level}} += 1;
	return 2 if($self->{outdated});
	$self->{msghd} = $self->progress . " L$rule->{level}>";
	$self->{response} = undef;
	$self->{callback_called} = undef;
	app_prompt($self->{msghd} . 'Rule',$rule->{source},"\n");
	if($self->{request}->{createdir} && $res->{title}) {
		my $wd = _safe_path($res->{title});
		if(!$self->make_change_dir($wd,'autoApply')) {
			return undef;
		}
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
		my(undef,@r) = $self->process($response,$rule);
		push @DATAS,@r if(@r);
		if($self->{outdated}) {
			chdir $DIR_KEEP;
			return 2;
		}
		if($response->{nextlevel}) {
			my %next = %{$response->{nextlevel}};
			app_prompt($self->{msghd} . 'NextLevel','Get ' . $next{count} . " items\n");# if($next{level});
			$self->{levels}->{"count" . $next{level}} ||= 0;
			$self->{levels}->{"count" . $next{level}} += $next{count};
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
#				$req->{progress} = ($res->{progress} || "");
#				$req->{progress} .= "[$idx/$count]" unless($count == 1);
				$idx--;
				push @requests,$req;
			}
			if($self->{request}->{callback_nextlevels}) {
				$self->{request}->{callback_nextlevels}(@requests);
				chdir $cwd;
			}
			else {
				foreach my $req (@requests) {
					my(undef,@r) = $self->processNextLevel($req);
					if($rule->{url} =~ m/weibo\.com/) {
						my $sec = 10;
						app_error(
							$self->{msghd},
							"Program will sleep for $sec seconds, avoiding blocked by weibo.com\n"
						);
						sleep $sec;
					}
					if(@r) {
						push @DATAS,@r;
					}
					if($self->{outdated}) {
						chdir $DIR_KEEP;
						return 2;
					}	
					chdir($cwd);
				}
			}
		}
#		$self->{msghd} = "[Level $rule->{level}] ";
	}
	chdir($DIR_KEEP);
	return 1,@DATAS;
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

sub make_change_dir {
	my $self = shift;
	my $wd = shift;
	my $caller = shift(@_) || '';
		if($wd) {
			unless(-d $wd or $self->makedir($wd)) {
				app_error($self->{msghd}, 
					"Error creating directory $wd:$!\n");
				return undef;
			}
			unless($self->changedir($wd,$caller)) {
				app_error($self->{msghd}, 
					"Error changing directory $wd:$!\n");
				return undef;
			}
		}
	return 1;
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
	my @DATAS;
	if($self->{request}->{callback_process}) {
		app_prompt($self->{msghd},"Get " . $response->{count} . " items\n") if($response->{count});
		unshift @_,$self,$response,$rule;
		goto $self->{request}->{callback_process};
	}
	my $wd;
	if($self->{request}->{createdir}) {
		my $wd = _safe_path($response->{title});
		if(!$self->make_change_dir($wd,'process')) {
			return undef,$response->{data} ? @{$response->{data}} : ();
		}
	}
	if(!$response->{count}) {
		app_prompt($self->{msghd}, "Nothing to process" . ($response->{title} ? " for [$response->{title}]\n" : "\n" ));
		return;
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
	return 1,@{$response->{data}};
}

sub NEW_SAVER {
	my $self = shift;
	my @SAVE_OPTS;
	foreach(qw/thread include exclude/) {
		next unless($self->{request}->{$_});
		push @SAVE_OPTS,"--" . $_,$self->{request}->{$_};
	}
	return MyPlace::Program::Saveurl->new(@SAVE_OPTS);
}

our @DOMAINS = (
	['v.weipai.cn','oldvideo.qiniudn.com'],
	['aliv3.weipai.cn', 'aliv.weipai.cn'],
);

sub DUP_URL {
	my $url = shift;
	my @r;
	my $lurl = $url;
	my $prefix;
	my $domain;
	my $suffix;
	if($lurl =~ m/^([a-z]+:\/\/)([^\/]+)(.*)$/) {
		$prefix = $1;
		$domain = lc($2);
		$suffix = $3;
	}
	else {
		return ($url);
	}
	foreach (@DOMAINS) {
		my $match = 0;
		foreach my $d(@$_) {
			if(lc($d) eq $domain) {
				$match = 1;
				last;
			}
		}
		if($match) {
			foreach my $d(@$_) {
				push @r, $prefix . $d . $suffix;
			}
			last;
		}
	}
	if(@r) {
		#	print STDERR "[DUPURL] $url =>\n";
		#print STDERR "\t" . join("\n\t",@r) . "\n";
		return @r;
	}	
	return ($url);
}
	sub write_database {
		my $self = shift;
		my $f_urls = shift;
		my $data = shift;
		my $count = 0;
		my $OUTDATE = 1;
		app_prompt($self->{msghd} . "Write data to database",$f_urls,"\n");
		my %records;
		if(-f $f_urls) {
			if(open FI,'<',$f_urls) {
				foreach(<FI>) {
					chomp;
					my @urls = DUP_URL($_);
					@records{(@urls)} = (1,1,1,1,1,1,1,1,1,1);
				}
				close FI;
				#use Data::Dumper;
				#print Data::Dumper->Dump([\%records],['*records']),"\n";
			}
			else {
				app_error($self->{msghd} . "Error reading $f_urls:$!\n");
				return undef;
			}
		}
		if(open FO,'>>',$f_urls) {
			foreach(@{$data}) {
				if($records{$_}) {
					if(m/weishi\.com|weishi_pic/) {
						$OUTDATE = 1;
						last;
					}
					next;
				}
				print FO $_,"\n";
				$OUTDATE = 0;
				$count++;
				print STDERR "    + [$count]$_\n";
			}
			close FO;
			app_warning($self->{msghd}, "$count lines wrote\n");
			return 1,$count,$OUTDATE;
		}
		else {
			app_error($self->{msghd}, "Error writting $f_urls!\n");
			return undef;
		}
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
	if($action =~ m/^\!(.+)$/) {
		$ACTION_MODE{FORCE} = 1;
		$action = $1;
	}
	else {
		$ACTION_MODE{FORCE} = $self->{request}->{force};
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
	$self->{DATAS_COUNT} = 0 unless(defined $self->{DATAS_COUNT});# ? $self->{DATAS_COUNT} + @$data : @$data;
	if($action eq 'DOWNLOAD') {
		my $f_urls='urls.lst';
		my ($status,$count,$OUTDATE) = $self->write_database($f_urls,$data);
		return $status unless($status);
		use MyPlace::Program::Downloader;
		$self->{DATAS_COUNT} += $count;
		if((!$ACTION_MODE{FORCE}) and $OUTDATE) {
			$self->outdated();
			return $count;
		}
		my $mpd = new MyPlace::Program::Downloader;
		$mpd->execute(
			'--title'=>$response->{title},
			'--no-queue',
			'--include'=>$self->{request}->{include},
			'--exclude'=>$self->{request}->{exclude},
			@$data,
		);
		return $count;
	}
	elsif($action eq 'DOWNLOADER') {
			my $f_urls='urls.lst';
			my ($status,$count,$OUTDATE) = $self->write_database($f_urls,$data);
			return $status unless($status);
			use MyPlace::Program::Downloader;
			my $mpd = new MyPlace::Program::Downloader;
			$mpd->execute(
				'--input'=>$f_urls,
				'--title'=>$response->{title},
				'--retry',
				'--include'=>$self->{request}->{include},
				'--exclude'=>$self->{request}->{exclude},
			);
			$self->{DATAS_COUNT} += $count;
			if((!$ACTION_MODE{FORCE}) and $OUTDATE) {
				$self->outdated();
			}
			return $count;
	}
	if($action eq 'DATABASE') {
		my $dbfile = $file || 'urls.lst';
		my ($status,$count,$OUTDATE) = $self->write_database($dbfile,$data);
		return $status unless($status);
		#app_prompt($self->{msghd} . "Write $count lines to",$dbfile,"\n");
		$self->{DATAS_COUNT} += $count;
		if((!$ACTION_MODE{FORCE}) and $OUTDATE) {
			$self->outdated();
		}
		return $count;
	}
    elsif($action eq 'FILE') {
		app_prompt($self->{msghd} . 'Writes file',$file,"\n");
		if (-f $file) {
			print STDERR colored('RED',"Ingored (File exists)...\n");
			return undef;
		}
		elsif(open FO,">",$file) {
            print FO @{$data};
            close FO;
			print STDERR "[OK]\n"	
		}
		else {
			app_error($self->{msghd}, 
					"Error opeing file $file:$!\n");
			return undef;
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
		$PROGRAM_SAVE ||= $self->NEW_SAVER;
		$PROGRAM_SAVE->setOptions('--history');
		$PROGRAM_SAVE->setOptions('--referer',$base) if($base);
		$PROGRAM_SAVE->addTask(@{$data});
		$PROGRAM_SAVE->execute();
	}
	elsif($action eq '!SAVE') {
		app_prompt($self->{msghd} . 'Action',"$action\n");
		$PROGRAM_SAVE ||= $self->NEW_SAVER;
		$PROGRAM_SAVE->setOptions('--referer',$base) if($base);
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
				if($link eq $rec) {
					if($link =~ m/weishi\.com|weishi_pic/) {
						$OUTDATE = 1;
						last;
					}
					next;
				}
				push @KEEPS,$_;
				$OUTDATE = 0;
			}
		}
		if(@KEEPS) {
			$PROGRAM_SAVE ||= $self->NEW_SAVER;
			$PROGRAM_SAVE->setOptions('--referer',$base) if($base);
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
	        if(open FO,"|-",$action) {
				print FO join("\n",@{$data}),"\n";
				close FO;
			}
			else {
				app_error($self->{msghd} . "Error process action <$action> : $!\n");
				return;
			}
    }
    else {
        print $_,"\n" foreach(@{$data});
    }
}

1;

__END__

=pod

=head1  NAME

MyPlace::URLRule::OO

=head1  SYNOPSIS
		
		use MyPlace::URLRule::OO;
		my $UOO = MyPlace::URLRule::OO->new(
			'createdir'=>0,
			'action'=>$action,
			'include'=>'\.jpg',
			'exclude'=>'',
			'thread'=>1,
		);
		foreach my $url(@urls) {
			$UOO->autoApply({
					count=>1,
					url=>$url,
					level=>$level,
			});
		}
		if($UOO->{DATAS_COUNT}) {
			print STDERR "OK\n";
		}
		else {
			print STDERR "Nothing to do\n";
		}

=head1  OPTIONS

=over 12

=item B<--include>

Config inclusive patterns for supported downloaders

=item B<--exclude>

Config exclusive patterns for supported downloaders

=item B<--thread>

Config numbers of threads for supported downloaders

=back

=head1  DESCRIPTION

Object orient class module for MyPlace::URLRule

=head1  CHANGELOG

2014-11-22 02:51  xiaoranzzz  <xiaoranzzz@MyPlace>
       
	* file created.

2015-04-20 01:09  xiaoranzzz <xiaoranzzz@MyPlace>
	
	* Add pod document
	* Tag as version 2.0

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@MyPlace>

=cut

#       vim:filetype=perl



