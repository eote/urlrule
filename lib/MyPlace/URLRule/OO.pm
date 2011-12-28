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
	$request = {%{$self->{request}},%{$request}};
	$request->{action} = 'COMMAND:echo' unless($request->{action});
	my $rule = parse_rule(@{$request}{qw/url level action/});
	$rule->{title} = $request->{title};
	return ($rule,$request);
}

sub to_response {
	my ($self,$result,$rule) = @_;
	my %response = %{$result};
	if($result) {
		$response{success} = 1;
		$response{target} = $rule;
		$response{data} = [] unless($response{data});
		$response{count} = scalar(@{$response{data}});
		$response{action} = $rule->{action} unless($response{action});
		$response{title} = $rule->{title} unless($response{title});
		unless(defined $response{level}) {
			$response{level} = $rule->{level} if($response{samelevel});
		}
		unless(defined $response{level}) {
			$response{level} = $rule->{level}  - 1;
		}
		if($response{pass_data}) {
			if(!$response{pass_count}) {
				$response{pass_count} = scalar(@{$response{pass_data}});
			}
			$response{next_level} = {
				count=>$response{pass_count},
				base=>$response{base},
				data=>$response{pass_data},
				name=>$response{pass_name},
				action=>$response{action},
				level=>$response{level}
			};
		}
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
	app_prompt($self->{msghd} . 'URL',$rule->{url},"\n");
	app_prompt($self->{msghd} . 'Rule',$rule->{source},"\n");
	my ($status,$result) = $self->applyRule($rule,$res);
	my @responses;
	#@{$res}{qw/title url level/});
	if(!$status) {
		app_error($self->{msghd},$result,"\n");
		return $status;
	}
	my $cwd = getcwd;
	if(!$result->{success}) {
		app_error($self->{msghd},"Rule not working for $res->{url}\n");
		next;
	}
	if($self->{callback_called}) {
		@responses = @{$self->{response}};
	}
	push @responses,$result;
#	if($self->{request}->{createdir} && $res->{title}) {
#		$self->makedir($res->{title}) or die("$!\n");
#		$self->changedir($res->{title}) or die("$!\n");
#	}
	foreach my $response (@responses) {
		my $cwd = getcwd;
		$self->process($response,$rule);
		if($response->{next_level}) {
			my %next = %{$response->{next_level}};
			app_prompt($self->{msghd} . 'NextLevel','Get ' . $next{count} . " items\n") if($next{count});
			my $idx = 0;
			$self->{msghd} = "[Level $next{level}] ";
			if($response->{base} and $self->{request}->{buildurl}) {
				map {$_ = URI->new_abs($_,$response->{base})->as_string} @{$next{data}};
			}
			foreach (@{$next{data}}) {
				my $cwd = getcwd;
				$self->processNextLevel({
					url=>$_,
					level=>$next{level},
					title=>	($next{name} ? $next{name}->[$idx] : undef),
					action=>$next{action}
				});
				chdir($cwd);
			}
		}
		chdir($cwd);
		$self->{msghd} = "[Level $rule->{level}] ";
	}
	chdir($cwd);
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
	app_prompt($self->{msghd} . 'Changes directory',$dir,"\n");
	chdir($dir);
}
sub makedir {
	my $self = shift;
	my $dir = shift;
	return 1 if(-d $dir);
	app_prompt($self->{msghd} . 'Creates directory',$dir,"\n");
	mkdir($dir);
}

sub callback_applyRule {
	my($from,$rule,$result,$self) = @_;
	my $response = $self->to_response($result,$rule);
	if($self->{request}->{callback_process}) {
		@_ = ($self,$response,$rule);
		goto &process;#$self->{request}->{callback_process};
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
		app_prompt($self->{msghd},"Get " . $response->{count} . " items\n");
		unshift @_,$self,$response,$rule;
		goto $self->{request}->{callback_process};
	}
	my $wd;
	if($self->{request}->{createdir}) {
		my $wd = $response->{work_dir} || $response->{title};
		if($wd) {
			$self->makedir($wd) or die("$!\n");
			$self->changedir($wd) or die("$!\n");
		}
	}
	app_prompt($self->{msghd},"Get " . $response->{count} . " items\n");
	if($response->{base} and $self->{request}->{buildurl}) {
		map {$_ = URI->new_abs($_,$response->{base})->as_string;} @{$response->{data}};
	}
	if($self->{request}->{callback_action}) {
		return $self->{request}->{callback_action}($self,$response->{data});
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
        open FO,"|-",$action;
		print FO "$_\n" foreach(@{$data});
		close FO;
    }
    else {
        print $_,"\n" foreach(@{$data});
    }
}

1;

__END__

