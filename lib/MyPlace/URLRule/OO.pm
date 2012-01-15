package MyPlace::URLRule::OO;
use MyPlace::URLRule qw/parse_rule apply_rule @URLRULE_LIB/;
use strict;
use warnings;
use Cwd qw/getcwd/;
use MyPlace::Script::Message;

sub lib {
	my $self = shift;
	if(@_) {
		@URLRULE_LIB = @_;
	}
	else {
		return \@URLRULE_LIB;
	}
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
		s/^\./_/g;
		s/[\/\\\?\*]/_/g;
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
		@{$request}{qw/url level action title/} = @_;
	}
#	print STDERR (Data::Dumper->Dump([$request],['*request']));
	$request = {%{$self->{request}},%{$request}};
	$request->{action} = 'COMMAND:echo' unless($request->{action});
	my $rule = parse_rule(@{$request}{qw/url level action/});
#	$request->{title} = _safe_path($request->{title}) if($request->{title});
	#$rule->{title} = $request->{title};
	return ($rule,$request);
}

sub to_response {
	my ($self,$result,$rule) = @_;
	if($result) {
		my %response = %{$result};
		$response{success} = 1;
		$response{target} = $rule;
		$response{data} = [] unless($response{data});
		$response{count} = scalar(@{$response{data}});
		$response{action} = $rule->{action} unless($response{action});
		$response{title} = $response{work_dir} unless($response{title});
		delete $response{work_dir};
		if($self->{request}->{createdir} and $response{title}) {
			$response{title} = _safe_path($response{title});
		}
		unless(defined $response{level}) {
			$response{level} = $rule->{level} if($response{samelevel});
		}
		unless(defined $response{level}) {
			$response{level} = $rule->{level}  - 1;
		}
		if($response{pass_data} and @{$response{pass_data}}) {
			if(!$response{pass_count}) {
				$response{pass_count} = scalar(@{$response{pass_data}});
			}
			if($response{pass_name}) {
				my $idx = -1;
				if($self->{request}->{createdir}) {
					foreach(@{$response{pass_data}}) {
						$idx++;
						next if(ref $_);
						$response{pass_name}->[$idx] = _safe_path($response{pass_name}->[$idx]);
						$_ = {url=>$_,title=>$response{pass_name}->[$idx]};
					}
				}
				else {
					foreach(@{$response{pass_data}}) {
						$idx++;
						next if(ref $_);
						$_ = {url=>$_,title=>$response{pass_name}->[$idx]};
					}
				}
				delete $response{pass_name};
			}
			else {
				foreach(@{$response{pass_data}}) {
					$_ = {url=>$_};
				}
			}
			$response{next_level} = {
				count=>$response{pass_count},
				base=>$response{base},
				data=>$response{pass_data},
			#	name=>$response{pass_name},
				action=>$response{action},
				level=>$response{level}
			};
		}
#		$response{title} = _safe_path($response{title}) if($response{title});
		return \%response;
	}
	else {
		return undef;
	}
}

sub applyRule {
	my ($self,$rule,$request) = @_;
	my ($status,$result) = apply_rule($rule);
	if(!$status) {
		return $status,$result,$rule;
	}
	my $response = $self->to_response($result,$rule,$request);
	return $status,$response,$rule;
}

sub autoApply {
	my $self = shift;
	my ($rule,$res) = $self->request(@_);
	$self->{msghd} = "[Level $rule->{level}] ";
	$self->{response} = undef;
	$self->{callback_called} = undef;
	app_prompt($self->{msghd} . 'Rule',$rule->{source},"\n");
	if($self->{request}->{createdir} && $res->{title}) {
		if(! -d $res->{title}) {
			$self->makedir($res->{title}) or die("$!\n");
		}
		$self->changedir($res->{title},'autoApply request') or die("$!\n");
	}
	app_prompt($self->{msghd} . 'Retriving' , $rule->{url},"...\n");
	my ($status,$result) = $self->applyRule($rule,$res);
	my @responses;
	if($self->{callback_called}) {
		@responses = @{$self->{response}};
		$self->{callback_called} = undef;
		$self->{response} = undef;
	}
	elsif(!$status) {
		app_error($self->{msghd},$result,"\n");
		return $status;
	}
	elsif(!$result->{success}) {
		app_error($self->{msghd},"Rule not working for $res->{url}\n");
		next;
	}
	push @responses,$result if($status);
	my $cwd = getcwd;
	foreach my $response (@responses) {
		$self->process($response,$rule);
		if($response->{next_level}) {
			my %next = %{$response->{next_level}};
			app_prompt($self->{msghd} . 'NextLevel','Get ' . $next{count} . " items\n");# if($next{level});
			$self->{msghd} = "[Level $next{level}] ";
			if($response->{base} and $self->{request}->{buildurl}) {
				foreach(@{$next{data}}) {
					$_->{url} = URI->new_abs($_->{url},$response->{base})->as_string;
				}
			}
			my $cwd = getcwd;
			my $idx = 0;
			foreach my $req (@{$next{data}}) {
				$req = {
					level=>$next{level},
					action=>$next{action},
					%{$req}
				};
				$self->processNextLevel($req);
				$idx++;
				chdir($cwd);
			}
		}
		chdir($cwd);
		$self->{msghd} = "[Level $rule->{level}] ";
	}
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
	#return 1 if(-d $dir);
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
		my $wd = $response->{work_dir} || $response->{title};
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
    return undef,"No data" unless($data);
    if(ref $data eq 'SCALAR') {
		$data = [$data];
    }
	if(!@{$data}) {
		app_prompt($self->{msghd},colored("No data\n",'RED'));
		return undef, 'No data';
	}
    app_prompt($self->{msghd} . "In ",getcwd,"\n");
    my $file=$response->{file};
    $file =~ s/\s*\w*[\/\\]\w*\s*//g if($file);
	my $action = $response->{pipeto} || $response->{action} || '';
	{
		my $base = $response->{base} || $rule->{base} || $rule->{url};
		$action =~ s/#URLRULE_BASE#/$base/g;
		$action =~ s/#URLRULE_TITLE#/$response->{title}/g;
	}
    if($file) {
		app_prompt($self->{msghd} . 'Writes file',$file);
        if (-f $file) {
			print STDERR colored('RED',"Ingored (File exists)...\n");
			return undef;
        }
        else {
            open FO,">:utf8",$file or die("$!\n");
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
	elsif($action =~ m/^COMMAND:(.+)$/) {
		$action = $1;
		app_prompt($self->{msghd} . 'Action',"$action\n");
		foreach(@{$data}) {
			system("$action \"$_\"");
		}
	}
    elsif($action) {
		app_prompt($self->{msghd} . 'Action',"$action\n");
        my $childpid = open FO,"|-",$action;
#		print STDERR "Childpid:$childpid\n";
		if($childpid) {
			print FO "$_\n" foreach(@{$data});
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

